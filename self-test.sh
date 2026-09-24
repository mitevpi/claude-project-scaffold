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
#   4. install.sh produces a target repository that check-claude-md.sh accepts,
#      merges into an existing project, and refuses a target it cannot undo.
#   5. session-start-git-context.sh warns about work already in the checkout.
#   6. land-branch.sh lands a branch, and every refusal loses nothing.
#   7. review-package.sh writes a correct package for the shell-less reviewer.
#   8. CLAUDE-light.md is generated from CLAUDE-template.md, and both stay in budget.
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

# The tests create commits, so they need a git identity even on a bare CI
# runner, and they must not depend on the identity of the person running them.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

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
    "cwd": "/work/repo",
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
# Two rules that the manual once stated only in prose are settings now.
setting() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$ROOT/settings.json" "$1" 2>/dev/null; }
[ "$(setting 'd["env"]["CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"]')" = "1" ] \
  && ok "settings.json stops a subagent from spawning a subagent" \
  || bad "settings.json does not set CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH to 1"
[ "$(setting 'd["attribution"]["commit"] == "" and d["attribution"]["pr"] == ""')" = "True" ] \
  && ok "settings.json hides the commit and pull-request attribution" \
  || bad "settings.json does not hide attribution"

# The Read deny rules must cover real secret files at any depth, and must not
# cover .env.example, which the manual tells the agent to read. The matcher
# below approximates Claude Code's gitignore-style patterns: "**/" matches any
# directory prefix, and a pattern without it matches at the repository root.
env_report=$(python3 - "$ROOT/settings.json" <<'PY'
import fnmatch, json, sys
deny = [r[5:-1] for r in json.load(open(sys.argv[1]))["permissions"]["deny"] if r.startswith("Read(")]
def denied(path):
    for pat in deny:
        if pat.startswith("**/"):
            rest = pat[3:]
            parts = path.split("/")
            if any(fnmatch.fnmatchcase("/".join(parts[i:]), rest) for i in range(len(parts))):
                return True
        elif fnmatch.fnmatchcase(path, pat):
            return True
    return False
must = [".env", ".env.local", ".env.production", "api/.env", "api/.env.local",
        "certs/server.pem", "certs/server.key", "id_rsa", "config/credentials.json"]
must_not = [".env.example", "api/.env.example", ".env.sample", "src/env.ts"]
wrong = [p for p in must if not denied(p)] + ["(readable) " + p for p in must_not if denied(p)]
print(" ".join(wrong))
PY
)
[ -z "$env_report" ] \
  && ok "the Read deny rules cover secret files at any depth and spare .env.example" \
  || bad "the Read deny rules are wrong for: $env_report"
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

echo "Hook: a git command cannot hide from the hook"
# Each of these runs a blocked git command. A hook that looks only at the
# first word of each segment lets every one of them through.
expect block sub '/usr/bin/git reset --hard HEAD'
expect block sub 'echo $(git reset --hard HEAD)'
expect block sub 'echo "$(git stash)"'
expect block sub 'echo `git stash`'
expect block sub 'bash -c "git reset --hard HEAD"'
expect block sub "sh -c 'git checkout main'"
expect block sub 'eval "git reset --hard"'
expect block sub '(git checkout main)'
expect block sub '{ git stash; }'
expect block sub 'if true; then git reset --hard; fi'
expect block sub 'for b in main; do git checkout "$b"; done'
expect block sub 'GIT_DIR=.git git reset --hard'
expect block sub 'env -i git reset --hard'
expect block sub 'nohup env git reset --hard'
expect block sub 'xargs git reset --hard < /dev/null'
expect block sub 'git -C .worktrees/x reset --hard'
expect block sub "$(printf 'git status\ngit reset --hard')"
echo

echo "Hook: staging and config loopholes stay closed"
expect block sub 'git add -f .env'
expect block sub 'git add --force secrets.txt'
expect block sub 'git add ..'
expect block sub 'git -c core.hooksPath=/dev/null commit -m "x"'
expect block sub 'git branch new-branch'
expect block sub 'git branch -m old new'
expect block sub 'git worktree remove .worktrees/x'
expect block sub 'git stash pop'
expect block sub 'git remote add other https://example.com/x.git'
expect block sub 'git reflog expire --all'
echo

echo "Hook: other spellings of a blocked action stay blocked"
# git accepts any unique prefix of a long option, and a group of short
# flags. A guard that compares whole words misses both.
expect block sub 'git commit --no-verif -m "x"'
expect block sub 'git commit --amen -m "x"'
expect block sub 'git commit --al -m "x"'
expect block sub 'git add --forc secrets.txt'
expect block sub 'git add --upd src'
expect block sub 'git add -fv .env'
expect block sub 'git add -Av src'
expect block sub 'git commit -im "x" src/a.ts'
expect block sub 'git add --pathspec-from-file=list.txt'
# A pathspec that names the whole tree is blanket staging, however it is spelt.
expect block sub 'git add "$PWD"'
expect block sub 'git add "$(git rev-parse --show-toplevel)"'
expect block sub 'git add ./*'
expect block sub 'git add "src/*.ts"'
expect block sub "git add ':(top)'"
expect block sub "git add ':!secrets'"
expect block sub 'git add ./.'
expect block sub 'git add /work/repo'
expect block sub 'git add /work'
# A pathspec on git commit commits the working tree, staged or not.
expect block sub 'git commit -m "x" .'
expect block sub 'git commit -m "x" -- :/'
# Hooks can be switched off through configuration as well as flags.
expect block sub 'git --config-env=core.hooksPath=X commit -m "x"'
expect block sub 'git --config-env core.hooksPath=X commit -m "x"'
expect block sub 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m "x"'
expect block sub 'export GIT_CONFIG_PARAMETERS="core.hooksPath=/dev/null"; git commit -m "x"'
expect block sub 'HUSKY=0 git commit -m "x"'
echo

echo "Hook: a git command cannot hide behind a run-time name or a wrapper"
expect block sub 'G=git; $G push'
expect block sub '$(echo git) push origin main'
expect block sub '"$GIT" push origin main'
expect block sub "echo \"\$(echo ')' ; git push)\""
expect block sub "env -S 'git push origin main'"
expect block sub "env --split-string='git push origin main'"
expect block sub 'find . -maxdepth 0 -exec git push \;'
expect block sub 'find . -maxdepth 0 -execdir git reset --hard {} +'
expect block sub 'watch -n 5 git push'
expect block sub "$(printf 'bash <<%sEOF%s\ngit push origin main\nEOF' "'" "'")"
expect block sub "$(printf 'cat <<EOF\n$(git push)\nEOF')"
# land-branch.sh rebases, fast-forwards, and deletes a branch. The hook
# cannot see the git commands inside it, so it blocks the script itself.
expect block sub '.claude/scripts/land-branch.sh feature main'
expect block sub 'bash .claude/scripts/land-branch.sh feature main'
expect block sub '/work/repo/.claude/scripts/land-branch.sh feature main'
echo

echo "Hook: ordinary work is not caught by the stricter guards"
expect allow sub 'git add src/a.ts src/b.ts'
expect allow sub 'git add /work/repo/src/a.ts'
expect allow sub 'git add src'
expect allow sub 'git add -v -- src/a.ts'
expect allow sub 'git add -N src/new.ts'
expect allow sub 'git commit -m "x" src/a.ts'
expect allow sub 'git commit --author="A <a@b>" -m "x"'
expect allow sub 'git commit --allow-empty -m "x"'
expect allow sub 'git commit -S -m "x"'
expect allow sub 'git commit -qm "x"'
expect allow sub 'git commit -m "fix: the --amend flag and the -a flag in the docs"'
expect allow sub 'git -c core.quotepath=off status'
expect allow sub 'git show-ref'
expect allow sub 'git ls-remote origin'
expect allow sub '"$PYTHON" -m pytest'
expect allow sub 'bash scripts/run-tests.sh && git status'
# Claude Code writes a commit message through a heredoc. An apostrophe in the
# message, or a line that mentions git, is data, not a command.
expect allow sub "$(printf 'git commit -m "$(cat <<%sEOF%s\nDon%st run git add -A here.\n\nIt%ss safe (really).\nEOF\n)"' "'" "'" "'" "'")"
expect allow sub "$(printf 'cat > notes.md <<%sEOF%s\nWe don%st git push from a subagent.\nEOF\ngit add notes.md' "'" "'" "'")"
echo

echo "Hook: read-only forms that Superpowers uses stay allowed"
expect allow sub 'git -C .worktrees/x status'
expect allow sub 'git -C .worktrees/x commit -m "feat: x"'
expect allow sub 'cd .worktrees/x && git status'
expect allow sub 'git --no-pager log -3'
expect allow sub 'git -c color.ui=never log'
expect allow sub 'git branch'
expect allow sub 'git branch --show-current'
expect allow sub 'git branch -a --contains HEAD'
expect allow sub 'git merge-base HEAD main'
expect allow sub 'git merge-base --is-ancestor HEAD main'
expect allow sub 'git check-ignore -q .worktrees'
expect allow sub 'git worktree list --porcelain'
expect allow sub 'git stash list'
expect allow sub 'git remote -v'
expect allow sub 'git remote get-url origin'
expect allow sub 'git reflog -5'
expect allow sub 'git commit -s -m "feat: signed"'
expect allow sub 'git commit -m "-n is not a flag inside a message"'
expect allow sub 'echo "$(git rev-parse HEAD)"'
expect allow sub 'bash scripts/run-tests.sh'
expect allow sub "$(printf 'git add a.ts\ngit commit -m "feat: a"')"
echo

echo "Hook: a subagent command it cannot read is blocked, not allowed"
raw_expect() {
  # $1 = allow|block. $2 = label. $3 = raw payload text.
  printf '%s' "$3" | "$HOOK" >/dev/null 2>&1
  code=$?
  want_code=0; [ "$1" = block ] && want_code=2
  [ "$code" -eq "$want_code" ] && ok "$1: $2" || bad "$1: $2 [exit $code, wanted $want_code]"
}
raw_expect block "truncated subagent JSON that mentions git" '{"agent_id":"a1","tool_input":{"command":"git reset --hard'
raw_expect allow "truncated subagent JSON with no git in it" '{"agent_id":"a1","tool_input":{"command":"npm te'
raw_expect allow "a main session started with --agent is not a subagent" \
  '{"agent_type":"implementer","tool_input":{"command":"git push origin main"}}'
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

  # install.sh installs the scaffold's committed HEAD, never its working
  # tree. So the tests run against a committed snapshot of this working tree:
  # every tracked file and every untracked file that is not ignored.
  SNAP="$tmp/scaffold"
  mkdir -p "$SNAP"
  (cd "$ROOT" && git ls-files -z --cached --others --exclude-standard) \
    | while IFS= read -r -d '' f; do
        [ -e "$ROOT/$f" ] || continue
        mkdir -p "$SNAP/$(dirname "$f")"
        cp -p "$ROOT/$f" "$SNAP/$f"
      done
  git -C "$SNAP" init -q -b main
  git -C "$SNAP" add -A
  git -C "$SNAP" commit -qm snapshot
  # A stray local file, such as a .DS_Store, must never reach a target.
  echo stray > "$SNAP/skills/.DS_Store"
  echo scratch > "$SNAP/agents/scratch-notes.md"

  target="$tmp/target"
  mkdir -p "$target"
  git -C "$target" init -q -b main 2>/dev/null || git -C "$target" init -q

  if "$SNAP/install.sh" "$target" >/dev/null 2>&1; then
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

  # git decides what is ignored, so ask git rather than grep the file.
  for probe in ".worktrees/x/f" ".claude/worktrees/x/f" ".superpowers/sdd/f"; do
    git -C "$target" check-ignore -q "$probe" \
      && ok "git ignores $probe after install" \
      || bad "git does not ignore $probe after install"
  done
  git -C "$target" check-ignore -q "src/worktrees/f" \
    && bad "the worktree entries also ignore src/worktrees/, a normal source directory" \
    || ok "the worktree entries are anchored at the repository root"

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

  # A GitHub Actions expression such as ${{ secrets.X }} is not a placeholder.
  cp "$target/CLAUDE.md" "$tmp/manual.saved"
  echo 'CI reads the token from `${{ secrets.DEPLOY_TOKEN }}`.' >> "$target/CLAUDE.md"
  "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1 \
    && ok "check-claude-md.sh accepts a \${{ }} expression in a filled manual" \
    || bad "check-claude-md.sh mistook a \${{ }} expression for a placeholder"
  echo 'Owner: {{OWNER_NAME}}' >> "$target/CLAUDE.md"
  "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1 \
    && bad "check-claude-md.sh missed a placeholder next to a \${{ }} expression" \
    || ok "check-claude-md.sh still catches a real placeholder"
  cp "$tmp/manual.saved" "$target/CLAUDE.md"

  # The check must catch a hook that is on disk but not wired into settings.
  # Without the wiring, the hook never runs, and a pass is false confidence.
  settings_edit() {
    # $1 = settings.json path. $2 = python expression that edits dict d.
    python3 - "$1" "$2" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
d = json.load(open(path))
exec(expr)
json.dump(d, open(path, "w"), indent=2)
PY
  }
  cp "$target/.claude/settings.json" "$tmp/settings.saved"
  settings_edit "$target/.claude/settings.json" 'd.pop("hooks")'
  if "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1; then
    bad "check-claude-md.sh passed with the git hook unregistered"
  else
    ok "check-claude-md.sh fails when the git hook is not registered"
  fi
  cp "$tmp/settings.saved" "$target/.claude/settings.json"
  # A registered command with a wrong path exits 127, and Claude Code treats
  # that as a non-blocking error: the hook fails open with no sign of it.
  settings_edit "$target/.claude/settings.json" '
h = d["hooks"]["PreToolUse"][0]["hooks"][0]
h["command"] = h["command"].replace(".claude/hooks/", ".claude/hook/")'
  if "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1; then
    bad "check-claude-md.sh passed with a hook command that points at a missing file"
  else
    ok "check-claude-md.sh runs the registered hook command and catches a broken path"
  fi
  cp "$tmp/settings.saved" "$target/.claude/settings.json"
  settings_edit "$target/.claude/settings.json" 'd["permissions"]["deny"].remove("Bash(git reset --hard:*)")'
  if "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1; then
    bad "check-claude-md.sh passed with a required deny rule missing"
  else
    ok "check-claude-md.sh fails when a required deny rule is missing"
  fi
  cp "$tmp/settings.saved" "$target/.claude/settings.json"

  # The check must ask git, not grep: a commented-out entry is no entry, and
  # an equivalent pattern is a valid one.
  cp "$target/.gitignore" "$tmp/gitignore.saved"
  printf '# .worktrees/\n.claude/worktrees/\n.superpowers/\n' > "$target/.gitignore"
  "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1 \
    && bad "check-claude-md.sh accepted a commented-out .worktrees/ entry" \
    || ok "check-claude-md.sh rejects a commented-out .worktrees/ entry"
  printf '/.worktrees\n/.claude/worktrees\n.superpowers\n' > "$target/.gitignore"
  "$target/.claude/scripts/check-claude-md.sh" "$target" >/dev/null 2>&1 \
    && ok "check-claude-md.sh accepts equivalent .gitignore patterns" \
    || bad "check-claude-md.sh rejected equivalent .gitignore patterns"
  cp "$tmp/gitignore.saved" "$target/.gitignore"

  # A personal skill with the same name shadows the project copy, because
  # Claude Code ranks personal skills above project skills. The check warns.
  fake_home="$tmp/home"
  mkdir -p "$fake_home/.claude/skills/ste-writing"
  echo "an older personal copy" > "$fake_home/.claude/skills/ste-writing/SKILL.md"
  shadow_out=$(HOME="$fake_home" "$target/.claude/scripts/check-claude-md.sh" "$target" 2>&1)
  case "$shadow_out" in
    *warn*ste-writing*shadows*) ok "check-claude-md.sh warns when a personal skill shadows a project skill" ;;
    *) bad "check-claude-md.sh did not warn about a shadowing personal skill" ;;
  esac
  cp "$target/.claude/skills/ste-writing/SKILL.md" "$fake_home/.claude/skills/ste-writing/SKILL.md"
  case "$(HOME="$fake_home" "$target/.claude/scripts/check-claude-md.sh" "$target" 2>&1)" in
    *shadows*) bad "check-claude-md.sh warned about an identical personal skill" ;;
    *) ok "check-claude-md.sh accepts an identical personal skill" ;;
  esac
  echo

  # --- An existing project --------------------------------------------------
  echo "Install into an existing project"
  existing="$tmp/existing"
  mkdir -p "$existing/.claude"
  git -C "$existing" init -q -b main
  printf '{\n  "permissions": {"allow": ["Bash(npm test)"], "deny": ["Bash(make deploy:*)"]},\n  "env": {"FOO": "1"},\n  "model": "sonnet"\n}\n' \
    > "$existing/.claude/settings.json"
  echo "# Existing manual" > "$existing/CLAUDE.md"
  git -C "$existing" add -A
  git -C "$existing" -c user.name=t -c user.email=t@t commit -qm init

  if "$SNAP/install.sh" "$existing" >/dev/null 2>&1; then
    ok "install.sh completed on an existing project"
  else
    bad "install.sh failed on an existing project"
  fi
  merged=$(python3 - "$existing/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("permissions", {})
hooks = json.dumps(d.get("hooks", {}))
checks = [
    "Bash(npm test)" in p.get("allow", []),
    "Bash(make deploy:*)" in p.get("deny", []),
    "Bash(git reset --hard:*)" in p.get("deny", []),
    "Bash(git push:*)" in p.get("ask", []),
    "block-subagent-git.sh" in hooks,
    "session-start-git-context.sh" in hooks,
    d.get("model") == "sonnet",
    d.get("env", {}).get("FOO") == "1",
    d.get("env", {}).get("CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH") == "1",
]
print("yes" if all(checks) else "no")
PY
)
  [ "$merged" = "yes" ] \
    && ok "install.sh merges into an existing settings.json and keeps its rules" \
    || bad "install.sh did not merge settings.json correctly"
  [ "$(head -1 "$existing/CLAUDE.md")" = "# Existing manual" ] \
    && ok "install.sh keeps an existing CLAUDE.md" \
    || bad "install.sh overwrote an existing CLAUDE.md"

  # A second run must not duplicate anything.
  git -C "$existing" add -A
  git -C "$existing" -c user.name=t -c user.email=t@t commit -qm install
  "$SNAP/install.sh" "$existing" >/dev/null 2>&1
  dupes=$(python3 - "$existing/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
lists = [d["permissions"][k] for k in ("allow", "deny", "ask") if k in d["permissions"]]
cmds = [h["command"] for ev in d["hooks"].values() for m in ev for h in m["hooks"]]
print(sum(len(l) - len(set(l)) for l in lists) + len(cmds) - len(set(cmds)))
PY
)
  blocks=$(grep -c '^# --- Claude Code and Superpowers ---' "$existing/.gitignore")
  if [ "$dupes" = "0" ] && [ "$blocks" = "1" ] && [ -z "$(git -C "$existing" status --porcelain)" ]; then
    ok "a second install changes nothing"
  else
    bad "a second install duplicated entries [dupes=$dupes gitignore-blocks=$blocks]"
  fi

  # An older install already has the marker block but lacks a newer entry.
  # A reinstall must add the entry anyway.
  grep -v 'claude/worktrees' "$existing/.gitignore" > "$tmp/gi" && cp "$tmp/gi" "$existing/.gitignore"
  git -C "$existing" add .gitignore
  git -C "$existing" -c user.name=t -c user.email=t@t commit -qm "older gitignore"
  "$SNAP/install.sh" "$existing" >/dev/null 2>&1
  git -C "$existing" check-ignore -q ".claude/worktrees/x/f" \
    && ok "a reinstall adds a missing .gitignore entry to an existing block" \
    || bad "a reinstall did not add the missing .claude/worktrees/ entry"
  git -C "$existing" add .gitignore
  git -C "$existing" -c user.name=t -c user.email=t@t commit -qm "reinstall" >/dev/null 2>&1

  # The installer must refuse a target it cannot cleanly undo.
  echo "uncommitted" > "$existing/wip.txt"
  cp "$existing/.claude/settings.json" "$tmp/settings.before"
  if ! "$SNAP/install.sh" --force "$existing" >/dev/null 2>&1 \
     && cmp -s "$existing/.claude/settings.json" "$tmp/settings.before" \
     && [ "$(head -1 "$existing/CLAUDE.md")" = "# Existing manual" ]; then
    ok "install.sh refuses a target with uncommitted changes"
  else
    bad "install.sh ran on a target with uncommitted changes"
  fi
  rm -f "$existing/wip.txt"

  mkdir -p "$tmp/not-a-repo"
  if ! "$SNAP/install.sh" "$tmp/not-a-repo" >/dev/null 2>&1 \
     && [ ! -e "$tmp/not-a-repo/CLAUDE.md" ]; then
    ok "install.sh refuses a directory that is not a git repository"
  else
    bad "install.sh installed into a directory that is not a git repository"
  fi
  echo

  # --light installs the light manual, and a filled light install passes.
  lt="$tmp/light-target"
  mkdir -p "$lt"; git -C "$lt" init -q -b main
  "$SNAP/install.sh" --light "$lt" >/dev/null 2>&1
  grep -q '^LIGHT variant' "$lt/CLAUDE.md" && grep -q '^variant light$' "$lt/.claude/scaffold-version" \
    && ok "install.sh --light installs and records the light manual" \
    || bad "install.sh --light did not install the light manual"
  python3 - "$lt" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
for name in ("CLAUDE.md", "README.md"):
    p = root / name
    text = re.sub(r"<!--\s*TEMPLATE USAGE.*?-->\n?", "", p.read_text(), flags=re.S)
    p.write_text(re.sub(r"\{\{[^}]*\}\}", "placeholder", text))
PY
  "$lt/.claude/scripts/check-claude-md.sh" "$lt" >/dev/null 2>&1 \
    && ok "check-claude-md.sh passes on a filled light install" \
    || bad "check-claude-md.sh failed on a filled light install"

  # --force overwrites, and git can undo it, because the tree was clean.
  ft="$tmp/force-target"
  mkdir -p "$ft"; git -C "$ft" init -q -b main
  echo "# Our own manual" > "$ft/CLAUDE.md"
  git -C "$ft" add CLAUDE.md; git -C "$ft" commit -qm own
  "$SNAP/install.sh" --force "$ft" >/dev/null 2>&1
  git -C "$ft" restore CLAUDE.md
  [ "$(cat "$ft/CLAUDE.md")" = "# Our own manual" ] \
    && ok "a --force install is undone by git restore" \
    || bad "a --force install could not be undone"
  echo

  # --- Versions and updates ---------------------------------------------------
  echo "Install versions and --update"
  [ ! -e "$target/.claude/skills/.DS_Store" ] && [ ! -e "$target/.claude/agents/scratch-notes.md" ] \
    && ok "install.sh installs committed files only, never stray local ones" \
    || bad "install.sh copied an uncommitted file from the scaffold"
  snap_a=$(git -C "$SNAP" rev-parse HEAD)
  grep -q "^commit $snap_a\$" "$target/.claude/scaffold-version" 2>/dev/null \
    && ok "install.sh records the scaffold commit it installed" \
    || bad "install.sh did not record the scaffold commit in .claude/scaffold-version"

  up="$tmp/update-target"
  mkdir -p "$up"; git -C "$up" init -q -b main
  "$SNAP/install.sh" "$up" >/dev/null 2>&1
  echo "# customised by this project" >> "$up/.claude/agents/implementer.md"
  git -C "$up" add -A; git -C "$up" commit -qm "install and customise"
  manual_before=$(cat "$up/CLAUDE.md")

  # The scaffold moves on: a hook fix, an agent change, a new file, and a
  # manual change.
  echo "# upstream hook fix" >> "$SNAP/hooks/block-subagent-git.sh"
  echo "# upstream agent change" >> "$SNAP/agents/implementer.md"
  mkdir -p "$SNAP/skills/new-skill"; echo "new" > "$SNAP/skills/new-skill/SKILL.md"
  echo "<!-- upstream manual change -->" >> "$SNAP/CLAUDE-template.md"
  git -C "$SNAP" add hooks agents/implementer.md skills/new-skill CLAUDE-template.md
  git -C "$SNAP" commit -qm "upstream changes"
  snap_b=$(git -C "$SNAP" rev-parse HEAD)

  update_out=$("$SNAP/install.sh" --update "$up" 2>&1); update_code=$?
  [ "$update_code" -eq 0 ] && ok "install.sh --update completed" || bad "install.sh --update failed [exit $update_code]"
  tail -1 "$up/.claude/hooks/block-subagent-git.sh" | grep -q "upstream hook fix" \
    && ok "--update refreshes a file the project did not change" \
    || bad "--update did not refresh an unchanged hook"
  tail -1 "$up/.claude/agents/implementer.md" | grep -q "customised by this project" \
    && ok "--update keeps a file the project customised" \
    || bad "--update overwrote a customised file"
  case "$update_out" in
    *implementer.md*) ok "--update names the customised file it skipped" ;;
    *) bad "--update did not report the customised file" ;;
  esac
  [ -f "$up/.claude/skills/new-skill/SKILL.md" ] \
    && ok "--update adds a file that is new upstream" \
    || bad "--update did not add a new upstream file"
  [ "$(cat "$up/CLAUDE.md")" = "$manual_before" ] \
    && ok "--update never touches CLAUDE.md" \
    || bad "--update changed CLAUDE.md"
  case "$update_out" in
    *CLAUDE-template.md*) ok "--update reports that the manual template changed upstream" ;;
    *) bad "--update did not report the manual template change" ;;
  esac
  grep -q "^commit $snap_b\$" "$up/.claude/scaffold-version" \
    && ok "--update records the new scaffold commit" \
    || bad "--update did not record the new scaffold commit"
  echo
fi

# --- 5. The session-start git context hook ---------------------------------
# It shows a new session the work that is already in its checkout, so the
# session does not treat another session's uncommitted work as its own.
CONTEXT_HOOK="$ROOT/hooks/session-start-git-context.sh"
echo "Session-start git context"
ctx_tmp=$(mktemp -d)
git -C "$ctx_tmp" init -q -b main
echo a > "$ctx_tmp/a.txt"
git -C "$ctx_tmp" add a.txt
git -C "$ctx_tmp" -c user.name=t -c user.email=t@t commit -qm init
out=$(cd "$ctx_tmp" && CLAUDE_PROJECT_DIR="$ctx_tmp" "$CONTEXT_HOOK" </dev/null 2>/dev/null)
case "$out" in
  *WARNING*) bad "context hook warned about a clean tree" ;;
  *main*) ok "context hook names the branch of a clean tree, with no warning" ;;
  *) bad "context hook printed nothing useful for a clean tree" ;;
esac
echo changed > "$ctx_tmp/a.txt"
echo new > "$ctx_tmp/other-session.txt"
out=$(cd "$ctx_tmp" && CLAUDE_PROJECT_DIR="$ctx_tmp" "$CONTEXT_HOOK" </dev/null 2>/dev/null)
case "$out" in
  *WARNING*other-session.txt* | *other-session.txt*WARNING*) ok "context hook warns about uncommitted work and lists it" ;;
  *) bad "context hook did not warn about uncommitted work" ;;
esac
out=$(cd /tmp && CLAUDE_PROJECT_DIR=/tmp "$CONTEXT_HOOK" </dev/null 2>/dev/null); code=$?
[ "$code" -eq 0 ] && [ -z "$out" ] \
  && ok "context hook is silent outside a git repository" \
  || bad "context hook misbehaved outside a git repository [exit $code]"
rm -rf "$ctx_tmp"
echo

# --- 6. Landing a branch -----------------------------------------------------
# land-branch.sh replaces a landing sequence that lived in prose and failed in a
# worktree. Every refusal must leave the work exactly where it was.
LAND="$ROOT/scripts/land-branch.sh"
echo "Landing a branch"

# new_repo DIR: a repository with main and a base branch named dev, which is
# checked out in DIR itself.
new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  printf '.worktrees/\n.superpowers/\n' > "$1/.gitignore"
  echo one > "$1/shared.txt"
  git -C "$1" add .gitignore shared.txt
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$1" switch -qc dev
}
# commit_in DIR FILE TEXT
commit_in() {
  echo "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}
sha() { git -C "$1" rev-parse --verify -q "$2"; }

land_tmp=$(mktemp -d)

# L1: a clean worktree lands, even when the base moved on, and nothing is left.
r="$land_tmp/l1"; new_repo "$r"
git -C "$r" worktree add -q .worktrees/t1 -b t1 dev
commit_in "$r/.worktrees/t1" a.txt a
commit_in "$r" b.txt b
if "$LAND" t1 dev -C "$r" >/dev/null 2>&1 \
   && [ -f "$r/a.txt" ] && [ -f "$r/b.txt" ] \
   && [ ! -d "$r/.worktrees/t1" ] && [ -z "$(sha "$r" t1)" ]; then
  ok "land: a clean worktree branch lands and is cleaned up"
else
  bad "land: a clean worktree branch did not land cleanly"
fi

# L2: uncommitted work in the worktree refuses, and touches nothing.
r="$land_tmp/l2"; new_repo "$r"
git -C "$r" worktree add -q .worktrees/t2 -b t2 dev
commit_in "$r/.worktrees/t2" a.txt a
echo wip > "$r/.worktrees/t2/wip.txt"
before=$(sha "$r" t2); base_before=$(sha "$r" dev)
if ! "$LAND" t2 dev -C "$r" >/dev/null 2>&1 \
   && [ -f "$r/.worktrees/t2/wip.txt" ] \
   && [ "$(sha "$r" t2)" = "$before" ] && [ "$(sha "$r" dev)" = "$base_before" ]; then
  ok "land: uncommitted work in the worktree refuses and is kept"
else
  bad "land: uncommitted work in the worktree was not protected"
fi

# L3: a rebase conflict refuses and aborts the rebase.
r="$land_tmp/l3"; new_repo "$r"
git -C "$r" worktree add -q .worktrees/t3 -b t3 dev
commit_in "$r/.worktrees/t3" shared.txt branch-side
commit_in "$r" shared.txt base-side
before=$(sha "$r" t3); base_before=$(sha "$r" dev)
"$LAND" t3 dev -C "$r" >/dev/null 2>&1; code=$?
wt_git=$(git -C "$r/.worktrees/t3" rev-parse --git-dir)
if [ "$code" -ne 0 ] && [ "$(sha "$r" t3)" = "$before" ] \
   && [ "$(sha "$r" dev)" = "$base_before" ] \
   && [ ! -d "$wt_git/rebase-merge" ] && [ ! -d "$wt_git/rebase-apply" ]; then
  ok "land: a rebase conflict refuses and leaves no rebase in progress"
else
  bad "land: a rebase conflict was not refused cleanly [exit $code]"
fi

# L4: a branch with no worktree lands, and work in progress in the base
# checkout survives the fast-forward.
r="$land_tmp/l4"; new_repo "$r"
git -C "$r" branch t4 dev
git -C "$r" worktree add -q "$land_tmp/l4-scratch" t4
commit_in "$land_tmp/l4-scratch" a.txt a
git -C "$r" worktree remove "$land_tmp/l4-scratch"
echo wip > "$r/notes.txt"
if "$LAND" t4 dev -C "$r" >/dev/null 2>&1 \
   && [ -f "$r/a.txt" ] && [ -f "$r/notes.txt" ] && [ -z "$(sha "$r" t4)" ]; then
  ok "land: a branch without a worktree lands and base-checkout WIP survives"
else
  bad "land: a branch without a worktree did not land, or WIP was lost"
fi

# L5: a worktree outside .worktrees/ belongs to someone else, such as another
# session or the harness. Land the commits, but leave the worktree and branch.
r="$land_tmp/l5"; new_repo "$r"
git -C "$r" worktree add -q "$land_tmp/l5-other" -b t5 dev
commit_in "$land_tmp/l5-other" a.txt a
if "$LAND" t5 dev -C "$r" >/dev/null 2>&1 \
   && [ -f "$r/a.txt" ] && [ -d "$land_tmp/l5-other" ] && [ -n "$(sha "$r" t5)" ]; then
  ok "land: a foreign worktree is landed but never removed"
else
  bad "land: a foreign worktree was removed, or the branch did not land"
fi

# L6: the base is checked out nowhere. The fast-forward still happens.
r="$land_tmp/l6"; new_repo "$r"
git -C "$r" switch -q main
git -C "$r" worktree add -q .worktrees/t6 -b t6 dev
commit_in "$r/.worktrees/t6" a.txt a
if "$LAND" t6 dev -C "$r" >/dev/null 2>&1 \
   && [ "$(sha "$r" dev)" = "$(git -C "$r" rev-parse "dev")" ] \
   && git -C "$r" cat-file -e dev:a.txt 2>/dev/null && [ ! -d "$r/.worktrees/t6" ]; then
  ok "land: a base branch that is checked out nowhere is fast-forwarded"
else
  bad "land: a base branch that is checked out nowhere was not fast-forwarded"
fi

# L7: an unknown branch is refused. A typo in the branch name must not become
# a silent no-op that reports success.
r="$land_tmp/l7"; new_repo "$r"
if ! "$LAND" no-such-branch dev -C "$r" >/dev/null 2>&1; then
  ok "land: an unknown branch is refused"
else
  bad "land: an unknown branch was accepted"
fi

rm -rf "$land_tmp"
echo

# --- 7. The review package ---------------------------------------------------
# The reviewer agent holds no shell, so it cannot run "git diff" itself. The
# orchestrator writes the diff to a file and hands the reviewer the path.
PACKAGE="$ROOT/scripts/review-package.sh"
echo "Review package"
pkg_tmp=$(mktemp -d)
git -C "$pkg_tmp" init -q -b main
echo one > "$pkg_tmp/a.txt"; git -C "$pkg_tmp" add a.txt; git -C "$pkg_tmp" commit -qm "first commit"
pkg_base=$(git -C "$pkg_tmp" rev-parse HEAD)
echo two > "$pkg_tmp/a.txt"; git -C "$pkg_tmp" add a.txt; git -C "$pkg_tmp" commit -qm "second commit"
pkg_path=$(cd "$pkg_tmp" && "$PACKAGE" "$pkg_base" HEAD 2>/dev/null)
if [ -f "$pkg_path" ] && grep -q "second commit" "$pkg_path" && grep -q '^+two' "$pkg_path" \
   && ! grep -q "first commit" "$pkg_path"; then
  ok "review-package writes the commit list and the diff for exactly the range"
else
  bad "review-package did not write a correct package [path: $pkg_path]"
fi
[ -z "$(git -C "$pkg_tmp" status --porcelain)" ] \
  && ok "review-package leaves git status clean, even without a .gitignore entry" \
  || bad "review-package left the package visible to git status"
if ! (cd "$pkg_tmp" && "$PACKAGE" no-such-ref HEAD >/dev/null 2>&1); then
  ok "review-package refuses an unknown revision"
else
  bad "review-package accepted an unknown revision"
fi
rm -rf "$pkg_tmp"
echo

# --- 8. The light manual is generated from the FULL one ----------------------
# The two variants differ only in the usage note and the Git section's branch
# model. dev/build-light.py builds the light file from the FULL one and the
# fragments in dev/light-variant.md, so a fix can never land in one variant
# and miss the other.
echo "Manual variants"
if python3 "$ROOT/dev/build-light.py" 2>/dev/null | cmp -s - "$ROOT/CLAUDE-light.md"; then
  ok "CLAUDE-light.md matches the output of dev/build-light.py"
else
  bad "CLAUDE-light.md is stale or hand-edited. Run: python3 dev/build-light.py --write"
fi
for f in CLAUDE-template.md CLAUDE-light.md; do
  n=$(python3 - "$ROOT/$f" <<'PY'
import re, sys
text = re.sub(r"<!--\s*TEMPLATE USAGE.*?-->\n?", "", open(sys.argv[1]).read(), flags=re.S)
print(text.count("\n"))
PY
)
  [ "$n" -le 240 ] && ok "$f is $n lines without its usage block (budget 240)" \
    || bad "$f is $n lines without its usage block, over the 240-line budget"
done
if grep -nE '[Ss]ection [0-9]' "$ROOT"/CLAUDE-*.md "$ROOT"/README*.md "$ROOT"/agents/*.md \
     "$ROOT"/skills/*/SKILL.md "$ROOT"/docs/*.md "$ROOT"/scripts/*.sh >/dev/null; then
  bad "a file refers to a manual section by number. Use the section name:"
  grep -nE '[Ss]ection [0-9]' "$ROOT"/CLAUDE-*.md "$ROOT"/README*.md "$ROOT"/agents/*.md \
    "$ROOT"/skills/*/SKILL.md "$ROOT"/docs/*.md "$ROOT"/scripts/*.sh | sed "s|$ROOT/|          |"
else
  ok "no file refers to a manual section by number"
fi
echo

# --- Report -----------------------------------------------------------------
if [ "$fail" -gt 0 ]; then
  echo "$fail test(s) failed, $pass passed."
  exit 1
fi
echo "All $pass tests passed."
