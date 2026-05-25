import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { parseArgs, parseCriteria, parseVerdict, runDevloop, welcome, type Event, type Options } from "../src/devloop.ts";

const root = await mkdtemp(path.join(tmpdir(), "devloop-test."));
let oldPath = process.env.PATH ?? "";

afterAll(async () => rm(root, { recursive: true, force: true }));
beforeEach(() => {
  oldPath = process.env.PATH ?? "";
  delete process.env.DEVLOOP_TEST_VERDICTS;
  delete process.env.DEVLOOP_TEST_STATE;
  delete process.env.DEVLOOP_TEST_NO_MATRIX;
  delete process.env.DEVLOOP_TEST_NO_REVIEW;
  delete process.env.DEVLOOP_TEST_NO_VERDICT;
  delete process.env.DEVLOOP_TEST_FAIL_CODEX;
  delete process.env.DEVLOOP_TEST_FAIL_CLAUDE;
});

describe("parsing", () => {
  test("parses options tightly", () => {
    expect(parseArgs(["--no-strict", "--report-format", "md", "spec.md", "08"], "/x")).toEqual({
      spec: "spec.md",
      max: 8,
      reportFormat: "markdown",
      strict: false,
      cwd: "/x",
    } satisfies Options);
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
  });

  test("renders a useful default screen", () => {
    expect(welcome()).toContain("▐▌▗▞▀▚▖");
    expect(welcome()).toContain("Common commands:");
    expect(welcome()).toContain("devloop .specs/change.md");
    expect(welcome()).toContain("bun scripts/install.ts");
  });
});

describe("loop", () => {
  test("accepts and writes core artifacts", async () => {
    const { repo, state } = await fixture("accept");
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result, events } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(result.passes).toBe(1);
    expect(result.branch).toBe("devloop/change");
    expect(result.commit).toMatch(/^[0-9a-f]+$/);
    expect(result.commitMessage).toBe("feat: change");
    await exists(path.join(repo, ".codex/tracks/change.md"));
    await exists(path.join(repo, ".codex/reviews/change-r1.md"));
    await exists(path.join(repo, ".codex/reports/change.html"));
    expect(await readFile(path.join(repo, ".codex/sessions/change-codex.id"), "utf8")).toContain("00000000-0000-4000-8000-000000000001");
    expect(await readFile(path.join(repo, ".codex/tracks/change.md"), "utf8")).toContain("- strict: true");
    expect(await readFile(path.join(repo, ".codex/reviews/change-r1.md"), "utf8")).toContain("- AC1: PASS");
    expect(await readFile(path.join(state, "codex-args.log"), "utf8")).toContain(`exec --dangerously-bypass-approvals-and-sandbox -C ${repo} -`);
    expect((await Bun.$`git -C ${repo} branch --show-current`.text()).trim()).toBe("devloop/change");
    expect((await Bun.$`git -C ${repo} log -1 --format=%s`.text()).trim()).toBe("feat: change");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).toContain("feature.txt");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).not.toContain(".codex/");
    const reportPrompt = await readFile(path.join(state, "claude-prompts.log"), "utf8");
    expect(reportPrompt).toContain("Codex session: 00000000-0000-4000-8000-000000000001");
    expect(reportPrompt).toContain("Final branch: devloop/change");
    expect(reportPrompt).toContain(`Local commit: ${result.commit}`);
    expect(reportPrompt).toContain("Commit message: feat: change");
    expect(events.some((event) => event.type === "gate" && event.name === "acceptance criteria" && event.ok)).toBe(true);
    expect(events).toContainEqual({ type: "log", id: "codex-1", line: "codex-tail" });
  });

  test("rejects then accepts with resumed sessions", async () => {
    const { repo, state } = await fixture("reject-accept");
    process.env.DEVLOOP_TEST_VERDICTS = "REJECT,ACCEPT";
    const { result } = await run(repo, { max: 3 });

    expect(result.status).toBe("accepted");
    expect(result.passes).toBe(2);
    expect(await readFile(path.join(repo, ".codex/reviews/change-r1.md"), "utf8")).toContain("Verdict: REJECT");
    expect(await readFile(path.join(repo, ".codex/reviews/change-r2.md"), "utf8")).toContain("Verdict: ACCEPT");
    expect(await readFile(path.join(state, "codex-args.log"), "utf8")).toContain("exec resume --dangerously-bypass-approvals-and-sandbox 00000000-0000-4000-8000-000000000001 -");
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
    await exists(path.join(repo, ".codex/reports/change.md"));
    expect(await exists(path.join(repo, ".codex/reports/change.html"), false)).toBe(false);
    expect(await readFile(path.join(state, "claude-prompts.log"), "utf8")).toContain("in markdown");
  });

  test("skips files dirty before the run when committing", async () => {
    const { repo } = await fixture("dirty-before");
    await writeFile(path.join(repo, "dirty.txt"), "do not commit\n");
    await writeFile(path.join(repo, "old.txt"), "old\n");
    await Bun.$`git -C ${repo} add old.txt`.quiet();
    await Bun.$`git -C ${repo} commit -q -m old`.quiet();
    await Bun.$`git -C ${repo} mv old.txt renamed.txt`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).toContain("feature.txt");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).not.toContain("dirty.txt");
    expect(await Bun.$`git -C ${repo} show --name-only --format= HEAD`.text()).not.toContain("renamed.txt");
    expect(await Bun.$`git -C ${repo} status --short -- dirty.txt`.text()).toContain("?? dirty.txt");
    expect(await Bun.$`git -C ${repo} status --short -- renamed.txt`.text()).toContain("renamed.txt");
  });

  test("reports commit errors", async () => {
    const { repo } = await fixture("commit-error");
    await writeFile(path.join(repo, ".git/hooks/pre-commit"), "#!/usr/bin/env bash\nexit 1\n", { mode: 0o755 });
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("commit-error");
  });

  test("uses a suffixed branch when the default branch exists", async () => {
    const { repo } = await fixture("branch-exists");
    await Bun.$`git -C ${repo} branch devloop/change`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const { result } = await run(repo);

    expect(result.status).toBe("accepted");
    expect(result.branch).toBe("devloop/change-2");
  });

  test("preserves spacey slugs and invocation repo ownership", async () => {
    const work = await fixture("space-work", undefined, "change with spaces.md");
    const specOnly = await fixture("space-spec", undefined, "external spec.md");
    process.env.PATH = `${work.bin}:${oldPath}`;
    process.env.DEVLOOP_TEST_STATE = work.state;
    process.env.DEVLOOP_TEST_VERDICTS = "REJECT,ACCEPT";

    const spaced = await runDevloop({ spec: work.specPath, max: 2, reportFormat: "html", strict: true, cwd: work.repo });
    expect(spaced.status).toBe("accepted");
    await exists(path.join(work.repo, ".codex/reviews/change with spaces-r2.md"));

    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    const external = await runDevloop({ spec: specOnly.specPath, max: 1, reportFormat: "html", strict: true, cwd: work.repo });
    expect(external.status).toBe("accepted");
    await exists(path.join(work.repo, ".codex/tracks/external spec.md"));
    expect(await exists(path.join(specOnly.repo, ".codex"), false)).toBe(false);
  });

  test("requires acceptance criteria in strict mode", async () => {
    const { repo } = await fixture("no-criteria", "# Spec\n");
    await expect(run(repo)).rejects.toThrow("strict mode requires ## Acceptance criteria");
    await expect(runDevloop({ spec: path.join(repo, ".specs/missing.md"), max: 1, reportFormat: "html", strict: true, cwd: repo })).rejects.toThrow("usage:");
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
    expect((await run(codex.repo)).result.status).toBe("codex-error");
    delete process.env.DEVLOOP_TEST_FAIL_CODEX;

    const claude = await fixture("claude-fail");
    process.env.DEVLOOP_TEST_FAIL_CLAUDE = "1";
    expect((await run(claude.repo)).result.status).toBe("claude-error");
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
    expect((await run(missingClaude.repo)).result.status).toBe("claude-error");
  });

  test("falls back to main when no base branch exists", async () => {
    const { repo } = await fixture("no-base");
    await Bun.$`git -C ${repo} branch -m topic`.quiet();
    process.env.DEVLOOP_TEST_VERDICTS = "ACCEPT";
    expect((await runDevloop({ spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, cwd: repo })).status).toBe("accepted");
    expect(await readFile(path.join(repo, ".codex/tracks/change.md"), "utf8")).toContain("- base: main");
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
[[ -z "\${DEVLOOP_TEST_FAIL_CODEX:-}" ]] || exit 42
prompt=$(cat)
mkdir -p "$DEVLOOP_TEST_STATE"
count=$(( $(cat "$DEVLOOP_TEST_STATE/codex-count" 2>/dev/null || echo 0) + 1 ))
printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/codex-count"
printf '%s\\n' "$*" >> "$DEVLOOP_TEST_STATE/codex-args.log"
printf '%s\\n---\\n' "$prompt" >> "$DEVLOOP_TEST_STATE/codex-prompts.log"
track=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Track: /{print $2; exit}')
[[ -z "$track" ]] || printf '\\n## Pass %s - mock codex\\n- verification: fixture\\n' "$count" >> "$track"
printf 'feature pass %s\\n' "$count" >> feature.txt
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
if [[ "$prompt" == *"Output path:"* ]]; then
  [[ -z "\${DEVLOOP_TEST_NO_REVIEW:-}" ]] || exit 0
  review_file=$(printf '%s\\n' "$prompt" | awk -F': ' '/^Output path: /{print $2; exit}')
  count=$(( $(cat "$DEVLOOP_TEST_STATE/claude-review-count" 2>/dev/null || echo 0) + 1 ))
  printf '%s\\n' "$count" > "$DEVLOOP_TEST_STATE/claude-review-count"
  IFS=',' read -r -a verdicts <<< "\${DEVLOOP_TEST_VERDICTS:-ACCEPT}"
  verdict="\${verdicts[$(( count <= \${#verdicts[@]} ? count - 1 : \${#verdicts[@]} - 1 ))]}"
  mkdir -p "$(dirname "$review_file")"
  {
    printf '# Claude review %s\\n\\n' "$count"
    [[ -n "\${DEVLOOP_TEST_NO_VERDICT:-}" ]] || printf 'Verdict: %s\\n\\n' "$verdict"
    if [[ -z "\${DEVLOOP_TEST_NO_MATRIX:-}" ]]; then
      printf '## Acceptance matrix\\n\\n'
      printf -- '- AC1: PASS - mock evidence\\n\\n'
    fi
    printf '## Findings\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. [must-fix] devloop.ts:1 - repeated fixture finding. Root cause: mock review. Principle: deterministic retry behavior.\\n\\n'; fi
    printf '## Missing tests\\n\\n- None\\n\\n## Fix instructions\\n\\n'
    if [[ "$verdict" == "ACCEPT" ]]; then printf 'None\\n\\n'; else printf '1. Fix the repeated fixture finding.\\n\\n'; fi
    printf '## Notes\\n\\n- None\\n'
  } > "$review_file"
else
  report_file=$(printf '%s\\n' "$prompt" | sed -n 's/^Write the report to \\([^ ]*\\).*/\\1/p' | head -n 1)
  [[ -z "$report_file" ]] || { mkdir -p "$(dirname "$report_file")"; printf '# mock devloop report\\n' > "$report_file"; }
fi
`,
    { mode: 0o755 },
  );
}

async function run(repo: string, overrides: Partial<Options> = {}) {
  const events: Event[] = [];
  const result = await runDevloop(
    { spec: path.join(repo, ".specs/change.md"), max: 1, reportFormat: "html", strict: true, cwd: repo, ...overrides },
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
