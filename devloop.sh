#!/usr/bin/env bash
set -euo pipefail

# devloop.sh — codex implements, claude reviews, loop till ACCEPT/max/stall.
# Usage: devloop.sh [--report-format html|markdown] <spec.md> [max]

usage() {
  echo "usage: devloop.sh [--report-format html|markdown] <spec.md> [max=5]" >&2
}

REPORT_FORMAT="html"
SPEC=""
MAX_RAW="5"
MAX_SET=0

while (($#)); do
  case "$1" in
    --report-format)
      shift
      [[ $# -gt 0 ]] || { usage; exit 2; }
      REPORT_FORMAT="$1"
      ;;
    --html)
      REPORT_FORMAT="html"
      ;;
    --markdown|--md)
      REPORT_FORMAT="markdown"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -z "$SPEC" ]]; then
        SPEC="$1"
      elif (( MAX_SET == 0 )); then
        MAX_RAW="$1"
        MAX_SET=1
      else
        usage
        exit 2
      fi
      ;;
  esac
  shift
done

case "$REPORT_FORMAT" in
  html|markdown) ;;
  md) REPORT_FORMAT="markdown" ;;
  *) echo "report format must be html or markdown" >&2; exit 2 ;;
esac

[[ -z "$SPEC" || ! -f "$SPEC" ]] && { usage; exit 2; }

[[ "$MAX_RAW" =~ ^[+-]?[0-9]+$ ]] || { echo "max must be an integer between 1 and 10" >&2; exit 2; }
MAX_SIGN=1
MAX_DIGITS="$MAX_RAW"
case "$MAX_DIGITS" in
  -*) MAX_SIGN=-1; MAX_DIGITS="${MAX_DIGITS#-}" ;;
  +*) MAX_DIGITS="${MAX_DIGITS#+}" ;;
esac
MAX=$(( MAX_SIGN * 10#$MAX_DIGITS ))
(( MAX < 1 )) && MAX=1; (( MAX > 10 )) && MAX=10

command -v claude >/dev/null || { echo "claude not on PATH" >&2; exit 2; }
command -v codex  >/dev/null || { echo "codex not on PATH" >&2; exit 2; }

RUN_DIR=$(pwd -P)
SPEC=$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")
REPO=$(git -C "$RUN_DIR" rev-parse --show-toplevel 2>/dev/null) \
  || { echo "current directory is not inside a git repo" >&2; exit 2; }
cd "$REPO"

SLUG=$(basename "$SPEC" .md)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' \
       || (git show-ref --verify -q refs/heads/main && echo main) \
       || (git show-ref --verify -q refs/heads/master && echo master) \
       || echo main)

mkdir -p .codex/tracks .codex/reviews .codex/reports .codex/logs .codex/sessions
TRACK=".codex/tracks/$SLUG.md"
if [[ "$REPORT_FORMAT" == "html" ]]; then
  REPORT=".codex/reports/$SLUG.html"
else
  REPORT=".codex/reports/$SLUG.md"
fi
CODEX_SESSION_FILE=".codex/sessions/$SLUG-codex.id"
CLAUDE_SESSION_FILE=".codex/sessions/$SLUG-claude.id"

[[ -f "$TRACK" ]] || cat > "$TRACK" <<EOF
# Track: $SLUG

- spec: $SPEC
- cwd: $RUN_DIR
- base: $BASE
- branch: $BRANCH
- max: $MAX
- report-format: $REPORT_FORMAT
- started: $(date -u +%Y-%m-%dT%H:%M:%SZ)

EOF

log() { printf '\033[36m[devloop]\033[0m %s\n' "$*" >&2; }

read_one_line() {
  local path="$1" value=""
  [[ -f "$path" ]] || return 0
  IFS= read -r value < "$path" || true
  printf '%s' "$value"
}

write_one_line() {
  local path="$1" value="$2"
  printf '%s\n' "$value" > "$path"
}

new_uuid() {
  if command -v uuidgen >/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi
  if command -v python3 >/dev/null; then
    python3 -c 'import uuid; print(uuid.uuid4())'
    return
  fi
  echo "uuidgen or python3 not on PATH" >&2
  return 127
}

extract_session_id() {
  local log_file="$1"
  # Codex currently prints the resumable UUID in human-readable session/thread
  # banners, commonly "To continue this session..." or "session id/thread_id".
  # If those banners change, fail loudly instead of starting a fresh fix session.
  grep -Ei '(session.?id|thread_id|codex exec resume|codex resume|To continue this session)' "$log_file" \
    | grep -Eio '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    | tail -n 1
}

assert_repo_cwd() {
  local cwd
  cwd=$(pwd -P)
  [[ "$cwd" == "$REPO" ]] || { echo "internal error: expected cwd $REPO, got $cwd" >&2; return 1; }
}

run_codex() {
  local log_file="$1"; shift
  local session_id
  assert_repo_cwd || return
  session_id=$(read_one_line "$CODEX_SESSION_FILE")

  if [[ -n "$session_id" ]]; then
    codex exec resume --dangerously-bypass-approvals-and-sandbox "$session_id" - 2>&1 | tee "$log_file"
    return
  fi

  codex exec --dangerously-bypass-approvals-and-sandbox -C "$REPO" - 2>&1 | tee "$log_file"
  session_id=$(extract_session_id "$log_file" || true)
  [[ -n "$session_id" ]] || { echo "could not determine codex session id from $log_file" >&2; return 1; }
  write_one_line "$CODEX_SESSION_FILE" "$session_id"
  log "codex session: $session_id"
}

run_claude() {
  local log_file="$1"; shift
  local session_id
  session_id=$(read_one_line "$CLAUDE_SESSION_FILE")

  if [[ -n "$session_id" ]]; then
    claude -p --resume "$session_id" --dangerously-skip-permissions --add-dir "$REPO" 2>&1 | tee "$log_file" >/dev/null
    return
  fi

  session_id=$(new_uuid) || return
  claude -p --session-id "$session_id" --dangerously-skip-permissions --add-dir "$REPO" 2>&1 | tee "$log_file" >/dev/null
  write_one_line "$CLAUDE_SESSION_FILE" "$session_id"
  log "claude session: $session_id"
}

list_reviews() {
  local i file
  for ((i=1; i<=MAX; i++)); do
    file=".codex/reviews/$SLUG-r$i.md"
    [[ -f "$file" ]] && printf -- '- %s\n' "$file"
  done
  return 0
}

hash_stdin() {
  if command -v sha256sum >/dev/null; then
    sha256sum | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null; then
    shasum -a 256 | awk '{print $1}'
    return
  fi
  echo "sha256sum or shasum not on PATH" >&2
  return 127
}

findings_hash() {
  awk '/^## Findings/{f=1;next} /^## /{f=0} f' "$1" \
    | sed -E 's/[0-9]+//g; s/[[:space:]]+/ /g' | sort -u | hash_stdin
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
  PRIORS=$(list_reviews)

  PROMPT=$(cat <<EOF
You are reviewing a Codex implementation. Be a senior reviewer, not a linter.

Spec: $SPEC
Track: $TRACK
Base: $BASE
Pass: $N
Prior reviews:
$PRIORS
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
PRIORS=$(list_reviews)

if [[ "$REPORT_FORMAT" == "html" ]]; then
  REPORT_INSTRUCTIONS=$(cat <<EOF
Write the report to $REPORT as valid standalone HTML. Include a concise <title>, semantic sections, and minimal embedded CSS for readable typography. Do not wrap the HTML in a markdown code fence. Be concrete, no filler, no recap of what the reader can see in the diff.

Use this content structure, with these visible section headings and no others:

<h1>$SLUG — devloop report</h1>

Opening result line:
<strong>Result:</strong> $status in $N pass(es). <one-sentence headline of what shipped and the single most important thing learned.>

<section>
<h2>The shape of the problem</h2>
<p>2-4 sentences: what the spec actually asked for, the real constraint behind it, and which alternative designs were ruled out and why. If the track or reviews surfaced a hidden assumption, name it.</p>
</section>

<section>
<h2>What was built</h2>
<ul><li>3-6 bullets describing the implementation at the level of design choices, not file lists. For each non-trivial choice, name the tradeoff that was weighed. The reader should be able to defend each choice in code review.</li></ul>
</section>

<section>
<h2>What the review caught (and why it mattered)</h2>
<p>For each unique finding across all review passes — even resolved ones — write one paragraph: the symptom, the root cause, and the principle. Group recurring themes. If a class of bug appeared twice, call that out as a pattern to internalize. If nothing was caught, say so and speculate on why: was the spec tight, was the change small, did the reviewer miss something.</p>
</section>

<section>
<h2>What to remember next time</h2>
<ul><li>3-5 sharp, transferable lessons. Each lesson must be actionable in a future task, not specific to this slug. Frame as "When X, prefer Y because Z." If there is nothing transferable, write a single honest line saying so.</li></ul>
</section>

<section>
<h2>Residual risk</h2>
<p>Concrete remaining risks, or "None known". Be specific: "untested on empty input" beats "edge cases".</p>
</section>

<section>
<h2>Pointers</h2>
<ul>
<li>Spec: $SPEC</li>
<li>Track: $TRACK</li>
<li>Reviews: include the review files listed in the Inputs block above.</li>
</ul>
</section>
EOF
)
else
  REPORT_INSTRUCTIONS=$(cat <<EOF
Write the report to $REPORT in this markdown structure. Be concrete, no filler, no recap of what the reader can see in the diff:

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
EOF
)
fi

SYNTH_PROMPT=$(cat <<EOF
You are writing a learning-oriented post-mortem for a developer who just ran a Codex/Claude devloop.
This is NOT an audit log. It is a teaching artifact. The reader should come away understanding WHY
each decision was made and what to internalize for next time.

Inputs:
- spec: $SPEC
- track: $TRACK
Review files:
$PRIORS
- final status: $status
- passes used: $N / $MAX
- base: $BASE, branch: $BRANCH

Run: git diff --stat $BASE...HEAD   (for context only; do not paste the full diff)

$REPORT_INSTRUCTIONS

Style:
- Terse, dense, no hedging.
- No headers beyond the ones above.
- No emoji.
- Optimize for a developer who will read this once, six weeks from now, and needs to extract the lesson in 90 seconds.
EOF
)

printf '%s' "$SYNTH_PROMPT" | run_claude ".codex/logs/$SLUG-report.log" \
  || log "report synthesis failed; see .codex/logs/$SLUG-report.log"

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
