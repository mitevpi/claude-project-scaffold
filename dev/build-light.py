#!/usr/bin/env python3
"""Build CLAUDE-light.md from CLAUDE-template.md and dev/light-variant.md.

The light manual differs from the FULL one in two places: the variant note in
the usage block, and the first two bullets of the Git section's branch model.
Everything else is generated, so a fix to the FULL manual reaches the light one
the next time this script runs, and self-test.sh fails until it does.

Usage:
  python3 dev/build-light.py           print the light manual
  python3 dev/build-light.py --write   write it to CLAUDE-light.md

Each replacement must match exactly once. A template edit that moves an anchor
stops the build with an error instead of producing a wrong file.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
full = (root / "CLAUDE-template.md").read_text()
fragments = (root / "dev" / "light-variant.md").read_text()


def fragment(name):
    m = re.search(r"<!-- %s -->\n(.*?)(?=\n<!-- |\Z)" % re.escape(name), fragments, re.S)
    if not m:
        sys.exit("dev/light-variant.md has no fragment named %r" % name)
    return m.group(1).rstrip("\n") + "\n"


def replace_once(text, pattern, replacement, what):
    matches = re.findall(pattern, text, re.S)
    if len(matches) != 1:
        sys.exit("build-light: %s matched %d times in CLAUDE-template.md, not once" % (what, len(matches)))
    return re.sub(pattern, lambda _: replacement, text, count=1, flags=re.S)


light = replace_once(full, r"FULL variant\..*?\n(?=\n)", fragment("usage"), "the FULL variant note")

model = re.search(r"### Branch model\n.*?(?=\n### )", light, re.S)
if not model:
    sys.exit("build-light: CLAUDE-template.md has no Branch model subsection")
section = model.group(0)
section = replace_once(
    section,
    r"- \*\*The base branch is .*?(?=- \*\*Land a branch)",
    fragment("base-bullets"),
    "the first two branch-model bullets",
)
section = section.replace("{{feature-dev}}", "{{main}}")
light = light[: model.start()] + section + light[model.end():]

if "--write" in sys.argv[1:]:
    (root / "CLAUDE-light.md").write_text(light)
else:
    sys.stdout.write(light)
