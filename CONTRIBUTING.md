# Contributing to devloop

Thanks for your interest in improving devloop. This is a single-file Bash CLI with a fixture-style shell test suite. Changes stay small, regression-first, and self-documenting.

## Getting set up

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./scripts/install.sh   # symlinks the checkout, installs missing dependencies and bundled skills
devloop doctor         # verify required dependencies
```

Required to run a loop: Bash, git, `glow`, `gum`, `fzf`, `tmux`, and the `codex` and `claude` CLIs. The install scripts use Homebrew to install missing git/UI tools and tmux, plus the Codex/Claude Code casks when `brew` is available. Interactive runs enter a named tmux session by default; use `--no-tmux` when debugging the foreground process. The test suite itself needs only Bash, git, and coreutils because tmux behavior is covered with a fake executable.

## Development loop

Run the same gates CI runs before opening a PR:

```sh
bash -n devloop scripts/install.sh scripts/release.sh scripts/skill_helpers.sh scripts/install.remote.sh scripts/devloop_test.sh
shellcheck devloop scripts/install.sh scripts/skill_helpers.sh scripts/release.sh scripts/install.remote.sh scripts/devloop_test.sh
bash scripts/devloop_test.sh
```

The shell suite enforces 100% project function coverage for `devloop`, `scripts/skill_helpers.sh`, and `scripts/release.sh`. New functions need new tests. Keep tests fixture-style: assert generated files, git state, status codes, and user-visible output.

## Coding style

- Readable Bash with small named functions, quoted expansions, and explicit status handling.
- Portable across macOS and Linux shell utilities.
- Self-documenting code over inline comments.
- kebab-case for branch and spec slugs (`devloop/change`).

## Commits and pull requests

- Branch names: `type/short-description` (`feat/pr-mode`, `fix/null-check`).
- [Conventional Commits](https://www.conventionalcommits.org/) with three prefixes: `feat:`, `fix:`, `chore:`. Append `!` for breaking changes (`feat!:`). The changelog is generated from this history, so subjects matter.
- One logical change per commit. Keep PRs small and focused; a PR over ~300 LOC should probably be split.
- PRs include a short problem summary, the approach, and test evidence (`bash scripts/devloop_test.sh`).
- Update `README.md` and `AGENTS.md` when user-facing behavior changes.

See [AGENTS.md](AGENTS.md) for the repository map and the same guidelines in agent-facing form.

## Releases

Releases are cut by maintainers from a CI-green `main` with [`scripts/release.sh`](scripts/release.sh), which bumps `VERSION`, regenerates `CHANGELOG.md` from commit history with [git-cliff](https://git-cliff.org/), tags, and publishes the GitHub Release. The release script skips the full local shell suite by default because CI already runs it on merge to `main`; for `--push` and `--publish`, it first verifies local `HEAD` matches upstream. Pass `--run-tests` when you want an extra local preflight. You do not need to touch `VERSION` or `CHANGELOG.md` in a normal PR.

## Reporting bugs and proposing features

Open an issue using the templates. Security issues follow [SECURITY.md](SECURITY.md) instead of the public tracker.

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).
