---
name: devloop-spec
description: Use this skill when the user wants one devloop-ready implementation spec from a rough idea, interview, notes, file, URL, issue, research, or conversation context. Also use for /spec-style requests, "turn this into a spec", "write a spec", "spec out this research", "draft a devloop spec", or when devloop launches an agent to create a spec. Interview for cold starts, ambiguous scope, or open questions; distill only well-scoped source material.
metadata:
  devloop-managed: "true"
---

# Devloop Spec

Produce exactly one implementation spec that conforms to the devloop standard. This is the canonical spec skill for devloop.

Use this skill for interviews and for distilling already well-scoped material. Do not hand off to a separate interview or spec-writing skill.

The markdown spec is the source of truth that `devloop` will use as implementation input. Author diagrams as ASCII art inside plain code fences so terminal readers, GitHub, and plain text show the same schematic.

Available resources:

- `references/spec-template.md`: read when drafting or validating the spec shape.

## Scope Guard

Write exactly one spec sized for one worktree and one PR. Push back before drafting when the request mixes multiple logical changes, depends on an unresolved preparatory refactor, or would plausibly exceed about 300 meaningful changed lines.

When interactive, name the overflow, propose the smallest useful slice, and ask the user to confirm before writing. When non-interactive and the source is otherwise implementation-ready, spec the first foundational slice and list deferred work in Notes as follow-up specs.

## Interview Gate

Before drafting, decide whether the source is implementation-ready. Start or continue an interview when any of these are true:

- No source material was provided.
- The source is a conversation, artifact bundle, notes, or research with multiple plausible implementation slices.
- The problem, outcome, scope, behavior, acceptance criteria, test expectations, or owner repo is missing or contradictory.
- An open question could change the files touched, user-visible behavior, acceptance criteria, spec type, or implementation slice.
- The request is broad or vague, such as "fix this", "improve this", "audit this", or "turn this conversation into a spec" without a clear target outcome.

Do not convert a conversation, artifact bundle, or notes directly into a spec just because there is enough text. Existing material only qualifies for direct distillation when it identifies one worktree-sized change and enough concrete requirements to draft without TODOs, TBDs, GAP markers, or invented detail.

When interactive, ask one question at a time until the gate passes. When the environment cannot ask questions, write a marked draft only if the caller explicitly needs best-effort non-interactive output; otherwise stop with the questions that must be answered.

## Source Resolution

Resolve the source material before drafting:

- File path: read it.
- URL: fetch it if the environment allows web access; otherwise record the URL in Notes as a source to verify.
- Pasted text: use it verbatim.
- Current conversation: use only the part clearly about this task; ask for the boundary if the conversation covers unrelated work.
- No source material: use the interview path.

After loading any source, run the Interview Gate. Source presence does not imply direct drafting.

If a path or URL will not load, say so and stop unless the caller explicitly asks for a best-effort draft.

## Interview

Use this mode when there is no document, URL, issue, or concrete context to distill, or when supplied material leaves scope or requirements open.

- Ask one question at a time.
- Ask why before what.
- Use the host agent's normal user-question mechanism when available; otherwise ask concise plain-text questions.
- Skip obvious questions the repository or prior answers already settle.
- Push vague answers toward observable behavior and acceptance criteria.
- Name contradictions and ask which statement is true.
- Stop only when the spec can be written without TODOs, TBDs, GAP markers, or invented requirements.

Cover these points:

1. The actual problem and when it hurts.
2. The desired observable outcome.
3. Happy path behavior.
4. Edge cases and failure modes.
5. Files, commands, APIs, UI surfaces, or workflows in scope.
6. Explicitly out-of-scope work.
7. Hard constraints, existing conventions, and test expectations.

If the environment cannot ask interactive questions and the caller needs best-effort output, write a draft with explicit `> **GAP:** ...` markers rather than inventing missing facts.

## Distill Existing Material

Use this path only after the Interview Gate passes.

Do not fill unsupported sections with plausible detail. Every line must trace to supplied context, repository evidence, or an explicit user answer.

If the spec depends on something cheap to verify, verify it rather than asserting it. Examples: file existence, command names in `package.json` or `pyproject.toml`, API paths in a router, or repo-local test commands.

## Standard

Read `references/spec-template.md` when creating the draft. Every section appears in this order. Frontmatter uses exactly these fields:

````markdown
---
status: draft
type: feat|fix|chore
created: YYYY-MM-DD
pr: null
---

# <Concise title>
<One-sentence subtitle that names the implementation slice and why it matters.>

```
  current             change                 result
  -------             ------                 ------
  Current behavior -> Implementation change -> Expected outcome
```

## Problem
<The real user pain or failure. Include the concrete moment this hurts.>

## Outcome
<The observable end state that means this worked.>

## Scope
- In: <paths, commands, APIs, UI surfaces, or behavior>
- Out: <explicit exclusions>

## Behavior
### Happy path
1. <User/system action>
2. <Expected observable result>

### Edge cases
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
````

- `created` is today's date.
- Infer `type`: `feat` for new capability, `fix` for broken behavior, and `chore` for maintenance, docs, tests, dependencies, or refactors.
- The H1 is a concise title, not a sentence.
- The subtitle is a plain one-sentence line directly under the H1.
- The ASCII schematic is optional but preferred when it clarifies architecture, data flow, ownership, or before/after behavior. Omit it if it would be decorative or speculative.
- Put schematics inside a plain code fence: three backticks on a line by themselves, ASCII diagram lines, then three closing backticks.
- Under `## Behavior`, use `### Happy path` and `### Edge cases` H3 headings, not plain `Happy path:` labels.
- Acceptance criteria must be singular, verifiable, and observable.
- Include concrete paths, commands, APIs, and behaviors when the context provides them.

## Gaps

When required information is still missing and the caller explicitly needs a best-effort non-interactive draft, replace that section's placeholder with:

```markdown
> **GAP:** <what is missing and why it matters>
```

Keep every standard section present, remove leftover placeholders, and list the count and names of remaining gaps in Notes.

If interactive and gaps remain, do not draft yet. Ask the next interview question instead.

## Output Path

Do not hard-code personal paths. Use this precedence:

1. If devloop or the caller provides a requested output path, write exactly there unless it would overwrite a file and overwrite permission is absent.
2. If devloop or the caller provides a requested output directory or spec directory, write `YYYY-MM-DD-<slug>.md` there.
3. If the user provides `target=<dir>`, write `<dir>/<slug>.md` for duet/devloop compatibility.
4. If a target repo can be resolved from the current working directory, an explicit target repo, or a source file path, write `<repo>/.devloop/specs/YYYY-MM-DD-<slug>.md` and create the directory if needed.
5. Otherwise, write only the markdown spec to stdout.

Do not wrap the spec in a code fence unless the caller explicitly asks for a fenced snippet.

## Signoff

After writing, report the spec path, inferred `type`, acceptance criteria, and remaining gaps. Offer `devloop --create-pr <spec path>` as the next handoff when a file path exists.
