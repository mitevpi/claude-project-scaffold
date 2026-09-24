# claude-scaffold

A starting configuration for a repository worked on with [Claude Code](https://claude.com/claude-code)
and the [`superpowers`](https://github.com/obra/superpowers) plugin. It gives a project
an operating manual that an agent reads first, three subagent definitions, two skills, a
permission ruleset, and a hook that limits what a subagent can do to git.

The point is not to make an agent faster. The point is to make its output reviewable, and
to keep one bad command from reaching the whole repository.

## Contents

- [What this is](#what-this-is)
- [What it is not](#what-it-is-not)
- [What is in the box](#what-is-in-the-box)
- [The idea: three layers of control](#the-idea-three-layers-of-control)
- [Quick start](#quick-start)
- [FULL or light](#full-or-light)
- [How it works with Superpowers](#how-it-works-with-superpowers)
- [What it is good for](#what-it-is-good-for)
- [Risks and limitations](#risks-and-limitations)
- [Verifying the install](#verifying-the-install)
- [Keeping up with plugin changes](#keeping-up-with-plugin-changes)
- [Contributing](#contributing)

---

## What this is

Every Claude Code session reads `CLAUDE.md` before it does anything else. Most projects
leave that file thin, or they let it grow into a wish list that nobody reads. Either way
the agent guesses, and a guess that looks confident costs more to unwind than a question.

This scaffold fills that gap with four kinds of artefact.

| Artefact | Job |
| --- | --- |
| `CLAUDE.md` template | The internal operating manual: commands, architecture, invariants, git model, working agreements. |
| `README.md` template | The public document, kept deliberately separate from the manual. |
| `.claude/settings.json` | Permission rules. Some commands are denied. Some ask first. |
| `.claude/hooks/`, `.claude/agents/`, `.claude/skills/` | Mechanical and configured limits on what an agent and its subagents can do. |

The templates carry `{{PLACEHOLDER}}` markers and a check script that fails while any
placeholder remains. This is deliberate. An unfilled placeholder is worse than a missing
section, because it teaches the agent to guess in the one file it trusts most.

## What it is not

- **Not a security boundary.** The deny rules and the git hook stop accidents and
  careless commands. They do not stop a determined agent, and they do not stop a
  prompt-injection attack that arrives through a file, a web page, or a dependency.
  Read the [Risks](#risks-and-limitations) section before you rely on any of it.
- **Not a substitute for review.** Nothing here reads a diff for you.
- **Not a plugin.** It installs no code and runs no server. It is a set of files that a
  Claude Code session happens to read.
- **Not language-specific.** It assumes git and a test command. Nothing else.

## What is in the box

```
CLAUDE-template.md            the FULL operating manual template
CLAUDE-light.md               the same manual with a simpler git model
README-template.md            the public README template
install.sh                    copies the payload into a target repository
self-test.sh                  this repository's own test suite
dev/                          scaffold-only tooling, never installed: the settings
                              merge, and the light-manual build and its fragments
settings.json              -> <target>/.claude/settings.json
agents/
  researcher.md               read-only. No shell. For exploration and fact-finding.
  reviewer.md                 read-only. No shell. For spec and quality review.
  implementer.md              writes inside one named scope. Runs tests. Commits.
hooks/
  block-subagent-git.sh       limits which git commands a subagent may run
  session-start-git-context.sh  shows each new session the work already in its checkout
scripts/
  check-claude-md.sh          verifies a filled-in install
  land-branch.sh              lands a finished branch, and refuses rather than lose work
  review-package.sh           writes a commit range to a file for the shell-less reviewer
skills/
  parallel-agent-safety/      isolation policy for running agents concurrently
  ste-writing/                the ASD-STE100 Simplified Technical English rules
docs/
  index.md, architecture.md   stubs, plus the directories Superpowers writes into
```

Everything from `settings.json` down is the payload that `install.sh` copies into a target
repository, under `.claude/`. Everything above it stays here.

## The idea: three layers of control

A rule written in a prompt is a preference. An agent follows it most of the time. "Most of
the time" is not a control when the failure mode is a destroyed working tree.

So the scaffold states every rule three times, at three different strengths, and it says
which layer is doing the work.

1. **Mechanical.** `settings.json` deny rules and settings, and the two hooks. These
   run outside the model. `git reset --hard`, forced worktree removal, and `rm -rf` are
   denied, and the git hook blocks the destructive git commands again in the forms a deny
   rule cannot match, such as `git -C <path> reset --hard`. `git push` and `npm install`
   ask first. A subagent cannot push, branch, merge, or rebase at all, and it cannot
   spawn a subagent of its own.
2. **Configured.** The agent definitions in `agents/`. A `researcher` and a `reviewer`
   hold no write tools and no shell, so they cannot write a file even when told to. This
   is a property of the configuration, not of the agent's cooperation.
3. **Written.** The rules in `CLAUDE.md` and in each subagent brief.

Prefer layer 1, then 2, then 3. The templates say this out loud, because an agent that
knows a rule is only written treats it with the right amount of suspicion.

The practical consequence: **grant tools, do not request behaviour.** "Do not edit any
file" in a prompt is a preference. An agent with no `Write` tool is a fact.

## Quick start

### A new project

```bash
git clone https://github.com/<your-account>/claude-scaffold.git
cd claude-scaffold
./install.sh /path/to/your-repo
```

Then, in the target repository:

1. Fill every `{{PLACEHOLDER}}` in `CLAUDE.md` and `README.md`. Delete any section that
   does not apply.
2. Delete the `TEMPLATE USAGE` comment block from the top of each file.
3. Run the check:

```bash
.claude/scripts/check-claude-md.sh
```

4. Commit `CLAUDE.md`, `README.md`, `.claude/`, and `docs/`. They are shared, tracked
   configuration, not local preference.

The target must be a git repository with no uncommitted changes. The installer refuses
anything else, so that the install is always one diff that you can review with
`git diff` and undo with `git restore .` and `git clean`.

The installer never overwrites an existing file. It lists everything it skipped, so
nothing goes missing quietly. Pass `--force` to overwrite, or merge by hand. Because the
tree was clean, every file that `--force` overwrites is still in git.

`.claude/settings.json` is the one exception: it is merged, never skipped. The installer
adds each scaffold permission rule and hook that the file lacks, and keeps every rule it
already holds. A skipped settings file would leave the hooks on disk but never registered.

### An existing project

Commit or stash your work first, then run the same command. The installer skips your
`README.md` and any file you already have. It still installs `.claude/`, merges the
scaffold's rules and hooks into your `.claude/settings.json`, and appends the required
`.gitignore` entries.
Then merge the template's `CLAUDE.md` into yours by hand, section by section. The sections
that repay the effort first are the Commands table and the invariants list under Project.

### Updating an installed project

The installer installs the scaffold's committed `HEAD`, never its working tree, and it
records that commit in `.claude/scaffold-version`. When the scaffold improves, bring a
project up to date from a clean tree:

```bash
./install.sh --update /path/to/your-repo
```

For each file under `.claude/agents/`, `hooks/`, `scripts/`, and `skills/`, it adds a file
that is new, refreshes a file that the project never changed, and keeps a file that the
project customised. It names every file it kept, with the `git diff` command that shows
the upstream change. A file the project deleted stays deleted, and a file that upstream
deleted is removed unless the project customised it.

`settings.json` gets the same three-way merge against the installed commit. A rule or
hook that is new upstream is added. One that the project removed stays removed, so you
can drop a scaffold rule you do not want. One that upstream dropped is removed, which
also replaces a hook whose command changed. It never touches `CLAUDE.md` or
`README.md`: when their templates changed, it prints the command that shows the change,
and you port what applies.

### The `.gitignore` entries are load-bearing

`install.sh` appends a block that covers the agent workspaces. Each entry matters:

- An unignored `.worktrees/`, `worktrees/`, or `.claude/worktrees/` commits a whole second
  checkout into the repository. The first two come from `superpowers:using-git-worktrees`.
  The third is where Claude Code's own worktree option puts them. The entries are anchored
  at the repository root, so a source directory that happens to be named `worktrees/` stays
  tracked.
- An unignored `.superpowers/` commits brainstorming mockups. The subagent-driven-development
  ledger and `review-package.sh` each ignore their own directory, but the brainstorming
  companion does not.

The check script asks `git check-ignore` about each path, so a commented-out entry fails
and an equivalent pattern passes. A reinstall adds any entry that an older block lacks.

## FULL or light

The two manual templates differ in the Git section's branch model, and in nothing else.
`CLAUDE-light.md` is generated: `dev/build-light.py` builds it from `CLAUDE-template.md`
and the two fragments in `dev/light-variant.md`, and the self-test fails when the file is
stale. Edit the FULL template or the fragments, never the light file itself.

| | `CLAUDE-template.md` (FULL) | `CLAUDE-light.md` |
| --- | --- | --- |
| Base branch | A separate integration branch. `main` is off-limits to the agent. | `main`, which the agent may commit to directly. |
| Use it when | `main` is protected, other people share the repo, or releases cut from another branch. | You are solo, and you own `main`. |
| Install | `./install.sh <target>` | `./install.sh --light <target>` |

Both land at about 250 lines once filled in. That file is read in full in every session,
so every line costs context in every turn. The check script warns above 260 lines. Move a
topic into `docs/` or into a skill when it outgrows a short section, and leave a one-line
link behind. The manual restates a Superpowers skill only where it overrides it; the
plugin's own skills carry the rest.

Sections refer to each other by name, never by number, so you can delete a section that
does not apply, such as the Superpowers workflow, without breaking a reference. The
self-test fails on any numbered reference.

## How it works with Superpowers

The `superpowers` plugin supplies the process: brainstorm, write a spec, write a plan,
execute it task by task with a fresh subagent, review each task, review the branch. This
scaffold is built to sit under that process rather than beside it. The alignment below was
checked against **Superpowers 6.4.1**.

### What the scaffold adopts unchanged

- **The classification vocabulary.** `spike`, `bounded`, and `architectural`, from
  `superpowers:brainstorming`. `CLAUDE.md` uses those words instead of inventing a
  parallel triage rule.
- **The approval gate on every path.** Including a one-line change. What scales with the
  size of a task is the artefact, never the gate. A typo fix earns a one-sentence design
  and a yes. It does not earn a spec file, and it does not earn silence.
- **The plugin's own document paths.** `docs/superpowers/specs/` and
  `docs/superpowers/plans/`. The stub tree creates both. Keeping the plugin's defaults
  means a plugin update never moves them, and no session spends instructions restating an
  override.
- **The worktree policy.** Prefer the harness's native worktree tool. Fall back to
  project-local `.worktrees/`, which `.gitignore` covers. The earlier version of this
  scaffold used a sibling `../worktrees/` directory, which the plugin does not look for.
- **Test-driven development, with no project exemption.** Write the test, watch it fail,
  then make it pass.
- **The three-option menu at the end of a branch.** `finishing-a-development-branch`
  presents merge, pull request, or keep, and the choice belongs to the repo owner. The
  scaffold does not pre-answer it.

### What the scaffold overrides, deliberately

Two overrides, both about git, and both labelled as overrides inside `CLAUDE.md` so that
they do not read as drift.

1. **How a branch lands.** The skill shows `git merge`. The FULL template rebases and
   fast-forwards instead, to keep each diff linear against a protected `main`.
2. **Commit attribution.** No `Co-Authored-By: Claude` trailer and no "Generated with
   Claude Code" line. The commit belongs to the repo owner. This overrides the harness
   default rather than the plugin, and it is mechanical: the `attribution` block in
   `settings.json` sets both lines to empty strings.

### The git hook, and why it allows a commit

`superpowers:subagent-driven-development` dispatches one implementer subagent per task,
and **that subagent commits its own work.** The controller then diffs the `BASE..HEAD`
range to build the review package it hands the reviewer. A hook that blocks a subagent
commit does not merely inconvenience that workflow. It breaks it.

So `block-subagent-git.sh` draws the line at reshaping the repository, not at writing to
it. For a subagent:

| Allowed | Blocked |
| --- | --- |
| `status`, `diff`, `log`, `show`, `rev-parse`, `merge-base`, `check-ignore`, and the other read commands | `push`, `checkout`, `switch`, `restore`, `merge`, `rebase`, `reset`, `cherry-pick`, `revert`, `clean`, `tag` |
| `branch` (listing), `worktree list`, `stash list` and `show`, `remote -v` and `get-url`, `reflog` | creating, moving, or deleting a branch, worktree, stash, or remote; `reflog expire` |
| `git add <explicit path>` | `git add -A`, `--all`, `-u`, `-f`, `-p`; a pathspec for the whole tree: `.`, `..`, `:/`, `:(top)`, a glob, `"$PWD"` |
| `git commit -m "..."` | `git commit` with `-a`, `-n`, `--no-verify`, `--amend`, or a pathspec such as `.` |
| `git config --get`, `--list` | `git config <name> <value>`; `core.hooksPath` through `-c`, `--config-env`, or `GIT_CONFIG_*`; `HUSKY=0` |
| `git -C <path> ...`, `cd <path> && git ...` | `land-branch.sh`, which rebases and deletes a branch out of the hook's sight |

The middle rows turn two written rules into mechanical ones: "stage explicit paths" and
"never bypass a hook". git accepts any unique prefix of a long option, so the guards
treat `--amen` as `--amend`, and they read a flag group such as `-fv` letter by letter.
The hook uses an allowlist, so a git subcommand it has never heard of is blocked, not
permitted.

The hook reads the whole command, not only its first word. A git command is inspected
wherever it sits: after a path such as `/usr/bin/git`, after `env` (including `env -S`),
`nohup`, `xargs`, `watch`, or a variable assignment, and inside `$(...)`, backticks, a
subshell, a `{ }` group, an `if` or `for` body, `bash -c`, `sh -c`, `eval`, `find -exec`,
or a heredoc fed to a shell. A command whose name is built at run time, such as `$G push`,
is blocked when the command mentions git. The self-test holds a case for each form.

The main session keeps the branch operations, the merges, and the pushes, which is where
the owner's review sits. The hook blocks it only from the commands that destroy work: the
ones `settings.json` denies, such as `reset --hard`, `clean`, a force push, and
`branch -D`. A deny rule matches the command as written, so `git -C <path> reset --hard`
or `bash -c "git clean -fd"` passes it. The hook reads those forms too.

### Skill naming

The scaffold's concurrency skill is called `parallel-agent-safety`, and its description
says it complements `superpowers:dispatching-parallel-agents` rather than replacing it.
Two skills with near-identical descriptions compete for the same trigger, and the model
picks one at random. The plugin skill holds the dispatch pattern. The scaffold skill holds
the isolation policy: partition by writer, one worktree per writing agent, a concurrency
cap, and how to land a wave one branch at a time.

### Agent definitions and prompt templates

Superpowers dispatches plain `general-purpose` subagents and supplies its own prompt
templates. The scaffold's `agents/` definitions are compatible, and `CLAUDE.md` states the
division: **the Superpowers template is the brief, and the agent definition is the tool
grant.** The model named at dispatch overrides the `model:` field in the agent file, so
the plugin's model-selection guidance still applies.

One template needs a bridge. The SDD task reviewer reads a review package file that the
plugin's own script writes. The `requesting-code-review` reviewer instead runs `git diff`
itself, which a shell-less `reviewer` cannot do. `scripts/review-package.sh` writes the
same kind of file for any range, and the manual tells the orchestrator to run it before
every such review.

### Skills that share a name with a personal skill

Claude Code ranks a personal skill in `~/.claude/skills/` above a project skill with the
same name. If you keep your own copy of `parallel-agent-safety` or `ste-writing`, the
project copy never runs on your machine, while your teammates run the project copy. The
check script warns when a personal copy differs. Treat the scaffold as the source, and
delete or re-sync the personal copy.

## What it is good for

- **A repository that more than one person or agent touches.** The invariants section and
  the commands table stop the same question being asked every session.
- **Work you intend to review rather than trust.** Every rule says which layer enforces
  it, so you know what you are relying on.
- **Parallel or subagent-driven work.** This is where an unscoped agent does real damage,
  and where the hook and the read-only agent definitions earn their place.
- **Documentation that survives.** Research and open-ended answers are deliverables that
  land in `docs/`, not chat messages that scroll away.
- **Consistent writing.** The `ste-writing` skill applies the ASD-STE100 Simplified
  Technical English writing rules to prose, commits, comments, and briefs. That standard
  exists to protect a reader who cannot ask a follow-up question, which is exactly the
  position of someone reading an agent's summary.

## Risks and limitations

Stated plainly, because a scaffold that oversells its guarantees is worse than none.

- **The permission rules are not a sandbox.** They pattern-match command strings. A
  command can be spelled another way, moved into a script, or run through an interpreter.
  Treat them as a guard against a slip, never as containment. Run genuinely untrusted work
  in a sandbox or a container. Claude Code's own `sandbox` setting limits where Bash may
  write, and is worth turning on per project.
- **The `Read` deny rules cover the Read tool only.** They keep `.env`, `.env.local`,
  `.env.production`, keys, and credentials out of a `Read` call at any depth, and they
  leave `.env.example` readable, because the manual tells the agent to read it. They do not
  stop `cat .env` through Bash.
- **The hook fails closed for a subagent git command, and open for everything else.** If
  it cannot read a subagent command that mentions git, or python3 is missing, it blocks.
  For the main session, and for a subagent command with no git in it, it allows. A hook
  that blocked on its own errors everywhere would stall every session. It is still a
  guard against a slip, not a wall: a script file or an interpreter such as
  `python3 -c` that runs git is invisible to it.
- **The hook limits the main session only a little.** It identifies a subagent by
  fields in the tool payload. For the main session it blocks only the destructive
  commands that `settings.json` also denies. Every other git command in the main
  session rests on the ask rules and on your review.
- **An agent could try to rewrite its own controls.** `settings.json` asks before any
  edit to the settings, the hooks, the scripts, or the agent definitions, and the hook
  blocks a subagent's shell writes to them, such as a redirection or `sed -i`. The main
  session can still write them through Bash. Read every diff that touches `.claude/`.
- **Two top-level sessions in one checkout are the largest risk.** The desktop app's
  parallel sessions, a second terminal, and `claude -p` are each a main session, so the
  git hook lets each of them commit, stash, and switch branches. They share one index and one working tree. The manual
  requires one session per checkout, and the session-start hook shows every new session
  the uncommitted work and the other worktrees it starts next to. Both are warnings, not
  locks. Start each parallel session in its own worktree.
- **Prompt injection defeats layer 3 entirely.** Content that an agent reads is data, not
  instruction, but a written rule cannot enforce that on its own. Never point an agent
  with write tools at untrusted content and then leave it unsupervised.
- **Superpowers costs tokens, and subagent-driven development costs multiples.** Every
  task pays for a fresh implementer, a reviewer, and often a fix round. A parallel wave
  costs many times a single conversation. For a small change this process is more expensive
  than doing it yourself, and the approval gate on every path adds turns.
- **A stale `CLAUDE.md` is worse than no `CLAUDE.md`.** A wrong command in the table sends
  an agent down a path with total confidence. The update triggers under Documentation exist for
  this reason, and they only work if you honour them.
- **The line budget is a real constraint.** The manual is re-read every session. Anything
  you add is paid for in every turn, for the life of the repository.
- **The alignment can drift.** Everything in the Superpowers section above was verified
  against version 6.4.1. A plugin release can move a default path or change a skill's
  process. See the next section.
- **The writing rules are opinionated.** The ASD-STE100 rules make output terse and
  literal. Some people read that as curt. Delete the Style section's first rule and the `ste-writing` skill if
  you do not want it; nothing else depends on them.
- **`git config` is readable by a subagent.** The hook allows `--get` and `--list`, which
  is enough to read a user name and email. That is intentional, because commits need a
  signature, but it is worth knowing.

## Verifying the install

This repository tests itself:

```bash
./self-test.sh
```

It checks that every shell script parses and that `settings.json` holds the rules it
must. It runs the git hook against a matrix of commands, including each of the hiding
places listed above. It lands branches in scratch repositories and proves that each
refusal loses nothing. It installs into a new and an existing project, reinstalls, and
updates, each end to end, and it runs the check script against every result.

In a target repository, run the check script instead:

```bash
.claude/scripts/check-claude-md.sh
```

It verifies:

- No placeholder or usage block remains in `CLAUDE.md` or `README.md`. A `{{ spaced }}`
  expression, as Jinja and Go templates write it, is not a placeholder. The `docs/` stubs
  get a warning, not a failure.
- The hooks, the settings, and `land-branch.sh` exist, and so does every other companion
  file the manual still names. Delete a skill and its mentions together.
- The attribution setting and the subagent spawn limit are still in force.
- `settings.json` registers both hooks, holds the required deny rules, and asks before an
  edit to the files that enforce them.
- The registered hook command actually runs and blocks.
- `.gitignore` covers the agent workspaces: `.worktrees/`, `worktrees/`,
  `.claude/worktrees/`, and `.superpowers/`.
- No personal skill shadows a project skill.
- The manual is inside its line budget.

## Keeping up with plugin changes

The alignment above is pinned to a version, not to a promise. When you update the
`superpowers` plugin, three things are worth re-checking, because they are what the
scaffold depends on:

1. **The document paths** in `superpowers:brainstorming` and `superpowers:writing-plans`.
2. **The worktree directory** that `superpowers:using-git-worktrees` looks for.
3. **Whether the subagent-driven-development implementer still commits its own work.** If
   that ever changes, the hook's allowance for `add` and `commit` can tighten again.
4. **The git commands that subagent prompts run.** A new read command in an implementer
   or reviewer template needs a place on the hook's allowlist. A reviewer template that
   runs git itself needs `review-package.sh`.
5. **Where the SDD ledger lives.** It resolves to `.superpowers/sdd/` under the top of the
   current worktree, so removing that worktree deletes it. `land-branch.sh` warns when it
   removes one.

Each one is a line or two in a skill file. The plugin installs under
`~/.claude/plugins/cache/`, so `grep` finds them quickly. Install the plugin from one
marketplace only. Two installs, such as `claude-plugins-official` and
`superpowers-marketplace`, can leave an older version registered beside the current one.

## Contributing

Read `CLAUDE-template.md` first. It is the manual this repository would install into
itself, and it describes the working agreements a change here is judged against.

- Run `./self-test.sh` before you open a pull request. CI runs it on Ubuntu and macOS,
  because `/bin/sh` is dash on one and bash 3.2 on the other. Add a test case for any
  behaviour you change in a hook, a script, or the installer, and watch it fail first.
- The scaffold's own prose follows the `ste-writing` rules. So does this file.
- Edit `CLAUDE-template.md` or `dev/light-variant.md`, then run
  `python3 dev/build-light.py --write`. Never edit `CLAUDE-light.md` by hand.

## License

MIT. See [LICENSE](LICENSE).
