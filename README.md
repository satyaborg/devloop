# devloop

Spec in, accepted code out. Codex implements, Claude reviews, loop until ACCEPT, stall, or max turns. One bash file.

```
devloop.sh [--report-format html|markdown] path/to/spec.md [max=5]
```

## Why

Skills-as-orchestrators drift. The LLM driver has discretion to skip steps and often does, especially under load. A shell state machine cannot. devloop is the same workflow as the [`/devloop`](https://github.com/anthropics/claude-code) skill it replaces, minus the discretion.

What stays in the LLMs (because they are good at it):
- Codex: implementation, design decisions, fix passes
- Claude: review judgment, verdict, final synthesis

What moves to bash (because the LLM does not need discretion here):
- Sequencing the loop
- Spawning each agent headless
- Reusing one Codex implementation session and one Claude review session
- Parsing the verdict
- Detecting stalls
- File path conventions
- Stopping at max turns

## Quick start

Prereqs on PATH: `claude`, `codex`, `git`.

```sh
# 1. write a spec
cat > .specs/add-foo-flag.md <<'EOF'
# Add foo flag to bar config

## Acceptance criteria
1. ...
EOF

# 2. loop
./devloop.sh .specs/add-foo-flag.md
```

Defaults to unattended (`--dangerously-bypass-approvals-and-sandbox` for codex, `--dangerously-skip-permissions` for claude). Run inside a git worktree, not your main checkout.

The implementation worktree is resolved from the directory where you invoke `devloop.sh`, not from the spec file's location. The spec can live elsewhere; Codex and Claude are pointed at the current worktree.

## The loop

```
pass 1: codex implements against spec
        claude reviews → ACCEPT | REJECT | UNCLEAR
pass N: codex fixes findings from review N-1
        claude reviews
exit:   ACCEPT          → 0
        stall | max | unclear → 1
        codex/claude error    → 2
```

Stall = normalized findings hash matches the prior REJECT.

## Sessions

Each spec slug gets two persisted sessions:

```
.codex/sessions/<slug>-codex.id
.codex/sessions/<slug>-claude.id
```

Pass 1 starts the Codex implementation session and records the resumable session ID. Later fix passes call `codex exec resume <session-id>`, so Codex keeps the implementation context. Claude uses one review session for every review pass and the final report.

## Artifacts

```
.codex/tracks/<slug>.md        codex's running notes per pass
.codex/reviews/<slug>-r<N>.md  one per review turn
.codex/reports/<slug>.html     synthesized post-mortem by default
.codex/reports/<slug>.md       synthesized post-mortem with --report-format markdown
.codex/logs/                   raw agent stdout for debugging
```

## Tests

```sh
./tests/devloop_test.sh
```

The tests run the shell state machine against temporary git repos with mocked `codex` and `claude` commands, so they do not call either agent.

## The report

Not a mechanical concat. Claude is called one more time in the same review session with the spec + track + all reviews and writes a learning-oriented post-mortem:

- **Shape of the problem** — what the spec really asked for, alternatives ruled out
- **What was built** — design choices and the tradeoffs weighed
- **What review caught (and why it mattered)** — symptom → root cause → principle violated, grouped into patterns
- **What to remember next time** — transferable lessons in `When X, prefer Y because Z` form
- **Residual risk** — concrete, not generic

The "why" is enforced in the prompts: codex must explain decisions, claude must articulate the principle behind each finding ("if you cannot articulate the principle, the finding is too shallow — drop it or sharpen it").

## Caveats

- **Unattended = trusts both agents.** Use worktrees.
- **Sessions persist per spec slug.** Delete the matching files in `.codex/sessions/` when you want a fresh Codex or Claude context for the same spec filename.
- **No spec writing.** Deliberate. Write the spec yourself (or via an interview skill) and hand the path in.
- **Stall detection is hash-based.** Cosmetic rewording of identical findings will defeat it.
- **Base branch is auto-guessed** (`origin/HEAD` → `main` → `master`). Edit the `BASE=` line for stacked branches.

## License

MIT
