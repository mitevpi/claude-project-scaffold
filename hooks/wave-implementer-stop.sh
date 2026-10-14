#!/bin/sh
# wave-implementer-stop.sh
#
# SubagentStop hook for the wave-implementer agent. When the agent tries to
# finish while its worktree holds uncommitted changes, the hook sends it back
# once, with the list of changes, to commit them or to report why not.
#
# Why this exists: the orchestrator lands only committed work, and
# land-branch.sh refuses a worktree that holds uncommitted changes. An
# implementer that reports success and leaves its work uncommitted stalls the
# landing, and the orchestrator must then decide what to do with files it did
# not write. "Commit your work" in the agent file is a written rule. This hook
# makes it mechanical.
#
# What it checks:
#   1. The agent type is wave-implementer. settings.json registers the hook
#      with that matcher, and the hook checks the field again.
#   2. stop_hook_active is false. The hook sends the agent back once. When the
#      agent stops again, it lets it go, so a change that cannot be committed
#      never traps the agent in a loop. Its report must then say why.
#   3. The cwd field names a linked worktree, not a main checkout. Claude Code
#      sets cwd to the subagent's own worktree for an agent with
#      "isolation: worktree". A main checkout can hold another session's
#      work, which this agent must not commit, so the hook says nothing there.
#
# Exit codes: 0 lets the agent stop. 2 sends it back, with stderr as its next
# instruction. Every error exits 0: a broken hook must never trap an agent.

payload=$(cat)
command -v python3 >/dev/null 2>&1 || exit 0

fields=$(HOOK_PAYLOAD=$payload python3 -c '
import json, os
d = json.loads(os.environ["HOOK_PAYLOAD"])
print(d.get("agent_type") or "")
print("1" if d.get("stop_hook_active") else "0")
print(d.get("cwd") or "")
' 2>/dev/null) || exit 0

agent_type=$(printf '%s\n' "$fields" | sed -n 1p)
active=$(printf '%s\n' "$fields" | sed -n 2p)
cwd=$(printf '%s\n' "$fields" | sed -n 3p)

[ "$agent_type" = "wave-implementer" ] || exit 0
[ "$active" = "0" ] || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
git_dir=$(cd "$top" && cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P) || exit 0
common_dir=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || exit 0
[ "$git_dir" != "$common_dir" ] || exit 0

changes=$(git -C "$top" status --porcelain 2>/dev/null)
[ -n "$changes" ] || exit 0

count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
{
  echo "Do not finish yet. Your worktree $top holds $count uncommitted change(s):"
  printf '%s\n' "$changes" | head -20 | sed 's/^/    /'
  [ "$count" -gt 20 ] && echo "    ... and $((count - 20)) more"
  echo
  echo "The orchestrator lands only committed work, and land-branch.sh refuses a"
  echo "worktree with uncommitted changes."
  echo
  echo "- Finished work inside your write scope: run the tests, stage each path"
  echo "  by name, and commit."
  echo "- A scratch file you made: delete it."
  echo "- A change you did not make: do not touch it. Name it in your report."
  echo "- Work you cannot commit, for example because a test fails: stop, and"
  echo "  say so first in your report."
} >&2
exit 2
