#!/usr/bin/env python3
"""Exit 1 if the retired product name appears where it must not.

The shipped product is OpenSnap. The previous name may appear (case-insensitively, in file names and in contents)
only in the places that deliberately deal with the old data and old assets:
  - the one-time migration and the only reader of the retired formats,
  - the migration and retired-format tests and the fixtures built for them,
  - this gate, and the original-asset name list and hash list that keep original art out of the bundle.
Scanned: Sources/, tools/, tests/, Info.plist, Resources/. A second check keeps the retired-format reader
reachable only from Migration: no other source file may mention its symbols.
Usage: check-skitch-strings.py   (from anywhere; paths are relative to the repository root)
"""
from pathlib import Path
import fnmatch
import re
import sys

root = Path(__file__).resolve().parent.parent
NEEDLE = re.compile(rb"skitch", re.I)
# Naming the gate itself (to run it) is not a use of the retired name.
GATE_NAME = re.compile(rb"check-skitch-strings", re.I)
SCANNED = ["Sources", "tools", "tests", "Resources", "Info.plist"]
ALLOWED = [
    "Sources/Migration.swift",
    "Sources/LegacyReader.swift",
    "tools/real_store_guard.py",
    "tests/MigrationTests.swift",
    "tests/AppSafetyRetiredFormatCases.swift",
    "tests/fixtures/legacy-sample*",
    "tools/check-skitch-strings.py",
    "tools/check-no-original.py",
    "tools/original-resource-hashes.txt",
]
READER_ALLOWED = {"Sources/Migration.swift", "Sources/LegacyReader.swift"}
READER_SYMBOLS = re.compile(r"LegacyDocumentReader|LegacyDocumentContent|LegacySkitch|LegacyBridge")


def allowed(relative):
    return any(fnmatch.fnmatch(relative, pattern) for pattern in ALLOWED)


def files():
    for name in SCANNED:
        base = root / name
        if base.is_file():
            yield base
        elif base.is_dir():
            for path in sorted(base.rglob("*")):
                if path.is_file() and ".DS_Store" not in path.name and "__pycache__" not in path.parts:
                    yield path


problems = []
for path in files():
    relative = path.relative_to(root).as_posix()
    if allowed(relative):
        continue
    if NEEDLE.search(relative.encode()):
        problems.append(f"{relative}: file name contains the retired product name")
    data = path.read_bytes()
    for number, line in enumerate(data.split(b"\n"), 1):
        if NEEDLE.search(GATE_NAME.sub(b"", line)):
            problems.append(f"{relative}:{number}: {line.decode('utf-8', 'replace').strip()[:140]}")

for path in sorted((root / "Sources").glob("*.swift")):
    relative = path.relative_to(root).as_posix()
    if relative in READER_ALLOWED:
        continue
    for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        if READER_SYMBOLS.search(line):
            problems.append(f"{relative}:{number}: reaches the retired-format reader (only Migration may): {line.strip()[:120]}")

for line in problems[:200]:
    print(line, file=sys.stderr)
if problems:
    print(f"FAIL check-skitch-strings: {len(problems)} problem(s)", file=sys.stderr)
    sys.exit(1)
print("PASS check-skitch-strings (retired product name only in the migration, its tests/fixtures and the original-asset lists)")
