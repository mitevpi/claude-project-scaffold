#!/usr/bin/env python3
"""Merge the scaffold's settings.json into a target's existing settings.json.

install.sh calls it when the target already has .claude/settings.json. A
skipped settings file would leave the hooks on disk but never registered,
and the check script would have nothing to catch. So the scaffold's rules and
hooks are merged in instead.

- Every permission rule the target lacks is appended. Existing rules stay,
  in their order. Deny still beats allow in Claude Code, so a target's own
  allow rule never weakens a scaffold deny rule.
- Every hook group whose command the target lacks is appended.
- Every top-level key the target lacks is added. A key the target already
  sets is left alone: the target's value is a deliberate choice.

The file is rewritten only when something was added, so a second install
leaves it byte-identical. Prints the number of additions. Exits 1 on
invalid JSON in the target, and changes nothing in that case.

Usage: merge-settings.py SOURCE DEST
"""
import json
import sys

src_path, dest_path = sys.argv[1], sys.argv[2]
with open(src_path) as f:
    src = json.load(f)
try:
    with open(dest_path) as f:
        dest = json.load(f)
except ValueError as e:
    print("invalid JSON: %s" % e)
    sys.exit(1)

added = 0

perms = dest.setdefault("permissions", {})
for kind, rules in src.get("permissions", {}).items():
    have = perms.setdefault(kind, [])
    for rule in rules:
        if rule not in have:
            have.append(rule)
            added += 1


def commands(groups):
    return {h.get("command") for g in groups for h in g.get("hooks", [])}


hooks = dest.setdefault("hooks", {})
for event, groups in src.get("hooks", {}).items():
    have = hooks.setdefault(event, [])
    for group in groups:
        if not commands([group]) <= commands(have):
            have.append(group)
            added += 1

for key, value in src.items():
    if key not in dest:
        dest[key] = value
        added += 1

if added:
    with open(dest_path, "w") as f:
        json.dump(dest, f, indent=2)
        f.write("\n")
print(added)
