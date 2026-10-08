# OpenSkitch agent handoff

Resume document, October 8, 2026, America/Chicago. Describes `main` at `db84445` plus this documentation pass. Repository: `/Users/shoemoney/Projects/OpenSkitch` (with **i**; `~/Projects/OpenSketch` with an e was only an old handoff location). Apple Silicon only. Origin is GitHub `shoemoney/OpenSkitch` (issue tracker; also pushes to the Forgejo mirror `shoemoney/skitch-redux`). Read `AGENTS.md` and `docs/agents/` first.

This is a Swift/AppKit reconstruction of Skitch 1.0.12, not a recompiled original (the archived original is 32-bit and has not been run on this Mac). **All 340 original parity flags remain unverified.** Passing tests prove the reconstruction, not original equivalence. Nothing here claims completion.

## State at db84445

Version `0.3.0` (build 3) in `Info.plist`. Issues #1, #2 and #3 are fixed in code with tests. Measured on the merged tree at `db84445`: AppSafety **96/96 Classic** (re-run in a docs worktree) and **16/16 Modern**, full `python3 tools/test.py` passes ("All suites passed on arm64 with no source drift"), startup smoke passes in both appearances with 3/3 relaunches. These counts supersede the 43,029 and 87 figures in older notes.

| Landed since `2d1ca2c` | Where to look |
| --- | --- |
| `CaptureCoordinator.submit` starts every capture via run-loop delivery. Not verified live: no Screen Recording grant | `Sources/Capture.swift` |
| Magnifier fed by a screen-image provider (native provider returns nil without Screen Recording, so the lens stays grey); tests use a synthetic image | `Sources/OriginalCaptureMagnifier.swift` |
| Image > Add Shadow (canvas +27x27, picture at (14,6), one NSShadow 8 down/blur 27/alpha 0.8, one Undo) from `MacImage::addShadow`/`addShadowTA` | `canvas.shadow` row |
| New and Open register one Undo restoring the previous document (original `loadFromFileTA`) | `analysis/reconstruction-progress.json` |
| A new Snap during a running capture cancels it and starts the new one | `snapSnap` cancelTimedSnap-first |
| Original corner/edge crop-resize rules; Option = centred resize; no crop handles in Actual mode | `docs/adr/0001-crop-resize-original-rules.md`, `tests/WindowSizingTests.swift` |
| Camera (iSight / Cam) removed everywhere by product decision 2026-10-08: OpenSkitch is screen capture only; `capture.camera-*` rows are retired | `Sources/Capture.swift`, `analysis/reconstruction-progress.json` |
| 19 progress rows promoted to `implemented_partial`; README planned count was 2 (`capture.camera-flip`, `gestures.control-share`); camera rows are now retired, see below | `analysis/reconstruction-progress.json`, `tools/check-dispositions.py` |
| On-screen shadows fall down-right like export and original (issue #1); `visualProof` compares with shadows on, 0 of 237,760 px differ | `NSShadow.cast(in:inFlippedView:)`, `tests/CanvasTests.swift` |
| App-safety isolation (issue #2): per-run binary name, default domain; Classic and Modern run at once | `tools/test-app-safety.sh`, `tools/test-app-safety-concurrent.sh`, `python3 tools/test.py --concurrent-app-safety` |
| Fonts panel sets `rowHeight` only on item-based `NSBrowser` delegates (issue #3) | `Sources/TextStyleForm.swift` |
| Release scaffolding: `sh tools/release.sh VERSION` (clean-tree check, staged copy, `tools/check-no-fonts.py`, codesign verify, zip, `build/release-manifest.json`), `OPENSKITCH_NO_PRO_FONTS=1` in `build.sh`, About panel reads the bundle version | `tools/release.sh`, `tools/build.sh` |
| Wipe resets crop/pan/render size when no snapshot remains (original `wipeTA`) | `Canvas.resetViewport` |
| Frame mode: no window shadow, screen-saver level, alpha 0.8, pre-Frame values restored on leave, both appearances | `AppDelegate.enterFrame`/`leaveFrame` |
| Webpost one-click upload: Webpost…/Publish Image…/Snap & Upload upload immediately (no sheet); right-click menu = destinations, settings, macOS Share | `AppDelegate.publishImage`, `PublishingCoordinator.publish` |
| Global hotkeys: Upload (default Command+Shift+Control+5) and Show Skitch (no default); a cancelled capture never publishes | `Sources/GlobalHotkeys.swift`, `AppDelegate.snapAndUpload` |
| Welcome document: first launch with an empty app-support folder opens bundled `firstlaunch.skitch` as unsaved "Welcome", once (`FirstLaunchDone` marker) | `Sources/App.swift` |
| Line tool Option polygon: holding Option keeps it open, releasing Option ends it | `Sources/Canvas.swift` |
| Capture flash: white panel after successful captures, 0.1 s (region/window/Frame/fullscreen) | `Sources/OriginalCaptureFlash.swift` |
| Crosshair magnifier geometry (10x zoom, 100x100 lens) behind `showCrosshairMagnifier` (now fed by the picker, see above) | `Sources/OriginalCaptureMagnifier.swift` |
| Modern canvas border corner/edge mouse gestures proven equal to Classic | `tests/AppSafetyModernCases.swift` |
| Every `unimplemented` row has a disposition; README "Not reconstructed" table; `tools/check-dispositions.py` enforces it (run by `tools/test.py`) | `analysis/reconstruction-progress.json` |

## Do not over-claim

- **The magnifier feed is wired but not proven live.** The picker passes a screen-image provider; the native one returns nil without Screen Recording permission, so the lens stays grey there. Tests use an injected synthetic image. Do not claim live magnifier pixels.
- **Not notarized.** Releases are ad-hoc signed; Gatekeeper blocks a downloaded copy until the user opens it via Privacy & Security or removes the quarantine flag (see README Releases).
- **No capture behavior has been verified live.** Screen Recording is not granted on this host to an agent; flash, countdown region, window, fullscreen and Frame are proven by controlled tests only. Do not change Security settings; ask the user to grant permission.
- **`analysis/*.json` checkpoint metadata deliberately still describes an older binary** (`interface-896edbdebc`, 42,977 checks/33 suites). Leave those numbers alone until the evidence reconciliation pass.
- The crop-resize ADR leaves the original snap-mode integer meaning unresolved (snap mode 1 + Shift is not honoured), and edge-crop rounding is not in the decompile.
- Real tablet hardware, printer output, the Fonts panel's live rendering and original-runtime visual equivalence remain unverified.

## Remaining plan

Source of truth: `/Users/shoemoney/Projects/OpenSkitch/build/completion-plan.md` (git-ignored; Bar B is the 0.3.0 release bar). Still open:

1. **Cursor policy.** Cursor policy needs no work: `Capture.swift` passes `-C` only for timed captures, the same rule as the original `showMouse` (decompiled.c 22395, 22455-22490).
2. **Mixed-display captures.** Decided: a snap covers only the active display (under the pointer at snap start; Fullscreen uses `-R` with its rect, the overlay and window clicks stay on it), so regions no longer span screens, a recorded deviation from the original. Still to check live on physical 1x/2x displays, plus cancel during flash or outside the picker. (The original has no Escape-during-countdown path; its Escape hotkey lives only in the crosshair view, decompiled.c 18650-18690.)
3. **Crop-resize leftovers.** The ADR's open points: original snap-mode integers and Shift behaviour, edge-crop rounding. `gestures.control-share` is the other planned row.
4. **WP-06: visual review by eye** of app-owned screenshots (default size, minimum size, Frame, Actual) in both appearances, Modern especially.
5. **WP-07: evidence reconciliation.** Re-anchor `analysis/*.json` (snapshot, `current_tests` metadata, hashes, test counts) to the release binary; keep parity flags unverified unless evidence supports otherwise.
6. **Live capture proof** needing Screen Recording permission (capture, countdown, magnifier pixels). Ask the user to grant them.
7. **WP-21b: release execution** (needs the user). `sh tools/release.sh 0.3.0`, startup smoke on the release bundle, tag, push, GitHub release with the zip SHA-256. Notarization is absent; builds are ad-hoc signed.

## Verification commands

```sh
cd /Users/shoemoney/Projects/OpenSkitch
git status --short
ln -s /Users/shoemoney/Projects/OpenSkitch/original original   # only inside a worktree; never commit the symlink
python3 tools/test.py                      # add --concurrent-app-safety for issue #2's proof
sh tools/build.sh
python3 tools/test-native-startup.py
```

Quit a running `build/OpenSkitch.app` safely before rebuilding (the startup script refuses otherwise), and check for unsaved work first. Use the supported computer-use tooling for real UI interaction, not AppleScript, CGEvent or `screencapture`.

## Original archive evidence: authoritative for interface fidelity

Original archive: `original/Skitch.app/Contents/Resources/English.lproj/MainMenu.nib`, version 1.0.12, root size 800×640. Coordinates below use the original bottom-left system. The shipped archive overrides assumptions drawn from older help screenshots.

- Hide UID146 `(13,612,24,25)` invokes `vanish`; Toolbox UID137 `(43,616,27,17)` is image-only, menu1907→1570.
- Evernote UID439 is hidden at startup. No top Photos button; Browse Photos menu1589 invokes `showMedia`. Current Photos is an explicit addition.
- Save cluster263 `(670,613,45,23)`, label457 and arrow459 all invoke `historyArchive`. History328 `(717,617,46,15)` invokes `showHistory`.
- Normal Snap container185 `(764,520,37,86)` uses tab1 (the original also held Cam, now removed). Frame tab2 replaces it with Snap/Cancel. There is no permanent Frame rail button.
- Font cluster415 `(764,425,37,39)` is on the right. Color296 `(764,470,37,46)`, size423, slider503 follow the same right-side grouping.
- Undo430 `(765,91,35,21)` uses responder-chain undo; Wipe172 `(765,71,35,21)` uses dynamic state.
- Actual505 `(4,77,28,31)` and Resize435 `(13,45,76,26)` are lower left.
- Left tools178 `(0,376,37,231)`, 31×31, ordered Cursor, Brush, Line, Circle, Rectangle, Fill, Eraser, Text, Arrow. Crop is not one of the nine.
- Frame mode `setSnapMode:` IMP `0x2067c`, decompiled.c around20481: normal tab1 shadow/alpha1, Frame tab2 no shadow/alpha0.8 and screen-saver window level. Implemented in both appearances (`enterFrame`/`leaveFrame` restore the pre-Frame shadow, alpha and level); no live desktop proof yet.
- Actual enabled getter `0x91d0`, decompiled4656: alreadyActual OR document + capturemode0 + pixelSize()<1.0; Float32 constant at `0x260470` is 1.0.
- `updateWipeButton` IMP `0x25d45`, decompiled24681: empty/no field editing/no background image/white means **Blank disabled**; empty with image or nonwhite means **Clear enabled**; artwork or field editing means **Wipe enabled**. The Classic rail button now follows this rule through `CanvasView.wipeStage`/`AppDelegate.updateWipeButton` (title and enabled state refresh on every document change, Undo/Redo and field-editor start/stop); the The Modern chrome Wipe button shares the `#selector(wipe)` action, so the same lookup retitles and enables it.
- Font `showHideFontPanel:` IMP `0xfb70`, decompiled8727: sharedFontPanel, isVisible, then orderOut or orderFront. Mode7 IMP `0xfb66`. It does not stop text editing, force first responder, or makeKeyAndOrderFront. Preserve this behavior.
- Original cluster-wide hover/click behavior: SKBezelClusterControl mouseUp `0x7f918`, hover `0x7f3a8` / `0x7f411`. Current horizontal native NSButtons are a readability adaptation; exact rendering/hover parity is not proven.

Recovered image chains (all root Resources, real original assets):

| Action | Image | Nib chain | Original pixels |
|---|---|---|---|
| Snap | SnapCrosshair | 274→278→279→280 | 20×19 |
| Font | Font | 419→424→427→421 | 20×16 |
| Actual off | ActualSizeToggleOff | 505→512→513→514 | 28×31 |
| Actual on | ActualSizeToggleOn | 505→512→515→516 | 28×31 |
| Resize | Resize | 477→480→482→483 | 7×7 |
| Save arrow | SaveToHistoryArrow | 459→464→465→466 | 10×9 |
| Hide | Hide | 146→444→446→447 | 16×17 |
| Frame Snap | SnapSnap | 308→310→311→312 | 25×48 |
| Frame Cancel | SnapCancel | 313→315→316→317 | 26×18 |

The Font image is `Font`, not `helpImageFont`.

## Invariants

- OriginalActionButton preserves native left-click, Control/right alternate handling, menu priority, accessibility/keyboard behavior, weak targets, cancellation and reentrancy safeguards. Normal Snap alone has the Fullscreen alternate; Frame clears and restores it. Do not regress that.
- Native menu dummy title/separator ownership belongs to NSPopUpButton; do not assert application-target ownership for unsupported native placeholder selectors.
- Bundle identifier stays `com.shoemoney.skitch-redux`; Application Support `SkitchRedux`, Keychain and serialization namespaces are intentionally preserved. Do not migrate user data to rename the UI.
- The supplied logo is packaged in `Resources/OpenSkitch.png` (header size 32, ten ICNS representations preserving alpha). `~/Projects/skitch-redux` is a compatibility symlink.
- Font Awesome Pro is never committed or shipped; `tools/check-no-fonts.py` guards the release bundle.
- Readable text is 18 points minimum, ordinarily 20. Do not shrink controls or force utility-window focus to simplify tests. No credentials, keys or secrets in logs, handoffs or committed artifacts.
- No AI attribution anywhere.
