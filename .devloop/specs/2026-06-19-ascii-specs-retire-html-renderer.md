---
status: draft
type: chore
created: 2026-06-19
pr: null
---

# ASCII spec diagrams, retire the HTML spec renderer
Switch the devloop-spec skill to ASCII diagrams in plain code fences and remove the Python HTML companion renderer, so specs need no renderer to be read as intended.

```
  before                                 after
  ────────────────────────────────────────────────────────────────
  spec ```mermaid fence ─┐               spec ``` ASCII fence ─┐
                         ├▶ render.py ─▶  (no renderer)         ├▶ glow
                         │   .html ─▶ Chrome                    ├▶ GitHub
  SKILL.md invokes python3                                      └▶ cat
  README + tests pin render.py           same text everywhere, zero deps
```

## Problem
The devloop-spec skill makes Python and a browser part of the spec path. Specs are authored with `mermaid` fences, and the skill ships `skills/devloop-spec/scripts/render.py` (a ~20k Python file) and instructs running `python3 scripts/render.py <spec>` to produce an HTML companion (`skills/devloop-spec/SKILL.md:19`, `:165`, `:168`). That renderer is referenced in `README.md:52` and pinned by tests (`scripts/devloop_test.sh:182`, `:194`, `:1129`, `:1133`). A `mermaid` fence is only a diagram once that HTML is generated and opened in a browser. With `glow` as the terminal reader (sibling spec) the HTML companion has no audience: specs are read in-terminal via `glow` and on GitHub directly, and neither renders the Python HTML file. The moment it hurts: every spec carries a `mermaid` block that you can only see as a diagram by generating HTML and opening Chrome, the exact fragmentation being removed.

## Outcome
The devloop-spec skill instructs authoring diagrams as ASCII art inside plain ` ``` ` code fences and never `mermaid`; the spec template uses an ASCII schematic; `render.py` is removed from the repo and is no longer installed, referenced, or tested; `README.md` and `scripts/devloop_test.sh` no longer mention it. A spec then renders identically as monospace in `glow`, on GitHub, and in any plain-text view, with no renderer and no browser.

## Scope
- In: `skills/devloop-spec/SKILL.md` (replace mermaid guidance with ASCII-in-plain-fence guidance; remove the `render.py` resource line and the HTML Companion section); `skills/devloop-spec/references/spec-template.md` (replace the ` ```mermaid ` block with an ASCII fence); delete `skills/devloop-spec/scripts/render.py`; `README.md:52`; `scripts/devloop_test.sh` (remove the render.py fixture and install assertions at `:182`, `:194`, `:1129`, `:1133` and assert no installed `render.py`).
- Out: the runtime `glow` rendering (sibling spec `2026-06-19-glow-tui-rendering.md`); HTML *report* generation (`synthesize_report`, `devloop:3957`, agent-authored, not `render.py`); the PR-backlink specs; the spec section order or frontmatter; adding any new diagram tool, linter, or renderer.

## Behavior
### Happy path
1. The skill drafts a spec; its diagram is ASCII art inside a plain ` ``` ` fence (or omitted when no diagram clarifies the change).
2. No `render.py` is invoked and no `.html` companion is written.
3. The `.md` renders as a styled document in `glow` and on GitHub, ASCII diagram included.
4. `scripts/install.sh` installs the skill with no `render.py`, and `devloop doctor` finds the bundled and installed skill checksums equal.

### Edge cases
- A spec with no useful diagram: the skill omits the fence entirely, as the template already allows.
- An existing spec that still contains a `mermaid` fence: left untouched; `glow` shows it as a code block and GitHub still renders it, so no migration is required.
- Skill checksum: deleting `render.py` changes the bundled skill tree checksum, but `devloop_doctor_skills` compares bundled against installed (`scripts/skill_helpers.sh:217`), so a fresh `install.sh` keeps them equal and no stale-skill failure occurs.

## Acceptance criteria
1. `skills/devloop-spec/SKILL.md` contains no `mermaid` instruction and no `render.py` or `python3` reference, and instructs authoring diagrams as ASCII inside plain code fences.
2. `skills/devloop-spec/references/spec-template.md`'s schematic is an ASCII diagram inside a plain ` ``` ` fence, not a ` ```mermaid ` block.
3. `skills/devloop-spec/scripts/render.py` does not exist in the repo and is not installed by `scripts/install.sh` into either skills directory.
4. `README.md` contains no `render.py` reference.
5. `scripts/devloop_test.sh` invokes no `render.py` and asserts that neither installed skill directory contains `render.py`.
6. `bash scripts/devloop_test.sh` passes.

## Test plan
- Red: in `scripts/devloop_test.sh`, delete the render.py green/fixture lines (`:182`, `:194`) and the two installed-render.py assertions (`:1129`, `:1133`); add assertions that no `render.py` exists under either installed skill directory and that `SKILL.md` and the template contain no `mermaid`. These fail before the file and text are removed.
- Green: `bash scripts/devloop_test.sh`.
- Full: `bash scripts/devloop_test.sh`.
- Coverage: the shell runtime has no line-coverage tool; coverage is the fixture-style assertions covering skill content (no mermaid, no render.py) and installer output (no installed render.py).

## Constraints
- Must: keep the spec section order and frontmatter unchanged; only the diagram representation and the renderer change.
- Must: keep diagrams in plain ` ``` ` fences so `glow`, GitHub, and `cat` render them verbatim as monospace.
- Avoid: adding `mermaid-ascii` or any diagram dependency; migrating existing mermaid specs; introducing a new renderer in any language.
- Existing convention: skills are installed wholesale and checksum-verified by `devloop_doctor_skills` (`scripts/skill_helpers.sh:217`); tests assert installed skill files (`scripts/devloop_test.sh:1129`, `:1133`).

## Notes
- Supersedes the in-flight draft `.devloop/specs/2026-06-18-bash-spec-renderer.md`, which proposed porting `render.py` to a Bash HTML renderer with conditional mermaid. With `glow` as the reader and ASCII diagrams, no HTML companion is needed, so that draft should be deleted rather than implemented.
- HTML *reports* are unaffected: `synthesize_report` (`devloop:3957`) has the reviewer agent author HTML or markdown directly; `render.py` is only the spec companion.
- Sibling spec: `2026-06-19-glow-tui-rendering.md` (runtime). Independent file sets except shared `scripts/devloop_test.sh` and `README.md` in different sections; ship in either order.
- This spec models its own target state: its diagram is ASCII in a plain fence and it generates no HTML companion.
- Gaps: 0.
