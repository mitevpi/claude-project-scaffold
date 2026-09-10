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
dev/                          scaffold-only tooling, never installed
settings.json              -> <target>/.claude/settings.json
agents/
  researcher.md               read-only. No shell. For exploration and fact-finding.
  reviewer.md                 read-only. No shell. For spec and quality review.
  implementer.md              writes inside one named scope. Runs tests. Commits.
hooks/
  block-subagent-git.sh       limits which git commands a subagent may run
scripts/
  check-claude-md.sh          verifies a filled-in install
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

1. **Mechanical.** `settings.json` deny rules and the `block-subagent-git` hook. These
   run outside the model. `git reset --hard` and `rm -rf` are denied. `git push` and
   `npm install` ask first. A subagent cannot push, branch, merge, or rebase at all.
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

The installer never overwrites an existing file. It lists everything it skipped, so
nothing goes missing quietly. Pass `--force` to overwrite, or merge by hand.

### An existing project

Run the same command. The installer will skip your `README.md` and any file you already
have, and it will still install `.claude/` and append the required `.gitignore` entries.
Then merge the template's `CLAUDE.md` into yours by hand, section by section. The sections
that repay the effort first are section 2 (commands) and the invariants list in section 1.

### The `.gitignore` entries are load-bearing

`install.sh` appends a block covering `.worktrees/` and `.superpowers/`. Both matter:

- An unignored `.worktrees/` commits a whole second checkout into the repository.
- An unignored `.superpowers/` commits the subagent-driven-development ledger, every task
  brief, and every review package.

The check script fails if either is missing.

## FULL or light

The two manual templates differ in section 4, the git model, and in nothing else.

| | `CLAUDE-template.md` (FULL) | `CLAUDE-light.md` |
| --- | --- | --- |
| Base branch | A separate integration branch. `main` is off-limits to the agent. | `main`, which the agent may commit to directly. |
| Use it when | `main` is protected, other people share the repo, or releases cut from another branch. | You are solo, and you own `main`. |
| Install | `./install.sh <target>` | `./install.sh --light <target>` |

Both land at about 330 lines once filled in. That file is read in full in every session,
so every line costs context in every turn. The check script warns above 340 lines. Move a
topic into `docs/` or into a skill when it outgrows a short section, and leave a one-line
link behind.

## How it works with Superpowers

The `superpowers` plugin supplies the process: brainstorm, write a spec, write a plan,
execute it task by task with a fresh subagent, review each task, review the branch. This
scaffold is built to sit under that process rather than beside it. The alignment below was
checked against **Superpowers 6.3.0**.

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
   default rather than the plugin.

### The git hook, and why it allows a commit

`superpowers:subagent-driven-development` dispatches one implementer subagent per task,
and **that subagent commits its own work.** The controller then diffs the `BASE..HEAD`
range to build the review package it hands the reviewer. A hook that blocks a subagent
commit does not merely inconvenience that workflow. It breaks it.

So `block-subagent-git.sh` draws the line at reshaping the repository, not at writing to
it. For a subagent:

| Allowed | Blocked |
| --- | --- |
| `status`, `diff`, `log`, `show`, `rev-parse`, and the other read commands | `push`, `checkout`, `switch`, `restore`, `branch`, `merge`, `rebase`, `reset`, `cherry-pick`, `revert`, `clean`, `stash`, `tag`, `worktree` |
| `git add <explicit path>` | `git add -A`, `--all`, `-u`, `.`, `:/` |
| `git commit -m "..."` | `git commit` with `-a`, `-n`, `--no-verify`, or `--amend` |
| `git config --get`, `--list` | `git config <name> <value>` |

The last two rows turn two written rules into mechanical ones. "Stage explicit paths" and
"never bypass a hook" are now enforced rather than requested. The hook uses an allowlist,
so a git subcommand it has never heard of is blocked, not permitted.

The main session is never limited by the hook. It holds the branch operations, the merges,
and the pushes, which is where the owner's review sits.

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
  in a sandbox or a container.
- **The hook fails open.** If it cannot parse the payload, it allows the command. A hook
  that blocked on its own errors would stall every session. That trade-off is deliberate,
  and it means the hook is a second line of defence rather than a wall.
- **The hook only sees subagents.** It identifies a subagent by fields in the tool
  payload. The main session is unrestricted by design, so the deny rules in
  `settings.json` are what stand between the main session and a destructive command.
- **Prompt injection defeats layer 3 entirely.** Content that an agent reads is data, not
  instruction, but a written rule cannot enforce that on its own. Never point an agent
  with write tools at untrusted content and then leave it unsupervised.
- **Superpowers costs tokens, and subagent-driven development costs multiples.** Every
  task pays for a fresh implementer, a reviewer, and often a fix round. A parallel wave
  costs many times a single conversation. For a small change this process is more expensive
  than doing it yourself, and the approval gate on every path adds turns.
- **A stale `CLAUDE.md` is worse than no `CLAUDE.md`.** A wrong command in the table sends
  an agent down a path with total confidence. The update triggers in section 6 exist for
  this reason, and they only work if you honour them.
- **The line budget is a real constraint.** The manual is re-read every session. Anything
  you add is paid for in every turn, for the life of the repository.
- **The alignment can drift.** Everything in the Superpowers section above was verified
  against version 6.3.0. A plugin release can move a default path or change a skill's
  process. See the next section.
- **The writing rules are opinionated.** The ASD-STE100 rules make output terse and
  literal. Some people read that as curt. Delete section 9 and the `ste-writing` skill if
  you do not want it; nothing else depends on them.
- **`git config` is readable by a subagent.** The hook allows `--get` and `--list`, which
  is enough to read a user name and email. That is intentional, because commits need a
  signature, but it is worth knowing.

## Verifying the install

This repository tests itself:

```bash
./self-test.sh
```

It checks that every shell script parses, that `settings.json` is valid JSON, that the git
hook allows and blocks the right commands across a 46-case matrix, and that `install.sh`
produces a target repository the check script accepts. The install test is end to end: it
installs into a temporary repository, fills the placeholders, and runs the check script
against the result.

In a target repository, run the check script instead:

```bash
.claude/scripts/check-claude-md.sh
```

It verifies that no placeholder or usage block remains, that every companion file the
manual refers to exists, that the hook is executable and enforcing the intended policy,
that `.gitignore` covers the agent workspaces, and that the manual is inside its line
budget.

## Keeping up with plugin changes

The alignment above is pinned to a version, not to a promise. When you update the
`superpowers` plugin, three things are worth re-checking, because they are what the
scaffold depends on:

1. **The document paths** in `superpowers:brainstorming` and `superpowers:writing-plans`.
2. **The worktree directory** that `superpowers:using-git-worktrees` looks for.
3. **Whether the subagent-driven-development implementer still commits its own work.** If
   that ever changes, the hook's allowance for `add` and `commit` can tighten again.

Each one is a single line in a skill file. The plugin installs under
`~/.claude/plugins/cache/`, so `grep` finds them quickly.

## Contributing

Read `CLAUDE-template.md` first. It is the manual this repository would install into
itself, and it describes the working agreements a change here is judged against.

- Run `./self-test.sh` before you open a pull request. Add a test case for any behaviour
  you change in the hook or the installer.
- The scaffold's own prose follows the `ste-writing` rules. So does this file.
- Keep the two manual variants different in section 4 only. A divergence anywhere else is
  a bug.

## License

MIT. See [LICENSE](LICENSE).
