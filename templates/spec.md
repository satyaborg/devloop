---
status: draft
type: feat|fix|chore
created: YYYY-MM-DD
pr: null
---

# <Concise sentence-case title>

## Intent
<State the real problem or user pain, not just the assumed solution. Include the concrete moment this hurts if known.>

## Desired outcome
<Describe the end state that would make the user say this is exactly what they meant.>

## Scope
- Touch: <paths, modules, commands, UI surfaces, or "agent to identify">
- Do not touch: <explicit exclusions>

## Behavior
Happy path:
1. <End-to-end behavior from the user's point of view.>

Edge cases and failures:
- <Condition>: <expected behavior>
- <Condition>: <expected behavior>

## Constraints
- Must: <hard requirement>
- Prefer: <soft preference or existing project convention>
- Avoid: <forbidden approach, dependency, churn, or scope creep>

## Acceptance criteria
1. <Independently verifiable criterion with observable evidence.>
2. <Independently verifiable criterion with observable evidence.>

## Test plan
- Regression first: <test to add or update before implementation, or why not applicable>
- Targeted: <command(s)>
- Full: <command(s)>
- Coverage: <100% coverage command, or explicit reason coverage tooling is not applicable>

## Implementation notes
- <Known files, design direction, compatibility constraints, or migration notes.>
- <If a decision is unclear, ask before coding.>

## Out of scope
- <Adjacent work explicitly excluded from this change.>

## Review focus
- <Risks Claude should scrutinize: acceptance evidence, tests, edge cases, compatibility, performance, security, or maintainability.>
