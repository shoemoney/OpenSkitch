#!/bin/sh
# Build, verify and zip a release. Does not tag, push or upload.
set -eu
[ $# -eq 1 ] || { echo "usage: sh tools/release.sh VERSION" >&2; exit 2; }
VERSION=$1
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/OpenSkitch.app"
ZIP="$ROOT/build/OpenSkitch-$VERSION-arm64.zip"

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")
if [ "$VERSION" != "$PLIST_VERSION" ]; then
  echo "release: VERSION $VERSION does not match Info.plist $PLIST_VERSION" >&2
  exit 1
fi

unset OPENSKITCH_FETCH_FONTAWESOME
# build.sh reuses the bundle in place, so start clean or stale resources ship.
rm -rf "$APP"
OPENSKITCH_NO_PRO_FONTS=1 sh "$ROOT/tools/build.sh"

# OPENSKITCH_RELEASE_TEST_INJECT_FONT is a test hook that plants a dummy font
# after the build so the guard below can be proven to fail.
if [ -n "${OPENSKITCH_RELEASE_TEST_INJECT_FONT:-}" ]; then
  : > "$APP/Contents/Resources/$OPENSKITCH_RELEASE_TEST_INJECT_FONT"
fi

FONTS=$(find "$APP/Contents/Resources" \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff*' \))
if [ -n "$FONTS" ]; then
  echo "release: font files found in the bundle (Font Awesome Pro must never ship):" >&2
  echo "$FONTS" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE=$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^Signature=//p')
[ -n "$SIGNATURE" ] || SIGNATURE=unknown

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

python3 - "$ROOT" "$VERSION" "$APP" "$ZIP" "$SIGNATURE" <<'PYREL'
from pathlib import Path
import hashlib, json, subprocess, sys
root, version, app, zip_path, signature = sys.argv[1:]
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
git_sha = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
manifest = {
    "version": version,
    "git_sha": git_sha,
    "binary_sha256": sha(app + "/Contents/MacOS/OpenSkitch"),
    "zip": Path(zip_path).name,
    "zip_sha256": sha(zip_path),
    "signature": signature,
    "notarized": False,
}
Path(root, "build/release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PYREL
cat "$ROOT/build/release-manifest.json"
echo "release: $ZIP"
