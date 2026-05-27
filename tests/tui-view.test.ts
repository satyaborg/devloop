import { describe, expect, test } from "bun:test";
import { view, type Row } from "../src/tui-view.ts";

const baseRow = {
  id: "step",
  title: "run tests",
  status: "run",
  detail: "running",
  lines: [],
  open: false,
} satisfies Row;

describe("tui view", () => {
  test("renders empty state with logo and help", () => {
    const output = view([], 0);

    expect(output).toContain("____/ /__");
    expect(output).toContain("enter toggles logs, j/k moves");
  });

  test("renders closed and open rows", () => {
    const closed = view([{ ...baseRow, lines: ["hidden"] }], 0);
    const open = view([{ ...baseRow, status: "ok", detail: "completed", lines: Array.from({ length: 82 }, (_, i) => `line-${i}`), open: true }], 0);

    expect(closed).toContain("> .. [+] run tests - running");
    expect(closed).not.toContain("hidden");
    expect(open).toContain("> ok [-] run tests - completed");
    expect(open).not.toContain("line-0");
    expect(open).toContain("line-81");
  });

  test("renders failed rows and result details", () => {
    const output = view([{ ...baseRow, status: "fail", detail: "failed" }], 0, {
      status: "commit-error",
      passes: 1,
      max: 5,
      report: ".codex/reports/change.html",
      track: ".codex/tracks/change.md",
      branch: "feat/change",
      commit: "",
      commitMessage: "",
      worktree: "/tmp/repo-change",
      sourceRepo: "/tmp/repo",
      codexSessionId: "codex-session",
      claudeSessionId: "claude-session",
    });

    expect(output).toContain("> !!     run tests - failed");
    expect(output).toContain("result:  commit-error");
    expect(output).toContain("commit:  none");
    expect(output).toContain("worktree: /tmp/repo-change");
    expect(output).toContain("report:  /tmp/repo-change/.codex/reports/change.html");
    expect(output).toContain("track:   /tmp/repo-change/.codex/tracks/change.md");
  });

  test("suppresses worktree details for in-place results", () => {
    const output = view([], 0, {
      status: "accepted",
      passes: 1,
      max: 5,
      report: ".codex/reports/change.html",
      track: ".codex/tracks/change.md",
      branch: "feat/change",
      commit: "abc123",
      commitMessage: "feat: change",
      worktree: "/tmp/repo",
      sourceRepo: "/tmp/repo",
      codexSessionId: "codex-session",
      claudeSessionId: "claude-session",
    });

    expect(output).not.toContain("worktree:");
    expect(output).toContain("report:  .codex/reports/change.html");
    expect(output).toContain("track:   .codex/tracks/change.md");
  });
});
