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
INSTALL_ROOT="${DEVLOOP_INSTALL_DIR:-$HOME/.local/share/devloop}"
TARGET="$BIN_DIR/devloop"
DRY_RUN=false
SKILL_STATUS=0

usage() {
  cat <<'EOF'
usage: uninstall.sh [options]

Removes devloop installed by install.sh or the remote installer:
  - the devloop symlink (~/.local/bin/devloop)
  - the staged runtime (~/.local/share/devloop)
  - devloop-managed skills (~/.agents/skills, ~/.claude/skills)

Leaves the source checkout, plus gum/fzf/gh, untouched.

Options:
  --dry-run             Print planned actions without changing files.
  --bin-dir <dir>       Directory holding the devloop symlink. Default: ~/.local/bin.
  --install-dir <dir>   Versioned install root. Default: ~/.local/share/devloop.
  -h, --help            Show this help.

Set DEVLOOP_FORCE=1 to also remove hand-modified skills.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --bin-dir)
      [ "$#" -ge 2 ] || { echo "--bin-dir requires a value" >&2; exit 1; }
      BIN_DIR="$2"
      TARGET="$BIN_DIR/devloop"
      shift
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || { echo "--install-dir requires a value" >&2; exit 1; }
      INSTALL_ROOT="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$DRY_RUN" = true ]; then
  echo "dry run: no files will be changed"
  if [ -L "$TARGET" ]; then
    echo "would remove symlink: $TARGET -> $(readlink "$TARGET")"
  else
    echo "no devloop symlink at: $TARGET"
  fi
  if [ -d "$INSTALL_ROOT" ]; then
    echo "would remove staged runtime: $INSTALL_ROOT"
  else
    echo "no staged runtime at: $INSTALL_ROOT"
  fi
  while IFS= read -r skills_dir; do
    [ -z "$skills_dir" ] && continue
    for source in "$ROOT"/skills/*; do
      [ -d "$source" ] || continue
      dest="$skills_dir/$(basename "$source")"
      if [ -L "$dest" ] || { [ -e "$dest" ] && devloop_can_replace_skill "$dest"; }; then
        echo "would remove skill: $dest"
      elif [ -e "$dest" ]; then
        echo "would skip modified skill: $dest (set DEVLOOP_FORCE=1 to remove)"
      fi
    done
  done <<EOF
$(devloop_skills_dirs)
EOF
  exit 0
fi

if [ -L "$TARGET" ]; then
  rm -f "$TARGET"
  echo "removed symlink $TARGET"
fi

if [ -d "$INSTALL_ROOT" ]; then
  rm -rf "$INSTALL_ROOT"
  echo "removed staged runtime $INSTALL_ROOT"
fi

devloop_uninstall_skills "$ROOT" || SKILL_STATUS=$?

echo "devloop uninstalled"
exit "$SKILL_STATUS"
