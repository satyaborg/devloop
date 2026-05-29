#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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

bash -n "$ROOT/devloop" "$ROOT/install.sh" "$ROOT/skill_helpers.sh"
ok "bash syntax"

DEVLOOP_LIB=1
source "$ROOT/devloop"
unset DEVLOOP_LIB
equals "${CODEX_MODEL_ARGS[*]}" "-m gpt-5.5" "codex model args"
equals "${CLAUDE_MODEL_ARGS[*]}" "--model claude-opus-4-8" "claude model args"

help="$("$ROOT/devloop" --help)"
contains "$help" "Common commands:" "help"
contains "$help" "devloop doctor" "help"
contains "$help" "devloop reports" "help"
contains "$help" "--create-pr" "help"
contains "$help" "--no-shell" "help"
contains "$help" "--enter-worktree" "help"
ok "help output"

skill_path="$("$ROOT/devloop" spec --skill-path)"
[[ "$skill_path" == "$ROOT/skills/devloop-spec/SKILL.md" ]] || fail "unexpected skill path: $skill_path"
contains "$("$ROOT/devloop" spec --print-skill)" "name: devloop-spec" "spec skill"
ok "spec skill path"

for skill in "$ROOT"/skills/*/SKILL.md; do
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
contains "$review_prompt_text" "Bundled skill path, for fallback only: $ROOT/skills/devloop-review/SKILL.md" "review prompt"
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

spec_output=$'preface\n---\nstatus: draft\n---\n\n# Generated'
equals "$(extract_generated_spec "$spec_output")" $'---\nstatus: draft\n---\n\n# Generated' "extract_generated_spec"

config_repo="$work/config-repo"
config_home="$work/config-home"
mkdir -p "$config_repo/.specs" "$config_repo/.devloop/specs" "$config_home"
config_repo_real="$(cd "$config_repo" && pwd)"
printf '%s\n' "# Legacy" > "$config_repo/.specs/legacy.md"
printf '%s\n' "# Devloop" > "$config_repo/.devloop/specs/devloop.md"
config_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$config_specs" ".specs/legacy.md" "default spec search"
contains "$config_specs" ".devloop/specs/devloop.md" "default spec search"
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" ".specs, .devloop/specs" "spec search label"
equals "$(cd "$config_repo" && HOME="$config_home" write_config_spec_dir "custom-specs")" "custom-specs" "write config spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" "custom-specs" "configured spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir)" "custom-specs" "custom spec dir"
equals "$(cd "$config_repo" && HOME="$config_home" configured_spec_dir_scope)" "local" "custom spec dir scope"
[[ -d "$config_repo/custom-specs" ]] || fail "configured spec dir was not created"
configured_specs="$(cd "$config_repo" && HOME="$config_home" list_spec_files)"
contains "$configured_specs" ".specs/legacy.md" "configured spec search includes legacy dir"
contains "$configured_specs" ".devloop/specs/devloop.md" "configured spec search includes devloop dir"
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
contains "$absolute_configured_specs" ".specs/legacy.md" "absolute spec search includes legacy dir"
equals "$(cd "$config_repo" && HOME="$config_home" generated_spec_path "$spec_output" "" "2026-05-29" false)" "$absolute_specs/2026-05-29-generated.md" "absolute generated spec path"
equals "$(spec_dir_status "$absolute_specs")" "exists" "spec dir status exists"
equals "$(spec_dir_status "$work/missing-specs")" "missing" "spec dir status missing"
(cd "$config_repo" && HOME="$config_home" remove_config_spec_dir local)
if (cd "$config_repo" && HOME="$config_home" configured_spec_dir) >/dev/null 2>&1; then fail "custom spec dir was not removed"; fi
equals "$(cd "$config_repo" && HOME="$config_home" devloop_spec_dir)" ".specs" "removed custom spec dir falls back"
equals "$(cd "$config_repo" && HOME="$config_home" spec_search_label)" ".specs, .devloop/specs" "removed custom spec search label"

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
mkdir -p "$tilde_repo" "$tilde_home"
equals "$(cd "$tilde_repo" && HOME="$tilde_home" write_config_spec_dir "~/shared-specs")" "$tilde_home/shared-specs" "tilde input expands when saved"
equals "$(cat "$tilde_repo/.devloop/config")" "spec_dir=$tilde_home/shared-specs" "tilde input saved as absolute path"

raw_tilde_repo="$work/raw-tilde-repo"
mkdir -p "$raw_tilde_repo/.devloop"
printf '%s\n' "spec_dir=~/raw-specs" > "$raw_tilde_repo/.devloop/config"
equals "$(cd "$raw_tilde_repo" && devloop_spec_dir)" ".specs" "raw tilde config falls back"

session_output=$'unrelated 11111111-1111-4111-8111-111111111111\nTo continue this session, run codex exec resume 22222222-2222-4222-8222-222222222222'
equals "$(extract_session_id "$session_output")" "22222222-2222-4222-8222-222222222222" "extract_session_id uses session marker"

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

bin_dir="$work/bin"
install_home="$work/install-home"
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$ROOT/install.sh" >/tmp/devloop-install-test.out
[[ -x "$ROOT/devloop" ]] || fail "devloop is not executable"
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
DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$ROOT/install.sh" >/tmp/devloop-install-skip.out 2>&1
contains "$(cat /tmp/devloop-install-skip.out)" "skipping modified skill" "installer modified skill guard"
contains "$(cat /tmp/devloop-install-skip.out)" "try: devloop doctor" "installer guidance after skill skip"
contains "$(cat "$install_home/.agents/skills/devloop-review/SKILL.md")" "user edit" "installer modified skill preserved"
DEVLOOP_FORCE=1 DEVLOOP_BIN_DIR="$bin_dir" HOME="$install_home" "$ROOT/install.sh" >/tmp/devloop-install-force.out
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
  "$ROOT/devloop" spec --agent "$agent" "Keep devloop as Bash." >/tmp/devloop-spec-test.out
)
contains "$(cat /tmp/devloop-spec-test.out)" "spec:" "spec command"
[[ -f "$repo_specs/$(date +%F)-shell-migration-spec.md" ]] || fail "spec command did not write dated spec under absolute configured dir"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Keep devloop as Bash." "spec prompt"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Output path: choose a $repo_specs/" "spec prompt configured output"
ok "spec generation"
