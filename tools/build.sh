#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=$(xcrun --show-sdk-path)
APP="$ROOT/build/Skitch Redux.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/objects"
SNAPSHOT=$(mktemp -d "$ROOT/build/source-snapshot.XXXXXX")
cp "$ROOT"/Sources/*.swift "$SNAPSHOT/"
cp "$ROOT/Info.plist" "$SNAPSHOT/Info.plist"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework AppKit -framework WebKit -framework AVFoundation -framework CoreMedia -framework ImageIO "$SNAPSHOT"/*.swift -o "$ROOT/build/objects/SkitchRedux-$ARCH"
done
xcrun lipo -create "$ROOT/build/objects/SkitchRedux-arm64" "$ROOT/build/objects/SkitchRedux-x86_64" -output "$APP/Contents/MacOS/SkitchRedux"
cp "$ROOT"/original/Skitch.app/Contents/Resources/ToolOff*.png "$ROOT"/original/Skitch.app/Contents/Resources/ToolOn*.png "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/CursorMove.png" "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/SkitchMac.icns" "$APP/Contents/Resources/"
cp "$SNAPSHOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
file "$APP/Contents/MacOS/SkitchRedux"

python3 - "$ROOT" "$SNAPSHOT" "$APP" <<'PYBUILD'
from pathlib import Path
import hashlib, json, sys
root, snapshot, app = map(Path, sys.argv[1:])
manifest = {
    "architectures": ["arm64", "x86_64"],
    "minimum_macos": "13.0",
    "source_snapshot": str(snapshot),
    "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(snapshot.iterdir()) if p.is_file()},
    "resource_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((app / "Contents/Resources").iterdir()) if p.is_file()},
    "binary_sha256": hashlib.sha256((app / "Contents/MacOS/SkitchRedux").read_bytes()).hexdigest(),
}
(root / "build/build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PYBUILD
