# Devloop

**Spec in. Reviewed code out.**

`devloop` is a single Bash executable that runs a local implementation and review loop for agent-written code.

By default, Codex makes the change, Claude Code reviews it, and Codex retries until the work is accepted, stalled, unclear, or out of passes.

## Install

Prereqs: Bash, git, and the agent CLIs you want to use. The default pairing requires `codex` and `claude`.
For the full interactive UI, install [`gum`](https://github.com/charmbracelet/gum) and [`fzf`](https://github.com/junegunn/fzf). They are optional; `devloop` falls back to plain terminal output when they are missing.

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./install.sh
```

Run without installing:

```sh
./devloop --help
```

`install.sh` also installs the bundled Agent Skills globally under `~/.agents/skills`.
After install or update, verify the local setup:

```sh
devloop doctor
```

## Quick Start

Create a spec:

```sh
devloop spec "add retry behavior to the chat sender"
```

Start the guided UI:

```sh
devloop
```

Run the loop from the repo you want changed:

```sh
devloop .specs/change.md
```

In an interactive terminal, `devloop` opens a shell in the generated worktree after the run finishes. Exiting that shell returns `devloop`'s final accepted/stalled/failure status. Use `--no-shell` when you want the command to return immediately instead.

Open a PR after an accepted run:

```sh
devloop --create-pr .specs/change.md
```

## Specs

A good spec is short, concrete, and verifiable. Start from [`skills/devloop-spec/references/spec-template.md`](skills/devloop-spec/references/spec-template.md), or generate one:

```sh
devloop spec
devloop spec --agent claude --output .specs/chat-retry.md notes.md
```

Strict mode is on by default. It requires acceptance criteria and only accepts
reviews that pass both the spec gate and engineering quality gate:

```md
## Acceptance criteria
1. ...
```

## Common Options

```sh
devloop [options] <spec.md> [max=5]
```

| Option | Meaning |
| --- | --- |
| `--plain` | Force plain output, useful for automation |
| `--tui` | Force simple terminal progress output |
| `--coder <agent>` | Choose `codex` or `claude` for implementation |
| `--reviewer <agent>` | Choose `codex` or `claude` for review |
| `--report-format <format>` | Choose `html` or `markdown` |
| `--in-place` | Run in the current worktree |
| `--create-pr`, `--pr` | Push the accepted branch and open a GitHub PR |
| `--no-strict` | Weaken strict review gates |
| `--no-shell`, `--stay` | Do not open a shell in the generated worktree after completion |
| `--shell`, `--enter-worktree` | Open a shell in the generated worktree after completion |

## Interactive UI

When stdout is a terminal, running `devloop` without arguments opens a menu:

- `Run a spec`: pick a `.specs/*.md` file, review run settings, then start.
- `Create a spec`: choose the spec agent and provide source context.
- `Continue a run`: pick a prior `.codex/tracks/*.md` and continue in that worktree.
- `Open reports`: pick a prior report from any registered worktree.
- `Doctor`: verify required commands, optional UI tools, and installed skills.

`gum` powers prompts, confirmations, status output, paging, and setup screens. `fzf` powers searchable pickers for specs, tracks, and reports.

## What Devloop Does

- Runs up to 5 passes by default, clamped between 1 and 10.
- Uses isolated sibling git worktrees by default.
- Commits eligible changes after each coder pass.
- Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.codex/`.
- Leaves generated worktrees and branches in place for inspection.
- Drops you into the generated worktree shell after interactive runs, unless `--no-shell` is set.
- Never pushes or opens a PR unless you pass `--create-pr`.

## Security

`devloop` runs local agent CLIs against your checkout, so those agents inherit your local credentials, PATH, and machine access. `devloop` itself adds no telemetry and does not send data anywhere; network behavior depends on the agents and commands you configure.

## Development

```sh
bash -n devloop install.sh
./devloop --help
tmp="$(mktemp -d)"
DEVLOOP_BIN_DIR="$tmp/bin" DEVLOOP_SKILLS_DIR="$tmp/skills" ./install.sh
PATH="$tmp/bin:$PATH" DEVLOOP_SKILLS_DIR="$tmp/skills" devloop doctor
```

The supported runtime is the root [`devloop`](devloop) Bash script.

## License

MIT. See [LICENSE](LICENSE).
