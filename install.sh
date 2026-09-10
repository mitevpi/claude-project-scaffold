#!/usr/bin/env bash
# install.sh — copy this scaffold into a target repository.
#
# Usage:
#   ./install.sh <target-repo>            install the FULL CLAUDE.md variant
#   ./install.sh --light <target-repo>    install the light CLAUDE.md variant
#   ./install.sh --force <target-repo>    overwrite files that already exist
#
# What it copies:
#   CLAUDE-template.md   -> <target>/CLAUDE.md
#   README-template.md   -> <target>/README.md
#   settings.json        -> <target>/.claude/settings.json
#   agents/  hooks/  scripts/  skills/  -> <target>/.claude/
#   docs/                -> <target>/docs/
#   and it appends the Claude and Superpowers block to <target>/.gitignore
#
# It never overwrites an existing file unless you pass --force. It reports
# every file it skipped, so nothing goes missing quietly.

set -euo pipefail

SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

variant="full"
force=0
target=""

while [ $# -gt 0 ]; do
  case "$1" in
    --light) variant="light"; shift ;;
    --full)  variant="full";  shift ;;
    --force) force=1; shift ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ -n "$target" ]; then
        echo "install.sh takes one target directory" >&2
        exit 2
      fi
      target="$1"
      shift
      ;;
  esac
done

if [ -z "$target" ]; then
  echo "usage: ./install.sh [--light] [--force] <target-repo>" >&2
  exit 2
fi

if [ ! -d "$target" ]; then
  echo "no such directory: $target" >&2
  exit 2
fi

TARGET="$(cd "$target" && pwd)"

if [ "$TARGET" = "$SCAFFOLD" ]; then
  echo "the target is the scaffold itself. Pick another directory." >&2
  exit 2
fi

copied=0
skipped=0

# copy_file SOURCE DEST
copy_file() {
  src="$1"
  dest="$2"
  if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
    printf '  skip  %s (already exists)\n' "${dest#"$TARGET"/}"
    skipped=$((skipped + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  printf '  copy  %s\n' "${dest#"$TARGET"/}"
  copied=$((copied + 1))
}

# copy_tree SOURCE_DIR DEST_DIR
copy_tree() {
  src_dir="$1"
  dest_dir="$2"
  [ -d "$src_dir" ] || return 0
  # -print0 and read -d keep a path with a space in it intact.
  while IFS= read -r -d '' file; do
    rel="${file#"$src_dir"/}"
    copy_file "$file" "$dest_dir/$rel"
  done < <(find "$src_dir" -type f -print0)
}

echo "Installing the $variant variant into $TARGET"
echo

case "$variant" in
  full)  manual="$SCAFFOLD/CLAUDE-template.md" ;;
  light) manual="$SCAFFOLD/CLAUDE-light.md" ;;
esac

[ -f "$manual" ] || { echo "missing: $manual" >&2; exit 1; }

copy_file "$manual" "$TARGET/CLAUDE.md"
copy_file "$SCAFFOLD/README-template.md" "$TARGET/README.md"
copy_file "$SCAFFOLD/settings.json" "$TARGET/.claude/settings.json"

for dir in agents hooks scripts skills; do
  copy_tree "$SCAFFOLD/$dir" "$TARGET/.claude/$dir"
done

copy_tree "$SCAFFOLD/docs" "$TARGET/docs"

# The hooks and scripts must stay executable through the copy.
find "$TARGET/.claude/hooks" "$TARGET/.claude/scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

# --- .gitignore --------------------------------------------------------------
# Two of these entries are load-bearing. An unignored .worktrees/ commits a
# whole second checkout into the repository. An unignored .superpowers/ commits
# the subagent-driven-development ledger and every review package with it.
echo
GITIGNORE="$TARGET/.gitignore"
MARKER="# --- Claude Code and Superpowers ---"

if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE"; then
  echo "  keep  .gitignore (the Claude block is already present)"
else
  [ -f "$GITIGNORE" ] && printf '\n' >> "$GITIGNORE"
  cat >> "$GITIGNORE" <<'IGNORE'
# --- Claude Code and Superpowers ---
# Isolated workspaces created by superpowers:using-git-worktrees. An unignored
# worktree directory commits a whole second checkout into the repository.
.worktrees/
worktrees/

# The subagent-driven-development workspace: task briefs, implementer reports,
# review packages, and the progress ledger. Scratch, not history.
.superpowers/

# Local, per-machine Claude Code settings. .claude/settings.json is shared and
# tracked; this one is not.
.claude/settings.local.json

# OS and editor noise
.DS_Store
Thumbs.db
IGNORE
  echo "  edit  .gitignore (appended the Claude and Superpowers block)"
fi

# --- Report ------------------------------------------------------------------
echo
echo "Copied $copied file(s), skipped $skipped."
echo
cat <<NEXT
Next:

  1. Fill every {{PLACEHOLDER}} in CLAUDE.md and README.md, then delete the
     TEMPLATE USAGE comment block from each. An unfilled placeholder is worse
     than a missing section: it teaches the agent to guess.
  2. Run the check:  .claude/scripts/check-claude-md.sh
  3. Commit the result. CLAUDE.md and .claude/ are shared, tracked files.
NEXT

if [ "$skipped" -gt 0 ]; then
  echo
  echo "Some files already existed and were left alone. Re-run with --force to"
  echo "overwrite them, or merge the differences by hand."
fi
