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

ROOT="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
BIN_DIR="${DEVLOOP_BIN_DIR:-$HOME/.local/bin}"
TARGET="$BIN_DIR/devloop"
SOURCE="$ROOT/devloop"

if [ ! -f "$SOURCE" ]; then
  echo "missing devloop executable: $SOURCE" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
chmod +x "$SOURCE"
ln -sfn "$SOURCE" "$TARGET"

echo "installed devloop -> $SOURCE"

case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on PATH. Add this to your shell profile:"
    echo "export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

echo
echo "try: devloop --help"
