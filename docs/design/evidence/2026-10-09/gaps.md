# Coverage gaps

Everything below was NOT captured (or could not be captured faithfully), with the reason. Nothing here is faked.

## Surfaces / states not captured

| ID | Surface / state | Appearance | Reason |
|---|---|---|---|
| S22 | Photo browser | both | PhotoBrowserCoordinator reads the user's Photos library and Desktop (Photos TCC prompt, real private pictures); no synthetic content seam exists, so it was deliberately not opened |
| S26 | Wipe confirmation | both | No Wipe confirmation exists: Wipe/Undo (Canvas.wipe) acts immediately, so there is nothing to capture; recorded as a finding |
| S29 | Native tooltips / help tags | both | AppKit tooltips are drawn by the window server on real mouse hover and cannot be forced or captured without a real pointer |
| S29 | Share with macOS picker | both | NSSharingServicePicker runs out of process and lists the user's real services/accounts |
| S09 | Format popup open (b9319c4) | both | The popup menu window was not present in the composite; capture dropped. Replaced by the PNG|JPG toggle at later SHAs. |
| S23 | Toolbox menu open; canvas text context menu open | both | Menu tracking ran but the menu windows were not present in the own-window composites; captures dropped. Menu contents are in menus.json. |
| S06 | Color palette popover composited with its parent | both | The composite omitted the popover; the popover window alone is captured instead. |
| S15 | Flash at half alpha over the editor | both | The composite omitted the flash window; flash-full (white panel alone) is kept. |
| S10 | NSSavePanel with ExportAccessory | both | runModal returned immediately in this environment (out-of-process panel); only the accessory view alone was captured. |
| S13/S14 | Picker and countdown over the live desktop | both | Only the overlay windows are captured (transparent where nothing is drawn); the desktop behind them is never captured. |

## Environment / accessibility coverage gaps

| Item | Why |
|---|---|
| Liquid Glass backdrop of alerts and the status-bar button | NSAlert panels use a translucent glass material that CGWindowList does not capture: the alert PNGs came out transparent behind the text (dark-mode text is white and invisible on a white viewer). The assembler flattens those PNGs onto a neutral backdrop (#ECECEC light, #2C2A29 dark; manifest field flattenedOnBackdrop); it is not the exact material a user sees. The S24 status-button renders (a bare template image) are flattened the same way. |
| Reduce Transparency | Cannot be toggled without changing system settings (forbidden). Current value recorded in environment.json (false); the chrome's reduced-transparency path (opaque glass, no canvas bleed) was NOT rendered. |
| Increase Contrast | Same: forbidden to toggle. Current value false; the 1-pt contrast ring on selected glass surfaces (GlassChrome.swift showsContrastRing) was NOT rendered. |
| Reduce Motion | Same: forbidden to toggle. Current value false; window-zoom/drag-thumbnail animations ran in their animated form only. |
| Bold Text / system text size | No public read-only API; not toggled. Recorded as unknown. |
| Differentiate Without Color | Current value false (environment.json); the selected-tool state relies on accent fill alone and was not rendered in the differentiated mode. |
| VoiceOver speech | Not run. The AX dumps in ax/ are a structural substitute only (roles, labels, help, children, key-view loop). |
| Non-Retina 1x display | Only the built-in 2x Retina display exists on this machine; 1x rendering (hairlines, glyph hinting) was not captured. |
| Multi-display | A single display is attached; active-display capture and cross-display window placement were not exercised. |
| Live screen capture / real crosshair over real pixels | No Screen Recording grant and capturing the screen is forbidden for this audit. The picker lens is shown grey (what renders without a grant) and with synthetic pixels. |
| Native tooltips / hover-only affordances | AppKit tooltips are window-server drawn on real pointer dwell; they cannot be forced. Tooltip strings are recorded in metrics/*.json (toolTip). Hover/pressed glass states were forced through GlassSurfaceView.setHovered/isPressed only. |
| NSSharingServicePicker / system share sheet | Out-of-process and lists the user's real accounts; not opened. |
| Photo browser (S22) | Reads the user's Photos library and Desktop with no synthetic-content seam; not opened (privacy). |
| Real drag-and-drop to Finder | A real drag session needs a real pointer and writes files; only the drag thumbnail panel states were driven. |
| Real uploads (S3/SFTP/WebDAV) | Forbidden; the publish progress/success/error states were driven through a stubbed uploader on an isolated destination store with in-memory secrets. |
