# devloop

Spec in, accepted code out. Codex implements, Claude reviews, loop until ACCEPT, stall, unclear, error, or max turns.

```sh
devloop [--plain|--tui] [--no-strict] [--report-format html|markdown] path/to/spec.md [max=5]
bun src/cli.ts [--plain|--tui] [--no-strict] [--report-format html|markdown] path/to/spec.md [max=5]
```

## Defaults

- strict mode is on
- HTML report output is on
- max turns defaults to 5 and is clamped to 1-10
- interactive terminals use the OpenTUI view
- non-TTY runs use plain output
- accepted runs create a local `devloop/<slug>` branch and a local Conventional Commit

Use `--plain` for CI or debugging. Use `--tui` to force the collapsed terminal UI. Use `--no-strict` only when you deliberately want to bypass strict acceptance-gate behavior.

## Strict Mode

Strict mode requires the spec to contain:

```md
## Acceptance criteria
1. ...
```

Codex is prompted to follow a regression-first lifecycle: tests first, red phase when behavior changes, smallest implementation, targeted tests, full tests, lint/typecheck, and 100% coverage when the target project exposes coverage tooling.

Claude must write an acceptance matrix:

```md
## Acceptance matrix

- AC1: PASS - evidence
```

`Verdict: ACCEPT` is only honored in strict mode when every parsed acceptance criterion has a passing matrix row. Missing evidence becomes `unclear`.

## Local Commit

On `accepted`, devloop creates or reuses a local branch:

```text
devloop/<spec-slug>
```

It commits only files that were not already dirty when the run started, and it excludes `.codex/` artifacts from the commit. The generated commit message uses a Conventional Commit type:

```text
feat: <spec-slug>
```

No push or PR is performed.

## Artifacts

```text
.codex/tracks/<slug>.md
.codex/reviews/<slug>-r<N>.md
.codex/reports/<slug>.html
.codex/reports/<slug>.md
.codex/logs/
.codex/sessions/
```

Report format stays deliberately narrow:

```sh
devloop --report-format html .specs/change.md
devloop --report-format markdown .specs/change.md
devloop --md .specs/change.md
```

Reports include top-level metadata: result, passes, repository, spec, base branch, starting branch, final branch, local commit, commit message, Codex session ID, Claude session ID, track, and review files.

## Sessions

Each spec slug gets one Codex session and one Claude session:

```text
.codex/sessions/<slug>-codex.id
.codex/sessions/<slug>-claude.id
```

Pass 1 starts the sessions. Later fix passes resume them.

## Development

Prereqs: `bun`, `codex`, `claude`, `git`.

```sh
bun install
bun run typecheck
bun test
```

`bun test` enforces 100% line/function/statement coverage for the TypeScript core.
