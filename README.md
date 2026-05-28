# devloop

`devloop` runs a configurable implementation and review loop. By default, Codex codes and Claude Code reviews.

The coder makes the change. The reviewer reviews it. If the reviewer rejects it, the coder gets the review and tries again. The loop stops when the work is accepted, stalls, becomes unclear, reaches the max turn count, or an agent fails.

## Install

From this checkout:

```sh
bun scripts/install.ts
```

This installs dependencies and links `devloop` into `~/.local/bin`.

To use another bin directory:

```sh
DEVLOOP_BIN_DIR=/path/to/bin bun scripts/install.ts
```

## Run

Run `devloop` from the git repository you want it to change:

```sh
devloop .specs/change.md
```

Full form:

```sh
devloop [--plain|--tui] [--in-place] [--no-strict] [--coder codex|claude] [--reviewer codex|claude] [--report-format html|markdown] spec.md [max=5]
```

Common examples:

```sh
devloop .specs/change.md
devloop --plain .specs/change.md
devloop --tui .specs/change.md
devloop --report-format markdown .specs/change.md 3
devloop --coder claude --reviewer codex .specs/change.md
```

## Write A Spec

Start with [`templates/spec.md`](templates/spec.md). A good spec is short and concrete:

- what is broken or missing
- what the finished behavior should look like
- what is in scope and out of scope
- examples for happy paths and edge cases
- acceptance criteria that can be verified
- the tests or checks that should prove the change works

Strict mode is on by default. In strict mode, the spec must include:

```md
## Acceptance criteria
1. ...
```

## What Happens

By default, `devloop`:

- runs up to 5 passes, clamped between 1 and 10
- uses Codex as the coder and Claude Code as the reviewer
- uses the TUI in a terminal and plain output elsewhere
- writes an HTML report
- requires the reviewer to pass every acceptance criterion
- creates an isolated sibling git worktree and runs agents there
- creates a local branch and commit when the run is accepted
- never pushes or opens a PR

Use `--plain` for CI. Use `--tui` to force the TUI. Use `--coder` and `--reviewer` to choose `codex` or `claude` for either role. Use `--in-place` to opt out of the isolated worktree and run in the current checkout. Use `--no-strict` only when you want weaker acceptance gates.

## Output

Each run writes files under `.codex/`:

```text
.codex/tracks/<slug>.md
.codex/reviews/<slug>-r<N>.md
.codex/reports/<slug>.html
.codex/reports/<slug>.md
.codex/logs/
.codex/sessions/<slug>-coder.id
.codex/sessions/<slug>-reviewer.id
.codex/specs/<slug>.md
```

With the default isolated worktree, these files are written inside the generated sibling worktree named `<repo>-<slug>`. The original checkout is left on its current branch, and uncommitted files in that checkout are not included in the run. The spec is snapshotted into `.codex/specs/<slug>.md` inside the worktree. The final CLI/TUI output prints the worktree path and absolute report/track paths.

Before creating the worktree, `devloop` asks the configured coder to read the spec and repository and return the semantic work item identity. That identity supplies `<slug>`, branch type, and breaking-change status. Explicit spec frontmatter wins when set:

```yaml
type: fix
slug: chat-retry
breaking: true
```

When `type`, `slug`, and `breaking` are all set, `devloop` skips the naming call.

On acceptance, `devloop` creates or reuses a branch like:

```text
feat/<slug>
fix/<slug>
chore/<slug>
```

Breaking changes use `!`, for example `feat!/<slug>`.

It commits only files that were clean when the run started. It excludes `.codex/`. Commit messages use:

```text
feat: <slug>
feat!: <slug>
```

devloop intentionally keeps generated worktrees and branches for inspection after both successful and failed runs. To remove one when you are done:

```sh
git -C <source-repo> worktree remove <worktree-path>
git -C <source-repo> branch -D feat/<slug>
git -C <source-repo> branch -D 'feat!/<slug>'
```

If `worktree remove` reports local modifications, inspect the worktree first or rerun the command with `--force` to discard them.

## Development

Prereqs: `bun`, `git`, and the agents you configure. The defaults require `codex` and `claude`.

```sh
bun scripts/install.ts
bun run typecheck
bun test
```

`bun test` enforces 100% line, function, and statement coverage for the TypeScript core.

## License

MIT. See [LICENSE](LICENSE).
