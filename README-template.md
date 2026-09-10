# {{PROJECT_NAME}}

<!--
TEMPLATE USAGE (delete this block once filled in)

This is the public document. `CLAUDE.md` is the internal operating manual and
`docs/` holds the long-form detail. CLAUDE.md section 6 sets the split.

1. Fill every `{{PLACEHOLDER}}`. Delete any section that does not apply. A
   half-filled README costs a reader more than a short one.
2. Write for a person who has never seen this repository and has ten minutes.
   The first screen must answer: what is this, is it for me, how do I run it.
3. Do not duplicate CLAUDE.md. The commands table in CLAUDE.md section 2 is the
   single source of truth. Repeat here only the handful a contributor needs on
   the first day, and keep the two consistent in the same commit.
4. Keep the file under ~200 lines. Link into `docs/` for depth.
5. Run `.claude/scripts/check-claude-md.sh`. It fails while a placeholder or
   this comment block remains.
-->

{{ONE_SENTENCE: what this project does, in plain language, with no jargon.}}

{{OPTIONAL_BADGES: build status, coverage, package version, license.}}

---

## What it is

{{TWO_OR_THREE_PARAGRAPHS: the problem this solves, who it serves, and what it
does differently from the obvious alternative. Name the alternative.}}

**Status:** {{prototype | active development | maintained | frozen}}. {{One line on
what that means for a reader: whether the interface is stable, and whether you
accept issues.}}

### What it is not

{{The two or three things a reader will reasonably assume and be wrong about.
This section saves more time than any other.}}

---

## Quick start

**You need:** {{runtime and version, package manager, any system dependency}}.

```
{{clone or install command}}
{{install dependencies}}
{{run}}
```

{{One line on what the reader should now see, so that they can tell it worked.}}

### Configuration

{{Delete this section when the project needs no configuration.}}

`{{.env.example}}` lists every variable. Copy it and fill it in:

```
cp {{.env.example}} .env
```

| Variable | Required | What it does |
| --- | --- | --- |
| `{{NAME}}` | {{yes / no}} | {{one line, and where to get the value}} |

Never commit a real value.

---

## Usage

{{The smallest complete example that does something useful. Show the input and
the output. A reader copies this first and reads the prose second.}}

```
{{example}}
```

{{Link to more examples in docs/ rather than growing this section.}}

---

## How it works

{{FIVE_TO_TEN_LINES: the mental model. What the main pieces are, and how a
request or a record moves through them. Enough that a reader can predict where a
given behaviour lives.}}

See [docs/architecture.md](docs/architecture.md) for the diagrams and the reasoning
behind each boundary.

---

## Project layout

```
{{path}}/          {{one line}}
{{path}}/          {{one line}}
docs/              long-form documentation, indexed in docs/index.md
CLAUDE.md          the internal operating manual for coding agents
.claude/           agent configuration: permissions, subagents, skills, hooks
```

---

## Development

{{CLAUDE.md section 2 holds the full command table. Repeat only the first-day
commands here.}}

| Purpose | Command |
| --- | --- |
| Install deps | `{{...}}` |
| Run the tests | `{{...}}` |
| Lint and typecheck | `{{...}}` |
| Build | `{{...}}` |

### Testing

{{The framework, where the tests live, and how to run one file. State the current
test count if CLAUDE.md tracks it.}}

This project is test-driven. A change arrives with the test that proves it, and the
test is written first. See `CLAUDE.md` for the full rule.

---

## Contributing

{{Delete or reduce this section for a private or personal project.}}

1. Read `CLAUDE.md` first. It holds the working agreements, the git model, and the
   documentation rules that a pull request is judged against.
2. {{Branch model: which branch to target, and how to name a branch.}}
3. Write the test before the code.
4. Update `CLAUDE.md`, this file, and the matching `docs/` entry in the same commit
   as any change that alters a command, an invariant, or an architectural boundary.
5. {{Commit message format, and whether you squash.}}

{{OPTIONAL: link a CONTRIBUTING.md, a code of conduct, or an issue template.}}

### Built with coding agents

{{Delete this section when it does not apply.}}

This repository is set up for [Claude Code](https://claude.com/claude-code) and the
`superpowers` plugin. `CLAUDE.md` and `.claude/` hold that configuration, and they
are tracked deliberately. A human reviews every change before it lands.

---

## Documentation

| Document | What it holds |
| --- | --- |
| [docs/index.md](docs/index.md) | The index of everything under `docs/`. |
| [docs/architecture.md](docs/architecture.md) | How the pieces fit together. |
| [CLAUDE.md](CLAUDE.md) | The internal operating manual. |

---

## License

{{SPDX identifier}}. See [LICENSE](LICENSE).

{{OPTIONAL: acknowledgements, citation, or contact.}}
