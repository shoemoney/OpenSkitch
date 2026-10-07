#!/usr/bin/env python3
"""Run independent native regression suites against a consistent source snapshot."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, hashlib, json, platform, subprocess, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
options = parser.parse_args()
root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)
snapshot = Path(tempfile.mkdtemp(prefix="test-snapshot.", dir=build))
inputs = sorted((root / "Sources").glob("*.swift")) + sorted((root / "tests").glob("*.swift"))
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

def suite(name, sources, test, define=None, arguments=()):
    binary = snapshot / name
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", options.arch + "-apple-macosx13.0"]
    if define:
        command += ["-D", define]
    command += [str(snapshot / source) for source in sources]
    command += [str(snapshot / test), "-o", str(binary)]
    subprocess.run(command, cwd=root, check=True)
    subprocess.run([str(binary), *arguments], cwd=root, check=True)
    return name

suites = [
    ("vector-geometry-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift"], "VectorGeometryTests.swift", "VECTOR_GEOMETRY_TESTS", ()),
    ("stroke-fitting-tests", ["LegacySkitch.swift", "StrokeFitting.swift"], "StrokeFittingTests.swift", "STROKE_FITTING_TESTS", ()),
    ("canvas-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "Canvas.swift"], "CanvasTests.swift", "CANVAS_TESTS", ("--skip-visual-proof",)),
    ("legacy-history-importer-tests", ["LegacyHistoryImporter.swift"], "LegacyHistoryImporterTests.swift", "LEGACY_HISTORY_IMPORTER_TESTS", ()),
    ("history-store-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "Canvas.swift", "SVGExport.swift", "SkitchFile.swift", "LegacyHistoryImporter.swift", "HistoryStore.swift"], "HistoryStoreTests.swift", "HISTORY_STORE_TESTS", ()),
    ("history-browser-tests", ["HistoryBrowser.swift"], "HistoryBrowserTests.swift", "HISTORY_BROWSER_TESTS", ()),
    ("history-remote-deletion-tests", ["Publishing.swift", "HistoryRemoteDeletion.swift"], "HistoryRemoteDeletionTests.swift", None, ("--test",)),
    ("publishing-tests", ["Publishing.swift"], "PublishingTests.swift", None, ("--test",)),
    ("publishing-shutdown-tests", ["Publishing.swift"], "PublishingShutdownTests.swift", None, ("--test",)),
    ("hotkey-tests", ["GlobalHotkeys.swift"], "GlobalHotkeysTests.swift", "GLOBAL_HOTKEY_TESTS", ()),
    ("svg-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "Canvas.swift", "SVGExport.swift"], "SVGExportTests.swift", "SVG_EXPORT_TESTS", ("--fixture", str(root / "original/Skitch.app/Contents/Resources/firstlaunch.skitch"))),
    ("skitch-file-tests", ["LegacySkitch.swift", "LegacyBridge.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "Canvas.swift", "SVGExport.swift", "SkitchFile.swift"], "SkitchFileTests.swift", "SKITCH_FILE_TESTS", ("--fixture", str(root / "original/Skitch.app/Contents/Resources/firstlaunch.skitch"))),
    ("capture-tests", ["Capture.swift"], "CaptureTests.swift", "CAPTURE_TESTS", ()),
    ("photo-browser-tests", ["PhotoBrowser.swift"], "PhotoBrowserTests.swift", None, ()),
]
with ThreadPoolExecutor(max_workers=len(suites)) as executor:
    futures = [executor.submit(suite, *args) for args in suites]
    failures = []
    for future in futures:
        try:
            print("PASS", future.result(), flush=True)
        except Exception as error:
            failures.append(str(error))
            print("FAIL", error, flush=True)
if failures:
    raise SystemExit(1)
subprocess.run([str(root / "tools" / "test-app-safety.sh"), "--arch", options.arch], cwd=root, check=True)
if not all(path.read_bytes() == data for path, data in contents.items()):
    raise SystemExit("Sources changed during verification; rerun before treating this result as current.")
print("All suites passed on", options.arch, "with no source drift. Evidence:", snapshot, flush=True)
