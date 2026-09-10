# CLAUDE.md

<!--
TEMPLATE USAGE (delete this block once filled in)

FULL variant. Use it when `main` is protected, when other people share the repo, or
when releases come from a separate branch. For a solo or small repo where you own
`main`, use `CLAUDE-light.md` instead. The two files differ only in the git model.

1. Run `./install.sh <target-repo>` from the scaffold folder. It copies this file,
   `README-template.md`, the `.claude/` directory, and the `docs/` stubs into the
   target repo, and it appends the required `.gitignore` entries.
2. Fill every `{{PLACEHOLDER}}`. Delete any section that does not apply. An unfilled
   placeholder is worse than a missing section: it teaches the agent to guess.
3. Run `.claude/scripts/check-claude-md.sh` to confirm that no placeholder remains
   and that the companion files are in place.
4. This file assumes the `superpowers` plugin. Delete section 3 if you do not use it.
5. Budget: keep the filled-in file under ~340 lines, which is where it lands with
   section 3 kept, or ~270 lines without it. The file is read in full in every
   session, so every line costs context. Detail goes in `docs/` or into a skill, and
   gets linked from here. Lower the budget for a small project by setting
   CLAUDE_MD_LINE_BUDGET before you run the check script.
6. For a non-Claude agent, symlink `AGENTS.md` to this file. Do not keep two copies.
-->

This is the internal operating manual for this repository. Claude reads it first, in every
session. `README.md` holds the public documentation. `docs/` holds the long-form detail.

**Companion files.** `.claude/settings.json` holds the permission rules. `.claude/agents/`
holds the subagent definitions. `.claude/skills/` holds the `parallel-agent-safety` and
`ste-writing` procedures. `.claude/hooks/block-subagent-git.sh` limits what a subagent
may do to git. These files enforce parts of this manual. Do not delete them.

---

## 1. Project

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

---

## 2. Commands

This table holds every command needed to work in this repo. Keep it accurate. A stale
command costs more than a missing one.

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

- **Current test count:** {{N}}. Update this number when you add or remove a test.
- **Ask before an expensive or slow operation:** {{the e2e suite, deploys, migrations,
  anything that costs money or touches production}}
- **Environment.** `{{.env.example}}` lists the required variables and how to get them.
  Never commit a real value.

---

## 3. Superpowers workflow

The `superpowers` plugin is installed and its method is the default here. Its skills
trigger on their own. The rules below settle only the points where its defaults and
this repo's rules would otherwise collide. Anything not named below follows the plugin.

### Classification and the approval gate

`superpowers:brainstorming` classifies every request as a **spike**, a **bounded**
change, or an **architectural** one. Use that vocabulary and announce the class.

The approval gate holds on every path, including a one-line change. What scales with
the size of a task is the artifact, never the gate. A typo fix earns a one-sentence
design in chat and a yes. It does not earn a spec file, and it does not earn silence.

Hidden complexity upgrades the path. Say so and step up. Nothing downgrades mid-task.

### Isolated workspaces

Use `superpowers:using-git-worktrees`. It may create a workspace without asking. This
is the one exception to the branch-and-worktree rule in section 4.

- Prefer the harness's native worktree tool. Fall back to `git worktree add` only when
  no native tool exists.
- The fallback path is `.worktrees/<branch>` inside the repo. `.gitignore` covers it
  already. Do not use a sibling directory outside the repo.
- Remove the worktree when the branch lands.

### Specs and plans

Keep the plugin's own paths, so that a plugin update never moves them:

- `superpowers:brainstorming` writes `docs/superpowers/specs/<yyyy-mm-dd>-<topic>-design.md`
- `superpowers:writing-plans` writes `docs/superpowers/plans/<yyyy-mm-dd>-<feature>.md`

Commit both with the work they describe. They record intent at one point in time. Do
not polish them afterwards.

`.superpowers/` holds the subagent-driven-development ledger, the task briefs, and the
review packages. It is git-ignored scratch. Never commit it, and never run
`git clean -fdx` while a plan is running: it destroys the ledger.

### Testing

`superpowers:test-driven-development` is mandatory here. It enforces RED-GREEN-REFACTOR:
write the test, watch it fail, then make it pass. Delete and rewrite any code you wrote
before its test. Never disable, skip, or weaken a test to make a suite pass. Say so and
fix the test as its own change when a test is genuinely wrong.

### Executing a plan

`superpowers:subagent-driven-development` works in this repo. Its implementer subagents
stage explicit paths and commit their own tasks, and the `block-subagent-git` hook
allows exactly that. Section 5 holds the boundary.

- Name an explicit model tier in every dispatch. An omitted model inherits this
  session's, which is normally the most capable and most expensive one.
- When a Superpowers skill supplies a prompt template, that template is the brief. Use
  `.claude/agents/implementer.md` or `.claude/agents/reviewer.md` as the container that
  grants the tools. The model named at dispatch overrides the file's `model:` field.
- Name a model tier, never a pinned version string. The tiers outlive the version
  names. Per-task review: {{a mid tier}}. Whole-branch review: {{the most capable
  tier}}. Do not ask which; the plugin already requires both reviews.

### Finishing a branch

`superpowers:finishing-a-development-branch` presents three options and the choice
belongs to the repo owner. Present the menu. Do not pre-empt it.

**One override.** When the owner picks option 1, land the branch with the rebase and
fast-forward sequence in section 4, not with the `git merge` that the skill shows. Say
which sequence you are using. Section 4 explains why this repo keeps a linear history.

---

## 4. Git

### Branch model

- **The base branch is `{{feature-dev}}`, not `{{main}}`.** `{{main}}` belongs to the repo
  owner for releases. Never check it out, commit to it, merge into it, or delete it.
  Never delete `{{feature-dev}}` either. The owner promotes `{{feature-dev}}` to
  `{{main}}` by hand. Do not open or suggest a PR that targets `{{main}}`.
- **Cut one short-lived branch per plan or task from `{{feature-dev}}`.** Never reuse a
  branch for unrelated work. You may create these and merge them back into
  `{{feature-dev}}` without permission. Every other branch operation needs permission.
- **Land a branch by rebase, not by a merge commit.** This keeps each diff linear and
  small:

  ```
  git fetch origin
  git rebase {{feature-dev}}          # from the feature branch
  git switch {{feature-dev}}
  git merge --ff-only {{feature-branch}}
  git branch -d {{feature-branch}}    # immediately, so nothing stale lingers
  ```

- **Every other branch and worktree is off-limits without a request in that turn.** Do not
  switch to, merge, rebase onto, or delete one. Say so and wait if the work looks like it
  belongs somewhere else.
- **Stop and report a dirty working tree at the start of a task.** Never stash, reset, or
  commit someone else's work in progress to reach a clean state.

These git rules are a deliberate override of the plugin's defaults, not drift. Section 3
names the one place the two differ on mechanics.

### Commits

- **Commit each coherent piece of finished work when it completes**, and only after its
  tests pass. Do not batch unrelated changes. Do not leave finished work uncommitted.
- **The commit belongs to the repo owner.** Never add a `Co-Authored-By: Claude` trailer,
  a "Generated with Claude Code" line, or any other self-attribution. Leave the author
  and committer as the configured git signature. This overrides the harness default.
- **Stage explicit paths. Do not run `git add -A`.** Blanket staging collects scratch
  files, local config, and secrets.
- **Message format:** {{conventional commits | plain imperative subject}}. Keep the subject
  under 72 characters. The body explains why, not what.

### Never

`.claude/settings.json` denies most of these mechanically. The list stands even where a
deny rule does not reach.

- `git push --force` on a shared branch. Use `--force-with-lease` on your own branch only.
- `--no-verify`, or any other bypass of a hook, a linter, or CI.
- `git reset --hard`, `git checkout .`, `git clean -fd`, or anything else that destroys
  uncommitted work you did not create.
- A commit that contains a secret, a `.env` file, a credential, a large binary, or a
  vendored dependency.
- A rewrite of history that you already pushed.
- A push or a PR that nobody asked for in that request.

---

## 5. Parallel agents

One destructive command from one agent in a wave acts on the whole repository. Three
controls prevent that, in falling order of strength: the deny rules and the
`block-subagent-git` hook in `.claude/`, the tool grants in `.claude/agents/`, and the
rules below.

`superpowers:dispatching-parallel-agents` holds the dispatch pattern. The
`parallel-agent-safety` skill holds this repo's isolation procedure. Read both before
you launch a wave. The rules below are absolute, and they override any plan, any skill,
and any subagent prompt.

- **Sequential is the default.** Fan out only for genuinely independent subtasks. Say why
  in one line first. A plan goes through `subagent-driven-development`, which is
  sequential by design. Never fan out the tasks of a plan.
- **One writer per file.** One agent owns each file for the whole wave. Two subtasks that
  need the same file are one subtask. Keep every hotspot yourself: config, routes,
  registries, lockfiles, migrations, `README.md`, and this file.
- **At most {{MAX_PARALLEL_WRITERS: 3}} write-capable agents.** Read-only agents may go
  wider. A cheaper model needs a tighter scope, not a looser one.
- **Confirm a clean tree first.** Never fan out on top of uncommitted work.
- **Give every writing agent its own worktree.** A worktree isolates files. It does not
  isolate a database, a port, or a cache. Do not fan out writers at all when worktrees
  are disabled.
- **A subagent commits its own work and nothing more.** It may read history, stage
  explicit paths, and commit. It may not push, branch, merge, rebase, reset, checkout,
  stash, clean, tag, or create a worktree. The orchestrator owns every one of those, and
  the hook enforces the line.
- **No subagent spawns a subagent.** One level of fan-out only. A reviewer that an
  implementer spawned is a defect to report, not extra assurance.
- **Grant tools. Do not request behaviour.** Use `researcher`, `reviewer`, and
  `implementer` from `.claude/agents/`. "Do not edit" in a prompt is a preference, not a
  control.
- **Land one branch at a time.** Read every diff yourself. Run section 2's checks between
  each branch. The wave ends when the combined result passes, not when the agents return.

---

## 6. Documentation

Three surfaces do three jobs. That separation stops any one of them from bloating.

- **`CLAUDE.md`, this file.** The internal operating manual: commands, architecture,
  invariants, and working agreements. Keep it under ~340 lines, because it is read in
  full in every session. Move a topic to `docs/` or into a skill when it outgrows a
  short section, and leave a one-line link.
- **`README.md`.** The public document: what the project is, how it works, how to run it,
  and how to contribute. Keep it thorough but short. Link into `docs/` for depth.
- **`docs/`.** Everything long: architecture, decisions, research, and plans. Give each
  file a one-line entry in `docs/index.md`. `docs/superpowers/` is the exception: the
  plugin owns it, and the directory is its own index.

**Research output is a deliverable.** Write any research or open-ended answer to
`docs/research/{{slug}}.md` before the session ends. Cite every source. An answer that
lives only in the chat history is lost.

**Update triggers.** Revise this file, the README, and the matching `docs/` entry in the
same commit as the change, whenever a change alters a command, adds or changes an
invariant, moves an architectural boundary, adds or removes a test, or adds a dependency.

---

## 7. Code comments

Explain the **why**, not the **what**. The bar: an engineer new to this repo reads a file
and understands the intent, the constraints, and how to change it safely. This is not
optional polish. It lands in the same commit as the code.

- Give every public API surface a doc comment in the standard form for the language:
  {{TSDoc for TypeScript / PEP 257 docstrings for Python / rustdoc for Rust / ...}}.
- Explain the constraint behind every non-obvious decision, workaround, and invariant.

Do not narrate the next line (`// increment i`), restate a type signature in prose, or
address a reviewer (`// changed this to fix the bug`). Git holds the history. A comment
describes the code as it stands now.

**A comment that lies is worse than no comment.** Change the comment when you change the
behaviour, in the same commit.

---

## 8. Working agreements

### Verify before you conclude

Never assume. Never invent a fact, a file path, a command, an API, a version, or a number.
If you did not read it or run it, you do not know it. This is the same rule as
`superpowers:verification-before-completion`, and it binds every subagent too.

Stop when you lack the information to proceed. Say what is missing, then give a short list
of options, each naming one action: a file to read, a command to run, a search to make, or
a question for the user to answer.

Label every claim. A claim is **verified** only when you ran the check or read the source.
Label everything else **unverified**, and say what would verify it. An unverified claim
that reaches the user as a fact is a defect, not a shortcut.

### Definition of done

A task ends when all of these hold, and you observed each one in this session:

1. The tests pass. Run the real command from section 2.
2. Lint and typecheck are clean.
3. Comments and docs match sections 6 and 7.
4. The work sits committed on the correct branch.
5. You stated everything that is incomplete or uncertain.

### Stop and ask before

- You add, remove, or upgrade a dependency.
- You change a public API, a schema, or a data migration.
- You touch auth, payments, secrets, or anything user-facing and irreversible.
- You run a destructive or non-local operation: a deploy, production data, a force push.
- Two reasonable readings of a requirement exist. Ask once. Spell out both readings. Do
  not guess and build the wrong thing.

### Browser verification

Do not start a browser check unless someone asks for one. Say why and wait for a yes when
you believe one is the best way to diagnose something.

### Reporting

Report what you observed, not what you expected. "Tests pass" means you ran the suite and
it passed. State anything unverified, unfinished, or broken first, before the summary of
what went well.

---

## 9. Style

- **Write to the ASD-STE100 Simplified Technical English writing rules.** They apply to
  chat replies, documentation, research, commit messages, code comments, and agent briefs.
  In short: active voice, one instruction per sentence, short sentences, simple tenses,
  a vertical list instead of a complex sentence, and a warning before the step it
  protects. Never drop a subject, a verb, or an article to shorten a sentence. Load the
  `ste-writing` skill for the full rule set and the examples. We follow the writing
  rules. We do not claim STE compliance, because that needs the ASD dictionary.
- Be concise and direct. Cut a word that does not change the meaning. Keep a word that the
  grammar needs.
- Do not use an em-dash in prose. Use a comma, a semicolon, or a colon.
- Use kebab-case for every new file and folder.
- Research reports use MLA citations and end with a full MLA bibliography.
