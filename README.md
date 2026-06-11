# Devloop

Spec in. Reviewed code out.

`devloop` runs a local agent loop: Codex implements, Claude Code reviews, and Codex retries until the work is accepted, stalled, unclear, or out of passes.

## Install

```sh
curl -fsSL https://devloop.sh/install | bash
```

Installs to `~/.local/share/devloop`, links `~/.local/bin/devloop`, and installs the bundled Codex and Claude Code skills.

Required: Bash, git, Homebrew, `codex`, `claude`, `gum`, and `fzf`. The installer can install missing `gum` and `fzf`; install the agent CLIs yourself. PR-backed loops (`--create-pr`) additionally require an authenticated `gh`.

From source:

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./scripts/install.sh
devloop doctor
```

## Uninstall

```sh
./scripts/uninstall.sh
```

Removes the `~/.local/bin/devloop` symlink, the `~/.local/share/devloop` runtime, and the devloop-managed skills. Pass `--dry-run` to preview, or set `DEVLOOP_FORCE=1` to also remove hand-modified skills. Leaves the source checkout, `gum`, `fzf`, and `gh` untouched.

## Use

```sh
devloop
devloop spec "add retry behavior to the chat sender"
devloop .devloop/specs/change.md
devloop --create-pr .devloop/specs/change.md
devloop continue
devloop status
devloop clean
```

Start with a spec you already have, or from scratch. Pass a path to run an existing spec; run `devloop spec` with no context to let the agent interview you and write one. `devloop continue` resumes a tracked run where it left off.

Each run writes an HTML report and the markdown spec and reviews under `.devloop/`, so the work is easy to read and review at a glance. HTML is the default; pass `--report-format markdown` for plain text.

## Specs

A good spec is short, concrete, and verifiable. Start from [`skills/devloop-spec/references/spec-template.md`](skills/devloop-spec/references/spec-template.md), or launch a spec agent:

```sh
devloop spec
devloop spec --agent claude notes.md
```

Strict mode is on by default. Specs need `## Acceptance criteria`, and reviews must pass both the spec gate and engineering quality gate.

Devloop stores shared settings in `~/.devloop/config`. The default spec directory is the current repo's `.devloop/specs/`. Set a custom `spec_dir` (global or per-repo) to point elsewhere, for example `~/Projects/specs`; the picker searches both the custom directory and the repo's `.devloop/specs/`.

## PR mode

A plain non-interactive `devloop <spec>` remains local-only.

With `--create-pr`, `devloop` opens and maintains a draft PR during the loop. The PR is canonical for review history; local `.devloop/reviews/*.md` files are execution cache.

Install `gh` and run `gh auth login` before using PR-backed loops.

## Runtime

- Uses an isolated sibling git worktree by default; pass `--in-place` to stay in the current worktree.
- Runs up to 5 passes, commits eligible coder changes, and executes `.devloop/verify` after each coder pass when present.
- Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.devloop/`; generated worktrees and branches remain for inspection.

## Security

`devloop` runs local agent CLIs against your checkout, so those agents inherit your local credentials, PATH, and machine access. `devloop` adds no telemetry; network behavior depends on the agents and commands you configure.

Keep `.devloop/verify` local and auditable. It runs from the run worktree with the pass number and slug as arguments.

## Development

```sh
bash scripts/devloop_test.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, full gates, and release notes.

## License

MIT
