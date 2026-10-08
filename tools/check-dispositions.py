#!/usr/bin/env python3
"""Fail when an unimplemented row in reconstruction-progress.json lacks a disposition."""
import json
import sys
from pathlib import Path

ALLOWED = {
    "not_reconstructed_retired_service",
    "deferred_post_0_3_0",
    "needs_user_artifact",
    "planned",
}


def check(progress):
    problems = []
    for row in progress["features"]:
        if row.get("status") != "unimplemented":
            continue
        if row.get("disposition") not in ALLOWED:
            problems.append("%s: missing or invalid disposition %r" % (row["id"], row.get("disposition")))
        elif len((row.get("disposition_reason") or "").strip()) < 10:
            problems.append("%s: missing disposition_reason" % row["id"])
    return problems


def main(argv):
    root = Path(__file__).resolve().parent.parent
    path = Path(argv[1]) if len(argv) > 1 else root / "analysis" / "reconstruction-progress.json"
    problems = check(json.loads(path.read_text()))
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        return 1
    print("PASS every unimplemented row has a disposition")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
