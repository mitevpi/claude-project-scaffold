---
name: parallel-agent-safety
description: The isolation and safety policy for running more than one agent at the same time. Load it together with superpowers:dispatching-parallel-agents, which holds the dispatch pattern. This skill holds what that pattern does not: how to partition work by writer, how to isolate each writing agent, the concurrency cap, what a subagent may and may not do to git, how to land a wave one branch at a time, and when to offer the owner a wave of independent tasks inside a plan.
---

# Parallel agent safety

`superpowers:dispatching-parallel-agents` holds the dispatch pattern: when to fan out,
how to scope an agent, how to write a prompt, and how to review what returns. Read it
first. It is the procedure.

This skill holds the isolation policy that the procedure does not cover. Load both.
Where the repository's `CLAUDE.md` states absolute rules for parallel work, they
bind whether or not you read either file, and they override this skill.

Three controls protect a wave. They differ in strength.

1. **Mechanical.** Deny rules in `.claude/settings.json` and a git-blocking hook such
   as `block-subagent-git`, where the repository configures them. A subagent may read
   history, stage explicit paths, and
   commit its own work. It cannot push, branch, merge, rebase, reset, checkout, stash,
   clean, tag, or create a worktree. Claude Code's worktree isolation blocks an edit,
   a command, or a git redirect that an isolated agent aims at the main checkout. The
   `wave-implementer-stop` hook sends a wave implementer back once when it tries to
   finish with uncommitted work.
2. **Configured.** The agents a repository may define in `.claude/agents/`, where a
   `researcher` and a `reviewer` hold no write tools, so they cannot write, and a
   `wave-implementer` declares `isolation: worktree`, so it always gets its own
   worktree. Where a repository defines none, use the harness's own available agent
   types instead.
3. **Written.** The rules in CLAUDE.md and in each brief.

Prefer control 1, then 2, then 3. A rule in a prompt is the weakest of the three. Never
rely on it alone.

## Step 1: Decide whether to fan out at all

`superpowers:dispatching-parallel-agents` answers this for independent failures. Add
two questions of your own before you launch.

1. Is each subtask large enough to pay for a fresh context? A wave costs many times the
   tokens of a single conversation.
2. Can you review everything that comes back? You must read every diff. Your review
   speed is the real limit.

Answer no to either and work sequentially. State the decision in one line and continue.

**A plan runs in sequence by default.** It goes through
`superpowers:subagent-driven-development`, which dispatches one implementer at a time
and reviews each task. This skill covers a wave of genuinely independent work outside a
plan. The one exception is a plan wave that the owner approves: see
[Waves inside a plan](#waves-inside-a-plan).

## Step 2: Partition the work by writer

Write the partition down before you launch anything.

- Give each file exactly one owner for the whole wave.
- Merge two subtasks into one when they need the same file. Do not hope that the merge
  will resolve cleanly.
- Keep every shared hotspot for yourself: build config, routes, registries, lockfiles,
  migrations, `README.md`, `CLAUDE.md`, and any generated file.
- Define the contracts first. Name the function signature, the schema, or the interface
  that both sides must respect. Put it in every brief that touches it.

A partition you cannot write down is a partition you do not have.

## Step 3: Set the concurrency

- Write-capable agents: the repository's stated cap if it has one, otherwise three.
- Read-only agents: more is safe. Three to five is a common working range.

A cheaper model does not raise the cap. A cheap model needs a tighter scope, not a
looser one, because it follows a written rule less reliably.

Name the model explicitly in every dispatch. An omitted model inherits the session's
model, which is normally the most capable and most expensive one. The model you name at
dispatch overrides the `model:` field in the agent definition file.

## Step 4: Isolate every writing agent

Confirm a clean working tree first. Never fan out on top of uncommitted work.

Dispatch every writing agent as `wave-implementer`. Its `isolation: worktree` field
makes Claude Code create the worktree before the agent's first turn:

- The worktree is `.claude/worktrees/agent-<id>`, on a new branch `worktree-agent-<id>`.
- It branches from your current `HEAD`, because `settings.json` sets
  `worktree.baseRef` to `"head"`. Without that setting it branches from the remote
  default branch, which is the wrong base when the wave lands on a feature branch.
  Check out the branch the wave lands on, and commit, before you dispatch. Uncommitted
  work never reaches the agent's worktree.
- An agent that changes nothing leaves no worktree. A worktree with work in it stays
  until you land it.

Where the harness has no worktree isolation, use a plain `implementer` and create the
worktree yourself, the same order of preference that `superpowers:using-git-worktrees`
sets:

```
git worktree add .worktrees/<slug> -b <branch> <base>
```

Then tell the agent its worktree path in the brief. `.worktrees/` must be in
`.gitignore`. An unignored worktree directory commits a whole second checkout into the
repository. Run `git check-ignore -q .worktrees/probe` to confirm it before you create
anything. Probe a path inside the directory: a pattern such as `/.worktrees/` matches
only a directory, so `git check-ignore .worktrees` reports "not ignored" until the
directory exists.

When worktrees are disabled for the project, do not fan out write-capable agents at all.

### Prepare the worktree environment

A worktree is a fresh checkout. It holds no gitignored file, so no `.env` and no
installed dependencies.

- **Local config.** Claude Code copies each gitignored file that `.worktreeinclude`
  lists into every worktree it creates. The scaffold installs one that lists `.env` and
  `.env.local`. Add what the tests need.
- **Dependencies.** The wave implementer runs the install command from the Commands
  section of CLAUDE.md, which must install from the lockfile. To skip that, a project
  can set `worktree.symlinkDirectories`, such as `["node_modules"]`, to share the main
  checkout's directory. Every worktree then uses the same copy. Use it only while no
  task in the wave changes a dependency.
- **A large monorepo.** `worktree.sparsePaths` checks out only the listed directories.

### Know the limits of a worktree

- A worktree isolates files. It does not isolate a database, a port, a cache, a queue,
  or any other external state. Name a separate port in each brief that starts a server.
  Give each agent its own dev database when the work touches migrations, or run those
  tasks serially.
- Worktree isolation reads the target of an edit and the directory of a command. It does
  not see a shell command such as `cp` that writes into the main checkout. The `sandbox`
  setting closes that gap where the project turns it on.
- **Agent teams share one working directory.** Their teammates do not get worktrees, so
  two teammates that edit one file overwrite each other. Do not use agent teams for a
  wave that writes. They suit research and review. With teams turned on, a named Agent
  call starts a teammate unless it passes isolation itself, so dispatch writers as
  `wave-implementer`, which always does.

## Step 5: Write the brief

Each brief carries five things.

1. **The task.** One outcome, stated plainly.
2. **The write scope.** The exact files or directories the agent may change. State that
   the list is complete.
3. **The contracts.** What it must not change, and the signatures it must respect.
4. **The output format.** What it must return, and in what shape.
5. **The verification.** The exact test and lint commands to run, taken from the
   repository's CLAUDE.md or its README.

Add one line to every brief: the agent cannot see the other agents and must not assume
their results.

A wave implementer normally runs in the background. Each permission prompt it reaches
appears in your session, and the agent waits until someone answers. A headless run in
`dontAsk` mode denies the prompt instead. Either way the wave slows to your reply time.
Confirm before you dispatch that `permissions.allow` covers every command the brief
names, the tests above all.

Hand a large input over as a file path, not as pasted text. Everything you paste into a
brief stays in your context for the rest of the session.

Pick the agent type by role, using these names where `.claude/agents/` defines them;
otherwise pick the harness's own closest available agent type for each role.

| Role | Agent | Model |
| --- | --- | --- |
| Find and report | `researcher` | a mid tier |
| Review against a spec | `reviewer` | a capable tier |
| Write code in a scope, in a wave | `wave-implementer` | a mid tier |
| Write code for a plan task | `implementer` | a mid tier |

When a Superpowers skill supplies a prompt template for the role, use that template as
the brief and dispatch it on the matching agent above. The template is the content. The
agent definition is the tool grant.

A `reviewer` with no shell cannot run the `git diff` that a review template asks for.
Write the range to a file first, with `.claude/scripts/review-package.sh <base> <head>`
where the repository has it, and put the printed path in the brief in place of the git
commands.

## Step 6: Land the wave

Start with the whole wave in view. Run `.claude/scripts/wave-status.sh <base>`. It lists
every worktree with its branch, its commits ahead and behind, its uncommitted changes,
and the files it touches, and then every file that two worktrees change. An overlap that
Step 2 did not plan is a scope breach. Find the agent that left its scope before you
land anything.

Integrate one branch at a time. Never merge two at once. Take each branch name from the
`worktreeBranch` line that the Agent tool returns with the agent's report, or from
`wave-status.sh`. A wave implementer's branch is `worktree-agent-<id>`.

For each branch:

1. Read the full diff. You own this review. Do not delegate it to the agent that wrote
   the code. `.claude/scripts/review-package.sh <base> <branch>` writes it to a file for
   a `reviewer` pass first, where the repository has the script.
2. Land it with
   `.claude/scripts/land-branch.sh --check "<full check command>" <branch> <base>`. The
   check command is the full test suite plus the lint and typecheck commands from the
   repository's CLAUDE.md. The script rebases the branch onto the current base, runs the
   check in the branch's worktree, fast-forwards the base only when the check passes,
   removes the worktree, and then deletes the branch. That order matters: git refuses to
   delete a branch that a worktree still has checked out. The fast-forward makes the
   base identical to the branch that passed, so the check covers the base too. Where the
   repository has no such script, follow the same order by hand, and run the suite
   again on the base.

Only then start the next branch. A failed check or a refused rebase stops the wave. Fix
it before you integrate anything else.

When the script refuses, it has changed nothing that loses work. Report its message. Never
remove a worktree with `--force`: git suggests it when a worktree holds uncommitted work,
and that work is exactly what `--force` deletes.

The wave is finished when the combined result passes on the base branch. It is not
finished when the agents return.

## Step 7: Report

Report what each agent actually did, not what you asked it to do. Name every task that
failed, every scope that an agent had to leave, and every check you did not run.

`superpowers:verification-before-completion` holds the rule that governs this report: no
completion claim without fresh evidence. An agent's own success report is not evidence.
The diff and the test output are.

## Waves inside a plan

A plan runs one task at a time. Sometimes two or more of its tasks are fully
independent, and running them together saves real time at almost no risk. Offer the
owner that wave only then. The owner decides. Never start a plan wave without a yes.

### When to offer it

Offer a plan wave only when every one of these holds for the tasks in it:

1. **No dependency.** No task uses another's output: not a function, a type, a file, a
   migration, or a test fixture. Every interface they share already exists in a commit.
2. **Disjoint write sets.** You can write down each task's files, and no file appears
   twice. No task touches a shared hotspot from Step 2.
3. **Worth a fresh context.** Each task is a real unit of work, not a one-line edit.
   The plan has at least two such tasks that could run together.
4. **Isolation is available.** `wave-implementer` and its worktrees work in this
   repository.

When any condition fails, run the plan in sequence and do not ask. A question about a
wave with real risk in it wastes the owner's attention.

### How to ask

Ask once, before the first task of the group, with a summary of five lines at most:

```
Parallel opportunity: tasks 3, 4, and 6 are independent.
Why it is low risk: no shared files (each owns its own module), no task uses another's output.
Pros: about two tasks' worth of waiting saved.
Cons: three agents' token cost at once, and three branches to review and land, one at a time.
Residual risk: <the one thing that could still collide, or "none found">.
Run them in parallel? Otherwise they run in sequence, as planned.
```

State the residual risk plainly. When you cannot name the files each task owns, you do
not have a wave. Do not ask.

### How to run it

On a yes, run the group as a wave under Steps 3 to 7, with the plan's branch as the base.

- Use each task's `subagent-driven-development` implementer prompt as the brief, and
  dispatch it on `wave-implementer`.
- Keep the plan's per-task review. Review each task's branch before it lands, as the
  plan would review it in sequence.
- Record each task in the plan's progress ledger when it lands, so that the plan
  continues from the right task.
- Resume the plan in sequence after the last branch of the group lands and the check
  passes on the plan's branch.

On a no, run the plan in sequence and do not ask again for that group.

## Failure modes to watch for

- **Silent overwrite.** Two agents wrote the same file. Step 2 prevents it.
- **Compiles but disagrees.** Two agents implemented the same contract differently.
  Step 2's contract definition prevents it.
- **Duplicated work.** Two agents built the same helper. Name the shared code in the
  briefs.
- **Blast radius.** One agent ran a destructive command. Controls 1 and 2 prevent it.
- **Stalled agent.** A background agent waits on a permission prompt for a command that
  an allow rule should cover. The allow-rule check in Step 5 prevents it.
- **Stale base.** A worktree branched from the remote default branch, not from the base
  the wave lands on. `worktree.baseRef: "head"` prevents it.
- **Review debt.** More output arrived than you can read. Step 1 question 2 prevents it.
- **Trusted report.** An agent said it passed the tests and it did not. Read the diff
  and run the suite yourself.
