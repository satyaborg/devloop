#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO="${DEVLOOP_GITHUB_REPO:-satyaborg/devloop}"
RELEASE_BASE_URL="${DEVLOOP_RELEASE_BASE_URL:-https://github.com/$GITHUB_REPO/releases/download}"
GITHUB_API_URL="${DEVLOOP_GITHUB_API_URL:-https://api.github.com/repos/$GITHUB_REPO/releases/latest}"
INSTALL_ROOT="${DEVLOOP_INSTALL_DIR:-$HOME/.local/share/devloop}"
BIN_DIR="${DEVLOOP_BIN_DIR:-$HOME/.local/bin}"
VERSION=""
YES=false
NO_SKILLS=false
DRY_RUN=false

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

usage() {
  cat <<'EOF'
usage: install.remote.sh [options]

Primary install:
  curl -fsSL https://devloop.sh/install | bash

Options:
  --yes                 Install missing dependencies without prompting.
  --version <version>   Install a specific tagged version, for example 0.2.0.
  --no-skills           Install only the devloop CLI.
  --dry-run             Print planned actions without changing files.
  --install-dir <dir>   Versioned install root. Default: ~/.local/share/devloop.
  --bin-dir <dir>       Directory for the devloop symlink. Default: ~/.local/bin.
  --release-base-url <url>
                        Release asset base URL. Default: GitHub releases.
  -h, --help            Show this help.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

version_tag() {
  printf 'v%s\n' "$1"
}

asset_name() {
  printf 'devloop-%s.tar.gz\n' "$1"
}

artifact_url() {
  local version="$1"
  printf '%s/%s/%s\n' "$RELEASE_BASE_URL" "$(version_tag "$version")" "$(asset_name "$version")"
}

checksum_url() {
  local version="$1"
  printf '%s.sha256\n' "$(artifact_url "$version")"
}

download_file() {
  local url="$1"
  local dest="$2"
  local source_path

  case "$url" in
    file://*)
      source_path="${url#file://}"
      cp "$source_path" "$dest"
      ;;
    *)
      if ! command -v curl >/dev/null 2>&1; then
        fail "missing curl; install curl or download the release archive manually"
      fi
      curl -fsSL "$url" -o "$dest"
      ;;
  esac
}

checksum_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    fail "missing sha256 tool; install shasum or sha256sum"
  fi
}

resolve_latest_version() {
  local response version source_path
  case "$GITHUB_API_URL" in
    file://*)
      source_path="${GITHUB_API_URL#file://}"
      [ -f "$source_path" ] || fail "missing latest release fixture: $source_path"
      response="$(<"$source_path")"
      ;;
    *)
      if ! command -v curl >/dev/null 2>&1; then
        fail "missing curl; pass --version <version> or install curl"
      fi
      response="$(curl -fsSL "$GITHUB_API_URL")" || fail "failed to resolve latest Devloop release"
      ;;
  esac
  version="$(printf '%s\n' "$response" | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' | head -n 1)"
  if [ -z "$version" ]; then
    fail "latest release response did not include tag_name"
  fi
  printf '%s\n' "$version"
}

normalize_version() {
  local version="$1"
  version="${version#v}"
  if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'; then
    fail "invalid version: $1"
  fi
  printf '%s\n' "$version"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) YES=true ;;
      --no-skills) NO_SKILLS=true ;;
      --dry-run) DRY_RUN=true ;;
      --version)
        [ "$#" -ge 2 ] || fail "--version requires a value"
        VERSION="$2"
        shift
        ;;
      --install-dir)
        [ "$#" -ge 2 ] || fail "--install-dir requires a value"
        INSTALL_ROOT="$2"
        shift
        ;;
      --bin-dir)
        [ "$#" -ge 2 ] || fail "--bin-dir requires a value"
        BIN_DIR="$2"
        shift
        ;;
      --release-base-url)
        [ "$#" -ge 2 ] || fail "--release-base-url requires a value"
        RELEASE_BASE_URL="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        fail "unknown option: $1"
        ;;
      *)
        fail "unexpected argument: $1"
        ;;
    esac
    shift
  done
}

missing_commands() {
  local missing=()
  local command_name
  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    printf '\n'
    return 0
  fi
  printf '%s\n' "${missing[*]}"
}

missing_agent_casks() {
  local missing=()
  if ! command -v codex >/dev/null 2>&1; then
    missing+=(codex)
  fi
  if ! command -v claude >/dev/null 2>&1; then
    missing+=(claude-code)
  fi
  if [ "${#missing[@]}" -eq 0 ]; then
    printf '\n'
    return 0
  fi
  printf '%s\n' "${missing[*]}"
}

print_dependency_status() {
  local tool
  for tool in git glow gum fzf tmux codex claude; do
    if command -v "$tool" >/dev/null 2>&1; then
      info "[ok] $tool: $(command -v "$tool")"
    fi
  done
}

report_required_dependencies() {
  local formula_missing_text="$1"
  local cask_missing_text="$2"

  if [ -z "$formula_missing_text" ] && [ -z "$cask_missing_text" ]; then
    print_dependency_status
    return 0
  fi

  if [ -n "$formula_missing_text" ]; then
    info "missing required dependencies: $formula_missing_text"
    info "install with: brew install $formula_missing_text"
  fi
  if [ -n "$cask_missing_text" ]; then
    info "missing required cask dependencies: $cask_missing_text"
    info "install with: brew install --cask $cask_missing_text"
  fi
}

confirm_dependency_install() {
  local formula_missing_text="$1"
  local cask_missing_text="$2"
  local reply

  if [ "$YES" = true ]; then
    return 0
  fi
  report_required_dependencies "$formula_missing_text" "$cask_missing_text"
  if [ ! -t 0 ]; then
    info "pass --yes to install missing dependencies without a prompt."
    return 1
  fi

  printf 'Install missing dependencies with Homebrew now? [y/N] '
  read -r reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *)
      info "skipping dependency install"
      return 1
      ;;
  esac
}

install_required_dependencies() {
  local formula_missing_text="$1"
  local cask_missing_text="$2"
  local missing_formulas=()
  local missing_casks=()
  local still_missing

  if [ -z "$formula_missing_text" ] && [ -z "$cask_missing_text" ]; then
    print_dependency_status
    return 0
  fi

  if [ -n "$formula_missing_text" ]; then
    read -r -a missing_formulas <<< "$formula_missing_text"
  fi
  if [ -n "$cask_missing_text" ]; then
    read -r -a missing_casks <<< "$cask_missing_text"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    report_required_dependencies "$formula_missing_text" "$cask_missing_text"
    info "install Homebrew, then rerun the installer."
    return 1
  fi
  if ! confirm_dependency_install "$formula_missing_text" "$cask_missing_text"; then
    return 1
  fi

  if [ "${#missing_formulas[@]}" -gt 0 ]; then
    info "installing required dependencies: ${missing_formulas[*]}"
    brew install "${missing_formulas[@]}"
  fi
  if [ "${#missing_casks[@]}" -gt 0 ]; then
    info "installing required cask dependencies: ${missing_casks[*]}"
    brew install --cask "${missing_casks[@]}"
  fi

  still_missing="$(missing_commands git glow gum fzf tmux codex claude)"
  if [ -n "$still_missing" ]; then
    info "still missing required dependencies: $still_missing"
    return 1
  fi
  print_dependency_status
}

print_path_guidance() {
  case ":${PATH:-}:" in
    *":$BIN_DIR:"*) ;;
    *)
      info ""
      info "$BIN_DIR is not on PATH. Add this to your shell profile:"
      info "export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
}

verify_archive() {
  local archive="$1"
  local checksum="$2"
  local expected actual
  expected="$(awk '{print $1; exit}' "$checksum")"
  [ -n "$expected" ] || fail "empty checksum file: $checksum"
  actual="$(checksum_file "$archive")"
  [ "$expected" = "$actual" ] || fail "checksum mismatch for $archive"
  info "verified checksum"
}

find_extracted_root() {
  local extract_dir="$1"
  local found
  found="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -n "$found" ] || fail "release archive did not contain an install directory"
  [ -f "$found/devloop" ] || fail "release archive missing devloop executable"
  [ -f "$found/scripts/skill_helpers.sh" ] || fail "release archive missing scripts/skill_helpers.sh"
  [ -d "$found/skills" ] || fail "release archive missing bundled skills"
  printf '%s\n' "$found"
}

install_archive() {
  local version="$1"
  local archive="$2"
  local target="$INSTALL_ROOT/$version"
  local tmp extract_dir extracted_root

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/devloop-install.XXXXXX")"
  extract_dir="$tmp/extract"
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  extracted_root="$(find_extracted_root "$extract_dir")"

  mkdir -p "$INSTALL_ROOT" "$BIN_DIR"
  rm -rf "$target.tmp"
  cp -R "$extracted_root" "$target.tmp"
  chmod +x "$target.tmp/devloop"
  rm -rf "$target"
  mv "$target.tmp" "$target"
  ln -sfn "$target/devloop" "$BIN_DIR/devloop"
  rm -rf "$tmp"

  info "installed devloop $version -> $target"
  info "linked $BIN_DIR/devloop -> $target/devloop"
}

install_skills() {
  local root="$1"
  if [ "$NO_SKILLS" = true ]; then
    info "skipping skill installation"
    info "devloop doctor will require skill installation before agent loops are ready."
    return 0
  fi

  DEVLOOP_SKILL_INSTALL=copy
  export DEVLOOP_SKILL_INSTALL
  # shellcheck source=/dev/null
  source "$root/scripts/skill_helpers.sh"
  devloop_install_skills "$root"
}

dry_run() {
  local version="$1"
  info "dry run: no files will be changed"
  info "version: $version"
  info "download: $(artifact_url "$version")"
  info "verify: $(checksum_url "$version")"
  info "install: $INSTALL_ROOT/$version"
  info "link: $BIN_DIR/devloop -> $INSTALL_ROOT/$version/devloop"
  if [ "$NO_SKILLS" = true ]; then
    info "skills: skipped"
    info "devloop doctor will require skill installation before agent loops are ready."
  else
    info "skills: $HOME/.agents/skills, $HOME/.claude/skills"
  fi
}

main() {
  local version formula_missing cask_missing tmp archive checksum installed_root dependency_status
  parse_args "$@"

  if [ -z "$VERSION" ]; then
    VERSION="$(resolve_latest_version)"
  fi
  version="$(normalize_version "$VERSION")"
  formula_missing="$(missing_commands git glow gum fzf tmux)"
  cask_missing="$(missing_agent_casks)"

  if [ "$DRY_RUN" = true ]; then
    dry_run "$version"
    report_required_dependencies "$formula_missing" "$cask_missing"
    print_path_guidance
    return 0
  fi

  dependency_status=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/devloop-download.XXXXXX")"
  archive="$tmp/$(asset_name "$version")"
  checksum="$archive.sha256"
  download_file "$(artifact_url "$version")" "$archive"
  download_file "$(checksum_url "$version")" "$checksum"
  verify_archive "$archive" "$checksum"
  install_archive "$version" "$archive"
  rm -rf "$tmp"

  installed_root="$INSTALL_ROOT/$version"
  install_skills "$installed_root"
  install_required_dependencies "$formula_missing" "$cask_missing" || dependency_status=$?
  print_path_guidance
  print_banner "$version"
  return "$dependency_status"
}

main "$@"
