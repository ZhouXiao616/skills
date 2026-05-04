#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Removes OpenCode skills installed by scripts/install-opencode-skills.sh.

MARKER=".mattpocock-skills-opencode"
MANIFEST=".mattpocock-skills-opencode-manifest"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}"
FORCE=0

usage() {
  cat <<'USAGE'
Usage: uninstall-opencode-skills.sh [--dest DIR] [--force]

Uninstalls skills previously installed by install-opencode-skills.sh.

Options:
  --dest DIR  Remove from DIR instead of ~/.config/opencode/skills.
              You can also set OPENCODE_SKILLS_DIR.
  --force     Remove matching skill names even if the ownership marker is absent.
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
seen_names=" "

is_valid_skill_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

add_name() {
  local name="$1"

  [ -n "$name" ] || return 0

  if ! is_valid_skill_name "$name"; then
    echo "error: invalid skill name in uninstall list: $name" >&2
    exit 1
  fi

  case "$seen_names" in
    *" $name "*) return 0 ;;
  esac

  seen_names="$seen_names$name "
  skill_names+=("$name")
}

if [ -f "$DEST/$MANIFEST" ]; then
  while IFS= read -r name; do
    add_name "$name"
  done < "$DEST/$MANIFEST"
else
  for bucket in engineering productivity misc; do
    for skill_md in "$REPO/skills/$bucket"/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      add_name "$(basename "$(dirname "$skill_md")")"
    done
  done
fi

skipped_unowned=0

for name in "${skill_names[@]}"; do
  target="$DEST/$name"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    echo "skipped $name (not installed)"
    continue
  fi

  if [ -d "$target" ] && [ ! -L "$target" ] && [ -f "$target/$MARKER" ]; then
    rm -rf "$target"
    echo "removed $name"
    continue
  fi

  if [ "$FORCE" -eq 1 ]; then
    rm -rf "$target"
    echo "removed $name"
    continue
  fi

  skipped_unowned=1
  echo "skipped $name (missing ownership marker; use --force to remove)" >&2
done

if [ "$skipped_unowned" -eq 1 ]; then
  echo "left $DEST/$MANIFEST in place because uninstall was incomplete" >&2
  exit 1
fi

rm -f "$DEST/$MANIFEST"

echo "uninstalled OpenCode skills from $DEST"
