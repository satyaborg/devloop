import { afterAll, describe, expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  agentInvocation,
  bundledSpecSkillPath,
  extractGeneratedSpec,
  generateSpec,
  parseSpecArgs,
  readBundledSpecSkill,
  specPrompt,
  specUsage,
  type AgentRunner,
  type GenerateSpecOptions,
} from "../src/spec.ts";

const root = await mkdtemp(path.join(tmpdir(), "devloop-spec-test."));

afterAll(async () => rm(root, { recursive: true, force: true }));

describe("spec command parsing", () => {
  test("parses generation options and utility actions", () => {
    expect(parseSpecArgs(["--agent", "claude", "--output", ".specs/x.md", "--force", "notes"], "/repo")).toEqual({
      type: "generate",
      options: {
        agent: "claude",
        context: ["notes"],
        cwd: "/repo",
        force: true,
        output: ".specs/x.md",
      },
    });
    expect(parseSpecArgs(["--print-skill"], "/repo")).toEqual({ type: "print-skill" });
    expect(parseSpecArgs(["--skill-path"], "/repo")).toEqual({ type: "skill-path" });
    expect(parseSpecArgs(["--agent"], "/repo")).toContain("--agent requires a value");
    expect(parseSpecArgs(["-o"], "/repo")).toContain("--output requires a value");
    expect(parseSpecArgs(["--wat"], "/repo")).toContain("unknown option");
    expect(parseSpecArgs(["--help"], "/repo")).toBe(specUsage());
    expect(parseSpecArgs([], "/repo")).toBe(specUsage());
  });

  test("exposes the bundled skill", async () => {
    expect(bundledSpecSkillPath()).toEndWith(path.join("skills", "spec", "SKILL.md"));
    expect(await readBundledSpecSkill()).toContain("name: spec");
  });
});

describe("spec prompt helpers", () => {
  test("builds agent-specific invocations", () => {
    expect(agentInvocation("codex", "/repo")).toEqual({ cmd: "codex", args: ["exec", "-s", "read-only", "-C", "/repo", "-"] });
    expect(agentInvocation("claude", "/repo")).toEqual({ cmd: "claude", args: ["-p", "--add-dir", "/repo"] });
    expect(agentInvocation("my-agent", "/repo")).toEqual({ cmd: "my-agent", args: [] });
  });

  test("builds prompts and extracts markdown specs", () => {
    expect(specPrompt({ context: "notes", output: ".specs/x.md", skill: "skill body", today: "2026-05-28" })).toContain("Output path: .specs/x.md");
    expect(specPrompt({ context: "notes", skill: "skill body", today: "2026-05-28" })).toContain("choose a .specs/YYYY-MM-DD-<slug>.md path");
    expect(extractGeneratedSpec("```markdown\n---\nstatus: draft\n---\n\n# Chat retries\n```")).toBe("---\nstatus: draft\n---\n\n# Chat retries");
    expect(extractGeneratedSpec("preface\n---\nstatus: draft\n---\n\n# Chat retries")).toBe("---\nstatus: draft\n---\n\n# Chat retries");
    expect(() => extractGeneratedSpec("no spec here")).toThrow("agent output must include spec frontmatter");
  });
});

describe("spec generation", () => {
  test("generates with codex, file context, and requested output", async () => {
    const cwd = await fixture("codex-output");
    await writeFile(path.join(cwd, "notes.md"), "Retry failed chat sends.\n");
    const calls: Array<{ cmd: string; args: string[]; input: string; cwd: string }> = [];
    const runner: AgentRunner = async (cmd, args, input, runCwd) => {
      calls.push({ cmd, args, input, cwd: runCwd });
      return { code: 0, stdout: specMarkdown("Chat retries"), stderr: "", output: specMarkdown("Chat retries") };
    };

    const result = await generateSpec(baseOptions(cwd, { context: ["notes.md", "Keep the existing CLI shape."], output: ".specs/chat-retry.md" }), runner);

    expect(result).toEqual({
      agent: "codex",
      command: ["codex", "exec", "-s", "read-only", "-C", cwd, "-"],
      file: path.join(cwd, ".specs/chat-retry.md"),
    });
    expect(calls[0]).toMatchObject({ cmd: "codex", args: ["exec", "-s", "read-only", "-C", cwd, "-"], cwd });
    expect(calls[0]!.input).toContain("Source file:");
    expect(calls[0]!.input).toContain("Retry failed chat sends.");
    expect(calls[0]!.input).toContain("Context:\nKeep the existing CLI shape.");
    expect(calls[0]!.input).toContain("Current date: 2026-05-28");
    expect(await readFile(result.file, "utf8")).toBe(`${specMarkdown("Chat retries")}\n`);
  });

  test("generates dated paths and suffixes existing files", async () => {
    const cwd = await fixture("dated-output");
    await mkdir(path.join(cwd, ".specs"), { recursive: true });
    await writeFile(path.join(cwd, ".specs", "2026-05-28-chat-retries.md"), "exists\n");
    const runner: AgentRunner = async () => ({ code: 0, stdout: specMarkdown("Chat retries"), stderr: "", output: specMarkdown("Chat retries") });

    const result = await generateSpec(baseOptions(cwd, { agent: "claude", context: ["Add retries."] }), runner);

    expect(result.command).toEqual(["claude", "-p", "--add-dir", cwd]);
    expect(result.file).toBe(path.join(cwd, ".specs", "2026-05-28-chat-retries-2.md"));
    expect(await readFile(result.file, "utf8")).toContain("# Chat retries");
  });

  test("refuses explicit overwrites and reports agent failures", async () => {
    const cwd = await fixture("errors");
    const file = path.join(cwd, ".specs", "exists.md");
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, "exists\n");
    const ok: AgentRunner = async () => ({ code: 0, stdout: specMarkdown("Overwrite spec"), stderr: "", output: specMarkdown("Overwrite spec") });
    const fail: AgentRunner = async () => ({ code: 1, stdout: "", stderr: "agent failed\n", output: "agent failed\n" });

    await expect(generateSpec(baseOptions(cwd, { output: ".specs/exists.md" }), ok)).rejects.toThrow("spec already exists");
    await expect(generateSpec(baseOptions(cwd), fail)).rejects.toThrow("agent failed");
    const forced = await generateSpec(baseOptions(cwd, { force: true, output: ".specs/exists.md" }), ok);
    expect(await readFile(forced.file, "utf8")).toContain("# Overwrite spec");
  });

  test("runs a custom agent command through stdin", async () => {
    const cwd = await fixture("custom-agent");
    const agent = path.join(cwd, "agent.sh");
    await writeFile(
      agent,
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "cat > prompt.log",
        "printf '%s\\n' '---' 'status: draft' 'type: feat' 'created: 2026-05-28' 'pr: null' '---' '' '# Custom agent spec'",
        "",
      ].join("\n"),
    );
    await chmod(agent, 0o755);

    const result = await generateSpec(baseOptions(cwd, { agent, context: ["Use a custom agent."] }));

    expect(result.command).toEqual([agent]);
    expect(await exists(path.join(cwd, "prompt.log"))).toBe(true);
    expect(result.file).toBe(path.join(cwd, ".specs", "2026-05-28-custom-agent-spec.md"));
    expect(await readFile(result.file, "utf8")).toContain("# Custom agent spec");
  });
});

async function fixture(name: string) {
  const dir = path.join(root, name);
  await mkdir(dir, { recursive: true });
  return dir;
}

function baseOptions(cwd: string, overrides: Partial<GenerateSpecOptions> = {}): GenerateSpecOptions {
  return {
    agent: "codex",
    context: ["Add a spec generator."],
    cwd,
    force: false,
    today: "2026-05-28",
    ...overrides,
  };
}

function specMarkdown(title: string) {
  return [
    "---",
    "status: draft",
    "type: feat",
    "created: 2026-05-28",
    "pr: null",
    "---",
    "",
    `# ${title}`,
  ].join("\n");
}

async function exists(file: string) {
  return Boolean(await stat(file).catch(() => false));
}
