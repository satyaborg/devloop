import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { hasPassingMatrix, parseArgs, parseCriteria, parseVerdict, reportFraming, runDevloop, welcome, type Event, type Options } from "../src/devloop.ts";

const root = await mkdtemp(path.join(tmpdir(), "devloop-test."));
let oldPath = process.env.PATH ?? "";
const defaultAgents = { coder: "codex", reviewer: "claude" } as const;

afterAll(async () => rm(root, { recursive: true, force: true }));
beforeEach(() => {
  oldPath = process.env.PATH ?? "";
  delete process.env.DEVLOOP_TEST_VERDICTS;
  delete process.env.DEVLOOP_TEST_STATE;
  delete process.env.DEVLOOP_TEST_NO_MATRIX;
  delete process.env.DEVLOOP_TEST_NO_REVIEW;
  delete process.env.DEVLOOP_TEST_NO_VERDICT;
  delete process.env.DEVLOOP_TEST_FAIL_CODEX;
  delete process.env.DEVLOOP_TEST_FAIL_NAMING;
  delete process.env.DEVLOOP_TEST_FAIL_CLAUDE;
  delete process.env.DEVLOOP_TEST_NOISY_NAMING;
  delete process.env.DEVLOOP_TEST_WORK_ITEM;
  delete process.env.DEVLOOP_TEST_MULTI_COMMIT;
  delete process.env.DEVLOOP_TEST_NO_CODE_CHANGE;
  delete process.env.DEVLOOP_TEST_FAIL_GH;
});

describe("parsing", () => {
  test("parses options tightly", () => {
    expect(parseArgs(["--no-strict", "--report-format", "md", "spec.md", "08"], "/x")).toEqual({
      spec: "spec.md",
      max: 8,
      reportFormat: "markdown",
      strict: false,
      worktree: true,
      coder: "codex",
      reviewer: "claude",
      cwd: "/x",
      createPr: false,
    } satisfies Options);
    expect(parseArgs(["--in-place", "spec.md"], "/x")).toMatchObject({ worktree: false });
    expect(parseArgs(["--create-pr", "spec.md"], "/x")).toMatchObject({ createPr: true });
    expect(parseArgs(["--pr", "spec.md"], "/x")).toMatchObject({ createPr: true });
    expect(parseArgs(["--coder", "claude", "--reviewer", "codex", "spec.md"], "/x")).toMatchObject({ coder: "claude", reviewer: "codex" });
    expect(parseArgs(["--coder", "gpt", "spec.md"], "/x")).toContain("coder must be codex or claude");
    expect(parseArgs(["--reviewer", "gpt", "spec.md"], "/x")).toContain("reviewer must be codex or claude");
    expect(parseArgs(["spec.md", "0"], "/x")).toMatchObject({ max: 1 });
    expect(parseArgs(["spec.md", "99"], "/x")).toMatchObject({ max: 10 });
    expect(parseArgs(["--wat"], "/x")).toContain("unknown option");
    expect(parseArgs([], "/x")).toContain("usage:");
    expect(parseArgs(["spec.md", "nope"], "/x")).toBe("max must be an integer between 1 and 10");
  });

  test("extracts acceptance criteria", () => {
    expect(parseCriteria("# Spec\n\n## Acceptance criteria\n1. One\n- Two\n\n## Notes\nNope")).toEqual(["One", "Two"]);
    expect(parseCriteria("# Spec")).toEqual([]);
    expect(parseVerdict("Verdict: ACCEPT\n")).toBe("ACCEPT");
    expect(parseVerdict("No verdict here\n")).toBe("");
    const review = "## Acceptance matrix\n\n| Criterion | Status | Implementation evidence | Test evidence |\n| --- | --- | --- | --- |\n| AC1 | PASS | code path | bun test |\n| AC2 | PASS | behavior | typecheck |\n";
    expect(hasPassingMatrix(review, 2)).toBe(true);
    expect(hasPassingMatrix(review.replace("| AC2 | PASS |", "| AC2 | FAIL |"), 2)).toBe(false);
  });

  test("derives report framing from the spec", () => {
    expect(
      reportFraming(
        "# Add chat retries\n\n## Problem\nUsers lose messages when the transport flakes.\n\n## Outcome\nFailed sends retry without duplicating messages.\n",
        "chat-retries",
      ),
    ).toEqual({
      title: "Add chat retries",
      subtitle: "Failed sends retry without duplicating messages.",
    });
    expect(reportFraming("# Config fallback\n\n## Problem\n- Missing config crashes startup.\n", "config-fallback")).toEqual({
      title: "Config fallback",
      subtitle: "Missing config crashes startup.",
    });
    expect(reportFraming("# <Concise title>\n\n## Acceptance criteria\n1. First useful criterion.\n", "fallback-slug")).toEqual({
      title: "Fallback Slug",
      subtitle: "First useful criterion.",
    });
    expect(reportFraming("# <Concise title>\n\n## Outcome\n<The observable end state>\n", "fallback-slug")).toEqual({
      title: "Fallback Slug",
      subtitle: "Outcome, review findings, and residual risk for Fallback Slug.",
    });
  });

  test("renders a useful default screen", () => {
    expect(welcome()).toContain("____/ /__");
    expect(welcome()).toContain("Common commands:");
    expect(welcome()).toContain("devloop .specs/change.md");
    expect(welcome()).toContain("--create-pr");
    expect(welcome()).toContain("bun scripts/install.ts");
  });
});

describe("loop", () => {
  test("accepts and writes core artifacts", async () => {
    const { repo, state } = await fixture("accept");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo);
    const worktree = result.worktree;

    expect(result.status).toBe("accepted");
    expect(result.passes).toBe(1);
    expect(result.branch).toBe("feat/change");
    expect(result.commit).toMatch(/^[0-9a-f]+$/);
    expect(result.commitMessage).toBe("feat: change");
    expect(result.commits).toEqual([{ pass: 1, commit: result.commit, message: "feat: change", paths: ["feature.txt"] }]);
    expect(result.sourceRepo).toBe(repo);
    expect(worktree).not.toBe(repo);
    await exists(path.join(worktree, ".codex/specs/change.md"));
    await exists(path.join(worktree, ".codex/tracks/change.md"));
    await exists(path.join(worktree, ".codex/reviews/change-r1.md"));
    await exists(path.join(worktree, ".codex/reports/change.html"));
    await exists(path.join(worktree, ".codex/logs/change-naming.log"));
    expect(result.coder).toBe("codex");
    expect(result.reviewer).toBe("claude");
    expect(await readFile(path.join(worktree, ".codex/sessions/change-coder-codex.id"), "utf8")).toContain("00000000-0000-4000-8000-000000000001");
    expect(await readFile(path.join(worktree, ".codex/tracks/change.md"), "utf8")).toContain("- strict: true");
    expect(await readFile(path.join(worktree, ".codex/tracks/change.md"), "utf8")).toContain("- create-pr: false");
    expect(await readFile(path.join(worktree, ".codex/tracks/change.md"), "utf8")).toContain("- coder: codex");
    expect(await readFile(path.join(worktree, ".codex/tracks/change.md"), "utf8")).toContain("- reviewer: claude");
    expect(await readFile(path.join(worktree, ".codex/tracks/change.md"), "utf8")).toContain(`- source-repo: ${repo}`);
    expect(await readFile(path.join(worktree, ".codex/reviews/change-r1.md"), "utf8")).toContain("| AC1 | PASS | mock evidence | mock test |");
    const codexArgs = await readFile(path.join(state, "codex-args.log"), "utf8");
    expect(codexArgs.split(/\r?\n/, 1)[0]).toBe(`exec -s read-only -C ${repo} -`);
    expect(codexArgs).toContain(`exec --dangerously-bypass-approvals-and-sandbox -C ${worktree} -`);
    expect((await Bun.$`git -C ${repo} branch --show-current`.text()).trim()).toBe("main");
    expect((await Bun.$`git -C ${worktree} branch --show-current`.text()).trim()).toBe("feat/change");
    expect((await Bun.$`git -C ${worktree} log -1 --format=%s`.text()).trim()).toBe("feat: change");
    expect(await Bun.$`git -C ${worktree} show --name-only --format= HEAD`.text()).toContain("feature.txt");
    expect(await Bun.$`git -C ${worktree} show --name-only --format= HEAD`.text()).not.toContain(".codex/");
    const reportPrompt = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    expect(reportPrompt).toContain("Coder: Codex");
    expect(reportPrompt).toContain("Reviewer: Claude Code");
    expect(reportPrompt).toContain("Coder session: 00000000-0000-4000-8000-000000000001");
    expect(reportPrompt).toContain("Final branch: feat/change");
    expect(reportPrompt).toContain(`Worktree: ${worktree}`);
    expect(reportPrompt).toContain(`Local commit: ${result.commit}`);
    expect(reportPrompt).toContain("Commit message: feat: change");
    expect(reportPrompt).toContain(`- pass 1 ${result.commit} feat: change (feature.txt)`);
    expect(reportPrompt).toContain("Pull request: none");
    expect(reportPrompt).toContain("Pull request error: none");
    expect(reportPrompt).toContain("Title: Fixture spec");
    expect(reportPrompt).toContain("Subtitle: The loop runs deterministically under test.");
    expect(reportPrompt).toContain("Haiku: Compose a three-line haiku");
    expect(reportPrompt).toContain("Haiku topic: Fixture spec - The loop runs deterministically under test.");
    expect(reportPrompt).toContain("rendered immediately after the subtitle before Metadata");
    expect(reportPrompt).toContain("The subtitle must be specific to this work");
    expect(reportPrompt).toContain("| Criterion | Status | Implementation evidence | Test evidence |");
    expect(reportPrompt).toContain("## Review flags");
    expect(reportPrompt).toContain("Silent decision:");
    expect(reportPrompt).toContain("Scope drift:");
    expect(reportPrompt).toContain("Missing test:");
    expect(reportPrompt).toContain("Flag scope drift when the diff changes behavior");
    expect(reportPrompt).toContain("Use UNCLEAR only when spec ambiguity prevents a defensible ACCEPT or REJECT");
    expect(events).toContainEqual({ type: "done", id: "naming", ok: true, detail: "feat/change" });
    expect(events).toContainEqual({ type: "done", id: "worktree", ok: true, detail: worktree });
    expect(events).toContainEqual({ type: "done", id: "commit-1", ok: true, detail: "1 commit" });
    expect(events.some((event) => event.type === "gate" && event.name === "acceptance criteria" && event.ok)).toBe(true);
    expect(events).toContainEqual({ type: "log", id: "coder-1", line: "codex-tail" });
  });

  test("rejects then accepts with resumed sessions", async () => {
    const { repo, state } = await fixture("reject-accept");
    process.env.DEVLOOP_TEST_VERDICTS = "REJECT,ACCEPT";
    const { result } = await run(repo, { max: 3 });

    expect(result.status).toBe("accepted");
    expect(result.passes).toBe(2);
    expect(result.commits.map((item) => item.message)).toEqual(["feat: change", "fix: change"]);
    expect(await readFile(path.join(result.worktree, ".codex/reviews/change-r1.md"), "utf8")).toContain("Verdict: REJECT");
    expect(await readFile(path.join(result.worktree, ".codex/reviews/change-r2.md"), "utf8")).toContain("Verdict: ACCEPT");
    expect(await readFile(path.join(state, "codex-args.log"), "utf8")).toContain("exec resume --dangerously-bypass-approvals-and-sandbox 00000000-0000-4000-8000-000000000001 -");
  });

  test("supports swapping coder and reviewer agents", async () => {
    const { repo, state } = await fixture("swapped-agents");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { coder: "claude", reviewer: "codex" });

    expect(result.status).toBe("accepted");
    expect(result.coder).toBe("claude");
    expect(result.reviewer).toBe("codex");
    expect(await readFile(path.join(result.worktree, ".codex/tracks/change.md"), "utf8")).toContain("- coder: claude");
    expect(await readFile(path.join(result.worktree, ".codex/tracks/change.md"), "utf8")).toContain("- reviewer: codex");
    const claudePrompts = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    const codexPrompts = await readFile(path.join(state, "codex-prompts.log"), "utf8");
    expect(claudePrompts).toContain("Work item naming task.");
    expect(claudePrompts).toContain("You are implementing against an approved spec.");
    expect(codexPrompts).toContain("You are reviewing a Claude Code implementation.");
    expect(codexPrompts).toContain("Coder: Claude Code");
    expect(codexPrompts).toContain("Reviewer: Codex");
    expect(await readFile(path.join(state, "codex-args.log"), "utf8")).toContain("exec resume --dangerously-bypass-approvals-and-sandbox 00000000-0000-4000-8000-000000000001 -");
    expect(events).toContainEqual({ type: "log", id: "coder-1", line: "claude-tail" });
  });

  test("stalls on repeated reject findings", async () => {
    const { repo } = await fixture("stall");
    process.env.DEVLOOP_TEST_VERDICTS = "REJECT,REJECT";
    const { result } = await run(repo, { max: 5 });

    expect(result.status).toBe("stalled");
    expect(result.passes).toBe(2);
  });

  test("supports markdown reports", async () => {
    const { repo, state } = await fixture("markdown");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo, { reportFormat: "markdown" });

    expect(result.report).toBe(".codex/reports/change.md");
    await exists(path.join(result.worktree, ".codex/reports/change.md"));
    expect(await exists(path.join(result.worktree, ".codex/reports/change.html"), false)).toBe(false);
    expect(await readFile(path.join(state, "claude-prompts.log"), "utf8")).toContain("in markdown");
  });

  test("isolates default runs from files dirty before the run", async () => {
    const { repo } = await fixture("dirty-before");
    await writeFile(path.join(repo, "dirty.txt"), "do not commit\n");
    await writeFile(path.join(repo, "old.txt"), "old\n");
    await Bun.$`git -C ${repo} add old.txt`.quiet();
    await Bun.$`git -C ${repo} commit -q -m old`.quiet();
    await Bun.$`git -C ${repo} mv old.txt renamed.txt`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(await Bun.$`git -C ${result.worktree} show --name-only --format= HEAD`.text()).toContain("feature.txt");
    expect(await Bun.$`git -C ${result.worktree} show --name-only --format= HEAD`.text()).not.toContain("dirty.txt");
    expect(await Bun.$`git -C ${result.worktree} show --name-only --format= HEAD`.text()).not.toContain("renamed.txt");
    expect(await exists(path.join(result.worktree, "dirty.txt"), false)).toBe(false);
    expect(await Bun.$`git -C ${repo} status --short -- dirty.txt`.text()).toContain("?? dirty.txt");
    expect(await Bun.$`git -C ${repo} status --short -- renamed.txt`.text()).toContain("renamed.txt");
  });

  test("supports opting out and running in the current worktree", async () => {
    const { repo, state } = await fixture("in-place");
    await writeFile(path.join(repo, "dirty.txt"), "do not commit\n");
    await writeFile(path.join(repo, "old.txt"), "old\n");
    await Bun.$`git -C ${repo} add old.txt`.quiet();
    await Bun.$`git -C ${repo} commit -q -m old`.quiet();
    await Bun.$`git -C ${repo} mv old.txt renamed.txt`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { worktree: false });

    expect(result.status).toBe("accepted");
    expect(result.worktree).toBe(repo);
    expect(result.sourceRepo).toBe(repo);
    expect(await readFile(path.join(state, "codex-args.log"), "utf8")).toContain(`exec --dangerously-bypass-approvals-and-sandbox -C ${repo} -`);
    expect((await Bun.$`git -C ${repo} branch --show-current`.text()).trim()).toBe("feat/change");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).toContain("feature.txt");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).not.toContain("dirty.txt");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).not.toContain("renamed.txt");
    expect(await Bun.$`git -C ${repo} status --short -- dirty.txt`.text()).toContain("?? dirty.txt");
    expect(await Bun.$`git -C ${repo} status --short -- renamed.txt`.text()).toContain("renamed.txt");
    expect(events.some((event) => event.type === "step" && event.id === "worktree")).toBe(false);
  });

  test("does not create an in-place branch when a coder pass has no eligible changes", async () => {
    const { repo } = await fixture("in-place-no-changes");
    process.env.DEVLOOP_TEST_NO_CODE_CHANGE = "1";
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { worktree: false });

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("main");
    expect(result.commit).toBe("");
    expect(result.commits).toEqual([]);
    expect((await Bun.$`git -C ${repo} branch --show-current`.text()).trim()).toBe("main");
    expect(events).toContainEqual({ type: "done", id: "commit-1", ok: true, detail: "no changes" });
  });

  test("reports commit errors", async () => {
    const { repo } = await fixture("commit-error");
    await writeFile(path.join(repo, ".git/hooks/pre-commit"), "#!/usr/bin/env bash\necho 'pre-commit blocked commit' >&2\nexit 1\n", { mode: 0o755 });
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo);

    expect(result.status).toBe("commit-error");
    expect(events).toContainEqual({ type: "done", id: "commit-1", ok: false, detail: "pre-commit blocked commit" });
  });

  test("creates one bundled commit per coder pass", async () => {
    const { repo } = await fixture("multi-file-pass");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_MULTI_COMMIT = "1";
    const { result, events } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(result.commits).toEqual([{ pass: 1, commit: result.commit, message: "feat: change", paths: ["api.txt", "ui.txt"] }]);
    expect(result.commitMessage).toBe("feat: change");
    expect((await Bun.$`git -C ${result.worktree} log --format=%s --reverse main..HEAD`.text()).trim()).toBe("feat: change");
    expect(events).toContainEqual({ type: "done", id: "commit-1", ok: true, detail: "1 commit" });
  });

  test("optionally pushes and opens a pull request", async () => {
    const { repo, state } = await fixture("create-pr");
    const remote = path.join(path.dirname(repo), "remote.git");
    await Bun.$`git init -q --bare ${remote}`.quiet();
    await Bun.$`git -C ${repo} remote add origin ${remote}`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { createPr: true });

    expect(result.status).toBe("accepted");
    expect(result.pullRequest).toBe("https://github.com/example/repo/pull/42");
    expect(result.pullRequestError).toBe("");
    expect(await Bun.$`git -C ${repo} ls-remote --heads origin feat/change`.text()).toContain("refs/heads/feat/change");
    expect(await readFile(path.join(state, "gh-args.log"), "utf8")).toBe("pr create --fill --base main --head feat/change\n");
    expect(await readFile(path.join(state, "gh-pwd.log"), "utf8")).toBe(`${result.worktree}\n`);
    expect(await readFile(path.join(result.worktree, ".codex/tracks/change.md"), "utf8")).toContain("- create-pr: true");
    const reportPrompt = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    expect(reportPrompt).toContain("Pull request: https://github.com/example/repo/pull/42");
    expect(reportPrompt).toContain("- pull request: https://github.com/example/repo/pull/42");
    expect(events).toContainEqual({ type: "done", id: "pull-request", ok: true, detail: "https://github.com/example/repo/pull/42" });
  });

  test("reports pull request publishing failures", async () => {
    const { repo, state } = await fixture("create-pr-fail");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { createPr: true });

    expect(result.status).toBe("pr-error");
    expect(result.pullRequest).toBe("");
    expect(result.pullRequestError).toContain("origin");
    const error = result.pullRequestError ?? "";
    expect(events).toContainEqual({ type: "done", id: "pull-request", ok: false, detail: error });
    const reportPrompt = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    expect(reportPrompt).toContain("Result: pr-error");
    expect(reportPrompt).toContain("Pull request: none");
    expect(reportPrompt).toContain("Pull request error:");
  });

  test("reports a pushed branch when pull request creation fails after push", async () => {
    const { repo, state } = await fixture("create-pr-after-push-fail");
    const remote = path.join(path.dirname(repo), "remote.git");
    await Bun.$`git init -q --bare ${remote}`.quiet();
    await Bun.$`git -C ${repo} remote add origin ${remote}`.quiet();
    process.env.DEVLOOP_TEST_FAIL_GH = "1";
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo, { createPr: true });

    expect(result.status).toBe("pr-error");
    expect(result.pullRequestError).toContain("pushed origin/feat/change");
    expect(result.pullRequestError).toContain("gh blocked");
    expect(await Bun.$`git -C ${repo} ls-remote --heads origin feat/change`.text()).toContain("refs/heads/feat/change");
    const reportPrompt = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    expect(reportPrompt).toContain("pushed origin/feat/change");
  });

  test("uses a suffixed branch when the default branch exists", async () => {
    const { repo } = await fixture("branch-exists");
    await Bun.$`git -C ${repo} branch feat/change`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("feat/change-2");
    expect(path.basename(result.worktree)).toBe("repo-change-2");
  });

  test("uses a suffixed worktree path when the default path exists", async () => {
    const { repo } = await fixture("worktree-path-exists");
    await mkdir(path.join(path.dirname(repo), "repo-change"), { recursive: true });
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(path.basename(result.worktree)).toBe("repo-change-2");
  });

  test("uses codex-derived artifact names and preserves invocation repo ownership", async () => {
    const work = await fixture("space-work", undefined, "change with spaces.md");
    const specOnly = await fixture("space-spec", undefined, "external spec.md");
    process.env.PATH = `${work.bin}:${oldPath}`;
    process.env.DEVLOOP_TEST_STATE = work.state;
    process.env.DEVLOOP_TEST_VERDICTS = "REJECT,ACCEPT";

    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"feat","slug":"change-with-spaces","breaking":false}';
    const spaced = await runDevloop({ spec: work.specPath, max: 2, reportFormat: "html", strict: true, worktree: true, cwd: work.repo, ...defaultAgents });
    expect(spaced.status).toBe("accepted");
    await exists(path.join(spaced.worktree, ".codex/reviews/change-with-spaces-r2.md"));

    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"feat","slug":"external-spec","breaking":false}';
    const external = await runDevloop({ spec: specOnly.specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: work.repo, ...defaultAgents });
    expect(external.status).toBe("accepted");
    await exists(path.join(external.worktree, ".codex/tracks/external-spec.md"));
    expect(await exists(path.join(work.repo, ".codex"), false)).toBe(false);
    expect(await exists(path.join(specOnly.repo, ".codex"), false)).toBe(false);
  });

  test("uses codex-derived breaking work names", async () => {
    const spec = [
      "---",
      "type: fix",
      "breaking: true",
      "---",
      "",
      "# Minimal AI SDK chat orchestration",
      "",
      "## Acceptance criteria",
      "1. The loop runs deterministically under test.",
      "",
    ].join("\n");
    const { repo, specPath } = await fixture("dated-spec", spec, "2026-05-26-minimal-ai-sdk-chat-orchestration.md");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"feat","slug":"minimal-ai-sdk-chat-orchestration","breaking":false}';
    const result = await runDevloop({ spec: specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents });

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("fix!/minimal-ai-sdk-chat-orchestration");
    expect(result.commitMessage).toBe("fix!: minimal-ai-sdk-chat-orchestration");
    expect(path.basename(result.worktree)).toBe("repo-minimal-ai-sdk-chat-orchestration");
    await exists(path.join(result.worktree, ".codex/specs/minimal-ai-sdk-chat-orchestration.md"));
    await exists(path.join(result.worktree, ".codex/tracks/minimal-ai-sdk-chat-orchestration.md"));
    expect(await readFile(path.join(result.worktree, ".codex/tracks/minimal-ai-sdk-chat-orchestration.md"), "utf8")).toContain("- breaking: true");
  });

  test("uses complete frontmatter names without a codex naming call", async () => {
    const spec = [
      "---",
      "type: chore",
      "slug: readme-refresh",
      "breaking: false",
      "---",
      "",
      "# Refresh README",
      "",
      "## Acceptance criteria",
      "1. The loop runs deterministically under test.",
      "",
    ].join("\n");
    const { repo, state, specPath } = await fixture("frontmatter-name", spec, "ignored-filename.md");
    process.env.DEVLOOP_TEST_FAIL_NAMING = "1";
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const result = await runDevloop({ spec: specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents });

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("chore/readme-refresh");
    expect(await readFile(path.join(state, "codex-prompts.log"), "utf8")).not.toContain("Work item naming task.");
  });

  test("parses noisy codex naming output", async () => {
    const { repo } = await fixture("noisy-name");
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"fix","slug":"noisy-json","breaking":false}';
    process.env.DEVLOOP_TEST_NOISY_NAMING = "1";
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const result = await runDevloop({ spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents });

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("fix/noisy-json");
    expect(await readFile(path.join(result.worktree, ".codex/logs/noisy-json-naming.log"), "utf8")).toContain("{not json}");
  });

  test("uses codex-derived fix and chore work names", async () => {
    const fix = await fixture("fix-prefix", undefined, "fix-null-check.md");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"fix","slug":"null-check","breaking":false}';
    expect((await runDevloop({ spec: fix.specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: fix.repo, ...defaultAgents })).branch).toBe("fix/null-check");

    const chore = await fixture("chore-prefix", undefined, "docs-readme-refresh.md");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"chore","slug":"readme-refresh","breaking":false}';
    expect((await runDevloop({ spec: chore.specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: chore.repo, ...defaultAgents })).branch).toBe("chore/readme-refresh");
  });

  test("rejects invalid codex-derived work names", async () => {
    const { repo } = await fixture("bad-name");
    process.env.DEVLOOP_TEST_WORK_ITEM = '{"type":"docs","slug":"feat-bad-name","breaking":false}';

    await expect(run(repo)).rejects.toThrow("naming log:");
  });

  test("rejects invalid explicit breaking metadata", async () => {
    const spec = [
      "---",
      "breaking: maybe",
      "---",
      "",
      "# Bad metadata",
      "",
      "## Acceptance criteria",
      "1. The loop runs deterministically under test.",
      "",
    ].join("\n");
    const { repo, specPath } = await fixture("bad-breaking", spec);

    await expect(runDevloop({ spec: specPath, max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents })).rejects.toThrow("frontmatter breaking must be true or false");
  });

  test("requires acceptance criteria in strict mode", async () => {
    const { repo } = await fixture("no-criteria", "# Spec\n");
    await expect(run(repo)).rejects.toThrow("strict mode requires ## Acceptance criteria");
    await expect(runDevloop({ spec: path.join(repo, ".specs/missing.md"), max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents })).rejects.toThrow("usage:");
  });

  test("allows missing criteria only when strict is off", async () => {
    const { repo } = await fixture("loose", "# Spec\n");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo, { strict: false });

    expect(result.status).toBe("accepted");
    expect(events).toContainEqual({ type: "gate", name: "acceptance criteria", ok: false, detail: "0 found" });
  });

  test("turns strict accepts without matrix into unclear", async () => {
    const { repo } = await fixture("no-matrix");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    process.env.DEVLOOP_TEST_NO_MATRIX = "1";
    const { result } = await run(repo);

    expect(result.status).toBe("unclear");
    expect(result.passes).toBe(1);
  });

  test("handles agent and review failures", async () => {
    const codex = await fixture("codex-fail");
    process.env.DEVLOOP_TEST_FAIL_CODEX = "1";
    expect((await run(codex.repo)).result.status).toBe("coder-error");
    delete process.env.DEVLOOP_TEST_FAIL_CODEX;

    const claude = await fixture("claude-fail");
    process.env.DEVLOOP_TEST_FAIL_CLAUDE = "1";
    expect((await run(claude.repo)).result.status).toBe("reviewer-error");
    delete process.env.DEVLOOP_TEST_FAIL_CLAUDE;

    const missing = await fixture("missing-review");
    process.env.DEVLOOP_TEST_NO_REVIEW = "1";
    expect((await run(missing.repo)).result.status).toBe("review-missing");
    delete process.env.DEVLOOP_TEST_NO_REVIEW;

    const noVerdict = await fixture("no-verdict");
    process.env.DEVLOOP_TEST_NO_VERDICT = "1";
    expect((await run(noVerdict.repo)).result.status).toBe("no-verdict");
    delete process.env.DEVLOOP_TEST_NO_VERDICT;
  });

  test("handles unclear verdicts and missing executables", async () => {
    const unclear = await fixture("unclear");
    process.env.DEVLOOP_TEST_VERDICTS = "UNCLEAR";
    expect((await run(unclear.repo)).result.status).toBe("unclear");

    const missingClaude = await fixture("missing-claude-bin");
    await rm(path.join(missingClaude.repo, "../bin/claude"), { force: true });
    process.env.PATH = `${path.join(missingClaude.repo, "../bin")}:/usr/bin:/bin`;
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    expect((await run(missingClaude.repo)).result.status).toBe("reviewer-error");
  });

  test("falls back to main when no base branch exists", async () => {
    const { repo } = await fixture("no-base");
    await Bun.$`git -C ${repo} branch -m topic`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const result = await runDevloop({ spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents });
    expect(result.status).toBe("accepted");
    expect(await readFile(path.join(result.worktree, ".codex/tracks/change.md"), "utf8")).toContain("- base: main");
  });

  test("uses origin head as the base branch when available", async () => {
    const { repo } = await fixture("origin-head");
    await Bun.$`git -C ${repo} update-ref refs/remotes/origin/trunk HEAD`.quiet();
    await Bun.$`git -C ${repo} symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const result = await runDevloop({ spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents });

    expect(result.status).toBe("accepted");
    expect(await readFile(path.join(result.worktree, ".codex/tracks/change.md"), "utf8")).toContain("- base: trunk");
  });
});

async function fixture(name: string, spec = "# Fixture spec\n\n## Acceptance criteria\n1. The loop runs deterministically under test.\n", specName = "change.md") {
  const dir = path.join(root, name);
  const repo = path.join(dir, "repo");
  const bin = path.join(dir, "bin");
  const state = path.join(dir, "state");
  await Bun.$`mkdir -p ${repo}/.specs ${bin} ${state}`.quiet();
  await Bun.$`git init -q ${repo}`.quiet();
  await Bun.$`git -C ${repo} symbolic-ref HEAD refs/heads/main`.quiet();
  await writeFile(path.join(repo, "README.md"), "# Fixture\n");
  const specPath = path.join(repo, ".specs", specName);
  await writeFile(specPath, spec);
  await Bun.$`git -C ${repo} config user.email devloop-test@example.com`.quiet();
  await Bun.$`git -C ${repo} config user.name "devloop test"`.quiet();
  await Bun.$`git -C ${repo} add README.md`.quiet();
  await Bun.$`git -C ${repo} commit -q -m init`.quiet();
  await installMocks(bin);
  process.env.PATH = `${bin}:${oldPath}`;
  process.env.DEVLOOP_TEST_STATE = state;
  return { repo: await real(repo), state, bin, specPath };
}

async function installMocks(bin: string) {
  await writeFile(
    path.join(bin, "codex"),
    `#!/usr/bin/env bash
set -euo pipefail
prompt=$(cat)
mkdir -p "$DEVLOOP_TEST_STATE"
printf '%s\\n' "$*" >> "$DEVLOOP_TEST_STATE/codex-args.log"
printf '%s\\n---\\n' "$prompt" >> "$DEVLOOP_TEST_STATE/codex-prompts.log"
if [[ "$prompt" == Work\\ item\\ naming\\ task.* ]]; then
  [[ -z "\${DEVLOOP_TEST_FAIL_NAMING:-}" ]] || exit 42
  [[ -z "\${DEVLOOP_TEST_NOISY_NAMING:-}" ]] || printf 'trace {"ignore":true}\\n'
  if [[ -n "\${DEVLOOP_TEST_WORK_ITEM:-}" ]]; then
    printf '%s\\n' "$DEVLOOP_TEST_WORK_ITEM"
  else
    printf '%s\\n' '{"type":"feat","slug":"change","breaking":false}'
  fi
  [[ -z "\${DEVLOOP_TEST_NOISY_NAMING:-}" ]] || printf 'tail {not json}\\n'
  exit 0
fi
[[ -z "\${DEVLOOP_TEST_FAIL_CODEX:-}" ]] || exit 42
if [[ "$prompt" == *"Output path:"* ]]; then
  [[ -z "\${DEVLOOP_TEST_NO_REVIEW:-}" ]] || exit 0
  review_file=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Output path: /{print $2; exit}')
  count=$(( $(cat "$DEVLOOP_TEST_STATE/codex-review-count" 2>/dev/null || echo 0) + 1 ))
  printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/codex-review-count"
  IFS=',' read -r -a verdicts <<< "\${DEVLOOP_TEST_VERDICTS:-ACCEPT}"
  verdict="\${verdicts[$(( count <= \${#verdicts[@]} ? count - 1 : \${#verdicts[@]} - 1 ))]}"
  mkdir -p "$(dirname "$review_file")"
  {
    printf '# Review %s\\n\\n' "$count"
    [[ -n "\${DEVLOOP_TEST_NO_VERDICT:-}" ]] || printf 'Verdict: %s\\n\\n' "$verdict"
    if [[ -z "\${DEVLOOP_TEST_NO_MATRIX:-}" ]]; then
      printf '## Acceptance matrix\\n\\n'
      printf '| Criterion | Status | Implementation evidence | Test evidence |\\n'
      printf '| --- | --- | --- | --- |\\n'
      printf '| AC1 | PASS | mock evidence | mock test |\\n\\n'
    fi
    printf '## Review flags\\n\\n- Silent decision: absent - None\\n- Scope drift: absent - None\\n- Missing test: absent - None\\n\\n'
    printf '## Findings\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. [must-fix] devloop.ts:1 - repeated fixture finding. Root cause: mock review. Principle: deterministic retry behavior.\\n\\n'; fi
    printf '## Missing tests\\n\\n- None\\n\\n## Fix instructions\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. Fix the repeated fixture finding.\\n\\n'; fi
    printf '## Notes\\n\\n- None\\n'
  } > "$review_file"
  printf 'To continue this session, run codex exec resume 00000000-0000-4000-8000-000000000001\\n'
  exit 0
fi
report_file=$(printf '%s\\n' "$prompt" | sed -n 's/^Write the report to \\([^ ]*\\).*/\\1/p' | head -n 1)
if [[ -n "$report_file" ]]; then
  mkdir -p "$(dirname "$report_file")"
  printf '# mock devloop report\\n' > "$report_file"
  printf 'To continue this session, run codex exec resume 00000000-0000-4000-8000-000000000001\\n'
  exit 0
fi
count=$(( $(cat "$DEVLOOP_TEST_STATE/codex-count" 2>/dev/null || echo 0) + 1 ))
printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/codex-count"
track=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Track: /{print $2; exit}')
[[ -z "$track" ]] || printf '\\n## Pass %s - mock codex\\n- verification: fixture\\n' "$count" >> "$track"
if [[ -z "\${DEVLOOP_TEST_NO_CODE_CHANGE:-}" ]]; then
  if [[ -n "\${DEVLOOP_TEST_MULTI_COMMIT:-}" ]]; then
    printf 'api pass %s\\n' "$count" >> api.txt
    printf 'ui pass %s\\n' "$count" >> ui.txt
  else
    printf 'feature pass %s\\n' "$count" >> feature.txt
  fi
fi
printf 'codex pass %s\\n' "$count"
printf 'To continue this session, run codex exec resume 00000000-0000-4000-8000-000000000001\\n'
printf 'codex-tail' >&2
`,
    { mode: 0o755 },
  );
  await writeFile(
    path.join(bin, "claude"),
    `#!/usr/bin/env bash
set -euo pipefail
[[ -z "\${DEVLOOP_TEST_FAIL_CLAUDE:-}" ]] || exit 43
prompt=$(cat)
mkdir -p "$DEVLOOP_TEST_STATE"
printf '%s\\n' "$*" >> "$DEVLOOP_TEST_STATE/claude-args.log"
printf '%s\\n---\\n' "$prompt" >> "$DEVLOOP_TEST_STATE/claude-prompts.log"
if [[ "$prompt" == Work\\ item\\ naming\\ task.* ]]; then
  [[ -z "\${DEVLOOP_TEST_FAIL_NAMING:-}" ]] || exit 42
  [[ -z "\${DEVLOOP_TEST_NOISY_NAMING:-}" ]] || printf 'trace {"ignore":true}\\n'
  if [[ -n "\${DEVLOOP_TEST_WORK_ITEM:-}" ]]; then
    printf '%s\\n' "$DEVLOOP_TEST_WORK_ITEM"
  else
    printf '%s\\n' '{"type":"feat","slug":"change","breaking":false}'
  fi
  [[ -z "\${DEVLOOP_TEST_NOISY_NAMING:-}" ]] || printf 'tail {not json}\\n'
  exit 0
fi
if [[ "$prompt" == *"Output path:"* ]]; then
  [[ -z "\${DEVLOOP_TEST_NO_REVIEW:-}" ]] || exit 0
  review_file=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Output path: /{print $2; exit}')
  count=$(( $(cat "$DEVLOOP_TEST_STATE/claude-review-count" 2>/dev/null || echo 0) + 1 ))
  printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/claude-review-count"
  IFS=',' read -r -a verdicts <<< "\${DEVLOOP_TEST_VERDICTS:-ACCEPT}"
  verdict="\${verdicts[$(( count <= \${#verdicts[@]} ? count - 1 : \${#verdicts[@]} - 1 ))]}"
  mkdir -p "$(dirname "$review_file")"
  {
    printf '# Review %s\\n\\n' "$count"
    [[ -n "\${DEVLOOP_TEST_NO_VERDICT:-}" ]] || printf 'Verdict: %s\\n\\n' "$verdict"
    if [[ -z "\${DEVLOOP_TEST_NO_MATRIX:-}" ]]; then
      printf '## Acceptance matrix\\n\\n'
      printf '| Criterion | Status | Implementation evidence | Test evidence |\\n'
      printf '| --- | --- | --- | --- |\\n'
      printf '| AC1 | PASS | mock evidence | mock test |\\n\\n'
    fi
    printf '## Review flags\\n\\n- Silent decision: absent - None\\n- Scope drift: absent - None\\n- Missing test: absent - None\\n\\n'
    printf '## Findings\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. [must-fix] devloop.ts:1 - repeated fixture finding. Root cause: mock review. Principle: deterministic retry behavior.\\n\\n'; fi
    printf '## Missing tests\\n\\n- None\\n\\n## Fix instructions\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. Fix the repeated fixture finding.\\n\\n'; fi
    printf '## Notes\\n\\n- None\\n'
  } > "$review_file"
else
  report_file=$(printf '%s\\n' "$prompt" | sed -n 's/^Write the report to \\([^ ]*\\).*/\\1/p' | head -n 1)
  if [[ -n "$report_file" ]]; then
    mkdir -p "$(dirname "$report_file")"
    printf '# mock devloop report\\n' > "$report_file"
  else
    count=$(( $(cat "$DEVLOOP_TEST_STATE/claude-count" 2>/dev/null || echo 0) + 1 ))
    printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/claude-count"
    track=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Track: /{print $2; exit}')
    [[ -z "$track" ]] || printf '\\n## Pass %s - mock claude\\n- verification: fixture\\n' "$count" >> "$track"
    if [[ -z "\${DEVLOOP_TEST_NO_CODE_CHANGE:-}" ]]; then
      if [[ -n "\${DEVLOOP_TEST_MULTI_COMMIT:-}" ]]; then
        printf 'api pass %s\\n' "$count" >> api.txt
        printf 'ui pass %s\\n' "$count" >> ui.txt
      else
        printf 'feature pass %s\\n' "$count" >> feature.txt
      fi
    fi
    printf 'claude pass %s\\n' "$count"
    printf 'claude-tail' >&2
  fi
fi
`,
    { mode: 0o755 },
  );
  await writeFile(
    path.join(bin, "gh"),
    `#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$DEVLOOP_TEST_STATE"
printf '%s\\n' "$*" >> "$DEVLOOP_TEST_STATE/gh-args.log"
printf '%s\\n' "$PWD" >> "$DEVLOOP_TEST_STATE/gh-pwd.log"
[[ -z "\${DEVLOOP_TEST_FAIL_GH:-}" ]] || { echo 'gh blocked' >&2; exit 42; }
printf 'https://github.com/example/repo/pull/42\\n'
`,
    { mode: 0o755 },
  );
}

async function run(repo: string, overrides: Partial<Options> = {}) {
  const events: Event[] = [];
  const result = await runDevloop(
    { spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, worktree: true, cwd: repo, ...defaultAgents, ...overrides },
    { event: (event) => void events.push(event) },
  );
  return { result, events };
}

async function exists(file: string, expected = true) {
  const ok = Boolean(await stat(file).catch(() => false));
  if (expected) expect(ok).toBe(true);
  return ok;
}

async function real(file: string) {
  return realpath(file);
}
