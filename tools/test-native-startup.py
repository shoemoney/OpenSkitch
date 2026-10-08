#!/usr/bin/env python3
"""Exercise the built native app, editable save/reopen, render and real AppKit Quit.

Uses isolated application support and the bundled original sample. No desktop
input, capture permissions or network publishing are exercised. Every run is
pinned with SKITCH_APPEARANCE (Classic everywhere, plus Modern on macOS 26+) and
checks the built window really carries that style's chrome. On macOS 26+ it also
clicks the real Preferences "Relaunch OpenSkitch" button in the built bundle,
once per appearance, and checks that a new process replaces the old one.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import platform
import signal
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64", "both"], default="arm64")
parser.add_argument("--timeout", type=float, default=30)
parser.add_argument("--relaunches", type=int, default=3, help="Relaunch cycles per appearance (0 skips the relaunch proof)")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = root / "build/OpenSkitch.app/Contents/MacOS/OpenSkitch"
manifest = json.loads((root / "build/build-manifest.json").read_text())
digest = hashlib.sha256(binary.read_bytes()).hexdigest()
assert digest == manifest["binary_sha256"], "Binary differs from its build manifest."
for name, expected in manifest["source_sha256"].items():
    source = root / ("Info.plist" if name == "Info.plist" else "Sources/" + name)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected, "Rebuild after changing " + name
fixture = root / "original/Skitch.app/Contents/Resources/firstlaunch.skitch"
evidence = root / "build" / ("startup-smoke-" + digest[:10])
results = {"binary_sha256": digest, "verified_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}
architectures = ["arm64", "x86_64"] if args.arch == "both" else [args.arch]
# Modern chrome only exists on macOS 26+; every host also proves the pinned Classic baseline.
appearances = ["classic", "modern"] if int(platform.mac_ver()[0].split(".")[0] or 0) >= 26 else ["classic"]
runs = {arch + "-" + style: (arch, style) for arch in architectures for style in appearances}


def bundle_processes():
    """PIDs whose executable is exactly this build's binary, read from ps."""
    paths = {str(binary), str(binary.resolve())}
    listing = subprocess.run(["/bin/ps", "-axo", "pid=,command="], capture_output=True, text=True, check=True).stdout
    found = {}
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(" ")
        if pid.isdigit() and any(command == path or command.startswith(path + " ") for path in paths):
            found[int(pid)] = command
    return found


def relaunch_cycle(arch, style, folder, attempt):
    """Click Relaunch in the built bundle; the old PID must exit and a different one must stay running."""
    result = {"passed": False, "attempt": attempt}
    if bundle_processes():
        result["error"] = "This build is already running; refusing to touch it."
        return result
    support = tempfile.mkdtemp(prefix="relaunch-support-", dir=folder)
    # The old instance opens the fixture; Relaunch must not forward it, or the new one would reopen it over the recovered drawing.
    env = dict(os.environ)
    env["SKITCH_FIXTURE"] = str(fixture)
    env.update(SKITCH_APP_SUPPORT=support, SKITCH_APPEARANCE=style, SKITCH_EVIDENCE_DIR=str(folder))
    failure = folder / "relaunch-smoke-result.txt"
    failure.unlink(missing_ok=True)
    try:
        with (folder / "relaunch-stderr.log").open("a") as log:
            old = subprocess.Popen(["/usr/bin/arch", "-" + arch, str(binary), "--relaunch-smoke"],
                                   cwd=root, env=env, stdout=log, stderr=log)
            result["old_pid"] = old.pid
            try:
                result["old_exit_code"] = old.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                old.kill()
                old.wait()
                result["error"] = "The old instance did not quit after Relaunch was clicked."
                return result
        if failure.exists():
            result["error"] = failure.read_text().strip()
            return result
        if result["old_exit_code"] != 0:
            result["error"] = "The old instance quit with status %s." % result["old_exit_code"]
            return result
        deadline = time.monotonic() + 15
        fresh = {}
        while not fresh and time.monotonic() < deadline:
            fresh = {pid: command for pid, command in bundle_processes().items() if pid != old.pid}
            if not fresh:
                time.sleep(0.1)
        result["new_pids"] = sorted(fresh)
        if len(fresh) != 1:
            result["error"] = "Expected one relaunched OpenSkitch process within 15 s, found %d." % len(fresh)
            return result
        new_pid = next(iter(fresh))
        result["new_pid"] = new_pid
        # A relaunch that was spawned but crashed on startup must not count.
        time.sleep(3)
        survivors = sorted(bundle_processes())
        if survivors != [new_pid]:
            result["error"] = "After 3 s the running processes were %s, expected only the new %d." % (survivors, new_pid)
            return result
        result["passed"] = True
        return result
    finally:
        # Only what this cycle started: the build was verified idle above.
        for pid in bundle_processes():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for _ in range(50):
            if not bundle_processes():
                break
            time.sleep(0.1)
        else:
            for pid in bundle_processes():
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

for label, (arch, style) in runs.items():
    folder = evidence / label
    folder.mkdir(parents=True, exist_ok=True)
    support = tempfile.mkdtemp(prefix="support-", dir=folder)
    env = os.environ | {"SKITCH_APP_SUPPORT": support, "SKITCH_APPEARANCE": style,
                        "SKITCH_EVIDENCE_DIR": str(folder), "SKITCH_FIXTURE": str(fixture)}
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
        # The pinned style must have produced its own chrome; a Classic window under SKITCH_APPEARANCE=modern would otherwise pass.
        built = json.loads((folder / "smoke-appearance.json").read_text())
        result["appearance"] = built
        assert built["style"] == style, "Pinned %s but the app resolved %s." % (style, built["style"])
        if style == "modern":
            assert built["modernChrome"] and built["toolButtonClass"] == "GlassChromeButton" and built["glassSurfaces"] > 0, \
                "Modern was pinned but the window is not the glass chrome: %s" % built
        else:
            assert not built["modernChrome"] and built["toolButtonClass"] == "ToolButton" and built["glassSurfaces"] == 0, \
                "Classic was pinned but the window carries Modern chrome: %s" % built
        result.update(passed=True, png_bytes=len(png), editable_bytes=len(native),
                      editable_sha256=hashlib.sha256(native).hexdigest())
    except Exception as error:
        result["error"] = str(error)
    results[label] = result
    print(label, "PASS" if result["passed"] else "FAIL",
          result.get("error", "native save/reopen/render and Quit, %s chrome (%d glass surfaces)" % (style, result.get("appearance", {}).get("glassSurfaces", 0))), flush=True)
# The Appearance row (and its Relaunch button) exists only on macOS 26+. LaunchServices starts the host's native slice, so this runs for arm64 only.
relaunch_labels = []
if args.relaunches > 0 and "modern" in appearances and "arm64" in architectures:
    for style in appearances:
        label = "arm64-" + style + "-relaunch"
        relaunch_labels.append(label)
        folder = evidence / label
        folder.mkdir(parents=True, exist_ok=True)
        attempts = []
        for attempt in range(1, args.relaunches + 1):
            attempts.append(relaunch_cycle("arm64", style, folder, attempt))
            if not attempts[-1]["passed"]:
                break
        replaced = [a for a in attempts if a["passed"]]
        passed = len(replaced) == args.relaunches
        results[label] = {"passed": passed, "attempts": attempts}
        detail = "%d/%d relaunches replaced the process (PIDs %s)" % (
            len(replaced), args.relaunches, ", ".join("%s->%s" % (a["old_pid"], a["new_pid"]) for a in replaced) or "none")
        error = next((a["error"] for a in attempts if not a["passed"]), "")
        print(label, "PASS" if passed else "FAIL", detail if passed else detail + "; " + error, flush=True)
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("Evidence:", evidence, flush=True)
raise SystemExit(0 if all(results[label]["passed"] for label in list(runs) + relaunch_labels) else 1)
