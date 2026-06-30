<p align="center">
  <pre align="center">
░█▀▄░█▀▀░█░█░█░░░█▀█░█▀█░█▀█
░█░█░█▀▀░▀▄▀░█░░░█░█░█░█░█▀▀
░▀▀░░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀░▀░░
  </pre>
  <p align="center">Spec in. Reviewed code out.</p>
</p>

<p align="center">
  <a href="https://devloop.sh/demo.mp4"><img src="https://raw.githubusercontent.com/satyaborg/devloop/main/demo.gif" alt="demo" width="600"></a>
</p>

`devloop` runs a local agent loop: Codex implements, Claude Code reviews, and Codex retries until the work is accepted, stalled, unclear, or out of passes.

## Install

```sh
curl -fsSL https://devloop.sh/install | bash
```

Or from source:

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
./scripts/install.sh
```

> Requires Bash, git, `codex`, `claude`, `glow`, `gum`, and `fzf`. Run `devloop doctor` to check.
> The installers use Homebrew to install missing git/UI tools and the Codex/Claude Code casks when `brew` is available.

Uninstall with `./scripts/uninstall.sh` (`--dry-run` to preview).

## Usage

| Command | Description |
|---|---|
| `devloop` | Interactive menu: create, run, or continue a spec |
| `devloop spec "..."` | Have an agent interview you and write a spec |
| `devloop <spec.md>` | Run a spec |
| `devloop --create-pr <spec.md>` | Run a spec and maintain a draft PR (requires `gh`) |
| `devloop update` | Install the latest released Devloop |
| `devloop continue` | Resume a tracked run |
| `devloop status` | Show run status |
| `devloop clean` | Remove run artifacts |

Each run writes a Markdown report, spec, and reviews under `.devloop/`.
When you pick a spec from the interactive menu, devloop uses your configured run defaults and only prompts for PR mode. The interactive **Settings** menu sets the default coder and reviewer agents (Codex or Claude Code), spec path, and run timeout, saved to `~/.devloop/config`. Use CLI flags such as `--coder`, `--reviewer`, `--in-place`, or `--timeout-minutes` to override those defaults per run.

## Specs

A good spec is short, concrete, and verifiable. Start from [`skills/devloop-spec/references/spec-template.md`](skills/devloop-spec/references/spec-template.md).

Strict mode is on by default: specs need `## Acceptance criteria`, and reviews must pass both the spec gate and engineering quality gate.

## Skills

Devloop ships two agent skills, installed into `~/.claude/skills` and `~/.agents/skills`:

- [`devloop-spec`](skills/devloop-spec/SKILL.md) — interviews when scope is unclear, then writes one concrete, devloop-ready spec.
- [`devloop-review`](skills/devloop-review/SKILL.md) — judges each pass against the spec and engineering quality gates, returning ACCEPT, REJECT, or UNCLEAR with fix instructions.

## Runtime

- Uses an isolated sibling git worktree by default; pass `--in-place` to stay in the current worktree.
- Runs up to 5 passes, commits eligible coder changes, and executes `.devloop/verify` after each coder pass when present. Keep `.devloop/verify` local and auditable.
- Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.devloop/`; generated worktrees and branches remain for inspection.

## Contributing

```sh
git clone https://github.com/satyaborg/devloop.git
cd devloop
bash scripts/devloop_test.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, full gates, and release notes.

## Privacy

`devloop` adds no telemetry. It runs local agent CLIs against your checkout, so network behavior depends on the agents and commands you configure.

## License

[MIT](LICENSE)
