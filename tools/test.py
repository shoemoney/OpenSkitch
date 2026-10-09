#!/usr/bin/env python3
"""Run independent native regression suites against a consistent source snapshot."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, sys, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
options = parser.parse_args()
root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_store_guard as guard
REAL_STORE_FOLDERS, SUPPORT = guard.REAL_STORE_FOLDERS, guard.SUPPORT
OPENSNAP_FOLDER_EXISTED = guard.OPENSNAP_FOLDER.exists()

def real_store_snapshot():
    return guard.snapshot()

def check_real_store(before):
    problems = guard.compare(before, OPENSNAP_FOLDER_EXISTED, PLISTS_BEFORE)
    if problems:
        raise SystemExit("FAIL real-store-guard: the owner's real stores " + str(guard.describe()) + " were touched by this run:\n" + "\n".join(problems))
    print("PASS real-store-guard (", len(guard.snapshot()[1]), "files in", len(REAL_STORE_FOLDERS), "real-store folders and 2 defaults files unchanged; OpenSnap folder not created; throwaway preference plists", len(PLISTS_BEFORE), "before /", len(guard.throwaway_plists()), "after, none new )", flush=True)

real_store_folder, real_store_before = real_store_snapshot()
PLISTS_BEFORE = guard.throwaway_plists()

def secrets_guard():
    """Licensed fonts and registry credentials must never become committable."""
    forbidden = re.compile(r"\.(ttf|otf|woff2?)$|(^|/)(\.npmrc|package-lock\.json)$|(^|/)node_modules/|(^|/)fortawesome-fontawesome-pro-[^/]*\.tgz$", re.I)
    listing = subprocess.run(["/usr/bin/git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True)
    problems = [f"committable licensed/credential file: {name}" for name in listing.stdout.splitlines() if forbidden.search(name)]
    token = re.compile(rb"_authToken=[0-9A-Fa-f-]{36}")
    for folder in ("Sources", "tools", "tests"):
        for path in sorted((root / folder).rglob("*")):
            if path.is_file() and token.search(path.read_bytes()):
                problems.append(f"registry auth token in {path.relative_to(root)}")
    if problems:
        raise SystemExit("FAIL secrets-guard\n" + "\n".join(problems))
    return "secrets-guard"

print("PASS", secrets_guard(), flush=True)
# The retired product name stays confined to the migration; the reader of retired formats stays unreachable from the app.
subprocess.run([sys.executable, str(root / "tools" / "check-skitch-strings.py")], cwd=root, check=True)
snapshot = Path(tempfile.mkdtemp(prefix="test-snapshot.", dir=build))

def current_inputs():
    return sorted((root / "Sources").glob("*.swift")) + sorted((root / "tests").glob("*.swift"))

inputs = current_inputs()
for attempt in range(3):
    contents = {path: path.read_bytes() for path in inputs}
    if all(path.read_bytes() == data for path, data in contents.items()):
        break
else:
    raise SystemExit("Sources changed while taking the snapshot; rerun after edits finish.")
for path, data in contents.items():
    (snapshot / path.name).write_bytes(data)
manifest = {str(path.relative_to(root)): hashlib.sha256(data).hexdigest() for path, data in contents.items()}
(snapshot / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

def suite(name, sources, test, define=None, arguments=(), environment=None, optional=False):
    if optional:
        for needed in [*sources, test]:
            if not (snapshot / needed).exists():
                return "SKIP", f"{name}: {needed} not present"
    binary = snapshot / name
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", options.arch + "-apple-macosx26.0"]
    if define:
        command += ["-D", define]
    command += [str(snapshot / source) for source in sources]
    command += [str(snapshot / test), "-o", str(binary)]
    subprocess.run(command, cwd=root, check=True)
    env = None
    if environment:
        env = dict(os.environ)
        for key, value in environment.items():
            env[key] = tempfile.mkdtemp(prefix="home-", dir=snapshot) if value == "@temp-home" else value
    subprocess.run([str(binary), *arguments], cwd=root, check=True, env=env)
    return "PASS", name

# Subsets from tools/fetch-fontawesome.sh are exercised when they have been built.
fonts = root / "build/fonts"
font_environment = os.environ | {"OPENSNAP_FA_FONT_DIR": str(fonts)} if any(fonts.glob("*-subset.ttf")) else None

suites = [
    ("original-action-button-tests", ["OriginalActionButton.swift"], "OriginalActionButtonTests.swift", "ORIGINAL_ACTION_BUTTON_TESTS", ()),
    ("original-capture-timing-tests", ["OriginalCaptureTiming.swift"], "OriginalCaptureTimingTests.swift", "ORIGINAL_CAPTURE_TIMING_TESTS", ()),
    ("original-capture-picker-tests", ["OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift", "TestDefaults.swift"], "OriginalCapturePickerTests.swift", "ORIGINAL_CAPTURE_PICKER_TESTS", ()),
    ("original-capture-countdown-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureCountdown.swift"], "OriginalCaptureCountdownTests.swift", "ORIGINAL_CAPTURE_COUNTDOWN_TESTS", ()),
    ("original-hint-messages-tests", ["SVGPath.swift", "DocumentModel.swift", "OriginalHintMessages.swift"], "OriginalHintMessagesTests.swift", "ORIGINAL_HINT_MESSAGES_TESTS", ()),
    ("original-help-bevel-tests", ["OriginalHelpBevel.swift"], "OriginalHelpBevelTests.swift", "ORIGINAL_HELP_BEVEL_TESTS", ()),
    ("window-zoom-tests", ["WindowZoom.swift"], "WindowZoomTests.swift", "WINDOW_ZOOM_TESTS", ()),
    ("text-style-form-tests", ["TextStyleForm.swift"], "TextStyleFormTests.swift", "TEXT_STYLE_FORM_TESTS", ()),
    ("general-preferences-form-tests", ["SVGPath.swift", "StrokeFitting.swift", "GeneralPreferencesForm.swift"], "GeneralPreferencesFormTests.swift", "GENERAL_PREFERENCES_FORM_TESTS", ()),
    ("original-general-preferences-tests", ["SVGPath.swift", "StrokeFitting.swift", "DocumentModel.swift", "GeneralPreferencesForm.swift", "OriginalGeneralPreferences.swift", "TestDefaults.swift"], "OriginalGeneralPreferencesTests.swift", "ORIGINAL_GENERAL_PREFERENCES_TESTS", ()),
    ("resize-presets-tests", ["ResizePresets.swift", "TestDefaults.swift"], "ResizePresetsTests.swift", "RESIZE_PRESETS_TESTS", ()),
    ("window-sizing-tests", ["WindowSizing.swift"], "WindowSizingTests.swift", "WINDOW_SIZING_TESTS", ()),
    ("canvas-navigator-tests", ["CanvasNavigator.swift"], "CanvasNavigatorTests.swift", "CANVAS_NAVIGATOR_TESTS", ()),
    ("canvas-border-tests", ["WindowSizing.swift", "CanvasBorderView.swift"], "CanvasBorderTests.swift", "CANVAS_BORDER_TESTS", ()),
    ("resize-panel-tests", ["ResizePresets.swift", "ResizePanel.swift"], "ResizePanelTests.swift", "RESIZE_PANEL_TESTS", ()),
    ("export-accessory-tests", ["ExportAccessory.swift"], "ExportAccessoryTests.swift", "EXPORT_ACCESSORY_TESTS", ()),
    ("image-export-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "ImageExport.swift"], "ImageExportTests.swift", "IMAGE_EXPORT_TESTS", ()),
    ("vector-geometry-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift"], "VectorGeometryTests.swift", "VECTOR_GEOMETRY_TESTS", ()),
    ("stroke-fitting-tests", ["SVGPath.swift", "StrokeFitting.swift"], "StrokeFittingTests.swift", "STROKE_FITTING_TESTS", ()),
    ("canvas-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift"], "CanvasTests.swift", "CANVAS_TESTS", ()),
    ("history-store-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift", "HistoryStore.swift"], "HistoryStoreTests.swift", "HISTORY_STORE_TESTS", ()),
    ("history-browser-tests", ["HistoryBrowser.swift", "TestDefaults.swift"], "HistoryBrowserTests.swift", "HISTORY_BROWSER_TESTS", ()),
    ("history-remote-deletion-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", "HistoryRemoteDeletion.swift"], "HistoryRemoteDeletionTests.swift", None, ("--test",)),
    ("publishing-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingTests.swift", None, ("--test",)),
    ("publishing-shutdown-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingShutdownTests.swift", None, ("--test",)),
    ("publishing-destinations-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingDestinationsTests.swift", None, ("--test",)),
    ("hotkey-tests", ["GlobalHotkeys.swift", "TestDefaults.swift"], "GlobalHotkeysTests.swift", "GLOBAL_HOTKEY_TESTS", ()),
    ("svg-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "SVGExport.swift"], "SVGExportTests.swift", "SVG_EXPORT_TESTS", ()),
    ("opensnap-file-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift"], "OpenSnapFileTests.swift", "OPENSNAP_FILE_TESTS", ()),
    ("migration-tests", ["SVGPath.swift", "LegacyReader.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift", "HistoryStore.swift", "Migration.swift"], "MigrationTests.swift", "MIGRATION_TESTS", (), {"CFFIXED_USER_HOME": "@temp-home"}),
    ("capture-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift", "OriginalCaptureCountdown.swift", "OriginalCaptureFlash.swift", "Capture.swift"], "CaptureTests.swift", "CAPTURE_TESTS", ()),
    ("photo-browser-tests", ["PhotoBrowser.swift"], "PhotoBrowserTests.swift", None, ()),
]
# Modern appearance suites are skipped, not failed, while their files are not in the tree yet.
optional_suites = [
    ("fontawesome-icons-tests", ["FontAwesomeIcons.swift", "ChromeIcons.swift"], "FontAwesomeIconsTests.swift", "FONTAWESOME_ICONS_TESTS", (), font_environment),
    ("menu-symbols-tests", ["FontAwesomeIcons.swift", "ChromeIcons.swift", "MenuSymbols.swift"], "MenuSymbolsTests.swift", "MENU_SYMBOLS_TESTS", ()),
    ("glass-chrome-tests", ["OriginalActionButton.swift", "FontAwesomeIcons.swift", "ChromeIcons.swift", "BezelDrawingControls.swift", "SVGPath.swift", "DocumentModel.swift", "GlassChrome.swift", "ModernEditorChrome.swift"], "GlassChromeTests.swift", "GLASS_CHROME_TESTS", ()),
]
with ThreadPoolExecutor(max_workers=len(suites) + len(optional_suites)) as executor:
    futures = [executor.submit(suite, *args) for args in suites]
    futures += [executor.submit(suite, *args, optional=True) for args in optional_suites]
    failures = []
    for future in futures:
        try:
            print(*future.result(), flush=True)
        except Exception as error:
            failures.append(str(error))
            print("FAIL", error, flush=True)
if failures:
    check_real_store(real_store_before)
    raise SystemExit(1)
print("== build + check-no-original", flush=True)
subprocess.run(["sh", str(root / "tools" / "build.sh")], cwd=root, check=True, stdout=subprocess.DEVNULL)
subprocess.run([sys.executable, str(root / "tools" / "check-no-original.py"), str(build / "OpenSnap.app")], cwd=root, check=True)
print("== app-safety", flush=True)
subprocess.run([str(root / "tools" / "test-app-safety.sh"), "--arch", options.arch], cwd=root, check=True)
check_real_store(real_store_before)
if current_inputs() != inputs or not all(path.read_bytes() == data for path, data in contents.items()):
    raise SystemExit("Sources changed during verification; rerun before treating this result as current.")
print("All suites passed on", options.arch, "with no source drift. Evidence:", snapshot, flush=True)
