#!/bin/sh
# block-subagent-git.sh
#
# PreToolUse hook for the Bash tool. It limits which git commands a subagent
# may run. The main session is never limited by this hook.
#
# Why this exists: a destructive git command from one agent in a parallel wave
# acts on the whole repository, not on that agent's task. Prose rules in
# CLAUDE.md do not stop it. This hook does.
#
# What a subagent may do:
#   1. Read history and state: status, diff, log, show, merge-base, the
#      listing forms of branch, worktree, stash, remote, and reflog, and the
#      rest of READ_ONLY below.
#   2. Stage explicit paths with "git add <path>".
#   3. Commit its own work with "git commit".
#
# Reason 3 matters: superpowers:subagent-driven-development requires every
# implementer subagent to commit its task, and the controller then diffs the
# BASE..HEAD range to build the review package. A hook that blocks the commit
# breaks that whole workflow.
#
# What stays with the orchestrator: every command that reshapes the
# repository or publishes it. push, reset, checkout, switch, restore, merge,
# rebase, cherry-pick, revert, clean, tag, creating or deleting a branch, a
# worktree, a stash, or a remote, and the rest.
#
# Two written CLAUDE.md rules become mechanical here:
#   - "Stage explicit paths. Do not run git add -A." Blanket staging is
#     blocked: -A, --all, -u, ".", "..", ":/", "*", --force, and interactive
#     mode.
#   - "Never bypass a hook." git commit --no-verify and -n are blocked, and so
#     is -c core.hooksPath=... on any git command. So are -a (which stages
#     everything) and --amend (which rewrites a commit the orchestrator may
#     already own).
#
# How it decides:
#   1. The PreToolUse payload arrives on stdin as JSON.
#   2. The field agent_id appears only for a subagent call. Without it, the
#      hook exits 0 at once. agent_type alone is not enough: it is also set
#      for a main session started with "claude --agent".
#   3. The command is split into shell words and segments. Every git command
#      is inspected wherever it sits: after a path (/usr/bin/git), after
#      env, nohup, xargs, or a variable assignment, inside $(...), `...`, a
#      subshell, a { } group, an if or a for body, bash -c, sh -c, or eval.
#   4. A git command is allowed only when its subcommand is on the allowlist
#      and passes that subcommand's argument guard. An allowlist fails safe:
#      a new or unknown subcommand is blocked, not permitted.
#
# Exit codes: 0 allows the call. 2 blocks it and returns the stderr text to
# the agent as the reason.
#
# Failure handling. For the main session, and for a subagent command that
# does not mention git, the hook allows the call when it cannot parse the
# payload: a hook that blocks on its own errors would stall every session.
# For a subagent command that mentions git, it blocks instead. Stalling one
# subagent is cheap. A destructive command that slips through is not.

set -u

payload=$(cat)

# --- 1. Is the caller a subagent? --------------------------------------------
# A cheap text test, so that the main session never pays for python3.
case "$payload" in
  *'"agent_id"'*) ;;
  *) exit 0 ;;
esac

mentions_git=0
case "$payload" in
  *git*) mentions_git=1 ;;
esac

block() {
  cat >&2 <<EOF
Blocked: a subagent may not run this git command.

$1

A subagent may read history and state, stage explicit paths, and commit its
own work. Every command that reshapes or publishes the repository belongs to
the orchestrator, which performs each branch operation, merge, and push after
the wave lands.

Run git directly, as its own command, so that the hook can read it. Use
"git -C <path>" or "cd <path> &&" to work in a worktree.

If this work needs a git operation you cannot run, stop and report that to the
orchestrator instead. See the "Parallel agents" section of CLAUDE.md.
EOF
  exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
  [ "$mentions_git" -eq 1 ] && block "python3 is missing, so the hook cannot read the command."
  exit 0
fi

# --- 2. Analyse the command ----------------------------------------------------
# The program reads the payload from HOOK_PAYLOAD, because its own source
# arrives on stdin. It prints nothing and exits 0 to allow. To block, it writes
# the reason to $out and exits 3. Any other exit means the payload did not
# parse or the analysis failed.
#
# The heredoc feeds python3 directly, never through $(...): bash 3.2, which is
# /bin/sh on macOS, misparses a heredoc with unbalanced parentheses inside a
# command substitution.
out=$(mktemp) || { [ "$mentions_git" -eq 1 ] && block "The hook could not create a temporary file."; exit 0; }
trap 'rm -f "$out"' EXIT

HOOK_PAYLOAD=$payload HOOK_OUT=$out python3 - 2>/dev/null <<'PY'
import json, os, re, shlex, sys

READ_ONLY = {
    "status", "diff", "log", "show", "blame", "describe", "rev-parse",
    "rev-list", "ls-files", "ls-tree", "cat-file", "grep", "shortlog",
    "for-each-ref", "count-objects", "var", "merge-base", "check-ignore",
    "check-attr", "name-rev", "whatchanged", "cherry", "range-diff",
    "help", "version",
}
SEPARATORS = {";", "&&", "||", "|", "|&", "&", "(", ")", "{", "}", "\n", ";;"}
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while",
            "until", "for", "in", "case", "esac", "!", "time"}
WRAPPERS = {"sudo", "env", "nohup", "nice", "timeout", "stdbuf", "command",
            "builtin", "exec", "noglob", "xargs", "caffeinate"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


class Blocked(Exception):
    pass


def substitutions(text):
    """Yield the body of every $(...) and `...` in text, innermost included."""
    for m in re.finditer(r"`([^`]*)`", text):
        yield m.group(1)
    depth, start = 0, None
    i = 0
    while i < len(text):
        if text.startswith("$(", i):
            if depth == 0:
                start = i + 2
            depth += 1
            i += 2
            continue
        if text[i] == ")" and depth:
            depth -= 1
            if depth == 0:
                yield text[start:i]
        i += 1


def words(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|(){}\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    seg = []
    for t in tokens:
        if t in SEPARATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def strip_prefix(seg):
    """Drop keywords, variable assignments, and wrapper commands with their
    options, so that seg starts at the command that actually runs."""
    i = 0
    while i < len(seg):
        w = seg[i]
        if w in KEYWORDS or ASSIGNMENT.match(w):
            i += 1
            continue
        if os.path.basename(w) in WRAPPERS:
            i += 1
            while i < len(seg) and (seg[i].startswith("-") or ASSIGNMENT.match(seg[i])):
                takes_value = seg[i] in ("-n", "-u", "-g", "-s", "-k", "-I", "-L", "-P")
                i += 2 if takes_value else 1
            # timeout takes a duration before the command.
            if i < len(seg) and re.match(r"^\d+[smhd]?$", seg[i]):
                i += 1
            continue
        break
    return seg[i:]


def analyse(text, depth=0):
    if depth > 5:
        raise Blocked("The command nests shells too deeply to read.")
    for body in substitutions(text):
        analyse(body, depth + 1)
    try:
        tokens = words(text)
    except ValueError:
        if "git" in text:
            raise Blocked("The command has unbalanced quotes, so the hook cannot read it.")
        return
    for seg in segments(tokens):
        seg = strip_prefix(seg)
        if not seg:
            continue
        prog = os.path.basename(seg[0])
        if prog == "git":
            check_git(seg[1:])
        elif prog in SHELLS:
            for j, w in enumerate(seg[1:], 1):
                if w.startswith("-") and not w.startswith("--") and "c" in w and j + 1 < len(seg):
                    analyse(seg[j + 1], depth + 1)
                    break
        elif prog == "eval":
            analyse(" ".join(seg[1:]), depth + 1)


def check_git(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-C", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2
            continue
        if a == "-c":
            key = args[i + 1].split("=", 1)[0].lower() if i + 1 < len(args) else ""
            if key == "core.hookspath" or key.startswith("alias."):
                raise Blocked("git -c %s changes which hooks or aliases run. A subagent may not." % key)
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1:]
    if sub in READ_ONLY:
        return
    guard = GUARDS.get(sub)
    if guard is None:
        raise Blocked('"git %s" changes git state. A subagent may not run it.' % sub)
    guard(rest)


def positionals(rest, takes_value=()):
    out, skip = [], False
    for a in rest:
        if skip:
            skip = False
            continue
        if a in takes_value:
            skip = True
            continue
        if not a.startswith("-"):
            out.append(a)
    return out


def guard_config(rest):
    reads = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
    if not reads & set(rest):
        raise Blocked("A subagent may only read git config, with --get or --list.")


def guard_add(rest):
    blanket_flags = {"-A", "--all", "-u", "--update", "--no-ignore-removal",
                     "-p", "--patch", "-i", "--interactive", "-e", "--edit",
                     "-f", "--force"}
    blanket_paths = {".", "./", ":", ":/", "*", "*.*", "..", "../", "../.."}
    paths = []
    for a in rest:
        if a in blanket_flags:
            raise Blocked("git add %s stages more than the paths you name. Stage explicit paths instead." % a)
        if a in blanket_paths:
            raise Blocked('git add %s is blanket staging. It collects scratch files, local config, and secrets. Stage explicit paths instead.' % a)
        if a != "--" and not a.startswith("-"):
            paths.append(a)
    if not paths:
        raise Blocked('Name the paths to stage. "git add" without an explicit path is not allowed.')


def guard_commit(rest):
    bypass = {"-a", "--all", "-n", "--no-verify", "--amend", "-i", "--include",
              "--interactive", "-p", "--patch"}
    value_flags = set("mFCct")
    skip = False
    for a in rest:
        if skip:
            skip = False
            continue
        if a in bypass:
            raise Blocked("Commit only what you staged, and never bypass a hook. -a, -n, --no-verify, --amend, and interactive mode are all blocked.")
        if a.startswith("--"):
            if a in ("--message", "--file", "--reuse-message", "--reedit-message", "--template", "--author", "--date", "--cleanup", "--fixup", "--squash", "--trailer"):
                skip = True
            continue
        if a.startswith("-") and len(a) > 1:
            if a.startswith("-u"):
                continue
            for pos, ch in enumerate(a[1:]):
                if ch in "anp":
                    raise Blocked("Commit only what you staged, and never bypass a hook. -a, -n, --no-verify, --amend, and interactive mode are all blocked.")
                if ch in value_flags:
                    # The rest of the group, or the next word, is the value.
                    skip = pos == len(a) - 2
                    break


def guard_branch(rest):
    read_flags = {"--show-current", "--list", "-l", "-a", "--all", "-r",
                  "--remotes", "-v", "-vv", "--verbose", "--no-color", "--color",
                  "--column", "--no-column", "-i", "--ignore-case", "--abbrev",
                  "--no-abbrev", "--omit-empty"}
    value_flags = {"--contains", "--no-contains", "--merged", "--no-merged",
                   "--points-at", "--format", "--sort"}
    listing = "--list" in rest or "-l" in rest
    skip = False
    for a in rest:
        if skip:
            skip = False
            continue
        if a in value_flags:
            skip = True
            continue
        if a.split("=", 1)[0] in value_flags or a in read_flags:
            continue
        if not a.startswith("-") and listing:
            continue
        raise Blocked("A subagent may list branches, but not create, rename, move, or delete one.")


def guard_listing_only(name, allowed):
    def guard(rest):
        pos = positionals(rest)
        if not pos or pos[0] not in allowed:
            if name == "remote" and not pos:
                return
            raise Blocked('A subagent may only run "git %s %s".' % (name, " | ".join(sorted(allowed))))
    return guard


def guard_reflog(rest):
    pos = positionals(rest)
    if pos and pos[0] in ("expire", "delete"):
        raise Blocked("git reflog %s destroys the history that recovers lost work." % pos[0])


GUARDS = {
    "config": guard_config,
    "add": guard_add,
    "commit": guard_commit,
    "branch": guard_branch,
    "worktree": guard_listing_only("worktree", {"list"}),
    "stash": guard_listing_only("stash", {"list", "show"}),
    "remote": guard_listing_only("remote", {"show", "get-url"}),
    "reflog": guard_reflog,
}

try:
    command = json.loads(os.environ["HOOK_PAYLOAD"]).get("tool_input", {}).get("command", "")
    analyse(command)
except Blocked as e:
    with open(os.environ["HOOK_OUT"], "w") as f:
        f.write(str(e))
    sys.exit(3)
except Exception:
    sys.exit(4)
PY
code=$?

case "$code" in
  0) exit 0 ;;
  3) block "$(cat "$out")" ;;
  *)
    # The payload did not parse, or the analysis crashed.
    [ "$mentions_git" -eq 1 ] && block "The hook could not read this command, and it mentions git."
    exit 0
    ;;
esac
