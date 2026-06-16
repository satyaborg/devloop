#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2034,SC2317,SC2329
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS_DIR="$REPO_ROOT/scripts"
REMOTE_INSTALLER="$SCRIPTS_DIR/install.remote.sh"

fail() {
  echo "not ok - $*" >&2
  exit 1
}

ok() {
  echo "ok - $*"
}

contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label missing: $needle"
}

not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$label should not contain: $needle"
}

equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label expected [$expected], got [$actual]"
}

bash -n "$REPO_ROOT/devloop" "$SCRIPTS_DIR/install.sh" "$SCRIPTS_DIR/uninstall.sh" "$SCRIPTS_DIR/skill_helpers.sh" "$SCRIPTS_DIR/release.sh" "$REMOTE_INSTALLER" "$REPO_ROOT/site/public/install"
ok "bash syntax"

DEVLOOP_LIB=1
source "$REPO_ROOT/devloop"
unset DEVLOOP_LIB
equals "${CODEX_MODEL_ARGS[*]}" "-m gpt-5.5" "codex model args"
equals "${CLAUDE_MODEL_ARGS[*]}" "--model claude-opus-4-8" "claude model args"

version="$(sed -n '1p' "$REPO_ROOT/VERSION")"
equals "$("$REPO_ROOT/devloop" --version)" "devloop $version" "version output"
equals "$("$REPO_ROOT/devloop" -V)" "devloop $version" "short version output"
equals "$("$REPO_ROOT/devloop" --plain --version)" "devloop $version" "version after global flag"

help="$("$REPO_ROOT/devloop" --help)"
contains "$help" "Common commands:" "help"
contains "$help" "devloop doctor" "help"
contains "$help" "devloop reports" "help"
contains "$help" "devloop status" "help"
contains "$help" "devloop clean" "help"
contains "$help" "--create-pr" "help"
contains "$help" "draft PR during the loop" "help"
contains "$help" "--no-shell" "help"
contains "$help" "--enter-worktree" "help"
contains "$help" "--version" "help"
contains "$help" "--timeout-minutes" "help"
ok "help output"

remote_help="$("$REMOTE_INSTALLER" --help)"
contains "$remote_help" "curl -fsSL https://devloop.sh/install | bash" "remote installer help"
contains "$remote_help" "--yes" "remote installer help"
contains "$remote_help" "--version <version>" "remote installer help"
contains "$remote_help" "--no-skills" "remote installer help"
contains "$remote_help" "--dry-run" "remote installer help"
contains "$remote_help" "--install-dir <dir>" "remote installer help"
contains "$remote_help" "--bin-dir <dir>" "remote installer help"
ok "remote installer help output"

readme_text="$(cat "$REPO_ROOT/README.md")"
contains "$readme_text" "curl -fsSL https://devloop.sh/install | bash" "README remote install"
contains "$readme_text" "git clone https://github.com/satyaborg/devloop.git" "README source install"
contains "$readme_text" "cd devloop" "README source install"
contains "$readme_text" "./scripts/install.sh" "README source install"
ok "README install docs"

skill_path="$("$REPO_ROOT/devloop" spec --skill-path)"
[[ "$skill_path" == "$REPO_ROOT/skills/devloop-spec/SKILL.md" ]] || fail "unexpected skill path: $skill_path"
contains "$("$REPO_ROOT/devloop" spec --print-skill)" "name: devloop-spec" "spec skill"
ok "spec skill path"

contains "$(cat "$REPO_ROOT/README.md")" "\`devloop --create-pr <spec.md>\`" "README PR mode"
contains "$(cat "$REPO_ROOT/README.md")" "maintain a draft PR (requires \`gh\`)" "README PR mode"
ok "README PR guidance"

for skill in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(sed -n 's/^name: *//p' "$skill" | head -n 1)"
  description="$(sed -n 's/^description: *//p' "$skill" | head -n 1)"
  dirname="$(basename "$(dirname "$skill")")"
  reference_nesting=""
  [[ "$name" == "$dirname" ]] || fail "skill name mismatch: $skill declares $name"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail "invalid skill name: $name"
  [[ -n "$description" ]] || fail "missing skill description: $skill"
  [[ "${#description}" -le 1024 ]] || fail "skill description too long: $skill"
  if [ -d "$(dirname "$skill")/references" ]; then
    reference_nesting="$(find "$(dirname "$skill")/references" -mindepth 2 -type f -print)"
    [[ -z "$reference_nesting" ]] || fail "nested skill references: $reference_nesting"
  fi
done
ok "skill metadata"

work=$(mktemp -d "${TMPDIR:-/tmp}/devloop-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

equals "$(sed -n '1p' "$REPO_ROOT/site/public/VERSION")" "$version" "site VERSION matches root VERSION"
ok "site version file"

bootstrap_bin="$work/install-bootstrap-bin"
bootstrap_log="$work/install-bootstrap.log"
mkdir -p "$bootstrap_bin"
cat > "$bootstrap_bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "-fsSL" ]; then
  printf 'unexpected curl args: %s\n' "$*" >&2
  exit 1
fi
url="${2:-}"
printf '%s\n' "$url" >> "$DEVLOOP_BOOTSTRAP_LOG"
case "$url" in
  https://version.example/devloop)
    printf '%s\n' '9.8.7'
    ;;
  https://raw.example/devloop/v*/scripts/install.remote.sh)
    cat <<'SCRIPT'
#!/usr/bin/env bash
printf 'installer args:'
for arg in "$@"; do printf ' <%s>' "$arg"; done
printf '\n'
SCRIPT
    ;;
  *)
    printf 'unexpected url: %s\n' "$url" >&2
    exit 1
    ;;
esac
CURL
chmod +x "$bootstrap_bin/curl"
bootstrap_output="$(
  DEVLOOP_BOOTSTRAP_LOG="$bootstrap_log" \
  DEVLOOP_VERSION_URL="https://version.example/devloop" \
  DEVLOOP_RAW_BASE_URL="https://raw.example/devloop" \
  PATH="$bootstrap_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$REPO_ROOT/site/public/install" --dry-run
)"
contains "$bootstrap_output" "installer args: <--version> <9.8.7> <--dry-run>" "site install bootstrap"
contains "$(cat "$bootstrap_log")" "https://version.example/devloop" "site install bootstrap version"
contains "$(cat "$bootstrap_log")" "https://raw.example/devloop/v9.8.7/scripts/install.remote.sh" "site install bootstrap installer"
: > "$bootstrap_log"
bootstrap_pinned_output="$(
  DEVLOOP_BOOTSTRAP_LOG="$bootstrap_log" \
  DEVLOOP_VERSION_URL="https://version.example/devloop" \
  DEVLOOP_RAW_BASE_URL="https://raw.example/devloop" \
  PATH="$bootstrap_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$REPO_ROOT/site/public/install" --version=1.2.3 --dry-run
)"
contains "$bootstrap_pinned_output" "installer args: <--version> <1.2.3> <--dry-run>" "site install bootstrap pinned"
not_contains "$(cat "$bootstrap_log")" "https://version.example/devloop" "site install bootstrap pinned"
contains "$(cat "$bootstrap_log")" "https://raw.example/devloop/v1.2.3/scripts/install.remote.sh" "site install bootstrap pinned"
: > "$bootstrap_log"
if bootstrap_bad_version_output="$(
  DEVLOOP_BOOTSTRAP_LOG="$bootstrap_log" \
  DEVLOOP_VERSION_URL="https://version.example/devloop" \
  DEVLOOP_RAW_BASE_URL="https://raw.example/devloop" \
  PATH="$bootstrap_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$REPO_ROOT/site/public/install" --version 2>&1
)"; then
  printf '%s\n' "$bootstrap_bad_version_output" >&2
  fail "site install bootstrap accepted bare --version"
fi
contains "$bootstrap_bad_version_output" "error: --version requires a value" "site install bootstrap bare version"
not_contains "$(cat "$bootstrap_log")" "https://version.example/devloop" "site install bootstrap bare version"
not_contains "$(cat "$bootstrap_log")" "scripts/install.remote.sh" "site install bootstrap bare version"
ok "site install bootstrap"

make_remote_release() {
  local version="$1"
  local releases="$2"
  local fixture="$work/remote-release-src-$version"
  local release_dir="$releases/v$version"
  local archive="$release_dir/devloop-$version.tar.gz"
  mkdir -p "$fixture/devloop-$version/scripts" "$release_dir"
  cp "$REPO_ROOT/devloop" "$fixture/devloop-$version/devloop"
  cp "$SCRIPTS_DIR/skill_helpers.sh" "$fixture/devloop-$version/scripts/skill_helpers.sh"
  cp -R "$REPO_ROOT/skills" "$fixture/devloop-$version/skills"
  printf '%s\n' "$version" > "$fixture/devloop-$version/VERSION"
  tar -C "$fixture" -czf "$archive" "devloop-$version"
  printf '%s  %s\n' "$(devloop_checksum_file "$archive")" "devloop-$version.tar.gz" > "$archive.sha256"
}

coverage_functions="$work/project-functions.txt"
coverage_hits="$work/project-function-hits.txt"
coverage_set=""
sed -nE 's/^([[:alpha:]_][[:alnum:]_]*)\(\)[[:space:]]*\{/\1/p' \
  "$REPO_ROOT/devloop" "$SCRIPTS_DIR/skill_helpers.sh" "$SCRIPTS_DIR/release.sh" |
  LC_ALL=C sort -u > "$coverage_functions"
while IFS= read -r fn; do
  coverage_set="${coverage_set}|${fn}|"
done < "$coverage_functions"

record_project_function_coverage() {
  local fn="${FUNCNAME[1]:-}"
  case "$coverage_set" in
    *"|$fn|"*) printf '%s\n' "$fn" >> "$coverage_hits" ;;
  esac
}

assert_project_function_coverage() {
  local covered missing fn
  covered="$work/project-function-covered.txt"
  missing="$work/project-function-missing.txt"
  LC_ALL=C sort -u "$coverage_hits" > "$covered"
  : > "$missing"
  while IFS= read -r fn; do
    grep -Fxq "$fn" "$covered" || printf '%s\n' "$fn" >> "$missing"
  done < "$coverage_functions"
  if [ -s "$missing" ]; then
    printf '%s\n' "missing project function coverage:" >&2
    cat "$missing" >&2
    fail "project function coverage is not 100%"
  fi
  ok "100% project function coverage"
}

set -T
trap record_project_function_coverage DEBUG

ui_has_gum() { return 1; }
ui_has_fzf() { return 1; }

contains "$(usage)" "usage: devloop" "usage"
contains "$(spec_usage)" "devloop spec" "spec usage"
old_use_tui="$USE_TUI"
USE_TUI=false
contains "$(welcome)" "Spec-driven code and review loop." "plain welcome"
USE_TUI="$old_use_tui"
gum() { return 0; }
old_use_tui="$USE_TUI"
USE_TUI=true
welcome_tui >/dev/null
USE_TUI="$old_use_tui"
unset -f gum

criteria_file="$work/criteria.md"
cat > "$criteria_file" <<'MARKDOWN'
# Spec

## Acceptance criteria
1. First thing
- Second thing

## Notes
Ignore me
MARKDOWN
equals "$(parse_criteria "$criteria_file")" $'First thing\nSecond thing' "parse_criteria"

review_file="$work/review.md"
cat > "$review_file" <<'MARKDOWN'
# Review

Verdict: ACCEPT

## Acceptance matrix

| Criterion | Status | Implementation evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | PASS | code path | test |
| AC2 | PASS | behavior | test |

## Engineering quality matrix

| Area | Status | Evidence |
| --- | --- | --- |
| Correctness | PASS | no logic regression |
| Test quality | PASS | targeted test |
| Maintainability | PASS | direct implementation |
| Architecture boundaries | PASS | existing layer |
| Simplicity | PASS | no extra abstraction |
| Security | N/A | no security boundary |
| Operational safety | PASS | no partial update |
MARKDOWN
equals "$(parse_verdict "$review_file")" "ACCEPT" "parse_verdict"
has_passing_matrix "$review_file" 2 || fail "has_passing_matrix rejected passing matrix"
has_passing_quality_matrix "$review_file" || fail "has_passing_quality_matrix rejected passing matrix"
sed 's/| AC2 | PASS |/| AC2 | FAIL |/' "$review_file" > "$work/review-fail.md"
if has_passing_matrix "$work/review-fail.md" 2; then fail "has_passing_matrix accepted failing matrix"; fi
sed 's/| Maintainability | PASS |/| Maintainability | FAIL |/' "$review_file" > "$work/review-quality-fail.md"
if has_passing_quality_matrix "$work/review-quality-fail.md"; then fail "has_passing_quality_matrix accepted failing matrix"; fi

review_prompt_text="$(review_prompt codex "$criteria_file" ".devloop/tracks/test.md" main 1 ".devloop/reviews/test-r1.md" test 5 "$criteria_file" true)"
contains "$review_prompt_text" "Skill: use the installed devloop-review skill." "review prompt"
contains "$review_prompt_text" "Bundled skill path, for fallback only: $REPO_ROOT/skills/devloop-review/SKILL.md" "review prompt"
contains "$review_prompt_text" "Engineering quality matrix" "review prompt"

findings_a="$work/findings-a.md"
findings_b="$work/findings-b.md"
cat > "$findings_a" <<'MARKDOWN'
## Findings

1. Fix item 123.
2. Another item 456.

## Notes
none
MARKDOWN
cat > "$findings_b" <<'MARKDOWN'
## Findings

2. Another item 999.
1. Fix item 000.

## Notes
none
MARKDOWN
equals "$(findings_hash "$findings_a")" "$(findings_hash "$findings_b")" "findings_hash normalizes order and numbers"

equals "$(slugify "Feat: Chat Retry's")" "feat-chat-retrys" "slugify"
equals "$(normalize_agent "Codex")" "codex" "normalize_agent Codex label"
equals "$(normalize_agent "Claude Code")" "claude" "normalize_agent Claude Code label"
equals "$(agent_label claude)" "Claude Code" "agent_label Claude"
equals "$(agent_choice_value "Claude Code")" "claude" "agent_choice_value"
equals "$(parse_bool yes)" "true" "parse_bool true"
equals "$(parse_bool 0)" "false" "parse_bool false"
if parse_bool maybe >/dev/null 2>&1; then fail "parse_bool accepted invalid value"; fi

frontmatter_text=$'---\ntype: fix!\nslug: "Chat Retry"\nbreaking: true\nempty: null\n---\n# Title'
equals "$(frontmatter_value type "$frontmatter_text")" "fix!" "frontmatter type"
equals "$(frontmatter_value slug "$frontmatter_text")" "Chat Retry" "frontmatter slug"
equals "$(frontmatter_value empty "$frontmatter_text")" "" "frontmatter ignores null"

parse_work_item 'noise {"type":"feat","slug":"chat-retry","breaking":false}' || fail "parse_work_item failed"
equals "$WORK_TYPE" "feat" "work item type"
equals "$WORK_SLUG" "chat-retry" "work item slug"
equals "$WORK_BREAKING" "false" "work item breaking"
if parse_work_item '{"type":"feat","slug":"feat-chat-retry","breaking":false}' >/dev/null 2>&1; then fail "parse_work_item accepted type-prefixed slug"; fi

equals "$(branch_base fix true null-check)" "fix!/null-check" "branch_base breaking"
equals "$(pass_commit_message feat false chat-retry 1)" "feat: chat-retry" "first pass commit"
equals "$(pass_commit_message feat false chat-retry 2)" "fix: chat-retry" "later pass commit"
equals "$(pass_commit_message chore false docs 2)" "chore: docs" "later chore commit"

branch_repo="$work/branch-repo"
git init -q "$branch_repo"
git -C "$branch_repo" config user.email devloop-test@example.com
git -C "$branch_repo" config user.name "devloop test"
printf x > "$branch_repo/file.txt"
git -C "$branch_repo" add file.txt
git -C "$branch_repo" commit -q -m init
git -C "$branch_repo" branch feat/chat-retry
equals "$(next_branch "$branch_repo" feat false chat-retry "")" "feat/chat-retry-2" "next_branch suffix"
PULL_REQUEST_ERROR=""
if create_pull_request "$branch_repo" "feat/chat-retry" "main" >/dev/null 2>&1; then fail "pull request creation unexpectedly passed without remote"; fi
contains "$PULL_REQUEST_ERROR" "branch push failed" "pull request push failure"
contains "$PULL_REQUEST_ERROR" "repository exists" "pull request push failure"
mkdir -p "$branch_repo/.devloop/reports" "$branch_repo/.devloop/tracks" "$branch_repo/.devloop/reviews"
printf '%s\n' "# Report" > "$branch_repo/.devloop/reports/chat-retry.md"
branch_repo_real="$(cd "$branch_repo" && pwd -P)"
cat > "$branch_repo/.devloop/tracks/chat-retry.md" <<MARKDOWN
# Track

- spec: $branch_repo_real/.specs/chat-retry.md
- worktree: $branch_repo_real
- max: 3
MARKDOWN
equals "$(cd "$branch_repo" && list_artifact_files ".devloop/reports")" "$branch_repo_real/.devloop/reports/chat-retry.md" "artifact listing"
equals "$(track_value max "$branch_repo/.devloop/tracks/chat-retry.md")" "3" "track value"
touch "$branch_repo/.devloop/reviews/chat-retry-r1.md" "$branch_repo/.devloop/reviews/chat-retry-r3.md"
equals "$(next_pass_from_track "$branch_repo/.devloop/tracks/chat-retry.md")" "4" "track next pass"

clean_status_repo="$work/clean-status-repo"
git init -q "$clean_status_repo"
git -C "$clean_status_repo" config user.email devloop-test@example.com
git -C "$clean_status_repo" config user.name "devloop test"
printf '%s\n' "# Clean status" > "$clean_status_repo/README.md"
git -C "$clean_status_repo" add README.md
git -C "$clean_status_repo" commit -q -m init
mkdir -p "$clean_status_repo/.devloop/tracks"
clean_status_track="$clean_status_repo/.devloop/tracks/clean-status.md"
printf '%s\n' "# Track" > "$clean_status_track"
if has_user_dirty_paths "$clean_status_repo"; then fail "clean worktree reported dirty"; fi
equals "$(clean_candidate_status "$clean_status_track" "$clean_status_repo" "$work/source-repo")" "ready" "clean candidate ready"
printf '%s\n' "spec_dir=.specs" > "$clean_status_repo/.devloop/config"
if ! has_user_dirty_paths "$clean_status_repo"; then fail "devloop config was not treated as user dirt"; fi
equals "$(clean_candidate_status "$clean_status_track" "$clean_status_repo" "$work/source-repo")" "dirty" "clean candidate sees config dirt"

config_repo="$work/config-repo"
config_home="$work/config-home"
git init -q "$config_repo"
config_repo_real="$(cd "$config_repo" && pwd -P)"
config_default_specs="$config_repo_real/.devloop/specs"
mkdir -p "$config_repo/.devloop/specs" "$config_home"
equals "$(HOME="$config_home" devloop_config_file)" "$config_home/.devloop/config" "default config file"
printf '%s\n' "# Devloop" > "$config_repo/.devloop/specs/devloop.md"
config_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
[[ -f "$config_home/.devloop/config" ]] || fail "global config was not created"
if grep -q "spec_dir=" "$config_home/.devloop/config"; then fail "global config seeded a default spec dir"; fi
contains "$(cat "$config_home/.devloop/config")" "timeout_minutes=30" "global config default timeout"
contains "$config_specs" "$config_default_specs/devloop.md" "default spec search uses repo .devloop/specs"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "$config_default_specs" "default spec dir is repo .devloop/specs"
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" "$config_default_specs" "spec search label is single default dir"
if (cd "$config_repo" && HOME="$config_home" configured_spec_dir) >/dev/null 2>&1; then fail "default spec dir reported as custom"; fi
equals "$(cd "$config_repo" && HOME="$config_home" write_config_spec_dir local "custom-specs")" "custom-specs" "write local config spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "custom-specs" "configured spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir)" "custom-specs" "custom spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir_scope)" "local" "custom spec dir scope"
[[ -d "$config_repo/custom-specs" ]] || fail "configured spec dir was not created"
printf '%s\n' "# Custom" > "$config_repo/custom-specs/custom.md"
configured_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$configured_specs" "custom-specs/custom.md" "configured spec search includes custom dir"
contains "$configured_specs" "$config_default_specs/devloop.md" "configured spec search still includes default"
if (cd "$config_repo" && HOME="$config_home" write_config_spec_dir "../bad") >/dev/null 2>&1; then fail "write_config_spec_dir accepted path traversal"; fi

absolute_specs="$work/shared-specs"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_spec_dir local "$absolute_specs")" "$absolute_specs" "write absolute config spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "$absolute_specs" "absolute configured spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir)" "$absolute_specs" "absolute custom spec dir"
[[ -d "$absolute_specs" ]] || fail "absolute configured spec dir was not created"
printf '%s\n' "# Shared" > "$absolute_specs/shared.md"
absolute_configured_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$absolute_configured_specs" "$absolute_specs/shared.md" "configured spec search includes absolute dir"
contains "$absolute_configured_specs" "$config_default_specs/devloop.md" "absolute spec search still includes default"
equals "$(spec_dir_status "$absolute_specs")" "exists" "spec dir status exists"
equals "$(spec_dir_status "$work/missing-specs")" "missing" "spec dir status missing"
(cd "$config_repo" && HOME="$config_home" remove_config_spec_dir local)
if (cd "$config_repo" && HOME="$config_home" configured_spec_dir) >/dev/null 2>&1; then fail "custom spec dir was not removed"; fi
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "$config_default_specs" "removed custom spec dir falls back"
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" "$config_default_specs" "removed custom spec search label"

global_repo="$work/global-repo"
global_home="$work/global-home"
global_specs="$work/global-specs"
mkdir -p "$global_repo" "$global_home"
equals "$(cd "$global_repo" && HOME="$global_home" write_config_spec_dir global "$global_specs")" "$global_specs" "write global config spec dir"
equals "$(cat "$global_home/.devloop/config")" "spec_dir=$global_specs" "global config path"
equals "$(cd "$global_repo" && HOME="$global_home" devloop_spec_dir)" "$global_specs" "global configured spec dir"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir)" "$global_specs" "global custom spec dir"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir_scope)" "global" "global custom spec dir scope"
printf '%s\n' "coder=codex" >> "$global_home/.devloop/config"
mkdir -p "$global_repo/.devloop"
printf '%s\n' "spec_dir=local-specs" > "$global_repo/.devloop/config"
equals "$(cd "$global_repo" && HOME="$global_home" devloop_spec_dir)" "local-specs" "local config overrides global spec dir"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir)" "local-specs" "local custom spec dir"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir_scope)" "local" "local custom spec dir scope"
equals "$(cd "$global_repo" && HOME="$global_home" devloop_config_value coder)" "codex" "global config fills missing local key"
printf '%s\n' "spec_dir=.specs" > "$global_repo/.devloop/config"
equals "$(cd "$global_repo" && HOME="$global_home" devloop_spec_dir)" ".specs" "repo .specs overrides global spec dir"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir)" ".specs" "repo .specs reported as override"
equals "$(cd "$global_repo" && HOME="$global_home" configured_spec_dir_scope)" "local" "repo .specs override scope"

default_scope_repo="$work/default-scope-repo"
default_scope_home="$work/default-scope-home"
default_scope_specs="$work/default-scope-specs"
mkdir -p "$default_scope_repo" "$default_scope_home"
equals "$(cd "$default_scope_repo" && HOME="$default_scope_home" write_config_spec_dir "$default_scope_specs")" "$default_scope_specs" "default write config spec dir is global"
equals "$(cat "$default_scope_home/.devloop/config")" "spec_dir=$default_scope_specs" "default write config path"
equals "$(cd "$default_scope_repo" && HOME="$default_scope_home" configured_spec_dir_scope)" "global" "default write config scope"

tilde_repo="$work/tilde-repo"
tilde_home="$work/home"
tilde_input="~"/shared-specs
mkdir -p "$tilde_repo" "$tilde_home"
equals "$(cd "$tilde_repo" && HOME="$tilde_home" write_config_spec_dir "$tilde_input")" "$tilde_home/shared-specs" "tilde input expands when saved"
equals "$(cat "$tilde_home/.devloop/config")" "spec_dir=$tilde_home/shared-specs" "tilde input saved as absolute path"

raw_tilde_repo="$work/raw-tilde-repo"
raw_tilde_home="$work/raw-tilde-home"
mkdir -p "$raw_tilde_repo/.devloop" "$raw_tilde_home"
printf '%s\n' "spec_dir=~/raw-specs" > "$raw_tilde_repo/.devloop/config"
equals "$(cd "$raw_tilde_repo" && HOME="$raw_tilde_home" devloop_spec_dir)" ".devloop/specs" "raw tilde config falls back to default"

equals "$(normalize_timeout_minutes 1)" "1" "timeout lower bound"
equals "$(normalize_timeout_minutes 30)" "30" "timeout normalize"
equals "$(normalize_timeout_minutes 1440)" "1440" "timeout upper bound"
if normalize_timeout_minutes 0 >/dev/null 2>&1; then fail "timeout accepted zero"; fi
if normalize_timeout_minutes 1441 >/dev/null 2>&1; then fail "timeout accepted above upper bound"; fi
if normalize_timeout_minutes nope >/dev/null 2>&1; then fail "timeout accepted non-numeric"; fi
equals "$(cd "$config_repo" && HOME="$config_home" devloop_timeout_minutes)" "30" "default timeout"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_timeout_minutes 45)" "45" "write timeout"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_timeout_minutes)" "45" "configured timeout"
equals "$(cd "$config_repo" && HOME="$config_home" configured_timeout_minutes_scope)" "global" "configured timeout scope"
(cd "$config_repo" && HOME="$config_home" remove_config_timeout_minutes)
equals "$(cd "$config_repo" && HOME="$config_home" devloop_timeout_minutes)" "30" "removed timeout falls back"

lint_spec_text=$'---\ntype: feat\n---\n# Title\n\n## Acceptance criteria\n1. Thing'
lint_spec_file "$criteria_file" "$lint_spec_text" 1 true || fail "lint_spec_file rejected valid spec"
bad_lint_spec=$'---\ntype: invalid\n---\n# Title\n\n## Acceptance criteria\n1. Thing'
if lint_spec_file "$criteria_file" "$bad_lint_spec" 1 true >/dev/null 2>&1; then fail "lint_spec_file accepted invalid type"; fi
if lint_spec_file "$criteria_file" "# Title" 0 true >/dev/null 2>&1; then fail "lint_spec_file accepted missing strict criteria"; fi
if lint_spec_file "$criteria_file" "## Missing H1" 0 false >/dev/null 2>&1; then fail "lint_spec_file accepted missing H1"; fi

STATUS="accepted"
equals "$(final_exit_code 0)" "0" "final exit accepted"
STATUS="timeout"
equals "$(final_exit_code 0)" "1" "final exit timeout"
STATUS="stalled"
equals "$(final_exit_code 0)" "1" "final exit stalled"
STATUS="preflight-error"
equals "$(final_exit_code 2)" "2" "final exit preserves early error"
STATUS=""
equals "$(final_exit_code 2)" "2" "final exit blank preserves fallback"

session_output=$'unrelated 11111111-1111-4111-8111-111111111111\nTo continue this session, run codex exec resume 22222222-2222-4222-8222-222222222222'
equals "$(extract_session_id "$session_output")" "22222222-2222-4222-8222-222222222222" "extract_session_id uses session marker"

contains "$(devloop_logo)" "░█▀▄░█▀▀" "devloop logo"
if [[ "$(devloop_logo)" == *"v$version"* ]]; then fail "devloop logo included version"; fi
ui_logo stdout >/dev/null
equals "$(ui_color_code accent)" "38;5;141" "accent color"
equals "$(ui_color_code rec)" "38;5;135" "run color"
equals "$(ui_color_code ok)" "38;5;141" "ok color"
equals "$(ui_color_code dim)" "38;5;244" "dim color"
old_use_tui="$USE_TUI"
USE_TUI=false
equals "$(ui_input "Prompt" "fallback")" "fallback" "ui input fallback"
if ui_confirm "Confirm?"; then fail "ui_confirm accepted non-tui input"; fi
USE_TUI="$old_use_tui"
if ! ( ui_choose() { printf '%s\n' "Back"; }; UI_BACK=false; interactive_create_spec >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "create spec back navigation"; fi
if ! menu_default_output="$(
  ui_header() { :; }
  ui_choose() { shift; printf '%s\n' "$1"; }
  interactive_create_spec() { printf '%s\n' "create"; }
  interactive_run_spec() { printf '%s\n' "run"; }
  UI_BACK=false
  interactive_menu
)"; then fail "menu default choice failed"; fi
equals "$menu_default_output" "create" "menu starts with create spec"
if ! create_spec_output="$(
  ui_choose() { printf '%s\n' "Codex"; }
  ui_input() { printf '%s\n' "unexpected input"; return 1; }
  spec_command() { printf '%s\n' "$*"; }
  UI_BACK=false
  interactive_create_spec
)"; then fail "create spec launch failed"; fi
equals "$create_spec_output" "--agent codex" "create spec launches immediately"
if ! ( ui_choose() { printf '%s\n' "Back"; }; UI_BACK=false; interactive_settings >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "settings back navigation"; fi
if ! run_setup_output="$(
  HOME="$config_home"
  USE_TUI=false
  UI_BACK=false
  interactive_create_pr_choice() { printf '%s\n' "false"; }
  run_header() { :; }
  run_devloop() { printf '%s\n' "$*"; return 0; }
  maybe_enter_worktree() { :; }
  interactive_run_setup "spec.md"
)"; then fail "run setup defaults failed"; fi
equals "$run_setup_output" "spec.md 5 html true true codex claude false 30" "run setup launches with defaults"
if ! ( ui_choose() { return 130; }; UI_BACK=false; interactive_create_spec >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "create spec escape navigation"; fi
if ! ( interactive_create_pr_choice() { return 130; }; UI_BACK=false; interactive_run_setup "spec.md" >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "run setup PR prompt navigation"; fi
if ! ( ui_choose() { printf '%s\n' "Quit"; }; UI_BACK=false; interactive_menu >/dev/null 2>&1 ); then fail "menu quit failed"; fi
empty_spec_repo="$work/empty-spec-repo"
mkdir -p "$empty_spec_repo"
old_use_tui="$USE_TUI"
USE_TUI=false
if ( cd "$empty_spec_repo" && interactive_run_spec >/dev/null 2>&1 ); then fail "interactive_run_spec accepted missing specs"; fi
USE_TUI=true
if ! ( cd "$empty_spec_repo" && ui_confirm() { return 1; }; UI_BACK=false; interactive_run_spec >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "interactive_run_spec missing specs did not go back"; fi
if ! ( cd "$empty_spec_repo" && UI_BACK=false; interactive_continue_run >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "interactive_continue_run missing tracks did not go back"; fi
if ! ( cd "$empty_spec_repo" && UI_BACK=false; interactive_open_report >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "interactive_open_report missing reports did not go back"; fi
USE_TUI="$old_use_tui"

cancel_spec_repo="$work/cancel-spec-repo"
mkdir -p "$cancel_spec_repo/.devloop/specs"
printf '%s\n' "# Cancel" > "$cancel_spec_repo/.devloop/specs/cancel.md"
if ! ( cd "$cancel_spec_repo" && ui_pick_from_file() { return 130; }; UI_BACK=false; interactive_run_spec >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "interactive_run_spec escape navigation"; fi

picker_file="$work/picker.txt"
printf '%s\n' "alpha" "beta" > "$picker_file"
old_use_tui="$USE_TUI"
USE_TUI=false
equals "$(ui_pick_from_file "$picker_file" "Pick")" "alpha" "non-tui picker fallback"
equals "$(USE_TUI=true; ui_numbered_pick "$picker_file" "Pick" 2>/dev/null <<<"2")" "beta" "numbered picker"
view_file "$picker_file" >/dev/null
USE_TUI="$old_use_tui"
equals "$(title_from_slug "chat-retry")" "Chat Retry" "title from slug"
RUN_TIMEOUT_MINUTES=7
contains "$(timeout_message)" "7 minutes" "timeout message"
terminate_pid_tree 999999

old_path="$PATH"
no_uuid_path="$work/no-uuid"
mkdir -p "$no_uuid_path"
PATH="$no_uuid_path"
uuid_one="$(new_uuid)"
uuid_two="$(new_uuid)"
PATH="$old_path"
[[ "$uuid_one" != "$uuid_two" ]] || fail "new_uuid fallback returned duplicate values"
contains "$uuid_one" "00000000-0000-4000-8000-" "new_uuid fallback format"
ok "pure helpers"

(
  DEVLOOP_RELEASE_LIB=1
  export DEVLOOP_RELEASE_LIB
  # shellcheck disable=SC1091
  source "$SCRIPTS_DIR/release.sh"
  contains "$(release_usage)" "usage: ./scripts/release.sh" "release usage"
  release_version_valid "0.1.0" || fail "release version rejected valid patch"
  release_version_valid "1.2.3-alpha.1+build.7" || fail "release version rejected valid prerelease"
  if release_version_valid "01.2.3"; then fail "release version accepted leading zero"; fi
  if release_version_valid "1.2"; then fail "release version accepted missing patch"; fi
  if release_version_valid "1.2.3-alpha.01"; then fail "release version accepted leading zero prerelease"; fi
  equals "$(release_tag_for_version "1.2.3")" "v1.2.3" "release tag"
  release_artifact_dir="$work/release-artifacts"
  release_create_artifacts "$version" "$release_artifact_dir"
  [[ -f "$RELEASE_ARCHIVE" ]] || fail "release archive was not created"
  [[ -f "$RELEASE_CHECKSUM" ]] || fail "release checksum was not created"
  contains "$(tar -tzf "$RELEASE_ARCHIVE")" "devloop-$version/devloop" "release archive"
  contains "$(tar -tzf "$RELEASE_ARCHIVE")" "devloop-$version/scripts/devloop_test.sh" "release archive"
  contains "$(tar -tzf "$RELEASE_ARCHIVE")" "devloop-$version/scripts/install.remote.sh" "release archive"
  equals "$(awk '{print $1; exit}' "$RELEASE_CHECKSUM")" "$(release_checksum_file "$RELEASE_ARCHIVE")" "release checksum"
  equals "$(release_next_version patch "0.1.0")" "0.1.1" "patch bump"
  equals "$(release_next_version minor "0.1.0")" "0.2.0" "minor bump"
  equals "$(release_next_version major "0.1.0")" "1.0.0" "major bump"
  if release_next_version patch "0.1.0-alpha.1" >/dev/null 2>&1; then fail "release bump accepted prerelease"; fi
  # shellcheck disable=SC2329
  release_require_command() {
    if [ "$1" = "git-cliff" ]; then return 1; fi
    return 0
  }
  ROOT="$work/release-root"
  mkdir -p "$ROOT/site/public"
  git init -q "$ROOT"
  release_write_version_files "9.9.8"
  equals "$(sed -n '1p' "$ROOT/VERSION")" "9.9.8" "release writes root version"
  equals "$(sed -n '1p' "$ROOT/site/public/VERSION")" "9.9.8" "release writes site version"
  printf '%s\n' "9.9.9" > "$ROOT/VERSION"
  printf '%s\n' "9.9.9" > "$ROOT/site/public/VERSION"
  dry_run_output="$(release_main "patch" --dry-run)" || fail "release dry-run required git-cliff"
  contains "$dry_run_output" "next: 9.9.10 (v9.9.10)" "release dry-run"
  contains "$dry_run_output" "would skip local tests (use --run-tests to run bash scripts/devloop_test.sh)" "release dry-run"
  contains "$dry_run_output" "would tag: v9.9.10" "release dry-run"
  test_dry_run_output="$(release_main "patch" --run-tests --dry-run)" || fail "release test dry-run required git-cliff"
  contains "$test_dry_run_output" "would run bash scripts/devloop_test.sh" "release test dry-run"
  publish_dry_run_output="$(release_main "patch" --publish --dry-run)" || fail "release publish dry-run required git-cliff"
  contains "$publish_dry_run_output" "would verify local HEAD matches upstream, then skip local tests" "release publish dry-run"
  contains "$publish_dry_run_output" "would push branch and tag" "release publish dry-run"
  contains "$publish_dry_run_output" "would build release assets: devloop-9.9.10.tar.gz and devloop-9.9.10.tar.gz.sha256" "release publish dry-run"
  contains "$publish_dry_run_output" "would create GitHub release: gh release create v9.9.10 --verify-tag --generate-notes" "release publish dry-run"
  git -C "$ROOT" config user.email devloop-test@example.com
  git -C "$ROOT" config user.name "devloop test"
  git -C "$ROOT" add VERSION site/public/VERSION
  git -C "$ROOT" commit -q -m init
  release_assert_clean_tree || fail "release clean tree rejected"
  printf '%s\n' "dirty" > "$ROOT/dirty"
  if release_assert_clean_tree >/dev/null 2>&1; then fail "release clean tree accepted dirty repo"; fi
  rm "$ROOT/dirty"
  if release_assert_head_matches_upstream >/dev/null 2>&1; then fail "release upstream accepted missing upstream"; fi
  git -C "$ROOT" branch verified-main
  git -C "$ROOT" branch --set-upstream-to=verified-main >/dev/null
  release_assert_head_matches_upstream || fail "release upstream rejected matching HEAD"
  git -C "$ROOT" commit --allow-empty -q -m local-ahead
  if release_assert_head_matches_upstream >/dev/null 2>&1; then fail "release upstream accepted local ahead HEAD"; fi
  [ -n "$(release_current_branch)" ] || fail "release current branch missing"
  DEVLOOP_RELEASE_ALLOW_BRANCH=1 release_assert_push_branch || fail "release push branch rejected"
)
ok "release helpers"

remote_version="9.8.7"
remote_releases="$work/remote-releases"
make_remote_release "$remote_version" "$remote_releases"
remote_release_base="file://$remote_releases"
remote_no_tools="$work/remote-no-tools"
mkdir -p "$remote_no_tools"
remote_no_tools_path="$remote_no_tools:/usr/bin:/bin:/usr/sbin:/sbin"

remote_custom_root="$work/remote-custom-root"
remote_custom_bin="$work/remote-custom-bin"
remote_dry_output="$(
  HOME="$work/remote-dry-home" PATH="$remote_no_tools_path" bash "$REMOTE_INSTALLER" \
    --dry-run \
    --version "$remote_version" \
    --install-dir "$remote_custom_root" \
    --bin-dir "$remote_custom_bin" \
    --release-base-url "$remote_release_base" \
    2>&1
)"
contains "$remote_dry_output" "dry run: no files will be changed" "remote dry run"
contains "$remote_dry_output" "version: $remote_version" "remote dry run version"
contains "$remote_dry_output" "download: $remote_release_base/v$remote_version/devloop-$remote_version.tar.gz" "remote dry run download"
contains "$remote_dry_output" "verify: $remote_release_base/v$remote_version/devloop-$remote_version.tar.gz.sha256" "remote dry run checksum"
contains "$remote_dry_output" "install: $remote_custom_root/$remote_version" "remote dry run install dir"
contains "$remote_dry_output" "link: $remote_custom_bin/devloop -> $remote_custom_root/$remote_version/devloop" "remote dry run bin dir"
contains "$remote_dry_output" "skills: $work/remote-dry-home/.agents/skills, $work/remote-dry-home/.claude/skills" "remote dry run skills"
contains "$remote_dry_output" "missing UI tools: gum fzf" "remote missing UI guidance"
contains "$remote_dry_output" "install with: brew install gum fzf" "remote missing UI guidance"
contains "$remote_dry_output" "missing agent CLIs: codex claude" "remote missing agent guidance"
contains "$remote_dry_output" "Devloop does not install codex or claude automatically." "remote missing agent guidance"
[[ ! -e "$remote_custom_root" ]] || fail "remote dry run created install root"
[[ ! -e "$remote_custom_bin" ]] || fail "remote dry run created bin dir"
ok "remote installer dry run"

latest_api_file="$work/latest-release.json"
latest_tool_path="$work/latest-tool-path"
test_bash="$(command -v bash)"
mkdir -p "$latest_tool_path"
for tool in grep sed head; do
  ln -s "$(command -v "$tool")" "$latest_tool_path/$tool"
done
printf '{"tag_name":"v%s"}\n' "$remote_version" > "$latest_api_file"
if ! remote_latest_output="$(
  HOME="$work/remote-latest-home" PATH="$latest_tool_path" DEVLOOP_GITHUB_API_URL="file://$latest_api_file" "$test_bash" "$REMOTE_INSTALLER" \
    --dry-run \
    --release-base-url "$remote_release_base" \
    2>&1
)"; then
  printf '%s\n' "$remote_latest_output" >&2
  fail "remote latest version dry run failed"
fi
contains "$remote_latest_output" "version: $remote_version" "remote latest version"
contains "$remote_latest_output" "download: $remote_release_base/v$remote_version/devloop-$remote_version.tar.gz" "remote latest version"
ok "remote installer latest version resolution"

tampered_version="9.8.8"
tampered_releases="$work/tampered-releases"
make_remote_release "$tampered_version" "$tampered_releases"
tampered_archive="$tampered_releases/v$tampered_version/devloop-$tampered_version.tar.gz"
printf '%064d  %s\n' 0 "devloop-$tampered_version.tar.gz" > "$tampered_archive.sha256"
tampered_home="$work/tampered-home"
if tampered_output="$(
  HOME="$tampered_home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$REMOTE_INSTALLER" \
    --yes \
    --version "$tampered_version" \
    --release-base-url "file://$tampered_releases" \
    2>&1
)"; then
  printf '%s\n' "$tampered_output" >&2
  fail "remote installer accepted checksum mismatch"
fi
contains "$tampered_output" "checksum mismatch" "remote checksum mismatch"
[[ ! -e "$tampered_home/.local/share/devloop/$tampered_version" ]] || fail "checksum mismatch created install dir"
[[ ! -e "$tampered_home/.local/bin/devloop" ]] || fail "checksum mismatch created devloop symlink"
ok "remote installer rejects checksum mismatch"

remote_tool_bin="$work/remote-tool-bin"
mkdir -p "$remote_tool_bin"
for tool in gum fzf codex claude; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$remote_tool_bin/$tool"
  chmod +x "$remote_tool_bin/$tool"
done
remote_path="$remote_tool_bin:/usr/bin:/bin:/usr/sbin:/sbin"
remote_home="$work/remote-home"
remote_install_output="$(
  HOME="$remote_home" PATH="$remote_path" bash "$REMOTE_INSTALLER" \
    --yes \
    --version "$remote_version" \
    --release-base-url "$remote_release_base" \
    2>&1
)"
remote_default_root="$remote_home/.local/share/devloop"
remote_default_bin="$remote_home/.local/bin"
[[ -d "$remote_default_root/$remote_version" ]] || fail "remote installer did not create versioned install dir"
[[ -L "$remote_default_bin/devloop" ]] || fail "remote installer did not create devloop symlink"
equals "$(readlink "$remote_default_bin/devloop")" "$remote_default_root/$remote_version/devloop" "remote installer symlink target"
equals "$("$remote_default_bin/devloop" --version)" "devloop $remote_version" "remote installed version"
contains "$remote_install_output" "verified checksum" "remote install checksum"
contains "$remote_install_output" "$remote_default_bin is not on PATH" "remote install PATH guidance"
contains "$remote_install_output" "export PATH=\"$remote_default_bin:\$PATH\"" "remote install PATH guidance"
contains "$remote_install_output" "[ok] gum:" "remote install UI check"
contains "$remote_install_output" "[ok] codex:" "remote install agent check"
contains "$remote_install_output" "devloop $remote_version installed" "remote install banner version"
contains "$remote_install_output" "try: devloop" "remote install banner try line"
[[ -f "$remote_home/.agents/skills/devloop-spec/SKILL.md" ]] || fail "remote installer did not install Codex spec skill"
[[ -f "$remote_home/.agents/skills/devloop-review/.devloop-checksum" ]] || fail "remote installer did not write Codex skill checksum"
[[ -f "$remote_home/.claude/skills/devloop-spec/SKILL.md" ]] || fail "remote installer did not install Claude spec skill"
[[ -f "$remote_home/.claude/skills/devloop-review/.devloop-checksum" ]] || fail "remote installer did not write Claude skill checksum"
ok "remote installer successful install"

printf '%s\n' "user edit" >> "$remote_home/.agents/skills/devloop-review/SKILL.md"
remote_preserve_output="$(
  HOME="$remote_home" PATH="$remote_path" bash "$REMOTE_INSTALLER" \
    --yes \
    --version "$remote_version" \
    --release-base-url "$remote_release_base" \
    2>&1
)"
contains "$remote_preserve_output" "skipping modified skill" "remote installer modified skill guard"
contains "$(cat "$remote_home/.agents/skills/devloop-review/SKILL.md")" "user edit" "remote installer modified skill preserved"
ok "remote installer skill preservation"

remote_no_skills_home="$work/remote-no-skills-home"
remote_no_skills_output="$(
  HOME="$remote_no_skills_home" PATH="$remote_path" bash "$REMOTE_INSTALLER" \
    --yes \
    --no-skills \
    --version "$remote_version" \
    --release-base-url "$remote_release_base" \
    2>&1
)"
contains "$remote_no_skills_output" "skipping skill installation" "remote no-skills"
contains "$remote_no_skills_output" "devloop doctor will require skill installation before agent loops are ready." "remote no-skills"
[[ ! -e "$remote_no_skills_home/.agents/skills/devloop-spec" ]] || fail "remote no-skills installed Codex skill"
[[ ! -e "$remote_no_skills_home/.claude/skills/devloop-review" ]] || fail "remote no-skills installed Claude skill"
ok "remote installer no-skills"

uninstall_home="$work/uninstall-home"
HOME="$uninstall_home" PATH="$remote_path" bash "$REMOTE_INSTALLER" \
  --yes \
  --version "$remote_version" \
  --release-base-url "$remote_release_base" \
  >/dev/null 2>&1 || fail "uninstall fixture install failed"
uninstall_root="$uninstall_home/.local/share/devloop"
uninstall_bin="$uninstall_home/.local/bin"
[[ -L "$uninstall_bin/devloop" ]] || fail "uninstall fixture missing symlink"
[[ -d "$uninstall_root/$remote_version" ]] || fail "uninstall fixture missing runtime"
[[ -d "$uninstall_home/.agents/skills/devloop-spec" ]] || fail "uninstall fixture missing skill"
uninstall_dry_output="$(
  DEVLOOP_BIN_DIR="$uninstall_bin" DEVLOOP_INSTALL_DIR="$uninstall_root" HOME="$uninstall_home" \
    "$SCRIPTS_DIR/uninstall.sh" --dry-run 2>&1
)"
contains "$uninstall_dry_output" "dry run: no files will be changed" "uninstall dry run"
contains "$uninstall_dry_output" "would remove symlink: $uninstall_bin/devloop" "uninstall dry run symlink"
contains "$uninstall_dry_output" "would remove staged runtime: $uninstall_root" "uninstall dry run runtime"
contains "$uninstall_dry_output" "would remove skill: $uninstall_home/.agents/skills/devloop-spec" "uninstall dry run skill"
[[ -L "$uninstall_bin/devloop" ]] || fail "uninstall dry run removed symlink"
[[ -d "$uninstall_root/$remote_version" ]] || fail "uninstall dry run removed runtime"
[[ -d "$uninstall_home/.claude/skills/devloop-review" ]] || fail "uninstall dry run removed skill"
uninstall_output="$(
  DEVLOOP_BIN_DIR="$uninstall_bin" DEVLOOP_INSTALL_DIR="$uninstall_root" HOME="$uninstall_home" \
    "$SCRIPTS_DIR/uninstall.sh" 2>&1
)"
contains "$uninstall_output" "removed symlink $uninstall_bin/devloop" "uninstall symlink"
contains "$uninstall_output" "removed staged runtime $uninstall_root" "uninstall runtime"
contains "$uninstall_output" "devloop uninstalled" "uninstall banner"
[[ ! -e "$uninstall_bin/devloop" ]] || fail "uninstall left symlink"
[[ ! -e "$uninstall_root" ]] || fail "uninstall left staged runtime"
[[ ! -e "$uninstall_home/.agents/skills/devloop-spec" ]] || fail "uninstall left Codex skill"
[[ ! -e "$uninstall_home/.claude/skills/devloop-review" ]] || fail "uninstall left Claude skill"
uninstall_again_output="$(
  DEVLOOP_BIN_DIR="$uninstall_bin" DEVLOOP_INSTALL_DIR="$uninstall_root" HOME="$uninstall_home" \
    "$SCRIPTS_DIR/uninstall.sh" 2>&1
)" || fail "second uninstall run failed"
contains "$uninstall_again_output" "devloop uninstalled" "uninstall idempotent"
not_contains "$uninstall_again_output" "removed symlink" "uninstall idempotent no-op"
ok "uninstall script removes installed footprint"

bin_dir="$work/bin"
install_home="$work/install-home"
tool_bin="$work/tool-bin"
mkdir -p "$tool_bin"
cat > "$tool_bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "install" ]; then exit 1; fi
shift
tool_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
for formula in "$@"; do
  case "$formula" in
    gum|fzf)
      printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tool_dir/$formula"
      chmod +x "$tool_dir/$formula"
      ;;
    *) exit 1 ;;
  esac
done
BREW
chmod +x "$tool_bin/brew"
install_path="$tool_bin:/usr/bin:/bin:/usr/sbin:/sbin"
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" PATH="$install_path" "$SCRIPTS_DIR/install.sh" >/tmp/devloop-install-test.out
[[ -x "$REPO_ROOT/devloop" ]] || fail "devloop is not executable"
[[ -L "$bin_dir/devloop" ]] || fail "installer did not create symlink"
contains "$(cat /tmp/devloop-install-test.out)" "gh auth login" "installer optional gh auth"
PATH="$install_path" command -v gum >/dev/null 2>&1 || fail "installer did not make gum available"
PATH="$install_path" command -v fzf >/dev/null 2>&1 || fail "installer did not make fzf available"
[[ -f "$install_home/.agents/skills/devloop-spec/SKILL.md" ]] || fail "installer did not install Codex spec skill"
[[ -f "$install_home/.agents/skills/devloop-spec/references/spec-template.md" ]] || fail "installer did not install Codex spec template reference"
[[ -f "$install_home/.agents/skills/devloop-review/SKILL.md" ]] || fail "installer did not install Codex review skill"
[[ -f "$install_home/.agents/skills/devloop-review/.devloop-checksum" ]] || fail "installer did not write Codex checksum"
[[ -f "$install_home/.claude/skills/devloop-spec/SKILL.md" ]] || fail "installer did not install Claude spec skill"
[[ -f "$install_home/.claude/skills/devloop-review/SKILL.md" ]] || fail "installer did not install Claude review skill"
[[ -f "$install_home/.claude/skills/devloop-review/.devloop-checksum" ]] || fail "installer did not write Claude checksum"
"$bin_dir/devloop" --help >/tmp/devloop-help-test.out
contains "$(cat /tmp/devloop-help-test.out)" "Spec-driven code and review loop." "installed help"
ok "installer"

printf '%s\n' "user edit" >> "$install_home/.agents/skills/devloop-review/SKILL.md"
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" PATH="$install_path" "$SCRIPTS_DIR/install.sh" >/tmp/devloop-install-skip.out 2>&1
contains "$(cat /tmp/devloop-install-skip.out)" "skipping modified skill" "installer modified skill guard"
contains "$(cat /tmp/devloop-install-skip.out)" "try: devloop" "installer guidance after skill skip"
contains "$(cat "$install_home/.agents/skills/devloop-review/SKILL.md")" "user edit" "installer modified skill preserved"
DEVLOOP_FORCE=1 DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" PATH="$install_path" "$SCRIPTS_DIR/install.sh" >/tmp/devloop-install-force.out
if grep -q "user edit" "$install_home/.agents/skills/devloop-review/SKILL.md"; then fail "installer force did not restore skill"; fi
ok "installer skill updates"

fake_bin="$work/fake-bin"
mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/claude"
cat > "$fake_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

state="${DEVLOOP_GH_STATE:-${TMPDIR:-/tmp}/devloop-gh-state}"
mkdir -p "$state/comments"
if [ -n "${DEVLOOP_GH_LOG:-}" ]; then
  printf 'gh %s\n' "$*" >> "$DEVLOOP_GH_LOG"
fi

case "${1:-}" in
  auth)
    if [ "${2:-}" != "status" ]; then exit 1; fi
    if [ "${DEVLOOP_GH_AUTH_FAIL:-0}" = "1" ]; then
      printf '%s\n' "gh auth exploded" >&2
      exit 1
    fi
    printf '%s\n' "Logged in to github.com"
    ;;
  repo)
    if [ "${2:-}" != "view" ]; then exit 1; fi
    if [ "${DEVLOOP_GH_REPO_FAIL:-0}" = "1" ]; then
      printf '%s\n' "gh repo exploded" >&2
      exit 1
    fi
    printf '%s\n' "satyaborg/devloop"
    ;;
  pr)
    shift
    case "${1:-}" in
      list)
        if [ "${DEVLOOP_GH_LOOKUP_FAIL:-0}" = "1" ]; then
          printf '%s\n' "gh pr lookup exploded" >&2
          exit 1
        fi
        if [ -f "$state/pr_url" ]; then cat "$state/pr_url"; fi
        ;;
      create)
        if [ "${DEVLOOP_GH_CREATE_FAIL:-0}" = "1" ]; then
          printf '%s\n' "gh pr create exploded" >&2
          exit 1
        fi
        head=""
        body_file=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --head)
              shift
              head="${1:-}"
              ;;
            --body-file)
              shift
              body_file="${1:-}"
              ;;
          esac
          shift || true
        done
        if [ -n "$head" ] && ! git ls-remote --heads origin "$head" | grep -q .; then
          printf 'head branch was not pushed before PR creation: %s\n' "$head" >&2
          exit 1
        fi
        if [ -n "$body_file" ]; then
          cp "$body_file" "$state/pr-body.md"
        fi
        url="${DEVLOOP_GH_PR_URL:-https://github.com/satyaborg/devloop/pull/123}"
        printf '%s\n' "$url" > "$state/pr_url"
        printf '%s\n' "$url"
        ;;
      comment)
        if [ "${DEVLOOP_GH_COMMENT_FAIL:-0}" = "1" ]; then
          printf '%s\n' "gh comment exploded" >&2
          exit 1
        fi
        body_file=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --body-file)
              shift
              body_file="${1:-}"
              ;;
          esac
          shift || true
        done
        [ -n "$body_file" ] || exit 1
        count="$(find "$state/comments" -type f | wc -l | tr -d ' ')"
        body="$state/comments/comment-$((count + 1)).md"
        cp "$body_file" "$body"
        if grep -q '^# Devloop Review Round ' "$body"; then
          round_count="$(find "$state/comments" -name 'round-*.md' | wc -l | tr -d ' ')"
          cp "$body" "$state/comments/round-$((round_count + 1)).md"
          cp "$body" "$state/latest_round_comment"
        elif grep -q '^# Devloop Final Report' "$body"; then
          final_count="$(find "$state/comments" -name 'final-*.md' | wc -l | tr -d ' ')"
          cp "$body" "$state/comments/final-$((final_count + 1)).md"
        fi
        printf '%s\n' "commented"
        ;;
      view)
        if [ "${DEVLOOP_GH_VIEW_FAIL:-0}" = "1" ]; then
          printf '%s\n' "gh pr view exploded" >&2
          exit 1
        fi
        if [ -f "$state/latest_round_comment" ]; then cat "$state/latest_round_comment"; fi
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
GH
chmod +x "$fake_bin/gh"
chmod +x "$fake_bin/codex" "$fake_bin/claude"
doctor_output="$(HOME="$install_home" PATH="$bin_dir:$tool_bin:$fake_bin:$PATH" "$bin_dir/devloop" doctor 2>&1)"
contains "$doctor_output" "devloop doctor: ready" "doctor"
contains "$doctor_output" "Required dependencies" "doctor"
contains "$doctor_output" "[ok] codex:" "doctor"
contains "$doctor_output" "[ok] claude:" "doctor"
contains "$doctor_output" "[ok] skill devloop-spec" "doctor"
contains "$doctor_output" "[ok] gum:" "doctor"
contains "$doctor_output" "[ok] fzf:" "doctor"
contains "$doctor_output" "GitHub PR integration" "doctor"
contains "$doctor_output" "[PASS] gh installed" "doctor"
contains "$doctor_output" "[PASS] gh authenticated" "doctor"
contains "$doctor_output" "[PASS] current repo has origin" "doctor"
contains "$doctor_output" "[PASS] current repo resolves on GitHub" "doctor"
not_contains "$doctor_output" "Optional UI" "doctor"
contains "$doctor_output" "$install_home/.agents/skills/devloop-spec" "doctor Codex skill"
contains "$doctor_output" "$install_home/.claude/skills/devloop-spec" "doctor Claude skill"
ok "doctor"

no_gh_bin="$work/no-gh-bin"
mkdir -p "$no_gh_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$no_gh_bin/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$no_gh_bin/claude"
chmod +x "$no_gh_bin/codex" "$no_gh_bin/claude"
# Mirror the system bin dirs without gh so `command -v gh` fails regardless of
# where gh is installed on the host (CI runners ship gh in /usr/bin).
sys_clean="$work/sys-clean"
mkdir -p "$sys_clean"
for sys_dir in /usr/bin /bin; do
  [ -d "$sys_dir" ] || continue
  for sys_entry in "$sys_dir"/*; do
    sys_name="$(basename "$sys_entry")"
    [ "$sys_name" = "gh" ] && continue
    [ -e "$sys_clean/$sys_name" ] && continue
    ln -s "$sys_entry" "$sys_clean/$sys_name"
  done
done
doctor_no_gh_output="$(HOME="$install_home" PATH="$bin_dir:$tool_bin:$no_gh_bin:$sys_clean" "$bin_dir/devloop" doctor 2>&1)" || fail "doctor failed when gh was unavailable"
contains "$doctor_no_gh_output" "devloop doctor: ready" "doctor no gh"
contains "$doctor_no_gh_output" "[FAIL] gh installed" "doctor no gh"
contains "$doctor_no_gh_output" "PR-backed loop readiness unavailable" "doctor no gh"
ok "doctor optional GitHub readiness"

agent="$work/spec-agent"
cat > "$agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >/tmp/devloop-spec-agent-prompt.txt
printf '%s\n' "launched spec agent"
AGENT
chmod +x "$agent"

repo="$work/repo"
spec_home="$work/spec-home"
repo_specs="$work/repo-specs"
mkdir -p "$repo" "$spec_home/.devloop"
printf 'spec_dir=%s\n' "$repo_specs" > "$spec_home/.devloop/config"
old_use_tui="$USE_TUI"
USE_TUI=false
(
  cd "$repo"
  HOME="$spec_home" main spec --agent "$agent" "Keep devloop as Bash." >/tmp/devloop-spec-test.out
)
USE_TUI="$old_use_tui"
repo_specs_real="$(cd "$repo_specs" && pwd -P)"
contains "$(cat /tmp/devloop-spec-test.out)" "interactive spec session" "spec command"
contains "$(cat /tmp/devloop-spec-test.out)" "write: $repo_specs_real" "spec command target"
if [ -f "$repo_specs/$(date +%F)-shell-migration-spec.md" ]; then fail "spec command wrote the spec instead of launching the agent"; fi
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Skill: use the installed devloop-spec skill." "spec prompt skill"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Keep devloop as Bash." "spec prompt"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Requested spec path: choose $repo_specs_real/$(date +%F)-<slug>.md" "spec prompt configured output"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Devloop owns the implementation" "spec prompt ownership"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "devloop --create-pr <spec path>" "spec prompt handoff"
contains "$(absolute_path "$work/absolute-path/nested.md")" "/absolute-path/nested.md" "absolute path"
existing_spec="$repo/existing.md"
existing_spec_real="$(cd "$repo" && pwd -P)/existing.md"
printf '%s\n' "# Existing" > "$existing_spec"
rm -f /tmp/devloop-spec-agent-prompt.txt
if (cd "$repo" && HOME="$spec_home" main spec --agent "$agent" --output "$existing_spec" "Replace me") >/tmp/devloop-spec-existing.out 2>/tmp/devloop-spec-existing.err; then fail "spec command allowed existing output without force"; fi
contains "$(cat /tmp/devloop-spec-existing.err)" "spec already exists: $existing_spec_real" "spec existing output"
if [ -f /tmp/devloop-spec-agent-prompt.txt ]; then fail "spec command launched agent for existing output"; fi
ok "spec launch"

cat > "$fake_bin/codex" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
prompt="$(cat)"
if printf '%s\n' "$prompt" | grep -q "Work item naming task"; then
  printf '%s\n' '{"type":"feat","slug":"fake-loop","breaking":false}'
  exit 0
fi
pass="$(printf '%s\n' "$prompt" | sed -nE 's/^Pass: ([0-9]+).*/\1/p' | head -n 1)"
track="$(printf '%s\n' "$prompt" | sed -nE 's/^Track: (.+)$/\1/p' | head -n 1)"
mode="${DEVLOOP_FAKE_MODE:-accept}"
if [ -n "${DEVLOOP_AGENT_LOG:-}" ]; then
  printf 'agent coder %s\n' "${pass:-1}" >> "$DEVLOOP_AGENT_LOG"
  if [ "${pass:-1}" = "2" ]; then
    if printf '%s\n' "$prompt" | grep -q "# Devloop Review Round 1"; then
      printf '%s\n' "coder-pr-prior:yes" >> "$DEVLOOP_AGENT_LOG"
    else
      printf '%s\n' "coder-pr-prior:no" >> "$DEVLOOP_AGENT_LOG"
    fi
  fi
fi
case "$mode" in
  no-changes) ;;
  *) printf 'pass %s\n' "${pass:-1}" >> result.txt ;;
esac
if [ -n "$track" ]; then
  {
    printf '\n## fake coder pass %s\n' "${pass:-1}"
    printf -- '- mode: %s\n' "$mode"
  } >> "$track"
fi
printf '%s\n' "To continue this session, run codex exec resume 11111111-1111-4111-8111-111111111111"
AGENT

cat > "$fake_bin/claude" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
prompt="$(cat)"
if printf '%s\n' "$prompt" | grep -q "learning-oriented post-mortem"; then
  report="$(printf '%s\n' "$prompt" | sed -nE 's/.*Write the report to ([^ ]+) .*/\1/p' | head -n 1)"
  if [ -z "$report" ]; then report=".devloop/reports/fake.md"; fi
  mkdir -p "$(dirname "$report")"
  printf '%s\n' "# Fake report" "Result: ${DEVLOOP_FAKE_MODE:-accept}" > "$report"
  exit 0
fi
output="$(printf '%s\n' "$prompt" | sed -nE 's/^Output path: (.+)$/\1/p' | head -n 1)"
pass="$(printf '%s\n' "$prompt" | sed -nE 's/^Pass: ([0-9]+).*/\1/p' | head -n 1)"
mode="${DEVLOOP_FAKE_MODE:-accept}"
if [ -n "${DEVLOOP_AGENT_LOG:-}" ] && [ -n "$pass" ]; then
  printf 'agent reviewer %s\n' "$pass" >> "$DEVLOOP_AGENT_LOG"
fi
if [ "$mode" = "missing-review" ]; then exit 0; fi
verdict="ACCEPT"
ac_status="PASS"
maintainability="PASS"
findings="None"
fixes="None"
case "$mode" in
  reject-then-accept)
    if [ "${pass:-1}" = "1" ]; then
      verdict="REJECT"
      findings="1. [should-fix] result.txt:1 - first pass incomplete. Root cause: fixture. Principle: retry."
      fixes="1. Complete the fixture."
    fi
    ;;
  bad-ac) ac_status="FAIL" ;;
  bad-quality) maintainability="FAIL" ;;
  unclear) verdict="UNCLEAR" ;;
esac
mkdir -p "$(dirname "$output")"
cat > "$output" <<MARKDOWN
# Review ${pass:-1}

Verdict: $verdict

## Acceptance matrix

| Criterion | Status | Implementation evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | $ac_status | result.txt | fake verification |

## Engineering quality matrix

| Area | Status | Evidence |
| --- | --- | --- |
| Correctness | PASS | fixture |
| Test quality | PASS | fixture |
| Maintainability | $maintainability | fixture |
| Architecture boundaries | PASS | fixture |
| Simplicity | PASS | fixture |
| Security | N/A | fixture |
| Operational safety | PASS | fixture |

## Review flags

- Silent decision: absent - None
- Scope drift: absent - None
- Missing test: absent - None

## Findings

$findings

## Missing tests

- None

## Fix instructions

$fixes

## Notes

- None
MARKDOWN
AGENT
chmod +x "$fake_bin/codex" "$fake_bin/claude"

helper_home="$work/helper-home"
mkdir -p "$helper_home"
helper_output="$(HOME="$helper_home" DEVLOOP_FORCE=1 devloop_install_skills "$REPO_ROOT" 2>&1)" || fail "direct skill install failed"
contains "$helper_output" "installed skill devloop-spec" "direct skill install"
contains "$(HOME="$helper_home" devloop_skills_dirs)" "$helper_home/.agents/skills" "skill dirs"
devloop_can_replace_skill "$helper_home/.agents/skills/devloop-spec" || fail "installed skill should be replaceable"
devloop_valid_skill_name "devloop-spec" || fail "valid skill name rejected"
equals "$(devloop_skill_name "$helper_home/.agents/skills/devloop-spec/SKILL.md")" "devloop-spec" "skill name"
helper_doctor_output="$(HOME="$helper_home" PATH="$fake_bin:$bin_dir:$tool_bin:$sys_clean" devloop_doctor "$REPO_ROOT" 2>&1)" || fail "direct doctor failed"
contains "$helper_doctor_output" "devloop doctor: ready" "direct doctor"
ok "direct skill helpers"

uninstall_helper_home="$work/uninstall-helper-home"
mkdir -p "$uninstall_helper_home"
HOME="$uninstall_helper_home" DEVLOOP_FORCE=1 devloop_install_skills "$REPO_ROOT" >/dev/null 2>&1 || fail "uninstall helper install failed"
printf '%s\n' "user edit" >> "$uninstall_helper_home/.agents/skills/devloop-review/SKILL.md"
uninstall_helper_out="$(HOME="$uninstall_helper_home" devloop_uninstall_skills "$REPO_ROOT" 2>&1)"
contains "$uninstall_helper_out" "removed skill devloop-spec" "uninstall helper removes clean skill"
contains "$uninstall_helper_out" "skipping modified skill" "uninstall helper guards modified skill"
[[ ! -e "$uninstall_helper_home/.agents/skills/devloop-spec" ]] || fail "uninstall helper left clean skill"
[[ -f "$uninstall_helper_home/.agents/skills/devloop-review/SKILL.md" ]] || fail "uninstall helper removed modified skill"
HOME="$uninstall_helper_home" DEVLOOP_FORCE=1 devloop_uninstall_skills "$REPO_ROOT" >/dev/null 2>&1 || fail "forced uninstall failed"
[[ ! -e "$uninstall_helper_home/.agents/skills/devloop-review" ]] || fail "forced uninstall left modified skill"
ok "direct uninstall skill helpers"

make_loop_repo() {
  local repo_path="$1"
  local slug="$2"
  local title="$3"
  mkdir -p "$repo_path/.specs"
  git init -q "$repo_path"
  git -C "$repo_path" config user.email devloop-test@example.com
  git -C "$repo_path" config user.name "devloop test"
  printf '%s\n' "# Fixture" > "$repo_path/README.md"
  git -C "$repo_path" add README.md
  git -C "$repo_path" commit -q -m init
  cat > "$repo_path/.specs/$slug.md" <<MARKDOWN
---
status: draft
type: feat
slug: $slug
breaking: false
pr: null
---

# $title

## Problem

The result file is never written during the loop.

## Outcome

The loop writes the result file on accept.

## Acceptance criteria
1. Write the result file.
MARKDOWN
}

add_origin_remote() {
  local repo_path="$1"
  local remote_path="$2"
  local branch
  git init -q --bare "$remote_path"
  branch="$(git -C "$repo_path" branch --show-current)"
  git -C "$repo_path" remote add origin "$remote_path"
  git -C "$repo_path" push -q -u origin "$branch"
  git -C "$remote_path" symbolic-ref HEAD "refs/heads/$branch"
}

naming_repo="$work/naming-repo"
mkdir -p "$naming_repo"
naming_spec="$naming_repo/partial.md"
cat > "$naming_spec" <<'MARKDOWN'
---
type: feat
---

# Partial Naming
MARKDOWN
old_path="$PATH"
PATH="$fake_bin:$PATH"
resolve_work_item codex "$naming_repo" "$naming_spec" "$(cat "$naming_spec")" >/dev/null 2>&1 || fail "naming fallback failed"
PATH="$old_path"
equals "$WORK_TYPE" "feat" "naming fallback type override"
equals "$WORK_SLUG" "fake-loop" "naming fallback slug"
equals "$WORK_BREAKING" "false" "naming fallback breaking"
ok "naming fallback"

run_loop() {
  local repo_path="$1"
  local slug="$2"
  local mode="$3"
  local max="${4:-1}"
  local extra="${5:-}"
  local args=()
  local old_home="$HOME"
  local old_path="$PATH"
  local old_mode="${DEVLOOP_FAKE_MODE-}"
  local had_mode=false
  local old_use_tui="$USE_TUI"
  local old_enter_worktree="$ENTER_WORKTREE"
  local old_start_pass="$RUN_START_PASS"
  local code
  if [ "${DEVLOOP_FAKE_MODE+x}" = "x" ]; then had_mode=true; fi
  if [ -n "$extra" ]; then args+=("$extra"); fi
  args+=(".specs/$slug.md" "$max")
  HOME="$install_home"
  PATH="$fake_bin:$bin_dir:$PATH"
  DEVLOOP_FAKE_MODE="$mode"
  export HOME PATH DEVLOOP_FAKE_MODE
  USE_TUI=false
  ENTER_WORKTREE=false
  RUN_START_PASS=1
  (
    cd "$repo_path"
    main --plain --no-shell "${args[@]}"
  )
  code=$?
  HOME="$old_home"
  PATH="$old_path"
  if [ "$had_mode" = true ]; then DEVLOOP_FAKE_MODE="$old_mode"; export DEVLOOP_FAKE_MODE; else unset DEVLOOP_FAKE_MODE; fi
  USE_TUI="$old_use_tui"
  ENTER_WORKTREE="$old_enter_worktree"
  RUN_START_PASS="$old_start_pass"
  export HOME PATH
  return "$code"
}

run_repo_main() {
  local repo_path="$1"
  shift
  local old_home="$HOME"
  local old_path="$PATH"
  local old_use_tui="$USE_TUI"
  local code
  HOME="$install_home"
  PATH="$fake_bin:$bin_dir:$PATH"
  USE_TUI=false
  export HOME PATH
  (
    cd "$repo_path"
    main "$@"
  )
  code=$?
  HOME="$old_home"
  PATH="$old_path"
  USE_TUI="$old_use_tui"
  export HOME PATH
  return "$code"
}

continue_track_with_fake_agents() {
  local track="$1"
  local old_home="$HOME"
  local old_path="$PATH"
  local old_mode="${DEVLOOP_FAKE_MODE-}"
  local had_mode=false
  local old_use_tui="$USE_TUI"
  local old_enter_worktree="$ENTER_WORKTREE"
  local code
  if [ "${DEVLOOP_FAKE_MODE+x}" = "x" ]; then had_mode=true; fi
  HOME="$install_home"
  PATH="$fake_bin:$bin_dir:$PATH"
  DEVLOOP_FAKE_MODE=accept
  export HOME PATH DEVLOOP_FAKE_MODE
  USE_TUI=false
  ENTER_WORKTREE=false
  run_from_track "$track" 2>&1
  code=$?
  HOME="$old_home"
  PATH="$old_path"
  if [ "$had_mode" = true ]; then DEVLOOP_FAKE_MODE="$old_mode"; export DEVLOOP_FAKE_MODE; else unset DEVLOOP_FAKE_MODE; fi
  USE_TUI="$old_use_tui"
  ENTER_WORKTREE="$old_enter_worktree"
  export HOME PATH
  return "$code"
}

preflight_pr_repo="$work/preflight-pr-repo"
make_loop_repo "$preflight_pr_repo" "preflight-pr" "Preflight PR"
add_origin_remote "$preflight_pr_repo" "$work/preflight-pr-remote.git"
old_home="$HOME"
old_path="$PATH"
HOME="$install_home"
PATH="$no_gh_bin:$bin_dir:$tool_bin:$sys_clean"
export HOME PATH
if preflight_run "$preflight_pr_repo" codex claude true >/dev/null 2>&1; then fail "PR preflight accepted missing gh"; fi
contains "$PREFLIGHT_ERROR" "missing command: gh" "PR preflight missing gh"
PATH="$fake_bin:$bin_dir:$tool_bin:$old_path"
DEVLOOP_GH_AUTH_FAIL=1
export DEVLOOP_GH_AUTH_FAIL
if preflight_run "$preflight_pr_repo" codex claude true >/dev/null 2>&1; then fail "PR preflight accepted failed gh auth"; fi
contains "$PREFLIGHT_ERROR" "gh auth status failed: gh auth exploded" "PR preflight auth"
unset DEVLOOP_GH_AUTH_FAIL
preflight_no_origin="$work/preflight-no-origin"
make_loop_repo "$preflight_no_origin" "preflight-no-origin" "Preflight No Origin"
if preflight_run "$preflight_no_origin" codex claude true >/dev/null 2>&1; then fail "PR preflight accepted missing origin"; fi
contains "$PREFLIGHT_ERROR" "missing origin remote" "PR preflight origin"
DEVLOOP_GH_REPO_FAIL=1
export DEVLOOP_GH_REPO_FAIL
if preflight_run "$preflight_pr_repo" codex claude true >/dev/null 2>&1; then fail "PR preflight accepted failed repo lookup"; fi
contains "$PREFLIGHT_ERROR" "GitHub repo lookup failed: gh repo exploded" "PR preflight repo"
unset DEVLOOP_GH_REPO_FAIL
PATH="$old_path"
HOME="$old_home"
export HOME PATH
ok "PR preflight failures"

interactive_pr_repo="$work/interactive-pr-repo"
make_loop_repo "$interactive_pr_repo" "interactive-pr" "Interactive PR"
add_origin_remote "$interactive_pr_repo" "$work/interactive-pr-remote.git"
old_home="$HOME"
old_path="$PATH"
old_use_tui="$USE_TUI"
HOME="$install_home"
PATH="$fake_bin:$bin_dir:$tool_bin:$PATH"
USE_TUI=false
export HOME PATH
equals "$(cd "$interactive_pr_repo" && interactive_create_pr_choice "$interactive_pr_repo")" "true" "interactive PR prompt defaults yes when ready"
pr_cancel_code="$(
  set +e
  cd "$interactive_pr_repo" || exit 99
  ui_confirm() { return 130; }
  interactive_create_pr_choice "$interactive_pr_repo" >/dev/null 2>&1
  printf '%s\n' "$?"
)"
equals "$pr_cancel_code" "130" "interactive PR prompt preserves cancel"
PATH="$no_gh_bin:$bin_dir:$tool_bin:$sys_clean"
equals "$(cd "$interactive_pr_repo" && interactive_create_pr_choice "$interactive_pr_repo")" "false" "interactive PR prompt falls back local-only when unavailable"
PATH="$old_path"
HOME="$old_home"
USE_TUI="$old_use_tui"
export HOME PATH
ok "interactive PR prompt"

loop_repo="$work/loop-accept"
make_loop_repo "$loop_repo" "e2e-accept" "E2E Accept"
no_pr_gh_log="$work/no-pr-gh.log"
DEVLOOP_GH_LOG="$no_pr_gh_log"
export DEVLOOP_GH_LOG
mkdir -p "$loop_repo/.devloop"
cat > "$loop_repo/.devloop/verify" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'verify pass %s %s\n' "${1:-}" "${2:-}"
VERIFY
chmod +x "$loop_repo/.devloop/verify"
if ! accept_output="$(run_loop "$loop_repo" "e2e-accept" accept 1 2>&1)"; then
  printf '%s\n' "$accept_output" >&2
  fail "accept loop failed"
fi
contains "$accept_output" "accepted" "accept loop"
accept_worktree="$(printf '%s\n' "$accept_output" | sed -nE 's/^[[:space:]]*Worktree[[:space:]]+//p')"
[[ -f "$accept_worktree/result.txt" ]] || fail "accept loop did not write result"
contains "$accept_output" "Open Next" "accept loop"
if ! printf '%s\n' "$accept_output" | grep -F "Report" | grep -F "$accept_worktree/.devloop/reports/e2e-accept.html" >/dev/null; then
  fail "accept loop missing worktree-qualified report path"
fi
if ! printf '%s\n' "$accept_output" | grep -F "Track" | grep -F "$accept_worktree/.devloop/tracks/e2e-accept.md" >/dev/null; then
  fail "accept loop missing worktree-qualified track path"
fi
contains "$(cat "$accept_worktree/.devloop/logs/e2e-accept-r1-verify.log")" "verify pass" "verify hook"
contains "$(run_repo_main "$loop_repo" status)" "e2e-accept" "status command"
contains "$(run_repo_main "$loop_repo" clean --dry-run)" "skip:" "clean skips accepted"
if ! continue_output="$(continue_track_with_fake_agents "$accept_worktree/.devloop/tracks/e2e-accept.md")" ; then
  printf '%s\n' "$continue_output" >&2
  fail "continue run failed"
fi
contains "$continue_output" "accepted" "continue run"
contains "$(run_repo_main "$loop_repo" reports)" ".devloop/reports/e2e-accept" "reports command"
contains "$(run_repo_main "$loop_repo" continue)" ".devloop/tracks/e2e-accept.md" "continue command lists tracks"
if grep -Eq '^gh pr (create|comment|list|view)' "$no_pr_gh_log" 2>/dev/null; then fail "local-only loop touched PR commands"; fi
unset DEVLOOP_GH_LOG
ok "e2e accept and verify"

loop_repo="$work/loop-retry"
make_loop_repo "$loop_repo" "e2e-retry" "E2E Retry"
if ! retry_output="$(run_loop "$loop_repo" "e2e-retry" reject-then-accept 2 2>&1)"; then
  printf '%s\n' "$retry_output" >&2
  fail "retry loop failed"
fi
contains "$retry_output" "accepted" "retry loop"
contains "$retry_output" "2 / 2" "retry loop passes"
ok "e2e reject then accept"

pr_repo="$work/loop-pr-accept"
make_loop_repo "$pr_repo" "e2e-pr-accept" "E2E PR Accept"
add_origin_remote "$pr_repo" "$work/loop-pr-accept-remote.git"
pr_state="$work/gh-pr-accept"
pr_log="$work/gh-pr-accept.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
if ! pr_accept_output="$(run_loop "$pr_repo" "e2e-pr-accept" accept 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_accept_output" >&2
  fail "PR accept loop failed"
fi
contains "$pr_accept_output" "accepted" "PR accept loop"
contains "$pr_accept_output" "Open Next" "PR accept loop"
contains "$pr_accept_output" "PR         https://github.com/satyaborg/devloop/pull/123" "PR accept loop"
create_line="$(grep -n 'gh pr create' "$pr_log" | cut -d: -f1 | head -n 1)"
review_line="$(grep -n 'agent reviewer 1' "$pr_log" | cut -d: -f1 | head -n 1)"
[[ -n "$create_line" && -n "$review_line" && "$create_line" -lt "$review_line" ]] || fail "PR was not created before reviewer pass 1"
contains "$(cat "$pr_log")" "--body-file" "PR create body flag"
[[ -s "$pr_state/pr-body.md" ]] || fail "created PR body missing"
pr_body="$(cat "$pr_state/pr-body.md")"
contains "$pr_body" "E2E PR Accept" "created PR body"
contains "$pr_body" "## Problem" "created PR body"
contains "$pr_body" "The result file is never written during the loop." "created PR body"
contains "$pr_body" "## Outcome" "created PR body"
contains "$pr_body" "The loop writes the result file on accept." "created PR body"
contains "$pr_body" "Latest commit" "created PR body"
if ! printf '%s\n' "$pr_body" | grep -Eq 'Latest commit:[[:space:]]*[0-9a-f]{7,}'; then fail "created PR body missing commit hash"; fi
contains "$pr_body" "Write the result file." "created PR body"
if printf '%s\n' "$pr_body" | grep -q '/Users/'; then fail "created PR body leaked absolute local path"; fi
equals "$(find "$pr_state/comments" -name 'round-*.md' | wc -l | tr -d ' ')" "1" "one round PR comment"
equals "$(find "$pr_state/comments" -name 'final-*.md' | wc -l | tr -d ' ')" "1" "one final PR comment"
round_body="$(cat "$pr_state/comments/round-1.md")"
contains "$round_body" "# Devloop Review Round 1" "round PR comment"
contains "$round_body" "Verdict: ACCEPT" "round PR comment"
contains "$round_body" "## Acceptance matrix" "round PR comment"
contains "$round_body" "| AC1 | PASS |" "round PR comment"
contains "$round_body" "## Engineering quality matrix" "round PR comment"
contains "$round_body" "| Security | N/A |" "round PR comment"
contains "$round_body" "## Review flags" "round PR comment"
contains "$round_body" "## Findings" "round PR comment"
contains "$round_body" "## Missing tests" "round PR comment"
contains "$round_body" "## Fix instructions" "round PR comment"
contains "$round_body" "## Notes" "round PR comment"
final_body="$(cat "$pr_state/comments/final-1.md")"
contains "$final_body" "# Devloop Final Report" "final PR comment"
contains "$final_body" "Final status" "final PR comment"
contains "$final_body" "Pass count" "final PR comment"
contains "$final_body" "Final verdict" "final PR comment"
contains "$final_body" "Acceptance Matrix Summary" "final PR comment"
contains "$final_body" "Engineering Quality Summary" "final PR comment"
contains "$final_body" "Implementation Summary" "final PR comment"
contains "$final_body" "Tests Run" "final PR comment"
contains "$final_body" "Residual Risk" "final PR comment"
contains "$final_body" "PR URL" "final PR comment"
contains "$final_body" "Branch" "final PR comment"
contains "$final_body" "Commit References" "final PR comment"
if printf '%s\n' "$final_body" | grep -q '/Users/'; then fail "final PR comment leaked absolute local path"; fi
if printf '%s\n' "$round_body" | grep -q 'Local cache'; then fail "round PR comment leaked local cache path"; fi
if printf '%s\n' "$final_body" | grep -Eq '<(html|script|style)'; then fail "final PR comment embedded standalone HTML"; fi
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
ok "PR-backed accept comments"

pr_repo="$work/loop-pr-terminal"
make_loop_repo "$pr_repo" "e2e-pr-terminal" "E2E PR Terminal"
add_origin_remote "$pr_repo" "$work/loop-pr-terminal-remote.git"
pr_state="$work/gh-pr-terminal"
pr_log="$work/gh-pr-terminal.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
if pr_terminal_output="$(run_loop "$pr_repo" "e2e-pr-terminal" bad-ac 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_terminal_output" >&2
  fail "PR terminal failure loop unexpectedly passed"
fi
contains "$pr_terminal_output" "unclear" "PR terminal failure"
equals "$(find "$pr_state/comments" -name 'round-*.md' | wc -l | tr -d ' ')" "1" "terminal round PR comment"
equals "$(find "$pr_state/comments" -name 'final-*.md' | wc -l | tr -d ' ')" "1" "terminal final PR comment"
contains "$(cat "$pr_state/comments/final-1.md")" "| Final status | unclear |" "terminal final PR comment"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
ok "PR-backed terminal final comment"

pr_repo="$work/loop-pr-existing"
make_loop_repo "$pr_repo" "e2e-pr-existing" "E2E PR Existing"
add_origin_remote "$pr_repo" "$work/loop-pr-existing-remote.git"
pr_state="$work/gh-pr-existing"
pr_log="$work/gh-pr-existing.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
printf '%s\n' "https://github.com/satyaborg/devloop/pull/456" > "$pr_state/pr_url"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
if ! pr_existing_output="$(run_loop "$pr_repo" "e2e-pr-existing" accept 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_existing_output" >&2
  fail "existing PR loop failed"
fi
contains "$pr_existing_output" "https://github.com/satyaborg/devloop/pull/456" "existing PR loop"
if grep -q 'gh pr create' "$pr_log"; then fail "existing PR loop created a duplicate PR"; fi
contains "$(cat "$pr_log")" "gh pr list" "existing PR lookup"
equals "$(find "$pr_state/comments" -name 'round-*.md' | wc -l | tr -d ' ')" "1" "existing PR round comment"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
ok "PR-backed existing PR reuse"

pr_repo="$work/loop-pr-retry"
make_loop_repo "$pr_repo" "e2e-pr-retry" "E2E PR Retry"
add_origin_remote "$pr_repo" "$work/loop-pr-retry-remote.git"
pr_state="$work/gh-pr-retry"
pr_log="$work/gh-pr-retry.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
if ! pr_retry_output="$(run_loop "$pr_repo" "e2e-pr-retry" reject-then-accept 2 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_retry_output" >&2
  fail "PR retry loop failed"
fi
contains "$pr_retry_output" "accepted" "PR retry loop"
contains "$(cat "$pr_log")" "coder-pr-prior:yes" "PR retry prior review"
equals "$(find "$pr_state/comments" -name 'round-*.md' | wc -l | tr -d ' ')" "2" "two round PR comments"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG
ok "PR-backed retry uses durable PR review"

pr_repo="$work/loop-pr-comment-fail"
make_loop_repo "$pr_repo" "e2e-pr-comment-fail" "E2E PR Comment Fail"
add_origin_remote "$pr_repo" "$work/loop-pr-comment-fail-remote.git"
pr_state="$work/gh-pr-comment-fail"
pr_log="$work/gh-pr-comment-fail.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
DEVLOOP_GH_COMMENT_FAIL=1
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_COMMENT_FAIL
if pr_comment_fail_output="$(run_loop "$pr_repo" "e2e-pr-comment-fail" accept 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_comment_fail_output" >&2
  fail "PR comment failure loop unexpectedly passed"
fi
contains "$pr_comment_fail_output" "pr-error" "PR comment failure"
contains "$pr_comment_fail_output" "PR comment failed: gh comment exploded" "PR comment failure"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_COMMENT_FAIL
ok "PR comment failure handling"

pr_repo="$work/loop-pr-create-fail"
make_loop_repo "$pr_repo" "e2e-pr-create-fail" "E2E PR Create Fail"
add_origin_remote "$pr_repo" "$work/loop-pr-create-fail-remote.git"
pr_state="$work/gh-pr-create-fail"
pr_log="$work/gh-pr-create-fail.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
DEVLOOP_GH_CREATE_FAIL=1
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_CREATE_FAIL
if pr_create_fail_output="$(run_loop "$pr_repo" "e2e-pr-create-fail" accept 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_create_fail_output" >&2
  fail "PR creation failure loop unexpectedly passed"
fi
contains "$pr_create_fail_output" "pr-error" "PR creation failure"
contains "$pr_create_fail_output" "PR creation failed: gh pr create exploded" "PR creation failure"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_CREATE_FAIL
ok "PR creation failure handling"

pr_repo="$work/loop-pr-lookup-fail"
make_loop_repo "$pr_repo" "e2e-pr-lookup-fail" "E2E PR Lookup Fail"
add_origin_remote "$pr_repo" "$work/loop-pr-lookup-fail-remote.git"
pr_state="$work/gh-pr-lookup-fail"
pr_log="$work/gh-pr-lookup-fail.log"
rm -rf "$pr_state"
mkdir -p "$pr_state"
DEVLOOP_GH_STATE="$pr_state"
DEVLOOP_GH_LOG="$pr_log"
DEVLOOP_AGENT_LOG="$pr_log"
DEVLOOP_GH_LOOKUP_FAIL=1
export DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_LOOKUP_FAIL
if pr_lookup_fail_output="$(run_loop "$pr_repo" "e2e-pr-lookup-fail" accept 1 "--create-pr" 2>&1)"; then
  printf '%s\n' "$pr_lookup_fail_output" >&2
  fail "PR lookup failure loop unexpectedly passed"
fi
contains "$pr_lookup_fail_output" "pr-error" "PR lookup failure"
contains "$pr_lookup_fail_output" "PR lookup failed: gh pr lookup exploded" "PR lookup failure"
unset DEVLOOP_GH_STATE DEVLOOP_GH_LOG DEVLOOP_AGENT_LOG DEVLOOP_GH_LOOKUP_FAIL
ok "PR lookup failure handling"

loop_repo="$work/loop-bad-ac"
make_loop_repo "$loop_repo" "e2e-bad-ac" "E2E Bad AC"
if bad_ac_output="$(run_loop "$loop_repo" "e2e-bad-ac" bad-ac 1 2>&1)"; then
  printf '%s\n' "$bad_ac_output" >&2
  fail "bad acceptance loop unexpectedly passed"
fi
contains "$bad_ac_output" "unclear" "bad acceptance loop"
ok "e2e bad acceptance matrix"

loop_repo="$work/loop-bad-quality"
make_loop_repo "$loop_repo" "e2e-bad-quality" "E2E Bad Quality"
if bad_quality_output="$(run_loop "$loop_repo" "e2e-bad-quality" bad-quality 1 2>&1)"; then
  printf '%s\n' "$bad_quality_output" >&2
  fail "bad quality loop unexpectedly passed"
fi
contains "$bad_quality_output" "unclear" "bad quality loop"
ok "e2e bad quality matrix"

loop_repo="$work/loop-missing-review"
make_loop_repo "$loop_repo" "e2e-missing-review" "E2E Missing Review"
if missing_review_output="$(run_loop "$loop_repo" "e2e-missing-review" missing-review 1 2>&1)"; then
  printf '%s\n' "$missing_review_output" >&2
  fail "missing review loop unexpectedly passed"
fi
contains "$missing_review_output" "review-missing" "missing review loop"
ok "e2e missing review"

loop_repo="$work/loop-no-changes"
make_loop_repo "$loop_repo" "e2e-no-changes" "E2E No Changes"
if ! no_changes_output="$(run_loop "$loop_repo" "e2e-no-changes" no-changes 1 2>&1)"; then
  printf '%s\n' "$no_changes_output" >&2
  fail "no changes loop failed"
fi
contains "$no_changes_output" "accepted" "no changes loop"
contains "$no_changes_output" "Commit     none" "no changes loop"
ok "e2e no changes"

loop_repo="$work/loop-dirty"
make_loop_repo "$loop_repo" "e2e-dirty" "E2E Dirty"
printf '%s\n' "user dirty" > "$loop_repo/dirty.txt"
if ! dirty_output="$(run_loop "$loop_repo" "e2e-dirty" accept 1 "--in-place" 2>&1)"; then
  printf '%s\n' "$dirty_output" >&2
  fail "dirty in-place loop failed"
fi
contains "$dirty_output" "accepted" "dirty loop"
contains "$(git -C "$loop_repo" status --porcelain=v1 -- dirty.txt)" "dirty.txt" "dirty file remains dirty"
if git -C "$loop_repo" show --name-only --format= HEAD | grep -Fxq "dirty.txt"; then fail "dirty file was committed"; fi
ok "e2e dirty file preserved"

loop_repo="$work/loop-verify-fail"
make_loop_repo "$loop_repo" "e2e-verify-fail" "E2E Verify Fail"
mkdir -p "$loop_repo/.devloop"
cat > "$loop_repo/.devloop/verify" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "verify failed"
exit 1
VERIFY
chmod +x "$loop_repo/.devloop/verify"
if verify_fail_output="$(run_loop "$loop_repo" "e2e-verify-fail" accept 1 2>&1)"; then
  printf '%s\n' "$verify_fail_output" >&2
  fail "verify failure loop unexpectedly passed"
fi
contains "$verify_fail_output" "verify-error" "verify failure loop"
contains "$(run_repo_main "$loop_repo" status)" "verify-error" "verify failure status"
clean_output="$(run_repo_main "$loop_repo" clean --dry-run)"
contains "$clean_output" "would remove:" "clean dry run"
run_repo_main "$loop_repo" clean --force >/tmp/devloop-clean-force.out
contains "$(cat /tmp/devloop-clean-force.out)" "removed:" "clean force"
ok "e2e verify failure and clean"

assert_project_function_coverage
