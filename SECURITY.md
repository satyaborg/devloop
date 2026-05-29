# Security

## Security Model

devloop is a Bash harness that runs local agent CLIs with broad permissions because the configured coder and reviewer need access to inspect and modify a checkout. By default, devloop creates isolated sibling git worktrees before invoking those agents, but the agents still run on your machine with your local credentials, environment variables, PATH, and filesystem permissions.

devloop writes `.codex/` artifacts for specs, tracks, reviews, reports, logs, and session ids. Treat those files as local development artifacts that may contain prompts, review text, command output, and repository paths.

devloop does not add telemetry, phone home, or send data anywhere itself. Network access depends on the agent CLIs and commands you configure.

## Reporting A Vulnerability

Open a private security advisory at:

https://github.com/satyaborg/devloop/security/advisories/new

If that is not available, open a minimal issue that does not include exploit details and ask for a private contact path.

## Supported Versions

Security fixes target the root `devloop` executable on the `main` branch and the latest GitHub release.
