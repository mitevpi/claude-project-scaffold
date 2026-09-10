#!/usr/bin/env bash
# check-claude-md.sh — confirm that this project's CLAUDE.md setup is complete.
#
# Run it after you fill in CLAUDE.md, and again whenever you edit it.
#
# Usage:
#   .claude/scripts/check-claude-md.sh              check the repo it sits in
#   .claude/scripts/check-claude-md.sh <repo-dir>   check another repo
#
# It resolves the repository root in this order: the argument, then
# $CLAUDE_PROJECT_DIR, then two levels up from this script.
#
# Exit codes: 0 all checks pass. 1 at least one check failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ge 1 ]; then
  ROOT="$(cd "$1" 2>/dev/null && pwd)" || { echo "no such directory: $1" >&2; exit 1; }
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  ROOT="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd)" || { echo "CLAUDE_PROJECT_DIR is not a directory" >&2; exit 1; }
else
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

MANUAL="$ROOT/CLAUDE.md"
BUDGET="${CLAUDE_MD_LINE_BUDGET:-340}"

fail=0
warn=0

ok()      { printf '  ok    %s\n' "$1"; }
bad()     { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
caution() { printf '  warn  %s\n' "$1"; warn=$((warn + 1)); }

echo "Checking $ROOT"
echo

# --- 1. The manual exists ----------------------------------------------------
if [ ! -f "$MANUAL" ]; then
  bad "CLAUDE.md not found at $ROOT"
  echo
  echo "Pass the repository root as an argument, or set CLAUDE_PROJECT_DIR."
  echo
  echo "1 check failed."
  exit 1
fi
ok "CLAUDE.md exists"

# --- 2. No unfilled placeholders, and no usage block ------------------------
# An unfilled placeholder is worse than a missing section. It teaches the agent
# to guess. The usage block is instructions to the person filling the file in,
# and it wastes context in every session once the file is filled.
for name in CLAUDE.md README.md; do
  file="$ROOT/$name"
  if [ ! -f "$file" ]; then
    if [ "$name" = "README.md" ]; then
      bad "README.md is missing. CLAUDE.md section 6 requires it."
    fi
    continue
  fi

  placeholders=$(grep -c '{{' "$file" || true)
  if [ "$placeholders" -gt 0 ]; then
    bad "$placeholders unfilled {{PLACEHOLDER}} marker(s) in $name:"
    grep -n '{{' "$file" | sed 's/^/          /' | head -20
  else
    ok "$name has no unfilled placeholders"
  fi

  if grep -q 'TEMPLATE USAGE' "$file"; then
    bad "the TEMPLATE USAGE comment block is still present in $name. Delete it."
  else
    ok "$name has no template usage block"
  fi
done

# --- 3. Line budget ----------------------------------------------------------
lines=$(wc -l < "$MANUAL" | tr -d ' ')
if [ "$lines" -gt "$BUDGET" ]; then
  caution "CLAUDE.md is $lines lines, over the ~$BUDGET budget. Move detail into docs/ or a skill."
else
  ok "CLAUDE.md is $lines lines (budget ~$BUDGET)"
fi

# --- 4. Companion files ------------------------------------------------------
for path in \
  ".claude/settings.json" \
  ".claude/hooks/block-subagent-git.sh" \
  ".claude/agents/researcher.md" \
  ".claude/agents/reviewer.md" \
  ".claude/agents/implementer.md" \
  ".claude/skills/parallel-agent-safety/SKILL.md" \
  ".claude/skills/ste-writing/SKILL.md"
do
  if [ -f "$ROOT/$path" ]; then
    ok "$path"
  else
    bad "$path is missing. CLAUDE.md refers to it."
  fi
done

# --- 5. settings.json is valid JSON -----------------------------------------
if [ -f "$ROOT/.claude/settings.json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ROOT/.claude/settings.json" 2>/dev/null; then
      ok "settings.json parses as JSON"
    else
      bad "settings.json is not valid JSON"
    fi
  else
    caution "python3 not found, skipped the JSON check"
  fi
fi

# --- 6. The hook is executable ----------------------------------------------
hook="$ROOT/.claude/hooks/block-subagent-git.sh"
if [ -f "$hook" ]; then
  if [ -x "$hook" ]; then
    ok "the git hook is executable"
  else
    bad "the git hook is not executable. Run: chmod +x $hook"
  fi
fi

# --- 7. The hook actually enforces its policy -------------------------------
# A hook that is present but broken gives false confidence. Test it directly.
# The full matrix lives in the scaffold's own self-test.sh; these are the six
# cases that prove the policy is the intended one.
if [ -x "$hook" ] && command -v python3 >/dev/null 2>&1; then
  hook_case() {
    # $1 = label. $2 = expected exit code. $3 = caller (sub|main). $4 = command.
    local label=$1 want=$2 caller=$3 command=$4 code
    python3 - "$caller" "$command" <<'PY' | "$hook" >/dev/null 2>&1
import json, sys
caller, command = sys.argv[1], sys.argv[2]
d = {"hook_event_name": "PreToolUse", "tool_name": "Bash",
     "tool_input": {"command": command}}
if caller == "sub":
    d["agent_id"] = "a1"
    d["agent_type"] = "implementer"
print(json.dumps(d))
PY
    code=${PIPESTATUS[1]}
    if [ "$code" -eq "$want" ]; then
      ok "hook: $label"
    else
      bad "hook: $label [exit $code, wanted $want]"
    fi
  }

  hook_case "allows a subagent to read history"        0 sub 'git status --short'
  hook_case "allows a subagent to stage a named path"  0 sub 'git add src/foo.ts'
  hook_case "allows a subagent to commit"              0 sub 'git commit -m "feat: x"'
  hook_case "blocks blanket staging"                   2 sub 'git add -A'
  hook_case "blocks a hook bypass"                     2 sub 'git commit --no-verify -m "x"'
  hook_case "blocks a subagent push"                   2 sub 'git push origin main'
  hook_case "never limits the main session"            0 main 'git reset --hard HEAD~1'
fi

# --- 8. .gitignore covers the agent workspaces ------------------------------
# Both entries are load-bearing. An unignored .worktrees/ commits a whole
# second checkout. An unignored .superpowers/ commits the SDD ledger and every
# review package with it.
gitignore="$ROOT/.gitignore"
if [ -f "$gitignore" ]; then
  for entry in ".worktrees/" ".superpowers/"; do
    if grep -qF "$entry" "$gitignore"; then
      ok ".gitignore covers $entry"
    else
      bad ".gitignore does not cover $entry. Superpowers writes there."
    fi
  done
else
  bad ".gitignore is missing. It must cover .worktrees/ and .superpowers/"
fi

# --- 9. docs tree ------------------------------------------------------------
[ -f "$ROOT/docs/index.md" ] && ok "docs/index.md" || caution "docs/index.md is missing"
for dir in "docs/superpowers/specs" "docs/superpowers/plans"; do
  [ -d "$ROOT/$dir" ] && ok "$dir/" || caution "$dir/ is missing. Superpowers writes there."
done

echo
if [ "$fail" -gt 0 ]; then
  echo "$fail check(s) failed, $warn warning(s)."
  exit 1
fi
echo "All checks passed. $warn warning(s)."
