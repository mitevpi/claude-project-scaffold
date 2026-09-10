---
name: ste-writing
description: The ASD-STE100 Simplified Technical English writing rules. Load it when you write or edit documentation, a research report, a README, a commit message, a specification, or any longer piece of user-facing text, and when you must check a document against the rules or rewrite an ambiguous passage.
---

# ASD-STE100 writing rules

CLAUDE.md section 9 holds the short form of this rule. This skill holds the full rule set and the examples.

## What the standard is

ASD-STE100 is a controlled natural language. The European airline industry asked for it in 1979, because most European mechanics read English maintenance manuals as a second language. A misread instruction on an aircraft kills people. The current edition is Issue 9, published in January 2025. It has 53 writing rules and a dictionary of about 900 approved words.

We apply the writing rules. We do not apply the dictionary, because it is a copyright document of ASD and its vocabulary covers aircraft maintenance.

**Therefore: write "follows the ASD-STE100 writing rules". Never write "STE compliant".**

## Why we use it

The standard protects a reader who cannot ask a follow-up question. A person who reads agent output is in that position. They did not see what the agent saw. They read a summary and they act on it.

Ambiguous output transfers a false belief to that reader. The reader has no cheap way to detect it.

## The rules

### Words

- Prefer the short, common word. Write "use", not "utilize". Write "start", not "commence".
- Give a word one meaning across a document. Do not write "close the connection" and "close the meeting" in the same file.
- Write no more than three words in a multi-word noun.
  - Wrong: `user account permission update handler`
  - Right: `the handler that updates account permissions`

### Verbs

Use these forms only:

- the infinitive: "to build"
- the imperative: "Run the tests."
- the simple present: "The worker reads the queue."
- the simple past: "The build failed."
- the simple future: "The migration will drop the column."
- the past participle as an adjective: "the deleted record"

Do not chain auxiliaries.

- Wrong: "We have been seeing the tests fail."
- Right: "The tests failed three times."

Use an "-ing" form only as a technical noun, or inside one.

- Wrong: "Running the suite, you will see the error."
- Right: "Run the suite. The error appears."
- Allowed: "the logging module", "a rolling release"

### Voice

- Use the active voice in every instruction and procedure.
- Use the passive voice only in descriptive text, and only when the actor is genuinely unknown.

The passive voice hides the actor. That is the exact failure this standard exists to prevent.

- Wrong: "The config is read at boot."  Read by what?
- Right: "The worker reads the config at boot."

### Sentences

- Write one instruction per sentence.
- Procedures: 20 words maximum.
- Descriptive text: 25 words maximum.
- Keep the subject, the verb, and the article. Never drop them to shorten a sentence. A clipped sentence is more ambiguous, not clearer.
  - Wrong: "Returns error if missing."
  - Right: "The function returns an error when the field is missing."
- Replace a complex sentence with a vertical list.

### Paragraphs

- Write one topic per paragraph.
- Write no more than six sentences in a paragraph.

### Warnings and safety

Start a warning with the command or the condition. Put it before the step it protects, never after.

- Wrong: "Run the migration, but note that it drops the column."
- Right: "This migration drops the `legacy_id` column. Back up the table first. Then run the migration."

## Where the rules apply

| Surface | Applies |
| --- | --- |
| Chat replies to the user | Yes |
| Documentation and README | Yes |
| Research reports | Yes |
| Commit messages | Yes |
| Code comments | Yes |
| Agent briefs and subagent output | Yes |
| Code identifiers | No. Follow the language convention. |
| A direct quotation | No. Quote it exactly. |

## Two things the standard does not do

First, ASD states that STE cannot be used alone. It works with a style guide, not instead of one. Our voice rules and our house style still apply.

Second, the rules do not make a statement true. A checker can confirm that a sentence follows the rules and still pass a sentence that is wrong. Clarity is not accuracy. Verify the claim, then write it clearly.

## A worked rewrite

Before, 41 words, passive, buried condition:

> It should be noted that the caching layer, which is being introduced in this change, will potentially cause stale reads to be returned to clients in the event that the invalidation hook has not been correctly registered by the caller.

After:

> This change adds a caching layer. The caller must register the invalidation hook. An unregistered hook causes stale reads.

Three sentences. Active voice. 21 words. The actor and the condition are both visible.
