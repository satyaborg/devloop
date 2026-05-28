import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CLAUDE_EFFORT_ARGS, CODEX_REASONING_ARGS } from "./agent-options.ts";

export type GenerateSpecOptions = {
  agent: string;
  context: string[];
  cwd: string;
  force: boolean;
  output?: string;
  today?: string;
};

export type SpecCommand =
  | { type: "generate"; options: GenerateSpecOptions }
  | { type: "print-skill" }
  | { type: "skill-path" };

export type AgentResult = {
  code: number;
  stdout: string;
  stderr: string;
  output: string;
};

export type AgentRunner = (
  cmd: string,
  args: string[],
  input: string,
  cwd: string,
) => Promise<AgentResult>;

export type GeneratedSpec = {
  agent: string;
  command: string[];
  file: string;
};

export function parseSpecArgs(
  argv: string[],
  cwd = process.cwd(),
): SpecCommand | string {
  let agent = "codex";
  let force = false;
  let output = "";
  let action: "print-skill" | "skill-path" | "" = "";
  const context: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === "--agent") {
      const value = argv[++i];
      if (!value) return `--agent requires a value\n${specUsage()}`;
      agent = value;
    } else if (arg === "--output" || arg === "-o") {
      const value = argv[++i];
      if (!value) return `--output requires a value\n${specUsage()}`;
      output = value;
    } else if (arg === "--force") force = true;
    else if (arg === "--print-skill") action = "print-skill";
    else if (arg === "--skill-path") action = "skill-path";
    else if (arg === "-h" || arg === "--help") return specUsage();
    else if (arg.startsWith("--")) return `unknown option: ${arg}\n${specUsage()}`;
    else context.push(arg);
  }

  if (action) return { type: action };
  return {
    type: "generate",
    options: {
      agent,
      context,
      cwd,
      force,
      output: output || undefined,
    },
  };
}

export function specUsage() {
  return [
    "usage: devloop spec [--agent codex|claude|<cmd>] [--output spec.md] [--force] [context...]",
    "       devloop spec --print-skill",
    "       devloop spec --skill-path",
    "",
    "Without context, the bundled skill uses its interview path before writing a spec.",
  ].join("\n");
}

export function bundledSpecSkillPath() {
  return path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
    "skills",
    "spec",
    "SKILL.md",
  );
}

export async function readBundledSpecSkill() {
  return readFile(bundledSpecSkillPath(), "utf8");
}

export async function generateSpec(
  options: GenerateSpecOptions,
  runner: AgentRunner = runAgent,
): Promise<GeneratedSpec> {
  const skill = await readBundledSpecSkill();
  const context = await resolveContext(options.context, options.cwd);
  const today = options.today ?? new Date().toISOString().slice(0, 10);
  const invocation = agentInvocation(options.agent, options.cwd);
  const result = await runner(
    invocation.cmd,
    invocation.args,
    specPrompt({
      context,
      output: options.output,
      skill,
      today,
    }),
    options.cwd,
  );
  if (result.code !== 0)
    throw new Error(result.stderr.trim() || result.stdout.trim() || "spec agent failed");
  const markdown = extractGeneratedSpec(result.stdout || result.output);
  const file = await generatedSpecPath({
    cwd: options.cwd,
    force: options.force,
    markdown,
    output: options.output,
    today,
  });
  await mkdir(path.dirname(file), { recursive: true });
  if ((await stat(file).catch(() => false)) && !options.force)
    throw new Error(`spec already exists: ${file}`);
  await writeFile(file, markdown.endsWith("\n") ? markdown : `${markdown}\n`);
  return { agent: options.agent, command: [invocation.cmd, ...invocation.args], file };
}

export function agentInvocation(agent: string, cwd: string) {
  if (agent === "codex")
    return {
      cmd: "codex",
      args: ["exec", ...CODEX_REASONING_ARGS, "-s", "read-only", "-C", cwd, "-"],
    };
  if (agent === "claude")
    return {
      cmd: "claude",
      args: ["-p", ...CLAUDE_EFFORT_ARGS, "--add-dir", cwd],
    };
  return { cmd: agent, args: [] };
}

export function specPrompt(input: {
  context: string;
  output?: string;
  skill: string;
  today: string;
}) {
  return `Use this bundled devloop skill to produce one implementation spec.

Current date: ${input.today}
${input.output ? `Output path: ${input.output}` : "Output path: choose a .specs/YYYY-MM-DD-<slug>.md path if you write a file; otherwise return markdown on stdout."}

If the source context is missing or too thin, follow the skill's interview path before drafting. Return only the final markdown spec. Do not wrap it in a code fence.

Bundled skill:
${input.skill}

Context:
${input.context}`;
}

export function extractGeneratedSpec(output: string) {
  const trimmed = output.trim();
  const fenced = trimmed.match(/^```(?:markdown|md)?\s*\n([\s\S]*?)\n```$/i);
  const candidate = (fenced?.[1] ?? trimmed).trim();
  const start = candidate.indexOf("---");
  if (start < 0) throw new Error("agent output must include spec frontmatter");
  return candidate.slice(start).trim();
}

async function resolveContext(items: string[], cwd: string) {
  if (items.length === 0)
    return "No source material was provided. Use the cold-start interview path in the bundled skill to discover intent before writing the spec.";
  const resolved = await Promise.all(items.map((item) => contextBlock(item, cwd)));
  return resolved.join("\n\n---\n\n");
}

async function contextBlock(item: string, cwd: string) {
  const file = path.resolve(cwd, item);
  const info = await stat(file).catch(() => undefined);
  if (info?.isFile()) return `Source file: ${file}\n\n${await readFile(file, "utf8")}`;
  return `Context:\n${item}`;
}

async function generatedSpecPath(input: {
  cwd: string;
  force: boolean;
  markdown: string;
  output?: string;
  today: string;
}) {
  if (input.output) return path.resolve(input.cwd, input.output);
  const title = input.markdown.match(/^#\s+(.+)$/m)?.[1] ?? "spec";
  const slug = slugify(title) || "spec";
  const file = path.join(input.cwd, ".specs", `${input.today}-${slug}.md`);
  return input.force ? file : nextAvailablePath(file);
}

async function nextAvailablePath(file: string) {
  const extension = path.extname(file);
  const base = file.slice(0, -extension.length);
  let index = 2;
  let candidate = file;
  while (await stat(candidate).catch(() => false)) {
    candidate = `${base}-${index}${extension}`;
    index++;
  }
  return candidate;
}

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/'/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

async function runAgent(
  cmd: string,
  args: string[],
  input: string,
  cwd: string,
): Promise<AgentResult> {
  const proc = Bun.spawn([cmd, ...args], {
    cwd,
    env: Bun.env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(input);
  proc.stdin.end();
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { code, stdout, stderr, output: `${stdout}${stderr}` };
}
