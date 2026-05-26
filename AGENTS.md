# Repository Guidelines

## Project Structure & Module Organization

This is a Bun and TypeScript CLI project. Core source lives in `src/`: `cli.ts` handles command-line entry, `devloop.ts` contains the loop and parsing logic, and `tui*.ts` owns the OpenTUI interface. Tests live in `tests/` and mirror the main modules, for example `tests/devloop.test.ts` and `tests/tui-view.test.ts`. `templates/spec.md` is the starter spec copied by users, while `scripts/install.ts` installs dependencies and links the local `devloop` binary. Generated runtime output belongs under `.codex/` in target repositories and should not be committed here.

## Build, Test, and Development Commands

- `bun scripts/install.ts`: install dependencies and link `devloop` into `~/.local/bin` or `DEVLOOP_BIN_DIR`.
- `bun test`: run the Bun test suite with coverage enabled.
- `bun run typecheck`: run `tsc --noEmit` against `src/**/*.ts` and `tests/**/*.ts`.
- `devloop --plain .specs/change.md`: example local CLI invocation from a target git worktree.

## Coding Style & Naming Conventions

Use strict TypeScript modules with explicit `.ts` import extensions, matching the existing `moduleResolution: "Bundler"` setup. Keep code formatted with two-space indentation, double quotes, semicolons, and small named functions. Prefer clear camelCase names for variables and functions, PascalCase for exported types, and kebab-case for branch/spec slugs such as `devloop/change`.

## Testing Guidelines

Tests use `bun:test`. Name test files `*.test.ts` and keep behavior grouped with `describe` and `test`. `bunfig.toml` requires 100% line, function, and statement coverage for non-test TypeScript files, so update tests with every behavior change. For CLI behavior, prefer fixture-style tests that assert generated files, git state, status codes, and user-visible output.

## Commit & Pull Request Guidelines

Git history follows Conventional Commits, for example `fix: surface devloop commit failures` and `chore: cover tui view rendering`. Use concise subjects in imperative style and keep unrelated changes in separate commits. Pull requests should include a short problem summary, the implementation approach, test evidence (`bun test`, `bun run typecheck`), and screenshots or terminal captures when changing TUI behavior.

## Agent-Specific Instructions

Keep changes narrow and regression-first. Do not commit `.codex/`, coverage artifacts, local specs, or dependency caches unless explicitly requested. When modifying acceptance or reporting behavior, update both tests and `README.md` examples if user-facing output changes.
