#!/usr/bin/env bash
# review-package.sh — write one commit range to a file for a reviewer.
#
# Usage:
#   .claude/scripts/review-package.sh <base> <head>
#
# It writes the commit list, the diff stat, and the full diff of base..head to
# .superpowers/reviews/<base>-<head>.md, and prints that file's path.
#
# Why it exists: the reviewer agent holds no shell, so that it cannot change
# anything. But superpowers:requesting-code-review hands its reviewer a
# template that runs "git diff" itself. The orchestrator runs this script
# first and gives the reviewer the path instead. superpowers:subagent-driven-
# development has its own review-package script for per-task reviews; this one
# covers every other review.
#
# The directory ignores itself, so the package never shows in git status and
# never lands in a commit, even in a repository whose .gitignore lacks the
# .superpowers/ entry.
#
# Exit codes: 0 written. 1 a revision did not resolve. 2 usage error.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: review-package.sh <base> <head>" >&2
  exit 2
fi

base_sha=$(git rev-parse --verify -q "$1^{commit}") || { echo "unknown revision: $1" >&2; exit 1; }
head_sha=$(git rev-parse --verify -q "$2^{commit}") || { echo "unknown revision: $2" >&2; exit 1; }

dir="$(git rev-parse --show-toplevel)/.superpowers/reviews"
mkdir -p "$dir"
[ -f "$dir/.gitignore" ] || printf '*\n' > "$dir/.gitignore"

# The diff uses three dots: it runs from the merge base, so it shows what the
# branch changed. Two dots would also show every commit the base gained after
# the branch started, as a reverse change the reviewer would blame on the branch.
file="$dir/${base_sha:0:10}-${head_sha:0:10}.md"
{
  echo "# Review package: ${base_sha:0:10}..${head_sha:0:10}"
  echo
  echo "## Commits"
  echo
  git log --format='- %h %s' "$base_sha..$head_sha"
  echo
  echo "## Diff stat"
  echo
  echo '```'
  git diff --stat "$base_sha...$head_sha"
  echo '```'
  echo
  echo "## Diff"
  echo
  echo '```diff'
  git diff -U10 "$base_sha...$head_sha"
  echo '```'
} > "$file"

echo "$file"
