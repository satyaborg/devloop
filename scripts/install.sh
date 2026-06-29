#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
  SCRIPT_TARGET="$(readlink "$SCRIPT_PATH")"
  case "$SCRIPT_TARGET" in
    /*) SCRIPT_PATH="$SCRIPT_TARGET" ;;
    *) SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_TARGET" ;;
  esac
done

SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
source "$ROOT/scripts/skill_helpers.sh"

BIN_DIR="${DEVLOOP_BIN_DIR:-$HOME/.local/bin}"
TARGET="$BIN_DIR/devloop"
SOURCE="$ROOT/devloop"
SKILL_STATUS=0
TOOL_STATUS=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_ACCENT=$'\033[38;5;141m'
  C_DIM=$'\033[38;5;244m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_ACCENT=""
  C_DIM=""
  C_BOLD=""
  C_RESET=""
fi

print_banner() {
  local version="$1"
  printf '\n%s' "$C_ACCENT"
  cat <<'EOF'
░█▀▄░█▀▀░█░█░█░░░█▀█░█▀█░█▀█
░█░█░█▀▀░▀▄▀░█░░░█░█░█░█░█▀▀
░▀▀░░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀░▀░░
EOF
  printf '%s\n' "$C_RESET"
  printf '  %sdevloop %s installed%s\n' "$C_DIM" "$version" "$C_RESET"
  printf '  %stry:%s %s%sdevloop%s\n\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$C_ACCENT" "$C_RESET"
}

install_required_ui_tools() {
  local missing=()
  local tool

  for tool in glow gum fzf; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "required UI tools ready"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "missing required UI tools: ${missing[*]}" >&2
    echo "install Homebrew, then rerun ./scripts/install.sh" >&2
    return 1
  fi

  echo "installing required UI tools: ${missing[*]}"
  brew install "${missing[@]}"

  for tool in "${missing[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "failed to install required UI tool: $tool" >&2
      return 1
    fi
  done
}

if [ ! -f "$SOURCE" ]; then
  echo "missing devloop executable: $SOURCE" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
chmod +x "$SOURCE"
ln -sfn "$SOURCE" "$TARGET"

echo "installed devloop -> $SOURCE"
install_required_ui_tools || TOOL_STATUS=$?
devloop_install_skills "$ROOT" || SKILL_STATUS=$?
echo "optional for PR-backed loops: install GitHub CLI and run gh auth login"

case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on PATH. Add this to your shell profile:"
    echo "export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

print_banner "$(cat "$ROOT/VERSION" 2>/dev/null)"
if [ "$TOOL_STATUS" -ne 0 ] || [ "$SKILL_STATUS" -ne 0 ]; then
  exit 1
fi
exit 0
