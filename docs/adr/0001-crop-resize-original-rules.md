# ADR 0001: Original crop/resize rules (ActionCropResize)

Status: accepted. **Historical note:** this ADR records the rules the crop/resize behavior was built from; the decompile it cites is no longer tracked or distributed (`analysis/` is git-ignored), so the line references below cannot be re-checked from a clone. The behavior itself is covered by `tests/WindowSizingTests.swift`.

Original source of the rules: a decompile of the app this project was inspired by. Line numbers below are lines in that file. Where the decompile is ambiguous this ADR says so instead of inventing a rule.

## The action: `skitch::ActionCropResize`

| Part | decompiled.c | What it does |
|---|---|---|
| ctor | 311199-311260 | stores doc (+8), controller (+4), id (+0x30), `crop` (+0x2c), `proportional` (+0x2d), then computes the target window frame with `_frameForCropResize` |
| `_frameForCropResize` | 311262-311450 | all the geometry (below) |
| `execute` | 311454-311497 | saves old doc size/visible rect/frame, writes the new doc size unless (`crop` clear and `proportional` set... see note), `setVisibleRect` when cropping, else `clearCache` |
| `unExecute` | 311499-311517 | restores the saved doc size, visible rect and frame |
| `combineWith` | 311519-311558 | merges two actions only if id, `crop` and `proportional` are all equal; the newer frame and rect replace the older (one undo step per drag) |
| `usedMemory` / `name` | 311598 / 311606 | 0x5c bytes, "Crop / Resize" |

execute note: the doc size is rewritten when `crop` is set, or when `proportional` is clear (`(crop&1)!=0 || (proportional&1)==0`). Only the proportional resize skips it.

### The crop ids

`directionVector` (initialised at 307215-307240) is an array of 9 (x, y) float pairs. The ctor reads `directionVector[id == -1 ? 4 : id]`:

| id | handle | direction (x, y) |
|---|---|---|
| 0 | top-left corner | (-1, -1) |
| 1 | top edge | (0, -1) |
| 2 | top-right corner | (1, -1) |
| 3 | right edge | (1, 0) |
| 4 | bottom-right corner | (1, 1) |
| 5 | bottom edge | (0, 1) |
| 6 | bottom-left corner | (-1, 1) |
| 7 | left edge | (-1, 0) |
| 8 | centre | (0, 0) |
| -1 | "about the centre", row 4 plus forced mirror | (1, 1) |

A negative direction component moves the left/top edge (origin += d, size -= d); a positive one grows the right/bottom edge (size += d); zero ignores that axis (`_getDeltaPAndDeltaScale`, 311560-311593).

The "12 crop ids" are the 12 `SkitchCropView` instances made by `createCropViews` (13767, loop to 0xc). `positionCropViews` (13504) loops the 8 ids and treats the odd ones (mask 0xaa, the edges) as one view and the even ones (corners) as two views: 4 + 4x2 = 12. That view-to-id pairing is inferred from the loop shape; the `resetCursorRects` switch (9918) handles ids 0-7 only.

### Which delta axis drives a corner

- Free resize/crop: each axis uses its own delta times its direction sign.
- Proportional resize (`proportional` set and `crop` clear): width is driven; height is `floor(newWidth * docH / docW + 0.5)`; the vertical delta is ignored (311395-311402). For a top handle (direction.y < 0) the origin additionally moves by `oldHeight - newHeight` so the bottom edge stays fixed.
- Centred (`centered` set, or id == -1): the delta is applied a second time with negated delta and negated direction (311333-311350), so the opposite edge moves equally and the size changes by twice the delta.

### Rounding and clamps

- Rounding is `floorf(x + 0.5)` (`DAT_00260444` is 0.5; the value is inferred from its use as a rounding and halving constant, the raw bytes are not in the decompile). Only the derived proportional height is rounded; the dragged width is not.
- Minimums use `kMinDocumentSize` and `DAT_0029696c`, both set to 1.0 in `__GLOBAL__I_a` (311629). If docW <= docH: min width 1, min height `floor(docH/docW + 0.5)`; otherwise min width `floor(docW/docH + 0.5)`, min height 1 (311402-311414). The proportional minimum therefore is not always 1x1.
- When either minimum is violated the original does not reject: it recomputes the delta (`frameW - minW`, sign from the old delta, halved when centred or id == -1) and calls itself again with `centered = 0`; if the recomputed delta equals the input it returns the unchanged frame (311419-311447).
- No maximum (16384 px, 32 MP) exists in the decompile; those are OpenSkitch allocation guards.

## Gesture: `SkitchCropView`

- `mouseDragged:` (9968-9991) returns when deltaX and deltaY are both 0, then sends `cropResize:deltaX:deltaY:crop:centered:` with `crop = 1` and `centered = modifierFlags >> 19 & 1`. Bit 19 (0x80000) is Option. Option is the centre/symmetric modifier.
- Proportional is not a modifier at this call. `PlatformController cropResize:...` (3796) asks `resizeProportionally` (3756), which is: frame mode forces true; snap mode 1 is true only while Shift (0x20000) is held in the current event; snap modes 0 and 3 are true unless the document is empty and has no background; every other mode is false. The original passes `crop = crop && !frameMode`.
- `mouseDown:` (9998) sets `liveCropping`, calls `startTransaction`, hides the cursor. `mouseUp:` (10007-10106) unhides the cursor, calls `endTransaction`, replays mouseEntered/mouseExited from the pointer position, clears `liveCropping`. One drag is one transaction, which `combineWith` collapses into one undo step.

## Border view: `SkitchBorderView`

- `createCropViews` (13767): 12 `SkitchCropView`s, added above the scroll view, then `positionCropViews`.
- `awakeFromNib` (14118; branch at 14164-14175): crop views are built (`maxViewSize`, `createCropViews`) only when `inActualMode` is false.
- `maxViewSize` (13944): `bounds.size + DAT_002606a8` per axis, and the nil-view path returns -8.0, so the constant is -8: `bounds - 8`.

## What the code now encodes

`WindowSizingPolicy` (Sources/WindowSizing.swift) gained `cropID`, `cropDirection`, `isCenteredCrop`, `resizesProportionally`, `minimumProportionalCanvas`, `maxViewSize`, `cropViewsExist`. `cornerOutput` now enforces the proportional minimum (a 16384x1 canvas cannot shrink in width, the old test that said it could contradicted 311402). Each rule is a labelled check in `tests/WindowSizingTests.swift` ("ActionCropResize ...").

## Ambiguities and assumptions

- ASSUMPTION: where the original clamps to the minimum, `cornerOutput` returns nil and the caller keeps its last preview. This is the reversible option and matches the existing nil contract.
- Unresolved: the integer meaning of the original `snapMode` (0, 1, 3). The code takes it as an argument; `AppViewport.previewBorderGesture` keeps its existing `hasContent` rule (the snap-mode 0/3 behaviour) and does not yet honour snap mode 1 + Shift.
- The clamp compares against the current window frame rather than the document size; the pure policy compares document sizes. These agree except while the frame carries chrome, which is the caller's concern.
- Edge handles (ids 1, 3, 5, 7) on a crop are modelled by `cropPreview`; the decompile applies the same `_getDeltaPAndDeltaScale` rule, with the visible rect as the thing that moves. Their rounding is not in the decompile (no `floor` is applied to the visible rect).
