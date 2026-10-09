# OpenSkitch / OpenSnap — source inventory for the visual & cosmetic audit

**SOURCE-INFERRED, main @ 4b2ae0f** (full: `4b2ae0fd555dc2085f6bc7407b550782f96db04e`).

> Everything in this file is read from source. None of it is a rendered observation. Where a claim depends on how AppKit or
> Liquid Glass actually draws (contrast, material blur, tooltip font size, focus-ring visibility) it is marked *unverified until
> a screenshot or `eye-dump` confirms it*.

## 0. Method, baseline and caveats

* **SHA audited.** The brief said `b9319c4`. While this audit ran, `main` advanced to **`4b2ae0f`**: three commits
  (`88d8865`, `f19dfde`, `4b2ae0f`) merged the **PNG | JPG footer toggle** (9 files: `App.swift`, `App+ModernChrome.swift`,
  `ExportAccessory.swift`, `ImageExport.swift`, `ModernEditorChrome.swift`, `AppSafetyModernCases.swift`, `ExportAccessoryTests.swift`,
  `GlassChromeTests.swift`, `ImageExportTests.swift`). I audited an immutable `git archive` of `4b2ae0f` (`/tmp/osk-audit-4b2ae0f`)
  and re-derived **every** `file:line` below from it. Citations are therefore `4b2ae0f` lines. Lines in `App.swift` after ~L130 are
  +6…+34 vs `b9319c4`; this is why several `declassic-plan.md` line numbers look "drifted" (see §6.3 for which are real plan errors).
* **SNAPSHOT DRIFT (explicit).** The audit was *briefed* at `b9319c4`; **all `file:line` citations in this file and in `technical-spec.md` are `4b2ae0f`**. The rendered evidence captures under `docs/design/evidence/2026-10-09/` are **not** assumed to be at `4b2ae0f`: each is pinned to its own `sourceSha` in `docs/design/evidence/2026-10-09/manifest.json`. Before comparing a capture with a cited line, read that capture's `sourceSha` and run `git diff <sourceSha> 4b2ae0f -- <file>`; a mismatch means the comparison is unverified. Round 2 (owner layout feedback, right rail) re-read only `ModernEditorChrome.swift`, `App+ModernChrome.swift`, `BezelDrawingControls.swift`, `GlassChrome.swift`, `AppViewport.swift`, the Frame code in `App.swift` and the Modern tests at `4b2ae0f`; rows added for it are in §15.
* **Read-only.** No code, tests or tools were edited; no commit; the app and GUI tests were not run; no real user data
  (`~/Library/Application Support/SkitchRedux`, defaults domain, Keychain) was read. The unmerged `feat/png-jpg-toggle` branch is now
  an ancestor of `main` (`git merge-base --is-ancestor 88d8865 HEAD` → true), so T9 reconciles against merged code, not a branch.
* **Machine-readable font table:** `docs/design/evidence/source-font-sizes.json` (182 rows). Section 1 below is generated from it.
* **Path tags.** `modern` = only built when `Appearance.isModern`; `classic-only` = lives inside the Classic `buildWindow()` branch
  (`App.swift:720-864`) or a Classic-only helper; `shared` = reachable in both appearances (this is what Modern ships).
* **Product naming.** The owner renamed the product **OpenSnap** (declassic-plan §4). Today's strings still say OpenSkitch/Skitch; §7 lists them.
* **No CSS / HTML / web assets exist** (`find` for `*.css *.scss *.html *.htm *.svg *.xib *.storyboard *.nib` over the snapshot: none;
  no `font-size`/`<style>`/`@font-face` in any UI path). The only `font-size` strings are SVG **annotation output**
  (`SVGExport.swift:183`, reader `LegacySkitch.swift:390,530`) and are user content, not UI, so the "≥18 px at all widths" CSS rule has **nothing to apply to** in this repo today.

### Headline counts (details in the sections)

| Measure | Value |
|---|---|
| Explicit font-setting sites, UI text (rows / unique lines) | **124 / 121** |
| …of which below 18 pt | **0** (a floor is enforced in code: `GlassChrome.swift:58-69`, `ToolButton.swift:21-32`, `ModernEditorChrome.swift:213-215`) |
| …of which below 20 pt (all are exactly 18 pt) | **42** (33 on the Modern/shared path, 9 Classic-only rows + 0 other; see JSON `path`) |
| Modern/shared path rows at 18 / 20 / >20 | 33 / 70 / 4 (headings 24, 26, 26, 28) |
| AppKit-owned text with **no** font set in source (alerts, panels, About, tooltips, menu-bar strip) | **19** sites — expected < 18 pt, unverified until rendered |
| `controlSize` use | `.large` ×1 (`GeneralPreferencesForm.swift:184`), `.extraLarge` ×1 (`GlassChrome.swift:432`); **no** `.small`/`.mini` |
| Icon-only controls with no accessibility label | **0** (25 icon-only controls; each has an explicit or title-derived label — see §9) |
| Icon-only controls whose *only visible* name is a native tooltip | **25** (Cancel is hidden outside Frame mode, so 24 are visible at rest) |
| `NSGlassEffectView` instances (Modern) | **26** `GlassSurfaceView` + **7** `NSGlassEffectContainerView`; `NSVisualEffectView` ×1; `NSBackgroundExtensionView` ×1 (hidden by default) |
| Max glass nesting | container → surface = **2 glass-class ancestors**, but **0 glass-in-glass surfaces** (§4) |
| Original-asset runtime load sites in `Sources/` | **11** (13 lines) + 11 `cp` statements in `tools/build.sh` (§6) |
| User-visible "Skitch" strings (non-internal) | **25** sites (§7.1 rows 1-25; row 24 = 2 `Info.plist` lines, row 25 = exported SVG attributes) |
| User-visible "OpenSkitch" strings | 11 source lines (~15 strings, 2 of them Classic-only) + 8 `Info.plist` lines (§7.2) |
| Decorative / defective glyphs in UI strings | **0 emoji, 0 starbursts, 0 decorative arrows**; **3 defective** (2× `º` U+00BA used for "degree", 1× Apple logo U+F8FF) + 2 inconsistent ellipsis styles (§5.3) |

---

## 1. Typography — every font set in `Sources/`

Legend. *Role*: **UI text** (counted against the 18/20 rule), **annotation content** (user drawing text), **default doc text**, **icon glyph size**,
**helper (sizes at call sites)**, **control size**, **probe (not rendered)**, **UI text (system-owned)** (AppKit default; no font in source).
*<18 / <20* are only evaluated for UI text with a numeric size. `path`: M=modern, S=shared, C=classic-only.

| file:line | surface | size / weight | role | path | <18 | <20 |
|---|---|---|---|---|---|---|
| `App+ModernChrome.swift:54` | S06/S03 Color button (title hidden, image-only) | 18 | UI text | M | no | **yes** |
| `App+ModernChrome.swift:58` | S06 sizeLabel (built but not displayed in Modern) | 18 | UI text | M | no | **yes** |
| `App+ModernChrome.swift:65` | S09 'Original size' checkbox (footer status row) | 18 | UI text | M | no | **yes** |
| `App+ModernChrome.swift:72` | S09 Zoom popup (footer) | 18 | UI text | M | no | **yes** |
| `App+ModernChrome.swift:80` | S09 PNG / JPG toggle (glass capsule) | 20 | UI text | M | no | no |
| `App+ModernChrome.swift:86` | S09 drag size / byte-count label (footer) | 18 | UI text | M | no | **yes** |
| `App+ModernChrome.swift:87` | S09 status line (footer) | 18 | UI text | M | no | **yes** |
| `App.swift:75` | DragExportView hand glyph (SF Symbol hand.raised) | 22 semibold | icon glyph size | M | no | no |
| `App.swift:85` | Classic 'Drag Me' plate text (DragExportView.draw, non-icon branch) | 20 bold | UI text | C | no | no |
| `App.swift:426` | S24 status-item tooltip 'Click to show/hide Skitch' (system tooltip font) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:648` | AppDelegate.label() helper: Classic rail labels + Modern color-popover title | 18 | UI text | S | no | **yes** |
| `App.swift:649` | AppDelegate.button() helper: Classic buttons + Modern color-popover 'Custom color…' | 18 | UI text | S | no | **yes** |
| `App.swift:672` | Toolbox 'More Commands' copied submenus (S23) | 20 | UI text | S | no | no |
| `App.swift:677` | Toolbox popup button (S03) | 20 | UI text | S | no | no |
| `App.swift:678` | Toolbox menu (S23) | 20 | UI text | S | no | no |
| `App.swift:700` | Toolbox 'More Commands' menu (S23) | 20 | UI text | S | no | no |
| `App.swift:731` | Classic header brand text 'OpenSkitch' | 20 semibold | UI text | C | no | no |
| `App.swift:765` | Classic rail Crop tool title | 18 | UI text | C | no | **yes** |
| `App.swift:781` | Classic rail Color button | 18 | UI text | C | no | **yes** |
| `App.swift:785` | Classic rail Size label | 18 | UI text | C | no | **yes** |
| `App.swift:803` | Classic 'Original size' checkbox | 18 | UI text | C | no | **yes** |
| `App.swift:833` | Classic name field | 20 | UI text | C | no | no |
| `App.swift:834` | Classic zoom popup | 18 | UI text | C | no | **yes** |
| `App.swift:838` | Classic Webpost button | 20 | UI text | C | no | no |
| `App.swift:841` | Classic Drag Me format popup | 20 | UI text | C | no | no |
| `App.swift:843` | Classic Drag Me format menu items | 20 | UI text | C | no | no |
| `App.swift:848` | Classic drag size label | 18 | UI text | C | no | **yes** |
| `App.swift:849` | Classic status line | 18 | UI text | C | no | **yes** |
| `App.swift:915` | Main menu bar dropdown menus (S23) | 20 | UI text | S | no | no |
| `App.swift:918` | S23 menu bar titles (top-level menu strip is system-drawn) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:942` | Spelling submenu (S23) | 20 | UI text | S | no | no |
| `App.swift:1037` | Annotation text size change (Size slider) - user content | – | annotation content | S | no | no |
| `App.swift:1109` | Color popover preset swatch buttons (title is empty; font unused) | 18 | UI text | S | no | **yes** |
| `App.swift:1116` | Color popover 'Custom color…' button (S06) | 20 | UI text | S | no | no |
| `App.swift:1136` | S06 NSColorPanel.shared (Custom color…) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1271` | S26 error NSAlert(error:) message + informative text — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1275` | S26 'Save your drawing?' NSAlert — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1294` | S26 NSOpenPanel (Open…) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1326` | S26 NSSavePanel (Save) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1514` | S26 History remove/trash NSAlert — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1529` | S26 'Delete this web post?' NSAlert — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1579` | S10 NSSavePanel (Export) chrome around the 20 pt accessory — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1613` | S26 NSPageLayout (Page Setup) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1616` | S26 NSPrintOperation (Print) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:1623` | Webpost right-click destination menu (S09/S19) | 20 | UI text | S | no | no |
| `App.swift:1678` | S26 NSSharingServicePicker — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:2037` | Rename / Timed Snapshot / Snap from Link NSAlert accessory field (S26) | 20 | UI text | S | no | no |
| `App.swift:2037` | S26 prompt() NSAlert message/info text (accessory field is 20 pt) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `App.swift:2090` | Fonts-panel selection fallback font - default doc text | – | default doc text | S | no | no |
| `App.swift:2090` | Fonts-panel selection fallback font - default doc text | 24 bold | default doc text | S | no | no |
| `App.swift:2113` | Fonts-panel selection fallback font - default doc text | – | default doc text | S | no | no |
| `App.swift:2113` | Fonts-panel selection fallback font - default doc text | 24 bold | default doc text | S | no | no |
| `App.swift:2176` | S25 standard About panel (credits NSAttributedString has no font attribute) — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `BezelDrawingControls.swift:121` | S06 BezelSizeSlider font (not drawn; AX/tooltip only) | 18 | UI text | S | no | **yes** |
| `BezelDrawingControls.swift:141` | Size slider vector track/dots/knob (14 pt knob, 10 pt track, 3 pt dots) — not text; listed for completeness | – | icon glyph size | M | no | no |
| `Canvas.swift:81` | Text annotation render on canvas (displayedSize = max(18, fontSize*scale)) | – | annotation content | S | no | no |
| `Canvas.swift:81` | Text annotation render on canvas (displayedSize = max(18, fontSize*scale)) | – | annotation content | S | no | no |
| `Canvas.swift:132` | Annotation text editor context menu (S05/S23) | 20 | UI text | S | no | no |
| `Canvas.swift:886` | restoreDefaultTextStyle: Helvetica-Bold annotation style | – | annotation content | S | no | no |
| `Canvas.swift:906` | Fonts panel conversion of annotation fonts | – | annotation content | S | no | no |
| `Canvas.swift:906` | Fonts panel conversion of annotation fonts | – | annotation content | S | no | no |
| `Canvas.swift:1846` | Canvas text-element context menu (S05/S23) | 20 | UI text | S | no | no |
| `Canvas.swift:1921` | Inline annotation text editor font (max(18, fontSize*displayScale)) | – | annotation content | S | no | no |
| `Canvas.swift:1922` | Inline annotation text editor fallback (boldSystemFont) | – | annotation content | S | no | no |
| `CanvasNavigator.swift:156` | Actual Size overview header 'Overview' | 20 semibold | UI text | S | no | no |
| `Capture.swift:687` | S16 Screen Recording denial: surfaces as NSAlert(error:) via AppDelegate.error — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `DocumentModel.swift:335` | Annotation text measuring/rendering (document model) | – | annotation content | S | no | no |
| `DocumentModel.swift:336` | Annotation text measuring/rendering (document model) | – | annotation content | S | no | no |
| `DocumentModel.swift:429` | Annotation text measuring/rendering (document model) | – | annotation content | S | no | no |
| `DocumentModel.swift:429` | Annotation text measuring/rendering (document model) | – | annotation content | S | no | no |
| `ExportAccessory.swift:163` | S10 Export accessory heading 'Export options' | 24 semibold | UI text | S | no | no |
| `ExportAccessory.swift:169` | S10 format popup | 20 | UI text | S | no | no |
| `ExportAccessory.swift:174` | S10 format menu items | 20 | UI text | S | no | no |
| `ExportAccessory.swift:181` | S10 'Format' label | 20 | UI text | S | no | no |
| `ExportAccessory.swift:207` | S10 'Export at original size' checkbox | 20 | UI text | S | no | no |
| `ExportAccessory.swift:244` | Export accessory label() helper default size — default parameter; callers: heading 24 semibold (L163), body 20 | – | helper (sizes at call sites) | S | no | no |
| `ExportAccessory.swift:247` | Export accessory label() helper (variable size) — variable: 24 heading / 20 body | – | helper (sizes at call sites) | S | no | no |
| `FontAwesomeIcons.swift:101` | Font Awesome registration probe (never rendered) | 12 | probe (not rendered) | S | no | no |
| `FontAwesomeIcons.swift:112` | Font Awesome glyph font factory (pointSize param = icon glyph size 20/22/26) | – | icon glyph size | S | no | no |
| `GeneralPreferencesForm.swift:71` | S17 appearance note (Appearance row, to be removed) | 18 | UI text | S | no | **yes** |
| `GeneralPreferencesForm.swift:84` | S17 'Holding Option reverses the setting' help | 18 | UI text | S | no | **yes** |
| `GeneralPreferencesForm.swift:105` | S17 tab labels | 20 | UI text | S | no | no |
| `GeneralPreferencesForm.swift:183` | S17 radios / checkboxes / buttons (configure()) | 20 | UI text | S | no | no |
| `GeneralPreferencesForm.swift:184` | Preferences control size — controlSize = .large | – | control size | S | no | no |
| `GeneralPreferencesForm.swift:228` | S17 row labels | 20 | UI text | S | no | no |
| `GlassChrome.swift:26` | GlassChromeButton.iconPointSize default (icon-only commands) | 22 | icon glyph size | M | no | no |
| `GlassChrome.swift:58` | GlassChromeButton default label font | 20 | UI text | M | no | no |
| `GlassChrome.swift:67` | GlassChromeButton floor: rebuilds a <18 font at 18 | 18 | UI text | M | no | **yes** |
| `GlassChrome.swift:67` | GlassChromeButton floor: rebuilds a <18 font at 18 | 18 | UI text | M | no | **yes** |
| `GlassChrome.swift:69` | GlassChromeButton nil-font restore | 20 | UI text | M | no | no |
| `GlassChrome.swift:417` | GlassChrome.Metrics: icon 22 / primary(Snap) 26 / label 20 — primaryIconPointSize = 26, labelPointSize = 20, labeledIconPointSize = 20 (L420) | 22 | icon glyph size | M | no | no |
| `GlassChrome.swift:432` | GlassChrome.useExtraLarge control size — controlSize = .extraLarge (36 pt control height); no .small/.mini anywhere in Sources | – | control size | M | no | no |
| `GlobalHotkeys.swift:584` | Capture Shortcuts panel heading/body (heading 28 semibold, body 20) — heading ? 28 : 20 | – | helper (sizes at call sites) | S | no | no |
| `GlobalHotkeys.swift:589` | S18 buttons (Reset / Disable All / Cancel / Save) | 20 | UI text | S | no | no |
| `GlobalHotkeys.swift:618` | S18 'Global Capture Shortcuts' heading (label(heading:true) -> 28 semibold) | 28 semibold | UI text | S | no | no |
| `GlobalHotkeys.swift:619` | S18 intro/body labels (label() -> 20) | 20 | UI text | S | no | no |
| `GlobalHotkeys.swift:620` | S18 'Enable global capture shortcuts' checkbox | 20 | UI text | S | no | no |
| `GlobalHotkeys.swift:628` | S18 key popups + their menus | 20 | UI text | S | no | no |
| `GlobalHotkeys.swift:637` | S18 modifier checkboxes | 20 | UI text | S | no | no |
| `GlobalHotkeys.swift:648` | S18 status line | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:258` | S20 category segmented control | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:263` | S20 search field | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:265` | S20 date-filter popup + menu | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:281` | S20 context menu | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:291` | S20 count / status line | 18 | UI text | S | no | **yes** |
| `HistoryBrowser.swift:297` | S20 detail field names | 18 semibold | UI text | S | no | **yes** |
| `HistoryBrowser.swift:299` | S20 detail field values | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:306` | S20 missing-file warning | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:309` | S20 action buttons | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:314` | S20 'Drag from History format' label | 18 | UI text | S | no | **yes** |
| `HistoryBrowser.swift:315` | S20 drag-format popup + menu | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:441` | S20 tile placeholder 'Preview unavailable' | 18 | UI text | S | no | **yes** |
| `HistoryBrowser.swift:442` | S20 tile name | 20 | UI text | S | no | no |
| `HistoryBrowser.swift:443` | S20 tile action line | 18 | UI text | S | no | **yes** |
| `HistoryBrowser.swift:467` | S20 day header | 20 semibold | UI text | S | no | no |
| `LegacyBridge.swift:71` | Legacy .skitch import text sizing | – | annotation content | S | no | no |
| `LegacyBridge.swift:71` | Legacy .skitch import text sizing | – | annotation content | S | no | no |
| `ModernEditorChrome.swift:117` | Upload icon (SF Symbol icloud.and.arrow.up) | 22 | icon glyph size | M | no | no |
| `ModernEditorChrome.swift:214` | Modern chrome readable(_:_:) floor helper — called with 20 (format/toolbox, L223) and 18 (status, size label, zoom, original-size, slider, L224) | – | helper (sizes at call sites) | M | no | no |
| `ModernEditorChrome.swift:223` | S09 Format toggle + Toolbox via readable(_,20) | 20 | UI text | M | no | no |
| `ModernEditorChrome.swift:224` | S09 status, drag-size label, zoom popup, original-size checkbox, size slider via readable(_,18) | 18 | UI text | M | no | **yes** |
| `ModernEditorChrome.swift:228` | S03/S09 native tooltips (toolTip) - system tooltip font, 14 assignments in App.swift, 11 in ModernEditorChrome.swift, 5 in App+ModernChrome.swift — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `ModernEditorChrome.swift:256` | Toolbox glyph (FA toolbox) | 22 | icon glyph size | M | no | no |
| `OriginalCaptureMagnifier.swift:70` | S13 crosshair magnifier label | 20 | UI text | S | no | no |
| `OriginalCapturePicker.swift:440` | Crosshair 'WxHpx' read-out (black on white 0.75) | 20 | UI text | S | no | no |
| `OriginalHelpBevel.swift:32` | Hint bevel text (LucidaGrande 20 or system 20) | 20 | UI text | S | no | no |
| `OriginalHelpBevel.swift:32` | Hint bevel text (LucidaGrande 20 or system 20) | 20 | UI text | S | no | no |
| `PhotoBrowser.swift:278` | S22 row name | 20 medium | UI text | S | no | no |
| `PhotoBrowser.swift:279` | S22 row detail | 18 | UI text | S | no | **yes** |
| `PhotoBrowser.swift:362` | S22 sheet title | 26 semibold | UI text | S | no | no |
| `PhotoBrowser.swift:364` | S22 help paragraph | 20 | UI text | S | no | no |
| `PhotoBrowser.swift:370` | S22 Close button | 20 | UI text | S | no | no |
| `PhotoBrowser.swift:373` | S22 status line | 18 | UI text | S | no | **yes** |
| `PhotoBrowser.swift:397` | S22 source / open buttons | 20 | UI text | S | no | no |
| `PhotoBrowser.swift:406` | S22 NSOpenPanel folder chooser — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `Publishing.swift:1068` | S19/S26 message sheet label | 18 | UI text | S | no | **yes** |
| `Publishing.swift:1072` | S19 text field helper | 20 | UI text | S | no | no |
| `Publishing.swift:1076` | S19/S26 message sheet button | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:35` | PublishingDestinationsView font(_:) helper — helper; call sites below carry the sizes | – | helper (sizes at call sites) | S | no | no |
| `PublishingDestinationsView.swift:38` | S19 list/form buttons (Add, Edit, Remove, Make Default, Done, Test, Save) | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:64` | S19 destinations table cell | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:79` | S19 list status | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:150` | S26 'Remove destination?' NSAlert: window text patched to >=18 only for top-level NSTextFields (L154-156); button fonts 18 — not sized in source; AppKit/system default, expected below 18 pt (SOURCE-INFERRED) | AppKit default (unset) | UI text (system-owned) | S | **yes** | **yes** |
| `PublishingDestinationsView.swift:153` | S26 Remove-destination alert buttons | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:173` | S19 form text fields | 20 | UI text | S | no | no |
| `PublishingDestinationsView.swift:176` | S19 form captions | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:192` | S19 protocol / credentials popups + menus | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:198` | S19 ACL checkbox | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:199` | S19 password field | 20 | UI text | S | no | no |
| `PublishingDestinationsView.swift:218` | S19 form help | 18 | UI text | S | no | **yes** |
| `PublishingDestinationsView.swift:219` | S19 form status | 18 | UI text | S | no | **yes** |
| `ResizePanel.swift:362` | S08 'Resize or Crop' heading | 26 semibold | UI text | S | no | no |
| `ResizePanel.swift:364` | S08 preset popup | 20 | UI text | S | no | no |
| `ResizePanel.swift:379` | S08 Resize / Crop / Limit segmented control | 20 | UI text | S | no | no |
| `ResizePanel.swift:385` | S08 help paragraph | 20 | UI text | S | no | no |
| `ResizePanel.swift:401` | S08 limit-by popup | 20 | UI text | S | no | no |
| `ResizePanel.swift:412` | S08 'Lock proportions' checkbox | 20 | UI text | S | no | no |
| `ResizePanel.swift:415` | S08 crop-anchor popup | 20 | UI text | S | no | no |
| `ResizePanel.swift:419` | S08 crop-anchor menu items | 20 | UI text | S | no | no |
| `ResizePanel.swift:431` | S08 validation error | 20 | UI text | S | no | no |
| `ResizePanel.swift:493` | Resize label() helper default size — default parameter; heading passes 26 semibold (L362) | – | helper (sizes at call sites) | S | no | no |
| `ResizePanel.swift:496` | Resize label() helper (variable size) — variable: 26 heading / 20 body | – | helper (sizes at call sites) | S | no | no |
| `ResizePanel.swift:502` | S08 dimension fields | 20 | UI text | S | no | no |
| `ResizePanel.swift:511` | S08 buttons (Cancel / Apply / OK / preset buttons) | 20 | UI text | S | no | no |
| `ResizePanel.swift:599` | S08 preset popup menu items | 20 | UI text | S | no | no |
| `SVGExport.swift:14` | SVG export of text annotations (USER ANNOTATION CONTENT, not UI) | – | annotation content | S | no | no |
| `SVGExport.swift:14` | SVG export of text annotations (USER ANNOTATION CONTENT, not UI) | – | annotation content | S | no | no |
| `SVGExport.swift:174` | SVG export of text annotations (USER ANNOTATION CONTENT, not UI) | – | annotation content | S | no | no |
| `SVGExport.swift:174` | SVG export of text annotations (USER ANNOTATION CONTENT, not UI) | – | annotation content | S | no | no |
| `TextStyleForm.swift:36` | S06 Fonts-panel accessory controls (outline, shadow, Default style) | 20 | UI text | S | no | no |
| `TextStyleForm.swift:186` | S06 native Fonts panel browser prototype cell | 20 | UI text | S | no | no |
| `TextStyleForm.swift:187` | S06 native Fonts panel browser prototype cell | 20 | UI text | S | no | no |
| `TextStyleForm.swift:194` | S06 native Fonts panel controls forced to 20 | 20 | UI text | S | no | no |
| `TextStyleForm.swift:201` | S06 native Fonts panel attributed titles forced to 20 | 20 | UI text | S | no | no |
| `TextStyleForm.swift:211` | S06 native Fonts panel table header cells | 20 | UI text | S | no | no |
| `TextStyleForm.swift:212` | S06 native Fonts panel table data cells | 20 | UI text | S | no | no |
| `TextStyleForm.swift:226` | S06 native Fonts panel popup menus | 20 | UI text | S | no | no |
| `TextStyleForm.swift:231` | S06 native Fonts panel popup item fallback | 20 | UI text | S | no | no |
| `ToolButton.swift:21` | Classic rail ToolButton font floor | 20 | UI text | C | no | no |
| `ToolButton.swift:30` | Classic rail ToolButton font floor | 18 | UI text | C | no | **yes** |
| `ToolButton.swift:30` | Classic rail ToolButton font floor | 18 | UI text | C | no | **yes** |
| `ToolButton.swift:32` | Classic rail ToolButton font floor | 20 | UI text | C | no | no |

### 1.1 Reading the table

* **There is no type scale.** The values 18 / 20 / 24 / 26 / 28 are scattered literals; nothing named `Typography`/`Font` exists.
  The nearest thing is `GlassChrome.Metrics` (`GlassChrome.swift:406-426`), which holds only icon sizes and one label size (`labelPointSize = 20`) — and `labelPointSize` is **never read** (dead token).
* **Floors are re-implemented three times** (`GlassChromeButton.font` override `GlassChrome.swift:64-72`, `ToolButton.font` `ToolButton.swift:27-35`, `ModernEditorChrome.readable()` `:213-215`) plus per-site `max(18, …)` in the annotation editor (`Canvas.swift:80,833,908,1640,1921-1922`). They agree today; a new control created without them silently falls back to AppKit's 13 pt.
* **Annotation text floor** is a *policy*: `OriginalDrawingControls.readableFontSize` → `min 18` (`BezelDrawingControls.swift:72`), `SketchDocument` default `fontSize = 24` (`DocumentModel.swift:161`, `Canvas.swift:1640` fallback 24). SVG `font-size` is the same content, written verbatim.
* **Menu fonts** are set on every `NSMenu` we build (20 pt: `App.swift:672,678,700,915,942,1623`, `Canvas.swift:132,1846`, `HistoryBrowser.swift:281,265,315`, `GlobalHotkeys.swift:628`, `PublishingDestinationsView.swift:192`, `TextStyleForm.swift:226`). The **top-level menu-bar strip** (App / File / Edit …) is system-drawn and cannot take this font.
* **Tooltips** (`toolTip` mentions: `App.swift` 14, `ModernEditorChrome.swift` 11, `App+ModernChrome.swift` 5, `GlassChrome.swift` 1, `BezelDrawingControls.swift` 1, plus `FormatToggle.toolTip` `ImageExport.swift:12`) use the system tooltip font; the Modern chrome relies on them as the only visible name of 25 icon-only controls. *Unverified: size.*
* **NSAlert / NSOpenPanel / NSSavePanel / About / NSColorPanel / NSSharingServicePicker / NSPageLayout / print** text is AppKit's. Only the accessory views and prompt field are ours (20 pt). The Remove-destination alert is the one place that tries to raise alert text (`PublishingDestinationsView.swift:150-157`) and it only touches direct `NSTextField` children (may miss the informative text, which is a non-direct view on some OS versions — *unverified*).
* **Custom-drawn text** (not NSControl, so view-tree font walkers miss it): hint bevel `OriginalHelpBevel.swift:32,57-60` (20 pt white on black 0.85), crosshair size read-out `OriginalCapturePicker.swift:440` (20 pt black on white 0.75), magnifier label `OriginalCaptureMagnifier.swift:70` (20 pt), "Drag Me" plate `App.swift:85` (Classic-only), canvas annotations `Canvas.swift:81-96`, overview header `CanvasNavigator.swift:156`.

---

## 2. Color

### 2.1 Hard-coded colors (non-annotation)

| file:line | Use | Value | Dark-mode / contrast risk |
|---|---|---|---|
| `App.swift:29` | Classic bezel gradient | `NSColor(white:0.91)→(white:0.78)` | Classic-only; light-only gradient, dies with Classic (`FrameChromeView.usesRecoveredBezel`) |
| `App.swift:172` | Drag thumbnail "click to expand" scrim | `NSColor.white @0.1` | on dark desktop invisible; Classic art overlay follows it (`Skitch_ShowSkitch`) |
| `App.swift:1053-1055` | Color swatch image (Color button, Modern too) | white fill, `NSColor.darkGray` 1 px stroke | **Shared/Modern**: dark-gray hairline on dark glass has near-zero contrast; light-only |
| `App.swift:225,1162` | custom color default / restore | `calibratedRed 0,1,1` (cyan) | content color, not UI |
| `BezelDrawingControls.swift:84` | swatch checker (transparency preview) | `white` / `white 0.72` | intentional; fine in both modes |
| `BezelDrawingControls.swift:91-92` | preset swatch outline | selected `controlAccentColor` 3 pt; else `NSColor.darkGray` 1 pt | **Shared/Modern**: unselected outline is a fixed gray → weak on dark; selected state differs by color+weight only (no non-color cue) |
| `BezelDrawingControls.swift:140-148` | Modern size slider | `quaternaryLabelColor` track, `secondaryLabelColor` dots, `controlAccentColor` knob | semantic ✔ (dark-safe); quaternary track is very low contrast (*unverified*) |
| `BezelDrawingControls.swift:94,159` | slider/swatch focus ring | `keyboardFocusIndicatorColor` 2 pt | semantic ✔ |
| `GlassChrome.swift:235` | focus-ring mask fill | `NSColor.black` (mask only) | n/a |
| `GlassChrome.swift:324-328` | glass tint states | accent @0.85/1.0; `labelColor` @0.08/0.16 (IC: 0.16/0.28) | semantic ✔; alpha literals are the only "tokens" |
| `GlassChrome.swift:355` | contrast ring | `labelColor` 1 pt | semantic ✔ |
| `ToolButton.swift:44` / used `GlassChrome.swift:179` | on-accent text | luminance > 0.179 → black else white, **computed against the opaque accent** but the surface is tinted at 0.85 over glass | contrast against the real blended tint is *not guaranteed* (unverified) |
| `Canvas.swift:8` | annotation outline | `.white` (content) | content |
| `Canvas.swift:158,270`, `DocumentModel.swift:107,156` | default pen | `.systemRed` | content; OK |
| `Canvas.swift:193,207-208,691` | text grip / shadows | `black@0.8`, `white@0.5`, `black` | grip is drawn on canvas/editor; fixed |
| `Canvas.swift:1392-1393,1411,1419` | checkerboard / handle fill / crop mask | `white`, `white 0.88`, `white`, `black@0.25` | document surface is intentionally light; **checker + white handle squares don't adapt** to dark canvas well (content) |
| `Canvas.swift:1386-1388,1405-1427` | selection chrome, Frame boundary, eraser ring | `controlAccentColor` | semantic ✔ |
| `CanvasBorderView.swift:46-50` | crop/resize handles | accent @0.65 line, accent fill | semantic ✔ |
| `CanvasNavigator.swift:149,174-186` | overview panel | `windowBackgroundColor`, `controlBackgroundColor`, `separatorColor`, `selectedContentBackgroundColor`(@0.22), `keyboardFocusIndicatorColor`, `labelColor` | semantic ✔ (best-tokenised surface) |
| `HistoryBrowser.swift:306,458-459` | warning text; tile selection | `.systemRed`; accent border / accent@0.15 | semantic ✔; selection is color-only (border width 2 + tint) |
| `GlobalHotkeys.swift:712` | error status | `.systemRed` | ✔ |
| `ResizePanel.swift:432` | error | `.systemRed` | ✔ |
| `OriginalCaptureFlash.swift:28` | flash | `NSColor.white` | by design |
| `OriginalCaptureMagnifier.swift:90-92,103,105,110` | magnifier | `black` shadow, `white` border, `calibratedWhite 0.5` placeholder lens, `black` stroke, `white@0.75` label plate | overlay on screen pixels; fixed colors OK; label is **black on white .75** (fixed) |
| `OriginalCapturePicker.swift:421,431-432,446` | crosshair & scrim & read-out | scrim `deviceRGB(24,24,24)@0.65`; crosshair `white@0.2` + `black@0.4`; read-out plate `white@0.75` | overlay; fixed |
| `OriginalHelpBevel.swift:55-58,90-92` | hint bevel | `black` shadow, `white` text, fill `calibratedWhite 0 @0.85`, stroke `calibratedWhite 0.95` | fixed dark HUD; OK in both modes; *not* a system material |
| `App.swift:25,2173` | Frame/window fills | `windowBackgroundColor`; `.white`/`.clear` background actions | semantic ✔ / content |

### 2.2 Semantic color use

`labelColor` / `secondaryLabelColor` / `quaternaryLabelColor` / `controlAccentColor` / `windowBackgroundColor` / `controlBackgroundColor` /
`keyboardFocusIndicatorColor` / `separatorColor` / `selectedContentBackgroundColor` / `disabledControlTextColor` appear in **12 files**
(counts: App 6, BezelDrawingControls 6, Canvas 4, CanvasBorderView 2, CanvasNavigator 7, GeneralPreferencesForm 2, GlassChrome 7, GlobalHotkeys 3,
HistoryBrowser 3, ModernEditorChrome 2, Publishing 1, PublishingDestinationsView 1). The glass chrome and the overview panel are consistently semantic.
The leaks are the swatch/outline grays and the capture overlays.

### 2.3 What would break in dark mode / Increase Contrast (source reading)

1. Color swatch image and preset outlines use `NSColor.darkGray`/`white` (App.swift:1053-1055; BezelDrawingControls.swift:84,91).
2. Classic forces `NSAppearance.aqua` on the content view, the color popover and its popover (`App.swift:722`, `:1104`, `:1120`) — gone with Classic; Modern follows system (asserted by `modernPalettePopover`).
3. Increase Contrast is handled **only** inside `GlassSurfaceView` (ring + stronger tint) and nowhere else: no high-contrast variants for the slider track, swatch outlines, overview panel, hint bevel or capture overlays.
4. `NSVisualEffectView(.underWindowBackground, .behindWindow)` backdrop (`ModernEditorChrome.swift:238-240`) sits *under the canvas well* (scroll view and clip view do not draw: `ModernEditorChrome.swift:250-251`), so the area around a small document is a translucent material rather than a solid content surface; its legibility under Reduce Transparency is left to the system (no code path).

---

## 3. Spacing / size / corner magic numbers

### 3.1 Existing token structures and how consistently they are used

| Structure | file:line | Contents | Used by | Status |
|---|---|---|---|---|
| `GlassChrome.Metrics` | `GlassChrome.swift:406-426` | button sizes (48×40 tool, 48×36 icon, 60×36 toolbox, 56×44 primary), `commandHeight 36`, `headerHeight 44`, `rightRailWidth 64`, icon point sizes 22/26, `groupSpacing 10`, `surfaceSpacing 6`, `containerSpacing 2`, `toolSpacing 4`, `resizeSeparation 28`, `pillPadding 12`, `toolRadius 12` | `ModernEditorChrome` (≈22 refs) | **Partially used**; dead: `railWidth`, `railPillWidth`, `dragRadius`, `labelPointSize`, `labeledIconPointSize` (defined, never read) |
| local lets in `ModernEditorChrome.build` | `ModernEditorChrome.swift:219-220` | `margin 12`, `gap 8`, `headerTop 4`, `rowHeight 44`, `footerBottom 8` | same function | **not in `Metrics`** |
| `ModernEditorChrome.minimumWindowWidth` | `:51` | 980 ("measured 976, rounded up") | `App+ModernChrome.swift:48` | one-off measured constant |
| `NavigatorGeometry` | `CanvasNavigator.swift:5-12` | `padding 12`, `headerHeight 30`, … | navigator | tidy, local |
| `OriginalCaptureMagnifierGeometry` | `OriginalCaptureMagnifier.swift:6-57` | `zoom 10`, 100×100 lens, label rect | magnifier | recovered numbers |
| `ResizePanelGeometry` | `ResizePanel.swift:95` | resize math | – | not visual |
| `CanvasBorderView.border` | `CanvasBorderView.swift:10` | 8 | crop handles | local |
| `WindowSizing`, `AppViewport` | `WindowSizing.swift`, `AppViewport.swift` | window/Actual math | – | behavioural |

### 3.2 Raw numbers (not tokenised)

* `NSLayoutConstraint … constant:` literals: **App.swift 26**, ResizePanel 18, PhotoBrowser 12, GeneralPreferencesForm 10, ExportAccessory 7, PublishingDestinationsView 7, GlobalHotkeys 5, ModernEditorChrome 3, Publishing 3, TextStyleForm 2.
* Modern-chrome literals: slider box 36×96 (`ModernEditorChrome.swift:325-326`), size-stack insets 8/6/8/6 (`:324`), `statusRow.spacing 12` (`:368`), `zoomWidth 160` (`:363`), toolbox holder inset 8 (`:264`), format holder inset 4 (`:341`), status/zoom/etc. fonts 18, drag-well hand 22 pt (`App.swift:75`), DragExportView plate radius 8 (`App.swift:73`), `drag thumbnail 128` (`App.swift:98,566`), minimum thumbnail 90 (`App.swift:567`).
* Corner radii in use: 2 (`CanvasBorderView.swift:52`), 3 (`OriginalCaptureMagnifier.swift:111`), 4 (`BezelDrawingControls.swift:160`), 5 (`BezelDrawingControls.swift:81,90,141`, `Canvas.swift:199,202`, `OriginalCapturePicker.swift:447`), 6 (`BezelDrawingControls.swift:95`, `ToolButton.swift:68`), 8 (`App.swift:73`, `HistoryBrowser.swift:430`), 12 (`Metrics.toolRadius`, `OriginalHelpBevel.swift:81`), 14 (`Metrics.dragRadius`, unused), capsule = half height (`GlassShape`, `GlassChrome.swift:3-12`). **10 distinct radii, no scale, no concentricity rule** (a capsule next to radius-12 tool tiles inside a radius-? window).
* Prefs/History/Photos/Resize/Publishing use their own 12/14/16/18/20/24/28 spacing literals (e.g. Resize stack `spacing 14`, insets 28; Photos 22/24/14/18/20/16; Prefs 20/24/16; History 18/20/8/12/5; Hotkeys 20/24/12).
* Window sizes: see §10.

---

## 4. Glass layering (Modern)

| View | Created | Parent | Nesting | Tint | cornerRadius | Content/canvas beneath at rest? |
|---|---|---|---|---|---|---|
| `NSVisualEffectView` backdrop (`.underWindowBackground`, `.behindWindow`, `.followsWindowActiveState`) | `ModernEditorChrome.swift:77,238-240` | `ModernEditorChrome` (full bleed, z-lowest); hidden in Frame mode `:193` | 0 (not glass) | n/a | 0 | **Yes: it is the canvas well's background** (scroll view draws no background `:250-251`) |
| `NSBackgroundExtensionView` bleed | `:78,241-244` | chrome | 0 | alpha 0.6 | – | hidden: `GlassChrome.usesCanvasBleed = false` (`GlassChrome.swift:437`), `updateBackdropAndBleed` `:192-195`. Test `modernCanvasBleed` flips the flag itself |
| `NSGlassEffectContainerView` ×7 (`GlassHeaderLeading`, `GlassHeaderTrailing`, `GlassToolBar`, `GlassCaptureGroup`, `GlassDrawingGroup`, `GlassHistoryGroup`, `GlassFooterRow`) | `GlassChrome.group` `GlassChrome.swift:452-462`; call sites `ModernEditorChrome.swift:271-272,292,333-335,359` | header / right rail / footer | level 1 | none | n/a | none (they sit outside the scroll view frame) |
| `GlassSurfaceView : NSGlassEffectView` ×26 | `GlassChrome.swift:244-401`; `GlassChrome.surface` `:441-449` | inside a container's `NSStackView` | level 2 (container → surface) | `nil` (rest) / `labelColor@0.08` (hover) / `@0.16` (press) / `controlAccentColor@0.85` (selected & Snap) / IC: 0.16/0.28/1.0 (`:320-330`) | capsule = ½ height; tools `.rounded(12)`; size group `.rounded(12)` (`GlassShape`, `:3-12`; `syncShape` `:358-363`) | no |
| surfaces, by group: header-left 3 (Hide, Toolbox, Photos); toolbar 11 (10 tools + Resize); header-right 2 (Save, History); capture 2 (Snap, Cancel[hidden]); drawing 3 (Color, Font, Size); history 2 (Undo, Wipe); footer 3 (Format toggle, Drag, Upload) | `ModernEditorChrome.swift:263-270,286,291,315-332,351-357` | – | – | – | – | `AppSafetyModernCases.modernAccessibilityInjection` asserts `surfaces.count >= 26` |
| `style = .regular` only (never `.clear`) | `GlassChrome.swift:275` | – | – | – | – | one variant per interface ✔ |
| `effectIsInteractive` | `GlassChrome.swift:279` | macOS 27 only | – | – | – | – |

**Verdicts (SOURCE-INFERRED).**
1. **No glass-on-glass:** no `GlassSurfaceView` contains another; content views are `GlassChromeButton`, `ControlHolderView`(popup), `DragExportView`, a `NSStackView` holding the slider (`ModernEditorChrome.swift:320-330`).
2. **Control chrome on glass:** the PNG|JPG toggle is an `NSSegmentedControl` with `segmentStyle = .capsule` (`App+ModernChrome.swift:79`) inside the glass `formatSurface` (`ModernEditorChrome.swift:342-350`): AppKit paints its own capsule bezel on top of the glass → a second plate. The Toolbox popup is borderless (`:261`) and the format popup was borderless; the toggle is the only bordered-capsule-on-glass.
3. **Glass over content at rest:** none. Header, rail, footer are siblings; the scroll view is pinned between them (`ModernEditorChrome.swift:411-413`). The only translucent thing under content is the window backdrop material (above) and the disabled bleed.
4. **Granularity:** 26 individual glass surfaces (every icon is its own capsule/tile) rather than one surface per group. This is the opposite of "one disciplined navigation layer": it is the maximum-fragmentation reading of the HIG and the main cost driver for glass count.
5. **Tint discipline:** two tinted things at rest — the selected tool (`isSelected` → accent 0.85) and Snap (primary). "Tint only primary actions" is violated by selection tinting if read strictly.
6. **Reduce Transparency:** `ChromeAccessibility.reduceTransparency` is consumed in exactly one place — to hide the disabled bleed (`ModernEditorChrome.swift:194`). `GlassSurfaceView` stores `accessibility` and reads `increaseContrast`/`reduceMotion` only; **no surface fallback** (the test asserting "every surface receives the injected options" cannot see this — §14).
7. Non-glass floating windows: hint bevel child panel (`OriginalHelpBevel.swift:234-252`, black 0.85 plate above the host window's top edge), Drag thumbnail panel (`App.swift:582-596`), Actual-Size overview panel (`AppViewport.swift:116-124`), color `NSPopover` (`App.swift:1112-1121`, system material). None is glass.

---

## 5. Iconography

### 5.1 Chrome control → icon source (Modern)

| Control | Where | Source chain | Concrete asset |
|---|---|---|---|
| Hide / Photos / Save / History | `ModernEditorChrome.swift:103-106` | FA Pro → SF Symbol → classic PNG → none (`ChromeIcons.resolve`, `ChromeIcons.swift:38-54`) | FA `eye-slash`/`images`/`floppy-disk`/`clock-rotate-left`; SF `eye.slash`/`photo.on.rectangle`/`square.and.arrow.down`/`clock.arrow.circlepath` (`FontAwesomeIcons.swift:50-78`); PNG `Hide`,—,`SaveToHistoryArrow`,— |
| Toolbox | `:256-260` (`ChromeIcons.resolve(.toolbox…)`) | same | FA `toolbox` 0xF552 / SF `wrench.and.screwdriver` |
| 10 tools | `:45-48,276-290` | same | FA `arrow-pointer paintbrush slash-forward circle square fill-drip eraser text arrow-up-right crop-simple` / SF `cursorarrow paintbrush line.diagonal circle square drop.fill eraser textformat arrow.up.right crop`; PNG `ToolOff*` for 9 |
| Snap / Snap Frame / Cancel | `:107-108,184-190` | same | FA `crosshairs`/`camera-viewfinder`/`xmark`; SF `scope`/`viewfinder`/`xmark`; PNG `SnapCrosshair`/`SnapSnap`/`SnapCancel` |
| Color | `App.swift:1050-1056` | **drawn bitmap swatch** (white + color + darkGray) | not an icon asset |
| Font | `:109` | same chain | FA `font` 0xF031 / SF `textformat.size`; PNG `Font` |
| Undo / Wipe | `:110-111` | same | FA `arrow-rotate-left`/`broom` / SF `arrow.uturn.backward`/**`trash`** (broom→trash fallback is a *semantic mismatch*: Wipe ≠ delete) |
| Resize | `:112` | same | FA `ruler-combined` / SF `ruler`; PNG `Resize` |
| Upload | `:114-118` | **SF Symbol only**, bypasses FA (`icloud.and.arrow.up`) | SF — FA icon `arrow-up-from-bracket` exists in the table but is **unused** (`FontAwesomeIcons.swift:18,46,76`) |
| Drag well | `App.swift:71-82` | **SF Symbol only** (`hand.raised`, 22 pt, tinted manually) | – |
| PNG \| JPG toggle | `App+ModernChrome.swift:79-85` | text segments | – |
| Status item | `App.swift:430-431` | **original PNG** `menu`/`menu-sel` | to replace |
| Main-menu leading icons | `MenuSymbols.swift:6-30` (59 actions) | **SF Symbols only** | SF |
| Drag "Show/Cancel" overlays | `App.swift:173-178` | **original PNG** `Skitch_ShowSkitch[_mouseover]`, `Skitch_Cancel_DragMe` | to replace |
| Text-move cursor | `Canvas.swift:173-179` | **original PNG** `CursorMove` (fallback `.closedHand`) | to replace |
| Countdown numerals | `OriginalCaptureCountdown.swift:53-56` | **original PNG** `SkitchCount1-3` | to replace |
| FA glyphs defined but unused in Modern | `FontAwesomeIcons.swift:17,18` | `maximize`, `minimize` (Actual Size has no Modern button), `arrow-up-from-bracket` | dead entries (still subset-fetched by `tools/fetch-fontawesome.sh` via grep of hex literals) |

*FA Pro is never committed or shipped* (`.gitignore`, `check-no-fonts.py`): a clean clone/CI therefore runs the **SF Symbol** branch, and the FA glyph branch of `GlassChromeTests`/`FontAwesomeIconsTests` is skipped silently (§14).

### 5.2 Fallback chain consequences
FA → SF → recovered PNG → none. On a machine without the licensed subset fonts the shipped Modern icons are SF Symbols (and `Wipe` becomes a trash can). "Real FA Pro semantic assets everywhere" cannot hold without either bundling the licensed subset (policy: no) or committing own vector icons.

### 5.3 Unicode glyphs in user-visible strings

| Glyph | file:line | Use | Verdict |
|---|---|---|---|
| `…` U+2026 | menus & buttons throughout (e.g. `App.swift:681,930,936,1654,1655`; `PublishingDestinationsView.swift:74,75`) | HIG-correct ellipsis | functional ✔ |
| **ASCII `...`** | `App.swift:682,683` (Toolbox: "Open...", "Export...", "Save As...", "Print...") | same commands as the menus' `…` | **inconsistent copy (defect)** |
| `·` U+00B7 | status text and labels (`App.swift:218-219(sizeLabel),1047,1187,1216,1249,1617,1921`; `HistoryBrowser.swift:329,449`; `PhotoBrowser.swift:499`; `PublishingDestinationsView.swift:90`) | typographic separator | acceptable; not decorative |
| `×` U+00D7 | dimensions (`App.swift:1249`, `ExportAccessory.swift:89`, `HistoryBrowser.swift:346`, `PhotoBrowser.swift:499`) | "W × H" | functional ✔ |
| `—` U+2014 | placeholders (`HistoryBrowser.swift:299,334,348`) | empty value | ✔ |
| `° ` U+00B0 | `App.swift:688` "Rotate 90° Clockwise" | degree sign | ✔ |
| **`º` U+00BA** | `OriginalHintMessages.swift:59,60` ("45º arrows", "45º lock") | masculine ordinal used as degree | **defect** (should be `°`); copy is "unchanged from the original" by comment `:7` |
| **U+F8FF (Apple logo)** | `OriginalHintMessages.swift:87` ("command() = Grab…") | renders the Apple logo glyph in Apple fonts, a trademark glyph | **remove** (spell "Command") |
| `⌃ ⌥ ⇧ ⌘` U+2303/2325/21E7/2318 | `ModernEditorChrome.swift:142-146` (tooltip shortcut text) | standard Mac key glyphs | functional ✔ |
| `“ ”` | `PublishingDestinations.swift:170`, `PublishingDestinationsView.swift:141,146`, `PublishingS3.swift:74-143` | curly quotes | ✔ |
| arrows used as *icons* | `FAIcon.arrowUpRight`/SF `arrow.up.right` = **Arrow tool** (legit, keep); `arrow.uturn.backward/forward` (Undo/Redo), `arrow.up.left.and.arrow.down.right` (maximize, `MenuSymbols` Actual Size), `arrow.triangle.2.circlepath` (Re-snap) | semantic, not decorative | keep; arrow tool is **functional** |
| emoji / starburst / ornament | none in `Sources/` string literals (Python scan of all literals incl. `\u{…}` escapes) | – | **0** |

---

## 6. Original Skitch assets, sounds, welcome document

### 6.1 Runtime load sites in `Sources/` (4b2ae0f)

| # | file:line | Asset(s) | Shared with Modern? | Plan ref |
|---|---|---|---|---|
| 1 | `App.swift:12` (`FrameChromeView.bezelImages`, lazy; 8 names `docWin_*`) | bezel PNGs | Modern builds the same view with `usesRecoveredBezel = false` (`App+ModernChrome.swift:49`); **not loaded** unless flag set | §0.3 `App.swift:8-14` ✔ (line unchanged) |
| 2 | `App.swift:173-174` | `Skitch_ShowSkitch`, `Skitch_ShowSkitch_mouseover` (`NSImage(named:)`) | **Yes** (`DragThumbnailView`) | plan `:168-173` (was correct at `b9319c4`) |
| 3 | `App.swift:177` | `Skitch_Cancel_DragMe` | **Yes** | same |
| 4 | `App.swift:321` (+ open path `:355-364`) | `firstlaunch.skitch` welcome document | **Yes** (opens once, "Welcome") | plan `:315,350-358` (`b9319c4`) |
| 5 | `App.swift:430-431` | `menu`, `menu-sel` (status item) | **Yes** | plan `:424-425` (`b9319c4`) |
| 6 | `App.swift:653-656` (`recoveredImage`) | any PNG by name: Classic `ToolOff*/ToolOn*/Hide/SaveToHistoryArrow/SnapCrosshair/SnapSnap/SnapCancel/Font/Resize/ActualSizeToggle*` (call sites `App.swift:735-858`, `1916,1944`) and the **own** logo `OpenSkitch.png` (`:726`) | Classic-only | plan `:642-650` ✔ |
| 7 | `Canvas.swift:173-179` | `CursorMove.png` (text-grip cursor) | **Yes** | ✔ |
| 8 | `BezelDrawingControls.swift:111-112` | `sizeSlider.png`, `sizeSlider-indicator.png` (lazy, `.classic` style only) | not loaded in Modern | ✔ |
| 9 | `OriginalCaptureCountdown.swift:53-56` | `SkitchCount1-3` (+ alias `originalSkitchCount*`) | **Yes**: if absent the panel is *not shown at all* (timing still runs) | ✔ (`:54-55`) |
| 10 | `OriginalGeneralPreferences.swift:70` (+ names `:65-66`) | 9 `.m4a`: `wipe_snap wipe_brushlayer wipe_already_blank snap PTW_complete PTW_error PTW_commence archive_1st pre-snap-countdown`; played from `App.swift:446,1847`, `Capture.swift:368,787`, `Canvas.swift:314,734-752` | **Yes** (preference "Play sounds", `GeneralPreferencesForm.swift:45`) | ✔ (`:64-80`) |
| 11 | `ChromeIcons.swift:49-52` (+ names `:14-36`; setters `GlassChrome.swift:24,159`, `ModernEditorChrome.swift:98,186,283`) | classic PNG fallback chain | **Yes** (last-resort fallback) | ✔ |

`SkitchTitle.png` is copied by `build.sh:39` but **never loaded** by any source.

### 6.2 Build / tooling copy sites

| file:line | Copies |
|---|---|
| `tools/build.sh:14` | `ToolOff*.png`, `ToolOn*.png` |
| `tools/build.sh:15-17` | loop: `SnapCrosshair Font ActualSizeToggleOff ActualSizeToggleOn Resize SaveToHistoryArrow Hide SnapSnap SnapCancel` |
| `tools/build.sh:18` | `CursorMove.png` |
| `tools/build.sh:36` | `menu.png`, `menu-sel.png` |
| `tools/build.sh:37` | `Skitch_ShowSkitch*.png`, `Skitch_Cancel_DragMe.png` |
| `tools/build.sh:38` | `docWin_*.png` |
| `tools/build.sh:39` | `SkitchTitle.png` |
| `tools/build.sh:40` | `sizeSlider*.png` |
| `tools/build.sh:41` | `SkitchCount*.png` |
| `tools/build.sh:42` | `*.m4a` |
| `tools/build.sh:43` | `firstlaunch.skitch` |
| `tools/build.sh:11` | `-target arm64-apple-macosx13.0` (and `:7-10` snapshot) |

The script has `set -eu` (`:2`) so the first `cp` of an absent file aborts the build: a clean clone **cannot build** (11 statements across L14–L43; **not** a contiguous `16-33` block as the plan says).

**`tools/eye-dump.sh` flag:** line 11 hard-codes `FIXTURE=…/original/Skitch.app/Contents/Resources/firstlaunch.skitch`, and line 12 loops `for STYLE in modern classic`, passing `SKITCH_APPEARANCE`, `SKITCH_APP_SUPPORT`, `SKITCH_FIXTURE`, `SKITCH_EVIDENCE_DIR` (line 17). It cannot run on a clean clone and its "evidence" depends on original content. Same fixture in `tools/test-native-startup.py:37,67,134`, `tools/test.py:121-122` (`--fixture`), `tools/decompile.sh:7` (Ghidra input, not shipped).

### 6.3 Tests that read `original/` (git-ignored; most SKIP when absent)

| file:line | What |
|---|---|
| `tests/AppSafetyTests.swift:493,552` | **hard-fails** (`expect fileExists`) — `firstLaunchWelcome` requires the original fixture; not listed in the plan |
| `tests/CanvasTests.swift:79,1320-1321,1375` | firstlaunch fixture (SKIP) |
| `tests/SkitchFileTests.swift:13,28,83` | fixture (SKIP) |
| `tests/SVGExportTests.swift:63,248-251` | fixture (SKIP) |
| `tests/FontAwesomeIconsTests.swift:57,193` | original artwork lookup (silently skipped) |
| `tests/OriginalCaptureCountdownTests.swift:6,98-101,144,295` | **numeral/attachment/reentry checks skipped wholesale** without original art |
| `tests/OriginalGeneralPreferencesTests.swift:6,98-108` | audio decode checks skipped |
| `tests/OriginalHintMessagesTests.swift:12,110-113` | diffs strings against the original **binary** |
| `tests/ResizePresetsTests.swift:259` | original binary + `analysis/disassembly.txt` |
| `tests/ToolButtonTests.swift:6,167-171` | artwork pairs |

### 6.4 Declassic-plan line-number cross-check

At `b9319c4` (the plan's base) the plan's lines are **correct** for the load sites (`App.swift:8-14,168-173,315,350-358,424-425,642-650,713,929-932,964,1715-1720,2199,2258`; `Canvas.swift:174-176`; `OriginalCaptureCountdown.swift:54-55`; `OriginalGeneralPreferences.swift:64-80`; `ChromeIcons.swift:7,14-35,49-52`; `GlassChrome.swift:18,24,159,179,279`; `ModernEditorChrome.swift:98,186,236,283`). Because `main` moved, all `App.swift` lines after L130 are now +6…+34 (e.g. bezel stays L12; Drag overlays L173-177; firstlaunch L321; status item L430-431; `buildWindow` L716, Modern gate L719, Rename gate L935, `MenuSymbols.apply` L970, `relaunch` L1737, appearance evidence L2232, `RelaunchLauncher` L2291-2300, `runRelaunchSmoke` L2200).
**Real plan errors (wrong even at `b9319c4`):**
1. `tools/build.sh:16-33` — copies are at L14, 15-17, 18, 36-43 (11 statements), not a contiguous block; L19-35 is the icon/actool section.
2. `OriginalGeneralPreferences.swift:89` (`includeSkitch`) — the file has 81 lines; `includeSkitch` lives in `GeneralPreferencesForm.swift:8,15,20,44(box title),89,107,249` and `OriginalGeneralPreferences.swift:31,48,59`.
3. `HistoryBrowser.swift:56` — the message "missing or has changed outside Skitch" is `HistoryStore.swift:56`.
4. `TextStyleForm.swift:135` — "Skitch Text Style…" is **not** in `TextStyleForm.swift`; it is `Canvas.swift:135,1847` (only `Default Skitch Style` is at `TextStyleForm.swift:11`).
5. `PublishingDestinations.swift:127` — `SKITCH_APP_SUPPORT` read is at `:129` (comment `:125`).
6. `BezelDrawingControls.swift:101-210` — `Style` enum is `:105-106`; fine as a range but the "classic default" is `:106`.
7. `tools/test.py:72` (`-target`) is `:76`-region (`suite()` builds `["xcrun","swiftc",…,"-target", arch+"-apple-macosx13.0"]` at ~`:72-74`); `--concurrent-app-safety` is `:9-10`.
8. The plan's WP5 list of `original/` probes **omits** `tests/AppSafetyTests.swift:493,552` (hard failures) and `tools/test-native-startup.py:37`.
9. The plan's `Appearance.swift (61 lines)` is 64 lines; `GeneralPreferencesForm` "button count 18 → 15 (`:76`)" refers to a test line, not source — unverified.
10. Plan treats `SKITCH_*` → `OPENSKITCH_*`; owner §4 overrides to **`OPENSNAP_*`**, and the build/test tools **already** use an `OPENSKITCH_*` namespace (`OPENSKITCH_FETCH_FONTAWESOME`, `OPENSKITCH_NO_PRO_FONTS` `build.sh:47-53`, `release.sh:27,30`; `OPENSKITCH_FA_FONT_DIR` `test.py:89`) that must also be renamed.
11. Plan claims "the Modern drag-format item `Skitch`" at `App.swift:834`; that is Classic (`App.swift:840` now). The Modern copy was the same list in `App+ModernChrome.swift:79` **until the toggle merge removed it**; the Classic list, `ExportAccessory.swift:6` (`.skitch` → "Skitch") and `HistoryBrowser.swift:45,315` ("SKITCH") still ship the word.
12. The plan (§0.6) says the toggle branch is "uncommitted … 8 files"; it is committed and merged (3 commits, 9 files). **WP0 is already done.**

---

## 7. User-visible "Skitch" / "OpenSkitch" strings

### 7.1 "Skitch" (user-visible)

| # | file:line | String | Surface |
|---|---|---|---|
| 1 | `App.swift:432` | "Click to show/hide Skitch" | status-item tooltip (S24) |
| 2 | `App.swift:587` | AX label "Restore Skitch editor" | drag thumbnail (S29) |
| 3 | `App.swift:941` | menu "Default Skitch Style" | Text menu (S23) |
| 4 | `Canvas.swift:135` | "Skitch Text Style…" | annotation-editor context menu |
| 5 | `Canvas.swift:1847` | "Skitch Text Style…" | text-element context menu |
| 6 | `Canvas.swift:1849` | "Default Skitch Style" | text-element context menu |
| 7 | `Canvas.swift:886` | undo action name "Default Skitch Style" | Edit > Undo title |
| 8 | `TextStyleForm.swift:11` | button "Default Skitch Style" | Fonts panel accessory (S06) |
| 9 | `App.swift:135` | file-promise name fallback `"Skitch"` → dragged file "Skitch.png" | drag-out (S09) |
| 10 | `App.swift:1257` | `safeName()` fallback `"Skitch"` → default export/upload/History name | S09/S10/S19 |
| 11 | `HistoryBrowser.swift:486` | History drag file base name `"Skitch"` | S20 |
| 12 | `ExportAccessory.swift:6` | format title "Skitch" | export panel popup (S10) |
| 13 | `HistoryBrowser.swift:45,315` | drag-format popup item "SKITCH" (uppercased) | S20 |
| 14 | `App.swift:840` | Classic Drag Me format item "Skitch" | Classic S09 |
| 15 | `GlobalHotkeys.swift:15` | action title "Show Skitch" (+ AX labels `:631,638`) | S18 |
| 16 | `GeneralPreferencesForm.swift:44` | "Show Skitch window in fullscreen and crosshairs Snap" | S17 |
| 17 | `GeneralPreferencesForm.swift:107` | "Show Skitch in:" | S17 |
| 18 | `OriginalHintMessages.swift:125` | "…option-click to show Skitch during snap" | hint bevel (S30) |
| 19 | `HistoryStore.swift:56` | "…has changed outside Skitch." | alert text |
| 20 | `DocumentModel.swift:175` | "This is not a supported Skitch document." | alert text |
| 21 | `App.swift:1368` | "Old Skitch History could not be imported…" | status line (factual; migrates away) |
| 22 | `App.swift:2176` | About credits: "…reconstruction… parity with Skitch 1.0.12…" | About (S25) |
| 23 | `App.swift:349`, `HistoryStore.swift:81,112,140,185` | file/`UTType` names `.skitch/.skitchredux` shown in Save panel (`App.swift:1326`) and History | S10/S26 |
| 24 | `Info.plist:48,96` | "Original Skitch Drawing" (document type / UTI description; Finder "Kind") | Finder |
| 25 | `SVGExport.swift:184` | exported SVG attributes `skitchTextX/skitchTextY/skitchFontSize/skitchHasOutline/skitchHasShadow/skitchGroup`, ids `skitch-redux-shadow…` (`:43,118-124,185`) | exported files (visible to recipients) |
| 26 | `Capture.swift:214` | temp dir `skitch-capture-…` | internal (not UI) |
| 27 | window/tab titles: none contain "Skitch" except via above | – | – |

(Default document name is `"Untitled"` — `App.swift:214` — and `"Screenshot"` after a capture (`App.swift:1846`); the title fallback is "OpenSkitch".)

### 7.2 "OpenSkitch" (user-visible; becomes "OpenSnap")

`App.swift:718` window title; `App+ModernChrome.swift:22` title fallback; `App.swift:681` Toolbox "About OpenSkitch"/"Quit OpenSkitch"; `:920-921` app menu title, "About OpenSkitch", "Hide OpenSkitch", "Quit OpenSkitch"; `:433` AX "Show or hide OpenSkitch"; `:2176` About `applicationName`; `GeneralPreferencesForm.swift:48,79`; `DocumentModel.swift:176`; `HistoryStore.swift:58`; `Info.plist:6,8,12,20,22,28,38,76` (CFBundleName, display name, executable, icon names, `NSScreenCaptureUsageDescription`, document type names); Classic-only: `App.swift:726-731`; internal: `NSLog` `App.swift:2335`, identifiers `OpenSkitchHeader/Brand/Footer/StatusRow` (`ModernEditorChrome.swift:255,367,370`, `App.swift:734,2267-2268`), `NSError` domain `OpenSkitch.CapturePicker` (`OriginalCapturePicker.swift:27`).

### 7.3 Internal identifiers (not user-visible; migrate per §13)

`SkitchRedux` (error domains `App.swift:135,1306,1308,…`, `AppViewport.swift:16-36`, `Capture.swift:8,317`, `GlobalHotkeys.swift:110`), temp prefixes `SkitchPublish-/SkitchSFTP-/SkitchPublicCheck-/SkitchS3-/SkitchPhoto-`, queue `Skitch.HistoryPromise` (`HistoryBrowser.swift:490`), accessibility ids, legacy metadata keys `skitchBrushColor…` (`App.swift:1149-1164`), `skitch.toolbar.*` constraint ids (`TextStyleForm.swift:160-161`).

---

## 8. Component states (selected / hover / pressed / disabled / focus)

| Control | Rest | Hover | Pressed | Selected | Disabled | Focus | Missing |
|---|---|---|---|---|---|---|---|
| `GlassChromeButton` inside `GlassSurfaceView` (commands) | no tint | surface tint `labelColor@0.08` (IC 0.16) via tracking area `GlassChrome.swift:375-384` | `labelColor@0.16` (IC 0.28) from `mouseDown` bracket `:194-201`, secondary `highlight` `:186-190` | accent 0.85 (IC 1.0 + 1 pt `labelColor` ring `:353-356`) + glyph family regular→solid (`:152-153`) + contrasting glyph color (`:171-182`) | whole surface `alphaValue 0.5` (`:335`) + `disabledControlTextColor` glyph | AppKit exterior ring via `focusRingMask` hugging the glass (`:226-237`) | **keyboard-selected/active-descendant**; no distinct *focus+selected* look; disabled dims *everything* (0.5) incl. border/tint; no Differentiate-Without-Color cue except solid-glyph swap; no hover on touch-less keyboard; `effectIsInteractive` only on macOS 27 (`:279`) |
| 10 tool buttons | same, `setButtonType(.toggle)` (`ModernEditorChrome.swift:280`) | same | same | selected tool = accent tint + solid glyph, tooltip appends "(selected)" (`App.swift:1012`) | – | same | no per-tool disabled (Crop in Actual mode) styling beyond the generic |
| Snap (primary) | accent 0.85 always (`prominence .primary`) | no extra hover (accent already) | accent 1.0 | n/a | dims 0.5 | ring | primary has no hover distinction |
| Footer **PNG \| JPG** `NSSegmentedControl` capsule | native | native | native | native | native | native | custom tint/IC unaware; double plate over glass (§4.2) |
| Footer **Zoom** popup (`zoomControl`, bordered, outside glass) | native | native | native | n/a | native | native | looks like a 3rd control family (bordered, 160 pt wide) beside glass capsules |
| **Original size** checkbox (`dragOriginalControl`, footer status row `ModernEditorChrome.swift:366`) | native, 18 pt label | native | native | native (checkbox state) | native | native | none; it is the only footer *control* outside any group/glass (sits on the backdrop material, not on a solid surface) |
| **Drag well** (`DragExportView`, hand glyph) | surface only | **none** (`DragExportView` has no tracking area; hover is the *glass* surface tint only) | none (no pressed/“grab” feedback; closedHand cursor not set) | n/a | none (does not disable in Frame/empty) | **not focusable** (`acceptsFirstResponder` default false) | all of: cursor affordance, pressed, disabled, focus, keyboard activation, `accessibilityPerformPress` |
| **Size slider** `BezelSizeSlider` (vector) | track `quaternaryLabelColor`, dots `secondaryLabelColor`, knob accent | **none** | **none** (tracking only) | value = knob position | **none** (`isEnabled` not drawn) | custom 2 pt `keyboardFocusIndicatorColor` rounded rect (`BezelDrawingControls.swift:158-162`) | hover/pressed/disabled; knob 14 pt is below any comfortable hit target (hit area = whole 36×96 control) |
| **Color** button (`BezelHoverButton`) + swatch | bitmap swatch | hover opens popover after tracking (`onHover`) | native | n/a | native | native | state of "popover open" not shown; swatch outline dark-gray fixed |
| Color popover swatches `BezelColorButton` | 1 pt `darkGray` | **none** | **none** | 3 pt accent outline (`BezelDrawingControls.swift:91-92`) | none | custom 2 pt ring `:93-97` | hover/pressed/disabled; selected is color+weight only |
| Toolbox popup (borderless in glass) | glyph | surface tint | native menu | n/a | native | native | – |
| Webpost/Upload menu (right-click) | – | – | – | default destination checkmark | "No destination configured" disabled | – | – |
| Preferences radios/checkboxes/tabs | native, forced 20 pt, `.large` | native | native | native | native | native | none |
| History tile (`HistoryThumbnail`) | clear | none | none | accent border 2 pt + accent@0.15 | "Missing file" text | collection-view native | hover state; selection is color-first |
| Overview panel (`CanvasNavigator`) | – | – | drag | viewport rect fill/outline | – | 2 pt inset ring when first responder | – |

---

## 9. Accessibility

### 9.1 Labels / roles / help by control

| Control | Label | Role | Help / tooltip | Notes |
|---|---|---|---|---|
| 10 header/rail `GlassChromeButton`s (Hide, Photos, Save, History, Snap, Cancel, Font, Undo, Wipe, Resize) | title-derived `iconOnlyName` (`GlassChrome.swift:76-119`) | button | derived tooltip "Name (⌘X)" (`:101-104`) | Wipe label tracks Blank/Clear/Wipe (`App.swift:1201-1206`) |
| 10 tool buttons | `id.capitalized` ("Select", "Ellipse", …) (`ModernEditorChrome.swift:284`) | toggle button | tooltip "Brush tool (selected)…" (`App.swift:1007-1014`) | label lacks the word "tool"; selected state exposed via button state |
| Upload | "Upload to destination" (`ModernEditorChrome.swift:357`) | button | `webpostHelp` "Upload and copy link · Right-click for destinations" (`App.swift:1617,1619`) | label ≠ tooltip; the destinations menu is reachable through AX "show menu" (`OriginalActionButton.swift:36-45`, menu installed by `configureWebpostButton` `App.swift:1620-1626`) |
| Toolbox | "Toolbox" (`App.swift:712`) | popup | tooltip | image-only item |
| Color | "Drawing colors" + value "Red…, green…" (`App.swift:1062`) | button | long tooltip (`App+ModernChrome.swift:56`, overwritten `ModernEditorChrome.swift:228`) | – |
| Size slider | "Drawing size" + value/min/max/increment (`BezelDrawingControls.swift:122-135`) | slider | tooltip "Size N" | ✔ best-implemented control |
| Zoom | "Canvas zoom" (`App+ModernChrome.swift:73`) | popup | – | – |
| PNG\|JPG | "Image format" (`App+ModernChrome.swift:81`) | segmented | `FormatToggle.toolTip` | segment titles are visible text ✔ |
| Original size | "Drag out at original size" | checkbox | – | visible title "Original size" ≠ label (VoiceOver reads different words) |
| Drag well | "Drag Me" (`App.swift:886`) | **none set** (generic element) | tooltip | label is legacy caption; visible icon = hand; **no press/activate action**, not keyboard-focusable |
| Canvas | "Drawing canvas", role image (`Canvas.swift:473-474`) | image | – | no per-annotation AX children; the canvas is not operable by VoiceOver/keyboard beyond tool shortcuts |
| Overview | "Overview" + help + value + custom pan actions (`CanvasNavigator.swift:122-141`) | group | help text | ✔ |
| Canvas border | long label (`CanvasBorderView.swift:20-21`) | group | – | sentence-length label |
| Text editor / grip | "Annotation text", "Move annotation text" (`Canvas.swift:1934,1940`) | text / – | – | – |
| Status line | none | static text | – | **not a live region**: upload/publish/frame hints are only visual (no `NSAccessibility.post(.announcementRequested)` anywhere; only `valueChanged` in `CanvasNavigator.swift:130`) |
| Countdown view | "Capture countdown: N" role image (`OriginalCaptureCountdown.swift:99-101,139`) | image | – | not announced (panel never key) |
| Hint bevel | role staticText + value (`OriginalHelpBevel.swift:42,70`) | – | – | panel is non-key, child window |
| Drag thumbnail | "Restore Skitch editor", role button (`App.swift:586-587`) | button | – | wrong product name |
| Status item | "Show or hide OpenSkitch" (`App.swift:433`) | button | tooltip "Click to show/hide Skitch" | label/tooltip disagree |
| Prefs/History/Resize/Publishing/Hotkeys | labelled per control (`GlobalHotkeys.swift:631,638`, `HistoryBrowser.swift:261-317`, `ResizePanel.swift:366-433,504`, `PublishingDestinationsView.swift:68,184,241`, `ExportAccessory.swift:174-210`) | native | – | Destinations form rows relabel dynamically (`PublishingDestinationsView.swift:241`) |

**Unlabeled icon-only controls: 0.** Weak/legacy labels: Drag well ("Drag Me"), Upload (label ≠ tooltip), 10 tool labels (no "tool"), Drag thumbnail ("Skitch"), status item.
**25 icon-only controls rely on a system tooltip as their only visible name:** Hide, Toolbox, Photos, Save, History (5) + 10 tools + Resize (11) + Snap, Cancel, Color, Font, Size, Undo, Wipe (7) + Drag, Upload (2) = 25.

### 9.2 System display options

| Option | Handled | Where | Gap |
|---|---|---|---|
| Reduce Motion | window zoom/miniaturize animation (`App.swift:239`, uses `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`); glass state animation `GlassChrome.swift:336` (0 s) | `ChromeAccessibility` value | **not honoured:** hint-bevel fade timer (`OriginalHelpBevel.swift:255-279`, 0.02 s steps), capture flash ramp (`OriginalCaptureFlash.swift:6-23`), countdown alpha stepping (`OriginalCaptureCountdown.swift:141`), NSPopover/sheet animations (system), `WindowZoom` perspective CIFilter when `animatesWindowZoom` false is skipped ✔ |
| Reduce Transparency | only to hide the (disabled) bleed (`ModernEditorChrome.swift:194`) | `ChromeAccessibility` | **no fallback for 26 glass surfaces or the `.underWindowBackground` backdrop**; relies on system behaviour (unverified) |
| Increase Contrast | `GlassSurfaceView` ring + stronger tints (`GlassChrome.swift:264,321,327-328`) | only there | slider track, swatch outlines, overview, hint bevel, capture overlays have no variant |
| Differentiate Without Color | **never read** (`accessibilityDisplayShouldDifferentiateWithoutColor` has 0 uses) | – | selected tool: tint + glyph family; swatch selection: color + 3 pt; History tile: color border |
| Bold Text / Larger Text | n/a | – | fixed point sizes ignore the user's text-size setting by design |
| Notification | `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` observed only by `ModernEditorChrome` (`:122-124`) | – | Prefs/History/etc. do not re-read |

### 9.3 Keyboard, focus, Escape/Return

* `acceptsFirstResponder = true`: `CanvasView` (`Canvas.swift:352`), `BezelSizeSlider` (`BezelDrawingControls.swift:113`), `CanvasBorderView` (`:16`), `CanvasNavigator` (`:107`), picker view (`OriginalCapturePicker.swift:315`). `acceptsFirstResponder = false`: text grip, countdown image view. `DragExportView`: default (false).
* No `initialFirstResponder`, `autorecalculatesKeyViewLoop` or main-window `nextKeyView` anywhere (grep: only `ExportAccessory.swift:235-236` and `ResizePanel.swift:483-490` set loops). Main-window tab order is whatever AppKit derives; `setTool` always returns first responder to the canvas (`App.swift:1017`). *Runtime-unverified.*
* `focusRingType = .exterior` on glass buttons with a custom mask; `focusRingType` not set on others.
* Escape/Return: Prefs — Return = Done (`GeneralPreferencesForm.swift:139`), **no Escape** (window close → `closePreferences`); Photos sheet — Return = Open, Escape = Close (`PhotoBrowser.swift:368,370`); Resize — Return = OK + `defaultButtonCell`, Escape = Cancel (`ResizePanel.swift:436-440`); Capture Shortcuts — Escape = Cancel, Return = Save (`GlobalHotkeys.swift:654-656`); **Destinations sheet — no key equivalents** (`PublishingDestinationsView.swift`: none); History — none; text editor — Escape / Option-Return commit (`Canvas.swift:140-151`); picker — Escape cancels (`OriginalCapturePicker.swift:408-411`); border drag — Escape cancels (`CanvasBorderView.swift:82-87`).
* Tooltips are used as the *only* label for sighted users on 25 controls (§9.1).

---

## 10. Windows

| Window | Builder (file:line) | Size (default / min) | Style | Notes |
|---|---|---|---|---|
| **Main editor** | `App.swift:716-718`, Modern content `App+ModernChrome.swift:46-107` | **1024×740** / `minSize` 900×640 → width raised to **980** (`ModernEditorChrome.minimumWindowWidth`, `App+ModernChrome.swift:48`) | `[.titled,.closable,.miniaturizable,.resizable]` | title "OpenSkitch" → document name (`showDocumentName`, `App+ModernChrome.swift:20-23`); `isDocumentEdited` kept (`App.swift:362,412,1193,1331,1472`); **no** `setFrameAutosaveName`, `representedURL`, `subtitle`, toolbar, `titlebarAppearsTransparent` (only reset to `false` in Frame `App.swift:1900`), `titleVisibility`, `toolbarStyle`, `fullSizeContentView`, **no** `.fullScreenPrimary` (no full-screen support), `tabbingMode` default; `window.center()` every launch (`App.swift:368`) |
| Frame mode | `App.swift:1883-1931` | same window | alpha 0.8, `hasShadow=false`, **screen-saver level**, clear background; restores values | modal alerts suspend these (`withFrameWindowValuesSuspended`, `:1265-1270`) |
| **Preferences** | `App.swift:1698-1732` | 800×570 / `contentMinSize` 650×500 | `[.titled,.closable,.resizable]` normal `NSWindow` (not a sheet), closing hides | `NSTabView` with 3 tabs (General / Drawing / Snapping) + bottom row [Sharing Settings…][Done]; Cmd-, ✔; tabs are *in-content* tabs, not a toolbar-style Settings window |
| **History** | `HistoryBrowser.swift:94-96` | **1180×900 / min 1120×850** | titled, closable, miniaturizable, resizable | min height 850 exceeds a 13" laptop's usable height after menu bar/Dock (*unverified*); no autosave |
| **Photos** | `PhotoBrowser.swift:327-338` | 900×700 / min 760×540 | `NSPanel` **sheet** on main window | – |
| **Resize or Crop** | `ResizePanel.swift:336-357` | 600×(≥500, ~660) | `NSPanel` `[.titled,.closable]` **sheet** | not resizable |
| **Capture Shortcuts** | `GlobalHotkeys.swift:569-579,660-668` | 940×660 / min 880×530 | `NSPanel` sheet if a parent exists | – |
| **Destinations** | `Publishing.swift:908-909,1062-1065` | **820×860** | `NSPanel` `[.titled]` sheet | taller than the History default; fixed; scroll absent (stack layout) |
| Publishing message sheet | `Publishing.swift:1093-1099` | 700×300 | sheet | – |
| Export (save panel accessory) | `App.swift:1578-1583`, `ExportAccessory.swift:165-238` | accessory 600×(~380) | `NSSavePanel` modal | accessory only |
| Fonts panel | `App.swift:2038-2072` | `content 940×720`, positioned beside the main window | shared `NSFontPanel` | accessory `TextStyleForm` |
| Color panel | `App.swift:1136` | system | `NSColorPanel.shared` | – |
| Overview (Actual Size) | `AppViewport.swift:116-137` | `navigator` 180×170 → positioned | borderless non-activating child panel, `hidesOnDeactivate` | – |
| Drag thumbnail / window zoom | `App.swift:582-596`, `WindowZoom.swift:91-105` | 128 pt max | borderless, status-bar level | – |
| Hint bevel | `OriginalHelpBevel.swift:127-131,234-252` | window width − 80 × ≥47 | borderless child of host, above the top edge | – |
| Capture overlay / countdown / flash | `OriginalCapturePicker.swift:100-146`, `OriginalCaptureCountdown.swift:49-95`, `OriginalCaptureFlash.swift:35-54` | per display | borderless, popUpMenu+100 / screenSaver+200 level, `fullScreenAuxiliary`, canJoinAllSpaces | click-through except picker |
| Web capture (hidden) | `Capture.swift:854-860` | 1280×900 off-screen | borderless | not UI |

---

## 11. Surface map (S01–S33)

Columns: **builder** (file:line) · **owner file(s)** · **touches App.swift?** · **Classic dependencies still on the Modern path**.

| ID | Surface | Builder | Owning file(s) | App.swift? | Classic deps in Modern |
|---|---|---|---|---|---|
| S01 | Editor, empty | `App+ModernChrome.swift:46`, `Canvas.swift:656` (`newBlank` 1000×700) | App+ModernChrome, ModernEditorChrome, Canvas | **yes** (`newFile` `:1284`) | none visual; no empty-state UI exists |
| S02 | Editor, populated | `Canvas.swift:1372-1390` (`draw`) | Canvas, DocumentModel | no | checker/handle colors hard-coded |
| S03 | Title / top-bar chrome | `ModernEditorChrome.swift:254-309` | ModernEditorChrome, GlassChrome | yes (`window.title` `:718`) | `OriginalActionButton` base; PNG fallback chain; `bezelToolbox()` `App.swift:675` |
| S04 | Tool states | `ModernEditorChrome.swift:276-290`, `App.swift:1007-1014` | ModernEditorChrome, GlassChrome, App | **yes** | `ToolButton.textColor` `GlassChrome.swift:179`; hint bevel (original copy) |
| S05 | Selection / text editing | `Canvas.swift:1404-1429` (chrome), `:1910-1948` (editor), `:156-217` (grip) | Canvas | no | `CursorMove.png` `:173-179`; "Skitch Text Style…" menus |
| S06 | Color / size / text style / Fonts panel | `App.swift:1098-1124` (popover), `BezelDrawingControls.swift:76-209`, `App.swift:2038-2072` + `TextStyleForm.swift` | App, BezelDrawingControls, TextStyleForm | **yes** | `BezelSizeSlider.style` default `.classic` w/ PNGs; "Default Skitch Style" |
| S07 | Viewport zoom / Actual / centring | `AppViewport.swift:82-309`, `ModernEditorChrome.swift:427-460` (`CenteringClipView`), `App.swift:1176-1195` | AppViewport, ModernEditorChrome, App | yes | Actual button is **Classic-only**; overview panel original geometry |
| S08 | Crop + Resize panel/presets | `Canvas.swift` crop tool, `CanvasBorderView.swift`, `ResizePanel.swift:336-513`, `ResizePresets.swift` | ResizePanel, WindowSizing | yes (`resize()` `:2142`) | `ResizePresetKeys.id = "SkitchReduxResizePresetID"` (`:157`) |
| S09 | Footer (Undo/Wipe on rail, format, drag well, upload) | `ModernEditorChrome.swift:339-376`, `App+ModernChrome.swift:60-92`, `App.swift:50-148` (DragExportView) | ModernEditorChrome, App+ModernChrome, ImageExport | **yes** | Drag overlays `Skitch_*` PNG (`App.swift:173-177`); `dragFormatControl` popup still allocated (`App.swift:226`) |
| S10 | Export save-panel accessory | `App.swift:1578-1620`, `ExportAccessory.swift:165-238` | ExportAccessory | yes | format "Skitch" (`ExportAccessory.swift:6`) |
| S11 | Window sizes / full-screen | `App.swift:716-718`, `WindowSizing.swift`, `AppViewport.swift` | App, WindowSizing | **yes** | `minSize` 900×640 Classic baseline; no full-screen |
| S12 | Frame mode | `App.swift:1883-1931`, `App+ModernChrome.swift:5-12`, `App.swift:6-48` | App, App+ModernChrome | **yes** | `FrameChromeView` bezel code; `snapButton.image = recoveredImage(...)` guarded by `modernChrome == nil` |
| S13 | Capture picker / crosshair / magnifier | `OriginalCapturePicker.swift:57-146,306-450`, `OriginalCaptureMagnifier.swift:59-114` | OriginalCapture* | no (called from `Capture.swift`) | "original" geometry, black-on-white labels |
| S14 | Countdown | `OriginalCaptureCountdown.swift:13-170` | OriginalCaptureCountdown, OriginalCaptureTiming | no | **`SkitchCount1-3.png`**, `pre-snap-countdown.m4a` |
| S15 | Flash | `OriginalCaptureFlash.swift:26-170` | OriginalCaptureFlash | no | – (white, 0.1 s) |
| S16 | Permission alerts | `Capture.swift:685-687` → `App.swift:1271` | Capture, App | yes (`error(_:)`) | raw NSAlert, no deep link |
| S17 | Prefs — General (+Drawing, Snapping) | `GeneralPreferencesForm.swift:53-155`, `App.swift:1698-1732` | GeneralPreferencesForm, OriginalGeneralPreferences | **yes** | Appearance row + Relaunch, Sounds, tool-tip/keyboard-tip overlay rows (original) |
| S18 | Prefs — Hotkeys | `GlobalHotkeys.swift:558-721`, `:489` | GlobalHotkeys | yes (`shortcutSettings` `:1756`) | "Show Skitch" action, copy about Command+Shift+7 |
| S19 | Prefs — Destinations | `Publishing.swift:908-932`, `PublishingDestinationsView.swift:1-346` | Publishing*, PublishingDestinations* | yes (`openDestinationSettings`) | placeholders with owner-specific paths (`PublishingDestinationsView.swift:214-215`) |
| S20 | History browser | `HistoryBrowser.swift:94-101,252-321` | HistoryBrowser, HistoryStore | yes (`showHistory` `:1415`) | "SKITCH" format; 1120×850 min |
| S21 | Publish progress / success / error | `App.swift:1768-1830` (`publishImage`, `receivePublishing`) | App, Publishing | **yes** | status text only; no progress control; error = `NSAlert(error:)` |
| S22 | Photo browser | `PhotoBrowser.swift:327-418` | PhotoBrowser | yes (`showPhotos` `:1546`) | – |
| S23 | Menus / context menus | `App.swift:918-972`, `:675-715` (Toolbox), `Canvas.swift:130-138,1843-1852`, `App.swift:1620-1660` (Webpost), `MenuSymbols.swift` | App, Canvas, MenuSymbols | **yes** | "Rename…" gated on Appearance; Classic naming; `...` vs `…` |
| S24 | Status item | `App.swift:424-436` | App | **yes** | `menu.png`, `menu-sel.png`, "Skitch" tooltip |
| S25 | About | `App.swift:2176` | App | **yes** | "reconstruction … Skitch 1.0.12" credits |
| S26 | Alerts / sheets | `App.swift:1271,1275,1514,1529,2037`, `PublishingDestinationsView.swift:150` | App, Publishing | **yes** | system fonts, "Skitch" in some messages |
| S27 | First launch / welcome | `App.swift:321-322,355-368` | App | **yes** | `firstlaunch.skitch` (original doc) — owner §4: removed entirely |
| S28 | Keyboard focus | `GlassChrome.swift:226-237`, `Canvas.swift:352,1017` | GlassChrome, Canvas, App | yes | no key-view loop |
| **S29** | Drag-out thumbnail + window zoom | `App.swift:151-182,577-616`, `WindowZoom.swift:91-132` | App, WindowZoom | **yes** | `Skitch_ShowSkitch*`/`Skitch_Cancel_DragMe`, AX "Skitch" |
| **S30** | Hover-hint bevel / tooltips | `OriginalHelpBevel.swift`, `OriginalHintMessages.swift`, `App.swift:447-479,905-913` | OriginalHelpBevel, OriginalHintMessages, App | yes (`trackHint`, `installHintMonitoring`) | original copy `º`, Apple glyph, "Skitch" |
| **S31** | Actual-Size overview panel | `AppViewport.swift:116-172`, `CanvasNavigator.swift:74-254` | AppViewport, CanvasNavigator | yes | Classic-only Actual button |
| **S32** | Crop / border handles | `CanvasBorderView.swift:1-89`, `App.swift:889-897` | CanvasBorderView, WindowSizing | yes (gesture callbacks) | – |
| **S33** | Share picker / Webpost menu | `App.swift:1620-1700` | App | **yes** | – |

---

## 12. Classic dependencies still in the Modern path (verifies declassic §0.3)

| # | Dependency | Evidence (4b2ae0f) | Plan §0.3 | Verified |
|---|---|---|---|---|
| 1 | `GlassChromeButton: OriginalActionButton` | `GlassChrome.swift:18` | ✔ (keep class; no art) | ✔ |
| 2 | `ToolButton.textColor(on:)` | `GlassChrome.swift:179` | ✔ | ✔ (also `AppSafetyModernCases.modernToolSelection`) |
| 3 | PNG fallback chain | `ChromeIcons.swift:3,13-36,49-52`; `GlassChrome.swift:24-25,159`; `ModernEditorChrome.swift:98,186,283` | ✔ | ✔ |
| 4 | `BezelSizeSlider.style = .classic` default + PNG loads | `BezelDrawingControls.swift:105-106,111-112`; Modern sets `.modern` `ModernEditorChrome.swift:236` | ✔ | ✔ |
| 5 | `FrameChromeView.usesRecoveredBezel` + `docWin_*` | `App.swift:6-48`; Modern view constructed at `App+ModernChrome.swift:49` with flag off | ✔ | ✔ (but Modern **still depends on `FrameChromeView`** for Frame-mode hole and window background — only the *bezel code* is removable) |
| 6 | Shared assets: countdown, status item, drag overlays, cursor, sounds, welcome | §6.1 rows 2-5, 7, 9, 10 | ✔ | ✔ |
| 7 | `bezelToolbox()` (shared Toolbox popup built in `App.swift:675`) | used by Modern `App+ModernChrome.swift:51` | not mentioned | **new**: keep, but its menu copy uses `...` and "More Commands" and Skitch-era grouping |
| 8 | `AppDelegate.label()/button()` helpers | `App.swift:648-649`; reused by color popover `:1105,1116` | plan says "delete `recoveredImage`; `button()` stays if Modern uses it" | **Modern uses both** (popover title and "Custom color…") |
| 9 | Classic controls kept alive in Modern | `nameField` (`App.swift:214`), `sizeLabel` (`:218`), `colorWell` (`:216`), `dragFormatControl` popup (`:226`), `actualButton` (`:245`) are created in both; Modern hides/omits them | not mentioned | **new**: dead objects in Modern (nameField used as the document-name model) |
| 10 | `OriginalHelpBevel`/`OriginalHintMessages` | installed for both (`App.swift:899-913`, Modern `App+ModernChrome.swift:117-124`) | partly (§1.3) | ✔ — it is the hover-hint system of Modern too |
| 11 | `Appearance.isModern` branches | `App.swift:719,935,970,1104/1120(Classic aqua)`, `App+ModernChrome.swift:36`, `GeneralPreferencesForm.swift:13,53,164`, `OriginalGeneralPreferences.swift:15,36,55` | ✔ | ✔ |
| 12 | `ChromeAccessibility` lives in `Appearance.swift:54-64` | – | ✔ (move) | ✔ |
| 13 | Min-OS mismatch | `Info.plist:23-24` = 13.0; `build.sh:11` = `arm64-apple-macosx13.0`; `test.py:~74`; test files compile at 13.0 with `@available(macOS 26)` | ✔ | ✔ |
| 14 | `RelaunchLauncher`, `relaunch()`, `runRelaunchSmoke` | `App.swift:1737,2200,2291-2335` | ✔ | ✔ (exists only to switch appearance) |

---

## 13. Identity / migration surface (no real data read)

| Item | Current value | file:line |
|---|---|---|
| Bundle id | `com.shoemoney.skitch-redux` | `Info.plist:10` |
| Bundle name / display / executable / icon | `OpenSkitch` | `Info.plist:6,8,12,20,22`; `build.sh:5` (`APP=…/OpenSkitch.app`), executable copy `build.sh:12` |
| `LSMinimumSystemVersion` | 13.0 | `Info.plist:23-24` |
| Screen-capture usage text | "…annotate in OpenSkitch." | `Info.plist:28` |
| Document types | `OpenSkitch Drawing` (`com.shoemoney.skitch-redux.document`, role Editor), `Original Skitch Drawing` (`com.plasq.skitch.document`, Alternate), `Image` (public.image, pdf) | `Info.plist:36-70` |
| Exported UTI | `com.shoemoney.skitch-redux.document`, ext `skitchredux` | `Info.plist:73-86`, `DocumentModel.swift:185-186` |
| Imported UTI | `com.plasq.skitch.document`, ext `skitch` | `Info.plist:93-105`, `SkitchFile.swift:12` |
| File extensions in code | `.skitch` save default (`App.swift:1326`), `.skitchredux` read, History files `*.skitch` (`HistoryStore.swift:81,112,140,185`), recovery `Recovery.skitch`/`.skitchredux` (`App.swift:348-349,1346,1351,1355`), export/drag format id `"skitch"` (`App.swift:1220,1487,1550-1559`; `HistoryBrowser.swift:45`) | – |
| Document identifiers | formatIdentifier `com.skitch-redux.editable-document` (`DocumentModel.swift:185`), pasteboard `com.skitch-redux.editable-selection` (`Canvas.swift:422`), `com.shoemoney.skitch-redux.native` (`App.swift:1503`), SVG ns `urn:skitch-redux:editable-document:1` (`SkitchFile.swift:13`), SVG ids `skitch-redux-*` (`SVGExport.swift:43,118-124,185`) | – |
| App Support | `~/Library/Application Support/SkitchRedux/` (+ `History/`, `Publishing/`, `FirstLaunchDone`, `layout.json`, `Recovery.*`) | `App.swift:317-318`, `PublishingDestinations.swift:123,134`, `App.swift:347,322,2285` |
| Publishing files | `destinations.json`, `destination.json`, `destination.json.pre-destinations.bak` | `PublishingDestinations.swift:140-143,232` |
| Legacy importer paths | `~/Library/Application Support/Skitch/history`, `~/Pictures/Skitch` | `App.swift:1362,1367` |
| Keychain service | `SkitchRedux.CustomPublishing` (account = destination id) | `PublishingDestinations.swift:70` |
| Defaults domain | `com.shoemoney.skitch-redux` (bundle id) | – |
| Defaults keys (ours) | `statusMenu`, `skitchInSnap`, `disableSounds`, `disableOverlay`, `disableModtips`, `fittingPrecision`, `PencilSmoothing`, `arrowHead`, `appearanceStyle`, `DragFormatChoice`, `DragOriginalSize`, `ExportFormat`, `ExportOriginalSize`, `ExportQuality`, `showCrosshairMagnifier`, `SKPresetResizes`, `SkitchReduxResizePresetID`, `SkitchRedux.GlobalHotkeys.v1`, `SkitchRedux.HistoryDragFormat` | `OriginalGeneralPreferences.swift:9-15`, `DocumentModel.swift:12`, `Appearance.swift:9`, `ImageExport.swift:8`, `App.swift:805,845,1232-1233,1569-1571,1604-1606`, `OriginalCaptureMagnifier.swift:11`, `ResizePresets.swift:144,157`, `GlobalHotkeys.swift:243`, `HistoryBrowser.swift:46` |
| Env vars | `SKITCH_APP_SUPPORT`, `SKITCH_FIXTURE`, `SKITCH_EVIDENCE_DIR`, `SKITCH_APPEARANCE`; tool vars `OPENSKITCH_FETCH_FONTAWESOME`, `OPENSKITCH_NO_PRO_FONTS`, `OPENSKITCH_FA_FONT_DIR`, `APP_SAFETY_*` | `App.swift:317,355,1363,2178,2210,2217,2304`, `Appearance.swift:11`, `EyeDump.swift:6,11`, `PublishingDestinations.swift:125,129`; `build.sh:47-53`, `release.sh:27,30`, `test.py:89` |
| Legacy metadata keys inside documents | `skitchBrushColor`, `skitchBrushColorAlpha`, `skitchBrushSize`, `skitchCustomColor(Alpha)` | `App.swift:1149-1164` |
| Real-store test guard | hashes only `SkitchRedux/Publishing` | `tools/test.py:18` |
| Release / manifest | `minimum_macos: "13.0"` | `build.sh` python tail |

---

## 14. Existing visual tests — what they actually assert

| Suite | Visual claims actually asserted | Weaknesses (can't-fail / mirror / skipped) |
|---|---|---|
| `GlassChromeTests` (`tests/GlassChromeTests.swift`, 1057 lines) | font floor 18 / default 20 for `GlassChromeButton` (`:151-158`); tint model per state incl. IC (`:421-467`); disabled alpha 0.5; ring only with IC; layout of the chrome at several widths: every visible control inside window, ≥18 pt font, title fits (`:672-700`); icon source per state | (a) asserts the **tint property**, not what glass renders; (b) `chrome.accessibility = …` injection tests assert `surface.accessibility == options` (**an input mirror**) and, for `reduceTransparency: true`, pass although **no consumer exists** (§4.6); (c) glyph branch (the real Modern look) **skipped** unless `OPENSKITCH_FA_FONT_DIR`/`build/fonts` (`:96-99`) — a clean clone logs "SKIPPED" and exits 0; (d) macOS < 26 prints SKIP (`:101`) |
| `AppSafetyModernCases` (24 cases; `tests/AppSafetyModernCases.swift`) | `modernCanvasCentred` margins ≤1 pt at default and min size, larger/wide documents unconstrained; `modernCanvasCentredHitTest` (click at visual centre selects the element); `modernTopBarLayout` (every tool inside header at default & min); `modernFrameStatusFits` (hint ≤ label width at 1024); `modernIconOnlyCommands` (label + tooltip per action incl. shortcut from the real menu); `modernToolSelection` | `modernCanvasBleed` tests a **feature that is off in production** by setting `GlassChrome.usesCanvasBleed = true` itself (`:664-699`) — passes whatever the shipped default; `modernFixture()` forces `chrome.accessibility = .none` so the host's real Reduce Transparency/IC can never be observed (`:264-270`); `modernControlStrings` compares Modern against a **live Classic baseline** (`classicBaseline` `:361`) — dies with Classic and, until then, passes if both regress identically (partially mitigated by the literal checks at `:445-447`); `modernWindowStructure` asserts structure (types, targets) not looks; relaunch cases test machinery that only exists to switch appearance |
| `GeneralPreferencesFormTests` | tabs font 20 (`:46`), every control ≥18 / buttons ≥20 at widths (`:325-330`), body labels 20 (`:359`); the form's `modernAvailable` flag is *injected* (`init(state:modernAvailable:)`) | tests build their own precondition for the appearance row (flag passed in); tests the Appearance/Relaunch/Sounds rows that the owner is removing |
| `OriginalCaptureCountdownTests` | timing, cue sequence (1/11/21 etc.), attachment, reentrancy | **entire numeral/sequence/cancellation block is skipped without `original/`** (`:134-146`); the remaining `boundaryInputs`+`geometry` do not exercise the panel; the asserts compare the image size `138×140` to the original PNG |
| `FontAwesomeIconsTests` | table, subset codepoints, chain order | classic artwork cases create their own tiny PNG in a temp bundle (`:176-182`) then assert the chain picks it — precondition built by the test; original-artwork decode skipped (`:193`) |
| `ToolButtonTests`, `AppearanceTests` | Classic ToolButton drawing & font floor; `AppearanceResolver` env/defaults/OS logic | dead after Classic removal |
| `HistoryBrowserTests` | controls ≥18 pt, tile name ≥20 (`:266-268`) | fonts of `NSTextField`/`NSButton` only; segmented/popup menus unchecked |
| `OriginalHelpBevelTests` | font 20, paragraph, geometry | model of text, not pixels |
| `TextStyleFormTests` | accessory text ≥20 and survives resize | – |
| `MenuSymbolsTests` | every mapped action exists in `App.swift`; symbols apply on 26 | – |
| `WindowSizingTests`/`CanvasNavigatorTests`/`CanvasBorderTests` | math & hit regions | not visual |
| `tools/test-native-startup.py` | real launch, glass surface count > 0, `GlassChromeButton` class, relaunch cycles | needs `original/` fixture; relaunch obsolete |
| `tools/eye-dump.sh` + `Sources/EyeDump.swift` | writes PNGs of default / min / Frame / Preferences / annotations for each style | produces images, **asserts nothing**; Classic loop; original fixture |

**There is no test that:** walks every window for fonts <18; counts glass depth; bans decorative glyphs; checks the strings for "Skitch"; verifies the build with `original/` absent; checks contrast; or observes system Reduce Transparency / Differentiate Without Color.

## 15. Right rail inventory (round 2 — owner-required removal, see `technical-spec.md` T15)

**SOURCE-INFERRED, `4b2ae0f`.** Rows in §3.1 (`rightRailWidth`), §4 (`GlassCaptureGroup`, `GlassDrawingGroup`, `GlassHistoryGroup`, size stack), §11 (S03, S06, S09, S12) and §14 describe the **pre-T15** layout; this section is the single place that lists everything that belongs to the rail so none of it is missed. Captures taken before T15 lands show the rail; read each capture's `sourceSha` in `docs/design/evidence/2026-10-09/manifest.json`.

### 15.1 What the rail contains

| Control | Selector / API | Created | Sized | Rail group | Notes |
|---|---|---|---|---|---|
| Snap / Snap Frame | `snapButtonPressed`, alternate `fullscreenSnap` | `ModernEditorChrome.swift:107,315-316` | 56 × 44 (`Metrics.primaryButton`) | `GlassCaptureGroup` (vertical) | primary; icon crosshairs ↔ frame-viewfinder (`syncSnapPresentation` `:184-190`) |
| Cancel (Frame only) | `cancelFrame` | `:108,314,317` | 48 × 36 | `GlassCaptureGroup` | `isHidden` unless `frameMode` (`applyFrameMode` `:177-181`) |
| Color | `showDrawingColors(_:)`, `BezelHoverButton.onHover` | `App.swift:219`, wrapped `ModernEditorChrome.swift:318` | 48 × 36, swatch 28 × 22 (`App.swift:1051`) | `GlassDrawingGroup` | popover opens with `preferredEdge: .minX` (`App.swift:1122`) — only valid for a right-edge control |
| Font | `chooseFont` | `:109,319` | 48 × 36 | `GlassDrawingGroup` | opens the shared Fonts panel (`App.swift:2038`) |
| Size | `changeWidth(_:)`, `onBegin/onEnd` | `App.swift:217`, stack `ModernEditorChrome.swift:320-330` | **36 × 96** control in a 48 × 112 surface (insets 8/6/8/6) | `GlassDrawingGroup` | vertical value mapping `BezelDrawingControls.swift:136-138,171-174`; vector style `:139-149` |
| Undo | `undo` | `:110,331` | 48 × 36 | `GlassHistoryGroup` | shortcut ⌘Z read from the menu |
| Wipe | `wipe` (+ stage retitle) | `:111,332` | 48 × 36 | `GlassHistoryGroup` | located by action as `wipeRailButton` (`App.swift:303,1201-1208`); hint tag 50 |

### 15.2 Geometry and constraints that exist only because of the rail

| Item | file:line | Value / effect |
|---|---|---|
| `Metrics.rightRailWidth` | `GlassChrome.swift:416` | 64 (and the unused `railWidth` 64 beside it) |
| `rightRail` view | `ModernEditorChrome.swift:336-337` | plain `NSView`, three groups pinned centre-X (`:405-409`), stacked with `groupSpacing` 10 |
| Rail position | `:401-404` | trailing = chrome − 12, width 64, top = header.bottom + 8, bottom = footer.top − 8 |
| Canvas coupling | `:411-413` | `scrollView.trailing = rightRail.leading − 8`; `top/bottom` = rail's |
| Reserved column | derived | 64 + 8 = **72 pt** (+ the 12-pt margin) ⇒ viewport = W − 96 |
| Bleed inset | `:417-419` | `right = margin + rightRailWidth + gap` (= 84) |
| Vertical content height of the rail | derived from `GlassChrome` metrics | Frame mode: 86 (Snap 44 + 6 + Cancel 36) + 10 + 196 (Color 36 + 6 + Font 36 + 6 + Size 112) + 10 + 78 (Undo 36 + 6 + Wipe 36) = **380 pt**, against 492 pt of viewport height at the minimum window |
| Evidence writer | `App.swift:2216-2285` (`writeLayoutEvidence`) | does not name the rail; reports `bezelControls`/`popoverShown`/`sizeUndoGrouping` |

### 15.3 Tests that assert the rail (must change with T15; list in `technical-spec.md` T15 §h)

`AppSafetyModernCases.swift:34,134,143-146,148,155-159,179,412,467,872-873` · `GlassChromeTests.swift:568,720,735-757,786-819,809-813,897-900,977` (line numbers `4b2ae0f`). Classic-only slider tests (`AppSafetyTests.swift:3657-3721`) are independent of the rail and unaffected.

### 15.4 Width-relevant sizes (pt) used by the T15 budget

Tool tile 48 × 40 (T15: 44 × 40) · icon pill 48 × 36 · Toolbox 60 × 36 · Snap 56 × 44 · `surfaceSpacing` 6 · `toolSpacing` 4 · `resizeSeparation` 28 (disappears: Resize leaves the tool row) · margins 12 · header/footer rows 44 · title bar 32 (measured from a Classic `eye-dump` frame, `build/startup-smoke-*/layout.json`: window 1024 × 772 for a 740-pt content) · zoom popup fixed at 160 (`ModernEditorChrome.swift:363`, because its face can read `"Output · 100%"`, `App.swift:1184-1188`) · `dragSizeLabel` ≈ 170 pt at 18 pt (separate element today, merged into the status by T15). Text-dependent widths in the budget (zoom capsule, PNG | JPG capsule, Original-size checkbox, merged status) are **ESTIMATES** until `docs/design/evidence/2026-10-09/layout-width-budget.json` exists.

---

*End of inventory.*
