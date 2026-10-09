# OpenSnap todo checklist (visual audit, 2026-10-09, final)

Status of every todo: **pending**. IDs, priorities, milestones, dependencies and Lane A match `visual-audit.md` section 9 exactly. Each section records the main state from section 9 (`dc1eb26`). This file is generated from the same data as `backlog.json`. Edit the source, not the output.

Snapshot: briefed at `b9319c4`; drift to `4b2ae0f` and then `dc1eb26` (checked 11:01 CDT). WP4 (rename) is in flight on `opensnap/w3-rename`. Reconcile each todo against main before starting it (roadmap section 2a). Line numbers, counts and words such as 'today' in substeps and acceptance describe the `4b2ae0f` source unless a todo says otherwise. Estimates are in d, following the round-1 method (one Sonnet implementer-day). Lane A means the todo edits `Sources/App.swift`, which is serial.

Visual validation checklists cite BEFORE capture stems from `evidence/2026-10-09/manifest.json`. A stem with `@dc1eb26` is a capture at the current main SHA; a stem without a suffix is from `b9319c4`.

## Summary

| ID | P | M | Title | Depends on | Lane A |
|---|---|---|---|---|---|
| OSN-001 | P0 | M0 | Adopt the safe audit harness as the only screenshot path | none | yes |
| OSN-002 | P0 | M0 | Owner decisions: Q1 to Q5, D-TEXT, D-HINT, D-T15-1 to D-T15-3 | none | no |
| OSN-010 | P1 | M1 | Remove the right rail; relocate its actions per the T15 mapping | OSN-001, OSN-002, OSN-030 | yes |
| OSN-011 | P1 | M1 | Stroke width: horizontal pill and popover replace the vertical rail slider | OSN-010 | yes |
| OSN-012 | P1 | M1 | Can-fail layout regression tests for the rail removal | OSN-010, OSN-011 | no |
| OSN-013 | P1 | M1 | Rail-removal visual acceptance capture set and Opus review | OSN-012 | no |
| OSN-014 | P1 | M1 | Frame mode: keep overlay scrollers out of the snapped image (verify live first) | OSN-010 | yes |
| OSN-020 | P0 | M2 | WP3 build, runners and gates: clean-clone build and check-no-original | OSN-001 | no |
| OSN-021 | P0 | M2 | WP1: own assets in shared code (drawn digits, system cursor, sounds removed, PNG chain removed) | OSN-020 | yes |
| OSN-022 | P0 | M2 | WP2: remove Classic (window branch, Appearance, relaunch, welcome doc), macOS 26 minimum | OSN-021 | yes |
| OSN-023 | P0 | M2 | Own drawings for the status-item template icon and the drag-thumbnail overlays | OSN-022 | yes |
| OSN-024 | P0 | M2 | Synthetic test fixtures; delete every original/ probe | OSN-020 | no |
| OSN-030 | P0 | M3 | WP4: OpenSnap rename, .opensnap container, copy-never-move migration | OSN-002, OSN-022, OSN-024 | yes |
| OSN-031 | P0 | M3 | All user-visible strings to OpenSnap (menus, About, title, export and History format names) | OSN-030 | yes |
| OSN-032 | P1 | M3 | WP6 copy and docs: hint copy, Toolbox ellipsis, neutral Destinations placeholders, History tab names, analysis retirement | OSN-031 | yes |
| OSN-040 | P1 | M4 | DesignTokens.swift (Typography, Space, Radius, Size, Layout, Palette) and token source gates | OSN-022 | no |
| OSN-041 | P1 | M4 | Type sweep: body 20, caption 18 only, native-text exceptions per D-TEXT | OSN-002, OSN-031, OSN-040 | yes |
| OSN-042 | P1 | M4 | Glass consolidation: one plate per group, solid canvas well, backdrop and bleed deleted, fallbacks | OSN-002, OSN-010, OSN-040 | yes |
| OSN-043 | P1 | M4 | Unified window chrome: title and commands in one bar, autosave, representedURL, full screen per Q4 | OSN-042 | yes |
| OSN-044 | P1 | M4 | Component state model: StateStyles, CommandButton, slider, swatch, drag well, History tile, canvas border rest | OSN-042 | yes |
| OSN-045 | P1 | M4 | Iconography: every chrome icon through Font Awesome; semantic fallbacks; glyph hygiene | OSN-002, OSN-021 | yes |
| OSN-050 | P1 | M5 | Capture surfaces: permission sheet with Open Privacy Settings, drawn countdown, picker and magnifier styling, flash rule | OSN-002, OSN-021, OSN-040 | yes |
| OSN-051 | P1 | M5 | Settings window rebuild: toolbar tabs, no Done, Escape closes, aligned grid | OSN-022, OSN-041 | yes |
| OSN-052 | P1 | M5 | Destinations sheet: scrolling form within the visible height, Return and Escape, 20 pt text | OSN-032, OSN-041 | no |
| OSN-053 | P1 | M5 | History window: content-first grid, centred empty state, toolbar actions, minimum 880 x 600 | OSN-041 | no |
| OSN-054 | P1 | M5 | Upload progress, success and error presentation, with announcements | OSN-010, OSN-044 | yes |
| OSN-055 | P2 | M5 | Menus, About, status item polish (copy, symbols, About credits) | OSN-010, OSN-031 | yes |
| OSN-056 | P2 | M5 | Hover-hint bevel: decide retire or modernise, tokenise, Reduce Motion gate | OSN-002, OSN-032 | no |
| OSN-057 | P2 | M5 | Highlighter stroke: no darker start cap | none | no |
| OSN-058 | P2 | M5 | Resize panel: whole-pixel size display | none | no |
| OSN-060 | P1 | M6 | Keyboard: key-view loop, operable drag well, focus rings, Escape and Return in every sheet | OSN-044 | yes |
| OSN-061 | P1 | M6 | Display-option consumers and an injected DisplayOptions capture mode | OSN-001, OSN-042, OSN-044 | no |
| OSN-062 | P1 | M6 | VoiceOver labels, announcements, and a recorded manual VoiceOver pass | OSN-060 | yes |
| OSN-070 | P0 | M7 | Regression gates in tools/test.py: font-floor walker, glass depth and budget, glyphs, original bytes, Skitch strings, layout fit at 980 | OSN-012, OSN-040 | yes |
| OSN-071 | P0 | M7 | Visual acceptance run: full gallery, light and dark, widths, states, icon modes, and Opus sign-off | OSN-070 | no |
| OSN-072 | P0 | M7 | WP7: migration verified on a copy of the owner's real store; clean-clone build, test and release dry run | OSN-030, OSN-070 | no |

Counts: 36 todos. P0 12, P1 20, P2 4. M0 2, M1 5, M2 5, M3 3, M4 6, M5 9, M6 3, M7 3. Lane A 22.

---

# M0 · Baseline, safety, decisions

## OSN-001 · Adopt the safe audit harness as the only screenshot path

`OSN-001 · P0 · M0 · Status: pending`

**Main state (dc1eb26):** open (harness on unmerged `audit/visual-harness`).

**Findings:** VF-05, VF-06, VF-24. **Spec:** T14.

**User-visible issue.** No end-user symptom. The current screenshot script runs the real bundle id in place with the original fixture, so a visual check can change the owner's live settings and its captures show original Skitch content.

**Implementation substeps**

1. Merge the audit/visual-harness branch (tip 1ab0674 when checked) to main. Its only Lane A change is the 3-line App.swift hook.
2. Make tools/eye-dump-audit.sh the only screenshot path. Retire tools/eye-dump.sh (it runs com.shoemoney.skitch-redux in place with SKITCH_FIXTURE=original/... per VF-06 evidence tools/eye-dump.sh:11-19).
3. Run every capture under an isolated bundle id, a throwaway defaults domain and a throwaway support folder. Do not rely on CFFIXED_USER_HOME for UserDefaults (VF-06 probe).
4. Use a synthetic fixture only. No path under original/ may be read.
5. Hash the real stores (SkitchRedux folder, and its Publishing subfolder) before and after each run. Fail the run on any change. The script already writes safety.txt.
6. Remove the 'welcome' group from the default --groups list (D5: no welcome document). The REAL_ID constant must follow the bundle id change in OSN-030.
7. Decide whether EyeDumpAuditProto.swift stays out of the product target (it is a rail-less mock).
8. Emit manifest entries with sourceSha, plus layout.json and AX dumps. Support FA and SF icon modes as a run parameter.

**File owners** (`Sources/App.swift` is Lane A)

- tools/eye-dump-audit.sh (branch audit/visual-harness, unmerged)
- tools/eye-dump-audit-docs.py, tools/eye-dump-audit-report.py (branch)
- Sources/EyeDumpAudit.swift, Sources/EyeDumpAuditSurfaces.swift, Sources/EyeDumpAuditLayout.swift (branch)
- Sources/EyeDumpAuditProto.swift (branch; rail-less prototype mock, must not ship in the product target)
- Sources/App.swift (Lane A: 3-line --eye-dump-audit hook, branch) **[Lane A]**
- tools/eye-dump.sh (retired)

**Prerequisites**

- Depends on: none
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. No spec figure for the harness. The T14 gate figure (3 d) is booked to OSN-070.

**Measurable acceptance**

- Running the harness leaves the real-store hashes unchanged before and after.
- No run reads any file under original/.
- Every manifest entry carries sourceSha.
- tools/eye-dump.sh is absent from main.
- The baseline gallery at 4b2ae0f reproduces from the harness (visual-audit M0 exit).

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 and S01-editor-empty-dark@dc1eb26 are the baseline the harness must reproduce (same surface, same main SHA).
- Produce FA and SF icon-mode captures of the same surfaces in one run (both are needed until Q1 is decided).
- The run's safety.txt shows the real-store and defaults hashes unchanged before and after. Compare with the hashes recorded in evidence/2026-10-09/safety.txt.

**Regression tests**

- Can-fail check: the real-store hash guard fails the run when a watched store file changes (shown on a scratch copy).
- The harness uses the isolated defaults domain: no write to com.shoemoney.skitch-redux.

## OSN-002 · Owner decisions: Q1 to Q5, D-TEXT, D-HINT, D-T15-1 to D-T15-3

`OSN-002 · P0 · M0 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-05, VF-07, VF-08, VF-11, VF-21. **Spec:** §0, T15 k.

**User-visible issue.** Five open choices (icon licence, document format, top-bar construction, full screen, capture flash), plus the native-text and zoom-control rules, block the work that depends on them.

**Implementation substeps**

1. Q1: record option (a) licence-cleared glyph outlines (IconPaths.swift generated at build time) or option (b) SF Symbols in release (technical-spec section 0).
2. Q2: write docs/adr/0002. The JSON SketchDocument encoding becomes .opensnap (id com.shoemoney.opensnap.document, version 1). SVG stays an export. Old readers move to Sources/Migration/ (section 0).
3. Q3: record NSToolbar (after the spike) or option B custom bars (T4).
4. Q4: record full screen enabled, and Frame mode exited or refused while full screen (T8).
5. Q5: record the flash rule: 0.1 s, no ramp under Reduce Motion, peak 70 % (T10).
6. D-TEXT: record which native-text surfaces are exceptions, and which are replaced (VF-11 options a and b).
7. D-T15-1: zoom face shows the percentage only. D-T15-2: size-pill arrows follow NSSlider. D-T15-3: tool tiles 44 x 40 (T15 sections b, d and k).
8. State in the record that D1 to D5 are already decided (declassic-plan section 4) and are not open.

**File owners** (`Sources/App.swift` is Lane A)

- docs/adr/0002-opensnap-document-container.md (new; Q2, as spec section 0 asks)
- Decision record for Q1, Q3, Q4, Q5, D-TEXT and D-T15-1 to D-T15-3 (location not named in the sources)

**Prerequisites**

- Depends on: none
- Owner decisions: Q1, Q2, Q3, Q4, Q5, D-TEXT, D-HINT, D-T15-1, D-T15-2, D-T15-3 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. No spec figure. Owner time, not implementer time.

**Measurable acceptance**

- Each of Q1, Q2, Q3, Q4, Q5, D-TEXT, D-T15-1, D-T15-2 and D-T15-3 has a recorded answer.
- docs/adr/0002 exists and matches the spec's Q2 text.
- No M1 todo starts with a D-T15 item still open.

**Visual validation checklist**

- None. Decision record only (no capture).

**Regression tests**

- None. Decision record only.

---

# M1 · Owner layout (rail removal)

## OSN-010 · Remove the right rail; relocate its actions per the T15 mapping

`OSN-010 · P1 · M1 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-07, VF-22, VF-26. **Spec:** T15.

**User-visible issue.** A permanent right-hand column reserves about 64 pt of width and shows mostly empty space below the Wipe button. The canvas is narrower than it needs to be. Undo, Wipe, Color, Size, Font, Snap and Cancel sit in that column.

**Implementation substeps**

1. Metrics: GlassChrome.Metrics.toolButton becomes 44 x 40 (D-T15-3). Delete rightRailWidth and railWidth. Add groupGap = 12.
2. Top bar (ModernEditorChrome.build, replacing :254-309): four groups. GlassHeaderLeading (Hide, Toolbox, Photos). GlassCaptureGroup (Snap, Cancel; NSStackView detachesHiddenViews collapses Cancel outside Frame mode). GlassToolBar (10 tools; Resize removed). GlassAnnotationGroup (Color, Size pill, Font).
3. Centre the tool group between the capture group and the annotation group with two NSLayoutGuides of equal width (each at least 12). Retire the priority-750 centerX constraint (:298-299).
4. Bottom bar (replacing :339-376): GlassUndoWipeGroup (Undo, Wipe); GlassViewGroup (zoom capsule, Resize); a status row (Original size checkbox, conditional, then status); GlassSaveGroup (Save, History); GlassFooterRow (PNG | JPG toggle, Drag, Upload; pinned trailing).
5. Zoom popup: wrap in ControlHolderView (:5-25). Face shows the percentage only (D-T15-1). Mode word moves to the item toolTip and the AX value (for example 'Fit, 83%').
6. Delete rightRail (:311-337), sizeStack, the three vertical groups, and the rail width, top and bottom constraints (:401-404).
7. Scroll view: trailing == chrome.trailing - 12; top == header.bottom + 8; bottom == footer.top - 8 (replacing :411-413). Bleed inset right = margin (replacing :419).
8. Status: split updateStatus() (App.swift:1214-1217) into refreshStatusText() (no scheduleDragPreview; no-op while frameMode). updateDragPreview (:1249-1250) writes dragSizeLabel then calls refreshStatusText(). Calling updateStatus() there would re-arm the 1 s timer forever (T15 section i).
9. Colour popover: preferredEdge .minX becomes .minY (App.swift:1122), because Color now sits in the top bar.
10. Relocate each action per the T15 section g table. Keep selectors, shortcuts, AX labels, tooltips and hover hints per section f.
11. Optional: extract frameViewportScreenRect from App.swift:1956-1960; rename wipeRailButton to wipeButton (App.swift:303, :1201-1208).
12. Update the Modern test assertions listed in T15 section h. Re-run the width budget against layout-width-budget.json before merge.
13. Zoom popup menu: add Actual Size as an item with its menu-bar shortcut (VF-22). It costs no bottom-bar width, so no Actual Size button is added to the bottom bar.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/ModernEditorChrome.swift (primary: rebuild :254-421; delete rail :311-337; scroll constraints :411-413; bleed inset :417-419)
- Sources/GlassChrome.swift (Metrics only: toolButton 44 x 40; delete rightRailWidth and railWidth :407, :416; add groupGap 12)
- Sources/App+ModernChrome.swift (:86, :92: keep widthControl wiring; drop dragSizeLabel from SharedControls or keep it off-screen)
- Sources/App.swift (Lane A: :1122 colour popover edge to .minY; :1214-1217 and :1249-1250 status merge; optional :1956-1960 frameViewportScreenRect; optional :303 and :1201-1208 rename wipeRailButton) **[Lane A]**
- tests/AppSafetyModernCases.swift (assertions listed in T15 section h)
- tests/GlassChromeTests.swift (assertions listed in T15 section h)

**Prerequisites**

- Depends on: OSN-001, OSN-002, OSN-030
- Owner decisions: D-T15-1, D-T15-3 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: 2.0 d. T15 sub-items: chrome rebuild 1.0 + App.swift, metrics, status merge and zoom 0.5 + fit-up 0.5 = 2.0 d. The split across OSN-010, 011 and 012 is an assumption (the spec gives sub-items, not per-todo figures). Re-run the width budget when layout-width-budget.json lands.

**Measurable acceptance**

- No view 64 pt wide anchored to the trailing edge. GlassChrome.Metrics has no rightRailWidth or railWidth.
- scrollView.maxX equals chrome.maxX - 12 (within 0.5 pt) at 980, 1024, 1280 and 1440.
- Top bar at 980, Frame mode, needs 946 of 956 usable pt (slack 10). Normal mode needs 892 (slack 64) (T15 section b).
- Bottom bar at 980 keeps the status at 120 pt or more with the Original size checkbox shown (ESTIMATE: 21 pt slack; re-measure).
- Canvas viewport at 980 grows from 884 to 956 pt (T15 section e).
- Frame hole equals the scroll view frame.
- Minimum content height is 608 pt in T15 (492 pt viewport, unchanged). The 680 pt window minimum in T8 is an open item under OSN-043.
- Actual Size is in the Zoom popup menu with its shortcut and AX label. No Actual Size button is added to the bottom bar.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 (rail present), S11-width-980-light@dc1eb26, S12-frame-w980-light@dc1eb26, and PROTO-w980-frame-light@dc1eb26 (rail-less harness mock, not product; it shows the target layout).
- T15 section j items 1 to 4, 8 and 10, light and dark, at 980 (minimum height), 1024, 1280 and 1440: no rail and no blank column; the canvas runs to the 12-pt trailing margin.
- Frame mode at 980 and 1280 (compare S12-frame-mode-light@dc1eb26): Snap reads Snap Frame, Cancel sits beside it, and the hole matches the viewport.
- PNG and JPG in both states at 980: the toggle does not change the bar width (compare S09-format-toggle-png-light@dc1eb26 and S09-format-toggle-jpg-light@dc1eb26).
- Items 5 to 7 and 9 belong to OSN-011, OSN-013 and OSN-042, not this todo.

**Regression tests**

- Existing assertions changed per T15 section h: AppSafetyModernCases.swift:34, :134, :143-148, :155-159, :179, :412, :467, :562-575, :1046-1060; GlassChromeTests.swift:568, :735-747, :753-757, :786-819, :809-813, :897-900, :977.
- Order and ownership (T15 section h test 10): every relocated control's target and action equals the section f table (reuse modernActionRouting, AppSafetyModernCases.swift:831). Fails if a control is re-parented without its action.
- Footer order test extended with Actual Size (GlassChromeTests :746-747).

## OSN-011 · Stroke width: horizontal pill and popover replace the vertical rail slider

`OSN-011 · P1 · M1 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-07, VF-13. **Spec:** T15 d.

**User-visible issue.** The stroke-size control is a tall thin slider that cannot fit in the top bar. Its value is hard to read and it has no text read-out.

**Implementation substeps**

1. Add a .pill style to BezelSizeSlider (keep .classic until WP2 removes it; delete .modern). Pill: 48 x 36 glass-wrapped control, a horizontal line of length 24, thickness equal to the value (1.5 to 12 pt), labelColor, 2 pt focus ring, role .slider.
2. Add showPopover(), dismissPopover(), isPopoverShown. NSPopover .transient, show(relativeTo: bounds, of: pill, preferredEdge: .minY). Guard as onBegin does (App+ModernChrome.swift:61).
3. One gesture API for pill and popover track: beginGesture(), trackValue(fraction:modifiers:), endTracking(), performValueChange(_:continuous:).
4. Keyboard on the focused pill: Right and Up larger, Left and Down smaller, one preset step (2.625). Shift gives 0.1 continuous steps. Each press is one undo group (D-T15-2).
5. Keep accessibilityPerformIncrement and Decrement at plus or minus 2.625 (BezelDrawingControls.swift:134-135).
6. SizePopoverContent (320 x 156): row 1 'Size' (20 pt semibold) and a 20 pt monospaced read-out; row 2 SizeTrackView (288 x 36, five ticks, 20 pt accent knob; Shift continuous, otherwise the five steps); row 3 five SizePresetButtons (48 x 36, AX 'Size 2/4/7/9/12').
7. Popover content is solid: layer background controlBackgroundColor, re-resolved in viewDidChangeEffectiveAppearance. It is not glass.
8. Undo contract: a pointer drag is one undo step (beginGesture on mouse-down, trackValue on drag, endTracking on mouse-up). Add widthControl.dismissPopover() next to the endTracking() calls at App.swift:387 and :493.
9. Keep the hover hint (trackHint on the pill, tag 20) and the dynamic tooltip 'Size N'.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/BezelDrawingControls.swift (.pill style, popover, SizePopoverContent, SizeTrackView, SizePresetButton; delete the .modern vertical drawing; :103-209 plus about 220 new lines)
- Sources/App.swift (dismissPopover calls at :387 and :493. Lane A (visual-audit section 9)) **[Lane A]**
- Sources/App+ModernChrome.swift (keep widthControl wiring :59-64 and hint :122)
- tests/GlassChromeTests.swift (:326-400, :387 loops, :897-900 pill capsule)
- tests/AppSafetyModernCases.swift (:412, widthControl.style .modern becomes .pill)

**Prerequisites**

- Depends on: OSN-010
- Owner decisions: D-T15-2 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: 1.0 d. T15 section i: pill + popover + AX = 1.0 d. The App.swift dismissPopover hunks are required by T15 section d, and section 9 lists OSN-011 as Lane A.

**Measurable acceptance**

- The pill is one 48 x 36 control (hit target at least 36).
- A pointer drag on the track records exactly one undo step; undoManager.groupingLevel is 0 afterwards.
- Shift produces a non-preset value; a plain drag returns only the five preset steps.
- AX role is slider, with value, min and max. Increment and decrement step by 2.625.
- Each selected preset is marked without colour alone (fill plus 2 pt accent border).

**Visual validation checklist**

- Before: S03-rail-light@dc1eb26 (vertical slider) and S06-size-mid-light (b9319c4; the vertical slider with no value read-out).
- T15 section j item 5 at 980 and 1280, light and dark: the popover opens below the pill, on a solid surface, with a Size label, a 20-pt read-out, five ticks and five presets. The selected preset is marked without colour alone. Escape closes it.
- Zoom popup menu (OSN-010 scope): Actual Size is listed with its menu-bar shortcut. Native menu, so this is a manual check (menu windows are a gap, S23).
- Item 7: a size drag on selected text changes its font size, and one undo reverts it.
- Item 11 (non-visual, log it): Space opens the popover and the arrow keys step the value.

**Regression tests**

- Pill semantics (T15 section h test 9): AX role slider, value, min and max; increment and decrement by 2.625; glyph thickness differs between doubleValue 1.5 and 12 (pixel sample); Shift produces a non-preset value. Fails if the pill becomes decorative or loses Shift.
- Slider assertions updated per T15 section h (GlassChromeTests.swift:326-400, :387, :897-900).

## OSN-012 · Can-fail layout regression tests for the rail removal

`OSN-012 · P1 · M1 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-07. **Spec:** T15 h.

**User-visible issue.** Without tests, a future change can quietly bring the rail or its blank column back, or clip a control at the minimum width.

**Implementation substeps**

1. Write T15 section h tests 1 to 8 (listed below) in the two Modern test files.
2. Add the width-budget oracle: compute the section b sums from live Metrics and assert needed <= usable width. Assert minimumWindowWidth is at least the derived worst case.
3. Add the Frame capture-rect test. If OSN-010 extracted frameViewportScreenRect, use it; otherwise add the extraction (3 lines, T15 section e).

**File owners** (`Sources/App.swift` is Lane A)

- tests/GlassChromeTests.swift (new layout tests)
- tests/AppSafetyModernCases.swift (new layout cases)

**Prerequisites**

- Depends on: OSN-010, OSN-011
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 1.0 d. T15 section i: tests (about 10 changed regions, 10 new) = 1.0 d. Assumption: this figure includes the changed-assertion edits, which OSN-010 and OSN-011 do not cost separately.

**Measurable acceptance**

- All eight tests pass on main after OSN-010 and OSN-011.
- Each test's 'fails if' condition is shown to fail on a deliberate revert (mutation check). This is the reading of 'can-fail' the spec asks for.

**Visual validation checklist**

- Before: none (tests only). The layout captures for these tests are taken under OSN-013.

**Regression tests**

- 1 No rail: no view 64 pt wide anchored trailing; no GlassDrawingGroup or GlassHistoryGroup identifier; Metrics has no rightRailWidth.
- 2 Canvas reaches the margin: scrollView.frame.maxX == chrome.bounds.maxX - 12 (0.5 pt) at 980, 1024, 1280 and 1440.
- 3 Every relocated control visible, non-overlapping and inside its bar at 980 x min height, normal and Frame mode (reuse the verifyLayout pair loop, GlassChromeTests.swift near :700).
- 4 Width-budget oracle (see substeps).
- 5 Tool group balanced and stable: gap(B to C) equals gap(C to D) within 0.5; entering Frame mode moves Snap by 0 and the tool group by half of Cancel's slot (27 pt).
- 6 Canvas centred: equal-margin test at the default and minimum viewport, plus a hit-test at the viewport centre.
- 7 Frame capture rect: with a larger canvas, frameViewportScreenRect equals the window's scroll viewport in screen coordinates, and the hole's maxX equals chrome.width - 12. With a smaller canvas, the rect equals the centred canvas and lies inside the hole.
- 8 Stroke popover undo grouping: one undo restores the font size after a drag, a preset click, and a popover dismissed mid-drag (dismissPopover ends the group).

## OSN-013 · Rail-removal visual acceptance capture set and Opus review

`OSN-013 · P1 · M1 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-07. **Spec:** T15 j, §8.

**User-visible issue.** The owner asked for evidence that the rail is gone and that the canvas uses the space. Without captures, that is an assertion.

**Implementation substeps**

1. Run the harness (OSN-001) with the T15 matrix: light and dark x 980 (min height), 1024 x 740, 1280 x 800, 1440 x 900, full screen (1728 x 1117); empty and populated; Frame mode; selection and text editing; the Size popover open; PNG and JPG states.
2. Record each capture's sourceSha. Measure the title-bar height and the popover translucency (R05, R06).
3. Opus reviews the set against T15 section j and the D1 to D10 targets in visual-audit section 3.

**File owners** (`Sources/App.swift` is Lane A)

- docs/design/evidence/2026-10-09/** (capture output; written by the harness)
- tools/eye-dump-audit.sh (run only)

**Prerequisites**

- Depends on: OSN-012
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. Not costed in the spec. Opus review is separate.

**Measurable acceptance**

- Every capture in the T15 matrix exists in the manifest with sourceSha.
- The Opus review is recorded with a pass or the specific failures.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26, S02-populated-light@dc1eb26, S11-width-980-light@dc1eb26, S11-width-1440-dark@dc1eb26, S11-size-fullscreen-dark@dc1eb26 and S12-frame-w980-light@dc1eb26.
- T15 section j items 1 to 10 (item 11 is the keyboard log under OSN-062): each capture shows no rail and no blank column; the canvas runs to the 12-pt margin; no clipped or overlapping control at 980 in either mode.
- Every text is at least 18 pt (20 by default), and each capture records its sourceSha.

**Regression tests**

- None new. The layout.json frames from G7 are checked by OSN-012 test 2 and test 3.

## OSN-014 · Frame mode: keep overlay scrollers out of the snapped image (verify live first)

`OSN-014 · P1 · M1 · Status: pending`

**Main state (dc1eb26):** open (U).

**Findings:** VF-27. **Spec:** T15 e.

**User-visible issue.** In Frame mode a dark horizontal scroller is drawn along the bottom of the capture hole (S12-frame-w980-light@dc1eb26). Whether it ends up in the snapped image is unverified.

**Implementation substeps**

1. Get the owner's Screen Recording grant (or run the live capture with the owner present). Take a Frame snap at 980 with a 2000 x 1400 document, light and dark. Record the result in the evidence set with its sourceSha.
2. If the scroller is not in the snapped output: close the todo with the capture recorded. Make no code change.
3. If the scroller is captured: hide the overlay scrollers in Frame mode and during performFrameSnap (enterFrame :1911 and the snap path), restore them on exit, and keep scrolling working.
4. Add a test that the scrollers are hidden in Frame mode and during the snap, and restored on exit. It fails today.
5. Re-take the Frame set (S12) at 980 and 1024 after the change.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (enterFrame at :1911, scroll-view drawing at :1912-1913, performFrameSnap and the frame capture rect at :1956-1960; Lane A, visual-audit section 9) **[Lane A]**
- tests/AppSafetyModernCases.swift (Frame-mode scroller assertion, only if captured)

**Prerequisites**

- Depends on: OSN-010
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. New todo (round 2). Assumption: 0.5 d covers the live verification, the hide path if the scroller is captured, and one test. The spec gives no figure for this item.

**Measurable acceptance**

- A live capture decides the path, and the result is recorded with its sourceSha.
- If captured: no scroller pixel inside the Frame hole in the snapped output at 980 and 1024, light and dark.
- Scrolling inside Frame mode still works (manual check).

**Visual validation checklist**

- Before: S12-frame-w980-light@dc1eb26, S12-frame-w980-dark@dc1eb26 and S12-frame-w1024-light@dc1eb26 (a dark scroller is drawn inside the Frame hole at 980).
- Live capture (needs the owner's Screen Recording grant): a Frame snap at 980, light and dark, with the 2000 x 1400 document. Record whether the scroller pixels are in the snapped output. This is the decision point.
- If the scroller is captured, the Frame set at 980 and 1024 shows no scroller inside the hole after the change.

**Regression tests**

- Frame scroller state (only if captured): scrollers hidden in Frame mode and during performFrameSnap, restored on exit. Fails today.
- Frame capture rect unchanged: T15 e test 7 (frameViewportScreenRect equals the viewport) stays green.

---

# M2 · Foundation: declassic + clean build

## OSN-020 · WP3 build, runners and gates: clean-clone build and check-no-original

`OSN-020 · P0 · M2 · Status: pending`

**Main state (dc1eb26):** landed (S), except the `check-skitch-strings` gate (not found); verify with a clean-clone build.

**Remaining work:** Verification of the clean-clone build, plus the check-skitch-strings gate, which is not on main.

**Findings:** VF-01, VF-24. **Spec:** T13, T14.

**User-visible issue.** No end-user symptom. Nobody but the owner can build the app, because the build copies files from a private copy of Skitch.app.

**Implementation substeps**

1. Confirm the start state: tools/build.sh has no original/ reference and tools/check-no-original.py exists (visual-audit section 6.0, VF-01).
2. Clone to a temp directory with original/ absent, run the build, then the test runner. Record the result.
3. Run tools/check-no-original.py on the built bundle.
4. check-skitch-strings is not on main (section 9). Add it under this todo, or record the gap and link it to OSN-070.

**File owners** (`Sources/App.swift` is Lane A)

- tools/build.sh (delete the original/ copy block; target macosx26.0; clean the bundle per build)
- tools/test.py (target; single app-safety run; drop the check-dispositions hook; extend the real-store guard in OSN-030)
- tools/test-app-safety.sh (drop --appearance)
- tools/test-app-safety-concurrent.sh (delete)
- tools/test-native-startup.py (single run, no relaunch)
- tools/release.sh (call the new gate)
- tools/check-clean-clone.sh (new; G1)
- tools/check-no-original.py (new; G2)
- tools/check-skitch-strings.py (new; G3 static part; allowed to fail until M3)

**Prerequisites**

- Depends on: OSN-001
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. declassic-plan WP3 sizing (about 0.5 d). The spec gives no separate figure.

**Measurable acceptance**

- A clean clone with original/ absent builds and runs the test suite.
- check-no-original exits 0 on the built bundle.
- check-skitch-strings exists and passes.

**Visual validation checklist**

- No visual check: this is a build and gate todo. The named gate is tools/check-no-original.py (on main). check-skitch-strings is not on main (visual-audit section 9).

**Regression tests**

- G1 clean-clone build (check-clean-clone.sh).
- G2 no-original static and byte-match checks (check-no-original.py).
- G3 static (check-skitch-strings.py), known red until M3.

## OSN-021 · WP1: own assets in shared code (drawn digits, system cursor, sounds removed, PNG chain removed)

`OSN-021 · P0 · M2 · Status: pending`

**Main state (dc1eb26):** landed (S); verify visually (countdown, cursors).

**Remaining work:** Verification: a visual check against the cited S14 captures, plus the source grep gate.

**Findings:** VF-02. **Spec:** T13, T5.

**User-visible issue.** Countdown numerals and the move cursor are original Skitch art. The capture countdown does not appear at all without the original files. The app plays nine original Skitch sounds.

**Implementation substeps**

1. Run the source grep in the acceptance list at the start SHA. Any hit is residue to fix under this todo.
2. Check the countdown numerals at dc1eb26 against the S14 captures (light and dark).
3. Check the system hand cursors and the absence of sound by hand (not in the harness matrix).
4. Check that the sound preference row is gone (S17 captures).
5. Check that the ChromeIcons chain ends at none (visual-audit section 6.0, VF-02).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/OriginalCaptureCountdown.swift (drawn numerals; replace SkitchCount1-3.png at :53-55)
- Sources/Canvas.swift (system hand cursors at :170-178; sound calls :314, :734-752)
- Sources/OriginalGeneralPreferences.swift (delete OriginalSoundEffects :63-81 and the Play sounds row and key)
- Sources/ChromeIcons.swift (chain FA, SF, none; delete .classicArtwork and classicArtworkName(for:))
- Sources/GlassChrome.swift (delete classicArtworkName and selectedClassicArtworkName :24-25, :159; absorb textColor(on:) from ToolButton :179)
- Sources/ModernEditorChrome.swift (delete classicArtworkName uses :98, :186, :236, :283)
- Sources/BezelDrawingControls.swift (delete .classic and the sizeSlider PNG loads :104-112)
- Sources/Capture.swift (remove onSound at :368 and :787)
- Sources/ToolButton.swift (delete)
- Sources/App.swift (Lane A (visual-audit section 9). Sound callbacks at :446, :1814, :1847 per T13 WP1 and declassic section 1.2.) **[Lane A]**
- tests/GlassChromeTests.swift, tests/FontAwesomeIconsTests.swift, tests/OriginalCaptureCountdownTests.swift (updated)
- tests/ToolButtonTests.swift (delete)
- tools/test.py (delete the two suite rows for deleted suites only)

**Prerequisites**

- Depends on: OSN-020
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 1.0 d. declassic-plan WP1 sizing (about 1 d). The spec's T5 chain work is in this figure.

**Measurable acceptance**

- The grep for classicArtwork, sizeSlider, SkitchCount, CursorMove, .m4a and ToolButton in Sources prints 0 lines.
- test ! -e Sources/ToolButton.swift succeeds.
- The countdown shows 3, 2, 1 as drawn numerals, with no original art.

**Visual validation checklist**

- Before (original art): S14-countdown-2-light (b9319c4, Skitch numerals).
- Verify at dc1eb26 against S14-countdown-1-light@dc1eb26, S14-countdown-2-light@dc1eb26, S14-countdown-3-light@dc1eb26 and the -dark@dc1eb26 set: drawn numerals 3, 2 and 1, each non-empty and centred on its plate. The original numerals do not reappear.
- Cursors and sounds are outside the harness matrix: verify by hand (system hand cursors on the canvas; no sound on capture).

**Regression tests**

- CountdownViewTests (no original/): numeral non-empty for 3, 2, 1; each differs; fits the 140 x 140 plate; font at least 18 pt.
- The 31-tick and 61-tick sequences run against the drawn views (at 4b2ae0f they are skipped without original/).
- Source grep (see acceptance) is run by test.py.

## OSN-022 · WP2: remove Classic (window branch, Appearance, relaunch, welcome doc), macOS 26 minimum

`OSN-022 · P0 · M2 · Status: pending`

**Main state (dc1eb26):** landed (S); verify visually (Preferences, first launch).

**Remaining work:** Verification: a visual check against the cited S17 captures and a new first-launch capture, plus the Classic-removal checks.

**Findings:** VF-02, VF-04. **Spec:** T13.

**User-visible issue.** Preferences offers an Appearance choice between Modern and Classic, and a Relaunch button. The app opens a Skitch welcome document on first launch.

**Implementation substeps**

1. Check Preferences General at dc1eb26 against the S17 captures: no Appearance, Relaunch or Play sounds row.
2. Take a first-launch capture with a blank canvas, light and dark (S27 was not re-shot at dc1eb26).
3. Check that no Classic window branch, Appearance preference or Relaunch path remains (visual-audit section 6.0, VF-04).
4. Check that the macOS 26.0 minimum is set in the project (WP2 scope).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: Classic branch 714-859 per plan; FrameChromeView bezel :6-45; recoveredImage :642-650; welcome doc :315, :321-322, :350-364; relaunch :1715-1720; RelaunchLauncher :2258; runRelaunchSmoke :2167; evidence key :2199; un-gate Rename :929-932 and MenuSymbols.apply :964) **[Lane A]**
- Sources/App+ModernChrome.swift (drop @available; style evidence key :36)
- Sources/ModernEditorChrome.swift and Sources/GlassChrome.swift (drop @available)
- Sources/Appearance.swift (delete; move ChromeAccessibility into GlassChrome.swift, append only)
- Sources/GeneralPreferencesForm.swift (Appearance row, radios, Relaunch: :17, :44-81, :107-108, :164, :171, :253)
- Sources/OriginalGeneralPreferences.swift (appearance key and field, :1-60)
- Info.plist (LSMinimumSystemVersion 26.0)
- tests/AppearanceTests.swift (delete)
- tests/GeneralPreferencesFormTests.swift (button count 18 to 15 at :76; drop appearance cases)
- tests/OriginalGeneralPreferencesTests.swift (:117-183)
- tests/AppSafetyTests.swift (one list of 120 or more cases; delete relaunch cases :3181-3260)
- tests/AppSafetyModernCases.swift (delete classicBaseline :226-301 and comparison cases :358-367, :942-949, :968-969)
- tools/test-app-safety.sh, tools/test-native-startup.py, tools/test.py (rows and flags)

**Prerequisites**

- Depends on: OSN-021
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 1.5 d. declassic-plan WP2 sizing (about 1.5 d; 'AppSafety merge is the bulk').

**Measurable acceptance**

- Preferences General at dc1eb26 has no Appearance, Relaunch or Play sounds row.
- First launch shows a blank canvas, with no welcome document (new capture).
- No Classic path remains in Sources or tests.

**Visual validation checklist**

- Before: S17-preferences-general-light (b9319c4: Appearance row, Relaunch, Play sounds).
- Verify at dc1eb26 against S17-preferences-general-light@dc1eb26 and S17-preferences-general-dark@dc1eb26: no Appearance, Relaunch or Play sounds row.
- First launch with a blank canvas, light and dark. Before: S27-first-launch-welcome-light (b9319c4). S27 was not re-shot at dc1eb26 (gaps.md), so a new capture is needed.

**Regression tests**

- AppSafety single list of 120 or more cases (declassic target).
- GeneralPreferencesFormTests: the 15-button count and no appearance cases.
- Startup smoke: glassSurfaces > 0 and GlassChromeButton present (test-native-startup.py).

## OSN-023 · Own drawings for the status-item template icon and the drag-thumbnail overlays

`OSN-023 · P0 · M2 · Status: pending`

**Main state (dc1eb26):** landed (S) as SF template/badges (allowed by owner D5); verify visually.

**Remaining work:** Verification: a visual check against the cited S24 and S29 captures, plus a grep for the original overlay names.

**Findings:** VF-02. **Spec:** T5 §4–5.

**User-visible issue.** The menu-bar icon and the drag-preview badges are original Skitch PNG art.

**Implementation substeps**

1. Check the status item at dc1eb26: a template icon (SF camera.viewfinder, visual-audit section 6.0, VF-02).
2. Check the drag-thumbnail overlays at dc1eb26 against the S29 captures: drawn SF badges, no original plate.
3. Check the 1x and 2x status icon in light and dark menu bars by hand (the harness flattens the status-item captures).
4. Record whether the SF template and badges meet the owner's D5 rule, which allows them (section 9).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/Icons/StatusIcon.swift (new; spec ownership map)
- Sources/App.swift (Lane A: status item PNG load :430-431, :424-436; DragThumbnailView overlays :151-182, :173-178) **[Lane A]**
- tests/StatusIconTests.swift (new; T5 test 3)

**Prerequisites**

- Depends on: OSN-022
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. Part of the T5 figure (1.5 d), which also covers OSN-045. The spec does not split it. Ordering note: the overlay colour is Palette.overlay.hudFill (T2, OSN-040, M4). Until then use a local constant (interpretation).

**Measurable acceptance**

- grep for Skitch_ShowSkitch and Skitch_Cancel_DragMe in Sources prints 0 lines.
- The status icon and drag overlays read correctly at 1x and 2x, light and dark (manual capture, recorded).

**Visual validation checklist**

- Before: S24-statusitem-normal-light (b9319c4: original menu-bar art) and S29-drag-thumbnail-expand-light (b9319c4: Show Skitch plate).
- Verify at dc1eb26 against S24-statusitem-normal-light@dc1eb26, S24-statusitem-highlighted-light@dc1eb26, S29-drag-thumbnail-expand-light@dc1eb26 and S29-drag-thumbnail-expand-dark@dc1eb26: a template status icon and drawn drag badges with no original plate.
- The status-item captures are flattened on a neutral backdrop (gaps.md), so the 1x and 2x check in light and dark menu bars is manual.

**Regression tests**

- StatusIconTests (T5 test 3).
- Source gate: NSImage(named:) and Bundle.main.url(forResource:...png) anywhere in Sources/ fail (T5 test 5).

## OSN-024 · Synthetic test fixtures; delete every original/ probe

`OSN-024 · P0 · M2 · Status: pending`

**Main state (dc1eb26):** open: 5 test files still reference `original/`.

**Findings:** VF-01. **Spec:** T13, T14.

**User-visible issue.** No end-user symptom. Tests read files from the private original/ copy, and several skip silently when it is missing.

**Implementation substeps**

1. Generate the format fixtures in the tests (encoder in the test code). Do not commit a Welcome.skitch (D5 cancels the welcome document).
2. Repoint SVGExportTests, SkitchFileTests and CanvasTests from firstlaunch.skitch to the synthetic document. Re-pin any assertion tied to the old file's content (mixed fonts, README:102) to the synthetic document's known facts.
3. Delete the original/ probes at AppSafetyTests.swift:493 and :552, ResizePresetsTests.swift:259, FontAwesomeIconsTests.swift:57 and :193, and OriginalHintMessagesTests.swift:110 (the rewrite is OSN-032).
4. Change the SKIP-when-absent paths (CanvasTests.swift:79, SkitchFileTests.swift:13, SVGExportTests.swift:63) to hard failures.

**File owners** (`Sources/App.swift` is Lane A)

- tests/AppSafetyTests.swift (:493, :552 hard failures)
- tests/ResizePresetsTests.swift (:259)
- tests/FontAwesomeIconsTests.swift (:57, :193)
- tests/OriginalHintMessagesTests.swift (:110; the rewrite is OSN-032)
- tests/SVGExportTests.swift (:63 SKIP to FAIL; :248-251 fixture)
- tests/SkitchFileTests.swift (:13 SKIP to FAIL; :28, :83 fixture)
- tests/CanvasTests.swift (:79 SKIP to FAIL; :1320-1321, :1375 fixture)
- tools/test.py (fixture arguments)
- tools/test-native-startup.py (fixture)

**Prerequisites**

- Depends on: OSN-020
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. declassic-plan WP5 sizing (about 0.5 d). That figure included authoring Welcome.skitch, which is cancelled (D5). No reduced figure exists in the sources; treat 0.5 as an upper bound.

**Measurable acceptance**

- grep -rn 'original/' tests tools prints 0 (12 at 4b2ae0f; 5 test files still reference original/ at dc1eb26, VF-01).
- python3 tools/test.py 2>&1 | grep -c 'SKIP.*original' prints 0 (declassic done-check).

**Visual validation checklist**

- None (test fixtures; non-visual). Before: none.

**Regression tests**

- Format round trip on the synthetic fixture (SVG export, .skitch and JSON readers).
- The SKIP-to-FAIL change (a missing fixture now fails the suite).

---

# M3 · Identity + migration

## OSN-030 · WP4: OpenSnap rename, .opensnap container, copy-never-move migration

`OSN-030 · P0 · M3 · Status: pending`

**Main state (dc1eb26):** in flight (`opensnap/w3-rename`).

**Findings:** VF-03. **Spec:** T13.

**User-visible issue.** The app is named OpenSkitch. Its data lives in a SkitchRedux folder and a com.shoemoney.skitch-redux preferences domain. The owner's History (58 .skitch files) and destinations must survive the rename.

**Implementation substeps**

1. Identifiers: bundle id com.shoemoney.opensnap; App Support folder OpenSnap; Keychain service OpenSnap.Publishing; environment prefix OPENSNAP_*; UTI com.shoemoney.opensnap.document (declassic section 4 D1).
2. Native format: the JSON SketchDocument encoding becomes .opensnap, version 1 (Q2). SVG stays an export.
3. Drop .skitch and .skitchredux for users: no Open, Save, UTI or association (D3). The migration path alone reads them.
4. Migration.run(oldSupport:newSupport:oldDefaultsDomain:newDefaults:secrets:) is pure over injected URLs, defaults and secret store. It: (1) builds the new tree in a temp sibling and renames it into place atomically; (2) never writes into the old tree; (3) converts each old .skitch and .skitchredux History document to .opensnap, keeps the old file, and records per-document failures without stopping; (4) copies defaults keys, mapping DragFormatChoice to OpenSnap.imageFormat, dropping appearanceStyle and disableSounds, and mapping skitchInSnap to includeAppInSnap, leaving the old domain intact; (5) copies Keychain items from SkitchRedux.CustomPublishing to OpenSnap.Publishing with allowMissing: true, leaving the old items, and notes in the status line that macOS may prompt once per item; (6) is idempotent, with a marker Migration.v1.json in the new folder holding counts and hashes.
5. Copy, never move: folder, defaults domain and Keychain items.
6. Extend the real-store guard (tools/test.py:18-37) to hash both SkitchRedux/ as a whole and OpenSnap/.
7. Call the migration once in applicationDidFinishLaunching, before archiveStore().

**File owners** (`Sources/App.swift` is Lane A)

- Info.plist (bundle id com.shoemoney.opensnap; UTI com.shoemoney.opensnap.document; drop com.plasq.skitch.document per D3)
- Sources/Migration/ (new; holds the only readers of the old SVG-Skitch and JSON formats; move LegacySkitch.swift, SkitchFile.swift, LegacyBridge.swift here)
- Sources/DocumentModel.swift (UTI and extension at :185-186 to .opensnap)
- Sources/App.swift (Lane A: support folder, env vars, error domains, a launch call to the migration) **[Lane A]**
- Sources/PublishingDestinations.swift (folder :134; Keychain service :69-73 to OpenSnap.Publishing)
- Sources/Canvas.swift (pasteboard identifiers :422)
- tests/MigrationTests.swift (new; suite migration-tests)
- tools/test.py (real-store guard :18-37 extended to both folders; new row)
- All files with SKITCH_* environment variables in Sources/, tools/ and tests/ (about 40 sites, declassic section 1.3)

**Prerequisites**

- Depends on: OSN-002, OSN-022, OSN-024
- Owner decisions: Q2 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: 1.0 d. declassic-plan WP4 sizing (about 1 d). That sizing predates D3 and the spec's migration rules (crash injection, Keychain, marker), so treat it as a floor.

**Measurable acceptance**

- PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist prints com.shoemoney.opensnap.
- grep -rn 'SkitchRedux|skitch-redux|SKITCH_' Sources tools tests, excluding Sources/Migration and tests/MigrationTests, prints 0 (about 90 at 4b2ae0f).
- migration-tests pass in a scratch HOME: old folder copied, marker written, old tree untouched.
- The old tree manifest (path, size, mtime, sha256) is byte-identical after the run.
- A re-run is a no-op. Crash injection after N copies leaves no partial new tree.

**Visual validation checklist**

- Before: S17-preferences-general-light@dc1eb26 (shows Show Skitch in:) and S25-about-panel-light@dc1eb26 (shows OpenSkitch).
- After the rename, these surfaces and S01-editor-empty-light@dc1eb26 (title) read OpenSnap.
- The migration has no visual check here; it is verified on a copy in OSN-072.

**Regression tests**

- MigrationTests (G8): old tree byte-identical; new tree complete; documents decode and equal their source; idempotent; crash injection leaves no partial tree; old Keychain items still readable; corrupt documents reported, not fatal.
- Real-store guard covers both folders (tools/test.py).
- Defaults migration (T9): DragFormatChoice 3 maps to JPG (test lives with OSN-030).
- Migration tests use an injected defaults suite and a temp support directory. CFFIXED_USER_HOME alone does not isolate UserDefaults (VF-06 probe).

## OSN-031 · All user-visible strings to OpenSnap (menus, About, title, export and History format names)

`OSN-031 · P0 · M3 · Status: pending`

**Main state (dc1eb26):** in flight (`opensnap/w3-rename`).

**Findings:** VF-03. **Spec:** T12.

**User-visible issue.** The app says 'OpenSkitch' in its menus, title bar, About box and status tooltip. Export and History list a 'Skitch' format. The Preferences window says 'Show Skitch in:'.

**Implementation substeps**

1. Product name constant. T12 places it in DesignTokens.Brand.name, but DesignTokens lands in OSN-040 (M4). Interpretation: put one constant where this todo can reach it, and move it into DesignTokens with OSN-040.
2. App menu: About OpenSnap, Settings, Hide OpenSnap, Quit OpenSnap. File: New, Open, Save, Save As, Rename (unconditional), Export, Publish. Text: Text Style, Default Text Style. Replace every ASCII three-dot ellipsis in menu titles with the ellipsis mark.
3. Toolbox mirrors the main menu exactly, generated from the same table (replacing copiedMainMenuItem).
4. About: standard panel with applicationName, version and build; credits as an 18 pt attributed paragraph 'Capture, annotate, share.' and the MIT licence link. Omit 'Began as a Skitch-inspired rebuild.' from About: T12 contradicts itself here, and the owner's rule (declassic section 4) puts that sentence in the README only.
5. Default title 'OpenSnap' (App.swift:718; App+ModernChrome.swift:22). Default document name 'Untitled' or the document name (T9).
6. Export and History format names: 'OpenSnap' document, no 'Skitch' or 'SKITCH' (ExportAccessory.swift:3-6; HistoryBrowser.swift:45, :315).
7. Status tooltip 'OpenSnap'. Hotkey title 'Show OpenSnap' (GlobalHotkeys.swift:15). Keep the layout of the existing strings; the Settings rebuild is OSN-051.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: menus :918-972; Toolbox :675-715; status tooltip :432; About :2176; default title :718; default document name :131 and :1246) **[Lane A]**
- Sources/App+ModernChrome.swift (default title :22)
- Sources/Canvas.swift (context menus :135, :1847-1849; 'Default Skitch Style' :886, :1849)
- Sources/TextStyleForm.swift (:11, :135)
- Sources/GlobalHotkeys.swift (:15 'Show Skitch')
- Sources/GeneralPreferencesForm.swift ('Show Skitch in:' :44, :107)
- Sources/ExportAccessory.swift (format 'Skitch' :3-6)
- Sources/HistoryBrowser.swift (drag format 'SKITCH' :45, :315; message :56)
- Info.plist (CFBundleName, CFBundleDisplayName, document type 'OpenSnap Drawing')
- tests/MenuParityTests.swift (new; T12)
- tests/AppSafetyModernCases.swift and tests/AppSafetyTests.swift (string and title expectations)

**Prerequisites**

- Depends on: OSN-030
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 1.0 d. T12 is 1 d 'on top of WP4'. The spec puts all of T12 in WP4, so the full 1 d is booked here (assumption). OSN-055 gets no separate figure.

**Measurable acceptance**

- check-skitch-strings (static): no /skitch|openskitch/i match in string literals under Sources/, outside Sources/Migration/, and in Info.plist values (G3 static).
- The About options dictionary contains no 'Skitch' (T12 test).
- Toolbox items are a subset of the main-menu items by action (MenuParityTests).

**Visual validation checklist**

- Before: S17-preferences-general-dark@dc1eb26 (Show Skitch in:), S25-about-panel-dark@dc1eb26 (OpenSkitch credits), S01-editor-empty-light@dc1eb26 (OpenSkitch title), S06-fonts-panel-light (b9319c4: Default Skitch Style), S20-history-empty-light (b9319c4: Saved/DragMe'd).
- After: no Skitch or OpenSkitch string on any of these surfaces, light and dark.
- Export accessory and History format names read OpenSnap (before: S10-export-accessory-alone-light and S20-history-populated-light, both b9319c4).

**Regression tests**

- MenuParityTests (T12): Toolbox matches the menu by action; every item has a symbol or an exemption.
- String gate (static) over menus, Toolbox, status item, About and Info.plist.

## OSN-032 · WP6 copy and docs: hint copy, Toolbox ellipsis, neutral Destinations placeholders, History tab names, analysis retirement

`OSN-032 · P1 · M3 · Status: pending`

**Main state (dc1eb26):** partly landed (hint copy done).

**Findings:** VF-19, VF-23. **Spec:** T12, T13.

**User-visible issue.** Hover hints use the original Skitch wording, an ordinal sign where a degree sign belongs ('45º'), and an Apple logo to mean Command. The Destinations sheet shows the owner's own server paths as examples. History tabs use cramped names.

**Implementation substeps**

1. Rewrite OriginalHintMessages copy in our words, same meaning. Drop the 'copy unchanged' claim (OriginalHintMessages.swift:5-7). º to ° (:59-60). U+F8FF to the word 'Command' (:87). 'option-click to show Skitch' (:125) to OpenSnap wording.
2. Toolbox '...' to the ellipsis mark (App.swift :682-683).
3. Destinations placeholders to neutral examples: https://example.com/uploads, screenshots, the ~/.ssh/config alias, /var/www/site/uploads (T11).
4. History tab names: plain names (All, Posted to Web, Saved, Archived).
5. Delete tools/check-dispositions.py, tools/decompile.sh and tools/ExportDecompiled.java. Untrack analysis/*.json and ignore analysis/.
6. Rewrite the README and HANDOFF prose: H1 'OpenSnap', one factual paragraph that the project began as a Skitch-inspired rebuild, remove the Classic sections.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/OriginalHintMessages.swift (copy rewritten in our words; º to °, :59-60; U+F8FF to 'Command', :87; 'option-click to show Skitch', :125)
- Sources/App.swift (Lane A: Toolbox '...' to '…', :682-683) **[Lane A]**
- Sources/PublishingDestinationsView.swift (placeholders :214-215)
- Sources/HistoryBrowser.swift (tab names: All, Posted to Web, Saved, Archived)
- tests/OriginalHintMessagesTests.swift (table test of our own copy)
- tools/check-dispositions.py, tools/decompile.sh, tools/ExportDecompiled.java (delete)
- tools/make-icon-layers.py (docstring)
- analysis/*.json (untrack); .gitignore (analysis/)
- README.md (H1 'OpenSnap'; one factual history paragraph; delete the Classic, Modern, disposition and macOS 26 sections as the plan says)
- HANDOFF.md (drop the :108 invariant and the Classic rows)
- docs/agents/* (only if they mention Classic)

**Prerequisites**

- Depends on: OSN-031
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. declassic-plan WP6 sizing (about 0.5 d). The Destinations placeholder work sits inside T11 (OSN-052's figure) and is booked here only as a string change (assumption).

**Measurable acceptance**

- No U+F8FF, no º and no ASCII '...' in any user-facing title (G6 static).
- git ls-files analysis | wc -l prints 0 (4 at 4b2ae0f).
- test ! -e tools/decompile.sh and test ! -e tools/check-dispositions.py both succeed.
- No Destinations placeholder contains 'shoemoney'.

**Visual validation checklist**

- Before: S19-destinations-edit-form-light (b9319c4: owner-specific placeholders) and S20-history-empty-light (b9319c4: Saved/DragMe'd tab).
- After: generic example.com placeholders on the Destinations sheet; History tab names read plainly, light and dark.
- Toolbox menu text is in menus.json (menu windows are a gap, S23): check the text there, not a capture.

**Regression tests**

- OriginalHintMessagesTests as a table test of our own copy (replaces the binary diff at :110).
- G6 no-decorative-glyph static scan.
- Placeholder string gate (T11).

---

# M4 · Design-system foundation

## OSN-040 · DesignTokens.swift (Typography, Space, Radius, Size, Layout, Palette) and token source gates

`OSN-040 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-12. **Spec:** T1–T3.

**User-visible issue.** No end-user symptom. Sizes, spacing, corner radii and colours are scattered as literals, so the visual rhythm is uneven (ten corner radii, about 100 constants).

**Implementation substeps**

1. Add DesignTokens.Typography: readableMinimum 18, readableDefault 20; Style cases caption, body, bodyStrong, headline, title, hud, numeric, countdown; font(_:), floored(_:), attributes(_:color:), apply(_:to:) (T1 target).
2. Add Space (s1 to s6 on a 4-pt grid), Radius (sm 4, md 8, lg 12, xl 16, concentric(outer:inset:)), Size (control 36, field 40, row 44, tool 44 x 40, primary 56 x 44, icon 48 x 40, hitMin 36) and Layout (T3).
3. Set Layout.margin to 12, not Space.s4 (16). T3 warns that 16 breaks the T15 width budget unless the lever is changed. Interpretation: keep 12 until the budget is re-run.
4. Add DesignTokens.Palette: every role as a dynamic NSColor with four arms (aqua, darkAqua, and the two accessibilityHighContrast arms). Roles as in the T2 table. Add Palette.resolve(_:for:highContrast:).
5. tools/test.py suite(): append DesignTokens.swift to every suite's source list (T1 step 1). Otherwise any file that adopts tokens breaks its own suite.
6. Add tools/check-tokens.py (G9). It fails on font, constraint, radius and colour literals outside DesignTokens.swift and the allow-lists. Wire it in report mode until OSN-041, OSN-042 and OSN-044 land (interpretation: the spec says it fails today).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/DesignTokens.swift (new; AppKit only, so every suite can compile it)
- tools/test.py (suite() appends DesignTokens.swift to every suite's source list)
- tools/check-tokens.py (new; G9)
- tests/TypographyTests.swift, tests/PaletteTests.swift, tests/MetricsTests.swift (new)

**Prerequisites**

- Depends on: OSN-022
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. T1 'tokens file + tests' = 0.5 d. The T2 Palette (1 d) and the T3 token file are not separately costed in the spec, so they are not booked here (see the roadmap's unsplit list).

**Measurable acceptance**

- TypographyTests: for every Style, font(_:).pointSize is at least 18; body is 20; floored(9 pt) is 18; floored(nil) is 20.
- MetricsTests: every Space value is a multiple of 4; Radius.concentric never falls below sm.
- PaletteTests: in aqua, darkAqua and both high-contrast arms, every text role has contrast at least 4.5 against its surface (3 for 24 pt and above).
- Token file adds no visual change by itself (assumption: captures unchanged after this todo).

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 and S01-editor-empty-dark@dc1eb26 as the pixel reference. A token-only change must leave both unchanged.

**Regression tests**

- TypographyTests, PaletteTests, MetricsTests (T1, T2, T3 tests).
- G9 literal guard (tools/check-tokens.py), in report mode until the sweeps land.

## OSN-041 · Type sweep: body 20, caption 18 only, native-text exceptions per D-TEXT

`OSN-041 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-11. **Spec:** T1.

**User-visible issue.** Much of the interface text is 18 pt, the status line is 18 pt, the zoom popup is 18 pt, and some system text (alert text, tooltips) is about 11 to 14 pt. The owner's rule is 18 pt minimum, normally 20 pt.

**Implementation substeps**

1. Replace the three floors (GlassChrome.swift:58-69; ToolButton.swift, already gone; ModernEditorChrome.swift:213-215) with Typography.floored. Keep GlassChromeButton.font calling it.
2. Sweep file by file in section O order: NSFont.systemFont(ofSize: N), Self.font(N) and label(size:) become Typography.font(.style).
3. Move 18 pt controls to body (20): zoom popup, Original-size checkbox, Color button, all Destinations buttons and captions, Publishing helpers (:1068, :1076), History field names and tile labels, Photos detail and status, Prefs help text. About 12 true captions remain.
4. Custom-drawn text (hint bevel, picker and magnifier labels, the drag plate) uses Typography.attributes.
5. System-owned text: route every NSAlert through an Alert.make(...) helper that sets informativeText in 18 to 20 pt where possible (T1 step 4). Replace NSSavePanel and NSOpenPanel text only where the app owns an accessory. Option (b) and option (a) per D-TEXT.
6. Delete the dead metrics GlassChrome.Metrics.labelPointSize and labeledIconPointSize.
7. Re-measure minimumWindowWidth (980) and the Prefs and History minimums after the widening (R02).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A) **[Lane A]**
- Sources/App+ModernChrome.swift (zoom popup :72, Original-size checkbox :65, Color button :54)
- Sources/GlassChrome.swift (floors :58-69; labelPointSize and labeledIconPointSize dead metrics)
- Sources/ModernEditorChrome.swift (floor :213-215)
- Sources/ExportAccessory.swift, Sources/GeneralPreferencesForm.swift (help text :84), Sources/GlobalHotkeys.swift, Sources/HistoryBrowser.swift (:291, :297, :314, :441, :443), Sources/PhotoBrowser.swift (:279, :373), Sources/Publishing.swift (:1068, :1076), Sources/PublishingDestinationsView.swift (:38, :64, :79, :153, :176, :192, :198, :218), Sources/ResizePanel.swift, Sources/TextStyleForm.swift (:186-231 keep logic, change literal only)
- Sources/OriginalHelpBevel.swift (:32, :57-60), Sources/OriginalCapturePicker.swift (:440), Sources/OriginalCaptureMagnifier.swift (:70), Sources/CanvasNavigator.swift (:156), Sources/BezelDrawingControls.swift
- Sources/Canvas.swift (menus only)
- tests/AppSafetyTests.swift (snapshot expectations; budget the edits)

**Prerequisites**

- Depends on: OSN-002, OSN-031, OSN-040
- Owner decisions: D-TEXT (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: 1.5 d. T1 sweep = 1.5 d (parallel wall about 0.7 d). Sweeping 18 to 20 pt changes many snapshot expectations; the spec says budget the test edits.

**Measurable acceptance**

- Explicit font sites below 18 pt: 0 (0 at 4b2ae0f).
- Only the caption role is 18 pt; every body role is 20 pt.
- The font-floor walker (OSN-070) reports 0 readable text below 18 pt, and 0 controls below 20 pt unless caption.
- The N-exception list is recorded per D-TEXT.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 (status and zoom text), S17-preferences-general-light@dc1eb26 (help text), S20-history-empty-light (b9319c4: field names), and S16-permission-alert-light (b9319c4: about 13-pt message text).
- After: body text at 20 pt; 18 pt only for the caption role (the status line). The zoom popup text is at 20 pt.
- The S16 alert text stays native (about 13 pt) only if D-TEXT option (a) is chosen. Record the exception list.

**Regression tests**

- TypographyTests (from OSN-040) run across every Style.
- tools/check-tokens.py font gate turns green for fonts.
- Snapshot expectations in AppSafetyTests updated for the 20 pt widths.

## OSN-042 · Glass consolidation: one plate per group, solid canvas well, backdrop and bleed deleted, fallbacks

`OSN-042 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-09, VF-10. **Spec:** T4.

**User-visible issue.** The top and bottom bars are a busy row of about 26 separate glass plates, each with its own edge. The canvas surround is a translucent material, so the canvas looks different over different desktops.

**Implementation substeps**

1. Land the T2 and T3 tokens first (OSN-040).
2. Choose option A (NSToolbar, unified, showsBaselineSeparator off) or option B (custom bars) per Q3 (OSN-002). Option A needs the spike: all 16 items unclipped at 980 pt, no overflow chevron.
3. Top bar: one plate per group. Hover, pressed and selected are fills on a rounded layer, not nested glass. Only Snap carries saturated accent.
4. Bottom bar: one GlassSurfaceView (capsule) per group (Undo and Wipe; Zoom and Resize; Save and History; PNG | JPG, Drag, Upload). The status text sits on the solid window surface between groups.
5. Delete the NSVisualEffectView backdrop (ModernEditorChrome.swift:77-78, :238-244), the NSBackgroundExtensionView bleed and GlassChrome.usesCanvasBleed (and its test). Canvas well: surface.canvasWell as underPageBackgroundColor (T2, solid). Glass never overlaps scrollView.frame.
6. Reduce Transparency fallback: GlassSurfaceView.applyTransparencyFallback() sets style .regular and tintColor nil, and inserts a solid controlBackgroundColor plate with a 1 pt separatorColor border, same radius. Observe accessibilityDisplayOptionsDidChangeNotification (ModernEditorChrome.swift:122-124). The toolbar variant relies on the system; state that in the test as unverified.
7. Increase Contrast: 1 pt labelColor at 0.6 border on every glass plate.
8. Concentric corners: group radius xl (16); inner controls concentric (12); capsule footer height / 2.
9. Re-point AppDelegate references (toolButtons, snapButton, cancelFrameButton, resizeButton). Under option A, add a thin adapter for NSToolbarItem views (App.swift:241, :274, :300-301).
10. Delete the tests that cannot fail today: modernCanvasBleed (feature off by default) and the input-mirror accessibility assertions (replaced by G5 test 4).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/GlassChrome.swift (heavy)
- Sources/ModernEditorChrome.swift (backdrop :77-78, :238-251; bleed :417-419; header and footer rebuild)
- Sources/ModernToolbar.swift (new; option A only)
- Sources/App+ModernChrome.swift
- Sources/App.swift (Lane A: references toolButtons, snapButton, cancelFrameButton, resizeButton at :241, :274, :300-301; writeLayoutEvidence :2216-2285) **[Lane A]**
- tests/GlassChromeTests.swift, tests/AppSafetyModernCases.swift
- tests/GlassDepthTests.swift (new; G5)

**Prerequisites**

- Depends on: OSN-002, OSN-010, OSN-040
- Owner decisions: Q3 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. T4: option A 3 d plus 1 d tests (4 d, spec); the roll-up says 3 to 4 d less 0.5 d (3.5 d used in the roadmap). Option B 2 d. Unsplit.

**Measurable acceptance**

- Glass count per window: at most 4 bottom-bar group surfaces plus the system toolbar (option A), or at most 8 (option B). At 4b2ae0f: 26 plus 7 containers.
- No NSGlassEffectView has a glass ancestor or descendant.
- No glass frame intersects the canvas scroll view frame at default, minimum and Frame-mode sizes.
- With reduceTransparency, every surface has an alpha-1 plate and tintColor nil.
- Exactly one saturated-accent element at rest (Snap).
- Canvas well is an opaque surface.color; no NSVisualEffectView behind the canvas.

**Visual validation checklist**

- Before: S03-topbar-light@dc1eb26 and S03-topbar-dark@dc1eb26 (26 glass plates), S02-populated-light@dc1eb26, and S07-zoom-25-light@dc1eb26 (translucent surround).
- After: the two layers read as one. One glass plate per group; the canvas well is flat and solid (T2).
- Reduce Transparency and Increase Contrast at 980 (needs the injected DisplayOptions of OSN-061; the system toggles are not used): bars stay legible on solid plates.
- PNG and JPG in both states at 980 (VF-09 and T9).

**Regression tests**

- GlassDepthTests (G5) tests 1 to 6 from T4: depth, count budget, frame intersection at three sizes, Reduce Transparency plates, HC border, one accent at rest.
- The T14 walker (OSN-070) confirms the glass count and depth in the live tree.

## OSN-043 · Unified window chrome: title and commands in one bar, autosave, representedURL, full screen per Q4

`OSN-043 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open.

**Open items**

- Minimum height is not decided. T15 sets a 608 pt minimum content height (492 pt viewport). T8 sets a 680 pt window minimum. Decide which governs before the minimum-height captures are taken (technical-spec T8 and T15; not settled in visual-audit section 9).

**Findings:** VF-08, VF-21. **Spec:** T8.

**User-visible issue.** The window has a grey title strip above the command bar, forgets its size and position between launches, and cannot enter full screen.

**Implementation substeps**

1. Title: the document name (showDocumentName), fallback 'OpenSnap'. Set representedURL = currentURL through Save, Open and New. Set the subtitle to 'W x H, size' from the live size source (drop the footer label).
2. setFrameAutosaveName('OpenSnap.Main'). Skip center() when a saved frame exists (App.swift:368). Keep titlebarAppearsTransparent false (the Frame-mode hack depends on it).
3. Sizes: default 1120 x 780. Minimum = max(worst-case top-bar width in Frame mode with Cancel visible + 2 margins, bottom-bar width + 2 margins, 980) x 680, computed (T8). The 1000 pt floor is dropped.
4. Full screen (Q4): collectionBehavior.insert(.fullScreenPrimary). In enterFrame (:1883), exit full screen first or refuse with status text. Hide the status-item zoom animation under full screen.
5. Document-scoped alerts use beginSheetModal instead of runModal (App.swift :1271, :1275, :1514, :1529). Resize, Photos, Destinations, Hotkeys and Rename are sheets.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: buildWindow :716-718; center() :368; alerts :1271, :1275, :1514, :1529 to sheets; enterFrame :1883) **[Lane A]**
- Sources/App+ModernChrome.swift (showDocumentName :20-23)
- Sources/AppViewport.swift (minSize :131, :217-218, :269-270)
- Sources/WindowSizing.swift
- Sources/Publishing.swift (makePanel sizes :1062-1065)
- Sources/GlobalHotkeys.swift (Hotkeys sheet 760 x auto)
- Sources/ModernToolbar.swift (unified style, option A only)
- tests/WindowChromeTests.swift (new), tests/WindowSizingTests.swift (re-run)

**Prerequisites**

- Depends on: OSN-042
- Owner decisions: Q3, Q4 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. T8: 2 d, shared with OSN-051 (Settings) and OSN-053 (History minimum). Unsplit. History and Settings sizes are owned by OSN-053 and OSN-051 per section 9.

**Measurable acceptance**

- At the default and at the derived minimum, every control inside the content rect at 20 pt (walker).
- Autosave key restored round-trip in a temp defaults suite.
- representedURL follows currentURL through Save, Open and New.
- Full screen and Frame mode are mutually exclusive (styleMask injection).
- Minimum height matches the decision in Open items below.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 (system title bar above the header row), S11-size-maximized-light@dc1eb26, S11-size-fullscreen-dark@dc1eb26 and S12-frame-mode-light@dc1eb26.
- After: title and commands in one bar. Title and subtitle at 980 and 1280, light and dark.
- Full screen per Q4: Frame mode is not shown in full screen. VF-21 frame-autosave is a source and test check, not a capture.

**Regression tests**

- WindowChromeTests (T8 tests 1 to 4).
- WindowSizingTests re-run (AppViewport minSize math).

## OSN-044 · Component state model: StateStyles, CommandButton, slider, swatch, drag well, History tile, canvas border rest

`OSN-044 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-13, VF-15. **Spec:** T6.

**User-visible issue.** Hover, pressed, disabled and focus states are missing or uneven. The selected tool is a solid accent tile with a black glyph; other tiles differ only by glyph weight. The canvas border is always a bright yellow outline.

**Implementation substeps**

1. StateStyles.command(_:primary:focused:highContrast:differentiate:) as a pure function over ControlState (rest, hover, pressed, selected, disabled), per the T6 table.
2. CommandButton: an NSButton subclass that draws its plate from StateStyles, keeps OriginalActionButton behaviour (secondary click, menu, alternate action; GlassChrome.swift:18), uses an NSTrackingArea for hover, mouseDown for pressed, and keeps the focus-ring mask (:226-237). Interpretation: T4 step 2 names CommandButton, but section 9 orders OSN-044 after OSN-042. Use layer fills for group surfaces in OSN-042 and CommandButton here.
3. BezelSizeSlider: hover and pressed drawing (knob scale 1.15 and 1.25) and the disabled state (BezelDrawingControls.swift:139-163).
4. BezelColorButton: hover, pressed and a check glyph for the selected swatch (:76-99).
5. DragExportView (App.swift:50-148): tracking area, resetCursorRects (open hand, then closed hand while dragging), acceptsFirstResponder true, drawFocusRingMask, accessibilityPerformPress opens the Export panel, role button.
6. History tile: hover and a check badge for the selected tile (HistoryBrowser.swift:425-461).
7. Canvas border rest state: a separator hairline. Handles appear on hover or with the crop tool (VF-15). Keep the gestures (CanvasBorderView.swift).
8. Computed onAccent: take the real blended fill (accent at the used alpha over the plate), not the opaque accent (GlassChrome.swift:179, :324).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/GlassChrome.swift (CommandButton, StateStyles; computed onAccent :179, :324)
- Sources/BezelDrawingControls.swift (slider hover and pressed :139-163; BezelColorButton :76-99)
- Sources/App.swift (Lane A: DragExportView :50-148) **[Lane A]**
- Sources/HistoryBrowser.swift (tile :425-461)
- Sources/ModernEditorChrome.swift
- Sources/CanvasBorderView.swift (rest state; keep the gestures)
- Sources/DesignTokens.swift (ControlState inputs)
- Sources/SegmentedToggle (custom PNG | JPG toggle, T9; file location is an assumption)
- tests/StateStylesTests.swift, tests/CommandButtonStateTests.swift (new); tests/OriginalActionButtonTests.swift (re-run)

**Prerequisites**

- Depends on: OSN-042
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T6: 2.5 d base; the roll-up reduces it by 0.5 d because the rail is gone (2.0 d used). Unsplit.

**Measurable acceptance**

- StateStylesTests: for every state, primary, HC and differentiate flag, the exact fill alpha, content alpha and indicator flags. Disabled never has a hover or pressed fill. Selected with differentiate always has an indicator. Pressed differs from hover. HC is strictly stronger than normal.
- CommandButtonStateTests: layer backgroundColor equals the resolved style.
- Slider knob rectangle scales with hover and pressed.
- DragExportView is first responder; Space and Return invoke the press action.
- Canvas border at rest: separator hairline; no accent outline.

**Visual validation checklist**

- Before: S04-tool-hover-light and S04-snap-hover-light (b9319c4: hover not visibly different from rest), S04-controls-disabled-light (b9319c4) and S28-focus-footer-zoom-light (b9319c4: focus ring).
- After: a capture per state (D6): rest, hover, pressed, selected, disabled and focus, for the tools, Snap, Undo and Wipe, and the size pill; light and dark.
- Canvas border at rest: S01-editor-empty-light@dc1eb26 shows a 1-pt accent outline and four handles today. After this todo the rest state is a separator hairline.

**Regression tests**

- StateStylesTests (T6 pure tests).
- CommandButtonStateTests (drive setHovered, mouseDown, state and isEnabled; assert layer backgroundColor).
- OriginalActionButtonTests re-run (R09).

## OSN-045 · Iconography: every chrome icon through Font Awesome; semantic fallbacks; glyph hygiene

`OSN-045 · P1 · M4 · Status: pending`

**Main state (dc1eb26):** open (the PNG tier is gone; the SF-only Upload and the `trash` fallback remain).

**Findings:** VF-05, VF-25. **Spec:** T5.

**User-visible issue.** Upload and the drag hand use Apple SF symbols next to Font Awesome tools, so stroke weights differ within one bar. Wipe uses a trash icon, which means delete rather than wipe. Some Font Awesome entries are unused.

**Implementation substeps**

1. Add FAIcon cases: upload (cloud-arrow-up), dragHand (hand), check, warning (circle-exclamation). Verify each codepoint against the subset fetch.
2. Route the Upload button (ModernEditorChrome.swift:113-119) and the drag hand (App.swift:71-82) through FAIcon.
3. Wipe fallback: SF eraser.line.dashed (or xmark.bin) instead of trash (FontAwesomeIcons.swift:72). Keep the arrow tool's arrow.
4. Remove unused FA entries maximize, minimize and arrowUpFromBracket, with their subset codepoints.
5. Glyph hygiene: no emoji, starburst or decorative arrows in chrome (gate G6, OSN-070). The ° and Command fixes are in OSN-032.
6. Menu leading icons stay SF (system convention) unless Q1 favours embedded vectors.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/FontAwesomeIcons.swift (new FAIcon cases; remove unused maximize, minimize, arrowUpFromBracket; Wipe fallback at :72)
- Sources/ChromeIcons.swift (confirm the FA, SF, none chain from OSN-021)
- Sources/GlassChrome.swift
- Sources/ModernEditorChrome.swift (Upload SF symbol icloud.and.arrow.up at :113-119)
- Sources/App.swift (Lane A: drag hand SF symbol at :71-82) **[Lane A]**
- Sources/MenuSymbols.swift (change only if Q1 favours embedded vectors)
- tools/fetch-fontawesome.sh (greps hex literals; deleting a case removes its glyph)
- tests/FontAwesomeIconsTests.swift, tests/MenuSymbolsTests.swift, tests/IconCoverageTests.swift (new)

**Prerequisites**

- Depends on: OSN-002, OSN-021
- Owner decisions: Q1 (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. T5: 1.5 d, shared with OSN-023 (the status icon and drag overlays). Unsplit. Codepoints must be verified against the subset fetch; the spec says not to trust the names from memory.

**Measurable acceptance**

- IconCoverageTests: for every FAIcon used by ModernEditorChrome, the resolver returns .fontAwesome when the subset is registered and .sfSymbol otherwise. Both branches run. With OPENSNAP_FA_FONT_DIR absent the suite prints SKIPPED, and the gate fails in CI mode (OPENSNAP_REQUIRE_FA=1).
- Every FAIcon case is referenced by a chrome control.
- No SF symbol and FA glyph mixed within one bar (D7; VF-25).

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 (SF cloud and hand beside the FA tools), S09-footer-light@dc1eb26, and S29-drag-thumbnail-expand-light@dc1eb26 (SF double-arrow badge).
- After: one icon family per bar, in both icon modes (FA in FA mode; SF in SF mode while Q1 is open).
- Upload and the drag hand use the same stroke family as the tools (VF-25).

**Regression tests**

- IconCoverageTests (T5 tests 1 and 2).
- Source gate: NSImage(named:) and png lookups in Sources/ fail (T5 test 5).
- FontAwesomeIconsTests chain ends at none; MenuSymbolsTests unchanged.

---

# M5 · Surface polish

## OSN-050 · Capture surfaces: permission sheet with Open Privacy Settings, drawn countdown, picker and magnifier styling, flash rule

`OSN-050 · P1 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-16. **Spec:** T10.

**User-visible issue.** Screen Recording permission shows one long bold sentence with an OK button only and no way to open System Settings. The countdown and picker use fixed colours and sizes.

**Implementation substeps**

1. Countdown: CountdownNumeralView, a 140 x 140 plate (overlay.hudFill at 0.55; HC 0.8; radius xl) with the digit in Typography.countdown (SF Rounded Heavy 160, white, 2 pt shadow). Keep placement and timing. Under Reduce Motion ignore the alpha stepping (:141) and show the digit at alpha 1.
2. VoiceOver: announce '3, 2, 1' through announcementRequested (the announcement helper is OSN-062).
3. Crosshair and read-out: colours from overlay tokens; read-out Typography.hud on plateFill with Radius.sm; 1 pt separator stroke on the plate.
4. Magnifier: keep 10 x zoom and the 100 x 100 lens. Label uses Typography.numeric. Without Screen Recording, show a diagonal-hatch placeholder with the text 'Screen Recording off' instead of an unexplained grey lens (:103).
5. Flash (Q5): 0.1 s, peak white at 0.7. Under Reduce Motion, no ramp and a single 0.05 s frame. Skip entirely when Reduce Motion is on and the 'Show capture flash' preference is off.
6. Permission pre-flight: if !CGPreflightScreenCaptureAccess(), present PermissionAlert.screenRecording() before any overlay. Title 'OpenSnap needs Screen Recording'. Buttons 'Open System Settings' (x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture) and 'Cancel'. First run calls CGRequestScreenCaptureAccess() after Continue. A failure during capture routes through the same helper (Alert.make).
7. Keep the picker overlay level, fullScreenAuxiliary, and Escape and right-click cancel (tested).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/OriginalCaptureCountdown.swift (CountdownNumeralView; placement :191-221; alpha :141)
- Sources/OriginalCaptureFlash.swift (ramp :6-23)
- Sources/OriginalCapturePicker.swift (overlay colours :421-446)
- Sources/OriginalCaptureMagnifier.swift (label, placeholder :103)
- Sources/Capture.swift (pre-flight; alert text :685-687)
- Sources/App.swift (Lane A: alert wiring :1271) **[Lane A]**
- tests/OriginalCaptureCountdownTests.swift, tests/CaptureTests.swift, tests/OriginalCapturePickerTests.swift

**Prerequisites**

- Depends on: OSN-002, OSN-021, OSN-040
- Owner decisions: Q5, D-TEXT (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: 1.5 d. T10 = 1.5 d. This todo covers all of T10, so the figure is exact. T10 also needs T7's DisplayOptions for Reduce Motion, which section 9 places in OSN-061 (M6). Until then gate on the existing NSWorkspace check (assumption).

**Measurable acceptance**

- CountdownViewTests: non-empty alpha for 3, 2, 1; each digit differs; the numeral fits the 140 x 140 plate; font at least 18 pt.
- The 31-tick and 61-tick sequences run against the drawn views, not skipped.
- Reduce Motion gives a constant alpha of 1 for the countdown.
- With preflight false, the permission alert with the Settings button is shown and the picker does not start.
- Magnifier placeholder text present when there is no screen image.
- Flash peak is at most 0.7.

**Visual validation checklist**

- Before: S16-permission-alert-light and S16-permission-alert-dark (b9319c4: long bold sentence, OK only), S14-countdown-2-light@dc1eb26, S13-picker-synthetic-lens-light (b9319c4), and S15-flash-full-light (b9319c4).
- After: short message, informative text, Open Privacy Settings and Cancel, light and dark. The sheet is app-owned at 20 pt (D-TEXT default).
- Countdown, picker and magnifier in light and dark. The flash respects Reduce Motion (Q5).

**Regression tests**

- OriginalCaptureCountdownTests (drawn numerals), CaptureTests (preflight routing), OriginalCapturePickerTests (picker unchanged).

## OSN-051 · Settings window rebuild: toolbar tabs, no Done, Escape closes, aligned grid

`OSN-051 · P1 · M5 · Status: pending`

**Main state (dc1eb26):** open (Classic rows already gone).

**Findings:** VF-18. **Spec:** T8, T11.

**User-visible issue.** Preferences is an old tabbed box with a Done button, mixed alignment and ASCII ellipsis dots. Its title and structure are Classic-era.

**Implementation substeps**

1. NSTabViewController with tabStyle .toolbar. Tabs: General, Drawing, Capture, Upload. Title equals the selected tab. No Done button; changes apply live. Size 640 wide, height per tab. isRestorable frame. Escape closes (cancelOperation calls closePreferences).
2. General: Dock, Menu bar, Both presence; 'Show OpenSnap window in fullscreen and crosshair snaps'; tool-tip overlays; keyboard-tip overlay.
3. Drawing: precision, arrow head. Capture: shortcuts inline (the Hotkeys form), flash preference. Upload: destinations list.
4. Row labels right-aligned, 20 pt bodyStrong. Control column body. 16 pt rhythm (Space.s4). One aligned form grid (checkboxes align with the radio label column, VF-18).
5. Remove the Appearance and Play sounds rows and the Relaunch button (done in OSN-022; verify).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/GeneralPreferencesForm.swift (becomes four small view controllers)
- Sources/OriginalGeneralPreferences.swift (keys; sounds gone)
- Sources/GlobalHotkeys.swift (form embedded in Capture)
- Sources/PublishingDestinationsView.swift (list embedded in Upload)
- Sources/App.swift (Lane A: showPreferences :1698-1732) **[Lane A]**
- tests/GeneralPreferencesFormTests.swift (re-baseline the appearance references), tests/GlobalHotkeysTests.swift, tests/PublishingDestinationsTests.swift

**Prerequisites**

- Depends on: OSN-022, OSN-041
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T8 (Prefs structure) and T11 (Prefs tabs) share T8's 2 d and T11's 3 d. Unsplit.

**Measurable acceptance**

- No row labelled Appearance or Sounds. No Done button. Escape closes the window.
- Each tab's fitting size is at most the visible height of a 1280 x 800 fake screen (T8 test 5).
- Return and Escape bindings per sheet (T7 test 4).

**Visual validation checklist**

- Before: S17-preferences-general-light@dc1eb26 and S17-preferences-general-dark@dc1eb26 (Done button, NSTabView box), S17-preferences-alt-values-light@dc1eb26, and S18-hotkeys-sheet-light (b9319c4).
- After: toolbar tabs, no Done button, Escape closes, title Settings, one aligned grid sized to its content, light and dark.
- Default and minimum window sizes: each tab's fitting size is no taller than the visible screen.

**Regression tests**

- GeneralPreferencesFormTests re-baselined; new tests: no Appearance or Sounds row; Escape closes; fitting size per tab.

## OSN-052 · Destinations sheet: scrolling form within the visible height, Return and Escape, 20 pt text

`OSN-052 · P1 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-19. **Spec:** T11.

**User-visible issue.** The Destinations sheet is taller than many laptop screens and does not respond to Return or Escape. The default destination is marked with the text '(Default)'.

**Implementation substeps**

1. Sheet 720 wide, height min(720, visibleFrame - 120). The form sits in an NSScrollView (Publishing.swift:909).
2. Group fields into 'Connection' and 'Credentials' with headline section headers.
3. Buttons at body (20). Default (Return) is Save. Escape is Cancel (keyEquivalent on PublishingDestinationsView.swift:36-40, :221-224).
4. Test result is an inline status row with a check or cross FA glyph and text, not colour alone.
5. The list shows the default destination with a 'Default' pill (text and check) instead of the '(Default)' string (:90).
6. Message sheets have a minimum width of 560 (Publishing helpers).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/PublishingDestinationsView.swift (Return and Escape :36-40, :221-224; Default pill :90)
- Sources/Publishing.swift (sheet size :909 from 820 x 860 to 720 x min(720, visibleFrame - 120); helpers :1062-1099)
- tests/PublishingDestinationsTests.swift

**Prerequisites**

- Depends on: OSN-032, OSN-041
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T11 = 3 d for OSN-051, OSN-052 and OSN-053 together. Unsplit.

**Measurable acceptance**

- Sheet height is at most the visible frame on a 1280 x 800 fake screen, with scrolling when needed.
- Return saves and Escape cancels (tests).
- The test-result row carries a glyph and text.

**Visual validation checklist**

- Before: S19-destinations-edit-form-light, S19-destinations-list-light and S19-destinations-empty-light (all b9319c4: 820 x 860 sheet, owner-specific placeholders, no default button).
- After: a scrolling form no taller than the visible height, Return and Escape defaults, generic placeholders, at 980 and 1280, light and dark.
- Short-height display: scrolling present; test-result states captured.

**Regression tests**

- Keyboard defaults test per sheet (T7 test 4). Placeholder string gate (OSN-032).
- Shutdown barrier with the sheet open (Publishing.swift:868-880, R18).

## OSN-053 · History window: content-first grid, centred empty state, toolbar actions, minimum 880 x 600

`OSN-053 · P1 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-20. **Spec:** T11.

**User-visible issue.** History opens as a form. Its empty state is a large blank box with a line of text, seven disabled buttons sit in two rows, and the window is too big for a laptop.

**Implementation substeps**

1. Default 1000 x 720, minimum 880 x 600. Adaptive flow-layout grid (item 210 x 234). The details panel collapses below the grid when the width is under 760 pt.
2. Filter row (segmented category, search, date popup) in the window toolbar under option A; otherwise in the content area.
3. Selection cue: accent border and check badge (T6).
4. Empty state: centred text, 'No history yet. Press ⌘S…' per T11. Interpretation: section f lists Save to History with no shortcut ('—'), so confirm the ⌘S text before use.
5. Move the seven disabled actions to the toolbar or a context menu. Drag formats: PNG, JPG, PDF, TIFF, SVG, and .opensnap.
6. Warning rows use the 'Error:' prefix (T7).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/HistoryBrowser.swift (minimum size :96 from 1120 x 850; tile :425-461; format popup; filters)
- Sources/HistoryStore.swift (strings)
- tests/HistoryBrowserTests.swift

**Prerequisites**

- Depends on: OSN-041
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T11 = 3 d for OSN-051 to OSN-053 together. Unsplit.

**Measurable acceptance**

- Minimum window 880 x 600. The grid reflows and has no horizontal scroll at the minimum (T8 test 6).
- The selection cue (check badge) is present for the selected tile (T11; fails today).
- Empty state is centred.

**Visual validation checklist**

- Before: S20-history-empty-light, S20-history-populated-light and S20-history-selected-light (all b9319c4: form-first layout, one thumbnail per row).
- After: content-first grid with a centred empty state and actions in a toolbar or context menu, at 880 x 600, 1120 x 850 and 1280, light and dark.
- Selection cue visible on a populated grid.

**Regression tests**

- HistoryBrowserTests: reflow at the minimum; selection cue; drag-format list.
- T8 test 6 (minimum size).

## OSN-054 · Upload progress, success and error presentation, with announcements

`OSN-054 · P1 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-17, VF-26. **Spec:** T9, T11.

**User-visible issue.** Upload gives one status string that truncates, and a modal alert on failure. There is no progress, no success styling, and no retry.

**Implementation substeps**

1. UploadState on AppDelegate: .idle, .uploading(name), .success(url, copied), .failure(message).
2. While uploading, the footer shows a 20 pt indeterminate NSProgressIndicator, 'Uploading <name>…', and an inline Cancel (cancelUpload, App.swift:1659).
3. On success: 'Link copied' for 4 s, an announcement, and an Open or Copy affordance.
4. On failure: inline 'Error: <message>' with Retry and Details. This replaces NSAlert(error:) at App.swift:1795-1812, except destination-not-configured, which still opens Settings.
5. Keep the shutdown barrier working: the inline error path must not break finishShutdownDecision (App.swift:403-417).
6. The upload row hides the Original-size checkbox while uploading and lets the name truncate. Do not widen the bar (T9 risks).
7. Post the announcement on start, success and error (NSAccessibility.post, announcementRequested).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: upload :1758-1812; cancelUpload :1659; shutdown barrier :403-417) **[Lane A]**
- Sources/ModernEditorChrome.swift (footer status slot; progress indicator)
- Sources/App+ModernChrome.swift
- Sources/PublishingDestinationsView.swift (state hooks)
- tests/UploadStateTests.swift, tests/FooterLayoutTests.swift (new); tests/AppSafetyModernCases.swift, tests/ExportAccessoryTests.swift, tests/ImageExportTests.swift (byte-level tests kept)

**Prerequisites**

- Depends on: OSN-010, OSN-044
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T9 = 2 d for the whole footer, export, drag and upload work. It is not split across OSN-054 and the footer rows in OSN-010 and OSN-042. Unsplit.

**Measurable acceptance**

- UploadStateTests: idle to uploading to success or failure, via the injected uploader seam. Cancel returns to idle. Retry re-invokes with the same payload. Error text begins 'Error:'.
- FooterLayoutTests at minimum width: the status truncates before any control clips. The toggle exposes two AX children, 'PNG' and 'JPG'.
- Byte-level tests for drag, export, upload and History still produce the same bytes.

**Visual validation checklist**

- Before: S21-publish-progress-footer-light (progress is text only), S21-publish-success-footer-light (URL cut mid-string), S21-publish-error-footer-dark, and S21-upload-menu-busy-light (all b9319c4; no S21 capture exists at dc1eb26).
- After: determinate or indeterminate progress on the Upload control; success reads Link copied with Open or Copy; errors are announced and prefixed. Light and dark at 980 and 1280.
- PNG and JPG in both states at 980 (T9 and T15 j item 8). The status keeps the upload verb at 980 (VF-26); compare S09-footer-long-status-light@dc1eb26.

**Regression tests**

- UploadStateTests, FooterLayoutTests, and the kept byte-level tests.
- Quit during a failed upload (R15).

## OSN-055 · Menus, About, status item polish (copy, symbols, About credits)

`OSN-055 · P2 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-23. **Spec:** T12.

**User-visible issue.** The status item only toggles the window instead of opening a menu.

**Implementation substeps**

1. Status item: menu on click, with Show or Hide OpenSnap, Snap, Preferences and Quit (T12). Tooltip 'OpenSnap'.
2. Toolbox mirrors the main menu (MenuParityTests).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: menus; status item menu) **[Lane A]**
- Sources/App+ModernChrome.swift
- Sources/MenuSymbols.swift
- tests/MenuParityTests.swift (new), tests/AppSafetyModernCases.swift, tests/GlassChromeTests.swift (footer order)

**Prerequisites**

- Depends on: OSN-010, OSN-031
- Owner decisions: D-TEXT (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. No separate figure. T12's 1 d is booked to OSN-031. Actual Size is an item in the Zoom menu under OSN-010, so it adds no bottom-bar width.

**Measurable acceptance**

- The status item menu has the four items above.
- MenuParityTests pass.

**Visual validation checklist**

- Before: S25-about-panel-light@dc1eb26 and S25-about-panel-dark@dc1eb26 (credits line with Skitch 1.0.12), S24-statusitem-normal-light@dc1eb26, and S11-width-980-light@dc1eb26 (bottom bar at 980).
- After: About credits are clean at 18 pt, the status item tooltip and menu copy are fixed, and nothing clips in the bottom bar at 980.
- The status item menu and the Zoom menu are native: manual capture, because menu windows are not in own-window composites (gaps S23).

**Regression tests**

- MenuParityTests (T12).

## OSN-056 · Hover-hint bevel: decide retire or modernise, tokenise, Reduce Motion gate

`OSN-056 · P2 · M5 · Status: pending`

**Main state (dc1eb26):** open (copy already rewritten).

**Findings:** VF-14, VF-23. **Spec:** T7, T12.

**User-visible issue.** The hover hint is a custom-drawn bevel with fixed colours and a fade that ignores Reduce Motion.

**Implementation substeps**

1. Decide retire or modernise. This decision is not in OSN-002 (flagged). Interim: T7 says the bevel 'remains optional'; modernise it and keep it, and let the owner decide retirement.
2. Tokenise: Typography.hud (20 pt medium) on the plate; overlay.hudFill and hudText; white at 0.95 stroke; Radius.lg (12) as T3 maps the hint bevel.
3. Reduce Motion: skip the fade (OriginalHelpBevel.swift:255-279). Until OSN-061 lands, use the existing NSWorkspace check (assumption).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/OriginalHelpBevel.swift (:32, :57-60, :90-92, :255-279)
- Sources/OriginalHintMessages.swift (copy already rewritten in OSN-032)
- tests for OriginalHelpBevel (existing tests; not named in the sources)

**Prerequisites**

- Depends on: OSN-002, OSN-032
- Owner decisions: D-HINT (see the roadmap, section 3)

**Scope and estimate assumptions**

- Estimate: not split in the spec. Part of the T7 figure (2 d, shared with OSN-060, 061 and 062). Unsplit. The retire or modernise decision is not in OSN-002; see the roadmap.

**Measurable acceptance**

- With Reduce Motion, the hint shows at its final alpha with no intermediate steps (tick sequence equals [final]).
- The bevel uses only token values (no literals).

**Visual validation checklist**

- Before: S29-help-bevel-light@dc1eb26 and S29-help-bevel-dark@dc1eb26 (HUD forced on; the text is cut off at the top of the capture).
- After (D-HINT default: opt-in, off by default, modernised): a solid HUD plate, 20-pt text, token colours, and no clipped text at 980, light and dark.
- Reduce Motion: the bevel does not animate (T7). The harness cannot force Reduce Motion, so check it with the injected DisplayOptions of OSN-061.

**Regression tests**

- DisplayOptionsTests (T7 test 2) for the hint bevel once OSN-061 lands.

## OSN-057 · Highlighter stroke: no darker start cap

`OSN-057 · P2 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-28. **Spec:** none in the spec (canvas content rendering).

**User-visible issue.** The first cap of each highlighter stroke renders olive or grey against the pale-yellow body (S02-populated-light@dc1eb26).

**Implementation substeps**

1. Locate the highlighter stroke draw path. The preset is the translucent highlighter (alpha 0.35, BezelDrawingControls.swift:30).
2. Draw the whole stroke once into a transparency layer and composite the layer at the stroke alpha, so overlapping segments and the start cap are not composited twice (VF-28 direction).
3. Keep the stroke geometry and round caps unchanged. Only the compositing changes.
4. Re-take S02 populated with a highlighter stroke, light and dark.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/Canvas.swift or the annotation stroke renderer (locate the highlighter draw path at the start SHA; the preset is at Sources/BezelDrawingControls.swift:30 and Sources/OriginalHintMessages.swift:145)
- tests/CanvasTests.swift (new rendering case)

**Prerequisites**

- Depends on: none
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.25 d. New todo (round 2). Assumption: 0.25 d for the compositing change and one pixel test. The spec gives no figure for this item.

**Measurable acceptance**

- The start-cap colour equals the body colour (no darker cap) in a pixel sample at the stroke start.
- Stroke geometry (length, width, caps) is unchanged.

**Visual validation checklist**

- Before: S02-populated-light@dc1eb26 and S02-populated-dark@dc1eb26 (a darker olive or grey cap at the start of the highlighter stroke).
- After: the first point of the highlighter stroke matches its body (pale yellow, no darker cap), light and dark.
- The other annotation kinds in S02 are unchanged (a pixel diff outside the highlighter stroke).

**Regression tests**

- Canvas rendering test: the first-cap pixel colour and alpha of a highlighter stroke match its body. Fails with the current double composite.
- Existing canvas stroke tests stay unchanged.

## OSN-058 · Resize panel: whole-pixel size display

`OSN-058 · P2 · M5 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-29. **Spec:** T11.

**User-visible issue.** The Resize panel shows fractional pixel sizes, such as 1516.5 (S08-resize-panel-light, b9319c4).

**Implementation substeps**

1. Find where the width and height fields format their value (ResizePanel.swift around :502).
2. Round the displayed value to whole pixels. Keep the internal value at full precision so proportional math is unchanged.
3. Keep typed-value parsing as it is: a typed 1516 stays 1516.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/ResizePanel.swift (dimension fields, around :502; display rounding only, keep the internal precision)
- tests/ResizePanelTests.swift (display rounding case)

**Prerequisites**

- Depends on: none
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.25 d. New todo (round 2). Assumption: 0.25 d for display rounding and one test. T11 gives no per-item figure.

**Measurable acceptance**

- Width and height fields never show a decimal point.
- Proportional lock gives the same results for the same inputs.

**Visual validation checklist**

- Before: S08-resize-panel-light, S08-resize-panel-dark and S08-resize-panel-in-context-light (all b9319c4: the width reads 1516.5).
- After: width and height fields show whole pixels, light and dark. A typed value round-trips unchanged.
- No S08 capture exists at dc1eb26. Take one with the change; the b9319c4 set is the before.

**Regression tests**

- ResizePanelTests: a stored 1516.5 displays as a whole pixel under one fixed rounding rule (the implementer records the rule); the internal value stays 1516.5; a typed value round-trips.

---

# M6 · Accessibility + adaptivity

## OSN-060 · Keyboard: key-view loop, operable drag well, focus rings, Escape and Return in every sheet

`OSN-060 · P1 · M6 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-14. **Spec:** T7.

**User-visible issue.** Keyboard users cannot reach the drag well. There is no key-view loop across the window. Some sheets do not respond to Return or Escape.

**Implementation substeps**

1. window.autorecalculatesKeyViewLoop = true; initialFirstResponder = canvas. Explicit loop: top bar left to right, canvas, bottom bar left to right. Set nextKeyView only for the Size and Color popovers (T15 section f).
2. Each custom view exposes focusRingType and a mask. CommandButton and GlassChromeButton honour Full Keyboard Access (canBecomeKeyView).
3. Tab from the canvas keeps tool switching ('tab = Pen' in OriginalHintMessages). Document Control-F5 and FKA, and add a menu command 'Focus Toolbar' (R11).
4. Drag well: acceptsFirstResponder; Space and Return perform Export (T6 and T7).
5. Escape and Return: Preferences cancelOperation calls closePreferences. Destinations: Return saves, Escape cancels. Resize, Photos, Hotkeys: keyboard defaults. History: Return opens, Escape closes. NSAlerts already handle both.

**File owners** (`Sources/App.swift` is Lane A)

- Sources/App.swift (Lane A: DragExportView press; initialFirstResponder; Focus Toolbar menu command) **[Lane A]**
- Sources/ModernEditorChrome.swift (key-view loop; nextKeyView for the Size and Color popovers)
- Sources/GlassChrome.swift (canBecomeKeyView honours Full Keyboard Access)
- Sources/GeneralPreferencesForm.swift (Escape), Sources/PublishingDestinationsView.swift (Return and Escape), Sources/HistoryBrowser.swift (Return opens, Escape closes), Sources/ResizePanel.swift, Sources/PhotoBrowser.swift, Sources/GlobalHotkeys.swift
- tests/AccessibilityAuditTests.swift (new; key-loop and Escape and Return tests)

**Prerequisites**

- Depends on: OSN-044
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T7 = 2 d, shared with OSN-056, 061 and 062. Unsplit.

**Measurable acceptance**

- Key-loop test: from the first control, walking nextValidKeyView visits every enabled control once and returns (T7 test 3).
- Escape and Return test per sheet via performKeyEquivalent (T7 test 4): Prefs, Destinations, Resize, Photos, Hotkeys.
- Visible focus ring on keyboard focus for each control.

**Visual validation checklist**

- Before: S28-focus-topbar-tool-light, S28-focus-topbar-hide-light, S28-focus-footer-format-light, S28-focus-footer-upload-light and S28-focus-footer-zoom-light (all b9319c4: faint focus rings), and S19-destinations-form-focus-light (b9319c4).
- After: a visible focus ring on each control in the key-view loop, captured with keyboard focus, light and dark.
- Key-view order is checked by the test in the acceptance list, not by a capture.

**Regression tests**

- AccessibilityAuditTests key-loop and Escape and Return tests (T7 tests 3 and 4).
- DragExportView: Space and Return invoke press.

## OSN-061 · Display-option consumers and an injected DisplayOptions capture mode

`OSN-061 · P1 · M6 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-10, VF-14. **Spec:** T7, T14.

**User-visible issue.** Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color are ignored by most of the interface. The captures cannot show them because the system toggles were not changed.

**Implementation substeps**

1. Introduce DisplayOptions (reduceMotion, reduceTransparency, increaseContrast, differentiateWithoutColor), read live and observed through NSWorkspace.accessibilityDisplayOptionsDidChangeNotification. It replaces ChromeAccessibility.
2. Every window with custom drawing observes it (today only ModernEditorChrome does).
3. Consumers: reduceMotion gates the hint bevel, the flash ramp, the countdown alpha, and the drag-thumbnail shrink (already gated by animatesWindowZoom). reduceTransparency drives the T4 plates. increaseContrast drives the T2 HC arms, the T4 borders, and the slider, overview and hint variants. differentiateWithoutColor drives the T6 indicator, check and prefix.
4. Injected DisplayOptions capture mode in the harness (visual-audit section 5 gap).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/DesignTokens.swift (DisplayOptions, if placed there; the spec allows DesignTokens or GlassChrome)
- Sources/GlassChrome.swift (replaces ChromeAccessibility; applyTransparencyFallback reads it)
- Sources/ModernEditorChrome.swift (observer currently only here)
- Sources/OriginalHelpBevel.swift (fade gate), Sources/OriginalCaptureFlash.swift (ramp :6-23), Sources/OriginalCaptureCountdown.swift (alpha :141)
- tools/eye-dump-audit.sh (injected DisplayOptions capture mode; the harness from OSN-001)
- tests/DisplayOptionsTests.swift (new), tests/GlassChromeTests.swift

**Prerequisites**

- Depends on: OSN-001, OSN-042, OSN-044
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T7 = 2 d, shared with OSN-056, 060 and 062. Unsplit. T7 says every window with custom drawing must observe the options, which may touch App.swift (Lane A). Section 9 says no. See the roadmap.

**Measurable acceptance**

- With an injected reduceMotion, hint bevel, flash and countdown produce zero intermediate alpha steps (tick sequence equals [final]). This fails today.
- With reduceTransparency, every glass surface has an alpha-1 plate and tintColor nil (G5 test 4).
- Captures with injected options exist: Reduce Transparency and Increase Contrast at 980; Differentiate Without Color on selected states.

**Visual validation checklist**

- Before: S02-populated-light@dc1eb26 and S07-zoom-25-light@dc1eb26 (the translucent surround this todo removes).
- Injected DisplayOptions captures at 980, light and dark: Reduce Transparency, Increase Contrast and Differentiate Without Color. Bars and canvas stay legible on solid plates with a contrast ring.
- Differentiate Without Color: the selected tool shows a non-colour indicator, not colour alone.
- The owner's system toggles are not changed (audit rule). Use the injected mode only.

**Regression tests**

- DisplayOptionsTests (T7 test 2).
- G5 test 4 (GlassDepthTests).

## OSN-062 · VoiceOver labels, announcements, and a recorded manual VoiceOver pass

`OSN-062 · P1 · M6 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-14. **Spec:** T7.

**User-visible issue.** Icon-only controls have weak or legacy labels ('Drag Me', 'Upload'). Changes such as upload result or undo are not announced to VoiceOver users.

**Implementation substeps**

1. Tool labels: 'Select tool', 'Brush tool' and so on. Upload: 'Upload image'. Drag well: 'Drag image to another app', role button, accessibilityPerformPress opens the Export panel. Toolbox: 'Toolbox menu'. PNG and JPG: segments under the group 'Image format'. Status item: 'Show or hide OpenSnap' (OSN-023).
2. Relocated controls (T15 sections d and f): Size pill role slider, label 'Drawing size', value as a whole number, increment and decrement by one preset, custom action 'Show size options'. The popover track is a second slider with the same value. Preset buttons 'Size N'.
3. AppDelegate.announce(_:): NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [.announcement: text, .priority: .medium]). Events: upload start, success and error; capture success; Frame enter and leave; Undo and Redo results. Rate-limit to state changes (R10).
4. Status label: setAccessibilityRole(.staticText). Errors prefixed 'Error:'.
5. Manual VoiceOver pass, recorded with the date and the build SHA (visual-audit M6 exit).

**File owners** (`Sources/App.swift` is Lane A)

- Sources/ModernEditorChrome.swift (labels :92-112, :276-290)
- Sources/App+ModernChrome.swift
- Sources/App.swift (Lane A: announce(_:); drag well and Upload labels) **[Lane A]**
- Sources/BezelDrawingControls.swift (Size pill and popover track accessibility)
- tests/AccessibilityAuditTests.swift (new), tests/AppSafetyModernCases.swift (modernControlStrings, modernIconOnlyCommands)

**Prerequisites**

- Depends on: OSN-060
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. T7 = 2 d, shared with OSN-056, 060 and 061. Unsplit.

**Measurable acceptance**

- AccessibilityAuditTests (T7 test 1): every NSControl without a visible title has a non-empty AX label and a role; labels are unique within a window; no 'Skitch'.
- Announcement test with an injected poster (T7 test 5).
- Manual VoiceOver pass recorded.

**Visual validation checklist**

- None (non-visual). Before: none. The AX dumps in evidence/2026-10-09/ax/ are the structural baseline; they are not manifest captures.
- Keep the manual VoiceOver log with the captures.

**Regression tests**

- AccessibilityAuditTests (T7 tests 1 and 5).
- AppSafetyModernCases string expectations updated for new labels (R12).

---

# M7 · Visual acceptance + release readiness

## OSN-070 · Regression gates in tools/test.py: font-floor walker, glass depth and budget, glyphs, original bytes, Skitch strings, layout fit at 980

`OSN-070 · P0 · M7 · Status: pending`

**Main state (dc1eb26):** partly (`check-no-original` exists).

**Findings:** VF-01, VF-02, VF-03, VF-04, VF-05, VF-06, VF-07, VF-08, VF-09, VF-10, VF-11, VF-12, VF-13, VF-14, VF-15, VF-16, VF-17, VF-18, VF-19, VF-20, VF-21, VF-22, VF-23, VF-24, VF-25, VF-26, VF-27, VF-28, VF-29. **Spec:** T14.

**User-visible issue.** No end-user symptom. Without gates, the fixes in this backlog can quietly regress.

**Implementation substeps**

1. G4 walker (ViewTreeAudit): build the main window (default, minimum, Frame), Prefs (each tab), History, Photos, Resize (three modes), Hotkeys, Destinations (list and each protocol), the Export accessory, the Fonts accessory, the Overview panel and the colour popover. Collect fonts from text fields, buttons, popups, segmented controls, text views, table cells, menu items (recursively) and Typography-registered custom text. Assert at least 18 pt for readable text, and at least 20 pt for controls unless caption.
2. G5: GlassDepthTests (depth, count budget, frame intersection, Reduce Transparency plates).
3. G3 dynamic: OpenSnap --dump-strings DIR walks every window, menu, status item, tooltip, AX label, placeholder and alert, and writes JSON. tools/check-user-strings.py asserts no match for /skitch|openskitch/i.
4. G6: no emoji or decorative glyphs. Static scan of every string literal (including \u escapes) plus the dynamic dump.
5. G7: tools/check-eye-dump.py. Image non-empty; no control clipped (layout.json); labelled controls at least 4.5:1 contrast; window sizes within token minima. Pixel baselines only for deterministic non-glass surfaces (sheets, Prefs, History with fixed fixtures), with a perceptual-hash tolerance. Mask glass regions.
6. G9: tools/check-tokens.py blocking.
7. G11: test.py fails any suite that prints SKIP or SKIPPED for a reason other than 'macOS < N', unless OPENSNAP_ALLOW_SKIP=fa is set for a licence-free CI.
8. G12 (T15 section h tests 1 to 8) is covered by OSN-012. Confirm it is in the gate list.

**File owners** (`Sources/App.swift` is Lane A)

- tools/test.py (G11 skip budget; wire every gate)
- tools/check-clean-clone.sh, tools/check-no-original.py, tools/check-skitch-strings.py (created in OSN-020; wired here)
- tools/check-user-strings.py (new; G3 dynamic)
- tools/check-eye-dump.py (new; G7)
- tools/check-tokens.py (OSN-040; G9 made blocking here)
- tests/ViewTreeAudit.swift, tests/ViewTreeAuditTests.swift (new; G4 walker)
- tests/GlassDepthTests.swift (G5; created in OSN-042)
- Sources/App.swift --dump-strings DIR (G3 dynamic; needs a launch hook; Lane A per section 9) **[Lane A]**

**Prerequisites**

- Depends on: OSN-012, OSN-040
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 3.0 d. Spec roll-up: 'T14 gates 3 d'. Assumption: the roll-up figure maps to this todo. The harness (OSN-001) and the gallery (OSN-071) have no figure.

**Measurable acceptance**

- All gates green on main, or each exception is written down with its reason.
- G11: no unexplained SKIP in test.py output.
- Font-floor walker reports 0 readable text below 18 pt and 0 controls below 20 pt unless caption.
- Glass depth at most 1; glass count within budget.
- 0 decorative glyphs; 0 user-visible 'Skitch' strings (dynamic).
- 0 clipped controls at 980 in layout.json; contrast at least 4.5:1 for labelled controls.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 and S11-width-980-light@dc1eb26 are the first pixel baselines for the layout.json and PNG outputs of S01 to S28 from the harness.
- Gate outputs on the baseline: the font-floor walker, glass depth and budget, decorative-glyph scan, no-original and no-Skitch string checks, and the 980 fit.
- No visual sign-off here (OSN-071).

**Regression tests**

- G1 to G12 as listed in T14. Each gate states what makes it fail today; each must be shown to fail on a seeded violation (can-fail).
- ViewTreeAuditTests (G4), GlassDepthTests (G5).

## OSN-071 · Visual acceptance run: full gallery, light and dark, widths, states, icon modes, and Opus sign-off

`OSN-071 · P0 · M7 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-01, VF-02, VF-03, VF-04, VF-05, VF-06, VF-07, VF-08, VF-09, VF-10, VF-11, VF-12, VF-13, VF-14, VF-15, VF-16, VF-17, VF-18, VF-19, VF-20, VF-21, VF-22, VF-23, VF-24, VF-25, VF-26, VF-27, VF-28, VF-29. **Spec:** T14, T15 j.

**User-visible issue.** No end-user symptom. This is the evidence that the visible result matches the target.

**Implementation substeps**

1. Run the harness (OSN-001) over the full gallery: light and dark x 980, 1024, 1280, 1440 and full screen x states x FA and SF icon modes.
2. Include Frame mode, the popover open, populated and empty, selection, text editing, PNG and JPG states, and injected DisplayOptions (OSN-061).
3. Record sourceSha on every manifest entry. Record any gap in gaps.md (non-Retina, multi-display and live desktop stay gaps).
4. Opus reviews every capture against T15 section j and D1 to D10 (visual-audit section 3). Record the sign-off.

**File owners** (`Sources/App.swift` is Lane A)

- docs/design/evidence/2026-10-09/** (outputs: PNG, metrics, AX dumps, manifest.json, captures.md, gaps.md)
- tools/eye-dump-audit.sh (run only)

**Prerequisites**

- Depends on: OSN-070
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: not split in the spec. No figure in the spec. The gate set is OSN-070. Opus review is separate.

**Measurable acceptance**

- Each surface in the coverage matrix has at least one capture per mode.
- No unexplained gap in gaps.md.
- Opus sign-off recorded.
- The walker (OSN-070) reports no text violations on the captured surfaces.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26, S02-populated-light@dc1eb26, S11-width-980-light@dc1eb26, S11-width-1440-dark@dc1eb26, S11-size-fullscreen-dark@dc1eb26, S12-frame-w980-light@dc1eb26 and PROTO-w980-normal-light@dc1eb26 (rail-less mock, not product).
- Full matrix: light and dark x 980 (minimum height), 1024 x 740, 1280 x 800, 1440 and full screen x empty, populated, selection, text editing, Frame, popover open, PNG and JPG; in FA and SF icon modes.
- Each capture is checked against D1 to D10 (visual-audit section 3). Opus sign-off is recorded.

**Regression tests**

- Gate results from OSN-070 attached to the sign-off.

## OSN-072 · WP7: migration verified on a copy of the owner's real store; clean-clone build, test and release dry run

`OSN-072 · P0 · M7 · Status: pending`

**Main state (dc1eb26):** open.

**Findings:** VF-01, VF-03. **Spec:** T13.

**User-visible issue.** No end-user symptom beyond the migration. The owner's 58 History documents, both destinations and the Keychain items must survive.

**Implementation substeps**

1. Copy the owner's SkitchRedux folder read-only. Record a SHA-256 manifest of the source before and after. Never run against the live folder.
2. Run the migration against the copy, in an isolated HOME and defaults suite. Check: History count 58; both destinations listed; the migration report written.
3. Clean clone to /tmp, with original/ absent: sh tools/build.sh, python3 tools/test.py, python3 tools/test-native-startup.py.
4. Release dry run: sh tools/release.sh with the version, after confirming it will not publish (see acceptance).
5. Owner-only steps, not run without explicit confirmation: the 'AWS cdn' upload dry run (declassic WP7; it touches a remote) and installing the build over the owner's copy (declassic WP7).

**File owners** (`Sources/App.swift` is Lane A)

- No product code. Verification on a /tmp clone and a copy of the owner's store.
- Info.plist (version bump to 0.4.0, build 4, per declassic WP7; not in section 9, confirm)
- tools/release.sh (dry run only)

**Prerequisites**

- Depends on: OSN-030, OSN-070
- Owner decisions: none

**Scope and estimate assumptions**

- Estimate: 0.5 d. declassic-plan WP7 sizing (about 0.5 d).

**Measurable acceptance**

- The source SHA-256 manifest of the owner's store is unchanged after the copy and migration.
- History count 58; both destinations listed; re-run is a no-op (idempotent).
- Clean clone builds and tests with original/ absent; check-no-original exits 0 on the built bundle.
- The release dry run is confirmed not to publish anything.

**Visual validation checklist**

- Before: S01-editor-empty-light@dc1eb26 (the release-candidate build on a clean clone must match it) and S25-about-panel-light@dc1eb26 (the release must not read OpenSkitch).
- Migration verified on a copy of the owner's real store: the source store hash is unchanged. No visual check.
- Harness output from the clean clone is attached. The outward-facing upload dry run needs the owner's explicit confirmation (roadmap section 10).

**Regression tests**

- G1 clean-clone build; G2 no-original check on the built bundle; G8 migration on the copy.
