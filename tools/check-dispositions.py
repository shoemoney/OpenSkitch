#!/usr/bin/env python3
"""Fail when an unimplemented row in reconstruction-progress.json lacks a disposition."""
import json
import re
import sys
from collections import Counter
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


def readme_count_problems(progress, readme):
    problems = []
    rows = [r for r in progress["features"] if r.get("status") == "unimplemented"]
    counts = Counter(r.get("disposition") for r in rows)
    for name, expected in counts.items():
        match = re.search(r"^\| `%s` \| (\d+) \|" % re.escape(str(name)), readme, re.M)
        if not match or int(match.group(1)) != expected:
            problems.append("README Not reconstructed count for %s should be %d" % (name, expected))
    retired = Counter(r["id"].split(".")[0] for r in rows if r.get("disposition") == "not_reconstructed_retired_service")
    for area, expected in retired.items():
        match = re.search(r"^\| `%s\.\*` \| (\d+) \|" % re.escape(area), readme, re.M)
        if not match or int(match.group(1)) != expected:
            problems.append("README retired-area count for %s.* should be %d" % (area, expected))
    return problems


def main(argv):
    root = Path(__file__).resolve().parent.parent
    path = Path(argv[1]) if len(argv) > 1 else root / "analysis" / "reconstruction-progress.json"
    progress = json.loads(path.read_text())
    problems = check(progress)
    if len(argv) <= 1:
        problems += readme_count_problems(progress, (root / "README.md").read_text())
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        return 1
    print("PASS every unimplemented row has a disposition")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
