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
contains "$help" "--create-pr" "help"
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

spec_output=$'preface\n---\nstatus: draft\n---\n\n# Generated'
equals "$(extract_generated_spec "$spec_output")" $'---\nstatus: draft\n---\n\n# Generated' "extract_generated_spec"

session_output=$'unrelated 11111111-1111-4111-8111-111111111111\nTo continue this session, run codex exec resume 22222222-2222-4222-8222-222222222222'
equals "$(extract_session_id "$session_output")" "22222222-2222-4222-8222-222222222222" "extract_session_id uses session marker"

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
skills_dir="$work/skills"
DEVLOOP_BIN_DIR="$bin_dir" DEVLOOP_SKILLS_DIR="$skills_dir" "$ROOT/install.sh" >/tmp/devloop-install-test.out
[[ -x "$ROOT/devloop" ]] || fail "devloop is not executable"
[[ -L "$bin_dir/devloop" ]] || fail "installer did not create symlink"
[[ -f "$skills_dir/devloop-spec/SKILL.md" ]] || fail "installer did not install spec skill"
[[ -f "$skills_dir/devloop-spec/references/spec-template.md" ]] || fail "installer did not install spec template reference"
[[ -f "$skills_dir/devloop-review/SKILL.md" ]] || fail "installer did not install review skill"
[[ -f "$skills_dir/devloop-review/.devloop-checksum" ]] || fail "installer did not write checksum"
"$bin_dir/devloop" --help >/tmp/devloop-help-test.out
contains "$(cat /tmp/devloop-help-test.out)" "Spec-driven code and review loop." "installed help"
ok "installer"

printf '%s\n' "user edit" >> "$skills_dir/devloop-review/SKILL.md"
DEVLOOP_BIN_DIR="$bin_dir" DEVLOOP_SKILLS_DIR="$skills_dir" "$ROOT/install.sh" >/tmp/devloop-install-skip.out 2>&1
contains "$(cat /tmp/devloop-install-skip.out)" "skipping modified skill" "installer modified skill guard"
contains "$(cat /tmp/devloop-install-skip.out)" "try: devloop doctor" "installer guidance after skill skip"
contains "$(cat "$skills_dir/devloop-review/SKILL.md")" "user edit" "installer modified skill preserved"
DEVLOOP_FORCE=1 DEVLOOP_BIN_DIR="$bin_dir" DEVLOOP_SKILLS_DIR="$skills_dir" "$ROOT/install.sh" >/tmp/devloop-install-force.out
if grep -q "user edit" "$skills_dir/devloop-review/SKILL.md"; then fail "installer force did not restore skill"; fi
ok "installer skill updates"

fake_bin="$work/fake-bin"
mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/claude"
chmod +x "$fake_bin/codex" "$fake_bin/claude"
doctor_output="$(DEVLOOP_SKILLS_DIR="$skills_dir" PATH="$bin_dir:$fake_bin:$PATH" "$bin_dir/devloop" doctor 2>&1)"
contains "$doctor_output" "devloop doctor: ready" "doctor"
contains "$doctor_output" "[ok] skill devloop-spec" "doctor"
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
mkdir -p "$repo"
(
  cd "$repo"
  "$ROOT/devloop" spec --agent "$agent" "Keep devloop as Bash." >/tmp/devloop-spec-test.out
)
contains "$(cat /tmp/devloop-spec-test.out)" "spec:" "spec command"
[[ -f "$repo/.specs/$(date +%F)-shell-migration-spec.md" ]] || fail "spec command did not write dated spec"
contains "$(cat /tmp/devloop-spec-agent-prompt.txt)" "Keep devloop as Bash." "spec prompt"
ok "spec generation"
