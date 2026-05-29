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

bash -n "$ROOT/devloop" "$ROOT/install.sh"
ok "bash syntax"

help="$("$ROOT/devloop" --help)"
contains "$help" "Common commands:" "help"
contains "$help" "--create-pr" "help"
ok "help output"

skill_path="$("$ROOT/devloop" spec --skill-path)"
[[ "$skill_path" == "$ROOT/skills/spec/SKILL.md" ]] || fail "unexpected skill path: $skill_path"
ok "spec skill path"

work=$(mktemp -d "${TMPDIR:-/tmp}/devloop-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

bin_dir="$work/bin"
DEVLOOP_BIN_DIR="$bin_dir" "$ROOT/install.sh" >/tmp/devloop-install-test.out
[[ -x "$ROOT/devloop" ]] || fail "devloop is not executable"
[[ -L "$bin_dir/devloop" ]] || fail "installer did not create symlink"
"$bin_dir/devloop" --help >/tmp/devloop-help-test.out
contains "$(cat /tmp/devloop-help-test.out)" "Spec-driven code and review loop." "installed help"
ok "installer"

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
