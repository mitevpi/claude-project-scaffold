---
name: parallel-agent-safety
description: The isolation and safety policy for running more than one agent at the same time in this repository. Load it together with superpowers:dispatching-parallel-agents, which holds the dispatch pattern. This skill holds what that pattern does not: how to partition work by writer, how to isolate each writing agent, the concurrency cap, what a subagent may and may not do to git, and how to land a wave one branch at a time.
---

# Parallel agent safety

`superpowers:dispatching-parallel-agents` holds the dispatch pattern: when to fan out,
how to scope an agent, how to write a prompt, and how to review what returns. Read it
first. It is the procedure.

This skill holds the isolation policy that the procedure does not cover. Load both.
CLAUDE.md section 5 holds the absolute rules, and they bind whether or not you read
either file.

Three controls protect a wave. They differ in strength.

1. **Mechanical.** The deny rules in `.claude/settings.json` and the
   `block-subagent-git` hook. A subagent may read history, stage explicit paths, and
   commit its own work. It cannot push, branch, merge, rebase, reset, checkout, stash,
   clean, tag, or create a worktree.
2. **Configured.** The agents in `.claude/agents/`. A `researcher` and a `reviewer`
   hold no write tools, so they cannot write.
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

**Do not use this skill to execute an implementation plan.** A plan goes through
`superpowers:subagent-driven-development`, which dispatches one implementer at a time
and reviews each task. That skill is sequential by design. This skill covers a wave of
genuinely independent work outside a plan.

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

- Write-capable agents: the cap in CLAUDE.md section 5, normally three.
- Read-only agents: more is safe. Three to five is a common working range.

A cheaper model does not raise the cap. A cheap model needs a tighter scope, not a
looser one, because it follows a written rule less reliably.

Name the model explicitly in every dispatch. An omitted model inherits the session's
model, which is normally the most capable and most expensive one. The model you name at
dispatch overrides the `model:` field in the agent definition file.

## Step 4: Isolate every writing agent

Confirm a clean working tree first. Never fan out on top of uncommitted work.

Create one workspace per writing agent. Prefer this harness's native worktree tool,
the same order of preference that `superpowers:using-git-worktrees` sets. Fall back to
git only when no native tool exists:

```
git worktree add .worktrees/<slug> -b <branch> <base>
```

Then tell the agent its worktree path in the brief.

Know the limits of a worktree.

- A worktree isolates files. It does not isolate a database, a port, a cache, a queue,
  or any other external state.
- Give each agent its own dev database when the work touches migrations, or run those
  tasks serially.
- `.worktrees/` must be in `.gitignore`. An unignored worktree directory commits a
  whole second checkout into the repository. Run `git check-ignore -q .worktrees` to
  confirm it before you create anything.

When worktrees are disabled for the project, do not fan out write-capable agents at all.

## Step 5: Write the brief

Each brief carries five things.

1. **The task.** One outcome, stated plainly.
2. **The write scope.** The exact files or directories the agent may change. State that
   the list is complete.
3. **The contracts.** What it must not change, and the signatures it must respect.
4. **The output format.** What it must return, and in what shape.
5. **The verification.** The exact test and lint commands to run, from CLAUDE.md
   section 2.

Add one line to every brief: the agent cannot see the other agents and must not assume
their results.

Hand a large input over as a file path, not as pasted text. Everything you paste into a
brief stays in your context for the rest of the session.

Pick the agent type by role.

| Role | Agent | Model |
| --- | --- | --- |
| Find and report | `researcher` | a mid tier |
| Review against a spec | `reviewer` | a capable tier |
| Write code in a scope | `implementer` | a mid tier |

When a Superpowers skill supplies a prompt template for the role, use that template as
the brief and dispatch it on the matching agent above. The template is the content. The
agent definition is the tool grant.

## Step 6: Land the wave

Integrate one branch at a time. Never merge two at once.

For each branch:

1. Read the full diff. You own this review. Do not delegate it to the agent that wrote
   the code.
2. Rebase the branch onto the current base branch.
3. Run the full test suite and the lint and typecheck commands.
4. Fast-forward the base branch, then delete the feature branch.
5. Remove the worktree.

Only then start the next branch. A failure at step 3 stops the wave. Fix it before you
integrate anything else.

The wave is finished when the combined result passes on the base branch. It is not
finished when the agents return.

## Step 7: Report

Report what each agent actually did, not what you asked it to do. Name every task that
failed, every scope that an agent had to leave, and every check you did not run.

`superpowers:verification-before-completion` holds the rule that governs this report: no
completion claim without fresh evidence. An agent's own success report is not evidence.
The diff and the test output are.

## Failure modes to watch for

- **Silent overwrite.** Two agents wrote the same file. Step 2 prevents it.
- **Compiles but disagrees.** Two agents implemented the same contract differently.
  Step 2's contract definition prevents it.
- **Duplicated work.** Two agents built the same helper. Name the shared code in the
  briefs.
- **Blast radius.** One agent ran a destructive command. Controls 1 and 2 prevent it.
- **Review debt.** More output arrived than you can read. Step 1 question 2 prevents it.
- **Trusted report.** An agent said it passed the tests and it did not. Read the diff
  and run the suite yourself.
