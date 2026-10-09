# OpenSnap — technical implementation spec for the visual/cosmetic overhaul

**SOURCE-INFERRED, main @ 4b2ae0f.** Evidence is in `docs/design/source-inventory.md` (cited as **INV §n**) and
`docs/design/evidence/source-font-sizes.json` (**FONTS**). Nothing here is a rendered observation; every target value is a
proposal to be confirmed by screenshots/`eye-dump` after implementation. Line numbers are `4b2ae0f`.

> **SNAPSHOT DRIFT.** The audit was *briefed* at `b9319c4`. The PNG | JPG footer toggle then landed (`88d8865`, `f19dfde`, `4b2ae0f`), so
> **every `file:line` in this spec and in `source-inventory.md` is `4b2ae0f`**, not `b9319c4` (lines in `App.swift` after ~L130 moved by +6…+34).
> The rendered evidence captures are **not** necessarily at `4b2ae0f`: each is pinned to its own `sourceSha` in
> `docs/design/evidence/2026-10-09/manifest.json`. Before comparing a capture with a line cited here, read that capture's `sourceSha`
> (`git diff <sourceSha> 4b2ae0f -- <file>`) and treat a mismatch as unverified. Width figures marked **ESTIMATE** are derived from
> source metrics plus typographic estimates and are superseded by `docs/design/evidence/2026-10-09/layout-width-budget.json` once it exists.
> **Owner requirement of 2026-10-09 10:24 CDT (P1):** the permanent right rail is removed — see **T15**, which supersedes every rail
> statement elsewhere in this document.

**Scope guard.** No Classic fidelity revival. Owner rules in force: readable UI text ≥ 18 pt (default 20 pt) in native points; real Font
Awesome Pro semantic icons (arrow *tool* stays); disciplined single-level glass **navigation** layer, solid readable **content**
surfaces, tokenised type/spacing/corners/colors, semantic selected/hover/pressed/disabled/focus states, content first, no decoration.
Owner decisions of 2026-10-09 (declassic-plan §4) override its defaults: **OpenSnap**, `com.shoemoney.opensnap`, App Support
`OpenSnap`, Keychain `OpenSnap.Publishing`, `OPENSNAP_*`, macOS 26.0, native `.opensnap` (UTI `com.shoemoney.opensnap.document`),
migration-only legacy reader, **silent + minimal** (no sounds, no sound pref, drawn countdown digits, no welcome doc, own minimal
cursor/menu-bar drawings), copy-never-move migration, no history rewrite, repo rename later.

**Estimate unit.** "d" = one Sonnet implementer-day at the pace assumed in `declassic-plan.md §Sizing` (WP2 ≈ 1.5 d). Each estimate
assumes: tests are written with the change, Opus review is separate, and the Classic branch is already gone (otherwise add 30–50 %
for double edits).

---

## 0. Decisions that gate the plan (ask the owner once, up front)

| # | Decision | Why it matters | Recommended |
|---|---|---|---|
| Q1 | **Font Awesome Pro in the shipped app.** `tools/check-no-fonts.py` forbids shipping the fonts, so a released build always runs the **SF Symbol** fallback (INV §5.2). "Real FA Pro icons everywhere" is only true on machines with the licensed subset. | T5 can't satisfy the rule in a release without a licence ruling. | Either (a) get FA's licence read: if embedding glyph *outlines* as compiled vector assets is allowed, generate `IconPaths.swift` (CGPath data, not font files) from the subset at build time and ship that; or (b) accept SF Symbols in release and say so. Until then T5 builds on the `ChromeIcons` seam so both work. |
| Q2 | **`.opensnap` container.** Today's "native" file is the Skitch-compatible SVG (`SkitchFile`, `.skitch`) plus an internal JSON (`SketchDocument`, `.skitchredux`, id `com.skitch-redux.editable-document`, INV §13). | WP4 needs a format before it can write History/recovery/save. | Rename the JSON `SketchDocument` encoding (`DocumentModel.swift:185-186`) to the `.opensnap` format (id `com.shoemoney.opensnap.document`, version 1); SVG stays an **export**; the old SVG-Skitch and JSON readers move to `Sources/Migration/` and are not reachable from Open/drag/import. Needs a 1-page ADR (`docs/adr/0002`). |
| Q3 | **Top-bar implementation only: custom glass bars vs a real `NSToolbar`.** (The right rail is **not** part of this question: the owner has required its removal, T15, and that relocation lands inside the current `ModernEditorChrome` custom bars **without waiting on Q3**.) | A system toolbar gets single-level glass, Reduce-Transparency/Increase-Contrast handling and Full Keyboard Access for free; the custom bars are ≈ 26 hand-managed glass surfaces. A toolbar would also have to carry T15's 16 top-bar items (Hide, Toolbox, Photos, Snap, Cancel, 10 tools, Color, Size, Font), where overflow-chevron behaviour at 980 pt is unverified. | Prefer `NSToolbar` for the top bar *after* T15 has landed (tools as an `NSToolbarItemGroup` `.selectOne`, Snap/Cancel/Color/Size/Font as items), and keep the bottom bar custom. If rejected, T4 option B (custom bars, ≤ 5 glass surfaces total) is specified below and needs no further decision. |
| Q4 | **Full screen.** The main window has no `.fullScreenPrimary` (INV §10) and Frame mode relies on screen-saver level + alpha 0.8 (`App.swift:1883-1931`). | Full screen and Frame mode are mutually exclusive. | Enable full screen; disable/exit Frame while full screen. |
| Q5 | **Flash.** The white capture flash (INV §S15) is a photosensitivity risk and the only remaining capture feedback once sound is gone. | T10. | Keep, 0.1 s, but skip the ramp under Reduce Motion and cap peak luminance at 70 % (see T10). |

---

## T1 — Type tokens

**Current state (INV §1, FONTS).** 124 explicit UI font sites, 0 below 18 pt, 42 at exactly 18 pt (33 on the Modern/shared path), 70 at 20, headings
24/26/26/28 via local helpers; floors re-implemented three times (`GlassChrome.swift:58-69`, `ToolButton.swift:21-32`,
`ModernEditorChrome.swift:213-215`); 19 AppKit-owned text surfaces unsized; custom-drawn text (hint bevel, picker/magnifier labels, Drag plate)
invisible to control walkers; `GlassChrome.Metrics.labelPointSize` dead.

**Target spec** — one file, `Sources/DesignTokens.swift`, AppKit-only (no other dependency) so every test suite can compile it:

```swift
enum DesignTokens {
  enum Typography {                       // native points; SF Pro unless noted
    static let readableMinimum: CGFloat = 18, readableDefault: CGFloat = 20
    enum Style { case caption, body, bodyStrong, headline, title, hud, numeric, countdown }
    static func font(_ s: Style) -> NSFont
    //  caption   18 regular     status line, byte counts, helper/secondary text      (the only 18)
    //  body      20 regular     every control, label, field, menu item, table cell    (default)
    //  bodyStrong20 semibold    form field names, selected tab, list group titles
    //  headline  22 semibold    section headings inside a sheet/panel
    //  title     26 semibold    sheet / panel titles (replaces 24, 26, 26, 28)
    //  hud       20 medium      hint bevel, crosshair read-out, magnifier label (on plates)
    //  numeric   18 regular monospacedDigit   dimensions, byte counts (no layout jitter)
    //  countdown 160 heavy rounded           capture countdown numerals (T10)
    static func attributes(_ s: Style, color: NSColor = .labelColor) -> [NSAttributedString.Key: Any]
    static func floored(_ font: NSFont?) -> NSFont          // single replacement for the 3 floors
    static func apply(_ s: Style, to control: NSControl)    // sets control.font AND popup/menu/cell fonts
    static let iconRegular: CGFloat = 22, iconPrimary: CGFloat = 26, iconInline: CGFloat = 20
  }
}
```

Rules: `caption` is the only style allowed at 18; nothing is below `readableMinimum` (assert in `font(_:)` in debug). Controls that today use 18
**move up to `body` (20)**: zoom popup (`App+ModernChrome.swift:72`), Original-size checkbox (`:65`), Color button font (`:54`), all Destinations buttons/captions
(`PublishingDestinationsView.swift:38,64,79,153,176,192,198,218`), Publishing sheet helpers (`Publishing.swift:1068,1076`), History field names and tile labels
(`HistoryBrowser.swift:291,297,314,441,443`), Photos detail/status (`PhotoBrowser.swift:279,373`), Prefs help text (`GeneralPreferencesForm.swift:84`). That leaves ~12
true captions. Status line and drag-size label stay `caption`/`numeric`.

**Substeps**
1. Add `DesignTokens.swift` (no consumers) + `tools/test.py` `suite()` appends it to **every** suite's source list (each suite compiles only its listed sources, `test.py:~70-80, 93-131`) — otherwise any file adopting tokens breaks its own suite.
2. Replace the three floors with `Typography.floored`; keep `GlassChromeButton.font` override calling it.
3. Mechanical sweep, file by file, in the order in the ownership map (§O): replace `NSFont.systemFont(ofSize: N…)`/`Self.font(N)`/`label(size:)` with `Typography.font(.style)`; custom-drawn text (`OriginalHelpBevel.swift:32,57-60`, `OriginalCapturePicker.swift:440`, `OriginalCaptureMagnifier.swift:70`, `CanvasNavigator.swift:156`) use `Typography.attributes`.
4. System-owned text: replace `orderFrontStandardAboutPanel` credits with a 18 pt `NSAttributedString` (T12); route every `NSAlert` through one `Alert.make(...)` helper that sets `informativeText` via an 18–20 pt accessory-free attributed text where possible and 20 pt accessory fields; replace NSSavePanel/NSOpenPanel only where we own an accessory (already 20 pt).
5. Delete the dead metric (`GlassChrome.Metrics.labelPointSize`, `labeledIconPointSize`).

**Files touched.** New: `DesignTokens.swift`. Edited (all mechanical): `App.swift`, `App+ModernChrome.swift`, `GlassChrome.swift`, `ModernEditorChrome.swift`, `ExportAccessory.swift`, `GeneralPreferencesForm.swift`, `GlobalHotkeys.swift`, `HistoryBrowser.swift`, `PhotoBrowser.swift`, `Publishing.swift`, `PublishingDestinationsView.swift`, `ResizePanel.swift`, `TextStyleForm.swift`, `OriginalHelpBevel.swift`, `OriginalCapturePicker.swift`, `OriginalCaptureMagnifier.swift`, `CanvasNavigator.swift`, `BezelDrawingControls.swift`, `Canvas.swift` (menus only), `tools/test.py`.

**Ownership/parallelism.** `App.swift` is serial (also WP2/WP4/T3/T8/T9/T10/T12). Everything except `App.swift`, `Canvas.swift`, `GlassChrome.swift`, `ModernEditorChrome.swift` can be swept in parallel per file (one Sonnet per file group).

**Prerequisites.** Land **after WP2** (the Classic branch holds 17 of the 124 rows and 26 of App.swift's constraint literals) and **after WP4** (string renames touch the same lines). `DesignTokens.swift` itself can land at any time.

**Tests to add (can fail).**
* `TypographyTests`: for every `Style`, `font(_:).pointSize >= 18`; `body == 20`; `floored(.systemFont(ofSize: 9)).pointSize == 18`; `floored(nil)` is 20.
* Source guard (in `tools/check-tokens.py`, run by `test.py`): regex `ofSize:\s*[0-9]` / `Self\.font\([0-9]` / `NSFont\(name:[^)]*size:\s*[0-9]` outside `DesignTokens.swift` and the annotation/document files (`Canvas.swift:81,1921`, `DocumentModel.swift`, `SVGExport.swift`, `LegacyBridge.swift`) → **fails**. Today it would flag 124 lines.
* The live view-tree font-floor walker (T14) — that is the real regression gate.

**Risks.** 20 pt controls widen rows → `ModernEditorChrome.minimumWindowWidth` (980) and the Prefs/History minimum sizes must be re-measured (T8); Fonts-panel conversion (`TextStyleForm.swift:186-231`) fights AppKit's own sizing — keep its logic, change only the literal. Sweeping 18→20 will change many snapshot expectations in `AppSafetyTests` (328 KB) — budget the test edits.
**Estimate.** Tokens file + tests 0.5 d; sweep 1.5 d (parallelisable to ~0.7 d wall).

---

## T2 — Color tokens

**Current state (INV §2).** Glass chrome and overview panel are semantic; leaks are the swatch image/outline (`App.swift:1053-1055`, `BezelDrawingControls.swift:84,91`), Classic gradient (`App.swift:29`), drag-thumbnail scrim (`App.swift:172`), capture overlays and hint bevel (fixed values by design), `ToolButton.textColor` computed against the *opaque* accent while the surface is tinted at 0.85 (`GlassChrome.swift:324,179`). Increase Contrast is handled only in `GlassSurfaceView`.

**Target spec** — `DesignTokens.Palette`, every role a dynamic `NSColor` (`NSColor(name:dynamicProvider:)`) with four arms (aqua, darkAqua, and the two `accessibilityHighContrast*` appearances):

| Role | Value (light / dark follow system) | Replaces |
|---|---|---|
| `surface.window` | `windowBackgroundColor` | `FrameChromeView` fill (`App.swift:25`) + the vibrancy backdrop (`ModernEditorChrome.swift:238-240`) |
| `surface.content` | `controlBackgroundColor` | History grid, tables, cards |
| `surface.canvasWell` | `underPageBackgroundColor` (**solid**) | transparent scroll view over a material (`ModernEditorChrome.swift:250-251`) |
| `text.primary / secondary / disabled` | `labelColor` / `secondaryLabelColor` / `disabledControlTextColor` | – |
| `text.onAccent` | **computed**: blend accent at the used alpha over the plate colour, pick black/white by WCAG ratio ≥ 4.5 | `ToolButton.textColor` (move + fix) |
| `accent` | `controlAccentColor` | – |
| `state.hover / pressed` | `labelColor` @ 0.08 / 0.16 (high contrast 0.16 / 0.28) | `GlassChrome.swift:327-328` literals |
| `state.selected.fill` | `controlAccentColor` @ 0.20 (HC 0.32 + 1 pt accent border) | accent @ 0.85 on the tile (`GlassChrome.swift:324`) |
| `state.primary.fill` | `controlAccentColor` @ 1.0 (Snap only) | Snap @ 0.85 |
| `focus.ring` | `keyboardFocusIndicatorColor`, 2 pt | custom 2 pt rings (`BezelDrawingControls.swift:94,159`, `CanvasNavigator.swift:185-188`) |
| `separator` | `separatorColor` | – |
| `feedback.error` | `systemRed`, **always paired with an "Error"-prefixed string or icon** (Differentiate Without Color) | `GlobalHotkeys.swift:712`, `ResizePanel.swift:432`, `HistoryBrowser.swift:306` |
| `swatch.outline` | `separatorColor` (rest), `labelColor` @ 0.5 (hover), accent 3 pt **+ check glyph** (selected) | `NSColor.darkGray` (`BezelDrawingControls.swift:91`, `App.swift:1055`) |
| `overlay.scrim` | `deviceRGB(24,24,24)@0.65` (fixed, over arbitrary screen pixels) | `OriginalCapturePicker.swift:421` |
| `overlay.plateFill / plateText` | `white@0.75` / `black`; HC: `white@0.92` | `OriginalCapturePicker.swift:446`, `OriginalCaptureMagnifier.swift:110` |
| `overlay.hudFill / hudText` | `black@0.85` / `white`; stroke `white@0.95` | `OriginalHelpBevel.swift:90-92,58` |
| `overlay.crosshair` | `white@0.2` 3 pt under `black@0.4` 1 pt | `OriginalCapturePicker.swift:431-432` |

Fixed overlay colours are intentional (they sit on screenshots, not on app surfaces) and are named as such so the colour-literal gate can exempt only `overlay.*`.

**Substeps.** Add `Palette`; add `Palette.resolve(_ role:, for appearance:, highContrast:)` used by custom drawing (`performAsCurrentDrawingAppearance`); replace the 14 literals; fix `onAccent` to take the real blended fill; make `GlassSurfaceView.resolvedTint` read `Palette.state.*` (values equal today's except `selected`).
**Files.** `DesignTokens.swift` (new), `GlassChrome.swift`, `BezelDrawingControls.swift`, `App.swift` (swatch image + scrims), `HistoryBrowser.swift`, `GlobalHotkeys.swift`, `ResizePanel.swift`, `OriginalCapture*.swift`, `OriginalHelpBevel.swift`, `CanvasNavigator.swift`.
**Ownership.** `GlassChrome.swift` collision (WP1, WP2, T4, T6, T7); `App.swift` serial. Overlays/Hint bevel files are free.
**Prerequisites.** After WP1 (deletes `ToolButton` and moves `textColor`). `Palette` file can land earlier.
**Tests.** (1) `PaletteTests`: in `.aqua`, `.darkAqua`, and both HC appearances every text role vs its surface has contrast ≥ 4.5 (≥ 3 for ≥ 24 pt), computed with `NSColor` → sRGB luminance — **fails if a role is changed to a low-contrast value**. (2) `onAccent` is computed from the blended fill (test with accent set to yellow, which flips to black). (3) Source gate: no `NSColor(white:`, `.darkGray`, `.white`, `.black` outside `overlay.*`, `Canvas*`/`DocumentModel` content drawing, `FontAwesomeIcons` mask. (4) Appearance-snapshot assertion in the T14 walker: render the main window once in `.darkAqua` and sample the swatch outline pixel vs the surface (>= 3:1).
**Risks.** Accent @0.20 selected fill may be too weak on a light accent (e.g. yellow) — compute rather than assume; dynamic-provider colors must not be cached as `cgColor` (`GlassSurfaceView.updateRing` already uses `performAsCurrentDrawingAppearance`, keep that pattern).
**Estimate.** 1 d.

---

## T3 — Spacing, corner and size tokens

**Current state (INV §3).** One partially used metrics struct (`GlassChrome.Metrics`, 5 dead members); chrome layout lets inside `build()` (`ModernEditorChrome.swift:219-220`); ≥ 100 raw constraint constants; **10 distinct corner radii** (2,3,4,5,6,8,12,14,capsule); `minimumWindowWidth` a measured literal.

**Target spec** (4-pt grid; 8 as base unit):

```swift
enum Space  { static let s1: CGFloat = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32 }       // only these in layout
enum Radius { static let sm: CGFloat = 4,  md = 8, lg = 12, xl = 16
              static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat { max(sm, outer - inset) } }  // capsule = height/2
enum Size   { static let control: CGFloat = 36, field = 40, row = 44, tool = CGSize(44, 40), primary = CGSize(56, 44),
              icon = CGSize(48, 40), hitMin = 36 }          // control heights at 20 pt text
enum Layout { static let margin = Space.s4, gap = Space.s2, header = 52, footer = 52 }
```

* Radii mapping: handles/badges → `sm` 4 (was 2,3,4,5,6); swatches, thumbnails, drag plate, text grip → `md` 8 (was 5,8); tool tiles & hint bevel → `lg` 12; group plates/sheets cards → `xl` 16 (new); buttons in groups use `concentric(outer: xl, inset: s1)` = 12; capsules unchanged.
* Control heights at 20 pt: min 36 for any clickable control, 40 for text fields/popups, 44 for rows/primary; the 14–22 pt glyph keeps a 36 × 36 hit target (current icon tiles 48 × 36 satisfy it; the 14 pt size knob in the slider does not — its hit area is the whole control so OK).
* Replace the literals `margin 12, gap 8, headerTop 4, rowHeight 44, footerBottom 8` and the local insets (`:264,324-326,341,363,368`) with tokens; `GlassChrome.Metrics` is deleted in favour of `Size`/`Layout`.
* `ModernEditorChrome.minimumWindowWidth` becomes **derived**: `header.fittingSize.width + 2·Layout.margin` evaluated after build (kept ≥ the measured value as a floor) so type changes cannot silently clip (the existing test `modernTopBarLayout` already asserts "unclipped at min").
* **T15 dependency (owner-required rail removal).** `Size.tool = 44 × 40` (already proposed above) is also T15's fit lever that lets Frame mode
  (Cancel visible) fit the top bar at 980 pt; `Layout.margin` (12 today, 16 above) and `Layout.header/footer` (44 today, 52 above) feed T15's width and
  height budgets. T15's tables are computed with the **current** 12/44 values; if T3 moves to 16/52 the usable bar width at 980 falls from 956 to 948 and the
  Frame-mode top bar slack (10 pt) goes to 2 pt, and viewport height at the minimum window falls 16 pt — re-run T15's budget (it is a pure function of the tokens) before
  adopting 16/52. Do not adopt `margin 16` without changing the lever.

**Substeps.** Add tokens; migrate `ModernEditorChrome` and `GlassChrome` first (they are the only consumers of `Metrics`), then sheets/panels file by file.
**Files.** `DesignTokens.swift`, `GlassChrome.swift`, `ModernEditorChrome.swift`, `App+ModernChrome.swift`, `App.swift` (drag well plate, thumbnails), `HistoryBrowser.swift`, `PhotoBrowser.swift`, `ResizePanel.swift`, `GeneralPreferencesForm.swift`, `ExportAccessory.swift`, `GlobalHotkeys.swift`, `Publishing*.swift`, `BezelDrawingControls.swift`, `Canvas.swift` (grip/handles radii), `CanvasBorderView.swift`.
**Ownership.** Same hotspots as T1; do T1+T3 in a **single** sweep per file to avoid touching each line twice.
**Prerequisites.** After WP2/WP4 (as T1). Token definitions anytime.
**Tests.** (1) `MetricsTests`: every `Space.*` is a multiple of 4; `Radius.concentric` never < `sm`. (2) Source gate: `constant:\s*[0-9]+` and `xRadius:\s*[0-9]` outside `DesignTokens.swift` (and the geometry structs for recovered capture math) fail; today ~100 hits. (3) Layout assertion in the T14 walker: at minimum window size no control frame is clipped by any ancestor at 20 pt (reuse the `verifyLayout` pattern, `GlassChromeTests.swift:672-700`).
**Risks.** Changing header 44 → 52 and tool 48×40 → 44×40 moves the canvas rect (centring tests assert margins ≤ 1 pt — they self-adjust because they measure); Frame-mode capture rects derive from the scroll view frame (`App.swift:1951-1962`) — re-run capture geometry tests.
**Estimate.** 1.5 d (shared sweep with T1: 2.5 d total).

---

## T4 — Navigation glass layering

**Current state (INV §4).** 26 `GlassSurfaceView`s (one per icon) in 7 containers + a vibrancy backdrop under the canvas well; no glass-on-glass, no glass over canvas at rest; a native capsule `NSSegmentedControl` sits on a glass plate (double plate); two tinted elements at rest; Reduce Transparency has no consumer (INV §4.6).

**Layout is fixed by T15 (no right rail, owner-required) and does not depend on Q3.** T4 only decides *how the two bars are built*:
top bar = `[Hide][Toolbox][Photos] · [Snap][Cancel] · 10 tools · [Color][Size][Font]`, bottom bar = `[Undo][Wipe] · [Zoom][Resize…] · status · [Save][History] · [PNG|JPG][Drag][Upload]`.

**Target spec — option A (recommended, Q3): system toolbar on top, custom bottom bar.**
* `NSToolbar` (unified, `showsBaselineSeparator` off) carries the T15 top-bar order: [Hide][Toolbox][Photos] · [Snap][Cancel] · tool group (`NSToolbarItemGroup(selectionMode: .selectOne)`, 10 tools, archive order) · [Color][Size][Font]. The system supplies the single glass layer, Reduce Transparency and Increase Contrast adaptations and Control-F5 keyboard access. Items use FA/SF images with `label` + `toolTip`; labels are shown only in the toolbar's "Icon and Text"/customize sheet. **Gate before adopting:** a spike must show all 16 items (Cancel visible) unclipped at 980 pt with no overflow chevron; T15's numbers (top bar 946 of 956 pt in Frame mode) leave 10 pt, which `NSToolbar` item padding may not honour — if it overflows, Q3 resolves to option B.
* **No right rail** (T15). Snap/Cancel/Color/Size/Font are top-bar items; Undo/Wipe are bottom-bar items. Inside the bars nothing is nested glass: hover/pressed/selected are **fills on a rounded layer** (T6).
* Bottom bar: one `GlassSurfaceView` (`.capsule`) per group (T15 §c: Undo/Wipe, Zoom/Resize, Save/History, [PNG | JPG][Drag][Upload]); the status text (merged with the pixel size) sits on the solid window surface between the groups, *not* in glass.
* Content: window background `surface.window` solid; canvas well `surface.canvasWell` solid with the scroll view drawing it; **delete** the `NSVisualEffectView` backdrop and the `NSBackgroundExtensionView` bleed (`ModernEditorChrome.swift:77-78,238-244`, `GlassChrome.usesCanvasBleed`, `modernCanvasBleed` test). Glass surfaces never overlap `scrollView.frame` (keep the current constraint structure).
* Count budget: ≤ 2 `GlassSurfaceView` + the system toolbar (was 26 + 7 containers).

**Option B (custom bars, if Q3 = no — and it is what T15 builds first):** same T15 bars; the top bar becomes 4 group surfaces (leading, capture, tools, annotation) and the bottom bar 4 group surfaces (Undo/Wipe, Zoom/Resize, Save/History, output) inside two `NSGlassEffectContainerView`s = 8 surfaces total (was 26); selected tool = fill layer; no per-button glass. Bar group order, gaps and widths are T15 §c, not re-decided here.

**Reduce Transparency fallback.** `GlassSurfaceView.applyTransparencyFallback()`: when `accessibility.reduceTransparency` → hide the glass view's material by setting `style = .regular` + `tintColor = nil` **and** inserting a solid plate (`controlBackgroundColor`, 1 pt `separatorColor` border, same radius) behind `contentView`; observed through the existing `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (`ModernEditorChrome.swift:122-124`). The toolbar variant relies on system behaviour (state this in the test as *unverified, system-owned*).
**Increase Contrast.** 1 pt `separatorColor`→`labelColor@0.6` border on every glass plate (today only on selected tiles).
**Tint discipline.** Only Snap carries saturated accent; selected tool uses the 0.20 fill + accent glyph (T2).
**Concentric corners.** Bar-group radius `Radius.xl` (16); inner controls `Radius.concentric(16, inset: 4)` = 12; capsule footer = height/2.

**Substeps.** (1) Land T2/T3 tokens. (2) Introduce `CommandButton` (T6) with its own layer plate. (3) Rebuild header/footer in `ModernEditorChrome` (on top of T15's already-relocated groups) (or `ToolbarController`) — delete per-button `GlassChrome.surface` use, `iconPill`, `GlassChrome.group` of 1-glyph containers. (4) Delete backdrop/bleed code and tests. (5) Add fallback + HC border. (6) Re-point `AppDelegate` references (`toolButtons`, `snapButton`, `cancelFrameButton`, `resizeButton`) — they are `NSButton` today, so an `NSToolbarItem`'s view needs a thin adapter (`App.swift:241,274,300-301`; evidence in `writeLayoutEvidence` `:2216-2285`).
**Files.** `GlassChrome.swift`, `ModernEditorChrome.swift` (+ new `ModernToolbar.swift` for A), `App+ModernChrome.swift`, `App.swift` (references, evidence), `tests/GlassChromeTests.swift`, `tests/AppSafetyModernCases.swift`.
**Ownership.** **All four hotspots** (`App.swift`, `GlassChrome.swift`, `ModernEditorChrome.swift`, plus both test files): one implementer, serial; T6/T7/T9 touch the same files, so T4 → T6 → T7 are one chain.
**Prerequisites.** **T15 first** (it relocates every rail control into the two bars; T4 then restyles bars that already have their final contents and positions, so it never edits rail code), WP1 (strip `classicArtworkName`, `ToolButton`), WP2 (remove availability gates; macOS 26 min), T2/T3 tokens. Toolbar option also needs Q3.
**Tests.** `GlassDepthTests` + the T14 walker: (1) no `NSGlassEffectView` has an `NSGlassEffectView` ancestor or descendant; (2) glass count ≤ budget per window (option A: ≤ 4 bottom-bar group surfaces + the system toolbar; option B: ≤ 8, T15 §c groups); (3) no glass view's frame (window coords) intersects the canvas scroll view's frame, at default, minimum and Frame-mode sizes; (4) with `ChromeAccessibility(reduceTransparency: true)` every surface has a plate with alpha 1 and `tintColor == nil` — **this fails today** (no consumer); (5) HC border present; (6) exactly one saturated-accent element at rest (Snap) — assert fill alphas.
**Risks.** `NSToolbar` min-width/overflow behaviour with 14 items (overflow chevron) vs the current "one row fits at 980"; selection-group semantics vs `AppDelegate.updateToolButtons` (`App.swift:1007-1014`); Frame-mode clear window + toolbar (titlebar backdrop hack at `App.swift:1900-1910` assumes a plain titlebar). Glass APIs are macOS 26/27-specific (`effectIsInteractive` is macOS 27, `GlassChrome.swift:279`).
**Estimate.** Option A 3 d (+1 d tests); B 2 d.

---

## T5 — Iconography

**Current state (INV §5).** FA → SF → recovered PNG chain; Upload and Drag-well bypass the chain with SF-only symbols (`ModernEditorChrome.swift:114-118`, `App.swift:71-82`); status item and drag overlays and cursor use original PNGs; 3 FA entries unused (`maximize`, `minimize`, `arrow-up-from-bracket`); Wipe's SF fallback is `trash`; menus use 59 SF symbols; 3 defective glyphs; ASCII `...` in the Toolbox menu.

**Target spec.**
1. **Chain becomes FA → SF → none** (`ChromeIcons.resolve`, `ChromeIcons.swift:38-54`); delete `.classicArtwork`, `classicArtworkName(for:)`, `classicArtworkName`/`selectedClassicArtworkName` setters (`GlassChrome.swift:24-25,159`, `ModernEditorChrome.swift:98,186,283`) — WP1.
2. **Every chrome icon goes through `FAIcon`.** Add: `upload` (FA `cloud-arrow-up`), `dragHand` (FA `hand`), `check` (swatch selected cue), `warning`/`circle-exclamation` (error cue, T7), `screen`/`viewfinder` for the menu-bar glyph source. Remove unused `maximize`, `minimize`, `arrowUpFromBracket` (and their subset codepoints — `tools/fetch-fontawesome.sh` greps hex literals, so deleting the case removes the glyph). *Codepoints must be verified against the subset fetch; do not trust these names from memory.*
3. Semantic fix for fallbacks: Wipe → SF `eraser.line.dashed` (or `xmark.bin`) instead of `trash` (delete ≠ wipe); keep the Arrow tool (`arrow-up-right` / `arrow.up.right`) — functional.
4. **Menu-bar status icon:** own template drawing, no PNG and no SF symbol (owner D5): `StatusIcon.image()` draws an 18 × 18 viewfinder (four corner brackets + centre dot) with `NSBezierPath`, `isTemplate = true`; `button.image` only (the alternate image is unnecessary for templates); `setAccessibilityLabel("Show or hide OpenSnap")`; tooltip same.
5. **Drag-thumbnail overlays** (`App.swift:173-178`): draw a 36 pt circle plate (`Palette.overlay.hudFill`) with the FA `up-right-and-down-left-from-center`/`xmark` glyph (or SF if FA absent); hover brightens the plate.
6. **Cursor** (`Canvas.swift:173-179`): `NSCursor.openHand`/`.closedHand` (system) — owner allowed "own minimal cursor drawing"; system cursors are the minimal choice.
7. **Glyph hygiene:** `º` → `°` (`OriginalHintMessages.swift:59,60`); drop U+F8FF → "Command" (`:87`); Toolbox `...` → `…` (`App.swift:682-683`); no emoji/starburst introduced anywhere (gate in T14).
8. Menu leading icons (59 SF symbols, `MenuSymbols.swift`): leave SF (system convention for menu images) unless Q1 resolves in favour of embedded FA vectors, in which case route `MenuSymbols.apply` through `FontAwesomeIcons.image` with an SF fallback.

**Substeps/files.** `FontAwesomeIcons.swift`, `ChromeIcons.swift`, `GlassChrome.swift`, `ModernEditorChrome.swift`, `App.swift` (status item L424-436, DragThumbnailView L151-182), `Canvas.swift` (cursor), `MenuSymbols.swift`, `OriginalHintMessages.swift`, `tools/fetch-fontawesome.sh`, `tests/FontAwesomeIconsTests.swift`, `tests/MenuSymbolsTests.swift`.
**Ownership.** `App.swift` serial; `Canvas.swift` (one-line cursor) must be sequenced with WP1.
**Prerequisites.** WP1 (assets), WP2 (App.swift), Q1.
**Tests.** (1) `IconCoverageTests`: for every `FAIcon` used by `ModernEditorChrome` the resolver returns `.fontAwesome` when the subset is registered **and** `.sfSymbol` otherwise — run both branches, the FA branch is no longer skippable silently: if `OPENSNAP_FA_FONT_DIR` is absent the suite prints `SKIPPED` **and the gate script fails in CI mode** (`OPENSNAP_REQUIRE_FA=1`). (2) Every `FAIcon` case is referenced by a chrome control (fails on dead entries). (3) `StatusIconTests`: image is template, 18×18, non-empty alpha, symmetric about centre. (4) No-decorative-glyph gate (T14). (5) Source gate: `NSImage(named:` / `Bundle.main.url(forResource:…"png")` anywhere in `Sources/` fails.
**Risks.** Q1; template drawing in the menu bar looks different at 1x vs 2x (render via drawing handler so it is resolution independent); FA Pro codepoint drift between versions (`FontAwesome7Pro` pinned by name in `FAFamily`).
**Estimate.** 1.5 d (after WP1/WP2).

---

## T6 — Component states

**Current state (INV §8).** States exist only for glass tiles (tint model) and native controls; the slider, swatches, History tile, drag well and footer toggle lack some or all of hover/pressed/disabled/focus; disabled dims the whole surface (alpha 0.5); no non-color cue except glyph-family swap.

**Target spec** — one model, `ControlState { rest, hover, pressed, selected, disabled }` + orthogonal `focused`/`highContrast`/`differentiate` flags, resolved by a pure function (testable without views):

```swift
struct StateStyle { var fill: NSColor?; var content: NSColor; var border: NSColor?; var borderWidth: CGFloat; var contentAlpha: CGFloat; var indicator: Bool }
enum StateStyles { static func command(_ s: ControlState, primary: Bool, focused: Bool, highContrast: Bool, differentiate: Bool) -> StateStyle }
```

| State | Command (icon button) | Primary (Snap) | Size slider | Swatch | Drag well | Toggle segment |
|---|---|---|---|---|---|---|
| rest | no fill; `labelColor` | `accent` fill; `onAccent` | track `quaternaryLabel`, dots `secondaryLabel`, knob accent | 1 pt `separator` outline | no plate | native/ours: plate `label@0.06` |
| hover | fill `label@0.08` (HC .16) | +8 % brightness | knob scale 1.15 | outline `label@0.5` | fill `label@0.08` + `openHand` cursor | fill `label@0.08` |
| pressed | fill `label@0.16` (HC .28), glyph scale 0.96 (none under Reduce Motion) | −12 % brightness | knob scale 1.25, track highlight accent@.3 | fill `label@0.16` | `closedHand` during session | fill `label@0.16` |
| selected | fill `accent@0.20` (HC .32 + 1 pt accent), glyph = solid family, **indicator** (2 × 16 pt capsule under glyph) when `differentiate` or always | n/a | n/a | 3 pt accent outline **+ check glyph** | n/a | accent@0.20 + `bodyStrong` |
| disabled | glyph/content `alpha 0.38`, no fill, no hover/press | dimmed accent@0.38 | all @0.38, not draggable | outline 0.38 | plate hidden, `notAllowed` tooltip | content 0.38 |
| focus | 2 pt `keyboardFocusIndicator` ring, 2 pt outset, radius + 2, only when focus is keyboard-driven | ring in `onAccent` contrast colour | same ring around the control | same | same (drag well becomes focusable) | same |

**Implementation.** Introduce `CommandButton` (replaces `GlassChromeButton` + `GlassSurfaceView` pairing): an `NSButton` subclass that draws a rounded-rect plate layer from `StateStyles.command(...)` and keeps `OriginalActionButton` behaviour (secondary click, menu, alternate action — `GlassChromeButton` today inherits it, `GlassChrome.swift:18`). Hover via `NSTrackingArea` (re-use the `GlassSurfaceView` approach `GlassChrome.swift:375-384`), press bracket via `mouseDown` (as `:194-201`), `focusRingMaskBounds`/`drawFocusRingMask` kept (`:226-237`). `BezelSizeSlider` gets hover/pressed/disabled drawing (`BezelDrawingControls.swift:139-163`); `BezelColorButton` gets hover/pressed + check glyph (`:76-99`); `DragExportView` gets `NSTrackingArea`, `resetCursorRects` (open/closed hand), `acceptsFirstResponder = true`, `drawFocusRingMask`, `accessibilityPerformPress` → opens the Export panel (keyboard alternative to dragging) and `setAccessibilityRole(.button)`; History tile gets hover + a non-colour selection cue (check badge).
**Files.** `GlassChrome.swift` (heavy), `BezelDrawingControls.swift`, `App.swift` (DragExportView L50-148), `HistoryBrowser.swift` (tile L425-461), `ModernEditorChrome.swift`, `DesignTokens.swift`.
**Ownership.** Hotspot chain with T4 (same files). Slider/swatch/History/DragExportView parts are separable *except* `DragExportView` which lives in `App.swift` (serial).
**Prerequisites.** T2 palette, T3 sizes; T4 decides whether plates are layers (A/B both use `CommandButton`).
**Tests.** `StateStylesTests` (pure): for every state × primary × HC × differentiate assert the exact fill alpha / content alpha / indicator flags; disabled never has a hover/pressed fill; selected+differentiate always has `indicator`; pressed ≠ hover; HC strictly stronger than normal. `CommandButtonStateTests`: drive `setHovered/mouseDown/state/isEnabled` and assert `layer?.backgroundColor` equals the resolved style (this is what `GlassChromeTests` asserts only at the `tintColor` property today). Slider: knob rect scales; `DragExportView` first responder + press action invoked on Space/Return.
**Risks.** Re-implementing glass-tile behaviour in layers can regress click/Control-click/menu paths (`OriginalActionButton`) — keep inheritance and re-run `OriginalActionButtonTests`; focus rings drawn over a layer plate need `focusRingMaskBounds` in the button's own coordinates; if Q3-A, toolbar item views have their own states — apply `StateStyles` only to bottom-bar controls and the stroke pill. After T15 the *Size* column above describes the popover's horizontal track and the pill glyph, not a vertical slider (T15 §d); the five preset buttons in that popover use the Command column.
**Estimate.** 2.5 d.

---

## T7 — Accessibility

**Current state (INV §9).** 0 unlabeled icon-only controls; 25 icon-only controls with tooltip-only visible names; weak/legacy labels (Drag Me, Upload, tool labels, "Skitch" in two AX strings); no live-region announcements; Reduce Motion partly honoured (hint-bevel fade, capture flash, countdown alpha, not); Reduce Transparency and Differentiate Without Color not honoured; no key-view loop on the main window; Destinations sheet has no Return/Escape; Prefs has Return only.

**Target spec.**
* **Labels (VoiceOver text = verb or noun + role-free):** tools "Select tool", "Brush tool", … (add the word "tool"); Upload → "Upload image" (tooltip same); Drag well → "Drag image to another app" with role `.button` + `accessibilityPerformPress` → Export panel; Toolbox → "Toolbox menu"; PNG|JPG → segments "PNG", "JPG" under group "Image format"; status item → "Show or hide OpenSnap". Selected state exposed through `NSButton.state` (already) and `accessibilityValue` for the tool group.
* **Relocated controls (T15 §d, §f):** Size becomes a pill with role `.slider`, label "Drawing size", `accessibilityValue` = the whole-number size ("9"), `accessibilityPerformIncrement/Decrement` stepping one preset, and a custom action "Show size options" that opens the popover; Color keeps label "Drawing colors" and its swatch `accessibilityValue`; Cancel keeps "Cancel"; Undo/Wipe/Resize/Save/History keep their labels and tooltips when they move to the bottom bar. The Size popover's track is a second `.slider` element with the same value and the five preset buttons are `.button`s labelled "Size N".
* **Visible names, not just tooltips:** keep icon-only chrome (owner's "content first"), but (a) native tooltip delay is the only text → add **Icon+text mode** (View ▸ "Show Toolbar Labels") only if Q3-A (toolbar customisation provides it for free); (b) hover-hint bevel remains optional. State this as a conscious trade-off, not a defect.
* **Live announcements:** `AppDelegate.announce(_:)` posts `NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [.announcement: text, .priority: .medium])` on upload start/success/error, capture success, Frame enter/leave, Undo/Redo result. Status label gets `setAccessibilityRole(.staticText)` + `accessibilityLiveRegion`-equivalent via announcements.
* **Display options (one `DisplayOptions` value replacing `ChromeAccessibility`, read live + observed):** `reduceMotion` (also gate hint-bevel fade `OriginalHelpBevel.swift:255-279`, flash ramp `OriginalCaptureFlash.swift:6-23`, countdown alpha `OriginalCaptureCountdown.swift:141`, drag-thumbnail shrink `App.swift:582-596` — already gated by `animatesWindowZoom`), `reduceTransparency` (T4 plates), `increaseContrast` (T2 HC arms + T4 borders + slider/overview/hint-bevel variants), `differentiateWithoutColor` (T6 indicator/check/prefix), all observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` by **every** window with custom drawing (currently only `ModernEditorChrome`).
* **Keyboard:** `window.autorecalculatesKeyViewLoop = true`; `initialFirstResponder = canvas`; explicit loop top bar (left → right) → canvas → bottom bar (left → right) — after T15 this is also the default geometric order, so only the Size popover and Color popover need explicit `nextKeyView` entries; every custom view that draws content exposes `focusRingType`/mask; `GlassChromeButton`/`CommandButton.canBecomeKeyView` honours Full Keyboard Access; Tab from canvas moves to the next control (canvas currently eats Tab for tool switching, `OriginalHintMessages.toolHoverPrefix` "tab = Pen" — keep, but document Control-F5/FKA path and provide a menu command "Focus Toolbar").
* **Escape/Return:** Prefs gets Cancel-on-Escape (`cancelOperation` → `closePreferences`); Destinations sheet: Return = Save/Done, Escape = Cancel/Done (set `keyEquivalent` on the buttons, `PublishingDestinationsView.swift:36-40,221-224`); History: Return = Open, Escape = close; every `NSAlert` already handles both.
* **Errors/colour:** error strings are prefixed "Error:" (not colour-only).

**Substeps/files.** `DisplayOptions` in `DesignTokens.swift`/`GlassChrome.swift`; announcements in `App.swift`; labels in `ModernEditorChrome.swift`, `App+ModernChrome.swift`, `App.swift`; Escape/Return in `GeneralPreferencesForm.swift`, `PublishingDestinationsView.swift`, `HistoryBrowser.swift`; motion gates in `OriginalHelpBevel.swift`, `OriginalCaptureFlash.swift`, `OriginalCaptureCountdown.swift`.
**Ownership.** Hotspot chain (App.swift serial). Motion gates in the `Original*` files are conflict-free.
**Prerequisites.** T4/T6 (labels live on the new controls); the capture-file gates can go earlier.
**Tests.** (1) `AccessibilityAuditTests`: walk every window; every `NSControl` with no visible title has non-empty AX label **and** a role; labels unique within a window; the word "Skitch" absent. (2) `DisplayOptionsTests`: injecting `reduceMotion` makes hint-bevel/flash/countdown produce zero intermediate alpha steps (assert tick sequence = [final]) — fails today. (3) Key-loop test: starting at the first control, walking `nextValidKeyView` visits every enabled control exactly once and returns. (4) Escape/Return test on Prefs, Destinations, Resize, Photos, Hotkeys (simulate `performKeyEquivalent`). (5) Announcement test with an injected poster.
**Risks.** Announcements can be noisy (rate-limit to state changes); Full Keyboard Access vs canvas Tab semantics; AX label changes ripple into `AppSafetyModernCases` string expectations (`modernControlStrings`, `modernIconOnlyCommands`).
**Estimate.** 2 d.

---

## T8 — Window chrome

**Current state (INV §10).** 1024 × 740 default, min 900 × 640 → width 980 for the one-row bar; no frame autosave, `representedURL`, subtitle, full screen; `window.center()` on every launch (`App.swift:368`); Prefs/History sizes large (History min 1120 × 850; Destinations sheet 820 × 860).

**Target spec.**
* Main window: standard titled window; **title = document name** (existing `showDocumentName`, `App+ModernChrome.swift:20-23`, fallback "OpenSnap"); **`representedURL = currentURL`**; **`subtitle`** = "<W> × <H> · <size>" live from `dragSizeLabel` source (drop that footer label); `isDocumentEdited` kept; `setFrameAutosaveName("OpenSnap.Main")` + skip `center()` when a saved frame exists; `titlebarAppearsTransparent` stays false (Frame-mode hack depends on it).
* Sizes (re-measured at 20 pt after T1/T3): default **1120 × 780**, minimum = `max(worst-case top-bar fitting width (Frame mode, Cancel visible) + 2·margin, bottom-bar fitting width + 2·margin, 980) × 680` (computed, T3; T15 §b shows both bars fit at 980 with 10 pt / ≈ 21 pt slack, so the 1000 floor proposed earlier is **not** a fit requirement and is dropped), maximum none; `contentMinSize` for sheets as below. The viewport height at the 680 minimum is 680 − 32 (title bar) − 116 (bars + gaps) = 532 pt.
* Full screen: `collectionBehavior.insert(.fullScreenPrimary)`; in `enterFrame` (`App.swift:1883`) if `window.styleMask.contains(.fullScreen)` → `toggleFullScreen` first or refuse with status text (Q4). Hide the status-item zoom animation under full screen.
* Toolbar style: Option A (T4) `NSToolbar`, `toolbarStyle = .unified`; otherwise none.
* Preferences → Settings-style window: `NSTabViewController` with `tabStyle = .toolbar`, tabs **General / Drawing / Capture / Upload** (Appearance and Sounds removed; Shortcuts folded into Capture), title = selected tab, no Done button (changes apply live — they already do via `onChange`), size 640 × auto per tab, `isRestorable` frame, Escape closes. 
* History: default 1000 × 720, minimum **880 × 600** with an adaptive flow-layout grid (item 210 × 234 stays); details panel collapses under the grid below 760 pt width.
* Sheets: Resize 600 × auto ✔ (add `.resizable` no); Destinations 820 × 860 → **720 × min(720, visibleFrame−120)** with the form inside a scroll view; Photos 900 × 700 ✔ (min 760 × 540); Hotkeys 940 × 660 → 760 × auto (the stack already scrolls).
* Sheet vs modal: sheets for anything document-scoped (Resize, Photos, Destinations, Hotkeys, Rename); `NSAlert.beginSheetModal` instead of `runModal` for document alerts (`App.swift:1271,1275,1514,1529`) so the app stays responsive and Frame-mode level juggling (`withFrameWindowValuesSuspended`) is only needed for open/save panels.

**Files.** `App.swift` (buildWindow L716-718, showPreferences L1698-1732, alerts), `App+ModernChrome.swift`, `AppViewport.swift`, `WindowSizing.swift`, `HistoryBrowser.swift`, `Publishing.swift` (`makePanel` L1062-1065), `GlobalHotkeys.swift`, `GeneralPreferencesForm.swift` (becomes four small view controllers).
**Ownership.** `App.swift` serial. Prefs/History/Destinations/Hotkeys are separate files → parallel with T11.
**Prerequisites.** WP2 (Appearance/Relaunch rows gone), T1/T3, T4 (toolbar decision), Q4.
**Tests.** `WindowChromeTests`: (1) at default and at the derived minimum, every control inside the content rect at 20 pt (walker); (2) autosave key restored round-trip in a temp defaults suite; (3) `representedURL` follows `currentURL` through Save/Open/New; (4) full-screen + Frame mutual exclusion (inject `styleMask`); (5) Prefs: Escape closes, each tab's fitting size ≤ screen visible height on a 1280 × 800 fake screen; (6) History min size ≤ 880 × 600 and grid reflows (no horizontal scroll at min).
**Risks.** `WindowSizing`/Actual-Size math uses `window.minSize` (`AppViewport.swift:131,217-218,269-270`) — re-run `WindowSizingTests`; changing the Prefs window type breaks `App.runRelaunchSmoke`-style tests (deleted in WP2). Autosave + `center()` interplay affects `eye-dump` determinism (use the isolated defaults domain).
**Estimate.** 2 d (Prefs/History parts shared with T11).

---

## T9 — Footer / export / drag / upload (reconciled with the merged PNG | JPG toggle)

**Current state (4b2ae0f).** The toggle is merged: `FormatToggle` (`ImageExport.swift:5-22`, PNG default, JPG fixed 0.75, stored via the old `DragFormatChoice` row index), `dragFormatToggle` `NSSegmentedControl(.capsule)` in the glass `formatSurface` (`App+ModernChrome.swift:79-85`, `ModernEditorChrome.swift:342-351`), `dragFormat/dragQuality/uploadEncoding/historyJPEGQuality` switch on `modernChrome != nil` (`App.swift:1218-1233,1494,1759-1767`), Export panel accessory with `fixedJPEGQuality` (`ExportAccessory.swift:147-150,253-262`, `App.swift:1565-1575`), drag file extension `.jpg` (`App.swift:131-135`). Leftovers: the unused `dragFormatControl` popup still allocated (`App.swift:226`) and the stored-row compatibility shim; "Skitch" format entries in Export (`ExportAccessory.swift:3-6`), History (`HistoryBrowser.swift:45,315`); upload has only a status string and a modal alert on failure (`App.swift:1795-1812`); drag well has no states/keyboard path (T6).

**Target spec.**
* **Bottom bar — superseded by T15 §c** (left → right): `[Undo][Wipe]` · `[Zoom][Resize…]` · `Original size` checkbox (`body`, only when `isLargeShot`) + one flexible truncating status that now also carries the pixel size and byte count (the separate `dragSizeLabel` is no longer on screen) · `[Save][History]` · `[PNG | JPG][Drag][Upload]`. The toggle and the two icon buttons live in one glass group (T4); the status text sits on the solid surface between the groups.
* Format model: replace the row-index hack with a small enum `ImageFormat { png, jpg }` persisted under `OpenSnap.imageFormat` (migration maps old `DragFormatChoice` 1…5 → `.jpg`, else `.png` — in WP4's defaults copy); `FormatToggle.jpgQuality` becomes `ImageFormat.jpgQuality = 0.75` in `DesignTokens`/model, shared by drag, export, upload, History export (already true in code; keep the byte-comparison tests, `AppSafetyModernCases` toggle case).
* Segmented control: custom `SegmentedToggle` drawn with `StateStyles` (T6) on the glass capsule (no native bezel → no double plate); labels `body` 20.
* Export accessory (Modern): formats **PNG, JPG, PDF, TIFF, SVG** (drop GIF/BMP/“Skitch” unless needed; keep behind “More formats…” only if owner wants); JPEG quality row replaced by static text "JPG quality 75 %" (the slider is locked today, `ExportAccessory.swift:253-262`).
* Upload feedback (S21): `UploadState` model on `AppDelegate`: `.idle`, `.uploading(name)` → footer shows a 20 pt indeterminate `NSProgressIndicator` + "Uploading <name>…" + inline **Cancel** (`cancelUpload` already exists, `App.swift:1659`), `.success(url, copied)` → "Link copied" for 4 s + announcement + Undo-free toast row, `.failure(message)` → inline "Error: <message>" with **Retry** and **Details…** (replaces `NSAlert(error:)` at `App.swift:1795-1812` except destination-not-configured, which opens settings as today).
* Drag well: FA `hand` (T5), states (T6), keyboard activation (T7), tooltip "Drag the drawing into Finder or another app"; thumbnail-shrink animation respects Reduce Motion (already via `animatesWindowZoom`).
* Remove `Skitch`-named drag/file defaults (`App.swift:131-135` fallback name "Skitch" → "Untitled"/document name).

**Files.** `ModernEditorChrome.swift`, `App+ModernChrome.swift`, `App.swift` (DragExportView L50-148, drag/upload funcs L1221-1233, L1758-1812), `ImageExport.swift`, `ExportAccessory.swift`, `HistoryBrowser.swift`, `PublishingDestinations*.swift` (state hooks), `tests/AppSafetyModernCases.swift`, `tests/ExportAccessoryTests.swift`, `tests/ImageExportTests.swift`.
**Ownership.** **App.swift serial; ModernEditorChrome/App+ModernChrome hotspots** (T4/T6/T7 chain).
**Prerequisites.** **T15** (it already moves the footer to the final bottom-bar order and merges `dragSizeLabel` into the status text; T9 then adds the upload state UI *inside that status slot*), WP2 (remove Classic `dragFormatControl` popup and `webpost` button), WP4 (defaults migration, names), T4/T6.
**Tests.** Keep the merged byte-level tests (drag/export/upload/History produce the same bytes); add `UploadStateTests` (state machine via the injected `publishing.uploader` seam: idle → uploading → success/failure; Cancel returns to idle; Retry re-invokes with the same payload; error text begins "Error:"); `FooterLayoutTests` at min width: status truncates before any control clips; toggle exposes two AX children "PNG"/"JPG"; defaults migration test (old `DragFormatChoice` 3 → JPG).
**Risks.** *Width (T15):* the status slot is 291 pt at 980 (141 pt while the Original-size checkbox is shown, both ESTIMATE). The upload row (20 pt spinner + 8 + name + 12 + inline Cancel ≈ 140 pt of fixed parts) therefore **hides the Original-size checkbox for the duration of an upload** and lets the name truncate; do not widen the bar. `uploadEncoding` and `exportPanelAccessory` still branch on `modernChrome != nil` — after Classic removal these collapse (do it in WP2 to avoid dead branches); inline error UI must not break the shutdown barrier (`finishShutdownDecision` expects the alert path to be async, `App.swift:403-417`).
**Estimate.** 2 d.

---

## T10 — Capture surfaces

**Current state (INV §S13–S16).** Countdown shows original `SkitchCount1-3.png` and **does not show at all** if they are absent (`OriginalCaptureCountdown.swift:53-81`); crosshair/magnifier/read-out are recovered geometry with fixed colours and 20 pt labels; flash is a 0.1 s white panel; permission denial = raw `NSAlert(error:)` text (`Capture.swift:685-687`); sounds fire from `Capture.swift:787`, `App.swift:1847`.

**Target spec.**
* **Countdown (drawn).** `CountdownNumeralView`: a 140 × 140 plate (`Palette.overlay.hudFill` @ 0.55, HC 0.8, `Radius.xl`) with the digit in `Typography.countdown` (SF Rounded Heavy 160, white, 2 pt shadow). Placement math unchanged (`OriginalCaptureCountdown.placement` L191-221); images replaced by a closure `(Int) -> NSView`. Timing/cue sequence unchanged (3 → 2 → 1 at the existing ticks, `OriginalCaptureTiming`). **Reduce Motion:** ignore `frame.alpha` stepping (`:141`), show digit at alpha 1, hide at finish. VoiceOver: announce "3, 2, 1" via `.announcementRequested` (T7). Remove sound cue (`Capture.swift:368,787`, `App.swift:446`).
* **Crosshair & read-out.** Keep geometry; colours from `Palette.overlay.*`; read-out `Typography.hud` on `plateFill` with `Radius.sm`; add 1 pt `separator` stroke on the plate for dark screenshots.
* **Magnifier.** Keep 10 × zoom, 100 × 100 lens (`OriginalCaptureMagnifier.swift`); label `Typography.numeric`; when Screen Recording is absent show a **diagonal-hatch placeholder with the text "Screen Recording off"** instead of an unexplained grey lens (`:103`).
* **Flash.** 0.1 s, peak white @ 0.7 (not 1.0); Reduce Motion → no ramp, single 0.05 s frame; skipped entirely when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` **and** the user pref "Show capture flash" is off (Q5; the pref lives in Capture prefs).
* **Permission UX.** Pre-flight before any overlay: if `!CGPreflightScreenCaptureAccess()` → `PermissionAlert.screenRecording()`: title "OpenSnap needs Screen Recording", text "Allow OpenSnap in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then reopen it.", buttons **Open System Settings** (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`) / **Cancel**; first run also calls `CGRequestScreenCaptureAccess()` after the user presses Continue. Failure inside an in-flight capture keeps the typed error but routes through the same alert helper (T1 `Alert.make`).
* Picker overlay level, `fullScreenAuxiliary`, Escape/right-click cancel unchanged (tested).

**Files.** `OriginalCaptureCountdown.swift`, `OriginalCaptureFlash.swift`, `OriginalCapturePicker.swift`, `OriginalCaptureMagnifier.swift`, `Capture.swift` (permission pre-flight, remove `onSound`), `App.swift` (alert helper wiring, remove `playOriginalSound`), tests `OriginalCaptureCountdownTests.swift`, `CaptureTests.swift`, `OriginalCapturePickerTests.swift`.
**Ownership.** Capture files are conflict-free except `App.swift` (alert wiring: serial) and `Canvas.swift` only for sound removal (WP1).
**Prerequisites.** WP1 (drawn digits & sound removal are WP1 per owner D5; **T10 is only the styling/permission layer on top**), T1/T2, T7 `DisplayOptions`.
**Tests.** `CountdownViewTests` (no `original/`): the numeral view renders non-empty alpha for 3/2/1, differs per digit, fits the 140 × 140 plate, ≥ 18 pt font; the existing 31-tick/61-tick sequences run **against the drawn views** (they are currently skipped without `original/` — this restores them); Reduce Motion → alpha sequence is constant 1; permission alert: injected `preflight = false` presents our alert with the Settings button and **does not** start the picker; magnifier placeholder text present when no screen image; flash peak ≤ 0.7.
**Risks.** Screen Recording pre-flight can't be verified live in the sandboxed agent session (no permission grant) — keep injection seams (`environment.testDisplays`, `Capture.swift:388-389`); `CGRequestScreenCaptureAccess()` prompts once per bundle id — the rename to `com.shoemoney.opensnap` **resets the TCC grant**, so users re-approve after WP4 (document in release notes).
**Estimate.** 1.5 d.

---

## T11 — Preferences, History, Destinations, Publishing UI

**Current state.** Prefs: in-window 3-tab `NSTabView` with Appearance/Relaunch/Sounds/overlay-tip rows and a Done button only (INV §S17); Capture Shortcuts panel with Skitch wording; History 1120 × 850 min, "SKITCH" format, colour-only selection; Destinations list+form with owner-specific placeholders (`PublishingDestinationsView.swift:214-215` "shoemoney.com", "/var/www/shoemoney.com/shared/imgs"), no Return/Escape, 820 × 860 sheet; Publishing helper buttons 18 pt.

**Target spec.**
* Prefs (T8 structure) tabs: **General** (Dock/Menu bar/Both presence, "Show OpenSnap window in fullscreen and crosshair snaps", tool-tip overlays, keyboard-tip overlay), **Drawing** (precision, arrow head), **Capture** (shortcuts inline: the Hotkeys form embedded; flash pref), **Upload** (destinations list embedded). Removed: Appearance, Relaunch, Play sounds (and keys `appearanceStyle`, `disableSounds`). Row label column right-aligned 20 pt `bodyStrong`; control column `body`; 16 pt rhythm (`Space.s4`).
* History: toolbar-style filter row (segmented category · search · date popup) in the window toolbar when T4-A; grid unchanged; **selection cue = accent border + check badge**; drag formats `PNG, JPG, PDF, TIFF, SVG` (+ `.opensnap` document); empty state text "No history yet. Press ⌘S… " (functional, no illustration); warning row uses error prefix.
* Destinations: placeholders become neutral (`https://example.com/uploads`, `screenshots`, `~/.ssh/config alias`, `/var/www/site/uploads`); form rows grouped into "Connection" and "Credentials" with section headers (`headline`); buttons `body`, default (Return) = Save, Escape = Cancel; Test result is an inline status row with ✓/✗ **glyphs from FA** not colour alone; list shows default with a "Default" pill (text + check), not a trailing "(Default)" string (`PublishingDestinationsView.swift:90`).
* Publishing sheet helpers (`Publishing.swift:1062-1099`) use tokens; message sheet minimum width 560.
* Hotkeys: action titles "Show OpenSnap", etc.; replace the Command+Shift+7 prose with a conflict warning generated from `GlobalHotkeyManager.lastError`.

**Files.** `GeneralPreferencesForm.swift` (→ per-tab VCs), `OriginalGeneralPreferences.swift`, `GlobalHotkeys.swift`, `HistoryBrowser.swift`, `HistoryStore.swift` (strings), `PublishingDestinationsView.swift`, `Publishing.swift`, `App.swift` (showPreferences), tests `GeneralPreferencesFormTests.swift`, `HistoryBrowserTests.swift`, `PublishingDestinationsTests.swift`, `GlobalHotkeysTests.swift`.
**Ownership.** Parallel across files (4 implementers) except `App.swift` (showPreferences, serial) and `OriginalGeneralPreferences.swift` (WP1/WP2 collision → do after).
**Prerequisites.** WP2 (rows removed), WP4 (names/ids/keys), T1/T3 tokens, T8 (window shells).
**Tests.** Re-baseline the 26 appearance refs in `GeneralPreferencesFormTests`; add: no row labelled Appearance/Sounds; Return/Escape bindings per sheet (T7); placeholder strings contain no `shoemoney` (string gate, T14); History min-size reflow; selection cue present for the selected tile (check badge subview) — **fails today**; Destinations Test result shows glyph + text.
**Risks.** Moving shortcuts/destinations into Prefs tabs changes sheet presentation assumptions in `publishing.showSettings(relativeTo:)` and the shutdown barrier (`Publishing.swift:868-880`); keep sheets for modal flows from the main window, embed only in Prefs.
**Estimate.** 3 d (parallel wall ≈ 1.5 d).

---

## T12 — Menus, About, status item, app identity copy

**Current state.** App menu "OpenSkitch", About text "Native 64-bit reconstruction … Skitch 1.0.12" (`App.swift:2176`), Hide/Quit strings, Toolbox ASCII ellipses (`:682-683`), Rename gated on Appearance (`:935`), status item PNG + "Skitch" tooltip, 59 SF menu symbols, "Default Skitch Style", "Skitch Text Style…" (INV §7).

**Target spec.**
* Product string `DesignTokens.Brand.name = "OpenSnap"` (single source; `Info.plist` generated/validated against it by a gate).
* App menu: "About OpenSnap", "Settings…" (macOS 26 wording; ⌘,), "Hide OpenSnap", "Quit OpenSnap"; File: "New", "Open…", "Save", "Save As…", "Rename…" (unconditional), "Export…", "Publish…" ; Text: "Text Style…", "Default Text Style"; Capture: unchanged verbs. All `...` → `…`; Toolbox mirrors the menu bar exactly (generated from the same table; today copied via `copiedMainMenuItem`).
* About: standard panel with `applicationName`, `applicationVersion`, `version` (build), `credits` = 18 pt attributed paragraph "Capture, annotate, share." + one line "Began as a Skitch-inspired rebuild." (README-level factual mention only; **no "Skitch" in any UI string** per §4 — so the About credits omit it) + MIT licence link; app icon from `Resources/OpenSnap.icon`.
* Status item: T5 drawn template icon; menu on click (not only toggle): [Show/Hide OpenSnap, Snap…, Preferences…, Quit]; tooltip "OpenSnap".
* Hint copy (WP6): rewritten in our words, `°` fixed, "Command" spelled out.
* Window/Finder names: `CFBundleName/DisplayName = OpenSnap`, executable `OpenSnap`, document type "OpenSnap Drawing" (`.opensnap`), no “Original Skitch Drawing”.

**Files.** `App.swift` (menus L918-972, Toolbox L675-715, status item L424-436, about L2176), `Info.plist`, `OriginalHintMessages.swift`, `Canvas.swift` (context menus L135,1847-1849), `TextStyleForm.swift`, `GlobalHotkeys.swift`, `MenuSymbols.swift`, `GeneralPreferencesForm.swift`.
**Ownership.** `App.swift` serial — do **inside WP4** (it already owns every rename in App.swift) to avoid a second App.swift pass.
**Prerequisites.** WP4 for names; T5 for the icon.
**Tests.** String gate (T14) over menus/Toolbox/status/About/Info.plist; `MenuParityTests`: Toolbox items ⊆ main-menu items by action; every menu item has a symbol or is exempt; About options dictionary contains no "Skitch"; status icon template.
**Risks.** Renaming menu titles breaks `AppSafetyTests` lookups by title (328 KB file, many string expectations) — budget the test churn inside WP4.
**Estimate.** 1 d on top of WP4.

---

## T13 — Declassic / asset removal / identity / migration (mapped to WP0–WP7 with owner §4 overrides)

| WP | Status & owner-§4 changes | Foundation or polish |
|---|---|---|
| **WP0** land toggle | **Done** (`88d8865`, `f19dfde`, `4b2ae0f` on main). Nothing to do. | – |
| **WP1** assets in shared code | Countdown → drawn digits (plain text, T10 styles it); cursor → system hand cursors; status icon → drawn template (T5, but WP1 owns removing the PNG load `App.swift:430-431`); **sounds: delete outright** (not system sounds): remove `OriginalSoundEffects` (`OriginalGeneralPreferences.swift:63-81`), `playOriginalSound`/`onSound` callbacks (`App.swift:446,1847`, `Capture.swift:368,787`, `Canvas.swift:314,734-752`), the "Play sounds" row and key; ChromeIcons PNG fallback; slider PNG; delete `ToolButton.swift` | **Foundation blocker** (clean-clone build) |
| **WP2** Classic removal | as plan, **plus** delete the welcome document path (`App.swift:321-322,355-364`, `FirstLaunchDone`, `firstLaunchDocumentURL`), un-gate Appearance, delete Relaunch, set macOS 26, remove `@available(macOS 26, *)` | **Foundation blocker** |
| **WP3** build/runners/gates | as plan; `OPENSNAP_*`; `macosx26.0`; drop 11 `original/` copies (`build.sh:14-18,36-43`); `eye-dump.sh` & `test-native-startup.py` fixtures → synthetic `.opensnap` generated by the tests (no welcome doc exists any more); add the T14 gates | **Foundation blocker** |
| **WP4** rename + migration | `OpenSnap` ids (INV §13 table); **new native `.opensnap`** (Q2) replacing `.skitch/.skitchredux` for users; remove `com.plasq.skitch.document` doc type + imported UTI + `Original Skitch Drawing`; Open/Save/drag/History formats lose "Skitch"; `Sources/Migration/` holds the *only* readers of the old SVG-Skitch and JSON formats and converts the owner's 58 History `.skitch` files; copy-never-move for folder, defaults domain, Keychain; marker in the **new** folder only | **Foundation blocker** |
| **WP5** welcome doc + fixtures | **Cancelled by owner D5** (no welcome doc). Re-scoped: delete every `original/` probe (INV §6.3 incl. the two hard failures `AppSafetyTests.swift:493,552`), rewrite `OriginalHintMessagesTests` as a table test, generate synthetic documents in tests | Foundation (test hygiene) |
| **WP6** copy/docs/analysis | as plan + rewrite hint copy; README says once, factually, that the project began as a Skitch-inspired rebuild; untrack `analysis/*.json`; delete `check-dispositions.py`, `decompile.sh`, `ExportDecompiled.java` | Polish (but gate `check-skitch-strings.py` must be green before 0.4.0) |
| **WP7** verification | clean clone: build, `tools/test.py`, startup smoke, eye-dump, release; migration verified against a **copy** of the owner's store (read-only, never the live folder) | Foundation (exit gate) |

**What must wait for which WP**
* T1/T3 sweeps, T6, T9, T11, T12 touch `App.swift` and the deleted Classic code → **after WP2 (and WP4 for string-bearing lines)**. Doing them earlier edits ~17 font rows and 26 constraints that WP2 deletes.
* T4/T6 (GlassChrome/ModernEditorChrome) → after WP1 + WP2 (they remove `classicArtworkName`, availability gates, `ToolButton`).
* T5 → after WP1; T10 styling → after WP1 (drawn digits).
* Token *definitions* (T1/T2/T3 files), `PaletteTests`, `ViewTreeAudit` helper, and the T14 gate scripts have **no prerequisites** and can be built first, in parallel with WP1–WP3.

**Foundation blockers (in order)**: WP3 build/gates → WP1 shared assets/sounds → WP2 Classic/Appearance/welcome → WP4 identity + `.opensnap` + migration → WP5' fixtures → (visual work) → WP6 → WP7.
**Polish**: T1–T12, README/HANDOFF prose, analysis retirement.

**Migration safety spec (what WP4 must prove).** `Migration.run(oldSupport:newSupport:oldDefaultsDomain:newDefaults:secrets:)` is pure over injected URLs/defaults/secret store and:
1. builds the new tree in a temp sibling and `rename`s it into place atomically (a crash leaves either nothing or a complete tree);
2. never writes into the old tree (no marker there);
3. converts each old `.skitch/.skitchredux` History document to `.opensnap` via the migration-only readers and keeps the old file; per-document failure is recorded, not fatal;
4. copies defaults keys (INV §13 list) from `com.shoemoney.skitch-redux` into the new domain, mapping `DragFormatChoice` → `OpenSnap.imageFormat`, dropping `appearanceStyle`, `disableSounds`, `skitchInSnap` → `includeAppInSnap`, and leaves the old domain intact;
5. for each destination id copies Keychain items from `SkitchRedux.CustomPublishing` to `OpenSnap.Publishing` (`allowMissing: true`), leaves old items, and states in the status line that macOS may ask once per item (ad-hoc signed build);
6. is idempotent (marker `Migration.v1.json` with counts + hashes in the new folder; re-run is a no-op).

---

## T14 — Regression tests and gates

All gates run from `tools/test.py` (new rows) and the clean-clone job; each gate lists **what makes it fail today**.

| # | Gate | Implementation | Fails today because |
|---|---|---|---|
| G1 | **Clean-clone build** with `original/` absent | `tools/check-clean-clone.sh`: `git clone --no-hardlinks` to a temp dir, assert `! -e original`, `sh tools/build.sh`, `python3 tools/test.py`, `python3 tools/test-native-startup.py`; `build.sh` must not mention `original/` | first `cp` at `tools/build.sh:14` aborts (`set -eu`) |
| G2 | **No-original-assets byte match** | `tools/check-no-original.py`: (a) static: `original/`, `Skitch.app` absent from `Sources/ tests/ tools/ build.sh`; (b) when a local `original/Skitch.app` exists, SHA-256 every regular file there and fail if any file in the built bundle matches; (c) bundle `Resources` allow-list = {`OpenSnap.png`, `Assets.car`, `OpenSnap.icns`, subset fonts only in dev builds}; run from `release.sh` before `codesign --verify` | bundle contains 60+ original PNGs, 9 `.m4a`, `firstlaunch.skitch` |
| G3 | **No "Skitch" in user-visible strings** | static: regex `/skitch/i` over string literals in `Sources/` outside an allow-list (`Sources/Migration/`) + `Info.plist` values; dynamic: `OpenSnap --dump-strings DIR` walks every window/menu/status item/tooltip/AX label/placeholder/alert text built by the audit harness and writes JSON; `tools/check-user-strings.py` asserts none matches `/skitch|openskitch/i` | 27 string sites + `Info.plist` (INV §7) |
| G4 | **Font-floor test walking the live tree** | `tests/ViewTreeAudit.swift` + `ViewTreeAuditTests`: build main window (default, minimum, Frame), Prefs (each tab), History, Photos sheet, Resize (3 modes), Hotkeys, Destinations (list + each protocol), Export accessory, Fonts accessory, Overview panel, color popover; collect `NSTextField/NSButton/NSPopUpButton/NSSegmentedControl/NSTextView/NSTableView(cell)` fonts, `NSMenu` item fonts (recursively), `NSAttributedString` `.font` spans of custom-drawn text via `Typography` registry; assert every readable font ≥ 18, controls ≥ 20 unless `caption`; plus the T1 source gate | no tree walker exists; 19 system-owned surfaces unchecked; custom-drawn text invisible |
| G5 | **Glass depth ≤ 1 and no glass over content** | `GlassDepthTests` (T4): no glass ancestor/descendant of any `NSGlassEffectView`; count budget; frame-intersection with canvas well at 3 sizes; Reduce-Transparency plates | 26 surfaces; fallback absent |
| G6 | **No emoji / decorative glyphs** | static: scan every string literal (incl. `\u{…}`) for Emoji_Presentation, U+2190–21FF arrows (allow `⇧⇥⌘⌥⌃`), U+2600–27BF, U+2B00–2BFF, U+F8FF, U+00BA, ASCII `...` in titles; dynamic: same set over the dumped strings | `º`×2, U+F8FF, `...`×4 |
| G7 | **Visual snapshot / eye-dump gate** | `tools/eye-dump.sh` rewritten: one style, isolated support, synthetic fixture, PNG + `layout.json` for S01–S28; `tools/check-eye-dump.py` asserts: image non-empty, no control frame clipped (from JSON), every labelled control's measured text colour vs sampled background ≥ 4.5:1, window sizes within token minima; **pixel baselines only for deterministic non-glass surfaces** (sheets, Prefs, History with fixed fixtures) using a perceptual-hash tolerance; glass regions masked (wallpaper dependent) | script is Classic-looped and requires `original/`; asserts nothing |
| G8 | **Migration safety** | `tests/MigrationTests.swift` (new suite `migration-tests`): temp `CFFIXED_USER_HOME`; synthetic old tree (History index + several `.skitch` made by the test encoder, `destinations.json`, a fake secret store, a scratch defaults suite) — **never the real store**; assert old-tree manifest `(path,size,mtime,sha256)` is byte-identical after run; new tree complete; documents decode and equal source; idempotent; crash-injection (throw after N copies) leaves no partial new tree; old Keychain items still readable; unknown/corrupt documents reported; plus extend the real-store guard (`tools/test.py:18-37`) to hash **both** `SkitchRedux/` (whole folder, not just `Publishing/`) and `OpenSnap/` | no migration exists; guard watches only `SkitchRedux/Publishing` |
| G9 | **Token/literal guards** | `tools/check-tokens.py`: font/constraint/radius/colour literals outside `DesignTokens.swift` (allow-lists for annotation content, geometry structs, `overlay.*`) | ≈ 124 fonts, ≈ 100 constants, 10 radii |
| G10 | **Accessibility audit** | `AccessibilityAuditTests` (T7) | unlabeled legacy labels, no key loop, no motion gating |
| G11 | **Skip budget** | `tools/test.py` fails if any suite prints `SKIP`/`SKIPPED` for a reason other than "macOS < N" (so silent skips for missing FA fonts / `original/` cannot hide the real Modern look) unless `OPENSNAP_ALLOW_SKIP=fa` is set for a licence-free CI | 7 suites skip silently today |
| G12 | **Bars fit, no rail, canvas reaches the margin** (T15 §h tests 1-7) | `GlassChromeTests` + `AppSafetyModernCases`: no rail view/constraint/`Metrics` member; `scrollView.maxX == chrome.maxX − 12` at 980/1024/1280/1440; every relocated control visible, non-overlapping and inside its bar at 980 × min height in normal **and** Frame mode; the width-budget oracle (`needed ≤ U` computed from live `Metrics`); tool group balanced and Snap stable; canvas centred; Frame capture rect ⊂/== hole; `layout.json` from G7 carries the same frames at the 4 widths | the rail, its 64-pt reservation and `scrollView.trailing == rightRail.leading − 8` exist (`ModernEditorChrome.swift:336-337,401-413`); the Frame-mode top bar would need 986 pt with 48-pt tools |

**Tests that cannot fail today and what replaces them** (INV §14): `modernCanvasBleed` (feature off by default) → deleted with the bleed; "accessibility injected into every surface" input-mirror assertions → replaced by G5(4) behavioural plates; `modernControlStrings`' live Classic baseline → literal expectations; countdown suites skipped without art → run on the drawn view (T10); `FontAwesomeIconsTests` self-made PNG → deleted with the PNG chain.

---

## T15 — Owner-required layout: remove the right rail (P1)

**Source of the requirement.** `docs/design/user-feedback.md` (owner, 2026-10-09 10:24 CDT): *"the buttons extending the right side … could be relocated on the top bar or bottom and we could eliminate all that blank space."*
Required outcome: no permanent rail and no reserved blank column; every rail action keeps its keyboard and accessibility behaviour at ≥ 18 pt (default 20 pt) text; the freed width goes to the canvas; Frame Cancel and canvas centring are preserved; the layout fits at the minimum window width. **This is a spec only; no code was changed.** It lands inside the current custom `ModernEditorChrome` bars and does **not** wait for Q3 (§0).

**Evidence status at the time of writing.** `docs/design/evidence/2026-10-09/layout-width-budget.json` did **not** exist yet (the directory contained only `source-font-sizes.json` one level up), so every text-dependent width below is an ESTIMATE; reconcile the four figures in §k against that file when it lands and re-run §b (it is arithmetic on the `Metrics` constants plus four measured widths).

**Summary of the recommendation** (all numbers derived below; **ESTIMATE** = depends on text width, to be superseded by `docs/design/evidence/2026-10-09/layout-width-budget.json`):

| Bar | Left → right | Fits at 980? | Slack at 980 |
|---|---|---|---|
| **Top** | `[Hide][Toolbox][Photos]` · `[Snap / Snap Frame][Cancel*]` · 10 tools · `[Color][Size pill][Font]` | **yes, with the 44-pt tool token** | normal **64**, Frame **10** pt (exact, no text involved) |
| **Bottom** | `[Undo][Wipe]` · `[Zoom][Resize…]` · `[☐ Original size*]` status (+ size/bytes) · `[Save][History]` · `[PNG\|JPG][Drag][Upload]` | **yes** | status gets **291 pt** (141 pt while the Original-size checkbox is shown) — **ESTIMATE**; slack over the 120-pt status floor 171 / 21 pt |

`*` conditional: Cancel only in Frame mode; Original size only when `isLargeShot` (`AppViewport.swift:64-79`).

### a. Current state at `4b2ae0f` (what has to change)

| Piece | Where | What it does today |
|---|---|---|
| Rail creation | `ModernEditorChrome.swift:311-337` | `captureGroup` (Snap + Cancel, vertical, `:333`), `drawingGroup` (Color, Font, Size, `:334`), `historyGroup` (Undo, Wipe, `:335`) are added to `let rightRail = NSView()` (`:336-337`). |
| Rail width reservation | `GlassChrome.swift:416` `Metrics.rightRailWidth = 64` (+ dead `railWidth = 64`), used at `ModernEditorChrome.swift:402,419` | `rightRail.widthAnchor == 64`; `rightRail.trailing == chrome.trailing − 12` (`:401`); top/bottom pinned between header and footer with gap 8 (`:403-404`). |
| Canvas ↔ rail | `ModernEditorChrome.swift:411-413` | `scrollView.leading = +12`, **`scrollView.trailing == rightRail.leading − 8`**, `scrollView.top/bottom == rightRail.top/bottom`. |
| Bleed inset | `ModernEditorChrome.swift:417-419` | `bleed.additionalSafeAreaInsets.right = margin + rightRailWidth + gap` (= 84). The bleed is off by default (`GlassChrome.swift:437`), but the constant must go with the rail. |
| Canvas border | added last at `:380`; frame set in `AppViewport.swift:183-184` = canvas rect inset −8 (`CanvasBorderView.swift:10`), hidden in Frame/Actual/clipped | Follows the *canvas*, not the viewport, so it is rail-agnostic; it only needs ≥ 8 pt of free chrome beside the viewport — the new 12-pt margin provides it. |
| Centring | `CenteringClipView` `ModernEditorChrome.swift:427-460`, installed `:245` | Per-axis centring of a smaller document; larger documents pan exactly as `NSClipView`. Rail-agnostic. |
| Frame hole | `FrameChromeView.draw` `App.swift:16-23`: hole = `scroll.convert(scroll.bounds, to: self) ∩ bounds` | Cleared + even-odd excluded when `showsCanvasHole` (`enterFrame` `App.swift:1911`); also `scroll.drawsBackground = false` (`:1912`), `canvas.framePreview = true` (`:1913`). The hole is **exactly the scroll view frame**, so it grows with the viewport. |
| Frame capture rect | `performFrameSnap` `App.swift:1951-1962` | `canvas.visibleRect` → window → screen. Equals the viewport when the canvas fills it; equals the canvas (centred inside the hole) when it is smaller. Rail-agnostic, but it moves with the viewport. |
| Window size | `App.swift:717-718`: content 1024 × 740, `minSize` 900 × 640; `App+ModernChrome.swift:48` raises min width to `minimumWindowWidth = 980` (`ModernEditorChrome.swift:51`, "measured 976") | Frame height min 640; title bar measured 32 pt (`windowFrame` 1024 × 772 for a 740 content in `build/startup-smoke-*/layout.json`, Classic shell, same style mask) ⇒ **min content height 608**. |
| Vertical budget | header `top 4 + 44`, gap 8; footer row 44 + bottom 8, gap 8 (`:219-220,388-396`) | Viewport height = content − 116 ⇒ **492 pt at min (608), 624 at default (740)**. Unchanged by T15. |
| Size control | vertical `BezelSizeSlider` 36 × 96 (`ModernEditorChrome.swift:320-330`; class `BezelDrawingControls.swift:103-209`) | Value mapped on **y**; `pointForValue` `:136`. |
| Dependents of viewport width | `maximumNormalCanvas` `AppViewport.swift:64-73` (`chrome = window.frame − scroll.frame`), `sizeNormalWindowToCanvas` `:213-218`, `fitCanvasToWindow` `App.swift:1176-1183` | All derive from `scroll.frame`, so they self-adjust: a window sized to a given canvas becomes **72 pt narrower**; "large shot" thresholds shift by 72. Tests that hard-code chrome widths must be re-derived (see §h). |

### b. Width budget (points; source metrics; text-dependent items marked ESTIMATE)

Constants: margins 12 + 12 ⇒ **usable U = W − 24**; `surfaceSpacing` 6 inside a group; `toolSpacing` 4 between tools; minimum gap between groups 12 (`Metrics.groupGap`, new). Sizes: tool 48 × 40 (proposed **44 × 40**), icon 48 × 36, Toolbox 60 × 36, Snap 56 × 44, Cancel 48 × 36. Group stacks have no padding (`GlassChrome.group` `:452-462`). The merged PNG | JPG toggle is a 20-pt `NSSegmentedControl(.capsule)` inside a glass capsule (`App+ModernChrome.swift:79-85`, `ModernEditorChrome.swift:340-353`).

**Top bar — all components are fixed sizes, so these sums are exact (not estimates).**

| Group | Composition | Width |
|---|---|---|
| A leading | Hide 48 + 6 + Toolbox 60 + 6 + Photos 48 | **168** |
| B capture | Snap 56 · Frame: 56 + 6 + Cancel 48 | **56 / 110** |
| C tools, token 48 | 10 × 48 + 9 × 4 | **516** |
| C tools, token **44** | 10 × 44 + 9 × 4 | **476** |
| D annotation | Color 48 + 6 + Size pill 48 + 6 + Font 48 | **156** |
| gaps | A–B, B–C, C–D, each ≥ 12 | **36** |

| Window W (U) | Normal, tool 48 | Frame, tool 48 | Normal, tool **44** | Frame, tool **44** |
|---|---|---|---|---|
| sum needed | 168+56+516+156+36 = **932** | 168+110+516+156+36 = **986** | 168+56+476+156+36 = **892** | 168+110+476+156+36 = **946** |
| **980** (956) | slack **+24** | slack **−30 ✗ overflows** | slack **+64** | slack **+10** |
| **1024** (1000) | +68 | +14 | +108 | +54 |
| **1280** (1256) | +324 | +270 | +364 | +310 |
| **1440** (1416) | +484 | +430 | +524 | +470 |

For reference, today's top bar needs 976 (leading 168 + 12 + half of the 592-wide tool-and-Resize row, ×2) — `minimumWindowWidth = 980` is that figure rounded up; T15's worst case (Frame, token 44) needs 970 and the bottom bar ≈ 959 (935 + 24, below), so **980 stays the minimum and is now a derived floor**.

**Bottom bar** (ESTIMATE items: zoom surface Z ≈ 108 = popup fitting width of the widest *face* text "100%" at 20 pt incl. chevrons ≈ 100 + holder inset 4 + 4; toggle surface t ≈ 143 = two capsule segments "PNG"≈70 / "JPG"≈65 + holder inset 8; checkbox C ≈ 138 + 12 spacing = 150; status floor S = 120 = design floor, see below):

| Group | Composition | Width |
|---|---|---|
| UW | Undo 48 + 6 + Wipe 48 | **102** |
| ZR | Zoom 108 (ESTIMATE) + 6 + Resize 48 | **162** |
| SH | Save 48 + 6 + History 48 | **102** |
| OUT | toggle 143 (ESTIMATE) + 6 + Drag 48 + 6 + Upload 48 | **251** |
| gaps | UW–ZR, ZR–status, status–SH, SH–OUT, each ≥ 12 | **48** |
| fixed total | 102 + 162 + 102 + 251 + 48 | **665** |

| W (U) | Room for status text (no checkbox) | Room with checkbox shown (− 150) | Slack over the 120-pt floor (no checkbox / checkbox) |
|---|---|---|---|
| **980** (956) | **291** | **141** | +171 / **+21** |
| **1024** (1000) | 335 | 185 | +215 / +65 |
| **1280** (1256) | 591 | 441 | +471 / +321 |
| **1440** (1416) | 751 | 601 | +631 / +481 |

* **Status text.** `dragSizeLabel` (≈ 170 pt, 18 pt, was a separate element) is **merged** into the status string: `"<Tool> · <Saved|Unsaved changes> · <W> × <H> · <size>"` ≈ 395 pt at 18 pt (ESTIMATE, 45 chars × ≈ 8.8). Tail truncation drops the byte count first and never the state or an upload message. It fits whole at ≥ 1280; at 980 it truncates (the full text stays in `status.toolTip` and the AX value); the pixel size is also what T8's window subtitle shows.
* **Zoom face.** Today the zoom popup is fixed at 160 pt (`ModernEditorChrome.swift:363`) because its selected item can be a dynamic title such as `"Output · 100%"` (`App.swift:1184-1188`, labels Fit/Frame/Actual/Normal/Output) that would be ≈ 166 pt wide. A "fitting width" popup therefore needs the **face to show the percentage only** (`"83%"`); the mode word moves to the item's `toolTip` and the popup's AX value (`"Fit, 83%"`). That is a deliberate, owner-visible text change (no test asserts the old titles — grep for `Fit ·`/`Output ·` finds only `App.swift`). **Decision needed (D-T15-1).** If rejected, keep 160: ZR becomes 222, the 980-pt status room falls to 231 (81 with the checkbox ✗ below the floor) and the checkbox must take lever 3 below.
* **Frame hint.** `modernFrameStatusFits` (`AppSafetyModernCases.swift:562-575`) requires "Frame: position the window, then Snap" (≈ 310–330 pt ESTIMATE) to fit at 1024 where the room is 335 pt (no checkbox is shown in Frame mode): **a razor-thin ±20 pt margin**. Lever: shorten to "Frame: position, then Snap" (≈ 230 pt) with the long text in the tooltip, which the test already allows.

**Fit levers, in the order to pull them (smallest cost first).**

1. **Tool token 48 → 44** (`GlassChrome.Metrics.toolButton`, one constant, consumed only at `ModernEditorChrome.swift:286`). Gains 40 pt on the top bar; tiles stay 44 × 40 ≥ the 36-pt hit minimum; glyphs stay 22 pt. *Cost:* tiles are 4 pt narrower than the 48-wide icon pills beside them (visual rhythm), one metrics assertion (`GlassChromeTests.swift:568`). **Chosen.**
2. Zoom face = percentage only (above): gains 52 pt on the bottom bar. **Chosen** (D-T15-1).
3. *If the measured bottom bar overflows* (zoom or toggle wider than estimated by > ≈ 20 pt): turn the **Original size** checkbox into a 48-pt icon toggle beside Drag (saves ≈ 102 pt), its AX label/tooltip unchanged. Not applied by default.
4. *If the top bar still overflows in Frame mode after real measurement:* Cancel takes **Photos' slot in Frame mode only** (Photos hides, saves 54; Photos stays on File ▸ Photos…). Cost: a control disappears in one mode.
5. *Last resort:* Hide moves into the Toolbox menu (saves 54; Hide is a frequent command with ⌘M, so discoverability suffers), or the minimum window width becomes 1024 (Frame token-48 slack +14). Both worse than 1–4.

**Alternative mapping (rejected).** Top: `[Hide][Toolbox][Photos] · [Snap][Cancel] · tools · [Undo][Wipe]`; bottom: `[Color][Size][Font] · [Zoom][Resize] · status · [Save][History] · [PNG|JPG][Drag][Upload]`.
Top = 168 + 56/110 + 516/476 + 102 + 36: token 48 → **878 normal / 932 Frame (slack 78 / 24 at 980)**, token 44 → 838 / 892 (118 / 64) — fits without the lever. Bottom = 156 + 162 + 102 + 251 + 48 = **719**: status room at 980 = **237** and **87 with the checkbox ✗ (below the 120 floor by 33)**; fits at 1024 only (131 with checkbox). **Why the primary mapping wins:** (1) *Proximity:* the pen attributes (Color, Size, Font) sit next to the tools they modify; the alternative parks them a full canvas-height away from the tool row; (2) *grouping:* top = capture + annotation (what you do *to the picture*), bottom = document and output (Undo/Wipe/zoom/resize/save/history/export) — the owner's own starting arrangement; (3) *budget:* the alternative overflows the bottom bar at the 980-pt minimum whenever Original size is visible, the primary does not; (4) *risk:* Wipe is destructive and in the alternative it would sit at the far end of the top bar next to the tool row it is easily mis-hit from; in the primary it sits beside Undo, away from the tools; (5) Undo/Wipe in the top bar costs the 44-pt token nothing but also gains nothing the primary lacks.

### c. Verification of the proposed mapping (with arithmetic) and the exact structure

The orchestrator's mapping **is correct** with two additions: (i) the 44-pt tool token (without it, Frame mode at 980 needs 986 > 956), and (ii) the zoom face shrink (D-T15-1) or the checkbox lever. Arithmetic: top Frame/token 44 = 168 + 110 + 476 + 156 + 36 = **946 ≤ 956 (slack 10)**; bottom (checkbox shown) = 665 + 150 + 120 = **935 ≤ 956 (slack 21, ESTIMATE)**.

**Top bar construction** (`ModernEditorChrome.build`, replaces `:254-309` and the rail `:311-337`):
* Four `GlassChrome.group`s: `GlassHeaderLeading` (A), **`GlassCaptureGroup` horizontal** (B: `[snapSurface][cancelSurface]`, `NSStackView.detachesHiddenViews` default `true` collapses Cancel's slot outside Frame mode; Cancel's surface already hides with its button — `AppSafetyModernCases.swift:645`), `GlassToolBar` (C: 10 tools only, **Resize removed**, so `resizeSeparation` and `stack.setCustomSpacing` at `:293` are deleted), **`GlassAnnotationGroup`** (D: Color, Size pill, Font; replaces `GlassHeaderTrailing`).
* Constraints: A pinned leading; B.leading = A.trailing + 12 (fixed — Snap does not move when Cancel appears); D pinned trailing; **C is centred between B.trailing and D.leading** using two `NSLayoutGuide`s with `spacer1.width == spacer2.width`, each `≥ 12`. Exact window-centring of the tool row is *not* possible with an off-centre capture group (it needs U ≥ 1080 in Frame mode), so the old priority-750 `centerX` constraint (`:298-299`) is retired. Cost: the tool row sits ≈ 40 pt right of the window centre at 1440 (67 pt in Frame mode) and **shifts 27 pt (half of Cancel's 54) when Frame mode adds Cancel** — Frame is entered from the menu/hotkey, not from a pointer on this bar, so there is no click-through risk.
* Header remains 44 pt high (Snap is 44).

**Bottom bar construction** (replaces `:339-376`): `footer` (44 pt) holds four glass groups and one plain row: `GlassUndoWipeGroup` (pinned leading), `GlassViewGroup` `[zoom capsule][Resize]` (leading = prev + 12), `statusRow` = `[Original size checkbox (conditional)][status]` between `GlassViewGroup.trailing + 12` and `GlassSaveGroup.leading − 12` (`status` hugs low, compresses to 0), `GlassSaveGroup` `[Save][History]`, `GlassFooterRow` `[toggle][Drag][Upload]` (pinned trailing, unchanged). Zoom is wrapped in a glass capsule through the same `ControlHolderView` used for Toolbox/format (`:5-25`) so it matches its neighbour; it is `isBordered = false` inside the capsule and is sized once from the widest **face** text (the loop at `:345-350` is the pattern).

### d. Stroke width: from a vertical 36 × 96 slider to a pill + popover

**Problem.** `BezelSizeSlider` maps value on the y axis (`pointForValue` `:136-138`, `setValueForPoint` `:171-174`), is 96 pt tall (`ModernEditorChrome.swift:325-326`) and cannot sit in a 44-pt bar; rotating it or shrinking it is excluded by the owner.

**Spec.** Keep `widthControl` as the single model object (`App.swift:217`: `let widthControl = BezelSizeSlider(frame: .zero)` stays; so do `target/action = changeWidth(_:)` `App+ModernChrome.swift:59`, `onBegin/onEnd` `:60-64`, `trackHint` `:122`, `syncDrawingControls` `App.swift:1046-1049`, `endTracking()` callers `App.swift:387,493`). Add a third style:

```swift
// BezelDrawingControls.swift
final class BezelSizeSlider: NSControl {
  enum Style { case classic, pill }                    // .modern (vertical vector) is deleted; .classic dies with WP1/WP2
  // pill: 48 × 36 glass-wrapped control (iconPill), draws a horizontal rounded line, length 24, thickness = value (1.5…12 pt),
  //       labelColor, + 2 pt focus ring; role .slider; value/min/max as today
  private(set) var popover: NSPopover?
  var isPopoverShown: Bool { popover?.isShown == true }
  func showPopover()          // guards: isEnabled, window != nil, no attached sheet — the same guards as onBegin (App+ModernChrome.swift:61)
  func dismissPopover()       // performClose(nil); also calls endTracking() so an open undo group is closed
  // gesture API used by BOTH the pill (keyboard/AX) and the popover track — one code path, one undo grouping:
  func beginGesture() -> Bool            // = existing private begin()
  func trackValue(fraction: CGFloat, modifiers: NSEvent.ModifierFlags)   // fraction 0…1 → OriginalDrawingControls.size(raw, continuous: modifiers.contains(.shift))
  func endTracking()                     // unchanged
  func performValueChange(_:continuous:) // unchanged (preset buttons, keyboard, AX)
}
final class SizePopoverContent: NSView        // solid: layer.backgroundColor = NSColor.controlBackgroundColor (re-resolved in viewDidChangeEffectiveAppearance); NOT glass
final class SizeTrackView: NSControl          // horizontal track 288 × 36, 5 tick marks at OriginalDrawingControls.sizeSteps, 20-pt knob (accent), AX .slider
final class SizePresetButton: NSButton        // 5 × (48 × 36): draws the preset's line thickness; selected = accent @ 0.20 fill + 2 pt accent border (not colour alone)
```

* **Pill interaction.** Click or Space/Return → `showPopover()` (toggle), `NSPopover` `.transient`, `show(relativeTo: bounds, of: pill, preferredEdge: .minY)` (below the bar; AppKit flips if there is no room). Arrows on the focused pill (pill style only): **Right/Up = larger, Left/Down = smaller**, one preset step (2.625), Shift = 0.1 continuous, each press = `performValueChange` = one undo group (as `keyDown` `:197-204` today). The legacy inversion (Down = larger) was an artefact of the vertical layout and is **not carried over** (decision D-T15-2; the Classic `.classic` style keeps it until WP2 deletes it). `accessibilityPerformIncrement/Decrement` stay (`:134-135`, ±2.625). Optional, new: `scrollWheel` steps one preset per notch.
* **Popover content** (320 × 156 = 16 + 28 + 12 + 36 + 12 + 36 + 16): row 1 — "Size" (20 pt semibold) and the **numeric readout (20 pt, monospaced digits)** = `String(format: "%.0f", value.rounded())`, the same rounding as `sizeLabel` (`App.swift:1047`); row 2 — `SizeTrackView` (drag anywhere; **Shift = continuous, otherwise snaps to the five steps**, i.e. `OriginalDrawingControls.size(_, continuous:)` unchanged; double-click resets 6.75 as `mouseDown` `:189` does); row 3 — five `SizePresetButton`s (AX "Size 2/4/7/9/12", tooltips the same). No rotated or shrunken text; every control ≥ 36 pt tall.
* **Undo contract (must not regress).** Pointer drag on the track = `beginGesture()` on mouse-down (runs `onBegin` ⇒ `beginUndoGrouping`, `sizeUndoGrouping = true`, `App+ModernChrome.swift:60-63`), `trackValue` on drag (⇒ `changeWidth` ⇒ "Change Text Size" conversions registered *inside* the group), `endTracking()` on mouse-up (⇒ `onEnd` ⇒ `endDrawingSizeGesture`, `App.swift:1040-1043`) — **exactly one undo step per drag**. A preset click, a keypress and an AX increment each call `performValueChange` (begin → update → end) — one step each. `popoverWillClose`, `viewWillMove(toWindow: nil)` (existing `:205-208`), `toggleVisible` (`App.swift:493`) and `applicationShouldTerminate` (`:387`) all end tracking, so a popover dismissed mid-drag cannot leave a group open (**add `widthControl.dismissPopover()` next to those two `endTracking()` calls**).
* **Hover hint.** `trackHint(widthControl, owner: "drawing-size", actionTag 20)` (`App+ModernChrome.swift:122`) stays on the pill (the `HintTrackingView` overlay has `hitTest → nil`, `HintTrackingView.swift:8`, so clicks still reach the pill). Tooltip stays dynamic `"Size N"` (`App.swift:1049`).
* **Colour popover edge.** Color moves to the top bar, so its popover must open *below* it: `App.swift:1122` `preferredEdge: .minX` → `.minY`. The hover-open behaviour (`BezelHoverButton.onHover` → `drawingColorHover`) is unchanged.
* **UNVERIFIED (needs a capture):** whether the system popover frame is itself translucent on macOS 26 (only the *content* is solid here), and where AppKit places the arrow when the pill is 56 pt from the window edge.

### e. Canvas

* `scrollView.trailingAnchor == chrome.trailingAnchor − 12` (replaces `ModernEditorChrome.swift:412`); `scrollView.top == header.bottom + 8`, `bottom == footer.top − 8` (replace `:413`, which pinned them to the rail); `bleed.additionalSafeAreaInsets.right = margin` (replaces `:419`). Delete `rightRail`, its width/top/bottom constraints and the three vertical groups; delete `Metrics.rightRailWidth` and the dead `railWidth` (`GlassChrome.swift:416`).
* **Reclaimed width = rail 64 + gap 8 = 72 pt** (viewport width W − 96 → W − 24):

| W | viewport before → after | gain | share of window width |
|---|---|---|---|
| 980 | 884 → 956 | +72 (**+8.1 %**) | 90.2 % → 97.6 % |
| 1024 | 928 → 1000 | +72 (**+7.8 %**) | 90.6 % → 97.7 % |
| 1280 | 1184 → 1256 | +72 (**+6.1 %**) | 92.5 % → 98.1 % |
| 1440 | 1344 → 1416 | +72 (**+5.4 %**) | 93.3 % → 98.3 % |

  Height is unchanged (492 at min, 624 at default). A canvas that sat in an 884-pt viewport now has 36 pt more margin each side when centred.
* **Centring** — `CenteringClipView` is untouched; the equal-margin assertion (`AppSafetyModernCases.swift:194-207`, `abs(m.left − m.right) ≤ 1`) must hold at the new viewport, which is what makes it a real regression test.
* **Canvas border** — unchanged logic; with a canvas that exactly fills a 956-pt viewport the border extends 8 pt into the 12-pt margin (4 pt clear of the window edge): assert the border stays inside `content.bounds` at 980.
* **Frame mode** — the hole is the scroll-view frame, so it widens by 72 pt automatically; the 12-pt opaque strip at the right replaces an 84-pt one. The capture rect (`canvas.visibleRect` → screen, `App.swift:1956-1960`) equals the viewport when the canvas is ≥ the viewport on both axes and equals the centred canvas rect when smaller; **both are asserted to lie inside the hole and the former to equal it**. Recommended 3-line refactor to make this testable without a capture device: extract `var frameViewportScreenRect: NSRect` from `App.swift:1956-1960` and let `performFrameSnap` use it.
* Dependents re-derive (`maximumNormalCanvas`, `sizeNormalWindowToCanvas`): windows sized to a canvas become 72 pt narrower; "large shot" turns on later by 72 pt; `fitCanvasToWindow` fits a larger viewport. Re-run `WindowSizingTests`, `AppSafetyTests.swift:2074-2120,2884,2963-2995`, `TextStyleFormTests.swift:225`.

### f. Preserved-behaviours checklist (every action keeps its selector, shortcut, AX label, tooltip and hint)

Shortcuts are read from the live main menu by `ModernEditorChrome.menuShortcut(for:)` (`:130-147`), so they follow the menu; "—" = the menu item has no key equivalent.

| Action | Selector (target = AppDelegate) | New location | Shortcut | AX label (VoiceOver) | Tooltip | Hover hint |
|---|---|---|---|---|---|---|
| Hide | `vanish` (→ `toggleVisible`) | top A, 1st | ⌘M (Window ▸ Minimize) | "Hide" | "Hide (⌘M)" | – |
| Toolbox | popup, items copied from main menu | top A, 2nd | per item | "Toolbox" | – | – |
| Photos | `showPhotos` | top A, 3rd | — | "Photos" | "Photos" | – |
| Snap / Snap Frame | `snapButtonPressed`; **alternate** `fullscreenSnap` (right/Control-click via `alternateTarget/Action`, `App+ModernChrome.swift:114-115`); Frame ⇒ `performFrameSnap` (Shift = timed) | top B, 1st (primary 56 × 44, the primary command) | ⌘1 Crosshair / ⌘4 Frame are *menu* actions (`screenSnap`/`frameSnap`), so the tooltip shows none — unchanged | "Snap" / "Snap Frame" (`syncSnapPresentation` `:184-190`) | `snapToolTip` / `snapFrameToolTip` (`:43-44`) | – |
| Cancel (Frame only) | `cancelFrame` | top B, 2nd, right of Snap; present only while `frameMode` | — | "Cancel" | "Cancel" | – |
| 10 tools | `chooseTool(_:)` (identifier = tool id) | top C, archive order, 44 × 40 | per tool as today | "Select", "Brush", … | "<Id> tool" | `OriginalHintMessages.hover(tool:)`, owner `tool-<id>` |
| Color | `showDrawingColors(_:)`; hover-open `drawingColorHover`; **Shift ⇒ canvas background** (`applyChosenColor`) | top D, 1st | — | "Drawing colors" + RGBA value (`App.swift:1062`) | "Color: hover for original preset colors; hold Shift to change the canvas background" (`ModernEditorChrome.swift:228`) | presets 100–110 (`App.swift:1113`) |
| Size | `changeWidth(_:)`; `onBegin/onEnd` undo grouping | top D, 2nd (pill → popover, §d) | arrows on the focused pill; Space/Return opens | "Drawing size" (`.slider`, value) | "Size N" (dynamic) | tag 20 `drawing-size` |
| Font | `chooseFont` | top D, 3rd | — (Text ▸ Font…) | "Font" | "Font" | – |
| Undo | `undo` | bottom UW, 1st | ⌘Z | "Undo" | "Undo (⌘Z)" | – |
| Wipe (+ **Blank/Clear/Wipe** stage retitle, `updateWipeButton` `App.swift:1201-1208`, found by action) | `wipe` | bottom UW, 2nd | — | "Blank"/"Clear"/"Wipe" (live title) | same | tag 50 `wipe` |
| Resize… | `resize` (disabled in Frame/Actual, `AppViewport.swift:176`) | bottom ZR, 2nd | — | "Resize…" | "Resize…" | – |
| Zoom | `changeZoom(_:)` | bottom ZR, 1st (glass capsule) | — | "Canvas zoom" (+ value "Fit, 83%") | "Canvas zoom" | – |
| Save to History | `saveHistory` | bottom SH, 1st | — | "Save" | "Save to History" | – |
| History | `showHistory` | bottom SH, 2nd | — | "History" | "History" | – |
| Upload | `share(_:)`; **right-click menu** from `configureWebpostButton` (`App.swift:1620-1627`, `showMenuOnLeftClick = false`) | bottom OUT, 3rd (unchanged) | — | "Upload to destination" | "Upload" | – |
| PNG \| JPG, Drag well, Original size | `changeDragOptions(_:)`; drag session | bottom OUT / status row (unchanged) | – | "Image format" / "Drag Me" / "Drag out at original size" | as today | tag 40 (drag) |

**Key-view / VoiceOver order.** After T15 the geometric default loop is top bar left→right, canvas, bottom bar left→right, which is also the subview order of `header`, `scrollView`, `footer` (keep that z-order; the canvas border stays last). The Size and Color popovers are entered by Return/Space and return focus to their pill/swatch.

### g. Per-action destination table

| Control | Was | Now | Why |
|---|---|---|---|
| Snap / Snap Frame | right rail, 1st (vertical capture group) | **Top bar, group B, after Photos** | capture is the primary verb; keeps the 56 × 44 primary visually prominent beside the tools |
| Cancel | right rail, under Snap (Frame only) | **Top bar, group B, right of Snap** | its pair; the group collapses to Snap alone outside Frame mode |
| Color | right rail, drawing group | **Top bar, group D, 1st** | attribute of the pen; next to the tools it modifies |
| Size | right rail, vertical 36 × 96 slider | **Top bar, group D, 2nd — 48 pt pill + popover** | needs no vertical space; value visible in the glyph (§d) |
| Font | right rail, drawing group | **Top bar, group D, 3rd** | text-tool attribute |
| Undo | right rail, history group | **Bottom bar, group UW, 1st** | document history; away from the tool row |
| Wipe | right rail, history group | **Bottom bar, group UW, 2nd** | destructive, beside Undo, away from the tools |
| Resize… | top bar, tool-group tail (`resizeSeparation` 28) | **Bottom bar, group ZR, after Zoom** | an *image* operation, not a drawing tool (the code comment at `GlassChrome.swift:412` says as much); frees 76 pt (48 + 28) from the tool row |
| Save to History, History | top bar trailing | **Bottom bar, group SH** | document/output verbs; balances the bottom bar and keeps the top bar to capture + annotation |
| Zoom | status row, plain popup 160 pt | **Bottom bar, group ZR, 1st, glass capsule, face = percentage** | adjacent view/size controls; width lever |
| `dragSizeLabel` | status row, separate 18-pt label | **merged into the status text** (no on-screen element) | saves ≈ 170 pt; the info survives in the status, tooltip and (T8) window subtitle |
| Original size checkbox | status row | status row, first element, only when `isLargeShot` | unchanged behaviour; lever 3 if over budget |
| PNG \| JPG, Drag, Upload | footer, trailing | unchanged | already last |
| Hide, Toolbox, Photos | top bar leading | unchanged (group A) | – |

### h. Tests

**Existing assertions that must change (4b2ae0f):**

| File:line | Today | Change |
|---|---|---|
| `AppSafetyModernCases.swift:34` | case title "…keeps Undo and Wipe under the slider" | retitle: "puts capture and annotation in the top bar, document and output in the bottom bar, and no rail" |
| `AppSafetyModernCases.swift:134` | top-bar loop includes `("resize", chrome.resizeButton)` | remove Resize from the top-bar loop; assert it sits in the bottom bar |
| `AppSafetyModernCases.swift:143-146` | Resize ≥ 28 pt after Crop | delete (moved) |
| `AppSafetyModernCases.swift:148` | `header.subviews.count == 3` | `== 4` (leading, capture, tools, annotation) |
| `AppSafetyModernCases.swift:155-156` | viewport ends at `W − 12 − 64 − 8` | `abs(area.maxX − (content.bounds.width − 12)) < 0.5` |
| `AppSafetyModernCases.swift:157-159` | Undo directly under the slider | delete; replaced by bottom-bar order test |
| `AppSafetyModernCases.swift:179` | `footer.subviews.count == 2` | `== 5` (4 groups + status row); keep the "holds only" stray check |
| `AppSafetyModernCases.swift:412` | `widthControl.style == .modern` | `== .pill` |
| `AppSafetyModernCases.swift:467,872-873` | "rail Wipe" wording | wording only; recommend renaming `wipeRailButton` → `wipeButton` (`App.swift:303,1201-1208`) in the same change |
| `AppSafetyModernCases.swift:562-575` | Frame hint fits the status at 1024 | re-measure; may need the shorter hint (§b) |
| `AppSafetyModernCases.swift:1046-1060` | Color popover opens, system appearance | add: opened with `preferredEdge == .minY` and its positioning view is in the top bar |
| `GlassChromeTests.swift:568` | `toolButton == 48×40 … railWidth == 64 && rightRailWidth == 64` | `toolButton == 44×40`; remove both rail asserts; add `groupGap == 12` |
| `GlassChromeTests.swift:326-400` (`sliderTests`, `:387` loops `[.classic, .modern]`) | vertical geometry in both styles | `.modern` → `.pill`; vertical geometry stays asserted for `.classic` only; add pill glyph tests |
| `GlassChromeTests.swift:720` | `glassContainers.count >= 7` | `>= 8` |
| `GlassChromeTests.swift:735-745` | order Hide, Toolbox, Photos, tools, Resize, Save, History | new order: Hide < Toolbox < Photos < Snap < tools < Color < Size < Font, and Undo < Wipe < Zoom < Resize < Save < History < toggle < Drag < Upload |
| `GlassChromeTests.swift:746-747` | footer order zoom, status, format, drag, upload | include Undo, Wipe, Resize, Save, History |
| `GlassChromeTests.swift:753-757` | Undo under slider; right rail one aligned column | delete |
| `GlassChromeTests.swift:786-819` (`redesignChecks`) | rail/tool-order/footer shape; `groups.count == 3` | `groups.count == 4` with ids `GlassHeaderLeading/GlassCaptureGroup/GlassToolBar/GlassAnnotationGroup`; add bottom groups; footer child count |
| `GlassChromeTests.swift:809-813` | footer holds only zoom, status, format, drag, upload | extend the allow-list |
| `GlassChromeTests.swift:897-900` | slider has a rounded surface, 36 × 96 | pill has a capsule surface, 48 × 36 |
| `GlassChromeTests.swift:977` | "Cancel is an icon pill under Snap Frame" (`cancel.maxY <= snap.minY`) | "Cancel is an icon pill to the right of Snap Frame" (`cancel.minX >= snap.maxX`, same midY) |
| `GlassChromeTests.swift:685` | `controls.count >= 24` | still true; keep |

**New can-fail regression tests** (each says what breaks if the feature regresses):

1. **No rail** — walk `ModernEditorChrome`: no subview/constraint with width 64 anchored to the trailing edge; no view with identifier `GlassDrawingGroup`/`GlassHistoryGroup`; `Metrics` has no `rightRailWidth` (compile-time). *Fails if* anyone re-adds a reserved column.
2. **Canvas reaches the margin** — `scrollView.frame.maxX == chrome.bounds.maxX − 12 ± 0.5` at 980, 1024, 1280, 1440. *Fails if* a constraint still ties the scroll view to a sibling.
3. **Every relocated control is visible, non-overlapping, fully inside its bar** at 980 × min height, normal **and** Frame mode: for Snap, Cancel (Frame), Color, Size, Font, Undo, Wipe, Resize, Save, History, Zoom, toggle, Drag, Upload: `isHidden == false` (except Cancel outside Frame), frame ⊂ its bar rect (±0.5), pairwise non-overlap (reuse `verifyLayout`'s pair loop, `GlassChromeTests.swift:~700-706`), and `status.frame.width ≥ 120` at the minimum with the checkbox shown. *Fails if* a lever regresses (e.g. token back to 48 ⇒ the Frame top bar overflows 30 pt).
4. **Width-budget oracle** — compute the sums of §b from the live `Metrics` and assert `needed ≤ U` for Frame/normal at 980; assert `ModernEditorChrome.minimumWindowWidth ≥ derived worst case`. *Fails if* a metric is raised without moving the minimum.
5. **Tool group balanced and stable** — in normal mode `gap(B.trailing → C.leading) == gap(C.trailing → D.leading) ± 0.5`; entering Frame mode moves **Snap by 0** and C by exactly half Cancel's slot (27 ± 0.5). *Fails if* the centring guides are dropped or Snap shifts.
6. **Canvas centred** — the existing equal-margin test at the new viewport (default and minimum), plus a hit-test at the viewport centre. *Fails if* `CenteringClipView` or the leading/trailing constraints become asymmetric.
7. **Frame capture rect** — with a canvas larger than the viewport: `frameViewportScreenRect == window.convertToScreen(scroll viewport)` and `hole.maxX == chrome.width − 12`; with a smaller canvas: rect == the centred canvas rect and ⊂ hole. *Fails if* the hole is derived from stale geometry or Frame mode is given a different scroll frame.
8. **Stroke popover undo grouping** — select a text element, `showPopover()`, drive mouse-down / 4 drags / mouse-up on `SizeTrackView`, then assert `undoManager.groupingLevel == 0`, `sizeUndoGrouping == false`, **exactly one** undo restores the original font size; repeat for a preset click and for dismissing the popover mid-drag (`dismissPopover()` ends the group). *Fails if* any path leaves a group open or splits one drag into several steps.
9. **Pill semantics** — AX role `.slider`, value/min/max, `accessibilityPerformIncrement/Decrement` step ±2.625, glyph thickness differs between `doubleValue = 1.5` and `12` (pixel sample), Shift gives a non-preset value in the track while a plain drag only returns the five steps. *Fails if* the pill becomes decorative or loses Shift behaviour.
10. **Order and ownership** — top-bar order (§h) and bottom-bar order; every relocated control's `target`/`action` equals the table in §f (reuse `modernActionRouting`, `AppSafetyModernCases.swift:831`). *Fails if* a control is re-parented without its action.

### i. Files, order and ownership

| File | Exact change | Lines (4b2ae0f) |
|---|---|---|
| **`Sources/ModernEditorChrome.swift`** (primary, serial) | rebuild top-bar groups and the bottom bar; delete `rightRail`, `sizeStack`, three vertical groups; scroll-view constraints; bleed inset; zoom capsule; status row; Cancel's group | `:254-421` (≈ 170 lines), `:224` (font loop) |
| `Sources/App+ModernChrome.swift` | keep `widthControl` wiring; drop `dragSizeLabel` from `SharedControls` init (or leave it as an off-screen model); zoom font 18 → 20 stays T1's; no popover code here | `:86,92` (+ `:72`) |
| `Sources/BezelDrawingControls.swift` | `.pill` style, popover, `SizePopoverContent`, `SizeTrackView`, `SizePresetButton`; delete `.modern` vertical drawing | `:103-209` (+ new ≈ 220 lines) |
| `Sources/GlassChrome.swift` | `Metrics.toolButton 44×40`; remove `rightRailWidth`/`railWidth`; add `groupGap = 12`, optionally `zoomWidth` | `:407,416` |
| **`Sources/App.swift`** (small, serial slot) | (1) `:1122` popover edge `.minX` → `.minY`; (2) `:387` and `:493` add `widthControl.dismissPopover()`; (3) status merge — split `updateStatus()` (`:1214-1217`) into `refreshStatusText()` (no `scheduleDragPreview`, **no-op while `frameMode`**) + the rest, and have `updateDragPreview` (`:1249-1250`) write `dragSizeLabel` then call `refreshStatusText()` (calling `updateStatus()` there would re-arm the 1-s timer forever); (4) optional `frameViewportScreenRect` extraction `:1956-1960`; (5) optional rename `wipeRailButton` `:303,1201-1208`. **Nothing else** — `widthControl` stays declared at `:217`. | listed |
| `tests/AppSafetyModernCases.swift`, `tests/GlassChromeTests.swift` | §h | listed |
| `tests/AppSafetyTests.swift` | none for the rail; `:3657-3721` (Classic slider) keep passing untouched because `.classic` is unchanged | – |

**Collision hotspots and order.** `ModernEditorChrome.swift` and both Modern test files are hotspots (§O). T15 must be the **first** writer after the baseline: it fixes the final *contents and positions* of the bars, and T4 → T6 → T7 → T9 restyle them. WP1 touches this region in 3 lines (`classicArtworkName`, `:98,186,283`), WP2 only strips `@available`/Classic branches around it, WP3/WP5 do not touch these files. **Recommendation: land T15 BEFORE the declassic WPs.** It is owner-priority, almost entirely in Modern-only files, and `BezelSizeSlider`'s new style is additive (the `.classic` path and its Classic tests are untouched). *Conflict cost:* WP1/WP2 implementers rebase over one rewritten region (≈ 170 lines of `build()`, mostly orthogonal to their 3-line deletions) and ≈ 10 test regions; if T15 landed *after* WP2 the cost would be the reverse (T15 re-deriving against deleted Classic scaffolding, ≈ 30–50 % extra edits) and the owner's request would wait behind five foundation work packages. Do not interleave T15 with T3's token sweep on the same file in the same pass.

**Estimate (d = one Sonnet implementer-day, Classic branch still present):** chrome rebuild 1.0 · pill + popover + AX 1.0 · tests (≈ 10 changed regions, 10 new) 1.0 · `App.swift`/metrics/status merge/zoom 0.5 · fit-up after the evidence agent's real widths 0.5 ⇒ **≈ 4 d** (3 d if the width oracle confirms the estimates first time). Opus review is separate. T4/T6 estimates shrink by ≈ 0.5 d each because the rail never needs restyling.

### j. Visual acceptance checklist (captures to take after implementation; each capture records its `sourceSha`)

Matrix: **{light, dark} × {980 × min height, 1024 × 740, 1280 × 800, 1440 × 900, full screen (e.g. 1728 × 1117)} × {empty, populated}**, plus the state captures below at 980 and 1280. Every capture must show:

1. **No rail:** no blank column right of the canvas; the viewport's right edge is 12 pt from the window edge (measure); no control to the right of or below the canvas other than the bottom bar.
2. **Top bar:** `[Hide][Toolbox][Photos]  [Snap]  10 tools  [Color][Size][Font]` in one row, all icons ≥ 22 pt, no clipping, no overlap; Snap is the primary command; the selected tool is distinguishable without colour (glyph family swap); gaps ≥ 12 pt.
3. **Bottom bar:** `[Undo][Wipe]  [Zoom][Resize]  status  [Save][History]  [PNG|JPG][Drag][Upload]`; all text ≥ 18 pt (20 pt for controls); status truncates with an ellipsis rather than pushing a control; at 980 with a large image the Original size checkbox is visible and nothing clips.
4. **Frame mode (980 and 1280):** Snap reads *Snap Frame*, Cancel sits right of it, the hole spans the full viewport to the 12-pt margin, the capture rectangle drawn/measured equals the hole when the canvas fills it, no control overlaps the hole, Photos is still visible (lever 4 not applied unless flagged).
5. **Stroke popover open (light and dark, 980 and 1280):** opens below the pill, solid (non-glass) content, "Size" + 20-pt readout, horizontal track with five ticks, five preset buttons, selected preset marked without colour alone; dragging changes the pill's glyph thickness live; Escape closes; the Size value survives reopening.
6. **Color popover from the top bar:** opens below the swatch, not clipped by the window edge at 980.
7. **Selection / text editing:** a selected element, then text editing in the canvas; Color/Size/Font still affect the selection; a Size drag changes the selected text's font size and one ⌘Z reverts it.
8. **PNG | JPG both states** at 980: both segments and the pressed/selected state readable; toggle does not change the bar's width.
9. **Reduce Transparency, Increase Contrast** at 980: bars still legible (the shared T4 fallback applies; T15 adds nothing translucent).
10. **Centring:** a small canvas (e.g. 150 × 90) is centred with equal left/right and top/bottom margins at every width; a large canvas fills the viewport edge-to-edge to the 12-pt margin and pans.
11. **Keyboard / AX (non-visual, record the log):** Tab order top-left → top-right → canvas → bottom-left → bottom-right; VoiceOver reads each label of §f; Space on the Size pill opens the popover; arrows step the value.

### k. Decisions and unresolved items

* **D-T15-1** — zoom popup face shows the percentage only (`"83%"`) with the mode word in tooltip/AX (§b). Needed for the 980-pt bottom bar. Alternative: lever 3 with a 160-pt zoom.
* **D-T15-2** — Size arrow keys on the pill follow `NSSlider` (Right/Up larger); the Classic-era Down = larger inversion is dropped for the pill.
* **D-T15-3** — tool tiles become 44 × 40 (4 pt narrower than the icon pills).
* **Unresolved until measured:** the real widths of the zoom capsule (108), the PNG | JPG capsule (143), the Original-size checkbox (138) and the merged status text (≈ 395); the Frame-hint margin at 1024; the title-bar height on macOS 26 (32 assumed from a Classic eye-dump); whether the system popover frame is translucent; whether `NSStackView` collapses Cancel's glass surface cleanly in `NSGlassEffectContainerView` (the existing vertical group already does).
* **Not decided here:** `NSToolbar` for the top bar (Q3) — T15's 16 items at 946 of 956 pt are the budget any toolbar must meet.

---

## O. File ownership map (which T-areas touch which file)

Hotspots ⚠ must be edited by **one implementer at a time**; the order column is the recommended serial sequence.

| File | Areas | Notes / order |
|---|---|---|
| ⚠ `Sources/App.swift` (2340 l) | **T15 (5 small hunks: `:387,493,1122,1214-1217,1249-1250`, optional `:303,1956-1960`)**, WP1, WP2, WP4 (+T12), T1, T3, T5, T6 (DragExportView), T7, T8, T9, T10 (alert wiring), T11 (showPreferences) | **Strictly serial: T15 → WP3 → WP1 → WP2 → WP4(+T12) → T1/T3 sweep → T9 → T8 → T7 → T6/T5 remainder → T10.** (T15's hunks are line-local; WP2 later deletes the Classic code around them.) Nothing else may edit it concurrently. |
| ⚠ `Sources/Canvas.swift` | WP1 (cursor, sounds), WP4 (menu strings, pasteboard ids), T1 (menus), T3 (grip/handle radii) | WP1 → WP4 → T1/T3 (3 small edits) |
| ⚠ `Sources/GlassChrome.swift` | **T15 (`Metrics` only: tool 44×40, drop `rightRailWidth`/`railWidth`, add `groupGap`; `:407,416`)**, WP1, WP2 (`ChromeAccessibility` move), T2, T3, T4, T6, T7 | T15 → WP1 → WP2 → T4 → T6 → T7 (single owner for T2–T7) |
| ⚠ `Sources/ModernEditorChrome.swift` | **T15 (primary: `:254-421`)**, WP1, T3, T4, T5, T6, T7, T9 | **T15** → WP1 → T4 → T9 → T6 → T7 |
| `Sources/App+ModernChrome.swift` | **T15 (`:86,92`)**, WP2, T1, T3, T7, T8, T9, T12 | T15 first, then follows App.swift order |
| `Sources/OriginalGeneralPreferences.swift` | WP1 (sounds), WP2 (appearance), WP4 (keys) | WP1 → WP2 → WP4; T11 after |
| `Sources/GeneralPreferencesForm.swift` | WP2, WP4, T1, T3, T7, T8, T11 | after WP2; parallel to other files |
| `Sources/BezelDrawingControls.swift` | **T15 (`.pill` style, popover, track, presets; `:103-209` + new)**, WP1 (PNG), T2, T6 | T15 → WP1 → T2/T6 |
| `Sources/ChromeIcons.swift`, `FontAwesomeIcons.swift`, `MenuSymbols.swift` | WP1, T5 | WP1 → T5 |
| `Sources/OriginalCaptureCountdown.swift` | WP1, T7, T10 | free file |
| `Sources/OriginalCaptureFlash.swift`, `OriginalCapturePicker.swift`, `OriginalCaptureMagnifier.swift`, `OriginalHelpBevel.swift`, `OriginalHintMessages.swift` | T1, T2, T5, T7, T10, WP6 | free files; parallel |
| `Sources/Capture.swift` | WP1 (onSound), T10 | WP1 → T10 |
| `Sources/ExportAccessory.swift`, `ImageExport.swift` | WP4, T1, T9 | free |
| `Sources/HistoryBrowser.swift`, `HistoryStore.swift` | WP4, T1, T3, T6, T8, T11 | free |
| `Sources/PublishingDestinationsView.swift`, `Publishing.swift`, `PublishingDestinations.swift` | WP4 (service/folder), T1, T3, T7, T8, T11 | free; WP4 touches ids first |
| `Sources/GlobalHotkeys.swift`, `PhotoBrowser.swift`, `ResizePanel.swift`, `TextStyleForm.swift`, `CanvasNavigator.swift`, `CanvasBorderView.swift` | T1, T3, T7, T8, T11 | free; parallel |
| `Sources/Appearance.swift`, `ToolButton.swift` | deleted in WP1/WP2 | – |
| `Sources/DesignTokens.swift`, `Sources/Migration/*`, `Sources/Icons/StatusIcon.swift` | new | new files; no collisions |
| `Info.plist` | WP2 (min OS), WP4 (ids, UTIs), T12 | serial with WP4 |
| ⚠ `tools/test.py` | WP1, WP3, WP4, T1 (auto-append tokens), T14 | serial: WP3 → WP1 → WP4 → T14 |
| `tools/build.sh`, `release.sh`, `eye-dump.sh`, `test-native-startup.py`, `test-app-safety.sh` | WP3, T14 | WP3 only, then T14 |
| ⚠ `tests/AppSafetyTests.swift` (328 KB), `tests/AppSafetyModernCases.swift` | **T15 (Modern cases only, §h)**, WP2, WP4, T4, T6, T7, T9, T11, T12 | serial after the App.swift owner of each step; both files churn in every area |
| ⚠ `tests/GlassChromeTests.swift` | **T15 (§h)**, WP1, T4, T6, T7 | T15 → follows GlassChrome owner |
| other `tests/*.swift` | per area | parallel |

**Suggested global sequence** (each box is a merge point; items on one line may run in parallel worktrees):
0. **T15 — remove the right rail (owner-required, P1), FIRST.** One implementer on `ModernEditorChrome.swift` + `BezelDrawingControls.swift` + `GlassChrome.Metrics` + 5 small `App.swift` hunks + the two Modern test files; runs in parallel with step 1 (tokens/gates scaffolding) and WP3 (build/tools), none of which touch these files. It fixes the final contents and positions of the bars so T4/T6/T7/T9 never restyle a rail. After the evidence agent's real widths arrive (`layout-width-budget.json`), re-run T15's budget before merging.
1. **Tokens & gates scaffolding (no prerequisites):** `DesignTokens.swift` + `PaletteTests`/`TypographyTests`/`MetricsTests`, `ViewTreeAudit` helper, gate scripts G1–G3/G6/G9 (initially red).
2. **WP3** (build/runners) ∥ nothing else touching `tools/`.
3. **WP1** (assets/sounds/PNG chain/ToolButton).
4. **WP2** (Classic/Appearance/welcome/macOS 26).
5. **WP4** (+T12 copy) ∥ **WP5'** fixtures ∥ **WP6** docs.
6. **Visual sweep A (App.swift owner):** T1+T3 sweep → T9 footer → T8 window chrome. In parallel (other owners): T11 files, T10 capture files, T7 motion gates, T5 icon assets, T2 palette consumers outside App/GlassChrome.
7. **Visual chain B (GlassChrome/ModernEditorChrome owner):** T4 → T6 → T7 labels/keyboard (Q3 only decides toolbar-vs-custom for the *top bar*; the rail is already gone via T15).
8. **Gates green + WP7** (clean clone, migration against a copy of the real store, eye-dump review).

Sizing roll-up (visual work only, after WP1–WP4, except T15 which goes first): **T15 ≈ 4 d** · T1+T3 2.5 d · T2 1 d · T4 3–4 d (≈ −0.5 d: no rail to restyle) · T5 1.5 d · T6 2.5 d (≈ −0.5 d) · T7 2 d · T8 2 d · T9 2 d · T10 1.5 d · T11 3 d · T12 1 d (inside WP4) · T14 gates 3 d ⇒ ≈ 26 d of implementer time, ≈ 8–10 d wall-clock with the parallelism above; **App.swift-serial work alone is ≈ 7.5 d** and is the critical path (T15 adds only ≈ 0.5 d to it).
