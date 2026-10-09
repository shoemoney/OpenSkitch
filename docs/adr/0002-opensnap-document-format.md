# ADR 0002: The `.opensnap` document format

Status: accepted, 2026-10-09 (owner decision D3: drop the old formats for users).

## Context

The app saved editable drawings in two ways: an SVG-based file that carried the editing state as a base64 attribute (the legacy format, with a consistency fingerprint of the visible SVG), and a plain JSON file ("editable JSON"). Both were read by the same code path that Open, drag and drop, Recent and History used. The owner decided that only one native document type should exist from now on, that the legacy formats are no longer opened, saved or associated, and that existing History documents are converted once by the data migration.

## Decision

`.opensnap` is the **existing non-legacy native codec**, renamed: the canvas JSON that `CanvasView.snapshotDocumentData()` already produces and `CanvasView.validatedDocumentData(_:)` already validates.

- Contents: a versioned `SketchDocument` (`format`, `version`, size, optional render size, background colour, optional background PNG, ordered elements with embedded PNGs and exact path commands) plus the optional hidden pan-source pixels (`canvasPanBackground`), so panning away and back loses nothing.
- One addition: an optional top-level `drawingDefaults` object (pen colour, size and custom colour as strings) appended as the last member when present, so reopening a drawing restores the pen. Readers that do not know the key ignore it; `OpenSnapFile` removes it byte for byte before re-saving, so saves are stable.
- Identifier: `format` is `com.shoemoney.opensnap.document`, which is also the exported UTI (conforms to `public.data` and `public.content`, extension `opensnap`). `version` stays 1: the schema did not change, only the name did.
- Limits and validation are unchanged: 64 MB, dimension and pixel caps, finite numbers, unique element IDs, decodable PNGs.
- The format has no XML, no fingerprint and no second representation of the drawing, so there is no "visible SVG disagrees with hidden state" failure mode.

`SVGExport` remains an ordinary export format. It is one-way: nothing reads SVG back as a document.

## Consequences

- `Sources/OpenSnapFile.swift` is the only document reader and writer the app uses. Open panel types are pictures, PDFs and `.opensnap`; the Save panel offers only `.opensnap`; the canvas refuses to accept any other file type on drop; History and crash recovery (`Recovery.opensnap`) use the same file.
- The legacy reader (`Sources/LegacyReader.swift`: the strict SVG parser, the SVG-to-model bridge and the envelope reader) is compiled into the app but called only from `Sources/Migration.swift`. `tools/check-skitch-strings.py` and `MigrationTests` both fail if any other source file mentions its symbols.
- Migration converts each legacy document with the exact stored editing state when its visible-SVG fingerprint still matches, and otherwise from the visible drawing (reported). The retired JSON identifier is replaced byte for byte in the stored canvas JSON, so numbers and pixels are never re-encoded. A document that cannot be converted is kept as a picture-only drawing from its preview, or omitted if there is no usable preview; either is reported and nothing in the old folder is changed.
- Downgrade is not a goal: the previous app cannot read `.opensnap`, but its own folder is never modified.

## Alternatives considered

- A new self-contained archive (plist or zip with the PNGs beside the JSON): more moving parts and a second validator for no gain, since the canvas JSON already round-trips every field exactly.
- Keeping SVG as the native document: ruled out by the owner decision and by the cost of keeping a strict SVG reader reachable from Open.
