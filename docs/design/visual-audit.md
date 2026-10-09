# OpenSnap visual and cosmetic audit (2026-10-09)

Status: **FINAL (audit + specification; no product code changed).** 297 app-owned captures (205 at
`b9319c4`, 84 at `dc1eb26`, 8 prototype mocks), with live view-tree metrics, AX dumps and a live layout
budget, in `evidence/2026-10-09/`. Capture stems are written `<surface>-<slug>-<light|dark>`; the
`@dc1eb26` suffix marks the current-main delta set. Every manifest entry carries `sourceSha`.

## Summary

- **29 findings** (VF-01..VF-29): 6 P0, 16 P1, 7 P2. By the core claim's evidence class (§6 headers):
  rendered or measured (R/M) for 22; source-only (S) for 6 (VF-01, VF-10, VF-12, VF-14, VF-22, VF-23; VF-10,
  VF-12 and VF-23 also carry supporting rendered observations); 1 unverified (U, VF-27).
- **36 todos** (OSN-*), all **pending**, in 8 milestones (M0–M7). The owner's P1 layout request (remove
  the right rail) is milestone **M1** (OSN-010..OSN-014). Its fit at the 980-pt minimum is confirmed by
  a live measurement (§8).
- **`main` moved twice during the audit** (`b9319c4` → `4b2ae0f` → `dc1eb26`). Classic removal, the
  original assets, the clean-clone build and the hint copy landed in source at `dc1eb26`. The OpenSnap
  rename (WP4) is in flight on another branch. §6.0 gives each finding's status at `dc1eb26`.
- **The biggest visible problems on current `main`:** the blank right-rail column (VF-07); two stacked
  bars (VF-08); 26 separate glass pills (VF-09); "Skitch"/"OpenSkitch" in Preferences, About, hotkeys
  and the title (VF-03); 18-pt default text plus tooltip-only command names (VF-11); weak
  hover/focus/disabled states (VF-13); Frame-mode status truncation (VF-26).
- **Foundation blockers still open:** the safe screenshot path (OSN-001, VF-06: `tools/eye-dump.sh` can
  still write to the owner's real preferences), the owner decisions (OSN-002, including whether Font
  Awesome can ship in releases), WP4 identity and migration (OSN-030/031), and synthetic test fixtures
  (OSN-024).
- **Coverage gaps (§5):** Reduce Transparency/Motion, Increase Contrast, Bold Text, VoiceOver speech,
  1× displays, multi-display, live capture, the Photo browser (S22) and pixel captures of open menus
  (S23) were not rendered. The reasons are recorded.

## 0. Snapshot and drift (read first)

| Item | SHA | Notes |
|---|---|---|
| Audit briefed against | `b9319c4` | Modern UI with Classic code still present; footer format was a 12-item popup. |
| `main` when the owner's layout feedback arrived (10:24 CDT) | `4b2ae0f` | The PNG/JPG footer toggle landed in `88d8865` → `f19dfde` → `4b2ae0f` (9 files: `App.swift`, `App+ModernChrome.swift`, `ModernEditorChrome.swift`, `ExportAccessory.swift`, `ImageExport.swift`, tests). |
| Source inventory and technical spec line numbers | `4b2ae0f` | Child B re-derived every `file:line` from a pinned archive of `4b2ae0f`. |
| First rendered capture set | `b9319c4` | Built on the harness branch `audit/visual-harness` (forked at `b9319c4`). Every manifest entry carries `sourceSha`. |
| `main` at 11:01 CDT (re-checked by Opus) | `dc1eb26` | Nine commits after `4b2ae0f` landed declassic **WP1** (own assets: drawn countdown digits, system cursors, silent no-op sounds, FA→SF→none icons), **WP2** (Classic, Appearance, Relaunch and the welcome doc deleted; macOS 26.0 target), **WP3** (`build.sh` needs no `original/`, empties the bundle every build, `check-no-original.py` + `original-resource-hashes.txt`) and **WP6** (hint copy rewritten, README/HANDOFF, `analysis/` untracked). |
| In flight, not on `main` | `opensnap/w3-rename` (worktree `.todo-worktrees/w3-rename`, uncommitted) | **WP4**: the OpenSnap rename (Info.plist, README, HANDOFF, `OpenSnap.icon`). Not audited; another agent owns it. |
| Delta capture set (editor, footer toggle, widths, Frame, countdown, Preferences, status item, About, drag overlays) | `dc1eb26` (confirmed in the manifest) | Suffix `@dc1eb26`. These captures supersede the `b9319c4` observations wherever the two differ. The `4b2ae0f` delta was superseded before assembly and is not in the output. |

Line numbers in `technical-spec.md`/`source-inventory.md` are at `4b2ae0f`. Classic-related lines they cite are gone at `dc1eb26`, and WP4 will move them again. **Re-derive every `file:line` at the SHA a todo starts from.**

Rule used throughout: an observation is only as current as the SHA it was captured on. A footer
finding seen on `b9319c4` (12-format popup) is marked **superseded** where `4b2ae0f` changed it.

## 1. Files under `docs/design/` and who owns them

| File | Owner | Model |
|---|---|---|
| `visual-audit.md` (this file: method, design target, surface inventory, coverage, findings, backlog skeleton) | orchestrator | Opus 5.5 |
| `user-feedback.md` (owner layout feedback) | root | – (read-only here) |
| `evidence/2026-10-09/**` (captures, metrics, AX dumps, menus, manifest, captures.md, gaps.md, layout-width-budget.*) | evidence child A | Sonnet 5.5 |
| `source-inventory.md`, `technical-spec.md` (T1–T15), `evidence/source-font-sizes.json` | source/spec child B | Sonnet 5.5 |
| `roadmap.md`, `todo-checklist.md`, `backlog.json`, `README.md` | docs child C | Haiku 5.5 |

## 2. Evidence classes, confidence and severity

| Tag | Meaning |
|---|---|
| **R** observed | Seen in an app-owned rendered capture (the capture stem is cited). |
| **M** measured | Read from the live view-tree metrics, AX dump, layout budget or a probe (the JSON/probe is cited). |
| **S** source-inferred | Read from code (`file:line` at `4b2ae0f` unless stated). Not seen rendered. |
| **U** unverified | Plausible, but neither rendered nor confirmed in source. It needs a check before work starts. |

Confidence is **H**igh, **M**edium or **L**ow. Severity:
- **P0** blocks the OpenSnap direction, breaks a hard owner rule (identity, original assets, data
  safety, the readable-text floor on a primary surface), or is a foundation the rest depends on.
- **P1** is a visible quality or accessibility defect on a main surface, or an owner-required change.
- **P2** is polish.

**Never a rendered visual audit:** sections 6 and 7 cite R/M only where a capture or measurement
exists. Everything else is labelled S. The coverage gaps (§5) list what was not rendered at all.

## 3. Design target (what "done" looks like; measurable)

Values are specified in `technical-spec.md` T1–T7 and T15. These are the acceptance rules the
findings are judged against.

| # | Rule | Measurable acceptance |
|---|---|---|
| D1 | **Content first.** The canvas is the largest element; no permanent empty columns. | No rail column. Canvas viewport width ≥ window width − 2 × margin (T15). |
| D2 | **Single-level glass navigation.** Glass only on the top bar and the bottom bar's action group, one plate per group, never glass inside glass, never glass over the canvas at rest. | Walker: glass depth ≤ 1; glass count ≤ T4 budget; no glass frame intersects the scroll view frame. |
| D3 | **Solid readable content surfaces.** The canvas well, sheets, lists and forms sit on solid semantic colours. | No `NSVisualEffectView`/behind-window material behind the canvas; `surface.canvasWell` is opaque (T2). |
| D4 | **Readable native type.** UI text ≥ 18 pt, default 20 pt; 18 only for the `caption` role. | Walker: no visible app-owned text < 18 pt; every `body` role = 20 pt. Native system-owned text (menu bar, tooltips, NSAlert, save panel, Fonts panel, About) is listed separately as **N-exceptions** with an owner decision (§6, VF-11). No CSS exists in the repo (S, child B §0). |
| D5 | **Tokens, not literals.** Type, spacing (4-pt grid), radius (concentric), colour (semantic, dynamic, high-contrast arms), sizes. | Source gates in T1–T3 pass (0 literal font sizes, radii or constraint constants outside `DesignTokens.swift` and the annotation/content code). |
| D6 | **Semantic states.** Every interactive control has rest/hover/pressed/selected/disabled/focus, plus a non-colour cue for selection when Differentiate Without Color is on. | `StateStylesTests` (T6) plus a capture per state. |
| D7 | **One icon family, semantic glyphs.** Real Font Awesome semantic icons in chrome (subject to decision Q1), no SF/FA mixing inside a bar, no decorative arrows/starbursts/emoji; the arrow **tool** keeps its arrow. | `IconCoverageTests` + no-decorative-glyph gate (T5/T14). |
| D8 | **OpenSnap identity, no original assets.** No "Skitch" in user-visible strings; no file from the original bundle ships or is needed to build. | `check-no-original` byte-match gate + `check-skitch-strings` gate + clean-clone build (T13/T14). |
| D9 | **Accessible by default.** AX label + role on every control; key-view loop in reading order; Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color all consumed. | T7 tests plus captures with an injected `DisplayOptions` (§5 explains why system toggles are not used). |
| D10 | **No Classic revival.** Nothing reproduces 2008 Skitch art or copy. | – |

## 4. Surface inventory

Builders, owning files and Classic dependencies are in `source-inventory.md` §11 (S01–S33). Rendered
coverage per surface is filled from the evidence manifest in §5.

## 5. Coverage matrix and gaps

Rendered coverage (from `evidence/2026-10-09/manifest.json`; L = light, D = dark):

| Surface | `b9319c4` | `dc1eb26` | Notes |
|---|---|---|---|
| S01 editor empty | L D | L D | |
| S02 editor populated (every annotation kind) | L D | L D | |
| S03 top bar + rail crops | L D | L D | |
| S04 tool states (each tool, hover, pressed, disabled) | L D | – | hover/pressed forced through `GlassSurfaceView` |
| S05 selection + text editing | L D | L D | |
| S06 color popover, color panel, Fonts panel, size slider | L D | – | Fonts panel left pane renders blank (harness limit) |
| S07 viewport: actual, fit, centred, 25/50/200% | L D | L D | baseline "small centred" invalid (flagged); delta re-shot |
| S08 crop + Resize panel | L D | – | |
| S09 footer (+ PNG/JPG toggle states at `dc1eb26`) | L D | L D | b9319c4 popup-open capture dropped |
| S10 export accessory | L D | – | the real save panel is out of process |
| S11 sizes: min, default, wide, tall, maximized, 980/1024/1280/1440, full screen | L D | L D | full screen at `dc1eb26` only |
| S12 Frame mode (+ 980/1024) | L D | L D | |
| S13 picker / magnifier (grey lens + synthetic lens) | L D | – | overlay windows only, no desktop behind |
| S14 countdown 3/2/1 | L D | L D | original art at `b9319c4`; drawn tile at `dc1eb26` |
| S15 flash | L D | – | full-alpha panel only |
| S16 permission alert | L D | – | glass backdrop flattened (harness limit) |
| S17 Preferences | L D | L D | Classic/Sounds rows gone at `dc1eb26` |
| S18 Hotkeys sheet | L D | – | |
| S19 Destinations (empty, list, edit form, focus) | L D | – | synthetic destinations, fake in-memory secret |
| S20 History (empty, populated) | L D | – | synthetic entries |
| S21 publish progress / success / error | L D | – | stubbed uploader, no network |
| S22 Photo browser | – | – | **gap**: reads the real Photos library and Desktop |
| S23 menus | text only (`menus.json`) | – | **gap**: menu windows absent from own-window composites |
| S24 status item | L D | L D | template drawn outside the menu bar (may look invisible) |
| S25 About | L D | L D | |
| S26 alerts / sheets | L D | – | no Wipe confirmation exists |
| S27 first launch / welcome | L D | – | welcome doc removed at `dc1eb26` (not re-shot) |
| S28 keyboard focus rings | L D | – | |
| S29 drag thumbnail + hint bevel | L D | L D | |
| PROTO rail-less mock (not product) | – | L D | 980/1280, normal/Frame |

Live layout budget: `layout-width-budget.json/.md` at `dc1eb26`, 980/1024/1280/1440 × normal/Frame,
window height fixed at 772 pt. Text-size measurements: `metrics/text-size-summary.md` (from the
`b9319c4` trees).

Environment (M, `environment.json`): macOS 27.2 (build 26B5101f), built-in Retina display
3456 × 2234 px at 2× (1728 × 1117 pt), system appearance Dark, accent colour yellow. The accent colour
is the owner's system setting. Every "accent" in the captures is therefore yellow; on the default
blue accent the same states render blue.

Known structural gaps (not fakeable, by rule):
- Reduce Transparency, Increase Contrast, Reduce Motion and Bold Text were **not toggled**: changing
  system settings is forbidden for this audit. The code paths are S only. Closing this gap needs
  either the owner toggling the settings for a capture run, or the injected-`DisplayOptions` capture
  mode that OSN-061 specifies.
- VoiceOver speech was not run. The AX dump is a structural substitute only.
- 1× non-Retina, multi-display and live capture (Screen Recording is not granted) are not covered.
- Native tooltips, the share picker, real drag-and-drop to Finder and real uploads were not exercised
  (window-server drawn, out of process, or forbidden). The publish states use a stubbed uploader.
- Glass materials behind alerts and the status button are not captured by own-window imaging; those
  PNGs are flattened onto a neutral backdrop (`flattenedOnBackdrop` in the manifest).
- Per-capture review: the evidence child opened about 25 PNGs one by one and reviewed the rest on
  contact sheets. Opus opened about 30 captures across both SHAs, including every one cited below.
  Full list: `evidence/2026-10-09/gaps.md`.

## 6. Findings

Each finding: ID · title · severity · evidence class/confidence · surfaces · evidence · user-visible
issue · direction (technical-spec section). The backlog todos in §9 reference these IDs.

### 6.0 Finding status at `dc1eb26` (Opus source re-check, 11:05 CDT)

Severity is unchanged: it records what the finding was at audit time. "Landed (S)" means the fix is in
source on `main` but has **not** been visually verified or gate-verified by this audit. The owning
todo stays **pending** until its visual check and gate pass.

| Finding | Status at `dc1eb26` | Evidence of the change |
|---|---|---|
| VF-01 clean-clone build | **Landed (S)**. Residual: 5 test files still reference `original/` (`ResizePresetsTests`, `LegacyHistoryImporterTests`, `SVGExportTests`, `CanvasTests`, `SkitchFileTests`). | `tools/build.sh` has 0 `original/` references; `tools/check-no-original.py` exists |
| VF-02 original art/sounds ship | **Landed (S)**. Status item = SF `camera.viewfinder` template; drag overlays = drawn SF badges; countdown drawn | grep for every original asset name in `Sources/` returns 0; `App.swift:385-393`, `:145-150` |
| VF-03 "Skitch"/"OpenSkitch" identity | **Open, in flight** (WP4 on `opensnap/w3-rename`). 29 user-visible "Skitch" literals remain on `main`, e.g. "Show Skitch window in fullscreen…" and "Show Skitch in:" (`GeneralPreferencesForm.swift:37,79`); "OpenSkitch" in the title, app menu and About (`App.swift:668,725,1955`) | – |
| VF-04 Classic selectable | **Landed (S)**. The Appearance row, Relaunch and "Play sounds" are gone; `Appearance.swift` and `ToolButton.swift` are deleted | `GeneralPreferencesForm.swift:37-79` |
| VF-05 FA can't ship | **Open** (decision Q1). `release.sh:30` still builds with `OPENSKITCH_NO_PRO_FONTS=1` | – |
| VF-06 unsafe screenshot tool | **Partly**. The original fixture is gone, but `tools/eye-dump.sh` still runs the bundle binary in place with the real bundle id, so the real defaults domain is still at risk | `tools/eye-dump.sh` at `dc1eb26` |
| VF-07 right rail | **Open** | `ModernEditorChrome.swift:331-396` (`rightRail`) |
| VF-08 two stacked bars | **Open** | `App.swift:667` style mask unchanged |
| VF-09 26 glass pills | **Open** | unchanged |
| VF-10 translucent canvas surround | **Open** | `ModernEditorChrome.swift:76,234` |
| VF-11 18-pt default / system text / tooltip names | **Open** | – |
| VF-12 no tokens | **Open** | – |
| VF-13 states | **Open** (`textColor(on:)` moved into `GlassChromeButton`; behaviour unchanged) | `GlassChrome.swift:176` |
| VF-14 keyboard/AX | **Open** | – |
| VF-15 canvas border at rest | **Open** | – |
| VF-16 permission alert | **Open** | – |
| VF-17 upload feedback | **Open** | – |
| VF-18 Preferences structure | **Partly** (Classic rows gone). Still titled "Preferences", with a Done button and the NSTabView box | `App.swift:1498`, `GeneralPreferencesForm.swift:108` |
| VF-19 Destinations sheet | **Open** (owner-specific placeholders still at `PublishingDestinationsView.swift:214-215`) | – |
| VF-20 History window | **Open** ("Saved/DragMe'd" at `HistoryBrowser.swift:26`) | – |
| VF-21 window state / full screen | **Open** | – |
| VF-22 Actual Size control | **Open** | – |
| VF-23 copy/glyph defects | **Partly**. Hint copy rewritten ("Shift snaps to 45°.", no U+F8FF in copy), but the Toolbox still uses ASCII `...` (`App.swift:632-633`) | `OriginalHintMessages.swift:55-56` |
| VF-24 stale dev bundle | **Landed (S)** | `tools/build.sh:15` `rm -rf "$APP"` |
| VF-25 mixed icon families | **Open** (the drag badge is now an SF double arrow) | `App.swift:145-150` |
| VF-26 status truncation | **Open** (R/M at `dc1eb26`) | `layout-width-budget.json` |
| VF-27 scroller in the Frame hole | **Open / U** (R at `dc1eb26`) | S12-frame-w980-light@dc1eb26 |
| VF-28 highlighter cap | **Open** (R at `dc1eb26`) | S02-populated-light@dc1eb26 |
| VF-29 fractional Resize size | **Open** (R at `b9319c4`; not re-shot) | S08-resize-panel-light |

### Foundation (P0)

**VF-01 · A clean clone cannot build; the build copies the original Skitch bundle** · P0 · S/H · build
- Evidence: `tools/build.sh:14-43` (11 `cp` statements from `original/Skitch.app/Contents/Resources`,
  `set -eu` aborts at line 14 when the file is absent). Child B §6.2.
- Issue: OpenSnap cannot be built or verified by anyone else; every release depends on a private copy
  of Skitch.
- Direction: T13 / declassic WP3. Clean-clone build + `check-no-original` gate.

**VF-02 · The shipped Modern UI still renders original Skitch artwork and sounds** · P0 · R+S/H · S14, S24, S29, S05, S17
- Evidence (S): countdown numerals `SkitchCount1-3.png` (`OriginalCaptureCountdown.swift:53-56`; the
  panel does not appear at all without them, `:53-81`); status item `menu.png`/`menu-sel.png`
  (`App.swift:430-431`); drag-thumbnail overlays `Skitch_ShowSkitch*`/`Skitch_Cancel_DragMe`
  (`App.swift:173-177`); move cursor `CursorMove.png` (`Canvas.swift:173-179`); 9 `.m4a` sounds
  (`OriginalGeneralPreferences.swift:70`); welcome document `firstlaunch.skitch` (`App.swift:321`).
- Evidence (R) at `b9319c4`: Preferences shows "Play sounds" (S17-preferences-general-light); the countdown
  uses the original numeral art (S14-countdown-2-light); the drag thumbnail shows the "Show Skitch" plate
  (S29-drag-thumbnail-expand-light); the welcome document opens on first launch (S27-*).
- Evidence (R) at `dc1eb26`: the countdown is a drawn rounded tile with a white numeral
  (S14-countdown-2-dark@dc1eb26); the drag thumbnail shows a drawn expand badge
  (S29-drag-thumbnail-expand-light@dc1eb26); Preferences no longer has "Play sounds"
  (S17-preferences-general-dark@dc1eb26).
- Issue: owner direction is silent + minimal with every original asset removed. Today they ship.
- Direction: T13 / WP1 + WP2 (drawn countdown digits, system cursors, own template status icon, own
  drag overlays, sounds and the sound pref deleted, no welcome document).

**VF-03 · User-visible identity is "OpenSkitch"/"Skitch"** · P0 · R+S/H · S01, S17, S18, S20, S24, S25, S26
- Evidence (R) at `b9319c4`: Preferences "Show Skitch in:", "Takes effect the next time OpenSkitch opens.",
  "Relaunch OpenSkitch" (S17-preferences-general-light); History tab "Saved/DragMe'd"
  (S20-history-empty-light); Fonts panel "Default Skitch Style" (S06-fonts-panel-*).
- Evidence (R) at `dc1eb26`: "Show Skitch in:" (S17-preferences-general-dark@dc1eb26); About reads
  "OpenSkitch" with the credits "Native 64-bit reconstruction for personal use. Feature parity with
  Skitch 1.0.12 is still in progress." (S25-about-panel-light@dc1eb26).
- Evidence (S): 25 user-visible "Skitch" sites and 11 "OpenSkitch" lines (child B §7). Examples:
  status tooltip `App.swift:432`; About credits "Native 64-bit reconstruction … parity with Skitch
  1.0.12" (`App.swift:2176`); default title "OpenSkitch" (`App.swift:718`, `App+ModernChrome.swift:22`);
  "Default Skitch Style" (`TextStyleForm.swift:11`); hotkey "Show Skitch" (`GlobalHotkeys.swift:15`);
  export format "Skitch" (`ExportAccessory.swift:6`); History drag format "SKITCH" (`HistoryBrowser.swift:45,315`).
- Direction: T12 / T13 / WP4 + WP6, with the `check-skitch-strings` gate (T14).

**VF-04 · Classic is still selectable in Modern Preferences** · P0 · R/H · S17
- Evidence (R): "Appearance: ● Modern ○ Classic" and a "Relaunch OpenSkitch" button
  (S17-preferences-general-light). S: `GeneralPreferencesForm.swift:44-81,107-108`.
- Issue: the owner removed Classic, yet a single click restores the 2008 UI.
- Direction: T13 / WP2.

**VF-05 · Released builds cannot show Font Awesome; the semantics of the fallback icons drift** · P0 (decision) · S+M/H · all chrome
- Evidence: `tools/release.sh:27-41` builds with `OPENSKITCH_NO_PRO_FONTS=1` and fails if any font
  ships (`check-no-fonts.py`), so a release runs the SF Symbol fallback (`ChromeIcons.swift:38-54`).
  The dev captures show FA Pro (the bundle contains `FontAwesome7Pro-*-subset.ttf`, M: `ls` of
  `build/OpenSkitch.app/Contents/Resources` at 09:56). Wipe falls back to `trash`
  (`FontAwesomeIcons.swift:72`), a different meaning (delete vs. wipe).
- Issue: what the owner reviews (dev, FA) is not what users get (SF). The rule "actual FA semantic
  assets" cannot hold for releases until licensing is decided.
- Direction: owner decision Q1 (technical-spec §0). T5. Until then, every visual acceptance run
  captures **both** icon modes.

**VF-06 · The existing screenshot tool writes to the owner's real preferences and uses the original welcome doc** · P0 (data safety) · M+S/H · tooling
- Evidence (M): a 10:02 probe with a throwaway domain showed that `CFFIXED_USER_HOME` does not
  redirect `UserDefaults`; the plist landed in the real `~/Library/Preferences` (the probe domain was
  deleted). `tools/eye-dump.sh:11-19` runs the bundle binary (bundle id `com.shoemoney.skitch-redux`)
  in place with `SKITCH_FIXTURE=original/…/firstlaunch.skitch`.
- Issue: running the visual gate can rewrite the owner's live settings, and its captures contain
  original Skitch content.
- Evidence (S, child A at `dc1eb26`): the original fixture is gone, but the script still runs the bundle in
  place with the real bundle id.
- Evidence (M, harness QA by Opus): the audit harness's metrics walker records the **value** of secure
  text fields (the synthetic `example-secret-not-real` appears in `metrics/S19-destinations-edit-form-light.json`).
  It is harmless with synthetic data, but it must redact before the harness becomes the standard path.
- Direction: OSN-001. Adopt the audit harness (isolated bundle id + throwaway defaults domain,
  synthetic fixture, before/after real-store hashes, **secure-field redaction**) as the only screenshot
  path.

### Owner-required layout (P1)

**VF-07 · The permanent right rail reserves a mostly blank column** · P1 owner-required · R+S(+M pending)/H · S01, S02, S11, S12
- Evidence (R): in every editor capture, Snap, Color, Font, the vertical size slider, Undo and Wipe
  stack in a 64-pt column at the right edge. Below Wipe, the column is empty down to the footer
  (S01-editor-empty-light, S11-size-contentmin-light, S02-populated-light). In Frame mode the column
  also holds Cancel (S12-frame-mode-light).
- Evidence (S): `ModernEditorChrome.swift` creates `rightRail` (`Metrics.rightRailWidth` 64 +
  gap 8), and `scrollView.trailingAnchor` is pinned to `rightRail.leadingAnchor`. Line numbers:
  technical-spec T15.
- Evidence (M, `layout-width-budget.json` at `dc1eb26`): the canvas ends 84 pt from the window edge (12 margin
  + 64 rail + 8 gap). The scroll view is 884/928/1184/1344 pt wide at 980/1024/1280/1440. The rail's
  empty area is about 24,320 pt², 3.2% of the window at 980 and 2.2% at 1440. In full screen the rail
  is a thin column of controls at the far right edge of a 1728-pt-wide screen
  (S11-size-fullscreen-dark@dc1eb26).
- Owner: "the buttons extending the right side … could be relocated on the top bar or bottom and we
  could eliminate all that blank space" (`user-feedback.md`).
- Direction: T15. The recommended mapping is in §8.

### Navigation chrome and content surfaces (P1)

**VF-08 · Two stacked bars: a system title bar above a separate glass command bar** · P1 · R/H · S01–S12
- Evidence (R): a full-width opaque title bar ("Untitled") sits above the glass header row in every
  editor capture (S01-editor-empty-light). S: plain titled window, no `.fullSizeContentView` or
  toolbar (`App.swift:716-718`).
- Issue: about 28 pt of vertical chrome is spent on a title strip. On macOS 26 the title and commands
  normally share one unified bar.
- Direction: T8 + Q3. Either `NSToolbar` (unified), or a transparent title bar with the header inset
  under the traffic lights. The Frame-mode title-bar hack (`App.swift:1900-1910`) must be re-verified.

**VF-09 · Every command is its own glass pill (26 plates)** · P1 · R+S/H · S03, S04, S09
- Evidence (R): ten tool tiles, each a separate rounded glass plate with its own edge, plus separate
  plates for Hide, Toolbox, Photos, Resize, Save, History, each rail control and each footer action
  (S03-topbar-light, S01-editor-empty-light). S: 26 `GlassSurfaceView`s in 7 containers (child B §4;
  `ModernEditorChrome.swift:263-357`).
- Issue: a busy, beaded top edge. The selection highlight competes with 25 other plate outlines, and
  the bar does not read as one navigation layer.
- Direction: T4 (one plate per group; selection as a fill inside the group), with T6 states.

**VF-10 · The canvas surround is translucent material, not a solid surface; Reduce Transparency has no consumer** · P1 · S/H (R partial) · S01, S07
- Evidence (S): a behind-window `NSVisualEffectView` backdrop fills the whole chrome
  (`ModernEditorChrome.swift:77,238-251`); `scrollView.drawsBackground = false`; glass surfaces never
  read `reduceTransparency` (`GlassChrome.swift:244-401`).
- Evidence (R): the captures show a flat grey well, because an own-window capture has no desktop
  behind it. On a live desktop the well tints with whatever is behind the window. **U** for the live
  look: no live-desktop capture was allowed.
- Evidence (R): at maximized, full-screen and 25% sizes, a small canvas floats in a large undifferentiated
  grey field (S11-size-maximized-light, S11-size-fullscreen-dark@dc1eb26, S07-zoom-25-light).
- Direction: T2 `surface.canvasWell` (solid), T4 delete the backdrop and bleed, plus the
  Reduce Transparency plate fallback.

**VF-11 · Readable-type rule: 18 pt used as the default, system-owned text below 18, and names only in tooltips** · P1 · R+S+M/H · S01–S28
- Evidence (S): 124 explicit UI font sites: 0 below 18 pt, 42 at exactly 18 (33 on the
  Modern/shared path, e.g. zoom popup, "Original size", status, dragSizeLabel,
  `App+ModernChrome.swift:54-87`). 19 AppKit-owned text surfaces are unsized (child B §1).
- Evidence (R): the Screen Recording alert puts a five-line instruction in the bold system message
  text, about 13 pt (S16-permission-alert-light). The footer status runs at 18 pt
  (S01-editor-empty-light).
- Evidence (M, `metrics/text-size-summary.md`, `b9319c4` trees): **37 distinct visible controls under 18 pt,
  all system-owned** (window titles and traffic lights 13 pt, NSAlert text 13 pt, About version 10 pt
  and credits 12 pt, Color/Fonts panel labels 11 pt); **45 distinct controls at 18–19.9 pt, essentially
  all app UI** (zoom, status, size label, Original size, sheet and History labels), each mapped to its
  `file:line`. One reading is a walker artifact: the format popup's internal `NSButtonTextField` reports
  13 pt while the rendered face is visibly about 20 pt.
- Evidence (S): the 25 icon-only commands have no visible name except the native tooltip, whose font
  the app cannot size (`ModernEditorChrome.swift:92-112,276-290`).
- **N-exceptions needing an owner decision:** menu-bar menus, tooltips, NSAlert message and
  informative text, NSSavePanel/NSOpenPanel chrome, the Fonts and Colors panels, and the standard
  About panel. All are system-rendered at about 11–14 pt. Options: (a) accept them as platform text
  outside the rule; (b) replace with app-owned equivalents (custom alert sheets, a custom About
  window, an 18-pt hover label) where the app controls rendering.
- Direction: T1 (move `body` to 20; `caption` is the only 18) + decision D-TEXT.

**VF-12 · No design tokens: 10 corner radii, about 100 magic constants, 3 font floors, 5 dead metrics** · P1 · S/H · all
- Evidence: `GlassChrome.swift:406-426`, `ModernEditorChrome.swift:219-220`; child B §3.
- Issue (R corollary): unequal visual rhythm. The square swatch inside a rounded plate, the
  grey-filled native zoom popup next to capsule glass controls, and mixed plate heights in the footer
  are all visible in S01-editor-empty-light.
- Direction: T1–T3 (`DesignTokens.swift`) + source gates.

**VF-13 · State model gaps and weak selection cues** · P1 · R+S/H · S04, S06, S09, S20
- Evidence (R): the selected tool is a solid accent tile with a black glyph; other tiles differ only by
  glyph weight. The disabled Wipe is a very light grey glyph (S01-editor-empty-light). The vertical
  size slider shows a knob on dotted ticks with no value read-out (S06-size-mid-light). The hover tint
  on neutral glass is not visibly different from rest (S04-tool-hover-dark), and hovering Snap is
  indistinguishable from rest (S04-snap-hover-light). The keyboard focus ring on Snap is a faint yellow
  glow around a yellow plate (S28-focus-rail-snap-light). Disabled controls only fade, with no reason
  given (S04-controls-disabled-light).
- Evidence (S): slider, swatch, History tile, drag well and the footer toggle lack some or all of
  hover/pressed/disabled/focus (child B §8). Differentiate Without Color is never read. `onAccent`
  contrast is computed against the opaque accent while the plate is tinted at 0.85
  (`GlassChrome.swift:179,324`).
- Direction: T6 `StateStyles` + `CommandButton`; T2 `text.onAccent` computed from the blended fill.

**VF-14 · Keyboard and assistive access gaps** · P1 · S/H (AX dumps captured in `evidence/…/ax/`, not yet analysed) · S09, S28, S19, S17
- Evidence (S): the drag well is neither keyboard- nor AX-operable, and its AX label is "Drag Me"
  (`App.swift:50-148,886`). There is no key-view loop on the main window. The Destinations sheet has
  no Return/Escape (`PublishingDestinationsView.swift:36-40,221-224`); Preferences has no Escape. The
  hint bevel, flash and countdown ignore Reduce Motion (`OriginalHelpBevel.swift:255-279`).
- Direction: T7.

**VF-15 · The canvas border's accent outline and corner handles are always on** · P2 · R/H · S01, S02, S07, S12
- Evidence (R): a 1-pt accent (yellow) outline with four square handles surrounds the document at rest
  (S01-editor-empty-light, S02-populated-light).
- Issue: a saturated frame competes with the content and duplicates the selection colour.
- Direction: T6 (rest state = `separator` hairline; handles appear on hover or with the crop tool).
  Keep the gestures (`CanvasBorderView.swift`).

### Surfaces (P1/P2)

**VF-16 · Capture permission UX is a raw alert** · P1 · R+S/H · S16
- Evidence (R): one long bold sentence that says "this app" instead of naming the app, OK only, no
  "Open System Settings" (S16-permission-alert-light). S: `Capture.swift:685-687` → `App.swift:1271`.
- Direction: T10. A short message + informative text + an "Open Privacy Settings" button (deep link to
  the Screen Recording pane) + Cancel.

**VF-17 · Upload feedback is one truncating status string** · P1 · R+S/H · S21, S09
- Evidence (S): `App.swift:1795-1812` (`4b2ae0f`): "Uploading <name>…", "Link copied: <full URL>", or an
  `NSAlert` on error. No progress indicator, no success/error styling.
- Evidence (R): success reads "Link copied: https://cdn.example.com/pics/Upload-demo-ceaa0d1b-…" cut off
  mid-URL (S21-publish-success-footer-light). Progress is only the text "Uploading …"
  (S21-publish-progress-footer-light).
- Direction: T9/T11. A determinate/indeterminate progress capsule on the Upload control; success
  "Link copied" with an Open/Copy affordance; errors announced and prefixed (T7).

**VF-18 · The Preferences window is Classic-era in structure and copy** · P1 · R/H · S17, S18
- Evidence (R): title "Preferences" (macOS 13+ uses "Settings"); an `NSTabView` box with segmented tabs
  General/Drawing/Snapping; a "Done" button (settings apply live); "Sharing Settings..." with ASCII
  dots; checkboxes left-aligned at a different x than the right-aligned radio label column; sound,
  tool-tip-overlay and keyboard-tip-overlay rows (S17-preferences-general-light).
- Evidence (R) at `dc1eb26`: with the Classic and Sounds rows removed, the General pane holds two
  checkboxes and one radio row inside a large, more than half-empty tab box, with Done and
  "Sharing Settings..." (S17-preferences-general-dark@dc1eb26).
- Direction: T8/T11. A Settings window (toolbar tabs, no Done, Escape closes), with the WP2 removals
  and one aligned form grid sized to its content.

**VF-19 · The Destinations sheet is oversized, has no keyboard defaults, and ships owner-specific example values** · P1 · R+S/H · S19
- Evidence (S): fixed 820 × 860 (`Publishing.swift:909`); the placeholders are
  "shoemoney.com (from ~/.ssh/config)" and "/var/www/shoemoney.com/shared/imgs"
  (`PublishingDestinationsView.swift:214-215`); no Return/Escape.
- Evidence (R): Cancel, Save and Test sit small and left-aligned with no default (Return) button; a label
  wraps ("Endpoint (blank = AWS)"); about a quarter of the sheet is empty below the buttons
  (S19-destinations-edit-form-light). The empty state is mostly blank (S19-destinations-empty-*).
- Issue: a generic app shows the owner's server paths, and the sheet does not fit a 13" display
  without scrolling.
- Direction: T11 (generic `example.com` placeholders, a scrolling form, 720 × ≤ visible height,
  keyboard defaults).

**VF-20 · The History window is form-first, not content-first** · P1 · R/H · S20
- Evidence (R): in the empty state a large blank box holds a one-line "No history items match these
  filters." below it; a field list of em-dashes; seven disabled buttons in two rows; a "Drag from
  History format" popup; tabs "All / Posted to Web / Saved/DragMe'd / Archived"
  (S20-history-empty-light). S: minimum 1120 × 850 (`HistoryBrowser.swift:96`).
- Evidence (R): when populated, History shows one thumbnail per row, leaving most of the width empty
  (S20-history-populated-*).
- Direction: T11. A grid with a centred empty state, actions in a toolbar or context menu, a
  collapsible details panel, minimum ≤ 880 × 600, and plain tab names.

**VF-21 · Main window state is not remembered** · P2 · R+S/H · S11
- Evidence (S): no frame autosave, `representedURL` or `collectionBehavior`; `window.center()` on every
  launch (`App.swift:368,716-718` at `4b2ae0f`).
- Evidence (R): full screen **does** work through the default eligibility (`toggleFullScreen`,
  S11-size-fullscreen-dark@dc1eb26). Frame mode in full screen is still undefined (decision Q4).
- Direction: T8 + Q4.

**VF-22 · There is no visible Actual Size control in Modern** · P2 · S/M · S07
- Evidence (S): the Actual toggle is Classic-only (child B §11 S07/S31). Modern exposes it only through
  the menu.
- Direction: T15/T9. T15's bottom-bar budget has no room for another 48-pt button at 980 while "Original size" is visible (21-pt slack). So add **Actual Size as an item in the Zoom popup's menu** (with its menu-bar shortcut). That costs no width and is discoverable where zoom lives.

**VF-23 · Copy and glyph defects** · P2 · S/H · S30, S23, S17
- Evidence: "45º" uses the ordinal º (`OriginalHintMessages.swift:59-60`); the Apple logo U+F8FF
  stands in for Command (`:87`); the Toolbox menu uses ASCII `...` (`App.swift:682-683`); "Sharing
  Settings..." (R, S17). Hint copy is the original lowercase Skitch voice.
- Direction: T12 / WP6.

**VF-24 · The dev bundle keeps stale resources** · P2 · M/H · build
- Evidence (M): `build/OpenSkitch.app/Contents/Resources/SkitchMac.icns` is present but nothing copies
  it; `tools/build.sh:6` never cleans. Releases clean (`release.sh:28-29`).
- Issue: dev screenshots and visual gates can show assets the release lacks.
- Direction: OSN-010 (WP3): clean the bundle in `build.sh`, or make the visual gate build from a clean
  stage.

**VF-25 · Mixed icon families within one bar** · P1 · R+S/H · S09
- Evidence (S): Upload is always the SF Symbol `icloud.and.arrow.up` (`ModernEditorChrome.swift:113-119`),
  and the drag well uses an SF hand (`App.swift:71-82`), next to FA glyphs. R: the footer cloud and hand
  glyphs differ in stroke weight from the FA tools (S01-editor-empty-light).
- Evidence (R) at `dc1eb26`: the drag-thumbnail expand badge is a generic SF double-arrow glyph on a dark
  disc (S29-drag-thumbnail-expand-light@dc1eb26), not a Font Awesome semantic glyph.
- Direction: T5.

**VF-26 · The status line truncates its most important messages** · P1 · R+M/H · S09, S12, S21
- Evidence (M, `layout-width-budget.json` at `dc1eb26`, 18 pt): "Frame: position the window, then Snap" needs
  314 pt but gets 193 pt at 980 and 237 pt at 1024. "Link copied: https://cdn.example.com/…" needs
  581 pt. "Brush · Unsaved changes" needs 208 pt and gets 193 pt at 980 even in normal mode.
- Evidence (R): "Frame: position the w…" (S12-frame-w980-light@dc1eb26); a truncated link
  (S21-publish-success-footer-light).
- Issue: the Frame instruction and the upload result are exactly what the user needs to read, and they
  are cut off at ordinary window widths. T15 frees width at the top, but the bottom bar gains groups.
- Direction: T15 (merged status) + T9/T11. Short status copy ("Position the frame, then Snap"), the full
  URL only in the tooltip/AX value with a Copy/Open affordance, and a measured status floor at 980 in
  both modes. Acceptance: the Frame hint is fully visible at 1024 or wider, and at 980 its truncation
  keeps the verb.

**VF-27 · In Frame mode an overlay scroller is visible inside the capture hole** · P1 (if captured) · R/U · S12
- Evidence (R): at 980 with a 2000 × 1400 document, a dark horizontal scroller is drawn along the bottom
  of the Frame hole (S12-frame-w980-light@dc1eb26).
- **U:** whether the scroller ends up in the snapped image. The Frame capture reads screen pixels under
  `canvas.visibleRect` (`App.swift:1951-1962` at `4b2ae0f`); live capture was not allowed.
- Direction: verify with a live capture once Screen Recording is granted. If it is captured, hide the
  scrollers while in Frame mode and while snapping. Tracked as OSN-014.

**VF-28 · The highlighter stroke starts with a darker cap** · P2 · R/M · S02
- Evidence (R): the highlighter's first cap renders olive/grey against the pale-yellow body
  (S02-populated-light, S02-populated-light@dc1eb26).
- Issue: annotation content looks wrong at the start of every highlighter stroke (an overlapping-alpha
  or round-cap compositing artifact).
- Direction: Canvas stroke rendering for the highlighter: draw the stroke once into a transparency layer
  and composite it at its alpha. Content code, not chrome; tracked as OSN-057.

**VF-29 · The Resize panel shows fractional pixel sizes** · P2 · R/H · S08
- Evidence (R): width reads "1516.5" (S08-resize-panel-*).
- Direction: round to whole pixels in display (keep internal precision); tracked as OSN-058.


## 7. Reconciliation with the declassic plan (`build/declassic-plan.md`) and with `main`

| WP | Plan | State at `dc1eb26` | Backlog todo |
|---|---|---|---|
| WP0 land the toggle | first | **Done** (`88d8865`/`f19dfde`/`4b2ae0f`) | – |
| WP1 own assets | wave 1 | **Landed (S)** (`fc77158`, `691b890`, `12c6dfa`) | OSN-021: verify only |
| WP2 Classic removal + macOS 26 | wave 1 | **Landed (S)** (`42c52d8`, `6acc21c`) | OSN-022/OSN-023: verify only |
| WP3 build/runners/gates | wave 1 | **Landed (S)** (`6acc21c`, `1b065b6`, `dc1eb26`) | OSN-020: verify (clean-clone build) |
| WP4 rename + migration | wave 2 | **In flight** on `opensnap/w3-rename` | OSN-030/OSN-031 |
| WP5 own welcome doc | wave 2 | **Cancelled** by owner D5. The synthetic-fixture half is still open (5 tests reference `original/`). | OSN-024 |
| WP6 copy/docs/analysis | wave 2 | **Landed in part** (`69fa060`): hint copy rewritten, `analysis/` untracked. Toolbox `...`, Destinations placeholders and History tab names remain. | OSN-032 (residuals) |
| WP7 integration + 0.4.0 | wave 3 | Not started | OSN-072 |

- The plan's line numbers drifted by +6 to +34 in `App.swift` after the toggle merge, and Classic-era
  lines were deleted at `dc1eb26`. Six claims were wrong even at `b9319c4` (`source-inventory.md` §6.4).
- **Foundation blockers still open:** WP4 (identity + `.opensnap` + migration), synthetic fixtures
  (OSN-024), the safe screenshot path (OSN-001), and the owner decisions (OSN-002). Broad visual
  polish (T1–T12) waits for WP4 so each line is edited once.
- **Owner-priority layout (T15) re-sequenced.** T15's "land before WP1/WP2" no longer applies: those
  landed first. T15's Modern-only files (`ModernEditorChrome.swift`, `BezelDrawingControls.swift`,
  `GlassChrome.swift` Metrics, the Modern test cases) can start **now** on top of `dc1eb26`. Its five
  `App.swift` hunks (and `App+ModernChrome.swift`, which WP4 also renames) wait until WP4 merges, then
  take the next App.swift-lane slot.

## 8. Owner-required layout: remove the right rail

Full spec: `technical-spec.md` T15 (child B round 2, Sonnet 5.5, `4b2ae0f` line numbers). Opus
re-added the top-bar sums independently, and they hold: normal 168 + 56 + 476 + 156 + 36 = 892; Frame
+54 = 946; 956 pt usable at the 980 minimum.

**Live validation (M, `layout-width-budget.json` at `dc1eb26`, harness-only PROTO mock, NOT product):**
the mock re-parented the real controls into the recommended mapping. Measured top-row groups: leading 168,
capture 56 (Frame 110), tools 476 (at 44 pt), gaps 12. These match T15's arithmetic exactly. The mock's
annotation group measured 228 instead of 156 only because its stroke control was a placeholder 120-pt
horizontal slider, not the specified 48-pt pill. So the mock row needed 964 (Frame 1018) and the window
grew to 988 (Frame 1042) (PROTO-w980-normal-light@dc1eb26, PROTO-w980-frame-light@dc1eb26). With the 48-pt
pill, the row is **892 normal / 946 Frame against 956 usable at 980: slack 64 / 10**. The mock's bottom
row (zoom not yet trimmed, Original size and size label hidden) measured 740.5 excluding status, leaving
223 pt for status at 980. The measured PNG|JPG group is 265 (toggle about 157, wider than T15's
143 estimate). Trimming the zoom face (≈ −57) and showing "Original size" (≈ +150) leaves ≈ 130 pt for
status, above T15's 120-pt floor. So the long Frame hint must be shortened (VF-26). **Result:** the
mapping fits at 980 in both modes with the three fit levers. The fallbacks are not needed on current
evidence. Re-measure after implementation (OSN-013).

**Recommended mapping.** Capture and annotation go on top; document, view and output go on the bottom.

| Current rail control | Destination | Position |
|---|---|---|
| Snap / Snap Frame (primary; right-click Fullscreen alternate) | Top bar | capture group, after `[Hide][Toolbox][Photos]`, before the tools |
| Cancel (Frame mode only) | Top bar | beside Snap Frame, same group (appears only in Frame mode) |
| Color (swatch; Shift = canvas background) | Top bar | annotation group after the tools: `[Color][Size][Font]` |
| Stroke size (vertical 36 × 96 slider) | Top bar | **48 × 36 size pill** (draws the current width) → popover on a solid surface with a horizontal slider, five presets and a 20-pt read-out |
| Font | Top bar | annotation group |
| Undo | Bottom bar | leading edit group `[Undo][Wipe]` |
| Wipe (Blank / Clear / Wipe retitles) | Bottom bar | leading edit group |
| *(non-rail)* Resize… | Bottom bar | view group `[Zoom][Resize…]` (it is an image/view command, so it moves out of the tool row) |
| *(non-rail)* Save to History, History | Bottom bar | archive group, before the export group |
| *(non-rail)* dragSizeLabel | merged | into the status text ("800 × 600 · 10 KB · Arrow · Saved") |

**Fit levers** (needed at 980): tool tile 48 → 44 pt wide; zoom popup face shows the percentage only
(160 → ≈ 108); the merged status label truncates at a 120-pt floor. **Ordered fallbacks** if live
widths overflow: "Original size" becomes a 48-pt icon toggle → Cancel takes Photos' slot in Frame
mode → Hide moves into the Toolbox menu → the minimum width rises to 1024.

**Canvas gain:** +72 pt width (+8.1% at 980, +7.8% at 1024, +6.1% at 1280, +5.4% at 1440); height
unchanged. The Frame hole is the scroll-view frame (`App.swift:16-23`), so it grows with the viewport
automatically. `CenteringClipView` and `CanvasBorderView` are rail-agnostic.

**Owner decisions raised by T15** (added to OSN-002): D-T15-1 the zoom face shows the percentage only;
D-T15-2 size-pill arrow keys follow `NSSlider` (Right/Up = larger); D-T15-3 tool tiles become 44 pt
wide. Also accepted: the tool row is centred **between its neighbours**, not on the window, because
the capture group makes the row asymmetric. It sits about 40 pt right of centre at 1440 and shifts
27 pt when Cancel appears.

**Order:** T15 lands **before** the declassic WPs (Modern-only files plus an additive slider style;
`App.swift` gets 5 small hunks). The cost is that WP1/WP2 rebase over a rewritten `build()` region of
about 170 lines. Estimate about 4 d including tests.

**Rejected alternative:** Undo/Wipe top-trailing with Color/Size/Font bottom-leading. The top fits, but
the bottom overflows at 980 whenever "Original size" is visible, and the pen attributes end up a canvas
height away from the tools.

**Visual acceptance (owner checklist, from `user-feedback.md` + T15 j):** captures in light and dark
at 980/1024/1280/1440 and full screen; empty and populated; selection and text editing; Frame mode
(Cancel visible, hole aligned to the viewport); size popover open; PNG and JPG states. Each must
show: no rail and no blank column; the canvas runs to trailing −12 and is centred when smaller than
the viewport; no clipped or overlapping control at 980 in either mode; all text ≥ 18 pt (20 default);
every former rail action reachable, with its tooltip, AX label and shortcut unchanged.

## 9. Backlog skeleton (for the roadmap/checklist/JSON)

Status of every todo: **pending** (new todos, as briefed). `main state` records what the Opus re-check
found on `main` at `dc1eb26`. A "landed (S)" todo still needs its visual check and gate before it is
closed. IDs are stable; do not renumber (the numbering has deliberate gaps). **Lane A** marks todos
that edit `Sources/App.swift` (serial: one implementer at a time, in the order below).

| Milestone | Purpose | Entry | Exit |
|---|---|---|---|
| **M0** Baseline, safety, decisions | Make the visual gate safe; record the owner decisions everything else needs | This audit committed | OSN-001 merged; OSN-002 decisions answered; the baseline gallery reproducible from the harness |
| **M1** Owner layout (rail removal) | The owner's P1 request | M0 OSN-001 (for evidence) + D-T15-1..3. App.swift hunks also need WP4 (OSN-030) merged | T15 acceptance checklist passes at 980/1024/1280/1440 + full screen, light/dark, normal/Frame |
| **M2** Foundation: declassic + clean build | Remove Classic and every original asset; buildable from a clean clone | M0 (mostly landed at `dc1eb26`) | Clean clone builds and tests with `original/` absent; `check-no-original` green; no test references `original/` |
| **M3** Identity + migration | OpenSnap ids, `.opensnap`, copy-never-move migration, OpenSnap copy | M2; Q2 | Migration tests green; `check-skitch-strings` green; old store hash unchanged |
| **M4** Design-system foundation | Tokens, glass consolidation, window chrome, states, icons | M3 (string-bearing files) + M1 (chrome layout) + Q1/Q3/Q4 | Token gates, glass depth/budget and the font-floor walker green |
| **M5** Surface polish | Capture, Settings, Destinations, History, upload feedback, menus/About/status, hints | M4 | Per-surface visual checklists pass |
| **M6** Accessibility + adaptivity | Keyboard, display options, VoiceOver | M4 (parallel with M5 where files are disjoint) | T7 tests green; injected-DisplayOptions captures reviewed; manual VoiceOver pass recorded |
| **M7** Visual acceptance + release readiness | Gates, full gallery, migration on a copy of real data, clean-clone release dry run | M1–M6 | Opus visual sign-off; all gates green |

| ID | P | M | Title | Findings | Spec | Depends on | Lane A | main state (`dc1eb26`) |
|---|---|---|---|---|---|---|---|---|
| OSN-001 | P0 | M0 | Adopt the safe audit harness as the only screenshot path (isolated bundle id + throwaway defaults, synthetic fixture, before/after real-store hashes, FA and SF icon modes, metrics/AX dumps with **secure-field values redacted**); retire the unsafe `tools/eye-dump.sh` path | VF-06, VF-05, VF-24 | T14 | – | yes (flag hook) | open (harness on unmerged `audit/visual-harness`) |
| OSN-002 | P0 | M0 | Owner decisions: Q1 FA in release, Q2 `.opensnap` container, Q3 NSToolbar vs custom bars, Q4 full screen vs Frame, Q5 flash, D-TEXT native-text exceptions + tooltip-only names, D-HINT hint-bevel fate, D-T15-1..3 (zoom face, size-pill arrow direction, 44-pt tool tiles) | VF-05, VF-11, VF-08, VF-21, VF-07 | §0, T15 k | – | no | open |
| OSN-010 | P1 | M1 | Remove the right rail; relocate Snap/Snap Frame, Cancel, Color, Font, stroke width, Undo, Wipe per the T15 mapping (§8); 44-pt tool tiles; zoom face trimmed; dragSizeLabel merged into status; shorter Frame hint; Actual Size added to the Zoom menu; the canvas reclaims 72 pt | VF-07, VF-22, VF-26 | T15 | OSN-001, OSN-002 (D-T15-1..3); App.swift hunks after OSN-030 | yes (5 small hunks) | open |
| OSN-011 | P1 | M1 | Stroke width: a 48 × 36 size pill + popover on a solid surface replaces the vertical rail slider (undo grouping, Shift, stepping, AX value, popover dismissed on hide/quit) | VF-07, VF-13 | T15 d | OSN-010 | yes (`dismissPopover` + popover edge) | open |
| OSN-012 | P1 | M1 | Can-fail layout regression tests for the rail removal (no rail, fit at 980 in both modes, centring, Frame rect = viewport, one undo per width drag) | VF-07 | T15 h | OSN-010, OSN-011 | no | open |
| OSN-013 | P1 | M1 | Rail-removal visual acceptance capture set + Opus review | VF-07 | T15 j, §8 | OSN-012 | no | open |
| OSN-014 | P1 | M1 | Frame mode: verify with a live capture whether overlay scrollers enter the snapped image; if so, hide scrollers in Frame mode and during the snap (needs the owner's Screen Recording grant for the verification) | VF-27 | T15 e | OSN-010 | yes (`enterFrame`/`performFrameSnap`) | open (U) |
| OSN-020 | P0 | M2 | WP3 build/runners/gates: clean-clone build, macOS 26 target, single app-safety run, `check-no-original`, `check-skitch-strings`, clean bundle per build | VF-01, VF-24 | T13, T14 | OSN-001 | no | landed (S), except the `check-skitch-strings` gate (not found); verify with a clean-clone build |
| OSN-021 | P0 | M2 | WP1 own assets in shared code: drawn countdown digits, system hand cursors, sounds + sound pref deleted, `ToolButton` + PNG fallback chain + slider `.classic` deleted | VF-02 | T13, T5 | OSN-020 | yes | landed (S); verify visually (countdown, cursors) |
| OSN-022 | P0 | M2 | WP2 remove Classic: Appearance enum/pref/Relaunch, Classic window branch, Frame bezel art, welcome document (blank first launch), macOS 26 minimum | VF-04, VF-02 | T13 | OSN-021 | yes | landed (S); verify visually (Preferences, first launch) |
| OSN-023 | P0 | M2 | Own drawings for the status-item template icon and the drag-thumbnail overlays | VF-02 | T5 §4–5 | OSN-022 | yes | landed (S) as SF template/badges (allowed by owner D5); verify visually |
| OSN-024 | P0 | M2 | Synthetic test fixtures; delete every `original/` probe (incl. `AppSafetyTests.swift:493,552` at `4b2ae0f`) | VF-01 | T13, T14 | OSN-020 | no | open: 5 test files still reference `original/` |
| OSN-030 | P0 | M3 | WP4 OpenSnap rename + `.opensnap` + copy-never-move migration (bundle id, App Support, Keychain service, `OPENSNAP_*`, UTIs); migration tests with an injected defaults suite + temp support dir (`CFFIXED_USER_HOME` alone does not isolate defaults, VF-06) | VF-03 | T13 | OSN-022, OSN-024, OSN-002 (Q2) | yes | in flight (`opensnap/w3-rename`) |
| OSN-031 | P0 | M3 | All user-visible strings → OpenSnap (29 "Skitch" literals + "OpenSkitch" title/menu/About at `dc1eb26`), export/History format names | VF-03 | T12 | OSN-030 | yes | in flight (`opensnap/w3-rename`) |
| OSN-032 | P1 | M3 | WP6 residual copy: Toolbox `…`, generic Destinations placeholders, History tab names, any remaining original-voice copy | VF-23, VF-19 | T12, T13 | OSN-031 | yes | partly landed (hint copy done) |
| OSN-040 | P1 | M4 | `DesignTokens.swift` (Typography, Space, Radius, Size, Palette) + token source gates | VF-12 | T1–T3 | OSN-022 | no | open |
| OSN-041 | P1 | M4 | Type sweep: `body` 20, `caption` 18 only; N-exceptions per D-TEXT | VF-11 | T1 | OSN-040, OSN-031, OSN-002 | yes | open |
| OSN-042 | P1 | M4 | Glass consolidation (one plate per group), solid canvas well, backdrop/bleed deleted, Reduce Transparency plates, Increase Contrast borders | VF-09, VF-10 | T4 | OSN-040, OSN-010, OSN-002 (Q3) | yes | open |
| OSN-043 | P1 | M4 | Unified window chrome (title + commands in one bar), frame autosave, `representedURL`, full screen per Q4 | VF-08, VF-21 | T8 | OSN-042 | yes | open |
| OSN-044 | P1 | M4 | Component state model (`StateStyles`, `CommandButton`; slider/pill, swatch, drag well, History tile; computed `onAccent`; canvas border rest state) | VF-13, VF-15 | T6 | OSN-042 | yes | open |
| OSN-045 | P1 | M4 | Iconography: every chrome icon through FA (Upload, drag hand), semantic fallbacks (Wipe ≠ trash), dead FA entries removed, glyph hygiene | VF-05, VF-25 | T5 | OSN-021, OSN-002 (Q1) | yes | open (the PNG tier is gone; the SF-only Upload and the `trash` fallback remain) |
| OSN-050 | P1 | M5 | Capture surfaces: permission sheet with Open Privacy Settings, tokenised picker/magnifier/countdown, flash under Reduce Motion | VF-16 | T10 | OSN-021, OSN-040, OSN-002 (Q5) | yes | open |
| OSN-051 | P1 | M5 | Settings window rebuild (toolbar tabs, no Done, Escape, aligned grid, title "Settings") | VF-18 | T8, T11 | OSN-022, OSN-041 | yes | open (Classic rows already gone) |
| OSN-052 | P1 | M5 | Destinations sheet: scrolling form ≤ visible height, Return/Escape, 20-pt text, generic placeholders | VF-19 | T11 | OSN-032, OSN-041 | no | open |
| OSN-053 | P1 | M5 | History window: content-first grid, centred empty state, toolbar/context actions, min ≤ 880 × 600 | VF-20 | T11 | OSN-041 | no | open |
| OSN-054 | P1 | M5 | Upload progress / success / error presentation + announcements; short success copy with the URL in the tooltip/AX value and a Copy/Open affordance | VF-17, VF-26 | T9, T11 | OSN-010, OSN-044 | yes | open |
| OSN-055 | P2 | M5 | Menus, About, status item polish (copy, symbols, About credits) | VF-23 | T12 | OSN-031, OSN-010 | yes | open |
| OSN-056 | P2 | M5 | Hover-hint bevel per D-HINT (recommended: keep as opt-in, modernise: solid HUD plate, 20 pt, tokens, Reduce Motion) | VF-23, VF-14 | T7, T12 | OSN-032, OSN-002 (D-HINT) | no | open (copy already rewritten) |
| OSN-057 | P2 | M5 | Highlighter stroke: composite each stroke once at its alpha (no darker start cap) | VF-28 | – (Canvas content rendering) | – | no | open |
| OSN-058 | P2 | M5 | Resize panel shows whole-pixel sizes (display rounding; internal precision kept) | VF-29 | T11 | – | no | open |
| OSN-060 | P1 | M6 | Keyboard: key-view loop, operable drag well, visible focus rings, Escape/Return in every sheet | VF-14 | T7 | OSN-044 | yes | open |
| OSN-061 | P1 | M6 | Display-option consumers (Reduce Motion/Transparency, Increase Contrast, Differentiate Without Color) + an injected-`DisplayOptions` capture mode in the harness | VF-10, VF-14 | T7, T14 | OSN-042, OSN-044, OSN-001 | no | open |
| OSN-062 | P1 | M6 | VoiceOver labels, announcements, and a recorded manual VoiceOver pass | VF-14 | T7 | OSN-060 | yes | open |
| OSN-070 | P0 | M7 | Regression gates in `tools/test.py`: font-floor walker, glass depth/budget, no decorative glyphs, no original bytes, no "Skitch" strings, layout fit at 980 | all | T14 | OSN-012, OSN-040 | yes (walker evidence hook) | partly (`check-no-original` exists) |
| OSN-071 | P0 | M7 | Visual acceptance run: full gallery (light/dark × 980/1024/1280/1440/full screen × states × FA/SF icon modes), Opus sign-off | all | T14, T15 j | OSN-070 | no | open |
| OSN-072 | P0 | M7 | WP7: migration verified on a COPY of the owner's real store (source hash unchanged), clean-clone build/test/release dry run | VF-01, VF-03 | T13 | OSN-030, OSN-070 | no | open |

**Recommended defaults for the owner decisions** (OSN-002; the owner decides):
- **Q1 FA in release:** until the licence question is answered, treat SF Symbols as the release icon
  set and run visual acceptance in SF mode (FA mode is dev-only and captured for comparison). If the
  licence allows compiled vector outlines, ship FA as generated vector paths (spec Q1a).
- **D-TEXT:** accept system-rendered menus, tooltips, Save/Open panels and the Fonts/Colors panels as
  platform text outside the 18-pt rule. App-specific alerts (permission, upload errors) become
  app-owned sheets at 20 pt. The About credits are set as an 18-pt attributed string.
- **D-HINT:** keep the hover-hint bevel as an opt-in (off by default, as today), modernised.
- **D-T15-1..3:** accept (zoom face shows the percentage only; arrow keys follow `NSSlider`; 44-pt tool
  tiles). Without them, T15 does not fit at 980 in Frame mode.
- **Q2–Q5:** as recommended in `technical-spec.md` §0.

**Lane A serial order (App.swift):** OSN-030 → OSN-031 (WP4, in flight) → OSN-001 hook → OSN-010 →
OSN-011 → OSN-014 → OSN-032 → OSN-041 → OSN-042 → OSN-043 → OSN-044 → OSN-045 → OSN-050 → OSN-051 →
OSN-054 → OSN-055 → OSN-060 → OSN-062 → OSN-070 hook. OSN-021/022/023 have already landed. The
non-App.swift parts of OSN-010/011 (`ModernEditorChrome.swift`, `BezelDrawingControls.swift`,
`GlassChrome.swift` Metrics) may start before WP4 merges.

## 10. Provenance

Orchestrator and reviewer: Opus 5.5 (`claude-opus-5-5`). Opus wrote this file, verified the children's claims against source and captures, re-added the T15 sums, and recomputed the safety hashes (both unchanged at 11:45 CDT).

| Child | taskId | Model requested | Model confirmed |
|---|---|---|---|
| A: rendered evidence harness + captures (steered 3× in-flight: snapshot drift/rail budget, sheet re-shoots, `dc1eb26` delta) | `node:delegated-task:command%3Amcp%3A1178d98b-013f-4766-81ad-b245923f6479%3Adelegate-task%3Aopensnap-visual-audit-20261009-A-evidence-r1` | `claude-sonnet-5-5` | `claude-sonnet-5-5` (task status + self-report); harness branch `audit/visual-harness` @ `6ed6828`, unmerged |
| B: source inventory + technical spec (round 1) | `node:delegated-task:command%3Amcp%3A1178d98b-013f-4766-81ad-b245923f6479%3Adelegate-task%3Aopensnap-visual-audit-20261009-B-source-r1` | `claude-sonnet-5-5` | `claude-sonnet-5-5` (task status + self-report) |
| B: T15 rail removal (round 2) | `node:delegated-task:command%3Amcp%3A1178d98b-013f-4766-81ad-b245923f6479%3Adelegate-task%3Aopensnap-visual-audit-20261009-B-source-r2-rail` | `claude-sonnet-5-5` | `claude-sonnet-5-5` (task status + self-report) |
| C: roadmap/checklist/backlog/README (round 1) | `node:delegated-task:command%3Amcp%3A1178d98b-013f-4766-81ad-b245923f6479%3Adelegate-task%3Aopensnap-visual-audit-20261009-C-docs-r1` | `claude-haiku-5-5` | `claude-haiku-5-5` (task status; self-report from the session model note) |
| C: docs regenerated from the final audit (round 2) | `node:delegated-task:command%3Amcp%3Acf19f696-6f7b-41a0-a97c-2a38c85bc6c1%3Adelegate-task%3Aopensnap-visual-audit-20261009-C-docs-r2-final` | `claude-haiku-5-5` | `claude-haiku-5-5` (task status + self-report). Opus then aligned the §0 evidence-class summary with the §6 headers, removed the now-stale mismatch note from the child's generator, re-ran `gen2.py`/`gen3.py`/`check.py` (0 failures), and ran an independent cross-check (0 errors) |
