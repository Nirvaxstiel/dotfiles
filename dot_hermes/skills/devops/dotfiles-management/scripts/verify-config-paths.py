#!/usr/bin/env python3
"""Resolve every relative reference in a config tree; fail on a broken one.

Use when the native validator cannot run locally -- no Nix on the editing host, a
chezmoi source you cannot apply -- because a wrong relative path is exactly the
failure that a file move introduces and the one you cannot see by reading.

    python verify-config-paths.py <repo-root>

Exit 0 = every relative reference resolves. Exit 1 = the broken ones are listed.
"""

import os
import re
import sys

EXTS = (".nix", ".kdl", ".toml", ".yaml", ".yml", ".json", ".lua", ".sh")
SKIP_DIRS = {".git", "node_modules", ".venv", "__pycache__"}
# a relative reference to a real file: ./x.nix, ../y/z.kdl -- not a URL, not a
# bare filename, not a dotted attribute path.
REF = re.compile(r"(?<![\w./-])(\.\.?/[\w./@+-]+\.(?:nix|kdl|toml|yaml|yml|json|lua|sh))")


def main(argv):
    root = argv[1] if len(argv) > 1 else "."
    if not os.path.isdir(root):
        print(f"not a directory: {root}")
        return 2
    checked = broken = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(EXTS):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for match in REF.finditer(text):
                ref = match.group(1)
                checked += 1
                if not os.path.exists(os.path.normpath(os.path.join(dirpath, ref))):
                    broken += 1
                    print(f"BROKEN  {os.path.relpath(path, root)}  ->  {ref}")
    print(f"{checked} relative references checked, {broken} broken")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
