#!/usr/bin/env bash
# land-branch.sh: land one finished branch on its base branch, safely.
#
# Usage:
#   .claude/scripts/land-branch.sh [--check <cmd>] <branch> <base> [-C <repo>]
#   .claude/scripts/land-branch.sh --rebase-only [--check <cmd>] <branch> <base> [-C <repo>]
#
# It rebases <branch> onto <base>, fast-forwards <base>, removes the branch's
# worktree, and deletes the branch. It works whether or not either branch is
# checked out, and in whichever worktree it is checked out.
#
# --check runs <cmd> through sh in the rebased branch's checkout, after the
# rebase and before the fast-forward. A failing check stops the landing, so
# the base never moves to a combination that fails. Pass the project's full
# test, lint, and typecheck command. A branch that is checked out nowhere is
# checked in a temporary worktree, which holds no installed dependencies.
#
# --rebase-only stops after the rebase, and after the check when one is given.
#
# Why a script and not a sequence in CLAUDE.md: the written sequence failed in a
# worktree ("already used by worktree"), and a failed step is where an agent
# improvises. The improvisation is where work gets lost. This script refuses
# instead, and every refusal leaves the work exactly where it was.
#
# What it never does:
#   - force anything. No --force, no -D, no reset. Every git step is one that
#     git itself refuses when it would lose work.
#   - land a branch whose worktree holds uncommitted or untracked files.
#   - leave a rebase half done. A conflict aborts the rebase and stops.
#   - remove a worktree outside .worktrees/, worktrees/, or the harness's
#     subagent worktrees in .claude/worktrees/agent-*. Every other worktree
#     belongs to another session. The commits land; the worktree and the
#     branch stay. The harness locks a subagent worktree while its agent
#     runs, and git refuses to remove a locked worktree.
#
# Exit codes: 0 landed. 1 refused, and nothing was lost. 2 usage error.

set -uo pipefail

branch=""
base=""
repo="."
rebase_only=0
check=""

while [ $# -gt 0 ]; do
  case "$1" in
    -C)
      [ $# -ge 2 ] || { echo "-C needs a repository path" >&2; exit 2; }
      repo=$2; shift 2 ;;
    --rebase-only) rebase_only=1; shift ;;
    --check)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "--check needs a command" >&2; exit 2; }
      check=$2; shift 2 ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$branch" ]; then branch=$1
      elif [ -z "$base" ]; then base=$1
      else echo "too many arguments" >&2; exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$branch" ] || [ -z "$base" ]; then
  echo "usage: land-branch.sh [--rebase-only] [--check <cmd>] <branch> <base> [-C <repo>]" >&2
  exit 2
fi

g() { git -C "$repo" "$@"; }
refuse() { echo "Refused: $*" >&2; echo "Nothing was changed that loses work." >&2; exit 1; }
say() { echo "  $*"; }

g rev-parse --git-dir >/dev/null 2>&1 || refuse "$repo is not a git repository."
[ "$branch" != "$base" ] || refuse "the branch and the base are the same branch."
g rev-parse --verify -q "refs/heads/$branch" >/dev/null || refuse "no local branch named '$branch'."
g rev-parse --verify -q "refs/heads/$base" >/dev/null || refuse "no local branch named '$base'."

# --- Where is each branch checked out? -----------------------------------------
# The first entry of "worktree list" is always the main worktree.
checkout_of() {
  g worktree list --porcelain | awk -v ref="refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " ref { print path; exit }'
}
main_wt=$(g worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')
branch_wt=$(checkout_of "$branch")
base_wt=$(checkout_of "$base")
# From here on, run git from the main worktree by its absolute path. The
# caller may sit inside the branch's worktree, which step 3 removes, and a
# git command run from a deleted directory fails.
repo=$main_wt

is_dirty() { [ -n "$(git -C "$1" status --porcelain)" ]; }

# new_scratch: a free path for a temporary worktree. git creates the
# directory itself. The explicit template under $TMPDIR matters: on macOS a
# bare mktemp ignores TMPDIR and writes to /var/folders, which Claude Code's
# sandbox denies.
new_scratch() {
  d=$(mktemp -d "${TMPDIR:-/tmp}/land-branch.XXXXXX") || return 1
  rmdir "$d" && printf '%s\n' "$d"
}

if [ -n "$branch_wt" ] && is_dirty "$branch_wt"; then
  git -C "$branch_wt" status --short >&2
  refuse "$branch_wt holds uncommitted or untracked work. Commit it, or ask the owner."
fi

# --- 1. Rebase the branch onto the base -----------------------------------------
if g merge-base --is-ancestor "$base" "$branch"; then
  say "no rebase needed: $branch already contains $base"
else
  scratch=""
  where=$branch_wt
  if [ -z "$where" ]; then
    # The branch is checked out nowhere. Rebase it in a temporary worktree, so
    # that no checkout that someone else may be using ever moves.
    scratch=$(new_scratch)
    g worktree add -q "$scratch" "$branch" || refuse "could not create a temporary worktree to rebase in."
    where=$scratch
  fi
  if ! git -C "$where" rebase -q "$base" >/dev/null 2>&1; then
    git -C "$where" rebase --abort >/dev/null 2>&1
    [ -n "$scratch" ] && g worktree remove "$scratch" >/dev/null 2>&1
    refuse "$branch does not rebase cleanly onto $base. The rebase was aborted. Resolve the conflict on the branch first."
  fi
  [ -n "$scratch" ] && g worktree remove "$scratch"
  say "rebased $branch onto $base"
fi

# --- 2. Check the rebased branch ---------------------------------------------
if [ -n "$check" ]; then
  scratch=""
  where=$branch_wt
  if [ -z "$where" ]; then
    scratch=$(new_scratch)
    g worktree add -q --detach "$scratch" "$branch" || refuse "could not create a temporary worktree to run the check in."
    where=$scratch
  fi
  say "checking $branch: $check"
  (cd "$where" && sh -c "$check")
  check_code=$?
  # No --force here either. A check that wrote untracked files into the
  # temporary worktree leaves it in place, and the message names it.
  if [ -n "$scratch" ] && ! g worktree remove "$scratch" >/dev/null 2>&1; then
    say "kept the temporary worktree $scratch: the check left files in it"
  fi
  [ "$check_code" -eq 0 ] \
    || refuse "the check failed on the rebased $branch (exit $check_code). $base did not move."
  say "the check passed"
fi

if [ "$rebase_only" -eq 1 ]; then
  if [ -n "$check" ]; then
    echo "Rebased and checked $branch on $base. Nothing landed. Run again without --rebase-only to land."
  else
    echo "Rebased $branch onto $base. Nothing landed. Test the branch, then run again without --rebase-only."
  fi
  exit 0
fi

# --- 3. Fast-forward the base ---------------------------------------------------
if [ -n "$base_wt" ]; then
  # merge --ff-only refuses when it would overwrite local changes in that
  # checkout, so work in progress there is safe.
  git -C "$base_wt" merge -q --ff-only "$branch" \
    || refuse "could not fast-forward $base in $base_wt. $branch is rebased and intact."
else
  # The base is checked out nowhere. A fetch from the repository itself
  # updates the ref, and without a leading "+" it refuses anything but a
  # fast-forward.
  g fetch -q . "refs/heads/$branch:refs/heads/$base" \
    || refuse "could not fast-forward $base. $branch is rebased and intact."
fi
say "fast-forwarded $base to $(g rev-parse --short "$base")"

# --- 4. Remove the worktree, but only one this workflow owns ---------------------
root=$(cd "$main_wt" && pwd -P)
owned=0
if [ -n "$branch_wt" ]; then
  wt_real=$(cd "$branch_wt" && pwd -P)
  case "$wt_real" in
    "$root"/.worktrees/* | "$root"/worktrees/* | "$root"/.claude/worktrees/agent-*) owned=1 ;;
  esac
  if [ "$owned" -eq 0 ]; then
    say "kept $branch_wt: it is not a wave or subagent worktree, so another session owns it"
    say "kept the branch $branch, because that worktree still has it checked out"
    echo "Landed $branch on $base."
    exit 0
  fi
  if [ -d "$branch_wt/.superpowers/sdd" ]; then
    say "note: removing $branch_wt also deletes its git-ignored .superpowers/sdd ledger"
  fi
  # No --force. git refuses to remove a worktree with uncommitted work.
  g worktree remove "$branch_wt" \
    || refuse "could not remove $branch_wt. $base is landed. Remove the worktree by hand after you check it."
  say "removed the worktree $branch_wt"
fi

# --- 5. Delete the branch ---------------------------------------------------------
# -d, never -D: git refuses to delete a branch that is not merged. Run it where
# the base is checked out, because -d measures "merged" against HEAD.
if [ -n "$base_wt" ]; then
  git -C "$base_wt" branch -q -d "$branch" || say "kept the branch $branch: git did not confirm it is merged"
elif g merge-base --is-ancestor "$branch" "$base"; then
  # The base is checked out nowhere, so HEAD is some other branch and -d
  # would compare against the wrong thing. Delete the ref only if it still
  # points at the commit that was just landed.
  g update-ref -d "refs/heads/$branch" "$(g rev-parse "refs/heads/$branch")"
fi
if g show-ref --verify -q "refs/heads/$branch"; then
  say "kept the branch $branch"
else
  say "deleted the branch $branch"
fi

echo "Landed $branch on $base."
