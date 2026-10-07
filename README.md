# Skitch Redux

A personal native AppKit reconstruction of Skitch 1.0.12 for macOS 13 and newer. The build contains both Apple Silicon and Intel 64-bit executables. Full original feature parity remains in progress.

## Build and run

```
./tools/build.sh
open "build/Skitch Redux.app"
```

The original ZIP and extracted bundle must remain in `original/` for local icon resources. They are deliberately excluded from Git, along with the decompiled analysis and build outputs. The original ZIP SHA-256 is `b2f4181f5eb40a570547054e8ec22ca9bbe490eca02a28e2389fc5d83fdc6e97`.

## Current functionality

Native capture controls, editable annotation tools, text, selection, undo, groups, cropping, resizing, rotation, flipping, clipboard import/export, drag export, local history, session recovery, printing, image exports and SVG export are implemented. The original bundled `firstlaunch.skitch` opens with editable paths and text. New editable documents use `.skitchredux`; original `.skitch` export and complete historical file compatibility remain unfinished.

Custom publishing supports SFTP using the existing SSH configuration, plus FTP, FTPS and WebDAV. The configured personal destination is `shoemoney.com`, remote folder `/var/www/shoemoney.com/shared/imgs`, and public links under `https://shoemoney.com/imgs/`. SSH keys remain in their configured locations. Password destinations use macOS Keychain. Publishing requires a deliberate Publish action.

## Validation and remaining work

Run `./tools/test.py` for the independent native regression suites. Executable suites live in `tests/`. Canvas checks cover editable state, transforms, grouping, clipping, text and eraser behavior. Publishing checks cover path validation, transfer configuration and verification. Real SFTP uploads have been checked independently. Native desktop checks cover original-document import and rectangle drawing.

Important remaining gaps include exact original vector Boolean fill/erasing, pressure-sensitive and smoothed strokes, some original modifiers, complete original file interoperability, Photos integration, exact capture framing and legacy service behavior. Original online account services and obsolete update/crash endpoints cannot be assumed operational. Full original-runtime visual equivalence has not been established.

## Original analysis

`analysis/` contains the Ghidra project, Objective-C metadata, disassembly, drawing/document recovery and a feature inventory traced to original resources. Ghidra exported 11,977 functions without function-export failures. The pseudocode does not compile as original source; the application is reconstructed Swift/AppKit code. The original i386 executable has not been run on this Mac.

Recovery scripts: `tools/decompile.sh` and `tools/ExportDecompiled.java`. Ghidra source: https://github.com/NationalSecurityAgency/ghidra.
