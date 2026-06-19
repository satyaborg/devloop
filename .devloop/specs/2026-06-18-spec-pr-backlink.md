---
status: draft
type: feat
created: 2026-06-18
pr: null
---

# Backlink specs to their pull request
Write the opened PR URL into the source spec's `pr:` frontmatter during `--create-pr` runs, so every spec records the PR that implemented it.

```mermaid
flowchart LR
  Current["Spec pr: null, PR URL known but discarded"] --> Change["--create-pr writes URL into source spec frontmatter"]
  Change --> Result["Spec pr: full PR URL"]
```

## Problem
Every spec carries a `pr: null` frontmatter slot, and `devloop --create-pr` already opens a draft PR and captures its URL in `$PULL_REQUEST` (`devloop:2267`), yet nothing ever writes that URL back into the spec. So `pr: null` stays `null` forever and there is no link from a spec to the PR that implemented it. The moment it hurts: revisiting a spec weeks later with no idea which PR (if any) shipped it, forcing a dig through devloop reports or `gh pr list` to reconnect the two.

## Outcome
After a successful `devloop --create-pr <spec>` run, the source spec file's frontmatter `pr:` field holds the full PR URL (e.g. `pr: https://github.com/owner/repo/pull/123`) instead of `pr: null`, and every other byte of the spec is unchanged.

## Scope
- In: `devloop` runtime — a new frontmatter write-back helper plus one call site at PR creation in the pass loop (`devloop:2267-2268`); a unit test in `scripts/devloop_test.sh`; `README.md` only if the documented `--create-pr` behavior changes.
- Out: runs without `--create-pr`; reconciling an existing/found PR on resume (the pre-loop `lookup_pull_request` at `devloop:2193`); manually-created PRs; updating the worktree spec copy (`$run_spec`); editing any frontmatter field other than `pr:` (including `status:`).

## Behavior
### Happy path
1. User runs `devloop --create-pr .devloop/specs/<spec>.md`.
2. devloop commits pass 1 and opens a draft PR; `$PULL_REQUEST` holds the URL.
3. devloop rewrites the source spec's frontmatter `pr:` line to `pr: <url>`.
4. The spec on disk now reads `pr: https://github.com/owner/repo/pull/123`; all other lines are untouched.

### Edge cases
- `pr:` already equals the PR URL: no write (idempotent; prevents churn across multiple committing passes in one run).
- `pr:` set to a different or stale URL: overwritten with the current run's PR URL.
- Frontmatter lacks a `pr:` line: insert `pr: <url>` before the closing `---`.
- Spec has no closing frontmatter delimiter (malformed/absent frontmatter): skip the write, leave the file unchanged, do not fail the run.
- Spec file is not writable / the write fails: emit a non-fatal note; run status is unaffected.
- Run without `--create-pr`: spec is untouched.

## Acceptance criteria
1. After a `--create-pr` run that opens PR URL `U`, the source spec's frontmatter `pr:` value equals `U` (full URL) and no other line in the spec changes.
2. Calling the helper when `pr:` already equals `U` leaves the file byte-for-byte identical (idempotent).
3. A spec whose frontmatter lacks a `pr:` line gains a `pr: U` line inside the frontmatter block; a spec with no closing frontmatter delimiter is left unchanged.
4. A run invoked without `--create-pr` leaves the spec's `pr:` field unchanged.
5. A failed backlink write (e.g. unwritable spec) does not change the run's exit status or final `STATUS`.
6. `bash scripts/devloop_test.sh` passes, including a new test that covers the helper.

## Test plan
- Red: add a unit test in `scripts/devloop_test.sh` that sources `devloop` and calls the new helper directly, mirroring the `frontmatter_value` block (`scripts/devloop_test.sh:438`). Point it at a temp spec containing `pr: null` and assert the `pr:` line becomes `U` while body and other frontmatter stay intact; add idempotency, missing-`pr:`-line, and malformed-frontmatter cases. Fails before implementation (helper undefined).
- Green: `bash scripts/devloop_test.sh` (the suite runs as a whole; there is no per-test filter).
- Full: `bash scripts/devloop_test.sh`.
- Coverage: the shell runtime has no in-repo line-coverage tool; coverage is the new test exercising the replace, idempotent, insert, and skip paths of the helper.

## Constraints
- Must: operate on the source spec (`$spec`, not `$run_spec`), modify only the frontmatter `pr:` line, and stay portable across macOS/Linux (awk to a temp file then `mv`, not GNU-only `sed -i`).
- Must: be best-effort and non-fatal — a backlink failure never aborts the run or changes its status.
- Avoid: new dependencies; touching the worktree spec copy; editing any field other than `pr:`; any rewrite that alters unrelated bytes or whitespace.
- Existing convention: name the writer to mirror the reader `frontmatter_value` (e.g. `set_frontmatter_pr`/`sync_spec_pr`), reuse `frontmatter_value pr` to read the current value for the idempotency check, and follow the existing `event_step`/`event_done` style if the write is surfaced.

## Notes
- Hook site: the pass loop immediately after the successful PR creation at `devloop:2267-2268`, inside `if [ "$create_pr" = true ] && [ -n "$PASS_COMMIT" ]`, where both `$spec` and `$PULL_REQUEST` are in scope. This branch runs on every committing pass, so the idempotency guard is what prevents repeat writes.
- Two spec copies exist at runtime: `$spec` (source, the user's canonical file — the backlink target) and `$run_spec` (worktree runtime copy at `.devloop/specs/<slug>.md`, not committed — leave alone).
- Scope was deliberately limited to `--create-pr` runs; resume / found-existing-PR reconciliation is excluded, so a resumed run whose PR already existed may not backlink a spec that was never backlinked in its original run. Track as a follow-up spec if that gap matters.
- Tests source `devloop` and call functions directly (`frontmatter_value` test at `scripts/devloop_test.sh:438`, `create_pull_request` test at `:463`), so the helper is unit-testable without invoking `gh`.
- `--in-place` runs modify `$spec` in the working tree; this is expected and consistent with CLAUDE.md guidance that devloop does not commit `.devloop/` spec artifacts.
- Gaps: 0.
