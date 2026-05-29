[![CI](https://github.com/satyaborg/devloop/actions/workflows/ci.yml/badge.svg)](https://github.com/satyaborg/devloop/actions/workflows/ci.yml)
[![license](https://img.shields.io/github/license/satyaborg/devloop.svg)](LICENSE)

# Devloop

**Spec in. Reviewed code out.**

`devloop` is a single Bash executable that runs a local implementation and review loop for agent-written code.

By default, Codex makes the change, Claude Code reviews it, and Codex retries until the work is accepted, stalled, unclear, or out of passes.

## Install

Prereqs: Bash, git, and the agent CLIs you want to use. The default pairing requires `codex` and `claude`.

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./install.sh
```

Run without installing:

```sh
./devloop --help
```

## Quick Start

Create a spec:

```sh
devloop spec "add retry behavior to the chat sender"
```

Run the loop from the repo you want changed:

```sh
devloop .specs/change.md
```

Open a PR after an accepted run:

```sh
devloop --create-pr .specs/change.md
```

## Specs

A good spec is short, concrete, and verifiable. Start from [`templates/spec.md`](templates/spec.md), or generate one:

```sh
devloop spec
devloop spec --agent claude --output .specs/chat-retry.md notes.md
```

Strict mode is on by default and requires:

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
| `--plain` | Force plain output, useful for CI |
| `--tui` | Force simple terminal progress output |
| `--coder <agent>` | Choose `codex` or `claude` for implementation |
| `--reviewer <agent>` | Choose `codex` or `claude` for review |
| `--report-format <format>` | Choose `html` or `markdown` |
| `--in-place` | Run in the current worktree |
| `--create-pr`, `--pr` | Push the accepted branch and open a GitHub PR |
| `--no-strict` | Weaken acceptance gates |

## What Devloop Does

- Runs up to 5 passes by default, clamped between 1 and 10.
- Uses isolated sibling git worktrees by default.
- Commits eligible changes after each coder pass.
- Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.codex/`.
- Leaves generated worktrees and branches in place for inspection.
- Never pushes or opens a PR unless you pass `--create-pr`.

## Security

`devloop` runs local agent CLIs against your checkout, so those agents inherit your local credentials, PATH, and machine access. `devloop` itself adds no telemetry and does not send data anywhere; network behavior depends on the agents and commands you configure.

## Development

```sh
bash -n devloop install.sh
./devloop --help
DEVLOOP_BIN_DIR="$(mktemp -d)/bin" ./install.sh
```

The supported runtime is the root [`devloop`](devloop) Bash script.

## License

MIT. See [LICENSE](LICENSE).
