# Architecture

<!--
TEMPLATE USAGE (delete this block once the document has real content)

CLAUDE.md holds the 5 to 15 line mental model. This file holds the long form:
the diagrams, the data flows, and the reasoning behind each boundary.

Keep the two consistent. CLAUDE.md section 6 requires you to revise both in the
same commit as any change that moves an architectural boundary.
-->

## The mental model

{{The mental model that no single file contains: how the pieces fit, what calls what,
where the boundaries are.}}

## Components

| Component | Responsibility | Depends on |
| --- | --- | --- |
| {{name}} | {{one line}} | {{names}} |

## Data flow

{{Describe or diagram the path a request or a record takes through the system.}}

## Boundaries and why they sit there

{{For each boundary, name the constraint that put it there. A boundary with no
recorded reason gets moved by the next person who finds it inconvenient.}}

## Invariants

{{The things that break silently when someone violates them. Keep the short list in
CLAUDE.md and the reasoning here.}}
