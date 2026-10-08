#!/bin/sh
# Saves PNGs of the app's own windows (default, min size, Frame, Preferences, annotations) for Modern and Classic.
# Output: build/eye-dump/<style>/*.png. Uses isolated app support; never touches the installed app.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/OpenSkitch.app"
NEWEST=$(ls -t "$ROOT"/Sources/*.swift | head -1)
if [ ! -x "$APP/Contents/MacOS/OpenSkitch" ] || [ "$NEWEST" -nt "$APP/Contents/MacOS/OpenSkitch" ]; then
    sh "$ROOT/tools/build.sh"
fi
FIXTURE="$ROOT/original/Skitch.app/Contents/Resources/firstlaunch.skitch"
for STYLE in modern classic; do
    OUT="$ROOT/build/eye-dump/$STYLE"
    rm -rf "$OUT"; mkdir -p "$OUT"
    SUPPORT=$(mktemp -d "${TMPDIR:-/tmp}/eye-dump-support.XXXXXX")
    SKITCH_APPEARANCE=$STYLE SKITCH_APP_SUPPORT="$SUPPORT" SKITCH_FIXTURE="$FIXTURE" SKITCH_EVIDENCE_DIR="$SUPPORT/evidence" \
        "$APP/Contents/MacOS/OpenSkitch" --eye-dump "$OUT" || echo "eye-dump $STYLE exited $?" >&2
    rm -rf "$SUPPORT"
    echo "$STYLE: $(ls "$OUT" | tr '\n' ' ')"
done
