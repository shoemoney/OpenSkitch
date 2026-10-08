#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=$(xcrun --show-sdk-path)
APP="$ROOT/build/OpenSkitch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/objects"
SNAPSHOT=$(mktemp -d "$ROOT/build/source-snapshot.XXXXXX")
cp "$ROOT"/Sources/*.swift "$SNAPSHOT/"
cp "$ROOT/Info.plist" "$SNAPSHOT/Info.plist"
for ARCH in arm64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework AppKit -framework WebKit -framework AVFoundation -framework CoreMedia -framework ImageIO "$SNAPSHOT"/*.swift -o "$ROOT/build/objects/OpenSkitch-$ARCH"
done
cp "$ROOT/build/objects/OpenSkitch-arm64" "$APP/Contents/MacOS/OpenSkitch"
cp "$ROOT"/original/Skitch.app/Contents/Resources/ToolOff*.png "$ROOT"/original/Skitch.app/Contents/Resources/ToolOn*.png "$APP/Contents/Resources/"
for NAME in SnapCrosshair SnapISight Font ActualSizeToggleOff ActualSizeToggleOn Resize SaveToHistoryArrow Hide SnapSnap SnapCancel; do
  cp "$ROOT/original/Skitch.app/Contents/Resources/$NAME.png" "$APP/Contents/Resources/"
done
cp "$ROOT/original/Skitch.app/Contents/Resources/CursorMove.png" "$APP/Contents/Resources/"
# The Icon Composer document compiles to a Liquid Glass Assets.car plus a
# flattened OpenSkitch.icns for macOS 13-25. Older Xcodes cannot read .icon.
ICON_PARTIAL="$ROOT/build/icon-partial.plist"
if ! xcrun actool "$ROOT/Resources/OpenSkitch.icon" --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 13.0 --target-device mac --app-icon OpenSkitch \
    --output-partial-info-plist "$ICON_PARTIAL" >/dev/null 2>&1; then
  rm -f "$APP/Contents/Resources/Assets.car"
  ICONSET="$ROOT/build/OpenSkitch.iconset"
  mkdir -p "$ICONSET"
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/OpenSkitch.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT/Resources/OpenSkitch.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/OpenSkitch.icns"
fi
cp "$ROOT/Resources/OpenSkitch.png" "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/menu.png" "$ROOT/original/Skitch.app/Contents/Resources/menu-sel.png" "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/Skitch_ShowSkitch.png" "$ROOT/original/Skitch.app/Contents/Resources/Skitch_ShowSkitch_mouseover.png" "$ROOT/original/Skitch.app/Contents/Resources/Skitch_Cancel_DragMe.png" "$APP/Contents/Resources/"
cp "$ROOT"/original/Skitch.app/Contents/Resources/docWin_*.png "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/SkitchTitle.png" "$APP/Contents/Resources/"
cp "$ROOT/original/Skitch.app/Contents/Resources/sizeSlider.png" "$ROOT/original/Skitch.app/Contents/Resources/sizeSlider-indicator.png" "$APP/Contents/Resources/"
cp "$ROOT"/original/Skitch.app/Contents/Resources/SkitchCount*.png "$APP/Contents/Resources/"
cp "$ROOT"/original/Skitch.app/Contents/Resources/*.m4a "$APP/Contents/Resources/"
# Font Awesome Pro is optional and never committed: with your own token the
# fetch step builds glyph subsets under build/fonts; without them Modern
# falls back to SF Symbols. A failed fetch must not fail the build.
if [ "${OPENSKITCH_FETCH_FONTAWESOME:-0}" = 1 ]; then
  sh "$ROOT/tools/fetch-fontawesome.sh" || echo "warning: Font Awesome Pro fetch failed; building without it" >&2
fi
rm -f "$APP/Contents/Resources"/FontAwesome7Pro-*-subset.ttf
# OPENSKITCH_NO_PRO_FONTS=1 (used by tools/release.sh) skips bundling any
# subsets already sitting in build/fonts.
if [ "${OPENSKITCH_NO_PRO_FONTS:-0}" != 1 ]; then
  for FONT in "$ROOT"/build/fonts/FontAwesome7Pro-*-subset.ttf; do
    if [ -f "$FONT" ]; then cp "$FONT" "$APP/Contents/Resources/"; fi
  done
fi
cp "$SNAPSHOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
# Let Launch Services notice changed bundle resources on the next launch.
touch "$APP"
file "$APP/Contents/MacOS/OpenSkitch"

python3 - "$ROOT" "$SNAPSHOT" "$APP" <<'PYBUILD'
from pathlib import Path
import hashlib, json, sys
root, snapshot, app = map(Path, sys.argv[1:])
manifest = {
    "architectures": ["arm64"],
    "minimum_macos": "13.0",
    "source_snapshot": str(snapshot),
    "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(snapshot.iterdir()) if p.is_file()},
    "resource_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((app / "Contents/Resources").iterdir()) if p.is_file()},
    "binary_sha256": hashlib.sha256((app / "Contents/MacOS/OpenSkitch").read_bytes()).hexdigest(),
}
(root / "build/build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PYBUILD
