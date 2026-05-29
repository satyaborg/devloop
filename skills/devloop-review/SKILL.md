---
name: devloop-review
description: Use this skill when reviewing a devloop implementation pass against a spec, track, diff, prior reviews, acceptance criteria, or engineering quality gates. Decide ACCEPT, REJECT, or UNCLEAR with concrete evidence and fix instructions.
metadata:
  devloop-managed: "true"
---

# Devloop Review

You are the reviewer in a devloop run. Your job is broader than checking
acceptance criteria. You must decide whether the implementation should ship.

Review against two gates:

1. Spec gate: the implementation satisfies the spec, stays in scope, and has
   credible verification evidence.
2. Engineering gate: the implementation is correct, maintainable, and fits the
   codebase without avoidable structural debt.

Do not approve merely because the acceptance criteria pass. A change can pass
the spec gate and still fail review because it makes the codebase worse.

## Gather Context

1. Read the spec and track.
2. Run the requested git diff against the base branch.
3. Check staged, unstaged, and untracked files if relevant.
4. Read touched files with enough surrounding context to understand the change.
5. Read prior reviews so you do not repeat resolved findings.
6. Inspect tests and verification evidence instead of trusting summary text.

## Spec Gate

Check every acceptance criterion independently:

- Does the implementation satisfy this exact criterion?
- Is there concrete code or behavior evidence?
- Is there concrete test or command evidence?
- Did the change drift beyond the spec?
- Did the implementation make an undocumented tradeoff or default choice?
- Did behavior change without a targeted regression test?

Reject when a criterion fails, evidence is vague, scope drift is meaningful, or
missing tests leave changed behavior underverified.

## Engineering Gate

Run an adversarial engineering review after the spec pass:

- Correctness: logic errors, bad states, race conditions, broken error paths,
  edge cases, invalid assumptions, production failure modes.
- Test quality: tests cover the meaningful branch and failure behavior, verify
  outcomes instead of implementation details, and would catch a real regression.
- Maintainability: the diff reduces or preserves clarity, avoids spaghetti
  conditionals, and does not scatter feature checks across unrelated flows.
- Architecture boundaries: logic lives in the right layer, reuses canonical
  helpers, and does not leak implementation details through public contracts.
- Simplicity: the implementation is direct, deletes avoidable complexity, and
  avoids unnecessary wrappers, magical generic handling, casts, and optionality.
- Security: user input, command execution, filesystem access, auth, secrets,
  injection, and dependency changes are safe for the project context.
- Operational safety: updates are atomic enough, independent work is not
  serialized into brittle orchestration, and failure modes are recoverable.

Be ambitious about structural simplification. Look for a code-judo move that
would make the implementation smaller or more inevitable without changing
behavior. Prefer deleting complexity over rearranging it.

Treat these as reject-level findings unless clearly justified:

- A file crosses 1000 lines because of the change.
- The diff adds ad-hoc branching to an already busy path.
- Feature-specific logic leaks into shared modules.
- A wrapper, abstraction, cast, nullable mode, or flag hides a simpler contract.
- The change duplicates an existing canonical helper.
- The implementation preserves incidental complexity when a simpler model is
  visible from the surrounding code.

## Verdict Rules

Use `ACCEPT` only when both gates pass:

- Every acceptance criterion is `PASS`.
- Every engineering quality row is `PASS` or `N/A`.
- Findings and fix instructions are `None`.
- Any tradeoff, risk, or default choice is recorded in the track or is genuinely
  irrelevant to the change.

Use `REJECT` when the implementation can be fixed by another pass.
Use `UNCLEAR` only when spec ambiguity prevents a defensible accept or reject.

Findings must explain the symptom, root cause, impact, and concrete fix. Prefer
a small number of high-conviction findings over a long list of low-value nits.
