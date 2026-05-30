# Repository Guidelines

## Project Structure & Module Organization

This is a Bash CLI project. The active runtime is the root `devloop` executable. `VERSION` is the single version source, `release.sh` cuts local release commits and annotated tags, `install.sh` links the CLI into a local bin directory and installs bundled skills into `~/.agents/skills` and `~/.claude/skills`, `tests/devloop_test.sh` covers the shell runtime, `skills/devloop-spec/SKILL.md` is the spec-generation skill, `skills/devloop-review/SKILL.md` is the review skill, and `skills/devloop-spec/references/spec-template.md` is the starter spec. Generated runtime output belongs under `.codex/` in target repositories and should not be committed here.

## Build, Test, and Development Commands

- `bash tests/devloop_test.sh`: run the shell test suite.
- `./install.sh`: link `devloop` into `~/.local/bin` or `DEVLOOP_BIN_DIR`.
- `./devloop --plain .specs/change.md`: example local CLI invocation from a target git worktree.
- `./release.sh patch --dry-run`: validate the release path without changing files.

## Coding Style & Naming Conventions

Use readable Bash with small named functions, quoted expansions, explicit status handling, and portable macOS/Linux shell utilities where practical. Prefer kebab-case for branch/spec slugs such as `devloop/change`.

## Testing Guidelines

Tests use `tests/devloop_test.sh`. Keep behavior fixture-style where possible: assert generated files, git state, status codes, and user-visible output.

## Commit & Pull Request Guidelines

Git history follows Conventional Commits, for example `fix: surface devloop commit failures` and `chore: cover shell runtime`. Use concise subjects in imperative style and keep unrelated changes in separate commits. Pull requests should include a short problem summary, the implementation approach, and test evidence (`bash tests/devloop_test.sh`).

## Agent-Specific Instructions

Keep changes narrow and regression-first. Do not commit `.codex/`, coverage artifacts, local specs, or dependency caches unless explicitly requested. When modifying acceptance, reporting, versioning, or release behavior, update tests and `README.md` examples if user-facing output changes.
