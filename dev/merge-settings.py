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
- Every top-level key the target lacks is added. For an object such as env
  or attribution, every sub-key the target lacks is added. A value the target
  already sets is left alone: it is a deliberate choice.

With OLD, the scaffold settings.json of the installed commit, the merge is
three-way, as install.sh --update needs:

- A rule, hook, or key that OLD already had and the target lacks was removed
  by the project on purpose. It is not added back.
- A rule or hook command that OLD had and SOURCE dropped is removed from the
  target. That also replaces a hook whose command changed upstream, instead
  of registering both.

The file is rewritten only when something changed, so a second install
leaves it byte-identical. Prints "ADDED REMOVED". Exits 1 on invalid JSON in
the target, and changes nothing in that case.

Usage: merge-settings.py SOURCE DEST [OLD]
"""
import json
import sys

src_path, dest_path = sys.argv[1], sys.argv[2]
old_path = sys.argv[3] if len(sys.argv) > 3 else None
with open(src_path) as f:
    src = json.load(f)
try:
    with open(dest_path) as f:
        dest = json.load(f)
except ValueError as e:
    print("invalid JSON: %s" % e)
    sys.exit(1)
old = None
if old_path:
    try:
        with open(old_path) as f:
            old = json.load(f)
    except (OSError, ValueError):
        old = None


def offered(*keys):
    """True when OLD already held the value at keys, so the target had the
    chance to keep it."""
    if old is None:
        return False
    node = old
    for k in keys:
        if isinstance(node, dict) and k in node:
            node = node[k]
        elif isinstance(node, list) and k in node:
            return True
        else:
            return False
    return True


added = 0
removed = 0

perms = dest.setdefault("permissions", {})
for kind, rules in src.get("permissions", {}).items():
    have = perms.setdefault(kind, [])
    for rule in rules:
        if rule not in have and not offered("permissions", kind, rule):
            have.append(rule)
            added += 1
if old is not None:
    for kind, rules in old.get("permissions", {}).items():
        for rule in rules:
            if rule not in src.get("permissions", {}).get(kind, []) and rule in perms.get(kind, []):
                perms[kind].remove(rule)
                removed += 1


def commands(groups):
    return {h.get("command") for g in groups for h in g.get("hooks", [])}


hooks = dest.setdefault("hooks", {})
for event, groups in src.get("hooks", {}).items():
    have = hooks.setdefault(event, [])
    offered_cmds = commands(old.get("hooks", {}).get(event, [])) if old else set()
    for group in groups:
        cmds = commands([group])
        if not cmds <= commands(have) and not cmds <= offered_cmds:
            have.append(group)
            added += 1
if old is not None:
    for event, groups in old.get("hooks", {}).items():
        dropped = commands(groups) - commands(src.get("hooks", {}).get(event, []))
        kept = []
        for group in hooks.get(event, []):
            before = len(group.get("hooks", []))
            group["hooks"] = [h for h in group.get("hooks", []) if h.get("command") not in dropped]
            removed += before - len(group["hooks"])
            if group["hooks"]:
                kept.append(group)
        if event in hooks:
            hooks[event] = kept

for key, value in src.items():
    if key in ("permissions", "hooks"):
        continue
    if key not in dest:
        if not offered(key):
            dest[key] = value
            added += 1
    elif isinstance(value, dict) and isinstance(dest[key], dict):
        for sub, sub_value in value.items():
            if sub not in dest[key] and not offered(key, sub):
                dest[key][sub] = sub_value
                added += 1

if added or removed:
    with open(dest_path, "w") as f:
        json.dump(dest, f, indent=2, ensure_ascii=False)
        f.write("\n")
print("%d %d" % (added, removed))
