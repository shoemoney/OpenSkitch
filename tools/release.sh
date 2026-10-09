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

if ! git -C "$ROOT" diff --quiet HEAD; then
  echo "release: tracked files differ from HEAD; commit or discard first" >&2
  exit 1
fi
UNTRACKED=$(git -C "$ROOT" ls-files --others --exclude-standard -- Sources Resources Info.plist tools)
if [ -n "$UNTRACKED" ]; then
  echo "release: untracked files in release inputs:" >&2
  echo "$UNTRACKED" >&2
  exit 1
fi

unset OPENSKITCH_FETCH_FONTAWESOME
# build.sh reuses the bundle in place, so start clean or stale resources ship.
rm -rf "$APP"
OPENSKITCH_NO_PRO_FONTS=1 sh "$ROOT/tools/build.sh"

# Everything below works on a private copy so a concurrent build or test run
# that rewrites build/OpenSkitch.app cannot change what is checked and shipped.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/OpenSkitch.app"

python3 "$ROOT/tools/check-no-fonts.py" "$STAGE/OpenSkitch.app" || {
  echo "release: font files found in the bundle (Font Awesome Pro must never ship)" >&2
  exit 1
}

python3 "$ROOT/tools/check-no-original.py" "$STAGE/OpenSkitch.app" || {
  echo "release: original Skitch assets or sounds found in the bundle" >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$STAGE/OpenSkitch.app"
SIGNATURE=$(codesign -dvvv "$STAGE/OpenSkitch.app" 2>&1 | sed -n 's/^Signature=//p')
[ -n "$SIGNATURE" ] || SIGNATURE=unknown

rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE/OpenSkitch.app" "$ZIP"

python3 - "$ROOT" "$VERSION" "$STAGE/OpenSkitch.app" "$ZIP" "$SIGNATURE" <<'PYREL'
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
