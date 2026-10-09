#!/usr/bin/env python3
"""Exercise the built native app, editable save/reopen, render and real AppKit Quit.

Uses isolated application support and the bundled original sample. No desktop
input, capture permissions or network publishing are exercised. The built window
must carry the glass chrome.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64", "both"], default="arm64")
parser.add_argument("--timeout", type=float, default=30)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = root / "build/OpenSkitch.app/Contents/MacOS/OpenSkitch"
manifest = json.loads((root / "build/build-manifest.json").read_text())
digest = hashlib.sha256(binary.read_bytes()).hexdigest()
assert digest == manifest["binary_sha256"], "Binary differs from its build manifest."
for name, expected in manifest["source_sha256"].items():
    source = root / ("Info.plist" if name == "Info.plist" else "Sources/" + name)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected, "Rebuild after changing " + name
evidence = root / "build" / ("startup-smoke-" + digest[:10])
results = {"binary_sha256": digest, "verified_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}
architectures = ["arm64", "x86_64"] if args.arch == "both" else [args.arch]
runs = {arch: arch for arch in architectures}

for label, arch in runs.items():
    folder = evidence / label
    folder.mkdir(parents=True, exist_ok=True)
    support = tempfile.mkdtemp(prefix="support-", dir=folder)
    env = os.environ | {"SKITCH_APP_SUPPORT": support,
                        "CFFIXED_USER_HOME": tempfile.mkdtemp(prefix="home-", dir=folder),
                        "SKITCH_EVIDENCE_DIR": str(folder)}
    # Do not allow evidence left by an earlier invocation to count as a pass.
    for name in ["smoke-result.txt", "smoke.png", "smoke.skitch", "smoke.skitchredux", "smoke-appearance.json"]:
        (folder / name).unlink(missing_ok=True)
    result = {"passed": False}
    with (folder / "stderr.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-" + arch, str(binary), "--smoke-test"],
                                   cwd=root, env=env, stdout=log, stderr=log)
        try:
            result["exit_code"] = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            # This is only this test's isolated child, never a user app process.
            process.kill()
            process.wait()
            result["error"] = "Native app did not finish startup/save/render/Quit within the test deadline."
    try:
        text = (folder / "smoke-result.txt").read_text().strip()
        result["result"] = text
        assert result.get("exit_code") == 0, result.get("error", "Native app exited unsuccessfully.")
        assert text == "native startup, original-format editable save/load, PNG export succeeded"
        native = (folder / "smoke.skitch").read_bytes()
        assert ET.fromstring(native).tag == "{http://www.w3.org/2000/svg}svg"
        png = (folder / "smoke.png").read_bytes()
        assert png.startswith(b"\x89PNG\r\n\x1a\n")
        # A window built from anything but the glass chrome must not pass.
        built = json.loads((folder / "smoke-appearance.json").read_text())
        result["appearance"] = built
        assert built["modernChrome"] and built["toolButtonClass"] == "GlassChromeButton" and built["glassSurfaces"] > 0, \
            "The window is not the glass chrome: %s" % built
        result.update(passed=True, png_bytes=len(png), editable_bytes=len(native),
                      editable_sha256=hashlib.sha256(native).hexdigest())
    except Exception as error:
        result["error"] = str(error)
    results[label] = result
    print(label, "PASS" if result["passed"] else "FAIL",
          result.get("error", "native save/reopen/render and Quit, glass chrome (%d glass surfaces)" % result.get("appearance", {}).get("glassSurfaces", 0)), flush=True)
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("Evidence:", evidence, flush=True)
raise SystemExit(0 if all(results[label]["passed"] for label in runs) else 1)
