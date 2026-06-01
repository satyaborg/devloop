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
RELEASE_ARCHIVE=""
RELEASE_CHECKSUM=""

release_usage() {
  cat <<'EOF'
usage: ./release.sh <patch|minor|major> [--dry-run] [--publish] [--push]

Bumps VERSION, creates a release commit, and creates an annotated tag.
Use --publish to push the commit and tag, then create a GitHub Release.

Examples:
  ./release.sh patch --dry-run
  ./release.sh minor --publish
  ./release.sh major --push
EOF
}

release_version_valid() {
  local version="$1"
  printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'
}

release_tag_for_version() {
  printf 'v%s\n' "$1"
}

release_current_version() {
  sed -n '1p' "$ROOT/VERSION" 2>/dev/null || true
}

release_next_version() {
  local bump="$1"
  local current="$2"
  local major minor patch

  if ! release_version_valid "$current"; then
    printf 'invalid current VERSION: %s\n' "$current" >&2
    return 2
  fi

  case "$current" in
    *-*|*+*)
      printf 'cannot bump prerelease/build VERSION: %s\n' "$current" >&2
      return 2
      ;;
  esac

  IFS=. read -r major minor patch <<EOF
$current
EOF
  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      printf 'unknown bump: %s\n' "$bump" >&2
      return 2
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

release_require_command() {
  local command="$1"
  if command -v "$command" >/dev/null 2>&1; then return 0; fi
  printf 'missing required command: %s\n' "$command" >&2
  return 1
}

release_assert_clean_tree() {
  if [ -z "$(git -C "$ROOT" status --porcelain)" ]; then return 0; fi
  printf '%s\n' "working tree must be clean before release" >&2
  return 1
}

release_assert_tag_available() {
  local tag="$1"
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    printf 'tag already exists: %s\n' "$tag" >&2
    return 1
  fi
}

release_current_branch() {
  git -C "$ROOT" branch --show-current
}

release_checksum_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    printf '%s\n' "missing shasum or sha256sum" >&2
    return 1
  fi
}

release_create_artifacts() {
  local version="$1"
  local out_dir="$2"
  local name="devloop-$version"
  local staging="$out_dir/$name"

  rm -rf "$staging"
  mkdir -p "$staging"
  cp "$ROOT/devloop" "$staging/devloop"
  cp "$ROOT/install.sh" "$staging/install.sh"
  cp "$ROOT/install.remote.sh" "$staging/install.remote.sh"
  cp "$ROOT/skill_helpers.sh" "$staging/skill_helpers.sh"
  cp "$ROOT/README.md" "$staging/README.md"
  cp "$ROOT/LICENSE" "$staging/LICENSE"
  cp "$ROOT/CHANGELOG.md" "$staging/CHANGELOG.md"
  cp "$ROOT/VERSION" "$staging/VERSION"
  cp -R "$ROOT/skills" "$staging/skills"

  RELEASE_ARCHIVE="$out_dir/$name.tar.gz"
  RELEASE_CHECKSUM="$RELEASE_ARCHIVE.sha256"
  tar -C "$out_dir" -czf "$RELEASE_ARCHIVE" "$name"
  printf '%s  %s\n' "$(release_checksum_file "$RELEASE_ARCHIVE")" "$name.tar.gz" > "$RELEASE_CHECKSUM"
  rm -rf "$staging"
}

release_assert_push_branch() {
  local branch
  branch="$(release_current_branch)"
  if [ -z "$branch" ]; then
    printf '%s\n' "refusing to push release from detached HEAD" >&2
    return 1
  fi
  if [ "$branch" = "main" ] || [ "${DEVLOOP_RELEASE_ALLOW_BRANCH:-0}" = "1" ]; then return 0; fi
  printf 'refusing to push release from branch: %s\n' "$branch" >&2
  printf '%s\n' "checkout main, or set DEVLOOP_RELEASE_ALLOW_BRANCH=1" >&2
  return 1
}

release_main() {
  local bump=""
  local current version
  local dry_run=false
  local publish=false
  local push=false
  local tag branch
  local artifact_dir

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --publish) publish=true ;;
      --push) push=true ;;
      -h|--help) release_usage; return 0 ;;
      --*)
        printf 'unknown option: %s\n' "$1" >&2
        release_usage >&2
        return 2
        ;;
      *)
        if [ -n "$bump" ]; then
          release_usage >&2
          return 2
        fi
        bump="$1"
        ;;
    esac
    shift
  done

  case "$bump" in
    patch|minor|major) ;;
    "")
      release_usage >&2
      return 2
      ;;
    *)
      printf 'invalid bump: %s\n' "$bump" >&2
      release_usage >&2
      return 2
      ;;
  esac

  current="$(release_current_version)"
  version="$(release_next_version "$bump" "$current")" || return $?
  if [ -z "$version" ]; then
    release_usage >&2
    return 2
  fi
  if ! release_version_valid "$version"; then
    printf 'invalid SemVer version: %s\n' "$version" >&2
    return 2
  fi

  tag="$(release_tag_for_version "$version")"
  release_require_command git
  if [ "$dry_run" = true ]; then
    release_assert_tag_available "$tag"
    printf 'current: %s\n' "$current"
    printf 'next: %s (%s)\n' "$version" "$tag"
    if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
      printf '%s\n' "note: actual release requires a clean working tree"
    fi
    printf '%s\n' "would run bash tests/devloop_test.sh"
    printf '%s\n' "would update VERSION and CHANGELOG.md"
    printf 'would commit: chore: release %s\n' "$version"
    printf 'would tag: %s\n' "$tag"
    if [ "$publish" = true ] || [ "$push" = true ]; then printf '%s\n' "would push branch and tag"; fi
    if [ "$publish" = true ]; then
      printf 'would build release assets: devloop-%s.tar.gz and devloop-%s.tar.gz.sha256\n' "$version" "$version"
      printf 'would create GitHub release: gh release create %s --verify-tag --generate-notes devloop-%s.tar.gz devloop-%s.tar.gz.sha256\n' "$tag" "$version" "$version"
    fi
    return 0
  fi

  release_require_command git-cliff
  if [ "$publish" = true ]; then release_require_command gh; fi
  release_assert_tag_available "$tag"
  release_assert_clean_tree
  if [ "$publish" = true ] || [ "$push" = true ]; then release_assert_push_branch; fi

  bash "$ROOT/tests/devloop_test.sh"
  printf '%s\n' "$version" > "$ROOT/VERSION"
  git-cliff --config "$ROOT/cliff.toml" --workdir "$ROOT" --tag "$tag" --output "$ROOT/CHANGELOG.md"
  git -C "$ROOT" add VERSION CHANGELOG.md
  git -C "$ROOT" commit -m "chore: release $version"
  git -C "$ROOT" tag -a "$tag" -m "devloop $version"

  if [ "$publish" = true ] || [ "$push" = true ]; then
    branch="$(release_current_branch)"
    git -C "$ROOT" push origin "$branch"
    git -C "$ROOT" push origin "$tag"
  fi

  if [ "$publish" = true ]; then
    artifact_dir="$(mktemp -d "${TMPDIR:-/tmp}/devloop-release.XXXXXX")"
    release_create_artifacts "$version" "$artifact_dir"
    gh release create "$tag" --verify-tag --generate-notes "$RELEASE_ARCHIVE" "$RELEASE_CHECKSUM"
    rm -rf "$artifact_dir"
  fi

  printf 'released %s\n' "$tag"
}

if [ "${DEVLOOP_RELEASE_LIB:-}" != "1" ]; then
  release_main "$@"
fi
