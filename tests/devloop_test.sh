#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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

equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label expected [$expected], got [$actual]"
}

bash -n "$REPO_ROOT/devloop" "$REPO_ROOT/install.sh" "$REPO_ROOT/skill_helpers.sh" "$REPO_ROOT/release.sh"
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
contains "$help" "--no-shell" "help"
contains "$help" "--enter-worktree" "help"
contains "$help" "--version" "help"
contains "$help" "v$version" "help"
contains "$help" "--timeout-minutes" "help"
ok "help output"

skill_path="$("$REPO_ROOT/devloop" spec --skill-path)"
[[ "$skill_path" == "$REPO_ROOT/skills/devloop-spec/SKILL.md" ]] || fail "unexpected skill path: $skill_path"
contains "$("$REPO_ROOT/devloop" spec --print-skill)" "name: devloop-spec" "spec skill"
ok "spec skill path"

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

review_prompt_text="$(review_prompt codex "$criteria_file" ".codex/tracks/test.md" main 1 ".codex/reviews/test-r1.md" test 5 "$criteria_file" true)"
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
mkdir -p "$branch_repo/.codex/reports" "$branch_repo/.codex/tracks" "$branch_repo/.codex/reviews"
printf '%s\n' "# Report" > "$branch_repo/.codex/reports/chat-retry.md"
branch_repo_real="$(cd "$branch_repo" && pwd -P)"
cat > "$branch_repo/.codex/tracks/chat-retry.md" <<MARKDOWN
# Track

- spec: $branch_repo_real/.specs/chat-retry.md
- worktree: $branch_repo_real
- max: 3
MARKDOWN
equals "$(cd "$branch_repo" && list_artifact_files ".codex/reports")" "$branch_repo_real/.codex/reports/chat-retry.md" "artifact listing"
equals "$(track_value max "$branch_repo/.codex/tracks/chat-retry.md")" "3" "track value"
touch "$branch_repo/.codex/reviews/chat-retry-r1.md" "$branch_repo/.codex/reviews/chat-retry-r3.md"
equals "$(next_pass_from_track "$branch_repo/.codex/tracks/chat-retry.md")" "4" "track next pass"

clean_status_repo="$work/clean-status-repo"
git init -q "$clean_status_repo"
git -C "$clean_status_repo" config user.email devloop-test@example.com
git -C "$clean_status_repo" config user.name "devloop test"
printf '%s\n' ".codex/" > "$clean_status_repo/.gitignore"
printf '%s\n' "# Clean status" > "$clean_status_repo/README.md"
git -C "$clean_status_repo" add .gitignore README.md
git -C "$clean_status_repo" commit -q -m init
mkdir -p "$clean_status_repo/.codex/tracks"
clean_status_track="$clean_status_repo/.codex/tracks/clean-status.md"
printf '%s\n' "# Track" > "$clean_status_track"
if has_user_dirty_paths "$clean_status_repo"; then fail "clean worktree reported dirty"; fi
equals "$(clean_candidate_status "$clean_status_track" "$clean_status_repo" "$work/source-repo")" "ready" "clean candidate ready"

spec_output=$'preface\n---\nstatus: draft\n---\n\n# Generated'
equals "$(extract_generated_spec "$spec_output")" $'---\nstatus: draft\n---\n\n# Generated' "extract_generated_spec"

config_repo="$work/config-repo"
config_home="$work/config-home"
mkdir -p "$config_repo/.specs" "$config_repo/.devloop/specs" "$config_home"
config_repo_real="$(cd "$config_repo" && pwd)"
printf '%s\n' "# Default" > "$config_repo/.specs/default.md"
printf '%s\n' "# Devloop" > "$config_repo/.devloop/specs/devloop.md"
config_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$config_specs" ".specs/default.md" "default spec search"
if printf '%s\n' "$config_specs" | grep -Fq ".devloop/specs/devloop.md"; then fail "default spec search included .devloop/specs"; fi
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" ".specs" "spec search label"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_spec_dir "custom-specs")" "custom-specs" "write config spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "custom-specs" "configured spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir)" "custom-specs" "custom spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir_scope)" "local" "custom spec dir scope"
[[ -d "$config_repo/custom-specs" ]] || fail "configured spec dir was not created"
configured_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$configured_specs" ".specs/default.md" "configured spec search includes default dir"
if printf '%s\n' "$configured_specs" | grep -Fq ".devloop/specs/devloop.md"; then fail "configured spec search included .devloop/specs"; fi
equals "$(cd "$config_repo" && HOME="$config_home" generated_spec_path "$spec_output" "" "2026-05-29" false)" "$config_repo_real/custom-specs/2026-05-29-generated.md" "configured generated spec path"
if (cd "$config_repo" && HOME="$config_home" write_config_spec_dir "../bad") >/dev/null 2>&1; then fail "write_config_spec_dir accepted path traversal"; fi

absolute_specs="$work/shared-specs"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_spec_dir "$absolute_specs")" "$absolute_specs" "write absolute config spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "$absolute_specs" "absolute configured spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir)" "$absolute_specs" "absolute custom spec dir"
[[ -d "$absolute_specs" ]] || fail "absolute configured spec dir was not created"
printf '%s\n' "# Shared" > "$absolute_specs/shared.md"
absolute_configured_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$absolute_configured_specs" "$absolute_specs/shared.md" "configured spec search includes absolute dir"
contains "$absolute_configured_specs" ".specs/default.md" "absolute spec search includes default dir"
equals "$(cd "$config_repo" && HOME="$config_home" generated_spec_path "$spec_output" "" "2026-05-29" false)" "$absolute_specs/2026-05-29-generated.md" "absolute generated spec path"
equals "$(spec_dir_status "$absolute_specs")" "exists" "spec dir status exists"
equals "$(spec_dir_status "$work/missing-specs")" "missing" "spec dir status missing"
(cd "$config_repo" && HOME="$config_home" remove_config_spec_dir local)
if (cd "$config_repo" && HOME="$config_home" configured_spec_dir) >/dev/null 2>&1; then fail "custom spec dir was not removed"; fi
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" ".specs" "removed custom spec dir falls back"
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" ".specs" "removed custom spec search label"

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

tilde_repo="$work/tilde-repo"
tilde_home="$work/home"
tilde_input="~"/shared-specs
mkdir -p "$tilde_repo" "$tilde_home"
equals "$(cd "$tilde_repo" && HOME="$tilde_home" write_config_spec_dir "$tilde_input")" "$tilde_home/shared-specs" "tilde input expands when saved"
equals "$(cat "$tilde_repo/.devloop/config")" "spec_dir=$tilde_home/shared-specs" "tilde input saved as absolute path"

raw_tilde_repo="$work/raw-tilde-repo"
mkdir -p "$raw_tilde_repo/.devloop"
printf '%s\n' "spec_dir=~/raw-specs" > "$raw_tilde_repo/.devloop/config"
equals "$(cd "$raw_tilde_repo" && devloop_spec_dir)" ".specs" "raw tilde config falls back"

equals "$(normalize_timeout_minutes 1)" "1" "timeout lower bound"
equals "$(normalize_timeout_minutes 30)" "30" "timeout normalize"
equals "$(normalize_timeout_minutes 1440)" "1440" "timeout upper bound"
if normalize_timeout_minutes 0 >/dev/null 2>&1; then fail "timeout accepted zero"; fi
if normalize_timeout_minutes 1441 >/dev/null 2>&1; then fail "timeout accepted above upper bound"; fi
if normalize_timeout_minutes nope >/dev/null 2>&1; then fail "timeout accepted non-numeric"; fi
equals "$(cd "$config_repo" && HOME="$config_home" devloop_timeout_minutes)" "30" "default timeout"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_timeout_minutes 45)" "45" "write timeout"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_timeout_minutes)" "45" "configured timeout"
(cd "$config_repo" && HOME="$config_home" remove_config_timeout_minutes local)
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
contains "$(devloop_logo)" "v$version" "devloop logo version"
equals "$(ui_color_code accent)" "38;5;141" "accent color"
equals "$(ui_color_code rec)" "38;5;135" "run color"
equals "$(ui_color_code ok)" "38;5;141" "ok color"
equals "$(ui_color_code dim)" "38;5;244" "dim color"
if ! ( ui_choose() { printf '%s\n' "Back"; }; UI_BACK=false; interactive_create_spec >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "create spec back navigation"; fi
if ! ( ui_choose() { printf '%s\n' "Back"; }; UI_BACK=false; interactive_settings >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "settings back navigation"; fi
if ! ( ui_choose() { printf '%s\n' "Back"; }; UI_BACK=false; interactive_run_setup "spec.md" >/dev/null 2>&1; [ "$UI_BACK" = true ] ); then fail "run setup back navigation"; fi

picker_file="$work/picker.txt"
printf '%s\n' "alpha" "beta" > "$picker_file"
old_use_tui="$USE_TUI"
USE_TUI=false
equals "$(ui_pick_from_file "$picker_file" "Pick")" "alpha" "non-tui picker fallback"
USE_TUI="$old_use_tui"

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
  source "$REPO_ROOT/release.sh"
  release_version_valid "0.1.0" || fail "release version rejected valid patch"
  release_version_valid "1.2.3-alpha.1+build.7" || fail "release version rejected valid prerelease"
  if release_version_valid "01.2.3"; then fail "release version accepted leading zero"; fi
  if release_version_valid "1.2"; then fail "release version accepted missing patch"; fi
  if release_version_valid "1.2.3-alpha.01"; then fail "release version accepted leading zero prerelease"; fi
  equals "$(release_tag_for_version "1.2.3")" "v1.2.3" "release tag"
  release_require_command() {
    if [ "$1" = "git-cliff" ]; then return 1; fi
    return 0
  }
  dry_run_output="$(release_main "9.9.9" --dry-run)" || fail "release dry-run required git-cliff"
  contains "$dry_run_output" "would tag: v9.9.9" "release dry-run"
)
ok "release helpers"

bin_dir="$work/bin"
install_home="$work/install-home"
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$REPO_ROOT/install.sh" >/tmp/devloop-install-test.out
[[ -x "$REPO_ROOT/devloop" ]] || fail "devloop is not executable"
[[ -L "$bin_dir/devloop" ]] || fail "installer did not create symlink"
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
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$REPO_ROOT/install.sh" >/tmp/devloop-install-skip.out 2>&1
contains "$(cat /tmp/devloop-install-skip.out)" "skipping modified skill" "installer modified skill guard"
contains "$(cat /tmp/devloop-install-skip.out)" "try: devloop doctor" "installer guidance after skill skip"
contains "$(cat "$install_home/.agents/skills/devloop-review/SKILL.md")" "user edit" "installer modified skill preserved"
DEVLOOP_FORCE=1 DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$REPO_ROOT/install.sh" >/tmp/devloop-install-force.out
if grep -q "user edit" "$install_home/.agents/skills/devloop-review/SKILL.md"; then fail "installer force did not restore skill"; fi
ok "installer skill updates"

fake_bin="$work/fake-bin"
mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/claude"
chmod +x "$fake_bin/codex" "$fake_bin/claude"
doctor_output="$(HOME="$install_home" PATH="$bin_dir:$fake_bin:$PATH" "$bin_dir/devloop" doctor 2>&1)"
contains "$doctor_output" "devloop doctor: ready" "doctor"
contains "$doctor_output" "[ok] skill devloop-spec" "doctor"
contains "$doctor_output" "Optional UI" "doctor"
contains "$doctor_output" "$install_home/.agents/skills/devloop-spec" "doctor Codex skill"
contains "$doctor_output" "$install_home/.claude/skills/devloop-spec" "doctor Claude skill"
ok "doctor"

agent="$work/spec-agent"
cat > "$agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
cat >/tmp/devloop-spec-agent-prompt.txt
printf '%s\n' '---' 'status: draft' 'type: feat' 'created: 2026-05-29' 'pr: null' '---' '' '# Shell migration spec'
AGENT
chmod +x "$agent"

repo="$work/repo"
mkdir -p "$repo/.devloop"
repo_specs="$work/repo-specs"
printf 'spec_dir=%s\n' "$repo_specs" > "$repo/.devloop/config"
(
  cd "$repo"
  "$REPO_ROOT/devloop" spec --agent "$agent" "Keep devloop as Bash." >/tmp/devloop-spec-test.out
)
contains "$(cat /tmp/devloop-spec-test.out)" "spec:" "spec command"
[[ -f "$repo_specs/$(date +%F)-shell-migration-spec.md" ]] || fail "spec command did not write dated spec under absolute configured dir"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Keep devloop as Bash." "spec prompt"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Output path: choose a $repo_specs/" "spec prompt configured output"
ok "spec generation"

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
  if [ -z "$report" ]; then report=".codex/reports/fake.md"; fi
  mkdir -p "$(dirname "$report")"
  printf '%s\n' "# Fake report" "Result: ${DEVLOOP_FAKE_MODE:-accept}" > "$report"
  exit 0
fi
output="$(printf '%s\n' "$prompt" | sed -nE 's/^Output path: (.+)$/\1/p' | head -n 1)"
pass="$(printf '%s\n' "$prompt" | sed -nE 's/^Pass: ([0-9]+).*/\1/p' | head -n 1)"
mode="${DEVLOOP_FAKE_MODE:-accept}"
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

## Acceptance criteria
1. Write the result file.
MARKDOWN
}

run_loop() {
  local repo_path="$1"
  local slug="$2"
  local mode="$3"
  local max="${4:-1}"
  local extra="${5:-}"
  if [ -n "$extra" ]; then
    (
      cd "$repo_path"
      HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" DEVLOOP_FAKE_MODE="$mode" "$REPO_ROOT/devloop" --plain --no-shell "$extra" ".specs/$slug.md" "$max"
    )
  else
    (
      cd "$repo_path"
      HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" DEVLOOP_FAKE_MODE="$mode" "$REPO_ROOT/devloop" --plain --no-shell ".specs/$slug.md" "$max"
    )
  fi
}

loop_repo="$work/loop-accept"
make_loop_repo "$loop_repo" "e2e-accept" "E2E Accept"
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
accept_worktree="$(printf '%s\n' "$accept_output" | sed -nE 's/^worktree:[[:space:]]+//p')"
[[ -f "$accept_worktree/result.txt" ]] || fail "accept loop did not write result"
contains "$(cat "$accept_worktree/.codex/logs/e2e-accept-r1-verify.log")" "verify pass" "verify hook"
contains "$(cd "$loop_repo" && HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" "$REPO_ROOT/devloop" status)" "e2e-accept" "status command"
contains "$(cd "$loop_repo" && HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" "$REPO_ROOT/devloop" clean --dry-run)" "skip:" "clean skips accepted"
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
contains "$no_changes_output" "commit:   none" "no changes loop"
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
contains "$(cd "$loop_repo" && HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" "$REPO_ROOT/devloop" status)" "verify-error" "verify failure status"
clean_output="$(cd "$loop_repo" && HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" "$REPO_ROOT/devloop" clean --dry-run)"
contains "$clean_output" "would remove:" "clean dry run"
(cd "$loop_repo" && HOME="$install_home" PATH="$fake_bin:$bin_dir:$PATH" "$REPO_ROOT/devloop" clean --force >/tmp/devloop-clean-force.out)
contains "$(cat /tmp/devloop-clean-force.out)" "removed:" "clean force"
ok "e2e verify failure and clean"
