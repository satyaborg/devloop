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
- <Condition>: <expected result>

## Acceptance criteria
1. <Singular, verifiable requirement with observable evidence.>
2. <Singular, verifiable requirement with observable evidence.>

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
