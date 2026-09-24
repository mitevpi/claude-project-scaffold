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
BUDGET="${CLAUDE_MD_LINE_BUDGET:-260}"

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
      bad "README.md is missing. The Documentation section of CLAUDE.md requires it."
    fi
    continue
  fi

  # "{{" not preceded by "$", so that a GitHub Actions expression such as
  # ${{ secrets.X }} in a filled manual is not mistaken for a placeholder.
  placeholder_re='(^|[^$])[{][{]'
  placeholders=$(grep -cE "$placeholder_re" "$file" || true)
  if [ "$placeholders" -gt 0 ]; then
    bad "$placeholders line(s) with an unfilled {{PLACEHOLDER}} in $name:"
    grep -nE "$placeholder_re" "$file" | sed 's/^/          /' | head -20
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
  ".claude/hooks/session-start-git-context.sh" \
  ".claude/scripts/land-branch.sh" \
  ".claude/scripts/review-package.sh" \
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

# --- 5. settings.json parses, registers the hooks, and holds the deny rules --
# A hook on disk that settings.json does not register never runs. A check that
# only looks for the file gives false confidence, so check the wiring too.
# The deny rules below are the ones that stand between the main session and
# lost work. The main session is not limited by the git hook, so these rules
# are its only mechanical control.
if [ -f "$ROOT/.claude/settings.json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    settings_report=$(python3 - "$ROOT/.claude/settings.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except ValueError:
    print("bad settings.json is not valid JSON")
    sys.exit(0)
print("ok settings.json parses as JSON")

def registered(event, script):
    for group in d.get("hooks", {}).get(event, []):
        for h in group.get("hooks", []):
            if script in h.get("command", ""):
                return group.get("matcher", "")
    return None

for group in d.get("hooks", {}).get("PreToolUse", []):
    for h in group.get("hooks", []):
        if "block-subagent-git.sh" in h.get("command", ""):
            print("wire " + h["command"])

m = registered("PreToolUse", "block-subagent-git.sh")
if m is None:
    print("bad settings.json does not register block-subagent-git.sh under PreToolUse. The hook never runs.")
elif m not in ("Bash", "*", ""):
    print("bad block-subagent-git.sh is registered with matcher %r. It must match Bash." % m)
else:
    print("ok settings.json registers block-subagent-git.sh for Bash")

if registered("SessionStart", "session-start-git-context.sh") is None:
    print("bad settings.json does not register session-start-git-context.sh under SessionStart")
else:
    print("ok settings.json registers session-start-git-context.sh")

required = [
    "Bash(git reset --hard:*)",
    "Bash(git clean:*)",
    "Bash(git push --force:*)",
    "Bash(git checkout -f:*)",
    "Bash(git switch --discard-changes:*)",
    "Bash(git branch -D:*)",
    "Bash(git worktree remove --force:*)",
    "Bash(git reflog expire:*)",
    "Bash(git stash clear:*)",
    "Bash(rm -rf:*)",
]
deny = d.get("permissions", {}).get("deny", [])
missing = [r for r in required if r not in deny]
if missing:
    print("bad settings.json lacks %d required deny rule(s): %s" % (len(missing), ", ".join(missing)))
else:
    print("ok settings.json holds the required deny rules")

# The files that enforce the rules must not change without the owner's yes.
# A deny rule counts too: it is stricter than ask.
protect = [
    "Edit(/.claude/settings.json)",
    "Edit(/.claude/settings.local.json)",
    "Edit(/.claude/hooks/**)",
    "Edit(/.claude/scripts/**)",
    "Edit(/.claude/agents/**)",
]
guarded = deny + d.get("permissions", {}).get("ask", [])
missing = [r for r in protect if r not in guarded]
if missing:
    print("bad settings.json lets an agent edit its own controls without asking: add %s to ask" % ", ".join(missing))
else:
    print("ok settings.json asks before an edit to the settings, hooks, scripts, or agents")
PY
)
    while IFS= read -r line; do
      case "$line" in
        ok\ *)  ok "${line#ok }" ;;
        bad\ *) bad "${line#bad }" ;;
        wire\ *) wired_command=${line#wire } ;;
      esac
    done <<EOF
$settings_report
EOF
  else
    caution "python3 not found, skipped the settings.json checks"
  fi
fi

# --- 6. The hooks and scripts are executable ---------------------------------
# A hook that cannot execute exits 126, and Claude Code treats that as a
# non-blocking error. The command runs anyway, so the hook fails open silently.
hook="$ROOT/.claude/hooks/block-subagent-git.sh"
for f in "$hook" "$ROOT/.claude/hooks/session-start-git-context.sh" "$ROOT/.claude/scripts/land-branch.sh"; do
  [ -f "$f" ] || continue
  if [ -x "$f" ]; then
    ok "${f#"$ROOT"/} is executable"
  else
    bad "${f#"$ROOT"/} is not executable. Run: chmod +x $f"
  fi
done

# --- 7. The hook actually enforces its policy -------------------------------
# A hook that is present but broken gives false confidence. Test it directly.
# The full matrix lives in the scaffold's own self-test.sh; these are the few
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
  hook_case "lets the main session reshape the repo"   0 main 'git rebase main'
  hook_case "blocks a destructive main-session command" 2 main 'git -C .worktrees/x reset --hard'

  # Run the hook exactly as settings.json registers it. A wrong path in the
  # command exits 127, which Claude Code treats as a non-blocking error: the
  # hook would fail open with no sign of it.
  if [ -n "${wired_command:-}" ]; then
    printf '%s' '{"agent_id":"a1","tool_input":{"command":"git push origin main"}}' \
      | CLAUDE_PROJECT_DIR="$ROOT" sh -c "$wired_command" >/dev/null 2>&1
    wired_code=$?
    if [ "$wired_code" -eq 2 ]; then
      ok "hook: the command registered in settings.json runs and blocks"
    else
      bad "hook: the command registered in settings.json exits $wired_code, not 2. It fails open."
    fi
  fi
fi

# --- 8. .gitignore covers the agent workspaces ------------------------------
# Both entries are load-bearing. An unignored .worktrees/ commits a whole
# second checkout. An unignored .superpowers/ commits the SDD ledger and every
# review package with it.
# git decides what is ignored, so ask git. A grep passes on a commented-out
# line and fails on an equivalent pattern.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for probe in ".worktrees/probe" ".claude/worktrees/probe" ".superpowers/probe"; do
    dir=${probe%/probe}/
    if git -C "$ROOT" check-ignore -q "$probe"; then
      ok ".gitignore covers $dir"
    else
      bad ".gitignore does not cover $dir. Superpowers or Claude Code writes there."
    fi
  done
else
  bad "$ROOT is not a git repository, so the .gitignore entries cannot be checked"
fi

# --- 9. No personal skill shadows a project skill -----------------------------
# Claude Code ranks a personal skill (~/.claude/skills/<name>) above a project
# skill with the same name, so the project copy silently never runs on this
# machine. Teammates without the personal copy run the project one. Two people
# then follow two different procedures under one name.
for skill in "$ROOT"/.claude/skills/*/SKILL.md; do
  [ -f "$skill" ] || continue
  name=$(basename "$(dirname "$skill")")
  personal="${HOME:-}/.claude/skills/$name/SKILL.md"
  if [ -f "$personal" ] && ! cmp -s "$skill" "$personal"; then
    caution "the personal skill ~/.claude/skills/$name shadows .claude/skills/$name, and they differ. Delete or re-sync the personal copy."
  fi
done

# --- 10. docs tree -----------------------------------------------------------
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
