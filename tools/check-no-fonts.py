#!/usr/bin/env python3
"""Exit 1 if a bundle contains any font file, by extension or by magic bytes.

Usage: check-no-fonts.py PATH   (the whole .app, not just Contents/Resources)
Nothing is excluded: every entry under PATH is checked.
"""
import os
import sys

EXTENSIONS = {".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2", ".dfont", ".eot", ".pfb"}
MAGICS = {b"OTTO": "OpenType/CFF", b"\x00\x01\x00\x00": "TrueType", b"true": "TrueType (Apple)",
          b"ttcf": "TrueType collection", b"wOFF": "WOFF", b"wOF2": "WOFF2"}

root = sys.argv[1]
hits = []
for directory, _, names in os.walk(root):
    for name in names:
        path = os.path.join(directory, name)
        if os.path.splitext(name)[1].lower() in EXTENSIONS:
            hits.append((path, "font extension"))
            continue
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            head = handle.read(4)
        if head in MAGICS:
            hits.append((path, "font magic bytes: " + MAGICS[head]))
for path, why in hits:
    print("font found (%s): %s" % (why, path), file=sys.stderr)
sys.exit(1 if hits else 0)
