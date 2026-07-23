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
RELEASE_ARCHIVE=""
RELEASE_CHECKSUM=""

release_usage() {
  cat <<'EOF'
usage:
  ./scripts/release.sh <patch|minor|major> [--dry-run] [--run-tests]
  ./scripts/release.sh publish [--dry-run] [--run-tests]

Release flow:
  1. Run patch, minor, or major to open a version-bump pull request.
  2. The release pull request merges automatically after required CI passes.
  3. Run publish from main to push the existing version tag.
  4. GitHub Actions builds the assets and creates the GitHub Release.

Examples:
  ./scripts/release.sh patch --dry-run
  ./scripts/release.sh minor
  ./scripts/release.sh publish --dry-run
  ./scripts/release.sh publish
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

release_write_version_files() {
  local version="$1"
  local site_version="$ROOT/site/public/VERSION"
  printf '%s\n' "$version" > "$ROOT/VERSION"
  if [ -d "$(dirname "$site_version")" ]; then
    printf '%s\n' "$version" > "$site_version"
  fi
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

release_assert_remote_ref_missing() {
  local kind="$1"
  local ref="$2"
  local status

  set +e
  git -C "$ROOT" ls-remote --exit-code "--$kind" origin "$ref" >/dev/null 2>&1
  status=$?
  set -e

  case "$status" in
    0)
      printf '%s already exists on origin: %s\n' "$kind" "$ref" >&2
      return 1
      ;;
    2) return 0 ;;
    *)
      printf 'failed to check origin for %s: %s\n' "$kind" "$ref" >&2
      return 1
      ;;
  esac
}

release_assert_tag_available() {
  local tag="$1"
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    printf 'tag already exists: %s\n' "$tag" >&2
    return 1
  fi
  release_assert_remote_ref_missing tags "refs/tags/$tag"
}

release_assert_branch_available() {
  local branch="$1"
  if git -C "$ROOT" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    printf 'branch already exists: %s\n' "$branch" >&2
    return 1
  fi
  release_assert_remote_ref_missing heads "refs/heads/$branch"
}

release_current_branch() {
  git -C "$ROOT" branch --show-current
}

release_assert_main_branch() {
  local branch
  branch="$(release_current_branch)"
  if [ "$branch" = "main" ]; then return 0; fi
  printf 'release requires main branch, on: %s\n' "${branch:-detached HEAD}" >&2
  return 1
}

release_assert_head_matches_origin_main() {
  local head origin_head
  if ! git -C "$ROOT" fetch --quiet origin refs/heads/main; then
    printf '%s\n' "failed to fetch origin/main" >&2
    return 1
  fi
  head="$(git -C "$ROOT" rev-parse HEAD)"
  origin_head="$(git -C "$ROOT" rev-parse FETCH_HEAD)"
  if [ "$head" = "$origin_head" ]; then return 0; fi
  printf '%s\n' "local main must match origin/main before release" >&2
  printf 'local HEAD: %s\n' "$head" >&2
  printf 'origin/main: %s\n' "$origin_head" >&2
  return 1
}

release_assert_version_files() {
  local version="$1"
  local site_version="$ROOT/site/public/VERSION"
  if [ "$(release_current_version)" != "$version" ]; then
    printf 'root VERSION does not match release version: %s\n' "$version" >&2
    return 1
  fi
  if [ ! -f "$site_version" ] || [ "$(sed -n '1p' "$site_version")" != "$version" ]; then
    printf 'site VERSION does not match release version: %s\n' "$version" >&2
    return 1
  fi
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
  mkdir -p "$staging/scripts"
  cp "$ROOT/devloop" "$staging/devloop"
  cp "$ROOT/scripts/install.sh" "$staging/scripts/install.sh"
  cp "$ROOT/scripts/install.remote.sh" "$staging/scripts/install.remote.sh"
  cp "$ROOT/scripts/devloop_test.sh" "$staging/scripts/devloop_test.sh"
  cp "$ROOT/scripts/release.sh" "$staging/scripts/release.sh"
  cp "$ROOT/scripts/skill_helpers.sh" "$staging/scripts/skill_helpers.sh"
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

release_render_changelog() {
  local version="$1"
  local output="$2"
  local tag status
  tag="$(release_tag_for_version "$version")"
  status=0

  git -C "$ROOT" tag -a "$tag" -m "devloop $version" || return $?
  (cd "$ROOT" && git-cliff --config "$ROOT/cliff.toml" --output "$output") || status=$?
  if ! git -C "$ROOT" tag -d "$tag" >/dev/null; then
    printf 'failed to remove temporary tag: %s\n' "$tag" >&2
    return 1
  fi
  return "$status"
}

release_normalize_changelog_date() {
  local version="$1"
  local input="$2"
  local output="$3"
  awk -v version="$version" '
    index($0, "## [" version "](") == 1 {
      sub(/ - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/, " - <release-date>")
    }
    { print }
  ' "$input" > "$output"
}

release_changelog_matches() {
  local version="$1"
  local actual="$2"
  local expected="$3"
  local actual_normalized expected_normalized status

  actual_normalized="$(mktemp "${TMPDIR:-/tmp}/devloop-changelog-actual.XXXXXX")" || return $?
  expected_normalized="$(mktemp "${TMPDIR:-/tmp}/devloop-changelog-expected.XXXXXX")" || {
    status=$?
    rm -f "$actual_normalized"
    return "$status"
  }
  status=0
  release_normalize_changelog_date "$version" "$actual" "$actual_normalized" || status=$?
  if [ "$status" -eq 0 ]; then
    release_normalize_changelog_date "$version" "$expected" "$expected_normalized" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    cmp -s "$actual_normalized" "$expected_normalized" || status=$?
  fi
  rm -f "$actual_normalized" "$expected_normalized"
  return "$status"
}

release_pr_body() {
  local version="$1"
  cat <<EOF
Release pull request for v$version.

After this merges, publish from an updated main branch:

\`\`\`bash
./scripts/release.sh publish
\`\`\`
EOF
}

release_prepare_pr() {
  local bump="$1"
  local dry_run="$2"
  local run_tests="$3"
  local current version tag branch title pr_url

  current="$(release_current_version)"
  version="$(release_next_version "$bump" "$current")" || return $?
  tag="$(release_tag_for_version "$version")"
  branch="chore/release-$tag"
  title="chore: release $version"

  if [ "$dry_run" = true ]; then
    printf 'current: %s\n' "$current"
    printf 'next: %s (%s)\n' "$version" "$tag"
    printf '%s\n' "would require clean main matching origin/main"
    printf 'would create branch: %s\n' "$branch"
    printf '%s\n' "would update VERSION, site/public/VERSION, and CHANGELOG.md"
    if [ "$run_tests" = true ]; then
      printf '%s\n' "would run bash scripts/devloop_test.sh"
    else
      printf '%s\n' "would skip local tests; pull request CI remains authoritative"
    fi
    printf 'would commit: %s\n' "$title"
    printf 'would open pull request: %s\n' "$title"
    printf '%s\n' "would enable auto-merge after required CI passes"
    return 0
  fi

  release_require_command git || return $?
  release_require_command git-cliff || return $?
  release_require_command gh || return $?
  release_assert_main_branch || return $?
  release_assert_head_matches_origin_main || return $?
  release_assert_clean_tree || return $?
  release_assert_branch_available "$branch" || return $?
  release_assert_tag_available "$tag" || return $?

  git -C "$ROOT" switch -c "$branch" || return $?
  release_write_version_files "$version" || return $?
  git -C "$ROOT" add VERSION site/public/VERSION || return $?
  git -C "$ROOT" commit -m "$title" || return $?
  release_render_changelog "$version" "$ROOT/CHANGELOG.md" || return $?
  git -C "$ROOT" add CHANGELOG.md || return $?
  git -C "$ROOT" commit --amend --no-edit || return $?

  if [ "$run_tests" = true ]; then
    bash "$ROOT/scripts/devloop_test.sh" || return $?
  else
    printf '%s\n' "skip local tests; pull request CI remains authoritative"
  fi

  git -C "$ROOT" push -u origin "$branch" || return $?
  pr_url="$(gh pr create --base main --head "$branch" --title "$title" --body "$(release_pr_body "$version")")" || return $?
  printf '%s\n' "$pr_url"
  gh pr merge "$pr_url" --auto --merge || return $?
  printf 'enabled auto-merge for %s after required CI passes\n' "$tag"
}

release_publish() {
  local dry_run="$1"
  local run_tests="$2"
  local version tag expected_changelog status

  version="$(release_current_version)"
  if ! release_version_valid "$version"; then
    printf 'invalid current VERSION: %s\n' "$version" >&2
    return 2
  fi
  tag="$(release_tag_for_version "$version")"

  if [ "$dry_run" = true ]; then
    printf 'version: %s\n' "$version"
    printf 'tag: %s\n' "$tag"
    printf '%s\n' "would require clean main matching origin/main"
    printf '%s\n' "would require matching VERSION and site/public/VERSION"
    printf '%s\n' "would require CHANGELOG.md to match current main"
    if [ "$run_tests" = true ]; then
      printf '%s\n' "would run bash scripts/devloop_test.sh"
    else
      printf '%s\n' "would skip local tests; tag workflow runs the release gates"
    fi
    printf 'would create and push tag: %s\n' "$tag"
    printf '%s\n' "tag workflow would build assets and create the GitHub Release"
    return 0
  fi

  release_require_command git || return $?
  release_require_command git-cliff || return $?
  release_require_command awk || return $?
  release_require_command cmp || return $?
  release_assert_main_branch || return $?
  release_assert_head_matches_origin_main || return $?
  release_assert_clean_tree || return $?
  release_assert_version_files "$version" || return $?
  release_assert_tag_available "$tag" || return $?

  expected_changelog="$(mktemp "${TMPDIR:-/tmp}/devloop-changelog.XXXXXX")" || return $?
  release_render_changelog "$version" "$expected_changelog" || {
    status=$?
    rm -f "$expected_changelog"
    return "$status"
  }
  if ! release_changelog_matches "$version" "$ROOT/CHANGELOG.md" "$expected_changelog"; then
    rm -f "$expected_changelog"
    printf 'CHANGELOG.md does not match %s at current main\n' "$tag" >&2
    printf '%s\n' "refresh CHANGELOG.md in a release pull request, merge it, then retry publish" >&2
    return 1
  fi
  rm -f "$expected_changelog"

  if [ "$run_tests" = true ]; then
    bash "$ROOT/scripts/devloop_test.sh" || return $?
  else
    printf '%s\n' "skip local tests; tag workflow runs the release gates"
  fi

  git -C "$ROOT" tag -a "$tag" -m "devloop $version" || return $?
  if git -C "$ROOT" push origin "$tag"; then
    :
  else
    status=$?
    if ! git -C "$ROOT" tag -d "$tag" >/dev/null; then
      printf 'failed to remove local tag after push failure: %s\n' "$tag" >&2
    fi
    return "$status"
  fi
  printf 'published %s\n' "$tag"
  printf '%s\n' "GitHub Actions will build assets and create the GitHub Release."
}

release_main() {
  local action=""
  local dry_run=false
  local run_tests=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --run-tests) run_tests=true ;;
      -h|--help) release_usage; return 0 ;;
      --*)
        printf 'unknown option: %s\n' "$1" >&2
        release_usage >&2
        return 2
        ;;
      *)
        if [ -n "$action" ]; then
          release_usage >&2
          return 2
        fi
        action="$1"
        ;;
    esac
    shift
  done

  case "$action" in
    patch|minor|major) release_prepare_pr "$action" "$dry_run" "$run_tests" ;;
    publish) release_publish "$dry_run" "$run_tests" ;;
    "")
      release_usage >&2
      return 2
      ;;
    *)
      printf 'invalid action: %s\n' "$action" >&2
      release_usage >&2
      return 2
      ;;
  esac
}

if [ "${DEVLOOP_RELEASE_LIB:-}" != "1" ]; then
  release_main "$@"
fi
