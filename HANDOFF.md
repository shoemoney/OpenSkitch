# OpenSnap agent handoff

Resume document, October 9, 2026, America/Chicago. Describes branch `opensnap/integration-w1` plus the documentation pass in `opensnap/w2-docs`. The product is **OpenSnap**, a native macOS 26+ AppKit screen-capture and annotation app with a Liquid Glass UI. The repository and local folder are still named `OpenSkitch` until the owner approves the rename. Apple Silicon only. Origin is GitHub `shoemoney/OpenSkitch` (issue tracker; also pushes to the Forgejo mirror). Read `AGENTS.md` and `docs/agents/` first. Plan: `build/declassic-plan.md` (git-ignored); its section 4 "OWNER DECISIONS" overrides the rest.

## What landed

| Area | State |
| --- | --- |
| Single appearance | Classic is gone. The Liquid Glass UI is the only interface, with icon-only controls and tooltips. |
| Silent, own assets | Sounds and the sound preference are removed; countdown digits are drawn in code; no welcome document (first launch opens a blank canvas); no third-party artwork. `tools/check-no-original.py` guards it. |
| Build and tests | The build and `python3 tools/test.py` need nothing outside the repository (`original/` is absent and not needed). |
| Capture | Region, window, fullscreen and Frame snaps on the display under the pointer; timed snap with countdown. Camera was removed. |
| Export | Footer PNG / JPG toggle: PNG by default (keeps transparency), JPG fixed at 0.75 for drag, export, upload and History. |
| Upload | SFTP, FTP/FTPS, WebDAV and S3-compatible destinations; one default; right-click the upload button to switch. |
| Reconstruction evidence retired | `analysis/*.json` is untracked and `analysis/` is git-ignored (files stay on disk). `tools/check-dispositions.py`, `tools/decompile.sh` and `tools/ExportDecompiled.java` are deleted. No history rewrite. |
| Hint copy | `Sources/OriginalHintMessages.swift` holds our own wording for every hint and tooltip; `tests/OriginalHintMessagesTests.swift` is a plain table test. |
| Docs | README rewritten for OpenSnap; the crop-resize ADR is kept as history. |

## Decisions (2026-10-09)

- **Name:** OpenSnap. Bundle `OpenSnap.app`, id `com.shoemoney.opensnap`, Application Support folder `OpenSnap`, Keychain service `OpenSnap.Publishing`, env prefix `OPENSNAP_*`.
- **D1:** rename and migrate. One-time copy-never-move migration from the previous app's Application Support folder, defaults domain and Keychain items; the old data stays untouched; a marker file prevents repeats. Lands with this release.
- **D2:** macOS 26.0 minimum, no fallback UI.
- **D3:** the old `.skitch` and `.skitchredux` formats are no longer opened, saved or associated. The native extension is `.opensnap` (UTI `com.shoemoney.opensnap.document`). Only the migration converts existing History documents, with a reader reachable from nowhere else; originals stay untouched.
- **D4:** untrack and ignore `analysis/`, delete the decompile and disposition tools, no history rewrite.
- **D5:** silent and minimal (see the table above).

## Remaining work

1. **Rename and migration package** (in flight, `Sources/`): bundle id, Application Support `OpenSnap`, `.opensnap` documents, env prefix, migration with fixtures, then a read-only or copy-based check against the owner's real store.
2. **Fresh-clone verification:** clone, `tools/build.sh`, `python3 tools/test.py`, `tools/test-native-startup.py` with no `original/` and no Font Awesome token.
3. **0.4.0 release:** bump `Info.plist`, `sh tools/release.sh 0.4.0`, startup smoke on the release bundle, tag, push, GitHub release with the zip SHA-256. Builds are ad-hoc signed, not notarized.
4. **Repo rename:** GitHub `shoemoney/OpenSkitch`, the Forgejo mirror and the local path become OpenSnap only after explicit owner approval.
5. **Live capture proof** needs Screen Recording permission, which is not granted to agents on this host. Ask the owner; do not change Security settings. Mixed-display behavior on physical 1x/2x displays is also unchecked.

## Do not over-claim

- No capture behavior has been verified live; flash, countdown, region, window, fullscreen and Frame are proven by controlled tests only. The magnifier lens stays grey without Screen Recording.
- Not notarized; Gatekeeper blocks a downloaded copy until opened via Privacy & Security.
- Real tablet hardware and printer output are unverified.

## Verification commands

```sh
cd /path/to/your/worktree
git status --short
python3 tools/test.py                      # add --concurrent-app-safety for the isolation proof
sh tools/build.sh
python3 tools/test-native-startup.py
sh tools/eye-dump.sh                       # app-owned window PNGs in build/eye-dump/
```

Quit a running built app before rebuilding (the startup script refuses otherwise) and check for unsaved work first. Use the supported computer-use tooling for real UI interaction, not AppleScript, CGEvent or `screencapture`. Never build or test in the main checkout; use a worktree.

## Invariants

- Never touch the previous app's Application Support folder; the migration copies, it never moves or deletes.
- Font Awesome Pro is never committed or shipped; `tools/check-no-fonts.py` guards the release bundle.
- No third-party art, sounds, code or decompiled material in the tree or the bundle.
- Readable text is 18 points minimum, ordinarily 20. Do not shrink controls or force utility-window focus to simplify tests. No credentials, keys or secrets in logs, handoffs or committed artifacts.
- No AI attribution anywhere.
