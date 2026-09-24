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
# worktree, a stash, or a remote, and the rest. land-branch.sh is blocked
# too, because it rebases and deletes a branch where the hook cannot see it.
#
# Two written CLAUDE.md rules become mechanical here:
#   - "Stage explicit paths. Do not run git add -A." Blanket staging is
#     blocked: -A, --all, -u, --force, interactive mode, and a pathspec that
#     names the whole tree, such as ".", ":/", "*", or "$PWD".
#   - "Never bypass a hook." git commit --no-verify and -n are blocked, and so
#     are core.hooksPath through -c, --config-env, or GIT_CONFIG_*, and
#     HUSKY=0. So are -a (which stages everything), a pathspec on commit
#     (which commits unstaged work), and --amend (which rewrites a commit the
#     orchestrator may already own).
#
# git accepts any unique prefix of a long option, so "--amen" is "--amend".
# The guards treat an option as dangerous when it is a prefix of a dangerous
# one, and they read a group of short flags such as "-fv" letter by letter.
#
# How it decides:
#   1. The PreToolUse payload arrives on stdin as JSON.
#   2. The field agent_id appears only for a subagent call. Without it, the
#      hook exits 0 at once. agent_type alone is not enough: it is also set
#      for a main session started with "claude --agent".
#   3. The command is split into shell words and segments. Every git command
#      is inspected wherever it sits: after a path (/usr/bin/git), after
#      env (including env -S), nohup, xargs, watch, or a variable assignment,
#      inside $(...), `...`, a subshell, a { } group, an if or a for body,
#      bash -c, sh -c, eval, find -exec, or a heredoc fed to a shell.
#   4. A command whose name is built at run time, such as "$G push", is
#      blocked when the command mentions git, because the hook cannot know
#      what it runs.
#   5. A git command is allowed only when its subcommand is on the allowlist
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
    "show-ref", "show-branch", "ls-remote", "diff-tree", "diff-files",
    "diff-index", "verify-commit", "verify-tag", "help", "version",
}
SEPARATORS = {";", "&&", "||", "|", "|&", "&", "(", ")", "{", "}", "\n", ";;"}
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while",
            "until", "for", "in", "case", "esac", "!", "time"}
WRAPPERS = {"sudo", "doas", "env", "nohup", "nice", "ionice", "timeout",
            "stdbuf", "command", "builtin", "exec", "noglob", "xargs",
            "caffeinate", "watch", "chronic", "unbuffer"}
WRAPPER_VALUE_FLAGS = {"-n", "-u", "-g", "-s", "-k", "-I", "-L", "-P", "-c"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
# Scripts that run orchestrator-only git commands where the hook cannot see them.
ORCHESTRATOR_SCRIPTS = {"land-branch.sh"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Variables that switch off git hooks: GIT_CONFIG_* can set core.hooksPath,
# and HUSKY=0 disables husky.
HOOK_ENV = re.compile(r"^(GIT_CONFIG\w*|HUSKY)=")
GIT_WORD = re.compile(r"\bgit\b", re.I)
HEREDOC = re.compile(r"<<(-?)[ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|\\?([^\s;&|()<>]+))")

CWD = ""


class Blocked(Exception):
    pass


def scan(text, i=0, inner=False):
    """Walk shell text the way the shell quotes it.

    Returns (flat, subs, bodies, end). flat is the text with every heredoc
    body cut out, so that shlex can split it. subs holds the body of every
    $(...) and `...`. bodies holds the lines of every heredoc. With inner
    set, the walk starts inside a $( and stops at its closing parenthesis,
    and end is the index of that parenthesis. Raises ValueError on an
    unbalanced quote or parenthesis.
    """
    flat, subs, bodies, pending = [], [], [], []
    n, dq, depth = len(text), False, 0
    while i < n:
        c = text[i]
        if c == "\\":
            flat.append(text[i:i + 2])
            i += 2
            continue
        if c == "'" and not dq:
            j = text.find("'", i + 1)
            if j < 0:
                raise ValueError("unbalanced quote")
            flat.append(text[i:j + 1])
            i = j + 1
            continue
        if c == '"':
            dq = not dq
            flat.append(c)
            i += 1
            continue
        if c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                raise ValueError("unbalanced backtick")
            subs.append(text[i + 1:j])
            flat.append(text[i:j + 1])
            i = j + 1
            continue
        if text.startswith("$(", i):
            _, _, _, end = scan(text, i + 2, inner=True)
            subs.append(text[i + 2:end])
            flat.append(text[i:end + 1])
            i = end + 1
            continue
        if not dq and text.startswith("<<", i) and not text.startswith("<<<", i):
            m = HEREDOC.match(text, i)
            if m:
                delim = next(g for g in m.groups()[1:] if g is not None)
                pending.append((delim, m.group(1) == "-"))
                flat.append(text[i:m.end()])
                i = m.end()
                continue
        if c == "\n" and not dq and pending:
            flat.append(c)
            i += 1
            for delim, strip_tabs in pending:
                body = []
                while i < n:
                    j = text.find("\n", i)
                    line = text[i:] if j < 0 else text[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if strip_tabs else line) == delim:
                        break
                    body.append(line)
                bodies.append(body)
            pending = []
            continue
        if inner and not dq:
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    return "".join(flat), subs, bodies, i
                depth -= 1
        flat.append(c)
        i += 1
    if inner or dq:
        raise ValueError("unbalanced quote or parenthesis")
    return "".join(flat), subs, bodies, n


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
        name = os.path.basename(w)
        if name in WRAPPERS:
            i += 1
            while i < len(seg) and (seg[i].startswith("-") or ASSIGNMENT.match(seg[i])):
                opt = seg[i]
                # env -S splits its argument into the command to run, and
                # appends the words that follow it.
                if name == "env" and (opt.startswith("-S") or opt.startswith("--split-string")):
                    if opt in ("-S", "--split-string"):
                        value, rest = (seg[i + 1] if i + 1 < len(seg) else ""), seg[i + 2:]
                    elif opt.startswith("--split-string="):
                        value, rest = opt.split("=", 1)[1], seg[i + 1:]
                    else:
                        value, rest = opt[2:], seg[i + 1:]
                    return strip_prefix(words(value) + rest)
                i += 2 if opt in WRAPPER_VALUE_FLAGS else 1
            # timeout takes a duration before the command.
            if i < len(seg) and re.match(r"^\d+(\.\d+)?[smhd]?$", seg[i]):
                i += 1
            continue
        break
    return seg[i:]


def analyse(text, depth=0):
    if depth > 6:
        raise Blocked("The command nests shells too deeply to read.")
    try:
        flat, subs, bodies, _ = scan(text)
        tokens = words(flat)
    except ValueError:
        if GIT_WORD.search(text):
            raise Blocked("The command has unbalanced quotes, so the hook cannot read it.")
        return
    for body in subs:
        analyse(body, depth + 1)
    for body in bodies:
        for line in body:
            analyse_data_line(line, depth + 1)
    for seg in segments(tokens):
        check_segment(seg, depth, text)


def analyse_data_line(line, depth):
    """Read one line of a heredoc. The line may be commands for a shell, or
    prose such as a commit message. A line that parses is read as commands.
    A line that does not parse, such as "Don't run git add -A", is prose:
    only a git command at the start of the line or after a separator counts."""
    try:
        scan(line)
        words(line)
    except ValueError:
        for m in re.finditer(r"(?:^|[;&|(]\s*)git\s+(.*)", line):
            check_git(m.group(1).split())
        return
    analyse(line, depth)


def check_segment(seg, depth, text):
    for w in seg:
        if HOOK_ENV.match(w) and GIT_WORD.search(text):
            raise Blocked("%s switches off git hooks. A subagent may not set it." % w.split("=", 1)[0])
    seg = strip_prefix(seg)
    if not seg:
        return
    cmd = seg[0]
    if ("$" in cmd or "`" in cmd) and GIT_WORD.search(text):
        raise Blocked("The command name %s is built at run time, so the hook cannot tell whether it runs git." % cmd)
    prog = os.path.basename(cmd)
    if prog in ORCHESTRATOR_SCRIPTS:
        raise Blocked("%s rebases, lands, and deletes a branch. That belongs to the orchestrator." % prog)
    if prog == "git":
        check_git(seg[1:])
    elif prog in SHELLS:
        for j, w in enumerate(seg[1:], 1):
            if w.startswith("--"):
                continue
            if w.startswith("-"):
                if "c" in w and j + 1 < len(seg):
                    analyse(seg[j + 1], depth + 1)
                    return
                continue
            if os.path.basename(w) in ORCHESTRATOR_SCRIPTS:
                raise Blocked("%s rebases, lands, and deletes a branch. That belongs to the orchestrator." % os.path.basename(w))
            return
    elif prog in ("source", "."):
        if len(seg) > 1 and os.path.basename(seg[1]) in ORCHESTRATOR_SCRIPTS:
            raise Blocked("%s rebases, lands, and deletes a branch. That belongs to the orchestrator." % os.path.basename(seg[1]))
    elif prog == "eval":
        analyse(" ".join(seg[1:]), depth + 1)
    elif prog == "find":
        for j, w in enumerate(seg):
            if w in ("-exec", "-execdir", "-ok", "-okdir"):
                sub = []
                for t in seg[j + 1:]:
                    if t in (";", "+", "\\;"):
                        break
                    sub.append(t)
                check_segment(sub, depth + 1, text)


def check_config_key(pair):
    key = pair.split("=", 1)[0].lower()
    if key == "core.hookspath" or key.startswith("alias."):
        raise Blocked("git -c %s changes which hooks or aliases run. A subagent may not." % key)


def check_git(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-C", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2
            continue
        if a in ("-c", "--config-env"):
            check_config_key(args[i + 1] if i + 1 < len(args) else "")
            i += 2
            continue
        if a.startswith("--config-env="):
            check_config_key(a.split("=", 1)[1])
            i += 1
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


def abbreviates(arg, options):
    """True when the long option arg names one of options, either whole or
    as a prefix that git would expand to it."""
    name = arg.split("=", 1)[0]
    return len(name) > 2 and any(o.startswith(name) for o in options)


def blanket_path(p):
    """True when the pathspec p can stage or commit more than the files it
    names: the whole tree, a glob, pathspec magic, or a path the shell builds
    at run time."""
    if not p or p.startswith(":") or "*" in p or "$" in p or "`" in p:
        return True
    norm = os.path.normpath(p)
    if norm == "." or all(part == ".." for part in norm.split("/")):
        return True
    if os.path.isabs(norm) and CWD:
        cwd = os.path.normpath(CWD)
        if norm == "/" or cwd == norm or cwd.startswith(norm + "/"):
            return True
    return False


def guard_config(rest):
    reads = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
    if not reads & set(rest):
        raise Blocked("A subagent may only read git config, with --get or --list.")


ADD_DANGER_LONG = ("--all", "--update", "--force", "--patch", "--interactive",
                   "--edit", "--no-ignore-removal", "--pathspec-from-file")
ADD_DANGER_SHORT = "Aufpie"


def guard_add(rest):
    paths, only_paths = [], False
    for a in rest:
        if only_paths or not a.startswith("-"):
            if blanket_path(a):
                raise Blocked('git add %s is blanket staging. It collects scratch files, local config, and secrets. Stage explicit paths instead.' % a)
            paths.append(a)
        elif a == "--":
            only_paths = True
        elif a.startswith("--"):
            if abbreviates(a, ADD_DANGER_LONG):
                raise Blocked("git add %s stages more than the paths you name. Stage explicit paths instead." % a)
        elif any(ch in ADD_DANGER_SHORT for ch in a[1:]):
            raise Blocked("git add %s stages more than the paths you name. Stage explicit paths instead." % a)
    if not paths:
        raise Blocked('Name the paths to stage. "git add" without an explicit path is not allowed.')


COMMIT_DANGER_LONG = ("--all", "--no-verify", "--amend", "--include",
                      "--interactive", "--patch", "--pathspec-from-file")
COMMIT_VALUE_LONG = ("--message", "--file", "--reuse-message", "--reedit-message",
                     "--template", "--author", "--date", "--cleanup", "--fixup",
                     "--squash", "--trailer")
COMMIT_BLOCKED = "Commit only what you staged, and never bypass a hook. -a, -n, --no-verify, --amend, and interactive mode are all blocked."


def guard_commit(rest):
    skip, only_paths = False, False
    for a in rest:
        if skip:
            skip = False
            continue
        if only_paths or not a.startswith("-") or a == "-":
            if blanket_path(a):
                raise Blocked('git commit %s commits every change under it, staged or not. Stage explicit paths, then commit.' % a)
            continue
        if a == "--":
            only_paths = True
            continue
        if a.startswith("--"):
            if abbreviates(a, COMMIT_DANGER_LONG):
                raise Blocked(COMMIT_BLOCKED)
            if "=" not in a and abbreviates(a, COMMIT_VALUE_LONG):
                skip = True
            continue
        for pos, ch in enumerate(a[1:]):
            if ch in "anpi":
                raise Blocked(COMMIT_BLOCKED)
            if ch in "mFCct":
                # The rest of the group, or the next word, is the value.
                skip = pos == len(a) - 2
                break
            if ch in "uS":
                # -u and -S take an optional value in the same word.
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
    if pos and pos[0] in ("expire", "delete", "drop"):
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
    data = json.loads(os.environ["HOOK_PAYLOAD"])
    CWD = data.get("cwd") or ""
    analyse(data.get("tool_input", {}).get("command", ""))
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
