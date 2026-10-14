#!/usr/bin/env bash
# wave-status.sh: show every worktree's work against a base, and every file
# that more than one worktree changes.
#
# Usage:
#   .claude/scripts/wave-status.sh [<base>] [-C <repo>]
#   .claude/scripts/wave-status.sh --overlaps [<base>] [-C <repo>]
#
# For each worktree it prints the branch, the commits ahead of and behind
# <base>, the count of uncommitted changes, and the files it touches: the
# committed changes since its merge base with <base>, plus its uncommitted
# changes. The worktree that has <base> checked out contributes only its
# uncommitted changes. Then it lists every file that two or more worktrees
# touch.
#
# --overlaps prints only the overlap lines, and nothing when there is none.
# The session-start hook uses it, so that a new parallel session sees which
# files another session or agent is already changing.
#
# <base> defaults to the branch checked out in the main worktree.
#
# Why it exists: a parallel wave and parallel sessions fail at the landing,
# when two branches turn out to change one file. This script shows the
# collision while every branch is still unlanded, so the orchestrator can
# merge the two tasks, reorder them, or land the smaller one first. It reads
# state and changes nothing.
#
# Exit codes: 0 printed. 1 the base did not resolve. 2 usage error.

set -uo pipefail

base=""
repo="."
overlaps_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    -C)
      [ $# -ge 2 ] || { echo "-C needs a repository path" >&2; exit 2; }
      repo=$2; shift 2 ;;
    --overlaps) overlaps_only=1; shift ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      [ -z "$base" ] || { echo "too many arguments" >&2; exit 2; }
      base=$1; shift ;;
  esac
done

g() { git -C "$repo" "$@"; }

g rev-parse --git-dir >/dev/null 2>&1 || { echo "$repo is not a git repository" >&2; exit 2; }

# The porcelain list gives each path on its own line, so a path with a space
# in it stays whole. Each record becomes "path<TAB>ref", and the main
# worktree comes first.
worktrees=$(g worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10); ref = "" }
  /^branch / { ref = substr($0, 8); sub("^refs/heads/", "", ref) }
  /^detached/ { ref = "" }
  /^$/ { if (path != "") print path "\t" ref; path = "" }
  END { if (path != "") print path "\t" ref }')

if [ -z "$base" ]; then
  base=$(printf '%s\n' "$worktrees" | head -1 | cut -f2)
  [ -n "$base" ] || base=HEAD
fi
base_sha=$(g rev-parse --verify -q "$base^{commit}") || { echo "unknown base: $base" >&2; exit 1; }

# An explicit template under $TMPDIR: on macOS a bare mktemp ignores TMPDIR
# and writes to /var/folders, which Claude Code's sandbox denies.
touched=$(mktemp "${TMPDIR:-/tmp}/wave-status.XXXXXX") || { echo "could not create a temporary file" >&2; exit 2; }
trap 'rm -f "$touched"' EXIT
report=""

# porcelain_paths DIR: the uncommitted paths in DIR, one per line. A rename
# reports its destination.
porcelain_paths() {
  git -C "$1" status --porcelain 2>/dev/null | cut -c4- | sed 's/^.* -> //; s/^"\(.*\)"$/\1/'
}

while IFS="$(printf '\t')" read -r path ref; do
  [ -n "$path" ] && [ -d "$path" ] || continue
  label=${ref:-"(detached) $path"}
  dirty=$(porcelain_paths "$path")
  n_dirty=0
  [ -n "$dirty" ] && n_dirty=$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')
  if [ "$ref" = "$base" ]; then
    committed=""
    summary="the base checkout, uncommitted $n_dirty"
  else
    head=$(git -C "$path" rev-parse -q --verify HEAD 2>/dev/null) || continue
    counts=$(g rev-list --left-right --count "$base_sha...$head" 2>/dev/null)
    behind=${counts%%[[:space:]]*}
    ahead=${counts##*[[:space:]]}
    committed=$(g diff --name-only "$base_sha...$head" 2>/dev/null)
    summary="ahead ${ahead:-?}, behind ${behind:-?}, uncommitted $n_dirty"
  fi
  files=$(printf '%s\n%s\n' "$committed" "$dirty" | sed '/^$/d' | sort -u)
  [ -n "$files" ] && printf '%s\n' "$files" | awk -v l="$label" '{ print $0 "\t" l }' >> "$touched"
  n_files=0
  [ -n "$files" ] && n_files=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
  report="$report  $label  $path
    $summary
"
  if [ "$n_files" -gt 0 ]; then
    # Cap the list, so that a wide branch cannot flood the output.
    shown=$(printf '%s\n' "$files" | head -15 | tr '\n' ' ' | sed 's/ $//')
    more=""
    [ "$n_files" -gt 15 ] && more=" ... and $((n_files - 15)) more"
    report="$report    files: $shown$more
"
  fi
done <<EOF
$worktrees
EOF

overlaps=$(sort -u "$touched" | awk -F '\t' '
  { n[$1]++; who[$1] = (who[$1] == "" ? $2 : who[$1] ", " $2) }
  END { for (f in n) if (n[f] > 1) print f ": " who[f] }' | sort)

if [ "$overlaps_only" -eq 1 ]; then
  [ -n "$overlaps" ] && printf '%s\n' "$overlaps"
  exit 0
fi

echo "Wave status against $base ($(g rev-parse --short "$base_sha"))"
echo
printf '%s' "$report"
echo
if [ -n "$overlaps" ]; then
  echo "Overlaps: these files are changed in more than one worktree."
  printf '%s\n' "$overlaps" | sed 's/^/  /'
else
  echo "No overlaps: no file is changed in more than one worktree."
fi
exit 0
