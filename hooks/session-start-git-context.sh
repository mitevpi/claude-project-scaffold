#!/bin/sh
# session-start-git-context.sh
#
# SessionStart hook. It prints the git state of the checkout, and Claude Code
# adds that text to the new session's context.
#
# Why this exists: the most likely way to lose work is two sessions in one
# checkout. The desktop app, a second terminal, and "claude -p" each start a
# main session, and the subagent git hook does not limit a main session. A
# session that finds uncommitted work tends to treat it as its own: it stashes
# it, restores it, or commits it. This hook tells the session, before its
# first turn, that the work was already there.
#
# It reads state and changes nothing. It is silent outside a git repository,
# and it always exits 0, so it can never stop a session from starting.
#
# SessionStart also fires on a resume and after a compaction. The changes are
# then most likely the session's own, so the hook lists them without the
# warning that another session may own them. It reads "source" from the
# payload on stdin.

source=""
if [ ! -t 0 ]; then
  source=$(cat | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')
fi

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$dir" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

top=$(git rev-parse --show-toplevel 2>/dev/null)
branch=$(git branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch="(detached at $(git rev-parse --short HEAD 2>/dev/null))"

echo "Git state at session start:"
echo "- Checkout: $top"
echo "- Branch: $branch"

# Cap the list, so that a huge change set cannot flood the context.
changes=$(git status --porcelain 2>/dev/null)
if [ -n "$changes" ]; then
  count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
  case "$source" in
    resume|compact)
      echo "- This checkout holds $count uncommitted change(s), probably your own from earlier in this session:" ;;
    *)
      echo "- WARNING: this checkout holds $count uncommitted change(s):" ;;
  esac
  printf '%s\n' "$changes" | head -20 | sed 's/^/    /'
  [ "$count" -gt 20 ] && echo "    ... and $((count - 20)) more"
  case "$source" in
    resume|compact)
      echo "  Check any change you do not recognise with the user before you touch it." ;;
    *)
      echo "  Unless you made them earlier in this session, another session may own them."
      echo "  Do not stash, restore, reset, or commit work you did not make. Report it to"
      echo "  the user and ask before you change anything in this checkout." ;;
  esac
fi

# The porcelain form gives each path on its own line, so a path with a space
# in it stays whole.
others=$(git worktree list --porcelain 2>/dev/null | awk -v top="$top" '
  /^worktree / { path = substr($0, 10) }
  /^branch / { ref = substr($0, 8); sub("^refs/heads/", "", ref) }
  /^detached/ { ref = "(detached)" }
  /^$/ { if (path != "" && path != top) print path "  [" ref "]"; path = ""; ref = "" }
  END { if (path != "" && path != top) print path "  [" ref "]" }')
if [ -n "$others" ]; then
  echo "- Other worktrees of this repository. Other sessions or agents may be working in them:"
  printf '%s\n' "$others" | head -20 | sed 's/^/    /'
fi

exit 0
