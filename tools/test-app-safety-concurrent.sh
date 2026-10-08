#!/bin/sh
# Launches Classic and Modern app-safety at the same moment and requires both to pass.
# Proves concurrent runs on one host no longer share a binary name or a defaults domain.
# --script PATH runs a different runner (used to reproduce the old shared-name failure).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/tools/test-app-safety.sh"
ARCH=$(uname -m)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --script) [ "$#" -ge 2 ] || { echo "Missing argument for $1" >&2; exit 2; }; SCRIPT=$2; shift 2 ;;
        --arch) [ "$#" -ge 2 ] || { echo "Missing argument for $1" >&2; exit 2; }; ARCH=$2; shift 2 ;;
        *) echo "Usage: $0 [--arch arm64|x86_64] [--script PATH]" >&2; exit 2 ;;
    esac
done
OUT=$(mktemp -d "${TMPDIR:-/tmp}/skitch-app-safety-concurrent.XXXXXX")
"$SCRIPT" --arch "$ARCH" --appearance classic >"$OUT/classic.log" 2>&1 & CLASSIC=$!
"$SCRIPT" --arch "$ARCH" --appearance modern >"$OUT/modern.log" 2>&1 & MODERN=$!
RC=0
wait "$CLASSIC" || { echo "FAIL concurrent classic (log: $OUT/classic.log)" >&2; RC=1; }
wait "$MODERN" || { echo "FAIL concurrent modern (log: $OUT/modern.log)" >&2; RC=1; }
grep -E "^(PASS|FAIL)|passed|failed" "$OUT/classic.log" | tail -n 2 | sed 's/^/classic: /'
grep -E "^(PASS|FAIL)|passed|failed" "$OUT/modern.log" | tail -n 2 | sed 's/^/modern:  /'
[ "$RC" -eq 0 ] && echo "PASS concurrent app-safety (classic + modern in parallel)"
exit "$RC"
