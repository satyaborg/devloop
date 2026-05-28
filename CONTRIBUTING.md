# Contributing

devloop is a Bun and TypeScript CLI. Keep changes narrow, typed, and covered by tests.

## Local Setup

```sh
bun scripts/install.ts
bun run typecheck
bun test
bun run package:smoke
```

`bun test` is configured with 100% line, function, and statement coverage for non-test TypeScript files.

## Pull Requests

- Use Conventional Commits in commit subjects: `feat:`, `fix:`, or `chore:`. Use `!` for breaking changes.
- Keep one logical change per commit.
- Include test evidence in the PR description.
- Update README examples when user-visible CLI behavior changes.
- Do not commit `.codex/`, `.specs/`, coverage output, dependency caches, or local worktrees.

## Release Automation

Release Please manages version bumps from Conventional Commits, opens release PRs, updates `CHANGELOG.md`, and creates GitHub releases when release PRs merge. The repository uses `release-please-config.json` with the `node` release type for `@satyaborg/devloop`.

The release workflow can use the default GitHub token, but GitHub-token-created pull requests and releases can have workflow trigger limitations. Maintainers who need CI to run on Release Please PRs should create a fine-grained `RELEASE_PLEASE_TOKEN` with repository contents and pull request permissions, then store it as a GitHub Actions secret. The workflow falls back to the default token when that secret is absent.

## npm Publishing

The package is published as `@satyaborg/devloop`; the installed binary remains `devloop`.

Publishing is handled by `.github/workflows/publish.yml`. It runs after the Release Please workflow completes, verifies that a matching GitHub release exists for the package version, skips versions that are already on npm, reruns typecheck/tests/package checks, and then runs `npm publish`.

The publish workflow uses npm trusted publishing through GitHub Actions OIDC. It intentionally does not use a long-lived `NPM_TOKEN` or `NODE_AUTH_TOKEN`.

One-time npm setup before the first automated publish:

1. Ensure the `@satyaborg` npm scope is owned by the maintainer account.
2. `@satyaborg/devloop` must be created or first-published by a maintainer as a public package if npm requires an existing package before trusted publishing can be configured.
3. In npm package settings, add a trusted publisher for GitHub Actions.
4. Configure owner `satyaborg`, repository `devloop`, workflow filename `publish.yml`, and allowed action `npm publish`.
5. Leave the environment blank unless the GitHub workflow is later changed to use a protected environment.

For a manual first publish, verify locally first:

```sh
bun run typecheck
bun test
npm --cache /private/tmp/devloop-npm-cache pack --dry-run --json
bun run package:smoke
```
