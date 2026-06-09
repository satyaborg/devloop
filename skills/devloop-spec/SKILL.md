---
name: devloop-spec
description: Use this skill when the user wants a devloop-ready implementation spec from a rough idea, notes, file, URL, issue, research, or conversation context. Interview from a cold start when source material is too thin; otherwise distill the provided material into one concrete spec.
metadata:
  devloop-managed: "true"
---

# Devloop Spec

Produce one implementation spec that conforms to the devloop standard. This skill has two modes:

- Cold start: if the user has not provided enough source material, interview them one question at a time until the implementation target is clear.
- Distill: if the user supplied notes, a file, a URL, research, an issue, or conversation context, compress that material faithfully and flag any remaining gaps.

The output is the spec that `devloop` will use as its implementation input.

When a starter document is needed, read `references/spec-template.md`.

## Scope Guard

Write exactly one spec sized for one worktree and one PR. Push back before drafting when the request mixes multiple logical changes, depends on an unresolved preparatory refactor, or would plausibly exceed about 300 meaningful changed lines.

When the scope is too large, name the overflow, propose the smallest useful slice, and ask the user to confirm the slice before writing.

## Cold Start Interview

Use this mode when there is no document, URL, issue, or concrete context to distill.

- Ask one question at a time.
- Ask why before what.
- Skip obvious questions the repository or prior answers already settle.
- Push vague answers toward observable behavior and acceptance criteria.
- Name contradictions and ask which statement is true.
- Stop only when the spec can be written without TODOs, TBDs, or invented requirements.

Cover these points:

1. The actual problem and when it hurts.
2. The desired observable outcome.
3. Happy path behavior.
4. Edge cases and failure modes.
5. Files, commands, APIs, UI surfaces, or workflows in scope.
6. Explicitly out-of-scope work.
7. Hard constraints, existing conventions, and test expectations.

If the environment cannot ask interactive questions, write a draft with explicit `> **GAP:** ...` markers rather than inventing missing facts.

## Distill Existing Material

Resolve the input before drafting:

- File path: read it.
- URL: fetch it if the environment allows web access; otherwise record the URL in Notes as a source to verify.
- Pasted text: use it verbatim.
- Current conversation: use only the part clearly about this task; ask for the boundary if the conversation covers unrelated work.

Do not fill unsupported sections with plausible detail. Every line must trace to supplied context, repository evidence, or an explicit user answer.

## Standard

Every section appears in this order. Frontmatter uses exactly these fields:

```markdown
---
status: draft
type: feat|fix|chore
created: YYYY-MM-DD
pr: null
---

# <Concise title>

## Problem
<The real user pain or failure. Include the concrete moment this hurts.>

## Outcome
<The observable end state that means this worked.>

## Scope
- In: <paths, commands, APIs, UI surfaces, or behavior>
- Out: <explicit exclusions>

## Behavior
Happy path:
1. <User/system action>
2. <Expected observable result>

Edge cases:
- <Condition>: <expected result>

## Acceptance criteria
1. <Singular, verifiable requirement with observable evidence.>

## Test plan
- Red: <regression test to add/update first, or why not applicable>
- Green: <targeted command(s)>
- Full: <full test/typecheck/lint command(s)>
- Coverage: <100% coverage command, or why unavailable>

## Constraints
- Must: <hard requirement>
- Avoid: <forbidden approach, dependency, or churn>
- Existing convention: <repo pattern to preserve>

## Notes
<Only material implementation hints, risks, dependencies, migrations, or open questions.>
```

- `created` is today's date.
- Infer `type`: `feat` for new capability, `fix` for broken behavior, and `chore` for maintenance, docs, tests, dependencies, or refactors.
- The H1 is a concise title, not a sentence.
- Acceptance criteria must be singular, verifiable, and observable.
- Include concrete paths, commands, APIs, and behaviors when the context provides them.

## Gaps

When required information is still missing, replace that section's placeholder with:

```markdown
> **GAP:** <what is missing and why it matters>
```

Keep every standard section present, remove leftover placeholders, and list the count and names of remaining gaps in Notes.

## Output

When a caller provides an output path, write the spec there. Otherwise, write only the markdown spec to stdout or save it under the caller's requested default spec directory, usually `.devloop/specs/YYYY-MM-DD-<slug>.md`. Do not wrap the spec in a code fence unless the caller explicitly asks for a fenced snippet.
