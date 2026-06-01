# Devloop

**Spec-driven code and review loop.**

`devloop` is a single Bash executable that runs a local implementation and review loop for agent-written code.

By default, Codex makes the change, Claude Code reviews it, and Codex retries until the work is accepted, stalled, unclear, or out of passes.

## Install

Install Devloop with the remote installer:

```sh
curl -fsSL https://devloop.sh/install | bash
```

The installer downloads a tagged GitHub release asset, verifies its `.sha256` checksum, installs it under `~/.local/share/devloop/<version>/`, links `~/.local/bin/devloop`, and installs the bundled Agent Skills for Codex under `~/.agents/skills` and Claude Code under `~/.claude/skills`.

Install a specific version or preview the install:

```sh
curl -fsSL https://devloop.sh/install | bash -s -- --version 0.2.0
curl -fsSL https://devloop.sh/install | bash -s -- --dry-run
curl -fsSL https://devloop.sh/install | bash -s -- --no-skills
```

Inspect before running:

```sh
curl -fsSL https://devloop.sh/install -o install.sh
less install.sh
bash install.sh
```

The remote installer checks for `gum`, `fzf`, `codex`, and `claude`. It does not install Codex or Claude Code. If `gum` or `fzf` is missing, it only installs them with Homebrew after explicit confirmation; otherwise it prints the `brew install gum fzf` command to run yourself.

If `~/.local/bin` is not on `PATH`, the installer prints the shell profile line to add. It does not edit shell profile files.

For source checkout development, use the local installer:

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./install.sh
```

`./install.sh` symlinks the checkout executable, installs missing `gum` and `fzf` with Homebrew when available, installs bundled skills, and finishes with `try: devloop doctor`.

Check the installed version:

```sh
devloop --version
```

Run without installing:

```sh
./devloop --help
```

After install or update, verify the local setup:

```sh
devloop doctor
```

Uninstall a remote install:

```sh
rm -f ~/.local/bin/devloop
rm -rf ~/.local/share/devloop
rm -rf ~/.agents/skills/devloop-spec ~/.agents/skills/devloop-review
rm -rf ~/.claude/skills/devloop-spec ~/.claude/skills/devloop-review
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

See tracked runs and cleanup candidates:

```sh
devloop status
devloop clean
```

## Specs

A good spec is short, concrete, and verifiable. Start from [`skills/devloop-spec/references/spec-template.md`](skills/devloop-spec/references/spec-template.md), or generate one:

```sh
devloop spec
devloop spec --agent claude notes.md
```

Devloop maintains a global config at `~/.devloop/config`. By default, generated specs are written under `~/Projects/specs/`, and the interactive spec picker searches that directory plus the current repo's `.specs/` fallback.

Change the shared spec directory from `devloop` > `Settings`, or edit `~/.devloop/config`:

```ini
spec_dir=/Users/satya/Projects/specs
```

Repo-local `.devloop/config` is still supported for explicit overrides. Prefer absolute paths there unless the override should be repo-relative.

Runs time out after 30 minutes by default. Change that in `Settings`, in `~/.devloop/config`, or per command:

```ini
timeout_minutes=45
```

```sh
devloop --timeout-minutes 45 .specs/change.md
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
| `--tui` | Force terminal UI output |
| `--coder <agent>` | Choose Codex or Claude Code for implementation (`codex`/`claude`) |
| `--reviewer <agent>` | Choose Codex or Claude Code for review (`codex`/`claude`) |
| `--report-format <format>` | Choose `html` or `markdown` |
| `--timeout-minutes <n>` | Cap one run, default `30` |
| `--in-place` | Run in the current worktree |
| `--create-pr`, `--pr` | Push the accepted branch and open a GitHub PR |
| `--no-strict` | Weaken strict review gates |
| `--no-shell`, `--stay` | Do not open a shell in the generated worktree after completion |
| `--shell`, `--enter-worktree` | Open a shell in the generated worktree after completion |
| `-V`, `--version` | Show version |

## Interactive UI

When stdout is a terminal, running `devloop` without arguments opens a menu:

- `Run a spec`: pick a spec from the shared spec directory or `.specs/`.
- `Create a spec`: choose the spec agent and provide source context.
- `Continue a run`: pick a prior `.codex/tracks/*.md` and continue in that worktree.
- `Open reports`: pick a prior report from any registered worktree.
- `Settings`: view or change the shared spec path and set the run timeout.
- `Doctor`: verify required dependencies and installed skills.

Nested menu screens keep `Back` as the final option, and Esc/cancel also returns to the previous menu without exiting Devloop. Interactive screens redraw in place instead of appending a fresh UI after each selection.

`gum` powers the branded help screen, prompts, confirmations, status output, paging, and setup screens. `fzf` powers searchable pickers for specs, tracks, and reports. Both are required and installed by `install.sh` when missing.

## What Devloop Does

- Runs up to 5 passes by default, clamped between 1 and 10.
- Stops a run after the configured timeout, default 30 minutes.
- Uses isolated sibling git worktrees by default.
- Runs a small preflight before agents start: git identity, agent CLIs, installed skills, and `gh` when PR creation is enabled.
- Lints specs for a title, valid frontmatter type when frontmatter exists, and strict acceptance criteria.
- Commits eligible changes after each coder pass.
- Runs `.devloop/verify` after each coder pass when it exists and is executable. In strict mode, a failing hook blocks acceptance.
- Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.codex/`.
- Leaves generated worktrees and branches in place for inspection.
- Drops you into the generated worktree shell after interactive runs, unless `--no-shell` is set.
- Never pushes or opens a PR unless you pass `--create-pr`.

## Security

`devloop` runs local agent CLIs against your checkout, so those agents inherit your local credentials, PATH, and machine access. `devloop` itself adds no telemetry and does not send data anywhere; network behavior depends on the agents and commands you configure.

If present, `.devloop/verify` is executed from the run worktree with the pass number and slug as arguments. Keep that script local and auditable.

## Operations

`devloop status` summarizes tracked runs across registered git worktrees. It shows the slug, latest verdict-derived status, pass count, branch, worktree, report path, and a suggested next command.

`devloop clean` defaults to a dry run. `devloop clean --force` removes eligible generated worktrees, but skips accepted runs and user-dirty worktrees unless forced. `.codex/` runtime artifacts do not count as user dirt.

## Development

```sh
bash -n devloop install.sh release.sh skill_helpers.sh install.remote.sh
shellcheck devloop install.sh skill_helpers.sh release.sh install.remote.sh tests/devloop_test.sh
bash tests/devloop_test.sh
./devloop --help
./devloop --version
tmp="$(mktemp -d)"
DEVLOOP_BIN_DIR="$tmp/bin" HOME="$tmp/home" ./install.sh
PATH="$tmp/bin:$PATH" HOME="$tmp/home" devloop doctor
```

The supported runtime is the root [`devloop`](devloop) Bash script.
The shell suite enforces 100% project function coverage for `devloop`, `skill_helpers.sh`, and `release.sh`.

## Versioning and Release

`devloop` uses [Semantic Versioning](https://semver.org/) and stores the current version in [`VERSION`](VERSION). `0.x` releases are initial public API releases, so breaking changes can happen between minor versions.

Release notes in [`CHANGELOG.md`](CHANGELOG.md) are generated from Conventional Commit history with [`git-cliff`](https://git-cliff.org/). Published GitHub Releases use [`gh`](https://cli.github.com/). Install both before cutting a real release:

```sh
brew install git-cliff
brew install gh
```

Cut a release from a clean tree by choosing the bump:

```sh
./release.sh patch --dry-run
./release.sh patch --publish
```

Use `patch`, `minor`, or `major`. The script reads the current [`VERSION`](VERSION), computes the next SemVer version, updates `VERSION` and [`CHANGELOG.md`](CHANGELOG.md), runs `bash tests/devloop_test.sh`, commits `chore: release <version>`, and creates an annotated `v<version>` tag. Add `--publish` to push the release branch and tag, then create the GitHub Release. Use `--push` only when you want to publish the git refs without creating a GitHub Release. By default, published releases must run from `main`.

## License

MIT. See [LICENSE](LICENSE).
