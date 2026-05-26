# devloop

Codex implements. Claude reviews. devloop runs the loop until the work is accepted, stalls, becomes unclear, hits max turns, or an agent fails.

```sh
devloop [--plain|--tui] [--no-strict] [--report-format html|markdown] spec.md [max=5]
```

Run from the target git worktree. The spec may live anywhere.

Start new specs from [`templates/spec.md`](templates/spec.md), usually copied to `.specs/YYYY-MM-DD-slug.md`.

The template is intentionally short: clear problem, observable outcome, tight scope, behavior examples, verifiable acceptance criteria, regression-first test plan, constraints, and only material notes.

## Install

From this checkout:

```sh
bun scripts/install.ts
```

That installs dependencies and links `devloop` into `~/.local/bin`. Set `DEVLOOP_BIN_DIR` to choose another bin directory.

## Defaults

- strict mode is on
- HTML reports are on
- max turns default to 5 and clamp to 1-10
- TTY runs use the collapsed OpenTUI view
- non-TTY runs use plain output
- accepted runs create a local branch and local commit
- no-arg `devloop` shows the logo and common commands

Use `--plain` for CI. Use `--tui` to force the TUI. Use `--no-strict` only when you explicitly want weaker gates.

## Strict Acceptance

Strict mode requires:

```md
## Acceptance criteria
1. ...
```

Codex is prompted to work regression-first: add or update tests, observe the red phase when behavior changes, implement the smallest fix, then run targeted tests, full tests, lint/typecheck, and coverage.

Claude must write:

```md
## Acceptance matrix

- AC1: PASS - evidence
```

In strict mode, `Verdict: ACCEPT` only counts when every parsed criterion has a `PASS` matrix row. Missing evidence exits as `unclear`.

## Output

```text
.codex/tracks/<slug>.md
.codex/reviews/<slug>-r<N>.md
.codex/reports/<slug>.html
.codex/reports/<slug>.md
.codex/logs/
.codex/sessions/
```

Reports can be HTML or Markdown:

```sh
devloop --report-format html .specs/change.md
devloop --report-format markdown .specs/change.md
devloop --md .specs/change.md
```

Reports include result, passes, repo, spec, base branch, starting branch, final branch, local commit, commit message, Codex session ID, Claude session ID, track, and review files.

## Local Commit

On `accepted`, devloop creates or reuses:

```text
devloop/<spec-slug>
```

It commits only files that were clean when the run started and excludes `.codex/`. Commit messages are Conventional Commit style:

```text
feat: <spec-slug>
```

devloop does not push or open a PR.

## Development

Prereqs: `bun`, `codex`, `claude`, `git`.

```sh
bun scripts/install.ts
bun run typecheck
bun test
```

`bun test` enforces 100% line/function/statement coverage for the TypeScript core.

## References

- [ISO/IEC/IEEE 29148:2018](https://byui-cse.github.io/cse372-course/Reading/CSE372Week10-IEEE.pdf): requirements should be necessary, unambiguous, singular, feasible, verifiable, and focused on what is needed.
- [Erdogmus, Morisio, and Torchiano, 2005](https://cs.unm.edu/~joel/cs351/paper/IEEE-Effectiveness_of_Test-First_Approach_to_Programming.pdf): test-first work formalizes functionality as tests, gives fast feedback, and supports small measurable tasks.
- [Fucci et al., 2016](https://bura.brunel.ac.uk/bitstream/2438/14550/1/FullText.pdf): TDD benefits depend heavily on fine-grained, steady cycles, not ceremony.
- [Rafique and Misic, 2013](https://openurl.ebsco.com/contentitem/doi%3A10.1109/tse.2012.28?id=ebsco%3Adoi%3A10.1109%2Ftse.2012.28&sid=ebsco%3Aplink%3Acrawler) and [Bissi, Neto, and Emer, 2016](https://www.sciencedirect.com/science/article/abs/pii/S0950584916300222): TDD evidence is strongest for quality, less conclusive for productivity.
- [Agile Alliance user stories](https://agilealliance.org/glossary/user-stories/), [Given-When-Then](https://agilealliance.org/glossary/given-when-then/), and [Cucumber Gherkin reference](https://cucumber.io/docs/gherkin/reference/): acceptance criteria are strongest when they become concrete, observable examples.
