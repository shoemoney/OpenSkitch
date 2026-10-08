# OpenSkitch agent handoff

Final handoff, October 7, 2026, America/Chicago. User requested merge/push to main, cleanup, and then stop.

## Final delivery and stop state

- Authoritative checkout is `/Users/shoemoney/Projects/OpenSkitch`; this OpenSketch directory is only the requested handoff location.
- All source changes described below are committed in `c7c8d93905204f43e0133abeca4f20c7374ea1c4` and included on `main`.
- Code checkpoint after the additional license commit: `eeb3008f954ab71c3cbf17a0e7a7628d02c01fbe`. The subsequent handoff commit changes documentation only.
- GitHub `shoemoney/OpenSkitch` is origin and the issue tracker. Forgejo `shoemoney/skitch-redux` is the push mirror. The configured origin pushes to both. Both main tips were verified equal at the code checkpoint, and both default branches are main.
- The merged local and remote `codex/native-reconstruction` branches were deleted after ancestor verification. There is only the primary checkout, with no attached temporary worktrees. The sidecar agent was shut down.
- Verification recorded for the delivered patch: 43,029 checks across 33 arm64 suites, successful arm64 build and native save/reopen/render/Quit. Source snapshot equality was rechecked during finalization. That aggregate predates `f7d4321`, which fixed both Fonts findings and changed the test counts; the 43,029 figure is no longer current and has not been re-measured.
- Keep ignored build/evidence folders and the original archive: they are needed for the next agent. Cleanup intentionally preserves them and user documents.
- The two Fonts review findings were fixed in `f7d4321` (Fonts panel keeps your divider and stays on screen). Corner/resizing work, live Fonts/capture proof, and broader original parity remain open. Nothing below claims full completion.
- The overarching goal is paused at the user request. Do not automatically resume development; wait for the user.
- A committed copy of this handoff is saved in `/Users/shoemoney/Projects/OpenSkitch/HANDOFF.md`.

## Start here: spelling and scope

The user explicitly requested this handoff in `~/Projects/OpenSketch` (with **e**). This directory is only the handoff location. The actual application repository is **`/Users/shoemoney/Projects/OpenSkitch` (with i)**. Do not move or rename that checkout.

The user is clearing context and has explicitly requested stopping after this delivery. The overarching goal remains a working, native, 64-bit Skitch reconstruction with all original functions and features. **Apple Silicon only; Intel support is no longer required.** The current priority is the interface first, followed by corners and resizing: “Corners / resizing needs to work but the interface would come before that.”

Use the supplied ShoeMoney logo for both the app icon and the header, with the header reading OpenSkitch. Those branding changes are already implemented. When the user resumes work, continue within the authorized project and desktop-testing scope, preserving user documents and avoiding unnecessary approval requests.

This is a Swift/AppKit reconstruction, not a successfully recompiled original binary. The archived original is 32-bit. **All 340 original feature parity flags remain unverified. Passing reconstruction tests does not prove full original equivalence.**

## Checkout and delivered changes

- Repository: `/Users/shoemoney/Projects/OpenSkitch`
- Branch: `main`
- Origin: `git@github.com:shoemoney/OpenSkitch.git`, also configured to push to the Forgejo mirror.
- Mirror: `ssh://git@git.shoemoney.ai:2222/shoemoney/skitch-redux.git`
- Delivered interface commit: `c7c8d93905204f43e0133abeca4f20c7374ea1c4`.
- Included native skill commits: `b3cec46` and `0cbc153`; agent/issue docs commit `6abf284`; license commit `eeb3008`. Preserve these.
- Earlier verified interface checkpoint: `8bd0e32f37b0c5bca4a23b2aa7e35ceb40889710`.

The delivered interface commit changes README.md, Sources/App.swift, Sources/TextStyleForm.swift, tests/AppSafetyTests.swift, tests/TextStyleFormTests.swift, and tools/build.sh. These changes are committed, not pending. The two concrete review findings recorded below were fixed afterward in `f7d4321`; they stay recorded so the fix is traceable. No live worker or verification sessions remain.

## Current verified build and tests

The delivered source patch built successfully for **arm64 only**. Binary SHA256:

```
e71a84b127c4447ca125b5fba9c346ffec6013f239eb532279156f91f4756012
```

Evidence paths below are relative to the actual repository:

- Build source snapshot: `build/source-snapshot.e8mJL4`
- Build log: `build/interface-layout-verification/build.log`, terminal exit 0.
- Full arm64 test snapshot: `build/test-snapshot.c775uhph`
- Full test log: `build/interface-layout-verification/arm64.log`, terminal exit 0, all suites passed with no source drift.
- **43,029 aggregate checks across 33 suites** were recorded for the delivered patch, before `f7d4321`. That aggregate is no longer current. After `f7d4321` the counts are **87 AppSafety cases** and **117 TextStyleForm checks**; the new aggregate has not been re-measured here.
- `build/interface-layout-verification/results.json` was generated while writing this handoff. Its summarizer checked the complete log counts and verified snapshot hashes against current sources.
- Startup proof: `build/startup-smoke-e71a84b127/results.json`, arm64 passed native save/reopen/render and Quit.
- Startup log: `build/interface-layout-verification/startup.log`, terminal exit 0.
- AppSafety temporary evidence: `/var/folders/_5/kk_5dshn1zx_mn3ftl5dl7g40000gp/T/skitch-app-safety.mTlIgJ`.

`Sources/TextStyleForm.swift` has zero deprecation warnings: it sizes toolbar popups with Auto Layout floors instead of `NSToolbarItem.minSize/maxSize` and styles `NSBrowser` through `cellPrototype`. `swiftc -typecheck Sources/*.swift` reports no deprecations.

The tracked `analysis/*.json` checkpoint metadata still describes **8bd0e32 / binary 896edbdebc**, not the current build. Do not confuse historical evidence with the current patch.

## What the delivered interface patch changes

### Main window, Sources/App.swift

- Centers the logo/OpenSkitch brand on the window itself instead of using symmetric spacers between unequal command groups. `OpenSkitchHeader` and `OpenSkitchBrand` are the identifiers. Left group: Hide, Toolbox, Photos. Right: Save, History. Minimum 12-point gaps.
- Uses the recovered original Hide and Save-arrow images. Save still invokes `saveHistory`; its original arrow is not a dropdown.
- Restores archive tool order: Select, Brush, Line, Ellipse, Rectangle, Fill, Eraser, Text, Arrow. Crop follows as an explicit additional tool. Original ToolOn/ToolOff artwork remains.
- Moves Font to the right rail after Color, using the original Font artwork.
- Normal right-rail capture controls are Snap and Cam. Removes the permanent Frame button; the Frame command remains in menus.
- Entering Frame replaces Snap/Cam with Snap Frame and Cancel: original `SnapSnap` / `SnapCancel` images, Cam hidden. Leaving restores normal Snap/Cam and the Fullscreen alternate. Existing stale-secondary-press cancellation is retained.
- Places Actual and Resize below the canvas at lower left, using original artwork; filename/export controls begin to their right.
- Pins Undo/Wipe together at the bottom of the right rail using a flexible spacer.
- Adds read-only layout evidence for header geometry and Fonts-panel window number.
- Fonts continues using native `orderFront(nil)` / `orderOut`, mode 7. No forced key window or first-responder changes.

### Native Fonts accessory, Sources/TextStyleForm.swift

- Adds a native scroll container with flipped document content. Controls retain readable 20-point text and full hit targets at constrained sizes; scrolling appears when needed.
- Narrows the split-layout adjustment to the evidenced outer native structure: direct vertical two-pane NSSplitView, family NSOutlineView left, non-outline NSTableView and accessory right, width at least 800. Widen the first pane to 360 only if narrower.
- Avoids `sizeToFit` overriding native toolbar allocation. Preserves toolbar/menu identity, field selection/query, existing font weights, allocated room, and refresh idempotence.
- Controlled nonvisible tests exercise this structure. **Actual Fonts-panel visual confirmation remains open.**

### Tests, packaging, documentation

- Existing AppSafety cases now verify centered header at default/minimum sizes, recovered tool order plus Crop, right-side Font, lower-left sizing controls, no permanent Frame button, and real menu/action Frame routing with Cam/Cancel replacement and restoration.
- TextStyleForm coverage expanded from 19 checks to 71 in the delivered patch, and to 117 with `f7d4321`, covering overflow, full-size control reachability, native state/callback preservation, matching split only, and toolbar allocation/style preservation.
- `tools/build.sh` packages these ten recovered images: `SnapCrosshair`, `SnapISight`, `Font`, `ActualSizeToggleOff`, `ActualSizeToggleOn`, `Resize`, `SaveToHistoryArrow`, `Hide`, `SnapSnap`, `SnapCancel`.
- README explains archive grouping and the explicit Photos/Crop/readability adaptations. Refresh final checkpoint information only after remaining fixes and verification.
- Corner/resize gesture engines were not changed in this pass.

## Fonts review findings: fixed in f7d4321

Both findings from the delivered-patch review were fixed in `f7d4321` (`fix: 🔤 Fonts panel keeps your divider and stays on screen 🖥️`). The fix is committed. Live Fonts-panel rendering is still unverified (see the desktop section).

1. **P2 (fixed): A font change could reset a divider the user dragged.** `changeFont` reset `fontPanelRecordedTypography`, and the refresh timer then re-applied the opening 360-point divider position. `f7d4321` splits the opening layout state (`fontPanelOpeningLayoutApplied`) from typography/evidence refresh. `prepareFontPanelLayout` reports whether the matching loaded structure was found, so the layout is retried only until applied. The flag is set per presentation on show and cleared on teardown, not on every font change. Late-loading panels now also receive the opening layout.

2. **P2 (fixed): The Fonts panel could extend offscreen on small displays.** It requested 940×720 content and clamped its origin as if the whole frame fit the visible screen. `f7d4321` bounds the frame to the usable display (`TextStyleForm.fontPanelFrame`) before positioning, and the accessory scrolls when constrained.

Regression coverage was added in `f7d4321` (TextStyleForm and AppSafety cases; counts in the stop state above). The reviewer found no additional blocking issue in header, rail/footer constraints, or the Frame replacement.

## Desktop state, proof, and limitations

At the end of testing the new app was running with a blank **Untitled, 800×600, Arrow, Saved** document. The native Fonts utility panel had been opened and was visible according to app-owned evidence. Do not assume any unsaved drawing can be discarded; recheck current state before quitting/rebuilding.

Current desktop artifacts:

```
build/interface-layout-verification/archive-groups-and-centered-brand.ax.txt
build/interface-layout-verification/archive-groups-and-centered-brand.png
```

The screenshot was reviewed: centered logo/title, recovered tool order and selected Arrow, original header/capture/font images, Font on right, Actual/Resize lower left, Undo/Wipe bottom right. It proves the default-size main window only. Minimum-size geometry passed controlled tests but has not been freshly reviewed on the desktop. Live Frame/Cancel behavior and actual Fonts-panel rendering remain unverified for this build.

App-owned metrics are at:

`/Users/shoemoney/Library/Application Support/SkitchRedux/layout.json`

Last observed metrics: Fonts visible, window number 101865; main-window brand center offset 0.25 points. A Cua attempt to select the utility window by numeric windowId was rejected: macOS getApp requires app name, path, or bundle ID. Do not repeat that unsupported API or force key-window behavior just to ease testing.

Use **mcp__cua_repl** for real UI interaction/screenshots, not shell accessibility, AppleScript, CGEvent, or screencapture. After compaction call `await cua.rewriteDocumentation()` before continuing an existing computer-use session, and read the current supported API. Persistent bindings may be unavailable in a new agent; select the app again using the supported path/name entry point.

Important UI-test lesson: use fresh accessibility indices for each action. Escape may collapse one submenu without closing all menus. A stale index previously changed window placement during a Fonts check; placement was restored through Window > Move & Resize > Return to Previous Size, and the Saved state was reconfirmed.

The most recent actual capture attempt, at the prior checkpoint, was blocked by macOS Screen Recording permission. No permission was changed by this agent. System Settings was later observed running, so current permission state must be rechecked through an appropriate real test; do not assume it changed. Native picker/countdown/capture proof remains incomplete. Do not alter security settings silently.

## Original archive evidence: authoritative for interface fidelity

Original archive: `original/Skitch.app/Contents/Resources/English.lproj/MainMenu.nib`, version 1.0.12, root size 800×640. Coordinates below use the original bottom-left system. The shipped archive overrides assumptions drawn from older help screenshots.

- Hide UID146 `(13,612,24,25)` invokes `vanish`; Toolbox UID137 `(43,616,27,17)` is image-only, menu1907→1570.
- Evernote UID439 is hidden at startup. No top Photos button; Browse Photos menu1589 invokes `showMedia`. Current Photos is an explicit addition.
- Save cluster263 `(670,613,45,23)`, label457 and arrow459 all invoke `historyArchive`. History328 `(717,617,46,15)` invokes `showHistory`.
- Normal Snap/Cam container185 `(764,520,37,86)` uses tab1. Frame tab2 replaces it with Snap/Cancel. There is no permanent Frame rail button.
- Font cluster415 `(764,425,37,39)` is on the right. Color296 `(764,470,37,46)`, size423, slider503 follow the same right-side grouping.
- Undo430 `(765,91,35,21)` uses responder-chain undo; Wipe172 `(765,71,35,21)` uses dynamic state.
- Actual505 `(4,77,28,31)` and Resize435 `(13,45,76,26)` are lower left.
- Left tools178 `(0,376,37,231)`, 31×31, ordered Cursor, Brush, Line, Circle, Rectangle, Fill, Eraser, Text, Arrow. Crop is not one of the nine.
- Frame mode `setSnapMode:` IMP `0x2067c`, decompiled.c around20481: normal tab1 shadow/alpha1, Frame tab2 no shadow/alpha0.8. Current exact shadow/alpha fidelity remains open.
- Actual enabled getter `0x91d0`, decompiled4656: alreadyActual OR document + capturemode0 + pixelSize()<1.0; Float32 constant at `0x260470` is 1.0.
- `updateWipeButton` IMP `0x25d45`, decompiled24681: empty/no field editing/no background image/white means **Blank disabled**; empty with image or nonwhite means **Clear enabled**; artwork or field editing means **Wipe enabled**. The Classic rail button now follows this rule through `CanvasView.wipeStage`/`AppDelegate.updateWipeButton` (title and enabled state refresh on every document change, Undo/Redo and field-editor start/stop); the Modern chrome button is not yet wired into the app.
- Font `showHideFontPanel:` IMP `0xfb70`, decompiled8727: sharedFontPanel, isVisible, then orderOut or orderFront. Mode7 IMP `0xfb66`. It does not stop text editing, force first responder, or makeKeyAndOrderFront. Preserve this behavior.
- Original cluster-wide hover/click behavior: SKBezelClusterControl mouseUp `0x7f918`, hover `0x7f3a8` / `0x7f411`. Current horizontal native NSButtons are a readability adaptation; exact rendering/hover parity is not proven.

Recovered image chains (all root Resources, real original assets):

| Action | Image | Nib chain | Original pixels |
|---|---|---|---|
| Snap | SnapCrosshair | 274→278→279→280 | 20×19 |
| Cam | SnapISight | 292→297→298→299 | 19×16 |
| Font | Font | 419→424→427→421 | 20×16 |
| Actual off | ActualSizeToggleOff | 505→512→513→514 | 28×31 |
| Actual on | ActualSizeToggleOn | 505→512→515→516 | 28×31 |
| Resize | Resize | 477→480→482→483 | 7×7 |
| Save arrow | SaveToHistoryArrow | 459→464→465→466 | 10×9 |
| Hide | Hide | 146→444→446→447 | 16×17 |
| Frame Snap | SnapSnap | 308→310→311→312 | 25×48 |
| Frame Cancel | SnapCancel | 313→315→316→317 | 26×18 |

The Font image is `Font`, not `helpImageFont`.

## Evidence reconciliation still pending

Current ignored helper/evidence files under `build/` are important; preserve them locally:

- `run-interface-layout-verification.py`: runs/saves arm64 build/test/startup logs.
- `summarize-interface-layout-tests.py`: now run successfully; current results.json exists.
- `reconcile-interface-layout.py`: copied/adapted from the preceding interface checkpoint; **not run**. Review before use, including stale wording and source anchors.
- `interface-layout-verification/previous-build-validation.json` and `previous-reconstruction-progress.json`: historical baseline.

Current `original-recovery.json` and `desktop-proof.json` do not yet exist in this folder. Do not invent proof. Record actual successes and limitations, then reconcile tracked metadata against the final source/binary. Retain all original parity flags as unverified unless supported by the required evidence.

The prior complete checkpoint evidence is in `build/interface-verification/`, startup folder `build/startup-smoke-896edbdebc`, binary SHA256 `896edbdebc490b5e7a19133ad03704ab151c2fb1d34b9f1386ed24019c6a9893`. It passed 42,977 checks in 33 suites and 85 AppSafety cases. Its audit covered 1,535 metadata anchors. That desktop proof is historical, not proof of current Fonts rendering.

## Broader remaining work and important invariants

- Read `analysis/feature-inventory.json`, `analysis/feature-evidence.json`, and `analysis/reconstruction-progress.json` for the larger reconstruction scope.
- OriginalActionButton from the prior checkpoint preserves native left-click, Control/right alternate handling, menu priority, accessibility/keyboard behavior, weak targets, cancellation and reentrancy safeguards. Normal Snap alone has the Fullscreen alternate. Frame clears/restores it and cancels an armed stale press. Do not regress that behavior.
- Native menu dummy title/separator ownership belongs to NSPopUpButton; do not assert application-target ownership for unsupported native placeholder selectors.
- Capture implementation has owned region/window selection and original six-second Shift timing, but magnifier/window hover, flash/cursor/mixed displays and some cancellation behavior remain unproven/incomplete. Original camera timing/raw-versus-preview behavior was recovered but is not fully integrated with the current PhotoOutput implementation.
- Supplied logo is already packaged in `Resources/OpenSkitch.png`, header size32, ten ICNS representations preserving alpha, Info.plist CFBundleIconFile OpenSkitch.
- Bundle identifier remains `com.shoemoney.skitch-redux`; Application Support `SkitchRedux`, Keychain and serialization namespaces are intentionally preserved. Do not migrate user data merely to rename the UI.
- `~/Projects/skitch-redux` is a compatibility symlink; `~/Applications/OpenSkitch.app` points to the authoritative built app.

## Resume sequence

1. Read this handoff, inspect the actual checkout and current diff, read applicable instructions/skills. Start with `/Users/shoemoney/.codex/RTK.md`, `/Users/shoemoney/AGENTS.md`, `/Users/shoemoney/Projects/AGENTS.md`; also read the repository AGENTS.md and referenced docs/agents files. The appkit-interop skill is at `/Users/shoemoney/.codex/skills/appkit-interop/SKILL.md`, and newly vendored native skills are under the repository `.claude/skills/`.
2. The two Fonts review findings are already fixed in `f7d4321`. Re-verify them with step 3 and keep native presentation, divider choices, text state and readability intact in any later change to that code.
3. Recheck the currently running app/document through supported Cua controls. Quit safely before overwriting its built bundle. Run appropriate verification on the final source snapshot:

   ```sh
   cd /Users/shoemoney/Projects/OpenSkitch
   rtk proxy git status --short
   rtk proxy python3 tools/test.py --arch arm64
   rtk proxy sh tools/build.sh
   rtk proxy python3 tools/test-native-startup.py
   ```

4. Capture/review fresh main-window and minimum-size UI, live Frame replacement/Cancel, tool feedback, and Fonts-panel rendering if the supported UI tools permit. Clearly mark anything not observed. Native tests alone are not visual proof.
5. Finish original recovery/current desktop evidence, update metadata and source/hash anchors accurately, audit them, then commit/push the completed patch without AI attribution. Preserve the native skill, issue-documentation and license commits.
6. Continue remaining interface fidelity and then the user-requested corners/resizing work. When the user resumes, preserve the full original goal; do not claim completion until the actual full requirement is met.

Global design preference: readable text has an 18 minimum, ordinarily20; preserve comfortable spacing and contrast. Semantic Font Awesome icons are preferred for new generic UI; the user's explicit original Skitch fidelity requirement permits the recovered original assets here. Do not introduce tiny controls or force utility-window focus to simplify tests. Never put credentials, private keys or secrets into logs, handoffs or committed artifacts.

No security permission changes, external publishing/uploading, or user-document deletion were performed during this interface pass. This handoff records a committed and pushed, tested reconstruction checkpoint with documented remaining work; it does not claim full original parity.
