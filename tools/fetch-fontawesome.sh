#!/bin/sh
# Optional: fetch Font Awesome Pro and subset it to the glyphs Sources/FontAwesomeIcons.swift uses.
# Needs your own Pro token: $FONTAWESOME_TOKEN, else the aigate "fontawesome" key.
# Output goes to the git-ignored build/fonts; nothing from Font Awesome Pro is ever committed.
# Exit 3 means no token was available. Requires npm, woff2_decompress and fontTools (pyftsubset).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=7.3.1
TABLE="$ROOT/Sources/FontAwesomeIcons.swift"
FONTS="$ROOT/build/fonts"

fail() { echo "fetch-fontawesome: $1" >&2; exit "${2:-1}"; }
aigate_token() {
    [ -r "$HOME/.claude/aigate/env" ] || return 1
    set -a; . "$HOME/.claude/aigate/env"; set +a
    # The aigate credential travels through curl's stdin config so it never lands in argv.
    printf 'header = "Authorization: Bearer %s"\n' "${AIGATE_TOKEN:-}" |
        curl -fsS -m 20 -K - "${AIGATE_URL:-}/api/keys/fontawesome" |
        python3 -c 'import json, sys; print(json.load(sys.stdin)["key"])'
}

for TOOL in npm woff2_decompress pyftsubset python3 curl; do
    command -v "$TOOL" >/dev/null 2>&1 || fail "$TOOL is required but not installed"
done
[ -f "$TABLE" ] || fail "Sources/FontAwesomeIcons.swift is missing, so there is no glyph list to subset"
UNICODES=$(grep -oE '0x[0-9A-Fa-f]{2,5}' "$TABLE" | sed 's/^0x//' | tr 'a-f' 'A-F' | sort -u | sed 's/^/U+/' | paste -sd, -)
[ -n "$UNICODES" ] || fail "Sources/FontAwesomeIcons.swift lists no 0x codepoints, so there is nothing to subset"

TOKEN=${FONTAWESOME_TOKEN:-}
[ -n "$TOKEN" ] || TOKEN=$( (aigate_token) 2>/dev/null || true )
[ -n "$TOKEN" ] || fail "no Font Awesome Pro token: set FONTAWESOME_TOKEN, or store one in aigate as provider 'fontawesome'" 3
case "$TOKEN" in *[!A-Za-z0-9._-]*) fail "the Font Awesome Pro token has unexpected characters" 3 ;; esac

# The token only ever exists inside this npmrc, which lives outside the working tree.
SECRETS=$(mktemp -d "${TMPDIR:-/tmp}/opensnap-fa.XXXXXX")
mkdir -p "$ROOT/build"
WORK=$(mktemp -d "$ROOT/build/fontawesome.XXXXXX")
trap 'rm -rf "$SECRETS" "$WORK"' EXIT
trap 'exit 1' INT TERM HUP
case "$SECRETS" in "$ROOT"/*) fail "refusing to keep credentials inside the repository" ;; esac
NPMRC="$SECRETS/npmrc"
(umask 077; printf '@fortawesome:registry=https://npm.fontawesome.com/\n//npm.fontawesome.com/:_authToken=%s\n' "$TOKEN" > "$NPMRC")
chmod 600 "$NPMRC"

cd "$WORK"
if ! NPM_CONFIG_USERCONFIG="$NPMRC" npm_config_update_notifier=false npm_config_logs_max=0 \
    npm pack "@fortawesome/fontawesome-pro@$VERSION" --pack-destination "$WORK" --ignore-scripts --loglevel=error >"$WORK/npm.log" 2>&1; then
    sed "s/$TOKEN/***/g" "$WORK/npm.log" >&2
    fail "npm could not pack @fortawesome/fontawesome-pro@$VERSION"
fi
mkdir "$WORK/pkg"
tar -xzf "$WORK"/fortawesome-fontawesome-pro-*.tgz -C "$WORK/pkg" \
    package/webfonts/fa-regular-400.woff2 package/webfonts/fa-solid-900.woff2 package/LICENSE.txt \
    || fail "the Font Awesome package does not contain the expected webfonts"

mkdir -p "$FONTS"
for PAIR in regular-400:Regular solid-900:Solid; do
    SOURCE=${PAIR%%:*}
    FAMILY=${PAIR##*:}
    woff2_decompress "$WORK/pkg/package/webfonts/fa-$SOURCE.woff2" >/dev/null
    pyftsubset "$WORK/pkg/package/webfonts/fa-$SOURCE.ttf" --unicodes="$UNICODES" --no-hinting --desubroutinize \
        --output-file="$FONTS/FontAwesome7Pro-$FAMILY-subset.ttf"
done
cp "$WORK/pkg/package/LICENSE.txt" "$FONTS/FontAwesome-Pro-LICENSE.txt"

python3 -I - "$FONTS" "$UNICODES" <<'PYSUBSET'
import pathlib, sys
from fontTools.ttLib import TTFont
fonts, unicodes = pathlib.Path(sys.argv[1]), [int(u[2:], 16) for u in sys.argv[2].split(",")]
summary = []
for family in ("Regular", "Solid"):
    path = fonts / f"FontAwesome7Pro-{family}-subset.ttf"
    font = TTFont(path)
    name = font["name"].getDebugName(6)
    missing = [f"U+{u:04X}" for u in unicodes if u not in font.getBestCmap()]
    size = path.stat().st_size
    if name != f"FontAwesome7Pro-{family}":
        raise SystemExit(f"fetch-fontawesome: {path.name} has PostScript name {name!r}, expected FontAwesome7Pro-{family}")
    if missing:
        raise SystemExit(f"fetch-fontawesome: {path.name} lacks glyphs for {', '.join(missing)}")
    if size >= 20480:
        raise SystemExit(f"fetch-fontawesome: {path.name} is {size} bytes; a subset should stay under 20 KB")
    summary.append(f"{family.lower()} {size} B")
print(f"fetch-fontawesome: {len(unicodes)} glyphs, {', '.join(summary)} -> build/fonts")
PYSUBSET
