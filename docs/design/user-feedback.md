# Owner layout feedback — 2026-10-09

Owner at 10:24 CDT:

> the buttons extending the right side.. I feel they could be relocated on the top bar or bottom and we could eliminate all that blank space

This steers the active visual audit and implementation roadmap. The full audit remains in scope.

## Required outcome

- Remove the permanent right-side action rail and its reserved empty column.
- Relocate all of its actions to the top bar, bottom bar, or a clearly discoverable contextual control.
- Give the released space to the canvas viewport; retain modest, consistent canvas margins.
- Preserve capture, frame cancellation, drawing color, font, stroke width, Undo, and Wipe, with their keyboard and accessibility behavior.
- Maintain readable native UI text at 18 points minimum, normally 20 points; fit the layout by adjusting grouping and placement.

## Placement to evaluate

Recommended starting arrangement: capture and annotation controls at the top; zoom, status, output format, drag export, and upload at the bottom. Evaluate Undo/Wipe placement by available width and action grouping. Convert the vertical stroke-size control to a usable horizontal or contextual presentation rather than rotating text or shrinking controls.

The top bar is already crowded. Validate each arrangement at the minimum supported window width and ordinary window widths before choosing. The final specification must give each current action a concrete destination and provide a visual acceptance checklist.

## Acceptance checks for the roadmap

- No permanent right rail, rail-width reservation, or blank column remains in editor constraints.
- Canvas extends to the trailing editor margin and remains centered when smaller than its viewport.
- Essential controls do not overlap, clip, or become unreachable at the minimum window size.
- Frame mode still exposes Cancel and keeps its capture area aligned with the revised viewport.
- Selection, drawing, text editing, crop/resize, zoom, scrolling, and drag/export behavior remain intact.
- Capture light/dark, minimum/ordinary/large window, populated/empty, selected/text-editing, and frame-mode evidence for visual review.

## Live baseline note

Root rechecked `main` at `4b2ae0f` when receiving this feedback. The PNG/JPG toggle has landed since the audit's initial `b9319c4` baseline. Keep earlier evidence pinned to its actual source SHA and check the revised layout against the current toggle width.

Source confirmation on `4b2ae0f`: `Sources/ModernEditorChrome.swift` creates `rightRail` for capture/drawing/history action groups and constrains `scrollView.trailingAnchor` to `rightRail.leadingAnchor`. This identifies the implementation area; it is source evidence, not a fresh rendered observation.
