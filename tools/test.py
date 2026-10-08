#!/usr/bin/env python3
"""Run independent native regression suites against a consistent source snapshot."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, sys, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
parser.add_argument("--concurrent-app-safety", action="store_true",
                    help="also run Classic and Modern app-safety in parallel and require both to pass")
options = parser.parse_args()
root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)

def real_store_snapshot():
    """(path, size, mtime, sha256) of every file in the owner's real Publishing folder. Contents are hashed, never printed."""
    folder = Path(os.path.expanduser("~")) / "Library/Application Support/SkitchRedux/Publishing"
    entries = {}
    if folder.exists():
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                info = path.stat()
                entries[str(path)] = (info.st_size, info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())
    return folder, entries

def check_real_store(before):
    folder, after = real_store_snapshot()
    changed = [f"{kind} {name}" for name in sorted(before.keys() | after.keys())
               for kind in ["changed" if name in before and name in after else "appeared" if name in after else "disappeared"]
               if before.get(name) != after.get(name)]
    if changed:
        raise SystemExit(f"FAIL real-store-guard: the owner's {folder} was touched by this run:\n" + "\n".join(changed))
    print("PASS real-store-guard (", len(after), "files in", folder, "unchanged )", flush=True)

real_store_folder, real_store_before = real_store_snapshot()

def secrets_guard():
    """Licensed fonts and registry credentials must never become committable."""
    forbidden = re.compile(r"\.(ttf|otf|woff2?)$|(^|/)(\.npmrc|package-lock\.json)$|(^|/)node_modules/|(^|/)fortawesome-fontawesome-pro-[^/]*\.tgz$", re.I)
    listing = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True)
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
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", options.arch + "-apple-macosx13.0"]
    if define:
        command += ["-D", define]
    command += [str(snapshot / source) for source in sources]
    command += [str(snapshot / test), "-o", str(binary)]
    subprocess.run(command, cwd=root, check=True)
    subprocess.run([str(binary), *arguments], cwd=root, check=True, env=environment)
    return "PASS", name

# Appearance.swift joins the preference suites once it exists.
appearance = ["Appearance.swift"] if (snapshot / "Appearance.swift").exists() else []
# Subsets from tools/fetch-fontawesome.sh are exercised when they have been built.
fonts = root / "build/fonts"
font_environment = os.environ | {"OPENSKITCH_FA_FONT_DIR": str(fonts)} if any(fonts.glob("*-subset.ttf")) else None

suites = [
    ("original-action-button-tests", ["OriginalActionButton.swift"], "OriginalActionButtonTests.swift", "ORIGINAL_ACTION_BUTTON_TESTS", ()),
    ("tool-button-tests", ["OriginalActionButton.swift", "ToolButton.swift"], "ToolButtonTests.swift", "TOOL_BUTTON_TESTS", ()),
    ("original-capture-timing-tests", ["OriginalCaptureTiming.swift"], "OriginalCaptureTimingTests.swift", "ORIGINAL_CAPTURE_TIMING_TESTS", ()),
    ("original-capture-picker-tests", ["OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift"], "OriginalCapturePickerTests.swift", "ORIGINAL_CAPTURE_PICKER_TESTS", ()),
    ("original-capture-countdown-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureCountdown.swift"], "OriginalCaptureCountdownTests.swift", "ORIGINAL_CAPTURE_COUNTDOWN_TESTS", ()),
    ("original-hint-messages-tests", ["LegacySkitch.swift", "DocumentModel.swift", "OriginalHintMessages.swift"], "OriginalHintMessagesTests.swift", "ORIGINAL_HINT_MESSAGES_TESTS", ()),
    ("original-help-bevel-tests", ["OriginalHelpBevel.swift"], "OriginalHelpBevelTests.swift", "ORIGINAL_HELP_BEVEL_TESTS", ()),
    ("window-zoom-tests", ["WindowZoom.swift"], "WindowZoomTests.swift", "WINDOW_ZOOM_TESTS", ()),
    ("text-style-form-tests", ["TextStyleForm.swift"], "TextStyleFormTests.swift", "TEXT_STYLE_FORM_TESTS", ()),
    ("general-preferences-form-tests", ["LegacySkitch.swift", "StrokeFitting.swift", "GeneralPreferencesForm.swift", *appearance], "GeneralPreferencesFormTests.swift", "GENERAL_PREFERENCES_FORM_TESTS", ()),
    ("original-general-preferences-tests", ["LegacySkitch.swift", "StrokeFitting.swift", "DocumentModel.swift", "GeneralPreferencesForm.swift", "OriginalGeneralPreferences.swift", *appearance], "OriginalGeneralPreferencesTests.swift", "ORIGINAL_GENERAL_PREFERENCES_TESTS", ()),
    ("resize-presets-tests", ["ResizePresets.swift"], "ResizePresetsTests.swift", "RESIZE_PRESETS_TESTS", ()),
    ("window-sizing-tests", ["WindowSizing.swift"], "WindowSizingTests.swift", "WINDOW_SIZING_TESTS", ()),
    ("canvas-navigator-tests", ["CanvasNavigator.swift"], "CanvasNavigatorTests.swift", "CANVAS_NAVIGATOR_TESTS", ()),
    ("canvas-border-tests", ["WindowSizing.swift", "CanvasBorderView.swift"], "CanvasBorderTests.swift", "CANVAS_BORDER_TESTS", ()),
    ("resize-panel-tests", ["ResizePresets.swift", "ResizePanel.swift"], "ResizePanelTests.swift", "RESIZE_PANEL_TESTS", ()),
    ("export-accessory-tests", ["ExportAccessory.swift"], "ExportAccessoryTests.swift", "EXPORT_ACCESSORY_TESTS", ()),
    ("image-export-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "ImageExport.swift"], "ImageExportTests.swift", "IMAGE_EXPORT_TESTS", ()),
    ("vector-geometry-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift"], "VectorGeometryTests.swift", "VECTOR_GEOMETRY_TESTS", ()),
    ("stroke-fitting-tests", ["LegacySkitch.swift", "StrokeFitting.swift"], "StrokeFittingTests.swift", "STROKE_FITTING_TESTS", ()),
    ("canvas-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift"], "CanvasTests.swift", "CANVAS_TESTS", ()),
    ("legacy-history-importer-tests", ["LegacyHistoryImporter.swift"], "LegacyHistoryImporterTests.swift", "LEGACY_HISTORY_IMPORTER_TESTS", ()),
    ("history-store-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "SVGExport.swift", "SkitchFile.swift", "LegacyHistoryImporter.swift", "HistoryStore.swift"], "HistoryStoreTests.swift", "HISTORY_STORE_TESTS", ()),
    ("history-browser-tests", ["HistoryBrowser.swift"], "HistoryBrowserTests.swift", "HISTORY_BROWSER_TESTS", ()),
    ("history-remote-deletion-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", "HistoryRemoteDeletion.swift"], "HistoryRemoteDeletionTests.swift", None, ("--test",)),
    ("publishing-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingTests.swift", None, ("--test",)),
    ("publishing-shutdown-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingShutdownTests.swift", None, ("--test",)),
    ("publishing-destinations-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift"], "PublishingDestinationsTests.swift", None, ("--test",)),
    ("hotkey-tests", ["GlobalHotkeys.swift"], "GlobalHotkeysTests.swift", "GLOBAL_HOTKEY_TESTS", ()),
    ("svg-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "SVGExport.swift"], "SVGExportTests.swift", "SVG_EXPORT_TESTS", ("--fixture", str(root / "original/Skitch.app/Contents/Resources/firstlaunch.skitch"))),
    ("skitch-file-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "SVGExport.swift", "SkitchFile.swift"], "SkitchFileTests.swift", "SKITCH_FILE_TESTS", ("--fixture", str(root / "original/Skitch.app/Contents/Resources/firstlaunch.skitch"))),
    ("capture-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift", "OriginalCaptureCountdown.swift", "OriginalCaptureFlash.swift", "Capture.swift"], "CaptureTests.swift", "CAPTURE_TESTS", ()),
    ("photo-browser-tests", ["PhotoBrowser.swift"], "PhotoBrowserTests.swift", None, ()),
]
# Modern appearance suites are skipped, not failed, while their files are not in the tree yet.
optional_suites = [
    ("appearance-tests", ["Appearance.swift"], "AppearanceTests.swift", "APPEARANCE_TESTS", ()),
    ("fontawesome-icons-tests", ["FontAwesomeIcons.swift", "ChromeIcons.swift"], "FontAwesomeIconsTests.swift", "FONTAWESOME_ICONS_TESTS", (), font_environment),
    ("menu-symbols-tests", ["FontAwesomeIcons.swift", "ChromeIcons.swift", "MenuSymbols.swift"], "MenuSymbolsTests.swift", "MENU_SYMBOLS_TESTS", ()),
    ("glass-chrome-tests", ["Appearance.swift", "OriginalActionButton.swift", "ToolButton.swift", "FontAwesomeIcons.swift", "ChromeIcons.swift", "BezelDrawingControls.swift", "LegacySkitch.swift", "DocumentModel.swift", "GlassChrome.swift", "ModernEditorChrome.swift"], "GlassChromeTests.swift", "GLASS_CHROME_TESTS", ()),
]
# Every unimplemented progress row must carry a disposition; the checker must also reject a row without one.
subprocess.run([sys.executable, str(root / "tools" / "check-dispositions.py")], cwd=root, check=True)
with tempfile.TemporaryDirectory() as scratch:
    bad = Path(scratch) / "progress.json"
    bad.write_text(json.dumps({"features": [{"id": "x.y", "status": "unimplemented"}]}))
    if subprocess.run([sys.executable, str(root / "tools" / "check-dispositions.py"), str(bad)], capture_output=True).returncode == 0:
        raise SystemExit("check-dispositions accepted an unimplemented row without a disposition")
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
# Classic is the pinned baseline everywhere; Modern needs macOS 26+ and its integration cases.
safety_runs = ["classic"]
if int(platform.mac_ver()[0].split(".")[0] or 0) < 26:
    print("SKIP app-safety modern: host is older than macOS 26", flush=True)
elif not (root / "tests/AppSafetyModernCases.swift").exists():
    print("SKIP app-safety modern: tests/AppSafetyModernCases.swift not present", flush=True)
else:
    safety_runs.append("modern")
for style in safety_runs:
    print("== app-safety", style, flush=True)
    subprocess.run([str(root / "tools" / "test-app-safety.sh"), "--arch", options.arch, "--appearance", style], cwd=root, check=True)
if options.concurrent_app_safety:
    print("== app-safety concurrent", flush=True)
    subprocess.run([str(root / "tools" / "test-app-safety-concurrent.sh"), "--arch", options.arch], cwd=root, check=True)
check_real_store(real_store_before)
if current_inputs() != inputs or not all(path.read_bytes() == data for path, data in contents.items()):
    raise SystemExit("Sources changed during verification; rerun before treating this result as current.")
print("All suites passed on", options.arch, "with no source drift. Evidence:", snapshot, flush=True)
