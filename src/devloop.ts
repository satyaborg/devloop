import { createHash, randomUUID } from "node:crypto";
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

export type ReportFormat = "html" | "markdown";
export type Agent = "codex" | "claude";
export type Verdict = "ACCEPT" | "REJECT" | "UNCLEAR";
export type Status =
  | "accepted"
  | "stalled"
  | "max-turns"
  | "unclear"
  | "no-verdict"
  | "coder-error"
  | "reviewer-error"
  | "review-missing"
  | "commit-error";

type WorkType = "feat" | "fix" | "chore";
type WorkItem = {
  slug: string;
  type: WorkType;
  breaking: boolean;
};

export type Options = {
  spec: string;
  max: number;
  reportFormat: ReportFormat;
  strict: boolean;
  worktree: boolean;
  coder: Agent;
  reviewer: Agent;
  cwd: string;
};

export type Result = {
  status: Status;
  passes: number;
  max: number;
  report: string;
  track: string;
  branch: string;
  commit: string;
  commitMessage: string;
  worktree: string;
  sourceRepo: string;
  coder: Agent;
  reviewer: Agent;
  coderSessionId: string;
  reviewerSessionId: string;
};

export type Event =
  | { type: "gate"; name: string; ok: boolean; detail: string }
  | { type: "step"; id: string; title: string }
  | { type: "log"; id: string; line: string }
  | { type: "done"; id: string; ok: boolean; detail: string }
  | { type: "result"; result: Result };

export type Sink = {
  event(event: Event): void | Promise<void>;
  close?(): void | Promise<void>;
};

type RunResult = {
  code: number;
  output: string;
  stdout: string;
  stderr: string;
};
type Runner = (
  cmd: string,
  args: string[],
  input?: string,
  log?: string,
  id?: string,
) => Promise<RunResult>;

export const LOGO = [
  "       __          __                ",
  "  ____/ /__ _   __/ /___  ____  ____ ",
  " / __  / _ \\ | / / / __ \\/ __ \\/ __ \\",
  "/ /_/ /  __/ |/ / / /_/ / /_/ / /_/ /",
  "\\__,_/\\___/|___/_/\\____/\\____/ .___/ ",
  "                            /_/",
].join("\n");

export function welcome() {
  return `${LOGO}

Spec-driven code and review loop. Codex implements and Claude Code reviews by default.

Usage:
  devloop [options] <spec.md> [max=5]

Common commands:
  devloop .specs/change.md
  devloop --tui .specs/change.md
  devloop --plain .specs/change.md
  devloop --report-format markdown .specs/change.md 3
  devloop --coder claude --reviewer codex .specs/change.md
  bun scripts/install.ts

Options:
  --tui                         force the collapsed TUI
  --plain                       force plain output
  --coder codex|claude          choose the implementation agent
  --reviewer codex|claude       choose the review agent
  --report-format html|markdown choose report format
  --no-strict                   weaken acceptance gates
  --in-place                    run in the current worktree
  -h, --help                    show this screen`;
}

export function parseArgs(
  argv: string[],
  cwd = process.cwd(),
): Options | string {
  let reportFormat: ReportFormat = "html";
  let strict = true;
  let worktree = true;
  let coder: Agent = "codex";
  let reviewer: Agent = "claude";
  let spec = "";
  let maxRaw = "5";
  let maxSet = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === "--report-format") {
      const value = argv[++i];
      if (value !== "html" && value !== "markdown" && value !== "md")
        return usage();
      reportFormat = value === "md" ? "markdown" : value;
    } else if (arg === "--coder") {
      const value = parseAgent(argv[++i]);
      if (!value) return `coder must be codex or claude\n${usage()}`;
      coder = value;
    } else if (arg === "--reviewer") {
      const value = parseAgent(argv[++i]);
      if (!value) return `reviewer must be codex or claude\n${usage()}`;
      reviewer = value;
    } else if (arg === "--html") reportFormat = "html";
    else if (arg === "--markdown" || arg === "--md") reportFormat = "markdown";
    else if (arg === "--no-strict") strict = false;
    else if (arg === "--strict") strict = true;
    else if (arg === "--in-place") worktree = false;
    else if (arg === "--plain" || arg === "--tui") continue;
    else if (arg === "-h" || arg === "--help") return usage();
    else if (arg.startsWith("--")) return `unknown option: ${arg}\n${usage()}`;
    else if (!spec) spec = arg;
    else if (!maxSet) {
      maxRaw = arg;
      maxSet = true;
    } else return usage();
  }

  if (!spec) return usage();
  if (!/^[+-]?\d+$/.test(maxRaw))
    return "max must be an integer between 1 and 10";
  return {
    spec,
    max: clamp(Number.parseInt(maxRaw, 10), 1, 10),
    reportFormat,
    strict,
    worktree,
    coder,
    reviewer,
    cwd,
  };
}

export function usage() {
  return "usage: devloop [--plain|--tui] [--in-place] [--no-strict] [--coder codex|claude] [--reviewer codex|claude] [--report-format html|markdown] <spec.md> [max=5]";
}

export function parseCriteria(markdown: string): string[] {
  const lines = markdown.split(/\r?\n/);
  const start = lines.findIndex((line) =>
    /^##\s+acceptance criteria\s*$/i.test(line.trim()),
  );
  if (start < 0) return [];
  const body = lines.slice(start + 1);
  const end = body.findIndex((line) => /^##\s+/.test(line));
  return body
    .slice(0, end < 0 ? body.length : end)
    .map((line) => line.trim().replace(/^([-*]|\d+[.)])\s+/, ""))
    .filter(Boolean);
}

export function parseVerdict(review: string): Verdict | "" {
  const match = review.match(/^Verdict:\s+(ACCEPT|REJECT|UNCLEAR)/m);
  return match ? (match[1] as Verdict) : "";
}

export function hasPassingMatrix(review: string, count: number) {
  if (!/^## Acceptance matrix\s*$/m.test(review)) return false;
  return Array.from(
    { length: count },
    (_, i) => new RegExp(`^-\\s*AC${i + 1}:\\s*PASS\\b`, "mi"),
  ).every((r) => r.test(review));
}

export function reportFraming(specText: string, slug: string) {
  const title = reportTitle(specText) ?? titleFromSlug(slug);
  return {
    title,
    subtitle:
      sectionLead(specText, "Outcome") ??
      sectionLead(specText, "Problem") ??
      sectionLead(specText, "Acceptance criteria") ??
      `Outcome, review findings, and residual risk for ${title}.`,
  };
}

export function findingsHash(review: string) {
  const body =
    review.match(/^## Findings\s*\n([\s\S]*?)(?:\n##\s+|$)/m)?.[1] ?? "";
  const normalized = body
    .replace(/\d+/g, "")
    .replace(/[ \t\r\n]+/g, " ")
    .split(".")
    .map((line) => line.trim())
    .filter(Boolean)
    .sort()
    .join("\n");
  return createHash("sha256").update(normalized).digest("hex");
}

export function isIsolatedWorktree(
  result: Pick<Result, "sourceRepo" | "worktree">,
) {
  return result.worktree !== result.sourceRepo;
}

export function resultPath(
  result: Pick<Result, "sourceRepo" | "worktree">,
  file: string,
) {
  return isIsolatedWorktree(result) ? path.join(result.worktree, file) : file;
}

export async function runDevloop(
  options: Options,
  sink: Sink = { event: () => {} },
): Promise<Result> {
  const spec = await absoluteFile(options.spec, options.cwd);
  const specText = await readFile(spec, "utf8");
  const criteria = parseCriteria(specText);
  if (options.strict && criteria.length === 0)
    throw new Error("strict mode requires ## Acceptance criteria");
  await sink.event({
    type: "gate",
    name: "acceptance criteria",
    ok: criteria.length > 0,
    detail: `${criteria.length} found`,
  });

  const sourceRepo = (
    await command("git", ["-C", options.cwd, "rev-parse", "--show-toplevel"])
  ).trim();
  const sourceBranch = (
    await command("git", [
      "-C",
      sourceRepo,
      "rev-parse",
      "--abbrev-ref",
      "HEAD",
    ])
  ).trim();
  const base = await baseBranch(sourceRepo);
  const namingId = "naming";
  await sink.event({
    type: "step",
    id: namingId,
    title: `derive branch name with ${agentLabel(options.coder)}`,
  });
  let namingLog = "";
  let namingError = "";
  const work = await (async () => {
    const fields = workItemFields(specText);
    namingLog = completeWorkItem(fields)
      ? ""
      : path.join(
          await mkdtemp(path.join(tmpdir(), "devloop-naming.")),
          "naming.log",
        );
    return resolveWorkItem({
      agent: options.coder,
      runner: makeRunner(sourceRepo, sink),
      repo: sourceRepo,
      spec,
      specText,
      fields,
      log: namingLog,
    });
  })().catch((error) => {
    namingError = error instanceof Error ? error.message : String(error);
    return undefined;
  });
  await sink.event({
    type: "done",
    id: namingId,
    ok: Boolean(work),
    detail: work ? `${branchBase(work)}` : namingError,
  });
  if (!work)
    throw new Error(
      `naming failed: ${namingError}${namingLog ? `\nnaming log: ${namingLog}` : ""}`,
    );
  const slug = work.slug;

  let repo = sourceRepo;
  if (options.worktree) {
    const worktreeId = "worktree";
    await sink.event({
      type: "step",
      id: worktreeId,
      title: "create worktree",
    });
    repo = await createWorktree(sourceRepo, work);
    await sink.event({
      type: "done",
      id: worktreeId,
      ok: true,
      detail: repo,
    });
  }

  const dirs = [
    ".codex/specs",
    ".codex/tracks",
    ".codex/reviews",
    ".codex/reports",
    ".codex/logs",
    ".codex/sessions",
  ];
  await Promise.all(
    dirs.map((dir) => mkdir(path.join(repo, dir), { recursive: true })),
  );
  if (namingLog) {
    await copyFile(namingLog, path.join(repo, ".codex/logs", `${slug}-naming.log`));
    await rm(path.dirname(namingLog), { recursive: true, force: true });
  }

  const runSpec = options.worktree
    ? await snapshotSpec(repo, slug, specText)
    : spec;
  const initialDirty = await statusPaths(repo);
  const runBranch = (
    await command("git", ["-C", repo, "branch", "--show-current"])
  ).trim();
  const track = `.codex/tracks/${slug}.md`;
  const report = `.codex/reports/${slug}.${options.reportFormat === "html" ? "html" : "md"}`;
  const coderSession = `.codex/sessions/${slug}-coder-${options.coder}.id`;
  const reviewerSession = `.codex/sessions/${slug}-reviewer-${options.reviewer}.id`;
  const runner = makeRunner(repo, sink);
  await initTrack(path.join(repo, track), {
    spec: runSpec,
    sourceSpec: spec,
    cwd: options.cwd,
    sourceRepo,
    worktree: repo,
    base,
    branch: sourceBranch,
    worktreeBranch: runBranch,
    max: options.max,
    reportFormat: options.reportFormat,
    strict: options.strict,
    coder: options.coder,
    reviewer: options.reviewer,
    type: work.type,
    breaking: work.breaking,
  });

  let status: Status = "max-turns";
  let prior = "";
  let pass = 0;
  let commit = "";
  let commitMessage = "";
  let finalBranch = runBranch;

  for (pass = 1; pass <= options.max; pass++) {
    const coderLog = `.codex/logs/${slug}-r${pass}-coder.log`;
    const coderId = `coder-${pass}`;
    await sink.event({
      type: "step",
      id: coderId,
      title: `pass ${pass}/${options.max} ${agentLabel(options.coder)} implementation`,
    });
    const coded = await runAgent(
      options.coder,
      runner,
      repo,
      path.join(repo, coderSession),
      path.join(repo, coderLog),
      coderPrompt({
        spec: runSpec,
        track,
        pass,
        strict: options.strict,
        previous: `.codex/reviews/${slug}-r${pass - 1}.md`,
        criteria,
      }),
      coderId,
    );
    await sink.event({
      type: "done",
      id: coderId,
      ok: coded,
      detail: coded ? "completed" : "failed",
    });
    if (!coded) {
      status = "coder-error";
      break;
    }

    const review = `.codex/reviews/${slug}-r${pass}.md`;
    const reviewerLog = `.codex/logs/${slug}-r${pass}-reviewer.log`;
    const reviewerId = `reviewer-${pass}`;
    await sink.event({
      type: "step",
      id: reviewerId,
      title: `pass ${pass}/${options.max} ${agentLabel(options.reviewer)} review`,
    });
    const ok = await runAgent(
      options.reviewer,
      runner,
      repo,
      path.join(repo, reviewerSession),
      path.join(repo, reviewerLog),
      reviewPrompt({
        coder: options.coder,
        spec: runSpec,
        track,
        base,
        pass,
        output: review,
        priors: listReviews(slug, pass, options.max),
        criteria,
        strict: options.strict,
      }),
      reviewerId,
    );
    await sink.event({
      type: "done",
      id: reviewerId,
      ok,
      detail: ok ? "completed" : "failed",
    });
    if (!ok) {
      status = "reviewer-error";
      break;
    }

    let reviewText = "";
    try {
      reviewText = await readFile(path.join(repo, review), "utf8");
    } catch {
      status = "review-missing";
      break;
    }
    const verdict = parseVerdict(reviewText);
    await sink.event({
      type: "gate",
      name: `pass ${pass} verdict`,
      ok: verdict === "ACCEPT",
      detail: verdict || "MISSING",
    });
    if (verdict === "ACCEPT") {
      status =
        options.strict && !hasPassingMatrix(reviewText, criteria.length)
          ? "unclear"
          : "accepted";
      break;
    }
    if (verdict === "UNCLEAR") {
      status = "unclear";
      break;
    }
    if (verdict === "REJECT") {
      const hash = findingsHash(reviewText);
      if (prior && hash === prior) {
        status = "stalled";
        break;
      }
      prior = hash;
    } else {
      status = "no-verdict";
      break;
    }
  }

  if (pass > options.max) pass = options.max;
  if (status === "accepted") {
    const commitId = "commit";
    await sink.event({
      type: "step",
      id: commitId,
      title: "local branch and commit",
    });
    let commitError = "";
    const committed = await commitAccepted(repo, work, initialDirty).catch(
      (error) => {
        commitError = error instanceof Error ? error.message : String(error);
        return undefined;
      },
    );
    if (committed) {
      finalBranch = committed.branch;
      commit = committed.commit;
      commitMessage = committed.message;
      await sink.event({
        type: "done",
        id: commitId,
        ok: true,
        detail: commit
          ? `${finalBranch} ${commit}`
          : `${finalBranch} no changes`,
      });
    } else {
      status = "commit-error";
      await sink.event({
        type: "done",
        id: commitId,
        ok: false,
        detail: commitError || "failed",
      });
    }
  }

  const coderSessionId = await readLine(path.join(repo, coderSession));
  const reviewerSessionId = await readLine(path.join(repo, reviewerSession));
  await synthesizeReport(runner, repo, {
    slug,
    reviewer: options.reviewer,
    spec: runSpec,
    specText,
    sourceSpec: spec,
    sourceRepo,
    worktree: repo,
    track,
    report,
    status,
    pass,
    max: options.max,
    base,
    initialBranch: sourceBranch,
    branch: finalBranch,
    commit,
    commitMessage,
    coder: options.coder,
    reviewerSessionFile: path.join(repo, reviewerSession),
    coderSessionId,
    reviewerSessionId,
    format: options.reportFormat,
    reviews: listReviews(slug, pass, options.max),
  });
  const result = {
    status,
    passes: pass,
    max: options.max,
    report,
    track,
    branch: finalBranch,
    commit,
    commitMessage,
    worktree: repo,
    sourceRepo,
    coder: options.coder,
    reviewer: options.reviewer,
    coderSessionId,
    reviewerSessionId,
  };
  await sink.event({ type: "result", result });
  return result;
}

async function absoluteFile(file: string, cwd: string) {
  const full = path.resolve(cwd, file);
  if (!(await stat(full).catch(() => false))) throw new Error(usage());
  return realpath(full);
}

async function command(cmd: string, args: string[]) {
  const proc = Bun.spawn([cmd, ...args], { stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (code !== 0)
    throw new Error(
      err.trim() ||
        out.trim() ||
        `${cmd} ${args.join(" ")} failed with exit ${code}`,
    );
  return out;
}

async function createWorktree(repo: string, work: WorkItem) {
  const branch = await nextBranch(repo, work, "");
  const worktree = await nextWorktreePath(repo, branchLeaf(branch));
  await command("git", [
    "-C",
    repo,
    "worktree",
    "add",
    "-b",
    branch,
    worktree,
    "HEAD",
  ]);
  return realpath(worktree);
}

async function nextWorktreePath(repo: string, slug: string) {
  const base = path.join(
    path.dirname(repo),
    `${path.basename(repo)}-${slugify(slug)}`,
  );
  let suffix = 1;
  let candidate = base;
  while (await stat(candidate).catch(() => false)) {
    suffix++;
    candidate = `${base}-${suffix}`;
  }
  return candidate;
}

async function snapshotSpec(repo: string, slug: string, specText: string) {
  const file = path.join(repo, ".codex/specs", `${slug}.md`);
  await writeFile(file, specText);
  return file;
}

async function baseBranch(repo: string) {
  for (const args of [
    ["-C", repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
    ["-C", repo, "show-ref", "--verify", "-q", "refs/heads/main"],
    ["-C", repo, "show-ref", "--verify", "-q", "refs/heads/master"],
  ]) {
    const proc = Bun.spawn(["git", ...args], {
      stdout: "pipe",
      stderr: "pipe",
    });
    if ((await proc.exited) === 0) {
      if (args[2] === "symbolic-ref")
        return (await new Response(proc.stdout).text())
          .trim()
          .replace(/^origin\//, "");
      return args.at(-1)!.split("/").pop()!;
    }
  }
  return "main";
}

async function statusPaths(repo: string) {
  const out = await command("git", [
    "-C",
    repo,
    "status",
    "--porcelain=v1",
    "-z",
    "--untracked-files=all",
  ]);
  const parts = out.split("\0").filter(Boolean);
  const paths = new Set<string>();
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i]!;
    const code = item.slice(0, 2);
    const file = item.slice(3);
    if (file) paths.add(file);
    if (code.includes("R") || code.includes("C")) {
      const next = parts[++i];
      if (next) paths.add(next);
    }
  }
  return paths;
}

async function commitAccepted(
  repo: string,
  work: WorkItem,
  initialDirty: Set<string>,
) {
  const current = (
    await command("git", ["-C", repo, "branch", "--show-current"])
  ).trim();
  const branch = await nextBranch(repo, work, current);
  const message = `${work.type}${work.breaking ? "!" : ""}: ${work.slug}`;
  if (branch !== current)
    await command("git", ["-C", repo, "switch", "-c", branch]);
  const changed = [...(await statusPaths(repo))].filter(
    (file) => !initialDirty.has(file) && !file.startsWith(".codex/"),
  );
  if (changed.length === 0) return { branch, commit: "", message };
  await command("git", ["-C", repo, "add", "--", ...changed]);
  await command("git", [
    "-C",
    repo,
    "commit",
    "--only",
    "-m",
    message,
    "--",
    ...changed,
  ]);
  return {
    branch,
    commit: (
      await command("git", ["-C", repo, "rev-parse", "--short", "HEAD"])
    ).trim(),
    message,
  };
}

async function nextBranch(repo: string, work: WorkItem, current: string) {
  const base = branchBase(work);
  if (
    current === base ||
    new RegExp(`^${escapeRegex(base)}-\\d+$`).test(current)
  )
    return current;
  let suffix = 1;
  let branch = base;
  while (await branchExists(repo, branch)) {
    suffix++;
    branch = `${base}-${suffix}`;
  }
  return branch;
}

function branchBase(work: WorkItem) {
  return `${work.type}${work.breaking ? "!" : ""}/${work.slug}`;
}

async function branchExists(repo: string, branch: string) {
  const proc = Bun.spawn([
    "git",
    "-C",
    repo,
    "show-ref",
    "--verify",
    "--quiet",
    `refs/heads/${branch}`,
  ]);
  return (await proc.exited) === 0;
}

function makeRunner(cwd: string, sink: Sink): Runner {
  return async (cmd, args, input = "", log, id) => {
    let proc: Bun.Subprocess<"pipe", "pipe", "pipe">;
    try {
      proc = Bun.spawn([cmd, ...args], {
        cwd,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
        env: Bun.env,
      });
    } catch (error) {
      const output = error instanceof Error ? error.message : String(error);
      if (log) await writeFile(log, output);
      return { code: 127, output, stdout: "", stderr: output };
    }
    proc.stdin.write(input);
    proc.stdin.end();
    let output = "";
    let stdout = "";
    let stderr = "";
    const pump = async (
      stream: ReadableStream<Uint8Array>,
      append: (text: string) => void,
    ) => {
      const reader = stream.getReader();
      const decoder = new TextDecoder();
      let pending = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        const text = decoder.decode(value);
        output += text;
        append(text);
        pending += text;
        const lines = pending.split(/\r?\n/);
        pending = lines.pop() ?? "";
        if (id)
          for (const line of lines.filter(Boolean))
            await sink.event({ type: "log", id, line });
      }
      if (id && pending) await sink.event({ type: "log", id, line: pending });
    };
    const [, , code] = await Promise.all([
      pump(proc.stdout, (text) => {
        stdout += text;
      }),
      pump(proc.stderr, (text) => {
        stderr += text;
      }),
      proc.exited,
    ]);
    if (log) await writeFile(log, output);
    return { code, output, stdout, stderr };
  };
}

async function initTrack(
  file: string,
  data: {
    spec: string;
    sourceSpec: string;
    cwd: string;
    sourceRepo: string;
    worktree: string;
    base: string;
    branch: string;
    worktreeBranch: string;
    max: number;
    reportFormat: ReportFormat;
    strict: boolean;
    coder: Agent;
    reviewer: Agent;
    type: WorkType;
    breaking: boolean;
  },
) {
  if (await stat(file).catch(() => false)) return;
  await writeFile(
    file,
    `# Track: ${path.basename(file, ".md")}\n\n- spec: ${data.spec}\n- source-spec: ${data.sourceSpec}\n- cwd: ${data.cwd}\n- source-repo: ${data.sourceRepo}\n- worktree: ${data.worktree}\n- base: ${data.base}\n- branch: ${data.branch}\n- worktree-branch: ${data.worktreeBranch}\n- coder: ${data.coder}\n- reviewer: ${data.reviewer}\n- type: ${data.type}\n- breaking: ${data.breaking}\n- max: ${data.max}\n- report-format: ${data.reportFormat}\n- strict: ${data.strict}\n- started: ${new Date().toISOString()}\n\n`,
  );
}

async function readLine(file: string) {
  return (
    (await readFile(file, "utf8").catch(() => "")).split(/\r?\n/, 1)[0] ?? ""
  );
}

async function writeLine(file: string, value: string) {
  await writeFile(file, `${value}\n`);
}

async function runAgent(
  agent: Agent,
  runner: Runner,
  repo: string,
  sessionFile: string,
  log: string,
  prompt: string,
  id: string,
) {
  return agent === "codex"
    ? runCodex(runner, repo, sessionFile, log, prompt, id)
    : runClaude(runner, repo, sessionFile, log, prompt, id);
}

async function runAgentOnce(
  agent: Agent,
  runner: Runner,
  repo: string,
  log: string,
  prompt: string,
  id: string,
) {
  return agent === "codex"
    ? runner(
        "codex",
        ["exec", "-s", "read-only", "-C", repo, "-"],
        prompt,
        log,
        id,
      )
    : runner(
        "claude",
        ["-p", "--dangerously-skip-permissions", "--add-dir", repo],
        prompt,
        log,
        id,
      );
}

async function runCodex(
  runner: Runner,
  repo: string,
  sessionFile: string,
  log: string,
  prompt: string,
  id: string,
) {
  const session = await readLine(sessionFile);
  const args = session
    ? [
        "exec",
        "resume",
        "--dangerously-bypass-approvals-and-sandbox",
        session,
        "-",
      ]
    : ["exec", "--dangerously-bypass-approvals-and-sandbox", "-C", repo, "-"];
  const result = await runner("codex", args, prompt, log, id);
  if (result.code !== 0) return false;
  if (!session) {
    const next = extractSessionId(result.output);
    if (!next) return false;
    await writeLine(sessionFile, next);
  }
  return true;
}

async function runClaude(
  runner: Runner,
  repo: string,
  sessionFile: string,
  log: string,
  prompt: string,
  id: string,
) {
  const session = await readLine(sessionFile);
  const next = session || randomUUID();
  const args = session
    ? [
        "-p",
        "--resume",
        session,
        "--dangerously-skip-permissions",
        "--add-dir",
        repo,
      ]
    : [
        "-p",
        "--session-id",
        next,
        "--dangerously-skip-permissions",
        "--add-dir",
        repo,
      ];
  const result = await runner(
    "claude",
    args,
    prompt,
    log,
    id,
  );
  if (result.code !== 0) return false;
  if (!session) await writeLine(sessionFile, next);
  return true;
}

function extractSessionId(output: string) {
  return output
    .split(/\r?\n/)
    .filter((line) =>
      /(session.?id|thread_id|codex exec resume|codex resume|To continue this session)/i.test(
        line,
      ),
    )
    .join("\n")
    .match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)?.[0]
    .toLowerCase();
}

function listReviews(slug: string, upto: number, max: number) {
  return Array.from(
    { length: Math.min(upto, max) },
    (_, i) => `- .codex/reviews/${slug}-r${i + 1}.md`,
  ).join("\n");
}

function criteriaBlock(criteria: string[]) {
  return (
    criteria.map((criterion, i) => `AC${i + 1}: ${criterion}`).join("\n") ||
    "No parsed acceptance criteria."
  );
}

function coderPrompt(input: {
  spec: string;
  track: string;
  pass: number;
  strict: boolean;
  previous: string;
  criteria: string[];
}) {
  const strict = input.strict
    ? "\nStrict lifecycle:\n1. Add or update regression tests before implementation.\n2. Run the narrow test first and record the failing result, unless impossible; if impossible, say why.\n3. Implement the smallest change.\n4. Run targeted tests, full tests, lint/typecheck, and coverage. Coverage must be 100% when the project exposes coverage tooling.\n"
    : "";
  return input.pass === 1
    ? `You are implementing against an approved spec.\n\nSpec: ${input.spec}\nTrack: ${input.track}\nPass: ${input.pass}\nAcceptance criteria:\n${criteriaBlock(input.criteria)}${strict}\nTasks:\n1. Read the spec.\n2. Implement the smallest working change satisfying the acceptance criteria.\n3. Append "## Pass ${input.pass} - implement" to ${input.track} with changed files, design tradeoffs, verification, and residual risk.\n\nConstraints:\n- Do not commit.\n- Do not edit the spec.\n- Do not revert unrelated dirty files.\n`
    : `Fix only the findings in the review. Do not refactor unrelated code.\n\nSpec: ${input.spec}\nTrack: ${input.track}\nReview: ${input.previous}\nPass: ${input.pass}\nAcceptance criteria:\n${criteriaBlock(input.criteria)}${strict}\nTasks:\n1. Read the review file.\n2. Fix each finding or explain why it is wrong in the track.\n3. Re-run relevant tests.\n4. Append "## Pass ${input.pass} - fix" to ${input.track} with per-finding outcomes.\n`;
}

function reviewPrompt(input: {
  coder: Agent;
  spec: string;
  track: string;
  base: string;
  pass: number;
  output: string;
  priors: string;
  criteria: string[];
  strict: boolean;
}) {
  return `You are reviewing a ${agentLabel(input.coder)} implementation. Be a senior reviewer, not a linter.\n\nSpec: ${input.spec}\nTrack: ${input.track}\nBase: ${input.base}\nPass: ${input.pass}\nPrior reviews:\n${input.priors}\nAcceptance criteria:\n${criteriaBlock(input.criteria)}\nOutput path: ${input.output}\n\nSteps:\n1. Read the spec and track.\n2. Run: git diff ${input.base}...HEAD\n3. Read prior reviews so you do not repeat resolved findings.\n4. Write the review to ${input.output} using this exact format:\n\n# Review ${input.pass}\n\nVerdict: <ACCEPT | REJECT | UNCLEAR>\n\n## Acceptance matrix\n\n- AC1: <PASS | FAIL | UNCLEAR> - <evidence>\n\n## Findings\n\n1. [severity] <file:line> - <symptom>. Root cause: <why>. Principle: <principle>.\n\n## Missing tests\n\n- <gap, or None>\n\n## Fix instructions\n\n1. <standalone instruction>\n\n## Notes\n\n- <scope, disputes, lessons, or None>\n\nRules:\n- The verdict line must appear verbatim.\n- ACCEPT requires every acceptance criterion PASS with concrete evidence.${input.strict ? "\n- ACCEPT also requires regression-test evidence, red/green evidence when behavior changed, passing full tests, and 100% coverage when coverage tooling exists." : ""}\n- For ACCEPT: Findings and Fix instructions bodies are "None".\n- Findings must explain WHY, not just WHAT.\n`;
}

async function synthesizeReport(
  runner: Runner,
  repo: string,
  input: {
    slug: string;
    reviewer: Agent;
    spec: string;
    specText: string;
    sourceSpec: string;
    sourceRepo: string;
    worktree: string;
    track: string;
    report: string;
    status: Status;
    pass: number;
    max: number;
    base: string;
    initialBranch: string;
    branch: string;
    commit: string;
    commitMessage: string;
    coder: Agent;
    reviewerSessionFile: string;
    coderSessionId: string;
    reviewerSessionId: string;
    format: ReportFormat;
    reviews: string;
  },
) {
  const framing = reportFraming(input.specText, input.slug);
  const metadata = `Result: ${input.status}
Passes: ${input.pass} / ${input.max}
Repository: ${repo}
Spec: ${input.spec}
Source spec: ${input.sourceSpec}
Source repository: ${input.sourceRepo}
Worktree: ${input.worktree}
Base branch: ${input.base}
Starting branch: ${input.initialBranch}
Final branch: ${input.branch}
Local commit: ${input.commit || "none"}
Commit message: ${input.commitMessage || "none"}
Coder: ${agentLabel(input.coder)}
Reviewer: ${agentLabel(input.reviewer)}
Coder session: ${input.coderSessionId || "unknown"}
Reviewer session: ${input.reviewerSessionId || "unknown"}
Track: ${input.track}
Reviews:
${input.reviews}`;
  const body =
    input.format === "html"
      ? `Write the report to ${input.report} as valid standalone HTML. Use a readable document layout with embedded CSS, set the HTML <title> to the report title, render the report title and subtitle before Metadata, render a topical three-line haiku immediately after the subtitle, use a compact metadata table, and add substantive sections after it. Include these visible section headings: Metadata, The shape of the problem, What was built, What the review caught (and why it mattered), What to remember next time, Residual risk, Pointers. Do not optimize away substance: explain the decisions, tradeoffs, evidence, and transferable lessons clearly enough that the reader learns from the run.`
      : `Write the report to ${input.report} in markdown. Start with the report title as the H1, put the subtitle directly below it, put a topical three-line haiku immediately after the subtitle, then include these headings: Metadata, The shape of the problem, What was built, What the review caught (and why it mattered), What to remember next time, Residual risk, Pointers. Do not optimize away substance: explain the decisions, tradeoffs, evidence, and transferable lessons clearly enough that the reader learns from the run.`;
  await runAgent(
    input.reviewer,
    runner,
    repo,
    input.reviewerSessionFile,
    path.join(repo, `.codex/logs/${input.slug}-report.log`),
    `You are writing a learning-oriented post-mortem for a developer who just ran a devloop.\n\nReport framing to render visibly near the top, before Metadata:\nTitle: ${framing.title}\nSubtitle: ${framing.subtitle}\nHaiku: Compose a three-line haiku, 5/7/5 syllables if possible, about this specific work.\nHaiku topic: ${framing.title} - ${framing.subtitle}\n\nUse that exact title and subtitle. The subtitle must be specific to this work, not a generic or hard-coded tagline. The haiku must be topical, concrete, and rendered immediately after the subtitle before Metadata.\n\nMetadata to render exactly and visibly:\n${metadata}\n\nInputs:\n- spec: ${input.spec}\n- track: ${input.track}\nReview files:\n${input.reviews}\n- final status: ${input.status}\n- passes used: ${input.pass} / ${input.max}\n- base: ${input.base}, starting branch: ${input.initialBranch}, final branch: ${input.branch}, local commit: ${input.commit || "none"}\n\n${body}\n\nStyle:\n- Human readable, not ornamental.\n- Preserve useful substance over brevity.\n- Teach the why: symptom, root cause, principle, decision, tradeoff, and evidence.\n- No emoji.\n`,
    "report",
  );
}

function reportTitle(specText: string) {
  for (const line of specText.split(/\r?\n/)) {
    const match = line.match(/^#\s+(.+)$/);
    const title = cleanReportText(match?.[1] ?? "");
    if (title) return title;
  }
  return undefined;
}

function sectionLead(
  specText: string,
  heading: "Outcome" | "Problem" | "Acceptance criteria",
) {
  const lines = specText.split(/\r?\n/);
  const headingPattern = new RegExp(`^##\\s+${heading}\\s*$`, "i");
  const start = lines.findIndex((line) => headingPattern.test(line.trim()));
  if (start < 0) return undefined;
  for (const line of lines.slice(start + 1)) {
    if (/^##\s+/.test(line)) return undefined;
    const text = cleanReportText(line.replace(/^([-*]|\d+[.)])\s+/, ""));
    if (text) return text;
  }
  return undefined;
}

function cleanReportText(value: string) {
  const text = value.trim().replace(/\s+/g, " ");
  if (!text || text === "..." || /^<.*>$/.test(text)) return undefined;
  return text;
}

function titleFromSlug(slug: string) {
  return (
    slug
      .split("-")
      .filter(Boolean)
      .map((part) => part[0]!.toUpperCase() + part.slice(1))
      .join(" ") || "Devloop Report"
  );
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function parseAgent(value: string | undefined): Agent | undefined {
  const normalized = (value ?? "").trim().toLowerCase();
  if (normalized === "codex") return "codex";
  if (normalized === "claude") return "claude";
  return undefined;
}

function agentLabel(agent: Agent) {
  return agent === "codex" ? "Codex" : "Claude Code";
}

async function resolveWorkItem(input: {
  agent: Agent;
  runner: Runner;
  repo: string;
  spec: string;
  specText: string;
  fields: WorkItemFields;
  log: string;
}) {
  const explicit = completeWorkItem(input.fields);
  if (explicit) return explicit;
  const derived = await deriveWorkItem(input);
  return mergeWorkItem(derived, input.fields);
}

async function deriveWorkItem(input: {
  agent: Agent;
  runner: Runner;
  repo: string;
  spec: string;
  specText: string;
  log: string;
}) {
  const result = await runAgentOnce(
    input.agent,
    input.runner,
    input.repo,
    input.log,
    namingPrompt(input.spec, input.specText),
    "naming",
  );
  if (result.code !== 0)
    throw new Error(result.output || `${input.agent} failed`);
  return parseWorkItem(result.stdout || result.output);
}

function namingPrompt(spec: string, specText: string) {
  return `Work item naming task.

Read the spec and, when useful, inspect the repository to choose the semantic work item identity.

Return exactly one JSON object and no markdown:
{"type":"feat","slug":"short-kebab-case-name","breaking":false}

Rules:
- type must be one of: feat, fix, chore.
- Use feat for new capability or materially expanded behavior.
- Use fix for correcting broken, incorrect, or regressed behavior.
- Use chore for maintenance, docs, tests, dependency work, refactors, and internal cleanup.
- Use breaking true only when the work intentionally breaks an external API, data contract, command behavior, or migration expectation.
- slug must be 1-6 short kebab-case words that name the actual work, not the process.
- Exclude dates, issue numbers, repo names, agent names, and type words from slug.
- Prefer concrete nouns from the problem domain over generic words like change, update, cleanup, or implementation.

Spec path: ${spec}

Spec:
${specText}`;
}

function parseWorkItem(output: string): WorkItem {
  const errors: string[] = [];
  for (const candidate of jsonObjectCandidates(output).reverse()) {
    try {
      return workItemFromJson(JSON.parse(candidate));
    } catch (error) {
      errors.push(error instanceof Error ? error.message : String(error));
    }
  }
  throw new Error(errors.at(0) ?? "naming output must include JSON");
}

function workItemFromJson(parsed: unknown): WorkItem {
  if (!isRecord(parsed)) throw new Error("naming output must be an object");
  return validateWorkItem(parsed);
}

type WorkItemFields = {
  type?: WorkType;
  slug?: string;
  breaking?: boolean;
};

function mergeWorkItem(work: WorkItem, fields: WorkItemFields) {
  return validateWorkItem({
    type: fields.type ?? work.type,
    slug: fields.slug ?? work.slug,
    breaking: fields.breaking ?? work.breaking,
  });
}

function completeWorkItem(fields: WorkItemFields) {
  if (fields.type && fields.slug && fields.breaking !== undefined)
    return validateWorkItem(fields);
  return undefined;
}

function validateWorkItem(input: Record<string, unknown>): WorkItem {
  const type = input.type;
  if (typeof type !== "string" || !isWorkType(type))
    throw new Error("naming output type must be feat, fix, or chore");
  const slug = typeof input.slug === "string" ? slugify(input.slug) : "";
  if (!slug) throw new Error("naming output slug is required");
  if (slug.split("-").length > 6)
    throw new Error("naming output slug must be 1-6 words");
  if (["feat", "fix", "chore"].includes(slug.split("-", 1)[0] ?? ""))
    throw new Error("naming output slug must not include a type prefix");
  if (typeof input.breaking !== "boolean")
    throw new Error("naming output breaking must be boolean");
  return { type, slug, breaking: input.breaking };
}

function jsonObjectCandidates(output: string) {
  const candidates: string[] = [];
  let start = -1;
  let depth = 0;
  let string = false;
  let escape = false;
  for (let i = 0; i < output.length; i++) {
    const char = output[i]!;
    if (string) {
      if (escape) escape = false;
      else if (char === "\\") escape = true;
      else if (char === "\"") string = false;
    } else if (char === "\"") string = true;
    else if (char === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (char === "}" && depth > 0) {
      depth--;
      if (depth === 0 && start >= 0) candidates.push(output.slice(start, i + 1));
    }
  }
  return candidates;
}

function workItemFields(specText: string): WorkItemFields {
  const metadata = parseFrontmatter(specText);
  const fields: WorkItemFields = {};
  const type = frontmatterValue(metadata, "type");
  if (type) {
    const base = type.toLowerCase().replace(/!$/, "");
    if (!isWorkType(base))
      throw new Error("frontmatter type must be feat, fix, or chore");
    fields.type = base;
    if (type.endsWith("!")) fields.breaking = true;
  }
  const slug = frontmatterValue(metadata, "slug");
  if (slug) fields.slug = slugify(slug);
  const breaking = frontmatterValue(metadata, "breaking");
  if (breaking) {
    const parsed = parseBoolean(breaking);
    if (fields.breaking === true && !parsed)
      throw new Error("frontmatter breaking conflicts with type !");
    fields.breaking = parsed;
  }
  return fields;
}

function parseFrontmatter(text: string) {
  const metadata = new Map<string, string>();
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  if (!match) return metadata;
  for (const line of match[1]!.split(/\r?\n/)) {
    const pair = line.trim().match(/^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/);
    if (pair) metadata.set(pair[1]!.toLowerCase(), pair[2]!.trim());
  }
  return metadata;
}

function frontmatterValue(metadata: Map<string, string>, key: string) {
  const value = (metadata.get(key) ?? "").replace(/^["']|["']$/g, "").trim();
  if (
    !value ||
    value === "null" ||
    value === "undefined" ||
    value.includes("|") ||
    /^<.*>$/.test(value)
  )
    return undefined;
  return value;
}

function parseBoolean(value: string) {
  if (/^(true|yes|1)$/i.test(value)) return true;
  if (/^(false|no|0)$/i.test(value)) return false;
  throw new Error("frontmatter breaking must be true or false");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function isWorkType(value: string): value is WorkType {
  return value === "feat" || value === "fix" || value === "chore";
}

function branchLeaf(branch: string) {
  return branch.split("/").at(-1) ?? branch;
}

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function escapeRegex(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
