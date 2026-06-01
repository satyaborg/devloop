#!/usr/bin/env bash

devloop_skills_dirs() {
  printf '%s\n' "$HOME/.agents/skills"
  printf '%s\n' "$HOME/.claude/skills"
}

devloop_checksum_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    cksum "$file" | awk '{print $1}'
  fi
}

devloop_skill_tree_checksum() {
  local root="$1"
  local manifest checksum
  if [ ! -d "$root" ]; then return 1; fi
  manifest="$(mktemp "${TMPDIR:-/tmp}/devloop-skill-manifest.XXXXXX")"
  (
    cd "$root" || exit 1
    find . -type f ! -name ".devloop-checksum" | LC_ALL=C sort | while IFS= read -r file; do
      printf '%s  %s\n' "$(devloop_checksum_file "$file")" "${file#./}"
    done
  ) > "$manifest" || {
    rm -f "$manifest"
    return 1
  }
  checksum="$(devloop_checksum_file "$manifest")"
  rm -f "$manifest"
  printf '%s\n' "$checksum"
}

devloop_skill_name() {
  sed -n 's/^name: *//p' "$1" | head -n 1
}

devloop_valid_skill_name() {
  printf '%s\n' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

devloop_can_replace_skill() {
  local dest="$1"
  local force="${DEVLOOP_FORCE:-0}"
  local marker recorded current
  if [ "$force" = "1" ]; then return 0; fi
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then return 0; fi
  if [ -L "$dest" ]; then return 1; fi

  marker="$dest/.devloop-checksum"
  if [ ! -f "$marker" ]; then return 1; fi
  recorded="$(cat "$marker")"
  current="$(devloop_skill_tree_checksum "$dest")" || return 1
  [ "$recorded" = "$current" ]
}

devloop_install_skills() {
  local root="$1"
  local skills_dir mode status
  mode="${DEVLOOP_SKILL_INSTALL:-copy}"
  status=0

  case "$mode" in
    copy|link) ;;
    *)
      printf 'unknown DEVLOOP_SKILL_INSTALL: %s\n' "$mode" >&2
      return 2
      ;;
  esac

  while IFS= read -r skills_dir; do
    if [ -z "$skills_dir" ]; then continue; fi
    devloop_install_skills_to_dir "$root" "$skills_dir" "$mode" || status=1
  done <<EOF
$(devloop_skills_dirs)
EOF

  return "$status"
}

devloop_install_skills_to_dir() {
  local root="$1"
  local skills_dir="$2"
  local mode="$3"
  local source name dest checksum status
  status=0

  if ! mkdir -p "$skills_dir"; then
    printf 'failed to create skills directory: %s\n' "$skills_dir" >&2
    return 1
  fi
  for source in "$root"/skills/*; do
    if [ ! -d "$source" ]; then continue; fi
    name="$(basename "$source")"
    dest="$skills_dir/$name"
    checksum="$(devloop_skill_tree_checksum "$source")" || {
      printf 'failed to checksum bundled skill: %s\n' "$source" >&2
      status=1
      continue
    }

    if ! devloop_can_replace_skill "$dest"; then
      printf 'skipping modified skill: %s (set DEVLOOP_FORCE=1 to overwrite)\n' "$dest" >&2
      continue
    fi

    if ! rm -rf "$dest"; then
      printf 'failed to replace skill: %s\n' "$dest" >&2
      status=1
      continue
    fi

    if [ "$mode" = "link" ]; then
      if ! ln -s "$source" "$dest"; then
        printf 'failed to link skill: %s\n' "$dest" >&2
        status=1
        continue
      fi
      printf 'installed skill %s -> %s\n' "$name" "$source"
    else
      if ! mkdir -p "$dest"; then
        printf 'failed to create skill directory: %s\n' "$dest" >&2
        status=1
        continue
      fi
      if ! cp -R "$source/." "$dest/"; then
        printf 'failed to copy skill: %s\n' "$dest" >&2
        status=1
        continue
      fi
      if ! printf '%s\n' "$checksum" > "$dest/.devloop-checksum"; then
        printf 'failed to write skill checksum: %s\n' "$dest/.devloop-checksum" >&2
        status=1
        continue
      fi
      printf 'installed skill %s -> %s\n' "$name" "$dest"
    fi
  done

  return "$status"
}

devloop_doctor_command() {
  local command="$1"
  local resolved
  resolved="$(command -v "$command" 2>/dev/null || true)"
  if [ -n "$resolved" ]; then
    printf '[ok] %s: %s\n' "$command" "$resolved"
    return 0
  fi
  printf '[fail] missing command: %s\n' "$command" >&2
  return 1
}

devloop_doctor_skills() {
  local root="$1"
  local skills_dir status
  status=0

  while IFS= read -r skills_dir; do
    if [ -z "$skills_dir" ]; then continue; fi
    devloop_doctor_skills_in_dir "$root" "$skills_dir" || status=1
  done <<EOF
$(devloop_skills_dirs)
EOF

  return "$status"
}

devloop_doctor_skills_in_dir() {
  local root="$1"
  local skills_dir="$2"
  local source name dest declared bundled installed status
  status=0

  for source in "$root"/skills/*; do
    if [ ! -d "$source" ]; then continue; fi
    name="$(basename "$source")"
    dest="$skills_dir/$name"

    if [ ! -f "$dest/SKILL.md" ]; then
      printf '[fail] missing skill: %s\n' "$dest/SKILL.md" >&2
      status=1
      continue
    fi

    declared="$(devloop_skill_name "$dest/SKILL.md")"
    if [ "$declared" != "$name" ]; then
      printf '[fail] skill name mismatch: %s declares %s\n' "$dest/SKILL.md" "$declared" >&2
      status=1
      continue
    fi

    if ! devloop_valid_skill_name "$declared"; then
      printf '[fail] invalid skill name: %s\n' "$declared" >&2
      status=1
      continue
    fi

    bundled="$(devloop_skill_tree_checksum "$source")" || {
      printf '[fail] failed to checksum bundled skill: %s\n' "$source" >&2
      status=1
      continue
    }
    installed="$(devloop_skill_tree_checksum "$dest")" || {
      printf '[fail] failed to checksum installed skill: %s\n' "$dest" >&2
      status=1
      continue
    }

    if [ "$bundled" != "$installed" ]; then
      printf '[fail] stale skill: %s (run ./scripts/install.sh)\n' "$dest" >&2
      status=1
      continue
    fi

    printf '[ok] skill %s: %s\n' "$name" "$dest"
  done

  return "$status"
}

devloop_doctor() {
  local root="$1"
  local status=0

  printf 'devloop doctor\n'
  printf 'Required dependencies\n'
  devloop_doctor_command devloop || status=1
  devloop_doctor_command git || status=1
  devloop_doctor_command codex || status=1
  devloop_doctor_command claude || status=1
  devloop_doctor_command gum || status=1
  devloop_doctor_command fzf || status=1
  printf '\nSkills\n'
  devloop_doctor_skills "$root" || status=1

  if [ "$status" -eq 0 ]; then
    printf 'devloop doctor: ready\n'
  else
    printf 'devloop doctor: not ready\n' >&2
  fi
  return "$status"
}
