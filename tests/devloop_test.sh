#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEVLOOP="$ROOT/devloop.sh"
TMP_ROOT=${TMPDIR:-/tmp}
TEST_TMP=$(mktemp -d "$TMP_ROOT/devloop-test.XXXXXX")

total=0
passed=0

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_file_exists() {
  local path="$1"

  [[ -f "$path" ]] || fail "expected file to exist: $path"
}

assert_file_not_exists() {
  local path="$1"

  [[ ! -e "$path" ]] || fail "expected file not to exist: $path"
}

assert_contains() {
  local needle="$1"
  local path="$2"

  grep -Fq -- "$needle" "$path" || {
    printf '%s\n' "--- $path ---" >&2
    sed -n '1,220p' "$path" >&2 || true
    fail "expected '$path' to contain: $needle"
  }
}

assert_not_contains() {
  local needle="$1"
  local path="$2"

  ! grep -Fq -- "$needle" "$path" || fail "did not expect '$path' to contain: $needle"
}

make_repo() {
  local name="$1"
  local spec_name="${2:-change.md}"
  local repo="$TEST_TMP/$name/repo"

  mkdir -p "$repo/.specs"
  git init -q "$repo"
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  (
    cd "$repo"
    git config user.email "devloop-test@example.com"
    git config user.name "devloop test"
    printf '# Fixture\n' > README.md
    git add README.md
    git commit -q -m init
  )

  cat > "$repo/.specs/$spec_name" <<'EOF'
# Fixture spec

## Acceptance criteria
1. The loop runs deterministically under test.
EOF

  printf '%s\n' "$repo"
}

install_mocks() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"

  cat > "$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${DEVLOOP_TEST_STATE:?DEVLOOP_TEST_STATE is required}"
prompt=$(cat)
session_id="${DEVLOOP_TEST_CODEX_SESSION_ID:-00000000-0000-4000-8000-000000000001}"

mkdir -p "$DEVLOOP_TEST_STATE"
count_file="$DEVLOOP_TEST_STATE/codex-count"
count=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$count" > "$count_file"
printf '%s\n' "$*" >> "$DEVLOOP_TEST_STATE/codex-args.log"
printf '%s\n---\n' "$prompt" >> "$DEVLOOP_TEST_STATE/codex-prompts.log"

track=$(printf '%s\n' "$prompt" | awk -F': ' '/^Track: /{print $2; exit}')
if [[ -n "$track" ]]; then
  {
    printf '\n## Pass %s - mock codex\n' "$count"
    printf -- '- changed files: fixture\n'
    printf -- '- verification: fixture\n'
  } >> "$track"
fi

printf 'codex pass %s\n' "$count"
printf 'To continue this session, run codex exec resume %s\n' "$session_id"
EOF

  cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${DEVLOOP_TEST_STATE:?DEVLOOP_TEST_STATE is required}"
prompt=$(cat)

mkdir -p "$DEVLOOP_TEST_STATE"
total_file="$DEVLOOP_TEST_STATE/claude-total-count"
total=$(( $(cat "$total_file" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$total" > "$total_file"
printf '%s\n' "$*" >> "$DEVLOOP_TEST_STATE/claude-args.log"
printf '%s\n---\n' "$prompt" >> "$DEVLOOP_TEST_STATE/claude-prompts.log"

if [[ "$prompt" == *"Output path:"* ]]; then
  review_file=$(printf '%s\n' "$prompt" | awk -F': ' '/^Output path: /{print $2; exit}')
  review_count_file="$DEVLOOP_TEST_STATE/claude-review-count"
  review_count=$(( $(cat "$review_count_file" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$review_count" > "$review_count_file"

  IFS=',' read -r -a verdicts <<< "${DEVLOOP_TEST_VERDICTS:-ACCEPT}"
  if (( review_count <= ${#verdicts[@]} )); then
    verdict="${verdicts[$((review_count - 1))]}"
  else
    verdict="${verdicts[$((${#verdicts[@]} - 1))]}"
  fi

  mkdir -p "$(dirname "$review_file")"
  {
    printf '# Claude review %s\n\n' "$review_count"
    printf 'Verdict: %s\n\n' "$verdict"
    printf '## Findings\n\n'
    if [[ "$verdict" == "ACCEPT" ]]; then
      printf 'None\n\n'
    else
      printf '1. [should-fix] devloop.sh:10 - repeated fixture finding. Root cause: mock review. Principle: deterministic retry behavior.\n\n'
    fi
    printf '## Missing tests\n\n'
    printf -- '- None\n\n'
    printf '## Fix instructions\n\n'
    if [[ "$verdict" == "ACCEPT" ]]; then
      printf 'None\n\n'
    else
      printf '1. Fix the repeated fixture finding.\n\n'
    fi
    printf '## Notes\n\n'
    printf -- '- None\n'
  } > "$review_file"
else
  report_line=$(printf '%s\n' "$prompt" | awk '/^Write the report to /{print; exit}')
  report_file="${report_line#Write the report to }"
  report_file="${report_file%% in this structure.*}"
  report_file="${report_file%% in this markdown structure.*}"
  report_file="${report_file%% as valid standalone HTML.*}"
  [[ -n "$report_file" ]] || exit 0
  mkdir -p "$(dirname "$report_file")"
  {
    printf '# mock devloop report\n\n'
    printf 'Report synthesized by test double.\n'
  } > "$report_file"
fi
EOF

  chmod +x "$bin_dir/codex" "$bin_dir/claude"
}

run_devloop() {
  local cwd="$1"
  local stdout="$2"
  local stderr="$3"
  shift 3

  set +e
  (cd "$cwd" && "$BASH" "$DEVLOOP" "$@") >"$stdout" 2>"$stderr"
  local rc=$?
  set -e
  return "$rc"
}

test_usage_when_spec_missing() {
  local out="$TEST_TMP/usage.out"
  local err="$TEST_TMP/usage.err"

  set +e
  "$BASH" "$DEVLOOP" >"$out" 2>"$err"
  local rc=$?
  set -e

  assert_eq 2 "$rc" "missing spec exit code"
  assert_contains "usage: devloop.sh [--report-format html|markdown] <spec.md> [max=5]" "$err"
  assert_not_contains "claude not on PATH" "$err"
}

test_missing_claude_is_reported_before_git_setup() {
  local work="$TEST_TMP/missing-claude"
  local out="$work.out"
  local err="$work.err"
  local spec="$work/spec.md"

  mkdir -p "$work"
  printf '# Spec\n' > "$spec"

  set +e
  PATH="$work" "$BASH" "$DEVLOOP" "$spec" >"$out" 2>"$err"
  local rc=$?
  set -e

  assert_eq 2 "$rc" "missing claude exit code"
  assert_contains "claude not on PATH" "$err"
}

test_invalid_max_is_usage_error() {
  local work="$TEST_TMP/invalid-max"
  local out="$work.out"
  local err="$work.err"
  local spec="$work/spec.md"

  mkdir -p "$work"
  printf '# Spec\n' > "$spec"

  set +e
  "$BASH" "$DEVLOOP" "$spec" nope >"$out" 2>"$err"
  local rc=$?
  set -e

  assert_eq 2 "$rc" "invalid max exit code"
  assert_contains "max must be an integer between 1 and 10" "$err"
  assert_not_contains "unbound variable" "$err"
}

test_report_alias_is_not_accepted() {
  local work="$TEST_TMP/report-alias"
  local out="$work.out"
  local err="$work.err"
  local spec="$work/spec.md"

  mkdir -p "$work"
  printf '# Spec\n' > "$spec"

  set +e
  "$BASH" "$DEVLOOP" --report markdown "$spec" >"$out" 2>"$err"
  local rc=$?
  set -e

  assert_eq 2 "$rc" "report alias exit code"
  assert_contains "unknown option: --report" "$err"
}

test_accept_writes_core_artifacts() {
  local repo repo_real state bin out err rc
  repo=$(make_repo "accept")
  repo_real=$(cd "$repo" && pwd -P)
  state="$TEST_TMP/accept/state"
  bin="$TEST_TMP/accept/bin"
  out="$TEST_TMP/accept.out"
  err="$TEST_TMP/accept.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change.md" 5
  rc=$?
  set -e

  assert_eq 0 "$rc" "accepted loop exit code"
  assert_contains "result:  accepted" "$out"
  assert_contains "passes:  1 / 5" "$out"
  assert_file_exists "$repo/.codex/tracks/change.md"
  assert_file_exists "$repo/.codex/reviews/change-r1.md"
  assert_file_exists "$repo/.codex/reports/change.html"
  assert_file_exists "$repo/.codex/sessions/change-codex.id"
  assert_file_exists "$repo/.codex/sessions/change-claude.id"
  assert_contains "Verdict: ACCEPT" "$repo/.codex/reviews/change-r1.md"
  assert_contains "## Pass 1 - mock codex" "$repo/.codex/tracks/change.md"
  assert_contains "- report-format: html" "$repo/.codex/tracks/change.md"
  assert_contains "valid standalone HTML" "$state/claude-prompts.log"
  assert_contains "3-5 sharp, transferable lessons" "$state/claude-prompts.log"
  assert_contains "exec --dangerously-bypass-approvals-and-sandbox -C $repo_real -" "$state/codex-args.log"
  assert_eq "00000000-0000-4000-8000-000000000001" "$(cat "$repo/.codex/sessions/change-codex.id")" "codex session id"
  assert_eq 1 "$(grep -c -- '--session-id' "$state/claude-args.log")" "claude initial session count"
  assert_eq 1 "$(grep -c -- '--resume' "$state/claude-args.log")" "claude report resume count"
  assert_eq 1 "$(cat "$state/codex-count")" "codex call count"
  assert_eq 1 "$(cat "$state/claude-review-count")" "claude review count"
  assert_eq 2 "$(cat "$state/claude-total-count")" "claude total count including synthesis"
}

test_reject_then_accept_runs_fix_pass() {
  local repo state bin out err rc
  repo=$(make_repo "reject-accept")
  state="$TEST_TMP/reject-accept/state"
  bin="$TEST_TMP/reject-accept/bin"
  out="$TEST_TMP/reject-accept.out"
  err="$TEST_TMP/reject-accept.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="REJECT,ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change.md" 3
  rc=$?
  set -e

  assert_eq 0 "$rc" "reject then accept exit code"
  assert_contains "passes:  2 / 3" "$out"
  assert_contains "Verdict: REJECT" "$repo/.codex/reviews/change-r1.md"
  assert_contains "Verdict: ACCEPT" "$repo/.codex/reviews/change-r2.md"
  assert_contains "Fix only the findings in the review." "$state/codex-prompts.log"
  assert_contains "Review: .codex/reviews/change-r1.md" "$state/codex-prompts.log"
  assert_contains "exec resume --dangerously-bypass-approvals-and-sandbox 00000000-0000-4000-8000-000000000001 -" "$state/codex-args.log"
  assert_eq 1 "$(grep -c -- '--session-id' "$state/claude-args.log")" "claude initial session count"
  assert_eq 2 "$(grep -c -- '--resume' "$state/claude-args.log")" "claude resumed review and report count"
  assert_eq 2 "$(cat "$state/codex-count")" "codex call count"
  assert_eq 2 "$(cat "$state/claude-review-count")" "claude review count"
}

test_spec_slug_with_spaces_preserves_prior_reviews() {
  local repo state bin out err rc
  repo=$(make_repo "space-spec" "change with spaces.md")
  state="$TEST_TMP/space-spec/state"
  bin="$TEST_TMP/space-spec/bin"
  out="$TEST_TMP/space-spec.out"
  err="$TEST_TMP/space-spec.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="REJECT,ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change with spaces.md" 2
  rc=$?
  set -e

  assert_eq 0 "$rc" "space slug loop exit code"
  assert_file_exists "$repo/.codex/reviews/change with spaces-r1.md"
  assert_file_exists "$repo/.codex/reviews/change with spaces-r2.md"
  assert_contains "Prior reviews:" "$state/claude-prompts.log"
  assert_contains "- .codex/reviews/change with spaces-r1.md" "$state/claude-prompts.log"
  assert_contains "- .codex/reviews/change with spaces-r2.md" "$state/claude-prompts.log"
  assert_contains "Review files:" "$state/claude-prompts.log"
}

test_invocation_repo_controls_workdir_not_spec_location() {
  local repo repo_real spec_repo spec_path state bin out err rc
  repo=$(make_repo "invocation-repo")
  repo_real=$(cd "$repo" && pwd -P)
  spec_repo=$(make_repo "spec-repo")
  spec_path=$(cd "$spec_repo/.specs" && pwd)/change.md
  state="$TEST_TMP/invocation-repo/state"
  bin="$TEST_TMP/invocation-repo/bin"
  out="$TEST_TMP/invocation-repo.out"
  err="$TEST_TMP/invocation-repo.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$spec_repo/.specs/change.md" 1
  rc=$?
  set -e

  assert_eq 0 "$rc" "invocation repo exit code"
  assert_file_exists "$repo/.codex/tracks/change.md"
  assert_file_not_exists "$spec_repo/.codex"
  assert_contains "- spec: $spec_path" "$repo/.codex/tracks/change.md"
  assert_contains "- cwd: $repo_real" "$repo/.codex/tracks/change.md"
  assert_contains "exec --dangerously-bypass-approvals-and-sandbox -C $repo_real -" "$state/codex-args.log"
}

test_markdown_report_option() {
  local repo state bin out err rc
  repo=$(make_repo "markdown-report")
  state="$TEST_TMP/markdown-report/state"
  bin="$TEST_TMP/markdown-report/bin"
  out="$TEST_TMP/markdown-report.out"
  err="$TEST_TMP/markdown-report.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="ACCEPT" \
    run_devloop "$repo" "$out" "$err" --report-format markdown "$repo/.specs/change.md" 1
  rc=$?
  set -e

  assert_eq 0 "$rc" "markdown report exit code"
  assert_file_exists "$repo/.codex/reports/change.md"
  assert_file_not_exists "$repo/.codex/reports/change.html"
  assert_contains "report:  .codex/reports/change.md" "$out"
  assert_contains "- report-format: markdown" "$repo/.codex/tracks/change.md"
  assert_contains "in this markdown structure" "$state/claude-prompts.log"
}

test_repeated_reject_findings_stall_the_loop() {
  local repo state bin out err rc
  repo=$(make_repo "stall")
  state="$TEST_TMP/stall/state"
  bin="$TEST_TMP/stall/bin"
  out="$TEST_TMP/stall.out"
  err="$TEST_TMP/stall.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:/usr/bin:/bin" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="REJECT,REJECT,REJECT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change.md" 5
  rc=$?
  set -e

  assert_eq 1 "$rc" "stalled loop exit code"
  assert_contains "result:  stalled" "$out"
  assert_contains "passes:  2 / 5" "$out"
  assert_file_exists "$repo/.codex/reviews/change-r1.md"
  assert_file_exists "$repo/.codex/reviews/change-r2.md"
  assert_eq 2 "$(cat "$state/codex-count")" "codex call count before stall"
  assert_eq 2 "$(cat "$state/claude-review-count")" "claude review count before stall"
}

test_max_is_clamped_to_one() {
  local repo state bin out err rc
  repo=$(make_repo "max-clamp")
  state="$TEST_TMP/max-clamp/state"
  bin="$TEST_TMP/max-clamp/bin"
  out="$TEST_TMP/max-clamp.out"
  err="$TEST_TMP/max-clamp.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change.md" 0
  rc=$?
  set -e

  assert_eq 0 "$rc" "max clamp exit code"
  assert_contains "passes:  1 / 1" "$out"
  assert_contains "- max: 1" "$repo/.codex/tracks/change.md"
}

test_leading_zero_max_is_decimal() {
  local repo state bin out err rc
  repo=$(make_repo "leading-zero-max")
  state="$TEST_TMP/leading-zero-max/state"
  bin="$TEST_TMP/leading-zero-max/bin"
  out="$TEST_TMP/leading-zero-max.out"
  err="$TEST_TMP/leading-zero-max.err"
  install_mocks "$bin"

  set +e
  PATH="$bin:$PATH" DEVLOOP_TEST_STATE="$state" DEVLOOP_TEST_VERDICTS="ACCEPT" \
    run_devloop "$repo" "$out" "$err" "$repo/.specs/change.md" 08
  rc=$?
  set -e

  assert_eq 0 "$rc" "leading zero max exit code"
  assert_contains "passes:  1 / 8" "$out"
  assert_contains "- max: 8" "$repo/.codex/tracks/change.md"
}

run_test() {
  local name="$1"

  total=$((total + 1))
  printf 'test %s ... ' "$name"
  if ( "$name" ); then
    passed=$((passed + 1))
    printf 'ok\n'
  else
    printf 'not ok\n'
    return 1
  fi
}

run_test test_usage_when_spec_missing
run_test test_missing_claude_is_reported_before_git_setup
run_test test_invalid_max_is_usage_error
run_test test_report_alias_is_not_accepted
run_test test_accept_writes_core_artifacts
run_test test_reject_then_accept_runs_fix_pass
run_test test_spec_slug_with_spaces_preserves_prior_reviews
run_test test_invocation_repo_controls_workdir_not_spec_location
run_test test_markdown_report_option
run_test test_repeated_reject_findings_stall_the_loop
run_test test_max_is_clamped_to_one
run_test test_leading_zero_max_is_decimal

printf '\n%d/%d tests passed\n' "$passed" "$total"
