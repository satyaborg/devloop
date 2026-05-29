# Contributing

devloop is a Bash CLI. Keep changes narrow, readable, and covered by shell tests.

## Local Setup

```sh
bash tests/devloop_test.sh
```

The active executable is `./devloop`; install locally with `./install.sh`.

## Pull Requests

- Use Conventional Commits in commit subjects: `feat:`, `fix:`, or `chore:`. Use `!` for breaking changes.
- Keep one logical change per commit.
- Include test evidence in the PR description.
- Update README examples when user-visible CLI behavior changes.
- Do not commit `.codex/`, `.specs/`, coverage output, dependency caches, or local worktrees.

## Release Automation

Release Please manages version bumps from Conventional Commits, opens release PRs, updates `CHANGELOG.md`, and creates GitHub releases when release PRs merge.

The release workflow can use the default GitHub token, but GitHub-token-created pull requests and releases can have workflow trigger limitations. Maintainers who need CI to run on Release Please PRs should create a fine-grained `RELEASE_PLEASE_TOKEN` with repository contents and pull request permissions, then store it as a GitHub Actions secret. The workflow falls back to the default token when that secret is absent.
