#!/usr/bin/env bash
# land-branch.sh — land one finished branch on its base branch, safely.
#
# Usage:
#   .claude/scripts/land-branch.sh <branch> <base> [-C <repo>]
#
# It rebases <branch> onto <base>, fast-forwards <base>, removes the branch's
# worktree, and deletes the branch. It works whether or not either branch is
# checked out, and in whichever worktree it is checked out.
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
#   - remove a worktree outside .worktrees/ or worktrees/. Those belong to
#     another session or to the harness. The commits land; the worktree and
#     the branch stay.
#
# Exit codes: 0 landed. 1 refused, and nothing was lost. 2 usage error.

set -uo pipefail

branch=""
base=""
repo="."

while [ $# -gt 0 ]; do
  case "$1" in
    -C) repo="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  echo "usage: land-branch.sh <branch> <base> [-C <repo>]" >&2
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

is_dirty() { [ -n "$(git -C "$1" status --porcelain)" ]; }

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
    scratch=$(mktemp -d)
    rmdir "$scratch"
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

# --- 2. Fast-forward the base ---------------------------------------------------
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

# --- 3. Remove the worktree, but only one this workflow owns ---------------------
root=$(cd "$main_wt" && pwd -P)
owned=0
if [ -n "$branch_wt" ]; then
  wt_real=$(cd "$branch_wt" && pwd -P)
  case "$wt_real" in
    "$root"/.worktrees/* | "$root"/worktrees/*) owned=1 ;;
  esac
  if [ "$owned" -eq 0 ]; then
    say "kept $branch_wt: it is not under .worktrees/, so another session or the harness owns it"
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

# --- 4. Delete the branch ---------------------------------------------------------
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
[ -z "$(g rev-parse --verify -q "refs/heads/$branch")" ] && say "deleted the branch $branch"

echo "Landed $branch on $base."
