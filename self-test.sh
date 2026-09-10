#!/usr/bin/env bash
# self-test.sh — the scaffold's own test suite.
#
# Run it from the scaffold repository root: ./self-test.sh
#
# It tests the parts of the scaffold that
# have behaviour, rather than the parts that are prose:
#
#   1. Every shell script parses.
#   2. settings.json is valid JSON.
#   3. block-subagent-git.sh allows and blocks the right commands.
#   4. install.sh produces a target repository that check-claude-md.sh accepts.
#   5. The two CLAUDE.md variants differ in section 4 and nowhere else.
#
# scripts/ is the payload that install.sh copies into a target repository, so
# scaffold-only tooling lives here at the root and in dev/ instead.
#
# Exit codes: 0 all tests pass. 1 at least one test failed.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$ROOT/hooks/block-subagent-git.sh"

pass=0
fail=0

ok()   { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

# --- payload builder --------------------------------------------------------
# python3 builds the JSON so that a command containing quotes stays intact.
payload() {
  # $1 = caller: "sub" or "main". $2 = the command string.
  python3 - "$1" "$2" <<'PY'
import json, sys
caller, command = sys.argv[1], sys.argv[2]
d = {
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": command},
}
if caller == "sub":
    d["agent_id"] = "a1"
    d["agent_type"] = "implementer"
print(json.dumps(d))
PY
}

# --- the hook assertion -----------------------------------------------------
# $1 = "allow" or "block". $2 = caller. $3 = the command.
expect() {
  want=$1
  caller=$2
  command=$3

  payload "$caller" "$command" | "$HOOK" >/dev/null 2>&1
  code=$?

  case "$want" in
    allow) want_code=0 ;;
    block) want_code=2 ;;
    *) bad "bad expectation '$want' in the test itself"; return ;;
  esac

  if [ "$code" -eq "$want_code" ]; then
    ok "$want ($caller): $command"
  else
    bad "$want ($caller): $command  [exit $code, wanted $want_code]"
  fi
}

echo "Self-test: $ROOT"
echo

# --- 1. Shell scripts parse -------------------------------------------------
echo "Shell syntax"
for script in "$ROOT"/hooks/*.sh "$ROOT"/scripts/*.sh "$ROOT"/install.sh; do
  [ -f "$script" ] || continue
  name="${script#"$ROOT"/}"
  if sh -n "$script" 2>/dev/null || bash -n "$script" 2>/dev/null; then
    ok "$name parses"
  else
    bad "$name has a syntax error"
  fi
done
echo

# --- 2. settings.json -------------------------------------------------------
echo "settings.json"
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ROOT/settings.json" 2>/dev/null; then
  ok "settings.json parses as JSON"
else
  bad "settings.json is not valid JSON"
fi
echo

# --- 3. The subagent git hook ----------------------------------------------
# A subagent must be able to read history and to commit its own work, because
# superpowers:subagent-driven-development requires each implementer to commit.
# Everything that reshapes the repository stays with the orchestrator.
echo "Hook: a subagent may read"
expect allow sub 'git status --short'
expect allow sub 'git diff'
expect allow sub 'git diff -U10 HEAD~1'
expect allow sub 'git log --oneline -5'
expect allow sub 'git show HEAD'
expect allow sub 'git rev-parse HEAD'
expect allow sub 'git config --get user.name'
echo

echo "Hook: a subagent may stage explicit paths and commit"
expect allow sub 'git add src/foo.ts'
expect allow sub 'git add -- src/foo.ts tests/foo.test.ts'
expect allow sub 'git add "src/my file.ts"'
expect allow sub 'git commit -m "feat: add the retry helper"'
expect allow sub 'git commit --file /tmp/msg.txt'
expect allow sub 'git add src/a.ts && git commit -m "feat: a"'
expect allow sub 'git status && git commit -m "feat: b"'
echo

echo "Hook: blanket staging and hook bypass stay blocked"
expect block sub 'git add -A'
expect block sub 'git add --all'
expect block sub 'git add .'
expect block sub 'git add -u'
expect block sub 'git add :/'
expect block sub 'git commit -a -m "everything"'
expect block sub 'git commit -am "everything"'
expect block sub 'git commit --no-verify -m "skip the hooks"'
expect block sub 'git commit -n -m "skip the hooks"'
expect block sub 'git commit --amend -m "rewrite"'
echo

echo "Hook: a subagent may not reshape the repository"
expect block sub 'git push origin main'
expect block sub 'git push --force-with-lease'
expect block sub 'git reset --hard HEAD~1'
expect block sub 'git checkout main'
expect block sub 'git switch main'
expect block sub 'git restore .'
expect block sub 'git branch -D feature'
expect block sub 'git merge feature'
expect block sub 'git rebase main'
expect block sub 'git cherry-pick abc123'
expect block sub 'git revert HEAD'
expect block sub 'git clean -fd'
expect block sub 'git stash'
expect block sub 'git tag v1.0.0'
expect block sub 'git worktree add ../worktrees/x'
expect block sub 'git config user.email nobody@example.com'
expect block sub 'git status && git push origin main'
echo

echo "Hook: non-git and the main session pass through"
expect allow sub 'npm test'
expect allow sub 'grep -rn "TODO" src/'
expect allow main 'git reset --hard HEAD~1'
expect allow main 'git add -A'
expect allow main 'git push --force origin main'
echo

# --- 4. End-to-end install --------------------------------------------------
# Skipped until install.sh exists.
if [ -x "$ROOT/install.sh" ]; then
  echo "End-to-end install"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  target="$tmp/target"
  mkdir -p "$target"
  git -C "$target" init -q -b main 2>/dev/null || git -C "$target" init -q

  if "$ROOT/install.sh" "$target" >/dev/null 2>&1; then
    ok "install.sh completed"
  else
    bad "install.sh failed"
  fi

  for path in \
    "CLAUDE.md" "README.md" ".gitignore" \
    ".claude/settings.json" \
    ".claude/hooks/block-subagent-git.sh" \
    ".claude/agents/researcher.md" \
    ".claude/agents/reviewer.md" \
    ".claude/agents/implementer.md" \
    ".claude/skills/parallel-agent-safety/SKILL.md" \
    ".claude/skills/ste-writing/SKILL.md" \
    ".claude/scripts/check-claude-md.sh" \
    "docs/index.md"
  do
    [ -e "$target/$path" ] && ok "installed $path" || bad "install.sh did not create $path"
  done

  for entry in ".worktrees/" ".superpowers/"; do
    grep -qF "$entry" "$target/.gitignore" 2>/dev/null \
      && ok ".gitignore covers $entry" \
      || bad ".gitignore does not cover $entry"
  done

  # A fresh install still holds its placeholders, so the check script must fail.
  if "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1; then
    bad "check-claude-md.sh passed on an unfilled install"
  else
    ok "check-claude-md.sh rejects an unfilled install"
  fi

  # Fill the placeholders and strip the usage blocks, then it must pass.
  python3 - "$target" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
for name in ("CLAUDE.md", "README.md"):
    p = root / name
    text = p.read_text()
    text = re.sub(r"<!--\s*TEMPLATE USAGE.*?-->\n?", "", text, flags=re.S)
    text = re.sub(r"\{\{[^}]*\}\}", "placeholder", text)
    p.write_text(text)
PY
  if "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1; then
    ok "check-claude-md.sh passes on a filled install"
  else
    bad "check-claude-md.sh failed on a filled install"
    "$target/.claude/scripts/check-claude-md.sh" "$target" 2>&1 | sed 's/^/          /'
  fi
  echo
fi

# --- 5. The two manual variants diverge in section 4 only -------------------
# README.md and both usage blocks promise this. A divergence anywhere else means
# a fix landed in one variant and not the other.
if [ -f "$ROOT/CLAUDE-template.md" ] && [ -f "$ROOT/CLAUDE-light.md" ]; then
  echo "Manual variants"
  strip="$ROOT/dev/strip-variant.py"
  if diff <(python3 "$strip" "$ROOT/CLAUDE-template.md") \
          <(python3 "$strip" "$ROOT/CLAUDE-light.md") >/dev/null; then
    ok "the variants match outside section 4"
  else
    bad "the variants diverge outside section 4:"
    diff <(python3 "$strip" "$ROOT/CLAUDE-template.md") \
         <(python3 "$strip" "$ROOT/CLAUDE-light.md") | sed 's/^/          /' | head -20
  fi
  echo
fi

# --- Report -----------------------------------------------------------------
if [ "$fail" -gt 0 ]; then
  echo "$fail test(s) failed, $pass passed."
  exit 1
fi
echo "All $pass tests passed."
