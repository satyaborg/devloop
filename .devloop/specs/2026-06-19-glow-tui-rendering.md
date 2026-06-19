---
status: draft
type: feat
created: 2026-06-19
pr: null
---

# Glow-rendered specs and reports in the terminal
Render Markdown specs and reports with `glow` inside devloop's existing fzf previews and report viewer so reading a spec or report never leaves the terminal.

```
  today                          this change                    result
  ──────────────────────────────────────────────────────────────────────
  spec  ─▶ Obsidian (read)       fzf preview ─▶ glow            one terminal
  report ─▶ Chrome (open .html)  view_file   ─▶ glow (.md)      surface; no
  fzf preview ─▶ raw `sed`       report default ─▶ markdown     Obsidian, no
                                 doctor ─▶ checks glow          Chrome
```

## Problem
Reading the two artifacts devloop produces pulls you out of the terminal into two other tools. The fzf picker preview shows unstyled raw text: `ui_pick_from_file` runs `--preview 'sed -n "1,80p" {}'` (`devloop:1069`), so selecting a spec shows flat Markdown, which is why a second tool (Obsidian) stays open just to read specs. Reports are worse: the default report format is `html` (`devloop:1451`, `:1895`, `:1966`), and `view_file` opens `*.html` with `open`/`xdg-open` (`devloop:1711-1716`), so finishing a run and reading its report yanks you into Chrome. The moment it hurts: picking a spec from `devloop` shows raw markdown in the preview pane, and opening its report launches a browser tab, fragmenting one loop across three surfaces.

## Outcome
`glow` renders Markdown in every fzf preview pane (specs, reports, tracks) and in `view_file` for `*.md` reports, so reading happens in the terminal. The default report format is `markdown`, making the default reading path terminal-native and removing the browser from the loop. `--report-format html` still writes and opens an HTML report via the browser, unchanged. `devloop doctor` checks for `glow`. When `glow` is absent every path falls back to today's behavior, so runs never break.

## Scope
- In: `devloop` — `ui_pick_from_file` preview command (`devloop:1058-1071`); `view_file` (`devloop:1708-1727`); the default `report_format` value (`devloop:1451`, `:1895`, `:1966`) and the `REPORT` path branch (`devloop:2181-2185`) only to flip the default to markdown; a `ui_has_glow` helper mirroring `ui_has_fzf` (`devloop:819`); the doctor required-tool list (`scripts/skill_helpers.sh:349-354`); `README.md` usage notes if user-visible output changes; tests in `scripts/devloop_test.sh`.
- Out: a new keybind-driven dashboard (enter to run, ctrl-e to edit, ctrl-l to tail) — deferred follow-up; the existing menu navigation is reused as is. The spec-skill / ASCII-diagram / renderer change (sibling spec `2026-06-19-ascii-specs-retire-html-renderer.md`). Report content generation in `synthesize_report` (`devloop:3957`). Mermaid.

## Behavior
### Happy path
1. User runs `devloop`, picks "Run a spec"; the fzf preview shows the selected `.md` rendered by `glow`, wrapped to the preview pane width.
2. The run completes and writes its report as Markdown by default to `.devloop/reports/<slug>.md`.
3. User runs `devloop reports`, selects the report; `view_file` renders it with `glow` in a pager, in the terminal.
4. User runs `devloop doctor`; the output includes a `glow` line and the command returns non-zero if `glow` is missing.

### Edge cases
- `glow` not installed: previews fall back to the current `sed` slice and `view_file` falls back to `gum pager`/`$PAGER`/`cat`; runs and the menu still work; `devloop doctor` reports `[fail]` for `glow`.
- Non-Markdown file in a preview or `view_file` (an existing `.html` report, a track, a log): it is not piped through `glow`; `.html` still opens via `open`/`xdg-open`, other text uses the raw fallback.
- Preview width: `glow` is invoked with `-w "$FZF_PREVIEW_COLUMNS"` so wrapping matches the fzf pane.
- `--report-format html`: a run still writes `.devloop/reports/<slug>.md`? No — it writes `.devloop/reports/<slug>.html` (`devloop:2182`) and `view_file` opens it in the browser, exactly as today.
- `fzf` unavailable: unaffected; `ui_pick_from_file` keeps its existing `gum`/numbered/`sed` fallbacks (`devloop:1072-1089`).

## Acceptance criteria
1. With `glow` on `PATH`, the fzf preview command for a `.md` selection invokes `glow` with `-w "$FZF_PREVIEW_COLUMNS"` against the selected file, not `sed`.
2. `view_file` on a `.md` argument renders it through `glow` in a pager when TUI and a TTY are present and `glow` exists, and falls back to `gum pager`/`$PAGER`/`cat` when `glow` is absent.
3. A run invoked with no `--report-format` writes `.devloop/reports/<slug>.md` and writes no `.html` report.
4. A run invoked with `--report-format html` writes `.devloop/reports/<slug>.html`, and `view_file` opens it via `open`/`xdg-open`.
5. A non-Markdown file passed to the preview or to `view_file` is never piped through `glow` (a `.html` opens in the browser; a `.log` uses the raw fallback).
6. `devloop doctor` prints a `glow` status line and returns non-zero when `glow` is not installed.
7. `bash scripts/devloop_test.sh` passes, including the new glow-present, glow-absent, md-vs-non-md, and markdown-default-report assertions.

## Test plan
- Red: in `scripts/devloop_test.sh`, add assertions that fail before implementation: `devloop doctor` output contains a `glow` line and fails when a stub `glow` is removed from `PATH`; the spec-picker preview command string references `glow` and `FZF_PREVIEW_COLUMNS`; a default-format run produces `.devloop/reports/<slug>.md` and no `.html`; `view_file` on a `.md` calls a stub `glow` on `PATH`; `view_file` on a `.html` calls a stub `open`/`xdg-open` and not `glow`.
- Green: `bash scripts/devloop_test.sh`.
- Full: `bash scripts/devloop_test.sh`.
- Coverage: the shell runtime has no line-coverage tool; coverage is the fixture-style assertions above exercising glow-present, glow-absent, markdown vs html report, and md vs non-md view paths.

## Constraints
- Must: keep `glow` optional at runtime with a graceful fallback on every path, while making it a `devloop doctor` requirement; stay portable across macOS/Linux; quote all expansions.
- Must: pipe only `*.md` through `glow`; never render `.html` or logs through it.
- Must: pass `-w "$FZF_PREVIEW_COLUMNS"` to `glow` in the fzf preview so wrapping matches the pane.
- Avoid: a new keybind dashboard, a TUI framework or new language, mermaid, and committing `.devloop/` runtime artifacts.
- Existing convention: `ui_has_gum`/`ui_has_fzf` gating (`devloop:815-821`); `view_file` case-on-extension (`devloop:1710`); `devloop_doctor_command` per required tool (`scripts/skill_helpers.sh:190`, `:349-354`).

## Notes
- Highest-leverage change: the inline preview swap in `ui_pick_from_file` (`devloop:1069`) upgrades the spec, report, and track previews at once, since all three pickers share it. The fzf `--preview` is a shell string fzf evaluates in a subshell, so the glow-or-fallback guard must be inline (e.g. `case "{}" in *.md) command -v glow >/dev/null 2>&1 && glow -w "$FZF_PREVIEW_COLUMNS" {} || sed -n "1,200p" {} ;; *) sed -n "1,200p" {} ;; esac`), not a sourced bash function.
- HTML reports are authored by the reviewer agent in `synthesize_report` (`devloop:3957`), not by `render.py`; flipping the default to markdown changes only the default and the reading path, not report generation. `render.py` is the spec companion only and is retired by the sibling spec.
- Deferred follow-up (own spec): actionable fzf binds (`enter` run, `ctrl-e` edit, `ctrl-l` tail log) to turn the picker into a full dashboard. Out of this slice to keep it one PR.
- Sibling spec: `2026-06-19-ascii-specs-retire-html-renderer.md`. Independent file sets (runtime vs skills), aside from shared `scripts/devloop_test.sh` and `README.md` in different sections; ship in either order.
- Gaps: 0.
