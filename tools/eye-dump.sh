#!/bin/sh
# Saves PNGs of the app's own windows (default, min size, Frame, Preferences, annotations).
# Output: build/eye-dump/modern/*.png. Uses isolated app support; never touches the installed app.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/OpenSnap.app"
NEWEST=$(ls -t "$ROOT"/Sources/*.swift | head -1)
if [ ! -x "$APP/Contents/MacOS/OpenSnap" ] || [ "$NEWEST" -nt "$APP/Contents/MacOS/OpenSnap" ]; then
    sh "$ROOT/tools/build.sh"
fi
OUT="$ROOT/build/eye-dump/modern"
rm -rf "$OUT"; mkdir -p "$OUT"
SUPPORT=$(mktemp -d "${TMPDIR:-/tmp}/eye-dump-support.XXXXXX")
mkdir -p "$SUPPORT/home"
CFFIXED_USER_HOME="$SUPPORT/home" OPENSNAP_APP_SUPPORT="$SUPPORT" OPENSNAP_EVIDENCE_DIR="$SUPPORT/evidence" \
    "$APP/Contents/MacOS/OpenSnap" --eye-dump "$OUT" || echo "eye-dump exited $?" >&2
rm -rf "$SUPPORT"
echo "modern: $(ls "$OUT" | tr '\n' ' ')"
