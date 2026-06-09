# Security Policy

## Supported versions

devloop is pre-1.0. Security fixes land on the latest released `0.x` version. Always update to the newest release before reporting.

## Reporting a vulnerability

Please report security issues privately. Do not open a public issue.

- Preferred: open a [private security advisory](https://github.com/satyaborg/devloop/security/advisories/new) on this repository.
- Alternatively: email **satya.borg@gmail.com** with a description and reproduction steps.

You can expect an initial response within a few days. Once a fix is available, we will publish a release and credit you unless you prefer to remain anonymous.

## Scope and threat model

devloop runs local agent CLIs (Codex, Claude Code) against your checkout. Those agents inherit your local credentials, `PATH`, and machine access. devloop adds no telemetry and sends no data anywhere on its own; network behavior depends entirely on the agents and commands you configure.

If present, `.devloop/verify` is executed from the run worktree with the pass number and slug as arguments. Treat that script, and any spec you run, as code you are choosing to execute. Keep them local and auditable.

Reports most relevant to devloop itself include: command injection in the runtime, unsafe handling of untrusted spec or config input, the remote installer (`scripts/install.remote.sh`) fetching or executing unverified content, and checksum-verification bypasses.
