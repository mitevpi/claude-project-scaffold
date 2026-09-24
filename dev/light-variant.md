<!-- The two fragments that make CLAUDE-light.md differ from CLAUDE-template.md.
dev/build-light.py puts each one in place of its FULL counterpart, then renames the
base branch from {{feature-dev}} to {{main}} inside the Branch model subsection. Edit
these fragments, never CLAUDE-light.md itself. -->

<!-- usage -->
LIGHT variant. Use it for a solo or small repo where you own `main` and no release
branch stands between you and it. When `main` is protected, when other people share
the repo, or when releases come from a separate branch, use `CLAUDE-template.md`
instead. The two files differ only in the Git section's branch model.
<!-- base-bullets -->
- **The base branch is `{{main}}`.** You own it. Commit to it directly for a small,
  finished, tested change. Cut a branch for anything larger.
- **Cut one short-lived branch per plan or task from `{{main}}`.** Never reuse a branch
  for unrelated work. You may create these without permission.
