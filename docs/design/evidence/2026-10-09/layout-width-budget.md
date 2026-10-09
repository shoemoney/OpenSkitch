# Layout width budget (measured live at `dc1eb26`)

Real frames and `fittingSize` read from the running Modern editor (Light appearance; width does not depend on appearance) at four window widths, normal and Frame mode, with a small image (Original-size checkbox hidden) and a large image (checkbox visible). All numbers are points. Raw data: `layout-width-budget.json`.

**Typical status string at 18 pt:** “800 × 600 · 10 KB” = 150 pt, “2400 × 1500 · 610 KB” = 179 pt, “Brush · Saved” = 115 pt, “Brush · Unsaved changes” = 208 pt

## Scenario: small-image

| Window | Mode | Header row | Σ header groups | Header free | gap lead→tools / tools→trail | Rail col W | Rail BLANK pt² | Rail blank % window | Scroll view W×H | Scroll→window-edge | Footer free | Status W / needs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 980 | normal | 956 | 862 | 94 | 14 / 80 | 64 | 24320 | 3.2% | 884×624 | 84 | 12 | 193 / 208 TRUNCATED |
| 980 | Frame | 956 | 862 | 94 | 14 / 80 | 64 | 21968 | 2.9% | 884×624 | 84 | 12 | 193 / 314 TRUNCATED |
| 1024 | normal | 1000 | 862 | 138 | 36 / 102 | 64 | 24320 | 3.1% | 928×624 | 84 | 37.5 | 208 / 208 |
| 1024 | Frame | 1000 | 862 | 138 | 36 / 102 | 64 | 21968 | 2.8% | 928×624 | 84 | 12 | 237 / 314 TRUNCATED |
| 1280 | normal | 1256 | 862 | 394 | 164 / 230 | 64 | 24320 | 2.5% | 1184×624 | 84 | 293.5 | 208 / 208 |
| 1280 | Frame | 1256 | 862 | 394 | 164 / 230 | 64 | 21968 | 2.2% | 1184×624 | 84 | 187.5 | 314 / 314 |
| 1440 | normal | 1416 | 862 | 554 | 244 / 310 | 64 | 24320 | 2.2% | 1344×624 | 84 | 453.5 | 208 / 208 |
| 1440 | Frame | 1416 | 862 | 554 | 244 / 310 | 64 | 21968 | 2% | 1344×624 | 84 | 347.5 | 314 / 314 |

## Scenario: large-image

| Window | Mode | Header row | Σ header groups | Header free | gap lead→tools / tools→trail | Rail col W | Rail BLANK pt² | Rail blank % window | Scroll view W×H | Scroll→window-edge | Footer free | Status W / needs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 980 | normal | 956 | 862 | 94 | 14 / 80 | 64 | 24320 | 3.2% | 884×624 | 84 | 12 | 191.5 / 208 TRUNCATED |
| 980 | Frame | 956 | 862 | 94 | 14 / 80 | 64 | 21968 | 2.9% | 884×624 | 84 | 12 | 191.5 / 314 TRUNCATED |
| 1024 | normal | 1000 | 862 | 138 | 36 / 102 | 64 | 24320 | 3.1% | 928×624 | 84 | 36 | 208 / 208 |
| 1024 | Frame | 1000 | 862 | 138 | 36 / 102 | 64 | 21968 | 2.8% | 928×624 | 84 | 12 | 235.5 / 314 TRUNCATED |
| 1280 | normal | 1256 | 862 | 394 | 164 / 230 | 64 | 24320 | 2.5% | 1184×624 | 84 | 292 | 208 / 208 |
| 1280 | Frame | 1256 | 862 | 394 | 164 / 230 | 64 | 21968 | 2.2% | 1184×624 | 84 | 186 | 314 / 314 |
| 1440 | normal | 1416 | 862 | 554 | 244 / 310 | 64 | 24320 | 2.2% | 1344×624 | 84 | 452 | 208 / 208 |
| 1440 | Frame | 1416 | 862 | 554 | 244 / 310 | 64 | 21968 | 2% | 1344×624 | 84 | 346 | 314 / 314 |

## Per-element frames and fitting sizes (normal mode, small image)

### Window 980

| Group / control | frame W×H | fitting W×H | hidden |
|---|---|---|---|
| **GlassHeaderLeading** | 168×36 | 168×36 | False |
|   · Hide | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 60×36 | 60×36 | False |
|   · Photos | 48×36 | 48×36 | False |
| **GlassHeaderTrailing** | 102×36 | 102×36 | False |
|   · Save | 48×36 | 48×36 | False |
|   · History | 48×36 | 48×36 | False |
| **GlassToolBar** | 592×40 | 592×40 | False |
|   · Select | 48×40 | 48×40 | False |
|   · Brush | 48×40 | 48×40 | False |
|   · Line | 48×40 | 48×40 | False |
|   · Ellipse | 48×40 | 48×40 | False |
|   · Rectangle | 48×40 | 48×40 | False |
|   · Fill | 48×40 | 48×40 | False |
|   · Eraser | 48×40 | 48×40 | False |
|   · Text | 48×40 | 48×40 | False |
|   · Arrow | 48×40 | 48×40 | False |
|   · Crop | 48×40 | 48×40 | False |
|   · Resize… | 48×36 | 48×36 | False |
| **GlassCaptureGroup** (rail) | 56×44 | 56×44 | False |
|   · Snap | 56×44 | 56×44 | False |
|   · Cancel | 48×36 | 48×36 | True |
| **GlassDrawingGroup** (rail) | 48×196 | 48×196 | False |
|   · Drawing colors | 48×36 | 48×36 | False |
|   · Font | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 48×112 | 48×112 | False |
| **GlassHistoryGroup** (rail) | 48×78 | 48×78 | False |
|   · Undo | 48×36 | 48×36 | False |
|   · Clear | 48×36 | 48×36 | False |
| footer zoomPopup | 160×24 | 160×24 | False |
| footer originalSizeCheckbox | 120×21 | 120×21 | False |
| footer dragSizeLabel | 178×21 | 178×21 | False |
| footer status | 193×21 | 208×21 | False |
| footer statusRow | 679×24 | 694×24 | False |
| **GlassFooterRow** | 265×36 | 265×36 | False |
|   · GlassSurfaceView | 157×36 | 157×36 | False |
|   · Drag Me | 48×36 | 48×36 | False |
|   · Upload to destination | 48×36 | 48×36 | False |
| scroll view | 884×624 | 17×17 | False |
| canvas | 1444.3×1011 | 1444.5×1011 | False |

### Window 1024

| Group / control | frame W×H | fitting W×H | hidden |
|---|---|---|---|
| **GlassHeaderLeading** | 168×36 | 168×36 | False |
|   · Hide | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 60×36 | 60×36 | False |
|   · Photos | 48×36 | 48×36 | False |
| **GlassHeaderTrailing** | 102×36 | 102×36 | False |
|   · Save | 48×36 | 48×36 | False |
|   · History | 48×36 | 48×36 | False |
| **GlassToolBar** | 592×40 | 592×40 | False |
|   · Select | 48×40 | 48×40 | False |
|   · Brush | 48×40 | 48×40 | False |
|   · Line | 48×40 | 48×40 | False |
|   · Ellipse | 48×40 | 48×40 | False |
|   · Rectangle | 48×40 | 48×40 | False |
|   · Fill | 48×40 | 48×40 | False |
|   · Eraser | 48×40 | 48×40 | False |
|   · Text | 48×40 | 48×40 | False |
|   · Arrow | 48×40 | 48×40 | False |
|   · Crop | 48×40 | 48×40 | False |
|   · Resize… | 48×36 | 48×36 | False |
| **GlassCaptureGroup** (rail) | 56×44 | 56×44 | False |
|   · Snap | 56×44 | 56×44 | False |
|   · Cancel | 48×36 | 48×36 | True |
| **GlassDrawingGroup** (rail) | 48×196 | 48×196 | False |
|   · Drawing colors | 48×36 | 48×36 | False |
|   · Font | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 48×112 | 48×112 | False |
| **GlassHistoryGroup** (rail) | 48×78 | 48×78 | False |
|   · Undo | 48×36 | 48×36 | False |
|   · Clear | 48×36 | 48×36 | False |
| footer zoomPopup | 163.5×24 | 160×24 | False |
| footer originalSizeCheckbox | 120×21 | 120×21 | False |
| footer dragSizeLabel | 178×21 | 178×21 | False |
| footer status | 208×21 | 208×21 | False |
| footer statusRow | 697.5×24 | 694×24 | False |
| **GlassFooterRow** | 265×36 | 265×36 | False |
|   · GlassSurfaceView | 157×36 | 157×36 | False |
|   · Drag Me | 48×36 | 48×36 | False |
|   · Upload to destination | 48×36 | 48×36 | False |
| scroll view | 928×624 | 17×17 | False |
| canvas | 1444.3×1011 | 1444.5×1011 | False |

### Window 1280

| Group / control | frame W×H | fitting W×H | hidden |
|---|---|---|---|
| **GlassHeaderLeading** | 168×36 | 168×36 | False |
|   · Hide | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 60×36 | 60×36 | False |
|   · Photos | 48×36 | 48×36 | False |
| **GlassHeaderTrailing** | 102×36 | 102×36 | False |
|   · Save | 48×36 | 48×36 | False |
|   · History | 48×36 | 48×36 | False |
| **GlassToolBar** | 592×40 | 592×40 | False |
|   · Select | 48×40 | 48×40 | False |
|   · Brush | 48×40 | 48×40 | False |
|   · Line | 48×40 | 48×40 | False |
|   · Ellipse | 48×40 | 48×40 | False |
|   · Rectangle | 48×40 | 48×40 | False |
|   · Fill | 48×40 | 48×40 | False |
|   · Eraser | 48×40 | 48×40 | False |
|   · Text | 48×40 | 48×40 | False |
|   · Arrow | 48×40 | 48×40 | False |
|   · Crop | 48×40 | 48×40 | False |
|   · Resize… | 48×36 | 48×36 | False |
| **GlassCaptureGroup** (rail) | 56×44 | 56×44 | False |
|   · Snap | 56×44 | 56×44 | False |
|   · Cancel | 48×36 | 48×36 | True |
| **GlassDrawingGroup** (rail) | 48×196 | 48×196 | False |
|   · Drawing colors | 48×36 | 48×36 | False |
|   · Font | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 48×112 | 48×112 | False |
| **GlassHistoryGroup** (rail) | 48×78 | 48×78 | False |
|   · Undo | 48×36 | 48×36 | False |
|   · Clear | 48×36 | 48×36 | False |
| footer zoomPopup | 163.5×24 | 160×24 | False |
| footer originalSizeCheckbox | 120×21 | 120×21 | False |
| footer dragSizeLabel | 178×21 | 178×21 | False |
| footer status | 208×21 | 208×21 | False |
| footer statusRow | 697.5×24 | 694×24 | False |
| **GlassFooterRow** | 265×36 | 265×36 | False |
|   · GlassSurfaceView | 157×36 | 157×36 | False |
|   · Drag Me | 48×36 | 48×36 | False |
|   · Upload to destination | 48×36 | 48×36 | False |
| scroll view | 1184×624 | 17×17 | False |
| canvas | 1444.3×1011 | 1444.5×1011 | False |

### Window 1440

| Group / control | frame W×H | fitting W×H | hidden |
|---|---|---|---|
| **GlassHeaderLeading** | 168×36 | 168×36 | False |
|   · Hide | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 60×36 | 60×36 | False |
|   · Photos | 48×36 | 48×36 | False |
| **GlassHeaderTrailing** | 102×36 | 102×36 | False |
|   · Save | 48×36 | 48×36 | False |
|   · History | 48×36 | 48×36 | False |
| **GlassToolBar** | 592×40 | 592×40 | False |
|   · Select | 48×40 | 48×40 | False |
|   · Brush | 48×40 | 48×40 | False |
|   · Line | 48×40 | 48×40 | False |
|   · Ellipse | 48×40 | 48×40 | False |
|   · Rectangle | 48×40 | 48×40 | False |
|   · Fill | 48×40 | 48×40 | False |
|   · Eraser | 48×40 | 48×40 | False |
|   · Text | 48×40 | 48×40 | False |
|   · Arrow | 48×40 | 48×40 | False |
|   · Crop | 48×40 | 48×40 | False |
|   · Resize… | 48×36 | 48×36 | False |
| **GlassCaptureGroup** (rail) | 56×44 | 56×44 | False |
|   · Snap | 56×44 | 56×44 | False |
|   · Cancel | 48×36 | 48×36 | True |
| **GlassDrawingGroup** (rail) | 48×196 | 48×196 | False |
|   · Drawing colors | 48×36 | 48×36 | False |
|   · Font | 48×36 | 48×36 | False |
|   · GlassSurfaceView | 48×112 | 48×112 | False |
| **GlassHistoryGroup** (rail) | 48×78 | 48×78 | False |
|   · Undo | 48×36 | 48×36 | False |
|   · Clear | 48×36 | 48×36 | False |
| footer zoomPopup | 163.5×24 | 160×24 | False |
| footer originalSizeCheckbox | 120×21 | 120×21 | False |
| footer dragSizeLabel | 178×21 | 178×21 | False |
| footer status | 208×21 | 208×21 | False |
| footer statusRow | 697.5×24 | 694×24 | False |
| **GlassFooterRow** | 265×36 | 265×36 | False |
|   · GlassSurfaceView | 157×36 | 157×36 | False |
|   · Drag Me | 48×36 | 48×36 | False |
|   · Upload to destination | 48×36 | 48×36 | False |
| scroll view | 1344×624 | 17×17 | False |
| canvas | 1444.3×1011 | 1444.5×1011 | False |

## PROTOTYPE MOCK fit (NOT product; harness-only re-parenting)

| Appearance | Width | Mode | Top row needs | Top available | Top slack (− = overflow) | Bottom sum (excl. status) | Bottom available | Bottom slack | Status needs 18pt | Bottom overflow if status fully shown |
|---|---|---|---|---|---|---|---|---|---|---|
| dark | 988 | normal | 964 | 964 | 0 | 740.5 | 964 | 223.5 | 208 | -7.5 |
| dark | 1042 | Frame | 1018 | 1018 | 0 | 740.5 | 1018 | 277.5 | 208 | -61.5 |
| dark | 1280 | normal | 964 | 1256 | 292 | 740.5 | 1256 | 515.5 | 208 | -299.5 |
| dark | 1280 | Frame | 1018 | 1256 | 238 | 740.5 | 1256 | 515.5 | 208 | -299.5 |
| light | 988 | normal | 964 | 964 | 0 | 740.5 | 964 | 223.5 | 208 | -7.5 |
| light | 1042 | Frame | 1018 | 1018 | 0 | 740.5 | 1018 | 277.5 | 208 | -61.5 |
| light | 1280 | normal | 964 | 1256 | 292 | 740.5 | 1256 | 515.5 | 208 | -299.5 |
| light | 1280 | Frame | 1018 | 1256 | 238 | 740.5 | 1256 | 515.5 | 208 | -299.5 |

