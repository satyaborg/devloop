#!/usr/bin/env bash
set -euo pipefail

# devloop.sh — codex implements, claude reviews, loop till ACCEPT/max/stall.
# Usage: devloop.sh <spec.md> [max]

SPEC="${1:-}"; MAX="${2:-5}"
[[ -z "$SPEC" || ! -f "$SPEC" ]] && { echo "usage: devloop.sh <spec.md> [max=5]" >&2; exit 2; }
(( MAX < 1 )) && MAX=1; (( MAX > 10 )) && MAX=10

command -v claude >/dev/null || { echo "claude not on PATH" >&2; exit 2; }
command -v codex  >/dev/null || { echo "codex not on PATH" >&2; exit 2; }

SPEC=$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")
REPO=$(git -C "$(dirname "$SPEC")" rev-parse --show-toplevel 2>/dev/null) \
  || { echo "spec is not inside a git repo" >&2; exit 2; }
cd "$REPO"

SLUG=$(basename "$SPEC" .md)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' \
       || (git show-ref --verify -q refs/heads/main && echo main) \
       || (git show-ref --verify -q refs/heads/master && echo master) \
       || echo main)

mkdir -p .codex/tracks .codex/reviews .codex/reports .codex/logs
TRACK=".codex/tracks/$SLUG.md"
REPORT=".codex/reports/$SLUG.md"

[[ -f "$TRACK" ]] || cat > "$TRACK" <<EOF
# Track: $SLUG

- spec: $SPEC
- base: $BASE
- branch: $BRANCH
- max: $MAX
- started: $(date -u +%Y-%m-%dT%H:%M:%SZ)

EOF

log() { printf '\033[36m[devloop]\033[0m %s\n' "$*" >&2; }

run_codex() {
  local log_file="$1"; shift
  codex exec --dangerously-bypass-approvals-and-sandbox -C "$REPO" - 2>&1 | tee "$log_file"
}

run_claude() {
  local log_file="$1"; shift
  claude -p --dangerously-skip-permissions --add-dir "$REPO" 2>&1 | tee "$log_file" >/dev/null
}

findings_hash() {
  awk '/^## Findings/{f=1;next} /^## /{f=0} f' "$1" \
    | sed -E 's/[0-9]+//g; s/[[:space:]]+/ /g' | sort -u | sha256sum | awk '{print $1}'
}

status="unknown"; prior=""; N=0

for ((N=1; N<=MAX; N++)); do
  log "pass $N/$MAX — codex"
  CODEX_LOG=".codex/logs/$SLUG-r$N-codex.log"

  if (( N == 1 )); then
    PROMPT=$(cat <<EOF
You are implementing against an approved spec.

Spec: $SPEC
Track: $TRACK
Pass: $N

Tasks:
1. Read the spec.
2. Implement the smallest working change that satisfies the acceptance criteria.
3. Run relevant tests/linters/type checks for the languages touched.
4. Append a markdown section to $TRACK titled "## Pass $N — implement" with:
   - changed files
   - key design decisions AND the tradeoff you weighed for each (one line each)
   - verification commands run and outcomes
   - residual risk or blockers

Constraints:
- Do not commit.
- Do not edit the spec.
- Do not revert unrelated dirty files.
EOF
)
  else
    PREV=".codex/reviews/$SLUG-r$((N-1)).md"
    PROMPT=$(cat <<EOF
Fix only the findings in the review. Do not refactor unrelated code.

Spec: $SPEC
Track: $TRACK
Review: $PREV
Pass: $N

Tasks:
1. Read the review file.
2. Fix each finding. If a finding is wrong, explain why in the track instead of silently ignoring.
3. Re-run relevant tests/linters.
4. Append "## Pass $N — fix" to $TRACK with per-finding outcomes and the principle behind each fix.
EOF
)
  fi

  printf '%s' "$PROMPT" | run_codex "$CODEX_LOG" || { status="codex-error"; break; }

  log "pass $N — claude review"
  REVIEW=".codex/reviews/$SLUG-r$N.md"
  CLAUDE_LOG=".codex/logs/$SLUG-r$N-claude.log"
  PRIORS=$(ls -1 .codex/reviews/$SLUG-r*.md 2>/dev/null | sort -V | tr '\n' ' ' || true)

  PROMPT=$(cat <<EOF
You are reviewing a Codex implementation. Be a senior reviewer, not a linter.

Spec: $SPEC
Track: $TRACK
Base: $BASE
Pass: $N
Prior reviews: $PRIORS
Output path: $REVIEW

Steps:
1. Read the spec and the track.
2. Run: git diff $BASE...HEAD
3. Read all prior review files (if any) so you do not repeat resolved findings or contradict yourself.
4. Write the review to $REVIEW using this exact format:

# Claude review $N

Verdict: <ACCEPT | REJECT | UNCLEAR>

## Findings

1. [severity] <file:line> — <symptom>. Root cause: <why this happened>. Principle: <what design/correctness principle it violates>.

## Missing tests

- <gap, or None>

## Fix instructions

1. <standalone instruction Codex can act on without your context>

## Notes

- <scope, disputes, lessons surfaced, or None>

Rules:
- The line "Verdict: ACCEPT" or "Verdict: REJECT" or "Verdict: UNCLEAR" must appear verbatim.
- For ACCEPT: "## Findings" body is "None" and "## Fix instructions" body is "None".
- Findings must explain WHY, not just WHAT. If you cannot articulate the principle, the finding is too shallow — drop it or sharpen it.
- Rubric: acceptance criteria, bugs, edge cases, missing tests, scope creep, security/perf/compat/migration risk.
EOF
)

  printf '%s' "$PROMPT" | run_claude "$CLAUDE_LOG" || { status="claude-error"; break; }
  [[ -f "$REVIEW" ]] || { status="review-missing"; break; }

  V=$(grep -m1 -oE '^Verdict:[[:space:]]+(ACCEPT|REJECT|UNCLEAR)' "$REVIEW" | awk '{print $2}' || true)
  log "pass $N verdict: ${V:-MISSING}"

  case "$V" in
    ACCEPT)  status="accepted"; break ;;
    UNCLEAR) status="unclear"; break ;;
    REJECT)
      h=$(findings_hash "$REVIEW")
      [[ -n "$prior" && "$h" == "$prior" ]] && { status="stalled"; break; }
      prior="$h"
      ;;
    *) status="no-verdict"; break ;;
  esac
done

[[ "$status" == "unknown" ]] && status="max-turns"

log "synthesizing report"
PRIORS=$(ls -1 .codex/reviews/$SLUG-r*.md 2>/dev/null | sort -V | tr '\n' ' ' || true)

SYNTH_PROMPT=$(cat <<EOF
You are writing a learning-oriented post-mortem for a developer who just ran a Codex/Claude devloop.
This is NOT an audit log. It is a teaching artifact. The reader should come away understanding WHY
each decision was made and what to internalize for next time.

Inputs:
- spec: $SPEC
- track: $TRACK
- review files: $PRIORS
- final status: $status
- passes used: $N / $MAX
- base: $BASE, branch: $BRANCH

Run: git diff --stat $BASE...HEAD   (for context only; do not paste the full diff)

Write the report to $REPORT in this structure. Be concrete, no filler, no recap of what the reader can see in the diff:

# $SLUG — devloop report

**Result:** $status in $N pass(es). <one-sentence headline of what shipped and the single most important thing learned.>

## The shape of the problem
<2-4 sentences: what the spec actually asked for, the real constraint behind it, and which alternative designs were ruled out and why. If the track or reviews surfaced a hidden assumption, name it.>

## What was built
<3-6 bullets describing the implementation at the level of design choices, not file lists. For each non-trivial choice, name the tradeoff that was weighed. The reader should be able to defend each choice in code review.>

## What the review caught (and why it mattered)
<For each unique finding across all review passes — even resolved ones — write one paragraph: the symptom, the root cause, and the principle. Group recurring themes. If a class of bug appeared twice, call that out as a pattern to internalize. If nothing was caught, say so and speculate on why (was the spec tight, was the change small, did the reviewer miss something).>

## What to remember next time
<3-5 sharp, transferable lessons. Each lesson must be actionable in a future task, not specific to this slug. Frame as "When X, prefer Y because Z." If there is nothing transferable, write a single line saying so honestly.>

## Residual risk
<Concrete remaining risks, or "None known". Be specific — "untested on empty input" beats "edge cases".>

## Pointers
- Spec: $SPEC
- Track: $TRACK
- Reviews: $PRIORS

Style:
- Terse, dense, no hedging.
- No headers beyond the ones above.
- No emoji.
- Optimize for a developer who will read this once, six weeks from now, and needs to extract the lesson in 90 seconds.
EOF
)

printf '%s' "$SYNTH_PROMPT" | claude -p --dangerously-skip-permissions --add-dir "$REPO" \
  > ".codex/logs/$SLUG-report.log" 2>&1 \
  || log "report synthesis failed; see .codex/logs/$SLUG-report.log"

if command -v pandoc >/dev/null && [[ -f "$REPORT" ]]; then
  pandoc -s --metadata title="devloop: $SLUG" -o "${REPORT%.md}.html" "$REPORT" 2>/dev/null \
    && log "html: ${REPORT%.md}.html"
fi

echo
echo "result:  $status"
echo "passes:  $N / $MAX"
echo "report:  $REPORT"
echo "track:   $TRACK"

case "$status" in
  accepted) exit 0 ;;
  stalled|max-turns|unclear) exit 1 ;;
  *) exit 2 ;;
esac
