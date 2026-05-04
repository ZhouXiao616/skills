#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Installs the default skills in this repository for OpenCode.
#
# OpenCode discovers global skills from ~/.config/opencode/skills by default.
# This script copies each public skill directory there, including bundled
# reference files and helper scripts, and marks those copies so uninstall can
# remove them deterministically later.

MARKER=".mattpocock-skills-opencode"
MANIFEST=".mattpocock-skills-opencode-manifest"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}"
FORCE=0
INCLUDE_MISC=0

usage() {
  cat <<'USAGE'
Usage: install-opencode-skills.sh [--dest DIR] [--include-misc] [--force]

Installs this repo's engineering and productivity skills into OpenCode's global
skills dir. Misc skills are optional.

Options:
  --dest DIR  Install into DIR instead of ~/.config/opencode/skills.
              You can also set OPENCODE_SKILLS_DIR.
  --include-misc
              Also install the misc skills bucket.
  --force     Replace existing unmarked skills with the same names.
  -h, --help  Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)
      if [ "$#" -lt 2 ]; then
        echo "error: --dest requires a directory" >&2
        exit 1
      fi
      DEST="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --include-misc)
      INCLUDE_MISC=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

skill_names=()
skill_sources=()
omitted_names=()
omitted_targets=()
seen_names=" "

is_valid_skill_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

add_skill() {
  local src="$1"
  local name
  local frontmatter_name

  name="$(basename "$src")"

  if ! is_valid_skill_name "$name"; then
    echo "error: invalid OpenCode skill name: $name" >&2
    exit 1
  fi

  frontmatter_name="$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$src/SKILL.md")"
  if [ "$frontmatter_name" != "$name" ]; then
    echo "error: $src/SKILL.md has name '$frontmatter_name', expected '$name'" >&2
    exit 1
  fi

  case "$seen_names" in
    *" $name "*)
      echo "error: duplicate skill name: $name" >&2
      exit 1
      ;;
  esac

  seen_names="$seen_names$name "
  skill_names+=("$name")
  skill_sources+=("$src")
}

selected_buckets=(engineering productivity)

if [ "$INCLUDE_MISC" -eq 1 ]; then
  selected_buckets+=(misc)
fi

for bucket in "${selected_buckets[@]}"; do
  for skill_md in "$REPO/skills/$bucket"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    add_skill "$(dirname "$skill_md")"
  done
done

mkdir -p "$DEST"

if [ -f "$DEST/$MANIFEST" ]; then
  while IFS= read -r installed_name; do
    [ -n "$installed_name" ] || continue

    if ! is_valid_skill_name "$installed_name"; then
      echo "error: invalid skill name in existing manifest: $installed_name" >&2
      exit 1
    fi

    case "$seen_names" in
      *" $installed_name "*) continue ;;
    esac

    old_target="$DEST/$installed_name"

    if [ ! -e "$old_target" ] && [ ! -L "$old_target" ]; then
      continue
    fi

    if [ -d "$old_target" ] && [ ! -L "$old_target" ] && [ -f "$old_target/$MARKER" ]; then
      omitted_names+=("$installed_name")
      omitted_targets+=("$old_target")
      continue
    fi

    echo "skipped omitted skill $installed_name (missing ownership marker)" >&2
  done < "$DEST/$MANIFEST"
fi

for i in "${!skill_names[@]}"; do
  name="${skill_names[$i]}"
  target="$DEST/$name"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    continue
  fi

  if [ -d "$target" ] && [ ! -L "$target" ] && [ -f "$target/$MARKER" ]; then
    continue
  fi

  if [ "$FORCE" -eq 1 ]; then
    continue
  fi

  echo "error: $target already exists and was not installed by this script." >&2
  echo "Re-run with --force to replace it, or choose another --dest." >&2
  exit 1
done

for i in "${!omitted_names[@]}"; do
  rm -rf "${omitted_targets[$i]}"
  echo "removed omitted skill ${omitted_names[$i]}"
done

tmp_manifest="$DEST/$MANIFEST.tmp.$$"
trap 'rm -f "$tmp_manifest"' EXIT
: > "$tmp_manifest"

for i in "${!skill_names[@]}"; do
  name="${skill_names[$i]}"
  src="${skill_sources[$i]}"
  target="$DEST/$name"
  tmp_target="$DEST/.$name.tmp.$$"

  rm -rf "$tmp_target"
  mkdir -p "$tmp_target"
  cp -R "$src/." "$tmp_target/"
  printf 'installed-by: mattpocock-skills-opencode\nsource: %s\n' "$src" > "$tmp_target/$MARKER"
  rm -rf "$target"
  mv "$tmp_target" "$target"
  printf '%s\n' "$name" >> "$tmp_manifest"

  echo "installed $name -> $target"
done

mv "$tmp_manifest" "$DEST/$MANIFEST"
trap - EXIT

echo "installed ${#skill_names[@]} OpenCode skills into $DEST"
