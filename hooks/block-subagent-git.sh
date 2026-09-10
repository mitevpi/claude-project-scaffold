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
#   1. Read history and state: status, diff, log, show, and the rest of
#      ALLOWED below.
#   2. Stage explicit paths with "git add <path>".
#   3. Commit its own work with "git commit".
#
# Reason 3 matters: superpowers:subagent-driven-development requires every
# implementer subagent to commit its task, and the controller then diffs the
# BASE..HEAD range to build the review package. A hook that blocks the commit
# breaks that whole workflow.
#
# What stays with the orchestrator: every command that reshapes the
# repository or publishes it. push, reset, checkout, switch, restore, branch,
# merge, rebase, cherry-pick, revert, clean, stash, tag, worktree, and the
# rest.
#
# Two written CLAUDE.md rules become mechanical here:
#   - "Stage explicit paths. Do not run git add -A." Blanket staging is
#     blocked: -A, --all, -u, ".", ":/", and interactive mode.
#   - "Never bypass a hook." git commit --no-verify and -n are blocked, and
#     so are -a (which stages everything) and --amend (which rewrites a
#     commit the orchestrator may already own).
#
# How it decides:
#   1. The PreToolUse payload arrives on stdin as JSON.
#   2. The fields agent_id and agent_type appear only for a subagent call. If
#      neither field is present, the hook exits 0 and allows the command.
#   3. The hook splits the command on shell separators and inspects every
#      segment that invokes git.
#   4. A git segment is allowed only when its subcommand is on ALLOWED below,
#      and only when it passes that subcommand's argument guard. An allowlist
#      fails safe: a new or unknown subcommand is blocked, not permitted.
#
# Exit codes: 0 allows the call. 2 blocks it and returns the stderr text to
# the agent as the reason.
#
# Fail-open by design: if the hook cannot parse the payload, it allows the
# call. A hook that blocks on its own errors would stall every session. The
# deny rules in settings.json still apply in that case, and they apply to the
# main session too.

set -u

READ_OK="status diff log show blame describe rev-parse rev-list ls-files ls-tree cat-file grep shortlog for-each-ref count-objects var config"
ALLOWED="$READ_OK add commit"

payload=$(cat)

# --- 1. Is the caller a subagent? --------------------------------------------
case "$payload" in
  *'"agent_id"'* | *'"agent_type"'*) ;;
  *) exit 0 ;;
esac

# --- 2. Extract the command string -------------------------------------------
command_string=""
if command -v python3 >/dev/null 2>&1; then
  command_string=$(
    printf '%s' "$payload" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("tool_input", {}).get("command", ""))' 2>/dev/null
  )
elif command -v jq >/dev/null 2>&1; then
  command_string=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
fi

# No interpreter, or no command field: allow. See "Fail-open by design" above.
[ -n "$command_string" ] || exit 0

# --- 3. Inspect every git segment --------------------------------------------
# Replace shell separators with newlines so each segment is checked alone.
# tr is used instead of sed because BSD sed (macOS) does not emit \n in a
# replacement. "&&" and "||" become two newlines; an empty segment is harmless.
segments=$(printf '%s' "$command_string" | tr ';|&' '\n\n\n')

blocked=""
reason=""
old_ifs=$IFS
IFS='
'
for segment in $segments; do
  # Drop leading wrappers that the permission system also strips.
  cleaned=$(printf '%s' "$segment" | sed -E 's/^[[:space:]]*//; s/^(sudo|env|time|timeout [^ ]+|nice|nohup|stdbuf [^ ]+|command|builtin|noglob)[[:space:]]+//g')

  case "$cleaned" in
    git\ * | git)
      # Replace every quoted string with a single placeholder token, so that
      # a commit message cannot be mistaken for a flag. Without this,
      # git commit -m "use --amend with care" reads as an --amend call.
      stripped=$(printf '%s' "$cleaned" | sed -E 's/"[^"]*"/QSTR/g'"; s/'[^']*'/QSTR/g")

      # Split the segment into tokens. IFS is a newline in this loop, so it
      # must go back to whitespace for the split, then return.
      saved_ifs=$IFS
      IFS=' 	'
      # shellcheck disable=SC2086
      set -- $stripped
      IFS=$saved_ifs
      shift 2>/dev/null || true   # drop the "git" token itself

      subcommand=""
      blanket=0        # add: a blanket pathspec or flag is present
      explicit_path=0  # add: at least one explicit path is named
      bypass=0         # commit: staging or hook bypass, or a history rewrite
      config_read=0    # config: a read form is present

      for arg in "$@"; do
        if [ -z "$subcommand" ]; then
          case "$arg" in
            -*) continue ;;
            *) subcommand=$arg; continue ;;
          esac
        fi

        case "$subcommand" in
          add)
            case "$arg" in
              -A|--all|-u|--update|--no-ignore-removal|-p|--patch|-i|--interactive|-e|--edit)
                blanket=1 ;;
              .|./|:|:/|'*'|'*.*')
                blanket=1 ;;
              --) ;;
              -*) ;;
              *) explicit_path=1 ;;
            esac
            ;;
          commit)
            case "$arg" in
              -a|--all|-n|--no-verify|--amend|-i|--interactive|-p|--patch)
                bypass=1 ;;
              --) ;;
              --*) ;;
              -*)
                # A bundled short group such as -am or -nm.
                case "$arg" in
                  *a* | *n*) bypass=1 ;;
                esac
                ;;
              *) ;;
            esac
            ;;
          config)
            case "$arg" in
              --get|--get-all|--get-regexp|--get-urlmatch|--list|-l) config_read=1 ;;
            esac
            ;;
        esac
      done

      [ -n "$subcommand" ] || subcommand="(none)"

      # A case match is used instead of a loop over $ALLOWED, because IFS is
      # set to a newline here and word splitting on spaces would not happen.
      case " $ALLOWED " in
        *" $subcommand "*) allowed=1 ;;
        *) allowed=0; this_reason="A subagent must not change git state." ;;
      esac

      if [ "$allowed" -eq 1 ]; then
        case "$subcommand" in
          config)
            # "git config" may only be read, never set.
            if [ "$config_read" -eq 0 ]; then
              allowed=0
              this_reason="A subagent may only read git config, with --get or --list."
            fi
            ;;
          add)
            if [ "$blanket" -eq 1 ]; then
              allowed=0
              this_reason="Blanket staging collects scratch files, local config, and secrets. Stage explicit paths instead."
            elif [ "$explicit_path" -eq 0 ]; then
              allowed=0
              this_reason="Name the paths to stage. \"git add\" without an explicit path is not allowed."
            fi
            ;;
          commit)
            if [ "$bypass" -eq 1 ]; then
              allowed=0
              this_reason="Commit only what you staged, and never bypass a hook. -a, -n, --no-verify, --amend, and interactive mode are all blocked."
            fi
            ;;
        esac
      fi

      if [ "$allowed" -eq 0 ]; then
        blocked="$subcommand"
        reason="$this_reason"
      fi
      ;;
  esac
done
IFS=$old_ifs

[ -z "$blocked" ] && exit 0

# --- 4. Block ----------------------------------------------------------------
cat >&2 <<EOF
Blocked: a subagent may not run "git $blocked".

$reason

A subagent may read history and state, stage explicit paths, and commit its
own work. Every command that reshapes or publishes the repository belongs to
the orchestrator, which performs each branch operation, merge, and push after
the wave lands.

Allowed for a subagent: git $(printf '%s' "$ALLOWED" | tr ' ' ',' | sed 's/,/, /g').
Also allowed: git add <explicit path>, and git commit without -a, -n,
--no-verify, or --amend.

If this work needs a git operation you cannot run, stop and report that to the
orchestrator instead. See the "Parallel agents" section of CLAUDE.md.
EOF
exit 2
