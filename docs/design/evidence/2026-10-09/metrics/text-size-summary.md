# Text-size summary (visible UI text under 20 pt)

Generated from the live view trees in `metrics/*.json` captured at `b9319c4` (Light + Dark): every VISIBLE (not hidden, alpha > 0) text-bearing control whose font reports a point size below 20. Icon-only buttons (their title is only an accessibility name) are excluded. Annotation CONTENT (user drawings) is listed separately at the end and is not a UI-readability finding. Text drawn by custom `draw(_:)` code (the old 'Drag Me' label, help-bevel HUD, native tooltips, native menu items) is not in the view tree; see the notes at the end.

**Totals: 37 distinct controls under 18 pt (all system-owned AppKit text); 45 distinct controls at 18 to 19.9 pt.**

## Under 18 pt

### Common to the editor window (present in 6 or more surfaces)

| Control class | Text | pt | Source | Surfaces |
|---|---|---|---|---|
| _NSThemeCloseWidget | Button | 13 | system AppKit titlebar (not set by the app) | 18 surfaces (S01, S02, S03, S04, S05, S06…) |
| _NSThemeZoomWidget | Button | 13 | system AppKit titlebar (not set by the app) | 18 surfaces (S01, S02, S03, S04, S05, S06…) |
| _NSThemeWidget | Button | 13 | system AppKit titlebar (not set by the app) | 18 surfaces (S01, S02, S03, S04, S05, S06…) |
| NSButtonTextField | PNG | 13 | internal label of the format control; the control's own font is set at Sources/App+ModernChrome.swift:74 | 15 surfaces (S01, S02, S03, S04, S05, S06…) |
| NSTextField | ‹window title› | 13 | system AppKit titlebar (not set by the app) | 14 surfaces (S01, S02, S03, S04, S05, S06…) |

### S25 About panel

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Version 0.3.0 (3) | 10 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextView | Native 64-bit reconstruction for personal use. Feature parity with Skitch 1.0.12 is still in progress. | 12 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | OpenSkitch | 14 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |

### S06 color picker

| Control class | Text | pt | Source |
|---|---|---|---|
| NSColorPickerSelectingTextField | 100% | 11 | system NSColorPanel (AppKit) |
| NSTextView | 100% | 11 | system NSColorPanel (AppKit) |
| NSTextField | Colors | 11 | system NSColorPanel (AppKit) |
| NSTextField | Opacity | 11 | system NSColorPanel (AppKit) |

### S06 Fonts panel / text style form

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | G | 11 | system NSColorPanel (AppKit) |
| NSTextField | H | 11 | system NSColorPanel (AppKit) |
| NSTextField | I | 11 | system NSColorPanel (AppKit) |
| NSTextField | L | 11 | system NSColorPanel (AppKit) |

### S26 alerts / sheets

| Control class | Text | pt | Source |
|---|---|---|---|
| _NSAlertButton | Cancel | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| _NSAlertButton | Discard | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Document name | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| _NSAlertButton | Hide | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Hide drawings from History? | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | Move archived drawings to Trash? | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| _NSAlertButton | Move to Trash | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Rename | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| _NSAlertButton | Save | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Save your drawing? | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | The selected History copies and previews will move to Trash. Exported originals and web posts are kept. | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | The selected drawings will leave the History list. Their archive files and web posts are kept. | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | This capture is too large or cannot be decoded safely. | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| NSTextField | This document has changes that have not been saved. | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |

### S10 export save panel

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | ExportAccessory (rendered alone) | 13 | see manifest sourceRefs for the surface |

### S29 help bevel (tool-tip overlay)

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Extras | 13 | see manifest sourceRefs for the surface |

### S16 Screen Recording permission alert, S21 publish error, S26 alerts / sheets

| Control class | Text | pt | Source |
|---|---|---|---|
| _NSAlertButton | OK | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |

### S16 Screen Recording permission alert

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Screen Recording access is not granted. Enable this app in System Settings > Privacy & Security > Screen Recording, then reopen it if macOS requests that. | 13 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |

### S21 publish error

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Upload to Example S3 failed: the connection was refused (stub, no network was used). | 13 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |

### S27 first launch / welcome document

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Welcome | 13 | see manifest sourceRefs for the surface |

### S28 keyboard focus

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | ‹window title› | 13 | see manifest sourceRefs for the surface |

## 18 to 19.9 pt

### Common to the editor window (present in 6 or more surfaces)

| Control class | Text | pt | Source | Surfaces |
|---|---|---|---|---|
| NSButton | Original size | 18 | Sources/App+ModernChrome.swift:59 | 12 surfaces (S02, S03, S04, S05, S06, S07…) |
| NSTextField | ‹image size label, e.g. “800 × 600 · 10 KB”› | 18 | Sources/App+ModernChrome.swift:80 | 15 surfaces (S01, S02, S03, S04, S05, S06…) |
| NSTextField | ‹status line, e.g. “Arrow · Unsaved changes”› | 18 | Sources/App+ModernChrome.swift:81 | 14 surfaces (S01, S02, S03, S04, S05, S06…) |
| NSPopUpButton | ‹zoom popup, e.g. “Output · 100%”› | 18 | Sources/App+ModernChrome.swift:66 (floor: Sources/ModernEditorChrome.swift:210) | 15 surfaces (S01, S02, S03, S04, S05, S06…) |

### S20 History browser

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | 6 items · 0 selected | 18 | Sources/HistoryBrowser.swift:291 |
| NSTextField | 6 items · 1 selected | 18 | Sources/HistoryBrowser.swift:291 |
| NSTextField | Action: | 18 | Sources/HistoryBrowser.swift:297 |
| NSTextField | Date: | 18 | Sources/HistoryBrowser.swift:297 |
| NSTextField | Destination: | 18 | Sources/HistoryBrowser.swift:297 |
| NSTextField | Drag from History format: | 18 | Sources/HistoryBrowser.swift:314 |
| NSTextField | Exported/Dragged | 18 | Sources/HistoryBrowser.swift:443 |
| NSTextField | Name: | 18 | Sources/HistoryBrowser.swift:297 |
| NSTextField | No history items match these filters. | 18 | Sources/HistoryBrowser.swift:291 |
| NSTextField | Shared | 18 | Sources/HistoryBrowser.swift:443 |
| NSTextField | Size: | 18 | Sources/HistoryBrowser.swift:297 |

### S19 Destinations / Publishing

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Access key ID | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSPopUpButton | Access key stored in Keychain | 18 | Sources/PublishingDestinationsView.swift:192 |
| NSButton | Add… | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSTextField | Bucket | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSButton | Cancel | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSTextField | Credentials | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSButton | Done | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSButton | Edit… | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSTextField | Endpoint (blank = AWS) | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSTextField | Key prefix | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSButton | Make Default | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSButton | Make uploads public-read (leave off when the bucket disables ACLs) | 18 | Sources/PublishingDestinationsView.swift:198 |
| NSTextField | Name | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSTextField | Path-style S3 over system curl. Public base URL maps to the key prefix; the uploaded file is downloaded from it to verify the exact bytes. Test lists the bucket without uploading. | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSTextField | Protocol | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSTextField | Public base URL | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSTextField | Region | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSButton | Remove | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSPopUpButton | S3-compatible (AWS, R2, B2, Spaces, Wasabi, MinIO) | 18 | Sources/PublishingDestinationsView.swift:192 |
| NSButton | Save | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSTextField | Secret access key | 18 | Sources/PublishingDestinationsView.swift:176 |
| NSButton | Test | 18 | Sources/PublishingDestinationsView.swift:38 |
| NSTextField | Upload destinations. The checked one receives a Webpost click; right-click Webpost to switch. | 18 | Sources/PublishingDestinationsView.swift:176 |

### S26 alerts / sheets

| Control class | Text | pt | Source |
|---|---|---|---|
| _NSAlertButton | Cancel | 18 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Its saved password or secret key is removed from the Keychain too. This cannot be undone. It is the default, so “Example SFTP” becomes the default. | 18 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |
| _NSAlertButton | Remove | 18 | system NSAlert text (App.swift error alerts: Sources/App.swift:1069) |
| NSTextField | Remove “Example S3”? | 18 | system AppKit text (About panel / NSAlert / panels); the app sets no font here |

### S06 color picker

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Drawing colors | 18 | Sources/App.swift:608 |

### S17 Preferences: General

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | Takes effect the next time OpenSkitch opens. | 18 | Sources/GeneralPreferencesForm.swift:? |

### S09 footer, S12 Frame mode, S21 publish progress

| Control class | Text | pt | Source |
|---|---|---|---|
| NSTextField | ‹status line (Frame / upload message)› | 18 | Sources/App+ModernChrome.swift:81 |

## Annotation content text (user drawings, not UI)

- S05: “Edit in progress” 18 pt (field editor draws at the annotation's own size; new tool text is floored at 18 pt in Canvas.swift)

## Not in the view tree (custom-drawn or system-drawn)

- Window titles and traffic lights: system titlebar, 13 pt (listed above as common).
- Native menu bar and menu items: system-drawn; the app sets 20 pt on its own menus (Sources/App.swift:723) but the menu-bar titles are system size.
- Native tooltips: system-drawn on hover, not capturable.
- Help bevel HUD text: 20 pt (Sources/OriginalHelpBevel.swift:32).
- Fonts panel, colour panel and Save panel internals: system views; the colour panel measured 11 pt labels (listed above).
