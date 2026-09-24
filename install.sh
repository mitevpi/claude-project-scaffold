#!/usr/bin/env bash
# install.sh — copy this scaffold into a target repository.
#
# Usage:
#   ./install.sh <target-repo>            install the FULL CLAUDE.md variant
#   ./install.sh --light <target-repo>    install the light CLAUDE.md variant
#   ./install.sh --force <target-repo>    overwrite files that already exist
#   ./install.sh --update <target-repo>   bring an earlier install up to date
#
# It installs the scaffold's committed HEAD, never its working tree, so a
# stray local file such as a .DS_Store never reaches a target. It records the
# commit in <target>/.claude/scaffold-version.
#
# --update reads that record. For each file under .claude/agents, hooks,
# scripts, and skills, it adds a file that is new, refreshes a file that the
# project never changed, and keeps a file that the project customised, and
# names it. A file the project deleted stays deleted. A file that upstream
# deleted is removed, unless the project customised it. The settings merge
# works the same way: it adds a rule only when it is new upstream, and it
# drops a rule or hook command that upstream dropped. It never touches
# CLAUDE.md or README.md. It tells you when their templates changed
# upstream, and how to see the change.
#
# The target must be a git repository with no uncommitted changes. That makes
# the install one reviewable diff: "git diff" shows it, and "git restore ."
# plus "git clean" undo it. It is also what makes --force safe, because every
# file it overwrites is still in git.
#
# What it copies:
#   CLAUDE-template.md   -> <target>/CLAUDE.md
#   README-template.md   -> <target>/README.md
#   settings.json        -> <target>/.claude/settings.json, merged into an
#                           existing file rather than skipped (see below)
#   agents/  hooks/  scripts/  skills/  -> <target>/.claude/
#   docs/                -> <target>/docs/
#   and it appends the Claude and Superpowers block to <target>/.gitignore
#
# It never overwrites an existing file unless you pass --force. It reports
# every file it skipped, so nothing goes missing quietly.
#
# settings.json is the exception. It is never skipped and never overwritten.
# The scaffold's permission rules and hooks are merged into an existing file,
# and every rule already there is kept. A skipped settings.json would leave the
# hooks on disk but never registered, which is worse than no hooks at all.

set -euo pipefail

SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

variant="full"
variant_set=0
force=0
update=0
target=""

while [ $# -gt 0 ]; do
  case "$1" in
    --light)  variant="light"; variant_set=1; shift ;;
    --full)   variant="full";  variant_set=1; shift ;;
    --force)  force=1; shift ;;
    --update) update=1; shift ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
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
  echo "usage: ./install.sh [--light] [--force | --update] <target-repo>" >&2
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

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "$TARGET is not a git repository. Run 'git init' there first." >&2
  exit 2
fi

if [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
  echo "$TARGET has uncommitted changes. Commit or stash them first, so that" >&2
  echo "the install is one diff you can review and undo." >&2
  git -C "$TARGET" status --short >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to merge .claude/settings.json." >&2
  exit 2
fi

if [ "$force" -eq 1 ] && [ "$update" -eq 1 ]; then
  echo "--force and --update do not mix. --update already refreshes every file" >&2
  echo "that the project did not customise." >&2
  exit 2
fi

# --- Source: the scaffold's committed HEAD --------------------------------------
if git -C "$SCAFFOLD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  new_commit=$(git -C "$SCAFFOLD" rev-parse HEAD)
  SRC=$(mktemp -d)
  trap 'rm -rf "$SRC"' EXIT
  git -C "$SCAFFOLD" archive HEAD | tar -x -C "$SRC"
  if [ -n "$(git -C "$SCAFFOLD" status --porcelain)" ]; then
    echo "note: the scaffold has uncommitted changes. They are not installed."
    echo "      Installing commit ${new_commit:0:10}."
    echo
  fi
else
  new_commit="unversioned"
  SRC=$SCAFFOLD
  echo "note: the scaffold is not a git checkout. Installing its files as they are,"
  echo "      and --update will treat every changed file as customised."
  echo
fi

VERSION_FILE="$TARGET/.claude/scaffold-version"
old_commit=""
if [ "$update" -eq 1 ]; then
  if [ ! -f "$VERSION_FILE" ]; then
    echo "$TARGET has no .claude/scaffold-version, so there is no install to update." >&2
    echo "Run install.sh without --update." >&2
    exit 2
  fi
  old_commit=$(awk '$1 == "commit" { print $2 }' "$VERSION_FILE")
  if [ "$variant_set" -eq 0 ]; then
    variant=$(awk '$1 == "variant" { print $2 }' "$VERSION_FILE")
    [ -n "$variant" ] || variant="full"
  fi
  if ! git -C "$SCAFFOLD" cat-file -e "$old_commit^{commit}" 2>/dev/null; then
    echo "note: this scaffold checkout does not hold the installed commit $old_commit."
    echo "      Every file that differs is treated as customised and kept."
    echo
    old_commit=""
  fi
fi

copied=0
skipped=0
refreshed=0
removed=0
customised=""

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

# update_file SOURCE DEST SCAFFOLD_PATH
# For --update. Adds a new file, refreshes a file that still matches the
# installed version, and keeps a file that the project changed.
update_file() {
  src="$1"
  dest="$2"
  rel="$3"
  if [ ! -e "$dest" ]; then
    if [ -n "$old_commit" ] && git -C "$SCAFFOLD" cat-file -e "$old_commit:$rel" 2>/dev/null; then
      # The installed commit had this file, so the project deleted it.
      printf '  gone  %s (deleted in this project, so not restored)\n' "${dest#"$TARGET"/}"
    else
      copy_file "$src" "$dest"
    fi
  elif cmp -s "$src" "$dest"; then
    return 0
  elif [ -n "$old_commit" ] && git -C "$SCAFFOLD" show "$old_commit:$rel" 2>/dev/null | cmp -s - "$dest"; then
    cp "$src" "$dest"
    printf '  update %s\n' "${dest#"$TARGET"/}"
    refreshed=$((refreshed + 1))
  else
    printf '  keep  %s (customised in this project)\n' "${dest#"$TARGET"/}"
    customised="$customised ${dest#"$TARGET"/}"
  fi
}

# merge_settings SOURCE DEST [OLD]
# Adds every scaffold permission rule and hook that DEST lacks. Keeps
# everything DEST already has, in its order. With OLD, the scaffold settings
# of the installed commit, it skips what the project removed and drops what
# upstream dropped. Writes nothing when nothing changes, so a second install
# leaves the file byte-identical.
merge_settings() {
  src="$1"
  dest="$2"
  if [ ! -e "$dest" ]; then
    copy_file "$src" "$dest"
    return 0
  fi
  if ! result=$(python3 "$SRC/dev/merge-settings.py" "$src" "$dest" ${3:+"$3"}); then
    echo "  FAIL  .claude/settings.json could not be merged: $result" >&2
    exit 1
  fi
  n_added=${result% *}
  n_removed=${result#* }
  if [ "$result" = "0 0" ]; then
    echo "  keep  .claude/settings.json (it already holds every scaffold rule and hook)"
  else
    echo "  merge .claude/settings.json (added $n_added, removed $n_removed rule(s), hook(s), or key(s))"
  fi
}

case "$variant" in
  full)  manual_name="CLAUDE-template.md" ;;
  light) manual_name="CLAUDE-light.md" ;;
  *) echo "unknown variant in $VERSION_FILE: $variant" >&2; exit 2 ;;
esac
manual="$SRC/$manual_name"
[ -f "$manual" ] || { echo "missing: $manual" >&2; exit 1; }

if [ "$update" -eq 1 ]; then
  echo "Updating the $variant install in $TARGET to scaffold commit ${new_commit:0:10}"
  echo
  old_settings=""
  if [ -n "$old_commit" ]; then
    old_settings="$SRC/.installed-settings.json"
    git -C "$SCAFFOLD" show "$old_commit:settings.json" > "$old_settings" 2>/dev/null || : > "$old_settings"
  fi
  merge_settings "$SRC/settings.json" "$TARGET/.claude/settings.json" "$old_settings"
  for dir in agents hooks scripts skills; do
    [ -d "$SRC/$dir" ] || continue
    while IFS= read -r -d '' file; do
      rel="${file#"$SRC"/}"
      update_file "$file" "$TARGET/.claude/$rel" "$rel"
    done < <(find "$SRC/$dir" -type f -print0)
  done
  # A file that upstream deleted leaves the project too, unless the project
  # customised it. --no-renames reports a rename as a delete and an add.
  if [ -n "$old_commit" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      dest="$TARGET/.claude/$rel"
      [ -e "$dest" ] || continue
      if git -C "$SCAFFOLD" show "$old_commit:$rel" 2>/dev/null | cmp -s - "$dest"; then
        rm -f "$dest"
        rmdir "$(dirname "$dest")" 2>/dev/null || true
        printf '  remove %s (deleted upstream)\n' "${dest#"$TARGET"/}"
        removed=$((removed + 1))
      else
        printf '  keep  %s (deleted upstream, but customised in this project)\n' "${dest#"$TARGET"/}"
        customised="$customised ${dest#"$TARGET"/}"
      fi
    done < <(git -C "$SCAFFOLD" diff --no-renames --name-only --diff-filter=D "$old_commit" "$new_commit" -- agents hooks scripts skills)
  fi
  # docs/ is project content once installed. Add only what is missing.
  copy_tree "$SRC/docs" "$TARGET/docs" >/dev/null
else
  echo "Installing the $variant variant into $TARGET"
  echo
  copy_file "$manual" "$TARGET/CLAUDE.md"
  copy_file "$SRC/README-template.md" "$TARGET/README.md"
  merge_settings "$SRC/settings.json" "$TARGET/.claude/settings.json"
  for dir in agents hooks scripts skills; do
    copy_tree "$SRC/$dir" "$TARGET/.claude/$dir"
  done
  copy_tree "$SRC/docs" "$TARGET/docs"
fi

# The version record is what makes a later --update possible.
mkdir -p "$TARGET/.claude"
printf '# Written by claude-scaffold install.sh. install.sh --update reads it.\ncommit %s\nvariant %s\n' \
  "$new_commit" "$variant" > "$VERSION_FILE"

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
# Isolated workspaces: .worktrees/ and worktrees/ from
# superpowers:using-git-worktrees, and .claude/worktrees/ from Claude Code's own
# worktree option. An unignored worktree directory commits a whole second
# checkout into the repository. The leading slash anchors each entry at the
# repository root, so a source directory named worktrees/ stays tracked.
/.worktrees/
/worktrees/
/.claude/worktrees/

# The subagent-driven-development workspace: task briefs, implementer reports,
# review packages, and the progress ledger. Scratch, not history.
.superpowers/

# Local, per-machine Claude Code settings. .claude/settings.json is shared and
# tracked; this one is not.
/.claude/settings.local.json

# OS and editor noise
.DS_Store
Thumbs.db
IGNORE
  echo "  edit  .gitignore (appended the Claude and Superpowers block)"
fi

# An older install has the block but may lack a newer entry. Ask git whether
# each load-bearing path is ignored, and append the entry for any that is not.
for pair in "/.worktrees/ .worktrees/probe" \
            "/worktrees/ worktrees/probe" \
            "/.claude/worktrees/ .claude/worktrees/probe" \
            ".superpowers/ .superpowers/probe" \
            "/.claude/settings.local.json .claude/settings.local.json"; do
  entry=${pair%% *}
  probe=${pair#* }
  if ! git -C "$TARGET" check-ignore -q "$probe"; then
    printf '%s\n' "$entry" >> "$GITIGNORE"
    echo "  edit  .gitignore (added the missing entry $entry)"
  fi
done

# --- Report ------------------------------------------------------------------
echo
if [ "$update" -eq 1 ]; then
  echo "Added $copied file(s), refreshed $refreshed, removed $removed."
  if [ -n "$customised" ]; then
    echo
    echo "Kept these customised files. Compare each one with the scaffold by hand:"
    for f in $customised; do
      rel=${f#.claude/}
      if [ -n "$old_commit" ]; then
        echo "  $f:  git -C $SCAFFOLD diff ${old_commit:0:10} ${new_commit:0:10} -- $rel"
      else
        echo "  $f:  diff $SCAFFOLD/$rel $TARGET/$f"
      fi
    done
  fi
  # The manual and the README are project documents after install. Report a
  # template change, and never apply it.
  if [ -n "$old_commit" ]; then
    for tmpl in "$manual_name" README-template.md; do
      if [ -n "$(git -C "$SCAFFOLD" diff --name-only "$old_commit" "$new_commit" -- "$tmpl")" ]; then
        echo
        echo "$tmpl changed upstream. Port what applies into this project by hand:"
        echo "  git -C $SCAFFOLD diff ${old_commit:0:10} ${new_commit:0:10} -- $tmpl"
      fi
    done
  fi
  echo
  echo "Review the result with git diff, run .claude/scripts/check-claude-md.sh, and commit."
  exit 0
fi
echo "Copied $copied file(s), skipped $skipped."
echo
cat <<NEXT
Next:

  1. Fill every {{PLACEHOLDER}} in CLAUDE.md and README.md, then delete the
     TEMPLATE USAGE comment block from each. An unfilled placeholder is worse
     than a missing section: it teaches the agent to guess.
  2. Run the check:  .claude/scripts/check-claude-md.sh
     It also confirms that settings.json registers both hooks.
  3. Commit the result. CLAUDE.md and .claude/ are shared, tracked files.
NEXT

if [ "$skipped" -gt 0 ]; then
  echo
  echo "Some files already existed and were left alone. Re-run with --force to"
  echo "overwrite them, or merge the differences by hand."
fi
