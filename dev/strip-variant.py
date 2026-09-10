#!/usr/bin/env python3
"""Print a CLAUDE.md variant with its usage block and section 4 removed.

self-test.sh uses it to prove that CLAUDE-template.md and CLAUDE-light.md
differ in section 4, the git model, and nowhere else. README.md and both usage
blocks promise exactly that, and a fix that lands in one variant but not the
other is the failure this catches.
"""
import re
import sys
import pathlib

text = pathlib.Path(sys.argv[1]).read_text()
text = re.sub(r"<!--\s*TEMPLATE USAGE.*?-->\n?", "", text, flags=re.S)
text = re.sub(r"## 4\. Git.*?(?=## 5\. )", "", text, flags=re.S)
sys.stdout.write(text)
