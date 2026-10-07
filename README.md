# Skitch Redux

A personal native AppKit reconstruction of Skitch 1.0.12 for macOS 13 and newer. The build contains both Apple Silicon and Intel 64-bit executables. Full original feature parity remains in progress.

## Build and run

```
./tools/build.sh
open "build/Skitch Redux.app"
```

The original ZIP and extracted bundle must remain in `original/` for local icon resources. They are deliberately excluded from Git, along with the decompiled analysis and build outputs. The original ZIP SHA-256 is `b2f4181f5eb40a570547054e8ec22ca9bbe490eca02a28e2389fc5d83fdc6e97`.

## Current functionality

Native capture controls, editable annotation tools, text, selection, undo, groups, cropping, resizing, rotation, flipping, clipboard import/export, drag export, local history, session recovery, printing, image exports and SVG export are implemented. The original bundled `firstlaunch.skitch` opens with editable paths and text. Save now uses SVG-native `.skitch` files with original attributes and supplemental editing state; existing `.skitchredux` JSON remains supported. Native save, recovery and history retain background pixels hidden by panning. Complete historical file interoperability remains unverified.

Frame Snapshot opens a see-through canvas. Snap Frame captures its bounds; Re-snap keeps the annotations while replacing the picture. Drawing gestures include temporary Command selection, Control erasing, Space panning, Tab Pencil switching, Option-drag copying, an eyedropper, and Justype text entry. Wipe clears annotations first and the snapshot second; Wipe Snap Only retains annotations. Photos offers chosen-folder thumbnails and the system Photos picker for user-selected images.

Custom publishing supports SFTP using the existing SSH configuration, plus FTP, FTPS and WebDAV. The configured personal destination is `shoemoney.com`, remote folder `/var/www/shoemoney.com/shared/imgs`, and public links under `https://shoemoney.com/imgs/`. SSH keys remain in their configured locations. Password destinations use macOS Keychain. Publishing requires a deliberate Publish action.

## Validation and remaining work

Run `./tools/test.py --arch arm64` and `./tools/test.py --arch x86_64` for the independent native regression suites. After rebuilding, run `python3 tools/test-native-startup.py` to exercise the actual universal app's startup, native save/reopen, PNG rendering and AppKit Quit with isolated session storage. Executable suites live in `tests/`. Canvas checks cover editable state, transforms, grouping, clipping, text, eraser behavior and gestures. File checks cover original attributes, editable state and hidden pan pixels. Capture, publishing and Photos teardown checks use controlled local workers; they do not grant permissions or upload files. Quit waits for helper exit and owned temporary-file cleanup. Real SFTP uploads have been checked independently. Desktop checks are recorded separately from unit tests.

Important remaining gaps include exact original vector Boolean fill/erasing, pressure-sensitive and smoothed strokes, some original modifiers, original window/crop/output sizing, complete historical file interoperability, the full History workflow, exact capture behavior across displays and legacy service behavior. Actual screen/camera permissions and hardware, the system Photos-library picker and unfocused global shortcuts still need desktop verification. The chosen-folder Photos browser, full-resolution open, Justype, Pencil toggle, native editable save/reopen and SFTP publication have been checked in the desktop app. Original online account services and obsolete update/crash endpoints cannot be assumed operational. Full original-runtime visual equivalence has not been established.

## Original analysis

`analysis/` contains the Ghidra project, Objective-C metadata, disassembly, drawing/document recovery and a feature inventory traced to original resources. Ghidra exported 11,977 functions without function-export failures. The pseudocode does not compile as original source; the application is reconstructed Swift/AppKit code. The original i386 executable has not been run on this Mac.

Recovery scripts: `tools/decompile.sh` and `tools/ExportDecompiled.java`. Ghidra source: https://github.com/NationalSecurityAgency/ghidra.
