"""The owner's real data stores, which no test run may touch (imported by tools/test.py).

Watched: the previous app's whole Application Support folder, the new app's folder, and both defaults
plists. The new app's folder must not even be CREATED by a run. Contents are hashed, never printed.
Named with the retired product name on purpose; it is on the allowlist of check-skitch-strings.py.
"""
from pathlib import Path
import hashlib
import os

HOME = Path(os.path.expanduser("~"))
SUPPORT = HOME / "Library/Application Support"
OLD_FOLDER = SUPPORT / "SkitchRedux"
OPENSNAP_FOLDER = SUPPORT / "OpenSnap"
REAL_STORE_FOLDERS = [OLD_FOLDER, OPENSNAP_FOLDER]
REAL_STORE_FILES = [HOME / "Library/Preferences/com.shoemoney.skitch-redux.plist",
                    HOME / "Library/Preferences/com.shoemoney.opensnap.plist"]


def describe():
    return [str(path) for path in REAL_STORE_FOLDERS + REAL_STORE_FILES]


def _entry(path):
    info = path.stat()
    return (info.st_size, info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())


def snapshot():
    """(folders, {path: (size, mtime_ns, sha256)}) for every file in the real stores."""
    entries = {}
    for folder in REAL_STORE_FOLDERS:
        if folder.exists():
            for path in sorted(folder.rglob("*")):
                if path.is_file():
                    entries[str(path)] = _entry(path)
    for path in REAL_STORE_FILES:
        if path.is_file():
            entries[str(path)] = _entry(path)
    return REAL_STORE_FOLDERS, entries


def compare(before, opensnap_folder_existed):
    """Problems found since `before` (an earlier snapshot()); empty when nothing was touched."""
    _, after = snapshot()
    problems = [f"{'changed' if name in before and name in after else 'appeared' if name in after else 'disappeared'} {name}"
                for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]
    # No test may write preferences for any OpenSnap-named domain: CFFIXED_USER_HOME does not redirect the
    # preferences daemon, so a defaults suite used by a test lands in the real ~/Library/Preferences.
    for leftover in sorted((HOME / "Library/Preferences").glob("com.test.opensnap.*")):
        problems.append(f"left behind {leftover}")
    if not opensnap_folder_existed and OPENSNAP_FOLDER.exists():
        problems.append(f"created {OPENSNAP_FOLDER}")
    return problems
