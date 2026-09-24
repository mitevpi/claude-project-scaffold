# CLAUDE.md

<!--
TEMPLATE USAGE (delete this block once filled in)

LIGHT variant. Use it for a solo or small repo where you own `main` and no release
branch stands between you and it. When `main` is protected, when other people share
the repo, or when releases come from a separate branch, use `CLAUDE-template.md`
instead. The two files differ only in the Git section's branch model.

1. Fill every `{{PLACEHOLDER}}`. Delete any section that does not apply. An unfilled
   placeholder is worse than a missing section: it teaches the agent to guess.
2. Run `.claude/scripts/check-claude-md.sh`. It fails while a placeholder or this block
   remains, and it checks that the companion files and settings are in place.
3. Delete the Superpowers workflow section if you do not use the plugin. Sections refer
   to each other by name, so nothing else needs to change.
4. Budget: keep the filled-in file under ~260 lines. It is read in full in every
   session, so every line costs context in every turn. Move detail into `docs/` or a
   skill, and link it from here. Set CLAUDE_MD_LINE_BUDGET to change the check's limit.
5. For a non-Claude agent, symlink `AGENTS.md` to this file. Do not keep two copies.
-->

This is the internal operating manual for this repository. Claude reads it first, in every
session. `README.md` is the public document. `docs/` holds the long-form detail.

**Companion files in `.claude/` enforce parts of this manual. Do not delete them:** the
permission rules and hook registrations in `settings.json`, the `hooks/`, the subagent
tool grants in `agents/`, the `scripts/`, and the `skills/`.

## Project

- **What it is:** {{ONE_PARAGRAPH: what this project does, and who uses it}}
- **Status:** {{prototype | active development | maintained | frozen}}
- **Stack:** {{languages, frameworks, runtimes, package manager, versions}}
- **Entry points:** {{the files or directories to read first}}

### Architecture

{{The mental model that no single file contains: how the pieces fit, what calls what,
where the boundaries are. 5 to 15 lines. Put diagrams in `docs/architecture.md`.}}

### Invariants and gotchas

{{The things that break silently when someone violates them. This section repays the
effort faster than any other. Examples: "IDs are ULIDs, never sequential"; "the worker
assumes UTC"; "the app reads config once at boot and never reloads it".}}

## Commands

Every command needed to work in this repo. A stale command costs more than a missing one.

| Purpose | Command |
| --- | --- |
| Install deps | `{{...}}` |
| Dev server | `{{...}}` |
| Build | `{{...}}` |
| Test (full suite) | `{{...}}` |
| Test (single file) | `{{...}}` |
| Lint | `{{...}}` |
| Typecheck | `{{...}}` |
| Format | `{{...}}` |

- **Current test count:** {{N}}. Update it when you add or remove a test.
- **Ask before an expensive or slow operation:** {{the e2e suite, deploys, migrations,
  anything that costs money or touches production}}
- **Environment.** `{{.env.example}}` lists the required variables. Never commit a real
  value. The deny rules keep `.env` and its variants out of the Read tool.

## Superpowers workflow

The `superpowers` plugin's method is the default here. These rules settle only the points
where it and this repo would collide. Everything else follows the plugin.

- **Classification and the gate.** Use the plugin's classes, **spike**, **bounded**, and
  **architectural**, and announce the class. The approval gate holds on every path,
  including a one-line change. What scales with the task is the artifact, never the gate:
  a typo fix earns a one-sentence design in chat and a yes, not a spec file and not
  silence. Hidden complexity upgrades the path. Nothing downgrades mid-task.
- **Worktrees.** `superpowers:using-git-worktrees` may create one without asking: the one
  exception to the Git section. Prefer the harness's native tool. The fallback is
  `.worktrees/<branch>`, which `.gitignore` covers, never a directory outside the repo.
- **Specs and plans** keep the plugin's paths under `docs/superpowers/`, so that a plugin
  update never moves them. Commit each with its work. Do not polish it afterwards.
- **`.superpowers/`** holds the SDD ledger, task briefs, and review packages. It is
  git-ignored scratch. Never commit it. Removing a worktree deletes the ledger inside it,
  so land a worktree's branch only when its plan is finished.
- **Testing.** `superpowers:test-driven-development` is mandatory, with no exemption.
  Never disable, skip, or weaken a test to pass a suite. Fix a wrong test as its own change.
- **Executing a plan.** `superpowers:subagent-driven-development` works here: the git hook
  lets its implementers stage explicit paths and commit. Name a model tier in every
  dispatch, never a pinned version. An omitted model inherits this session's, which is
  normally the most expensive one. Per-task review: {{a mid tier}}. Whole-branch review:
  {{the most capable tier}}.
- **Templates and agents.** A Superpowers prompt template is the brief. The agent in
  `.claude/agents/` is the container that grants the tools, and the model named at
  dispatch overrides its `model:` field. The `reviewer` holds no shell. Before any review
  that the SDD scripts do not package, run `.claude/scripts/review-package.sh <base>
  <head>`, and give the reviewer the printed path in place of the template's git commands.
- **Finishing a branch.** `superpowers:finishing-a-development-branch` presents three
  options, and the choice belongs to the repo owner. Present the menu. Do not pre-empt it.
  **One override:** for option 1, land the branch with `land-branch.sh` from the Git
  section, not with the skill's `git merge`, and say so.

## Git

### Branch model

- **The base branch is `{{main}}`.** You own it. Commit to it directly for a small,
  finished, tested change. Cut a branch for anything larger.
- **Cut one short-lived branch per plan or task from `{{main}}`.** Never reuse a branch
  for unrelated work. You may create these without permission.
- **Land a branch with `.claude/scripts/land-branch.sh <branch> {{main}}`.** It
  rebases, fast-forwards the base, removes the branch's worktree, and deletes the branch,
  from any checkout, so that history stays linear. It asks the owner first, as `git merge`
  and `git rebase` do. It refuses, and loses nothing, when a worktree holds uncommitted
  work or the rebase conflicts: report the refusal and stop. Never land a branch by hand.
  When `{{main}}` tracks a remote, run `git pull --ff-only` in its checkout first.
- **Every other branch and worktree is off-limits without a request in that turn.** Do not
  switch to, merge, rebase onto, or delete one. Report a dirty tree at the start of a
  task. Never stash, reset, or commit someone else's work to reach a clean state.
- **Use `git switch` for branches and `git restore` for files.** `git checkout` does both,
  and can discard edits, so it asks first.

These git rules are a deliberate override of the plugin's defaults, not drift.

### Commits

- **Commit each coherent piece of finished work when it completes,** and only after its
  tests pass. Do not batch unrelated changes. Do not leave finished work uncommitted.
- **Stage explicit paths.** Never `git add -A`: blanket staging collects scratch files,
  local config, and secrets.
- **The commit belongs to the repo owner.** No `Co-Authored-By: Claude` trailer, no
  "Generated with Claude Code" line, and no other self-attribution. The `attribution`
  block in `settings.json` turns the harness default off. This rule covers what it misses.
- **Message format:** {{conventional commits | plain imperative subject}}. Keep the subject
  under 72 characters. The body explains why, not what.

### Never

`settings.json` denies most of these. The list stands where a rule does not reach.

- A force push of any kind, `--force-with-lease` included, or a rewrite of history you
  already pushed. The owner runs a force push by hand.
- `--no-verify`, or any other bypass of a hook, a linter, or CI.
- `git reset --hard`, `git clean`, a forced worktree removal, or anything else that
  destroys uncommitted work you did not create.
- A commit with a secret, a `.env` file, a credential, a large binary, or a vendored
  dependency. A push or a PR that nobody asked for in that request.

## Parallel agents

One destructive command from one agent acts on the whole repository. Read
`superpowers:dispatching-parallel-agents` and the `parallel-agent-safety` skill before a
wave. These rules are absolute. They override any plan, skill, or subagent prompt.

- **One session per checkout.** Two top-level sessions share one index and one working
  tree, and the git hook lets both stash and commit. Start each parallel session in its
  own worktree: `claude --worktree <name>`, or the desktop app's worktree option. The
  session-start hook lists uncommitted work and other worktrees. Work you did not make
  belongs to someone else: report it, and never stash, restore, or commit it.
- **Sequential is the default.** Fan out only for genuinely independent subtasks, and say
  why in one line first. Never fan out the tasks of a plan:
  `subagent-driven-development` is sequential by design.
- **One writer per file** for the whole wave. Two subtasks that need one file are one
  subtask. Keep every hotspot yourself: config, routes, registries, lockfiles,
  migrations, `README.md`, and this file.
- **At most {{MAX_PARALLEL_WRITERS: 3}} write-capable agents.** Read-only agents may go
  wider. A cheaper model needs a tighter scope, not a looser one.
- **Confirm a clean tree first, and give every writing agent its own worktree.** A
  worktree isolates files, not a database, a port, or a cache. Do not fan out writers at
  all when worktrees are disabled.
- **A subagent commits its own work and nothing more.** It may read history, stage
  explicit paths, and commit. The hook blocks every other git operation, and
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` stops it from spawning a subagent.
- **Grant tools. Do not request behaviour.** Use `researcher`, `reviewer`, and
  `implementer` from `.claude/agents/`. "Do not edit" in a prompt is not a control.
- **Land one branch at a time.** Read every diff yourself. Run the checks from the
  Commands section after each branch. The wave ends when the combined result passes, not
  when the agents return.

## Documentation

- **`CLAUDE.md`, this file:** the internal manual, read in full in every session. Keep it
  under ~260 lines. Move a topic that outgrows a short section to `docs/` or a skill.
- **`README.md`:** the public document. Thorough but short. Link into `docs/` for depth.
- **`docs/`:** everything long, each file with a one-line entry in `docs/index.md`.
  `docs/superpowers/` is the exception: the plugin owns it.

**Research output is a deliverable.** Write any research or open-ended answer to
`docs/research/{{slug}}.md` before the session ends, and cite every source. An answer that
lives only in the chat history is lost.

**Update triggers.** In the same commit as the change, revise this file, the README, and
the matching `docs/` entry whenever a change alters a command, adds or changes an
invariant, moves an architectural boundary, adds or removes a test, or adds a dependency.

## Code comments

Explain the **why**, not the **what**, so that an engineer new to this repo can change a
file safely. Comments land in the same commit as the code.

- Give every public API surface a doc comment in the language's standard form:
  {{TSDoc for TypeScript / PEP 257 docstrings for Python / rustdoc for Rust / ...}}.
- Explain the constraint behind every non-obvious decision, workaround, and invariant.
- Do not narrate the next line, restate a signature, or address a reviewer.
- **A comment that lies is worse than none.** Change it with the behaviour.

## Working agreements

### Verify before you conclude

Never invent a fact, a file path, a command, an API, a version, or a number. If you did
not read it or run it, you do not know it. This binds every subagent too.

- Label every claim. It is **verified** only when you ran the check or read the source.
  Label everything else **unverified**, and say what would verify it.
- Report what you observed, not what you expected. State anything unverified, unfinished,
  or broken first.
- When you lack the information to proceed, say what is missing. Offer options, each
  naming one action: a file to read, a command to run, a search, or a question.

### Definition of done

A task ends when all of these hold, and you observed each one in this session:

1. The tests pass. Run the real command from the Commands section.
2. Lint and typecheck are clean.
3. Comments and docs match the Documentation and Code comments sections.
4. The work sits committed on the correct branch.
5. You stated everything that is incomplete or uncertain.

### Stop and ask before

- You add, remove, or upgrade a dependency.
- You change a public API, a schema, or a data migration.
- You touch auth, payments, secrets, or anything user-facing and irreversible.
- You run a destructive or non-local operation: a deploy, production data, a force push.
- Two reasonable readings of a requirement exist. Ask once, and spell out both readings.

### Browser verification

Start a browser check only when someone asks for one. When you believe one is the best
diagnosis, say why and wait for a yes.

## Style

- **Write to the ASD-STE100 Simplified Technical English writing rules** in chat, docs,
  commits, comments, and briefs: active voice, one instruction per sentence, short
  sentences, simple tenses. Never drop a subject, a verb, or an article. The `ste-writing`
  skill holds the full rule set. Never claim STE compliance: that needs the ASD dictionary.
- Be concise. Cut a word that does not change the meaning. Keep a word the grammar needs.
- Do not use an em-dash in prose. Use a comma, a semicolon, or a colon.
- Use kebab-case for every new file and folder.
- Research reports use MLA citations and end with a full MLA bibliography.
