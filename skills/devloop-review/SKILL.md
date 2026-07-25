---
name: devloop-review
description: Use this skill when reviewing a devloop implementation pass against a spec, track, diff, prior reviews, acceptance criteria, or engineering quality gates. Decide ACCEPT, REJECT, or UNCLEAR with concrete evidence and fix instructions.
metadata:
  devloop-managed: "true"
---

# Devloop Review

You are the reviewer in a devloop run. Your job is broader than checking
acceptance criteria. You must decide whether the implementation should ship.

Review against the first two gates. Apply the third gate only when the prompt
says `Strict verification: enabled`.

1. Spec gate: the implementation satisfies the spec, stays in scope, and has
   credible verification evidence.
2. Engineering gate: the implementation is correct, maintainable, and fits the
   codebase without avoidable structural debt.
3. Verification gate: every declared test suite and applicable CI check has
   completed, and its result supports the verdict.

Do not approve merely because the spec obligations pass. A change can pass the
spec gate and still fail review because it makes the codebase worse.

## Gather Context

1. Read the spec and track.
2. Run the requested git diff against the base branch.
3. Check staged, unstaged, and untracked files if relevant.
4. Read touched files with enough surrounding context to understand the change.
5. Read prior reviews so you do not repeat resolved findings.
6. Inspect tests and verification evidence instead of trusting summary text.

Treat review output, agent summaries, and test summaries as advisory. Verify
each candidate finding by reading the real code path and adjacent ownership
boundaries before accepting it as blocking. When a finding depends on framework,
dependency, shell, platform, or API behavior, verify that contract from docs,
types, source, or executable evidence.

Reject speculative risks, unrealistic edge cases, style-only nits, broad
rewrites, and fixes that would complicate the codebase without improving a spec
or engineering gate.

When a real finding exposes a bug class or repeated pattern, inspect the current
diff and touched ownership boundary for sibling instances. Report the scoped
bug class when practical, but stop at clear ownership boundaries and leave
unrelated follow-up territory out of the devloop pass.

## Verification

Skip this section when the prompt says `Strict verification: disabled`.

Discover declared test suites only from README or CONTRIBUTING test
instructions, manifest test scripts, test configuration, and CI test jobs.
Run every declared test suite that is safe for local review. Record each exact
command and result.
Never run deploy, publish, release, seed, or migration commands.
Do not run any command that mutates state outside the worktree. Do not
substitute the implementer's reported results for a reviewer run. Use `N/A`
only when the repository declares no test suite.

Inspect CI configuration to determine which workflows apply. Capture
`git rev-parse HEAD`, confirm it matches the pull request's `headRefOid`, and
poll `gh pr checks "<pull-request>" --json bucket,name,link` every 15 seconds.
Stop after the prompt's cap, which is at most 10 minutes. Confirm the pull
request head still matches the reviewed SHA before recording the result.

If no check registers inside the cap, record CI as `N/A` with the reason. If CI
cannot be queried, the pull request head changes, or registered checks remain
pending at the cap, record CI as `FAIL` and write an `UNCLEAR` review with the
blocker. Always write the review after the bounded attempt.

Factor completed test and CI results into the verdict and relevant acceptance
and engineering evidence. Reject when any applicable test suite or CI check
fails. If a safe declared test suite cannot run, record it as `FAIL` and write
an `UNCLEAR` review with the blocker.

## Spec Gate

Check every spec obligation independently:

- Does the implementation satisfy this exact acceptance criterion, invariant,
  or failure mode?
- Is there concrete code or behavior evidence?
- Is there concrete test or command evidence?
- Did the change drift beyond the spec?
- Did the implementation make an undocumented tradeoff or default choice?
- Did behavior change without a targeted regression test?
- If this pass fixes a prior review finding, was verification rerun after the
  fix instead of reused from before the code changed?

Reject when an obligation fails, evidence is vague, scope drift is meaningful,
or missing tests leave changed behavior underverified.

Do not flag work required solely by an invariant or failure mode as scope drift.
Scope drift is work outside the spec's declared scope or not needed to satisfy
any listed obligation.

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

Report security findings only when the change creates a concrete, actionable
risk or removes an important safety check. Do not block legitimate functionality
for generic security posture advice.

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

Use `ACCEPT` only when all active gates pass:

- Every acceptance criterion, invariant, and failure mode is `PASS`.
- Every engineering quality row is `PASS` or `N/A`.
- When strict verification is enabled, test suites and CI are `PASS` or
  genuinely `N/A`.
- Findings and fix instructions are `None`.
- Any tradeoff, risk, or default choice is recorded in the track or is genuinely
  irrelevant to the change.

Use `REJECT` when the implementation can be fixed by another pass.
Use `UNCLEAR` only when spec ambiguity or unavailable verification prevents a
defensible accept or reject.

Findings must explain the symptom, root cause, impact, and concrete fix. Prefer
a small number of high-conviction findings over a long list of low-value nits.
