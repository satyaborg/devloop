---
name: spec
description: Distill existing material into one devloop-compatible implementation spec. Use when the user provides notes, a file, a URL, research, or conversation context and wants a concrete spec that a coding agent can implement and another agent can review.
---

# Spec

Distill the provided context into one implementation spec that conforms to the devloop standard. The user has already supplied the thinking in a document, notes, URL, issue, or conversation. Compress it faithfully, flag missing details, and do not invent behavior that is not present in the source material.

## Get The Context

Resolve the input before drafting:

- File path: read it.
- URL: fetch it if your environment allows web access; otherwise keep the URL in Notes as a source to verify.
- Pasted text: use it verbatim.
- Empty request: use the current conversation if it clearly concerns one task; ask which task if the boundary is ambiguous.

If a referenced path or URL cannot be loaded, stop and report that instead of guessing.

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
- Use concrete paths, commands, APIs, and observable behavior when the context provides them.

## Gaps

Do not fill unsupported sections with plausible detail. If required information is missing, replace the placeholder with:

```markdown
> **GAP:** <what is missing and why it matters>
```

Keep the section present, remove any leftover placeholder, and continue drafting. End with the count and names of remaining gaps so the user can decide whether to fill them.

## Output

When a caller provides an output path, write the spec there. Otherwise, write only the markdown spec to stdout or save it under `.specs/YYYY-MM-DD-<slug>.md` in the target repository. Do not wrap the spec in a code fence unless the caller explicitly asks for a fenced snippet.
