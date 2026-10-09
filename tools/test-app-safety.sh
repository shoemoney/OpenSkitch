#!/bin/sh
# Isolated internal AppKit regression tests; never launches the production app.
# --arch x86_64 also runs under Rosetta on an Apple Silicon host.
# --app-source /path/App.swift supports a behavioral counterfactual with old App code.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
APP_SOURCE="$ROOT/Sources/App.swift"
EVIDENCE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch|--app-source|--evidence-dir)
            [ "$#" -ge 2 ] || { echo "Missing argument for $1" >&2; exit 2; }
            case "$1" in
                --arch) ARCH=$2 ;;
                --app-source) APP_SOURCE=$2 ;;
                --evidence-dir) EVIDENCE=$2 ;;
            esac
            shift 2 ;;
        *) echo "Usage: $0 [--arch arm64|x86_64] [--app-source PATH] [--evidence-dir NEW_DIRECTORY]" >&2; exit 2 ;;
    esac
done
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 2 ;; esac
if [ -z "$EVIDENCE" ]; then
    EVIDENCE=$(mktemp -d "${TMPDIR:-/tmp}/skitch-app-safety.XXXXXX")
else
    mkdir "$EVIDENCE"
fi
EVIDENCE=$(CDPATH= cd -- "$EVIDENCE" && pwd)
echo "App safety evidence: $EVIDENCE"
# A bare binary's UserDefaults.standard domain is its process name, so a unique
# name per run is a throwaway defaults domain: concurrent runs cannot share keys.
BIN="AppSafetyTests-$$-$(basename "$EVIDENCE" | tr -c 'A-Za-z0-9' '-')"
cleanup_defaults() {
    defaults delete "$BIN" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$BIN.plist"
}
trap cleanup_defaults EXIT
python3 - "$ROOT" "$APP_SOURCE" "$EVIDENCE" <<'PY'
import hashlib, json, pathlib, re, sys
root, app_source, evidence = map(pathlib.Path, sys.argv[1:])
paths = sorted((root / 'Sources').glob('*.swift')) + [root / 'tests/AppSafetyTests.swift']
if (root / 'tests/AppSafetyWebpostCases.swift').exists():
    paths.append(root / 'tests/AppSafetyWebpostCases.swift')
if (root / 'tests/AppSafetyModernCases.swift').exists():
    paths.append(root / 'tests/AppSafetyModernCases.swift')
inputs = [(p.name, app_source if p.name == 'App.swift' else p) for p in paths]
for attempt in range(3):
    snapshot = {name: (p, p.read_bytes()) for name, p in inputs}
    if all(p.read_bytes() == data for p, data in snapshot.values()):
        break
else:
    raise SystemExit('Sources kept changing; retry after the current edit finishes.')
sources = evidence / 'sources'
sources.mkdir()
originals = evidence / 'original-sources'
originals.mkdir()
manifest = []
for name, (path, data) in snapshot.items():
    (originals / name).write_bytes(data)
    target = sources / name
    if name == 'App.swift':
        text = data.decode()
        entry = re.search(r'^@main\s+@MainActor\s+enum\s+OpenSkitchMain\b', text, re.M)
        if not entry:
            raise SystemExit('Cannot safely locate and remove the production @main entry.')
        text = text[:entry.start()]
        if text.count('        installMenuPresence()\n') != 1:
            raise SystemExit('Missing menu-bar installation safety boundary.')
        text = text.replace('        installMenuPresence()\n', '')
        text = text.replace('        installHintMonitoring()\n', '')
        text = text.replace('OriginalHelpBevel(host: window)', 'OriginalHelpBevel(host: window, makePanel: { AppSafetyHelpPanel() })')
        text = text.replace('NSApp.isActive', 'AppSafetyActivation.isActive')
        text = text.replace('NSApp.currentEvent', 'AppSafetyEvents.current')
        text = text.replace('NSApp.setActivationPolicy(', 'AppSafetyPresence.setPolicy(')
        text = text.replace('else if presence != 2 { installMenuPresence() }', 'else if presence != 2 { AppSafetyPresence.installs += 1 }')
        text = text.replace('NSWorkspace.shared.accessibilityDisplayShouldReduceMotion', 'AppSafetyAnimations.reduceMotion')
        text = text.replace('statusItem?.button?.window?.frame ?? .zero', 'AppSafetyMenuDestination.rect')
        replacements = {
            'NSAlert(': 'AppSafetyAlert(',
            'NSWindow(': 'AppSafetyWindow(',
            'NSSavePanel(': 'AppSafetySavePanel(',
            'NSOpenPanel(': 'AppSafetyOpenPanel(',
            'CaptureCoordinator()': 'AppSafetyCaptureCoordinator()',
            'NSApp.activate(ignoringOtherApps: true)': 'AppSafetyActivation.suppress()',
            'NSApp.terminate(nil)': 'AppSafetyTermination.request()',
        }
        for original, replacement in replacements.items():
            if original not in text:
                raise SystemExit('Missing safety boundary: ' + original)
            text = text.replace(original, replacement)
        # Optional for older counterfactual App inputs. Never construct a live
        # manager: even an apparently safe default can come from saved settings.
        text = text.replace('GlobalHotkeyManager()', 'AppSafetyHotkeyManager()')
        text = text.replace('NSPageLayout()', 'AppSafetyPageLayout()')
        text = text.replace('NSPopover()', 'AppSafetyPopover()')
        text = text.replace('colorPopover: NSPopover?', 'colorPopover: AppSafetyPopover?')
        text = text.replace('NSPanel(contentRect: rect, styleMask: [.borderless]', 'AppSafetyDragPanel(contentRect: rect, styleMask: [.borderless]')
        if 'NSPageLayout(' in text:
            raise SystemExit('Unrecognized live Page Setup construction; refusing to run.')
        text = text.replace('NSApp.reply(toApplicationShouldTerminate: approved)', 'AppSafetyTermination.reply(approved)')
        if re.search(r'\bGlobalHotkeyManager\b', text):
            raise SystemExit('Unrecognized live hotkey-manager construction; refusing to run.')
        target.write_text(text)
    elif name == 'WindowZoom.swift':
        text = data.decode()
        if 'NSPanel(' not in text:
            raise SystemExit('Missing zoom window safety boundary.')
        target.write_text(text.replace('NSPanel(', 'AppSafetyDragPanel('))
    elif name == 'HistoryBrowser.swift':
        # History now constructs its own window. Preserve the same nonvisible
        # boundary as App.swift without modifying the production UI source.
        text = data.decode()
        if 'NSWindow(' not in text:
            raise SystemExit('Missing History window safety boundary.')
        target.write_text(text.replace('NSWindow(', 'AppSafetyWindow('))
    else:
        target.write_bytes(data)
    manifest.append({'name': name, 'path': str(path), 'sha256': hashlib.sha256(data).hexdigest()})
(evidence / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(evidence / 'support').mkdir()
(evidence / 'layout').mkdir()
PY
SDK=$(xcrun --show-sdk-path)
if ! xcrun swiftc -swift-version 5 -O -D APP_SAFETY_TESTS -sdk "$SDK" \
    -target "$ARCH-apple-macosx26.0" -framework AppKit -framework WebKit \
    -framework ImageIO \
    "$EVIDENCE"/sources/*.swift -o "$EVIDENCE/$BIN" >"$EVIDENCE/compile.log" 2>&1; then
    cat "$EVIDENCE/compile.log" >&2
    exit 1
fi
# Defence in depth: even a code path that ignores SKITCH_APP_SUPPORT lands in this throwaway home, never the owner's.
mkdir -p "$EVIDENCE/home"
set +e
env -u SKITCH_FIXTURE SKITCH_APP_SUPPORT="$EVIDENCE/support" CFFIXED_USER_HOME="$EVIDENCE/home" \
    SKITCH_EVIDENCE_DIR="$EVIDENCE/layout" APP_SAFETY_EVIDENCE="$EVIDENCE" APP_SAFETY_ARCH="$ARCH" \
    /usr/bin/arch "-$ARCH" "$EVIDENCE/$BIN" >"$EVIDENCE/run.log" 2>&1
RESULT=$?
set -e
cat "$EVIDENCE/run.log"
if [ "$RESULT" -eq 0 ]; then
    # Reproduce the real AppKit quit loop without launching a preview app or
    # ordering any window. Bound hangs and terminate only this owned child.
    python3 - "$EVIDENCE" "$ARCH" "$BIN" <<'PY'
import json, os, pathlib, subprocess, sys
evidence, arch, binary = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
env = os.environ.copy()
env.pop('SKITCH_FIXTURE', None)
(evidence / 'native-home').mkdir(exist_ok=True)
env.update(SKITCH_APP_SUPPORT=str(evidence / 'native-support'),
           CFFIXED_USER_HOME=str(evidence / 'native-home'),
           SKITCH_EVIDENCE_DIR=str(evidence / 'native-layout'),
           APP_SAFETY_EVIDENCE=str(evidence), APP_SAFETY_ARCH=arch)
(evidence / 'native-layout').mkdir()
with (evidence / 'native-termination.log').open('w') as log:
    try:
        result = subprocess.run(['/usr/bin/arch', '-' + arch, str(evidence / binary),
                                 '--native-idle-termination'], env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=10)
    except subprocess.TimeoutExpired:
        raise SystemExit('FAIL native idle termination: test child did not exit within 10 seconds')
if result.returncode != 0:
    print((evidence / 'native-termination.log').read_text())
    raise SystemExit(result.returncode)
report = json.loads((evidence / 'native-termination.json').read_text())
if not report['passed']:
    raise SystemExit('FAIL native idle termination acknowledgement')
print('PASS native AppKit idle termination (actual Capture Result shutdown, no visible windows)')
PY
fi
exit "$RESULT"
