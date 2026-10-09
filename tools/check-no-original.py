#!/usr/bin/env python3
"""Exit 1 if a built bundle contains any recovered original-app asset or any sound file.

Usage: check-no-original.py PATH   (the whole .app)
The name list is static on purpose: this gate must work with no original/ folder on disk.
Three independent checks, all of which must come up empty:
  1. every file name in the bundle against the original's names and numbered families,
     and any sound file (.m4a .wav .aif .aiff .caf .mp3);
  2. every asset/rendition name inside every compiled *.car catalog (xcrun assetutil --info),
     against the same name list and patterns;
  3. the SHA-256 of every bundle file against tools/original-resource-hashes.txt
     (hashes only, no assets) so a renamed copy of an original file is still caught.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

ORIGINAL_NAMES = {n.lower() for n in (
    '.htaccess', 'About-skitch.png', 'ActualSizeToggleOff.png', 'ActualSizeToggleOn.png', 'Add.tiff',
    'AnonymousSkitchAccountOverlay.png', 'Authorization.nib', 'BezelTab.png', 'BezelTabActive.png',
    'CursorCropBottomRight.png', 'CursorCropHorizontal.png', 'CursorCropTopRight.png',
    'CursorCropVertical.png', 'CursorCrosshair.png', 'CursorCursor.png', 'CursorEyedrop.png',
    'CursorHand.png', 'CursorMove.png', 'CursorOK.png', 'Disclosure.png', 'DisclosureOver.png', 'DragMe.png',
    'ENCreateNotebookWindowController.nib', 'ENLoginViewController.nib', 'ENLoginWindowController.nib',
    'ENNotebookViewController.nib', 'ENPostedDetails.nib', 'ENRegistrationViewController.nib',
    'ENResetPasswordViewController.nib', 'ENShareConfirmationWindowController.nib',
    'ENShareWindowController.nib', 'Email_Exporter_Scripts.plist', 'Errors.thrift', 'Evernote.png',
    'Evernote.strings', 'EvernoteOver.png', 'EvernoteUploadActions.html', 'EvernoteUploadActions_en.html',
    'FilterBarBackground.png', 'Font.png', 'FontOver.png', 'Hide.png', 'HideOver.png', 'Internal.thrift',
    'Limits.thrift', 'Localizable.strings', 'MAAttachedWindow_license.html', 'MessagePopover.nib',
    'MySkitchPostedDetails.nib', 'NoteStore.thrift', 'OverflowButton.tif', 'OverflowButtonPressed.tif',
    'OverflowDivider.png', 'PTW_commence.m4a', 'PTW_complete.m4a', 'PTW_error.m4a',
    'PlusMenuItemAnnotation.png', 'PlusMenuItemAnnotation_Small.png', 'PostBack.png', 'PostBackOver.png',
    'ReadMe.rtf', 'Remove.tiff', 'Resize.png', 'ResizeOver.png', 'SKCustomPanelCloseWidget.png',
    'SKPresetResizeAnchorBottomCenter.png', 'SKPresetResizeAnchorBottomLeft.png',
    'SKPresetResizeAnchorBottomRight.png', 'SKPresetResizeAnchorMiddleCenter.png',
    'SKPresetResizeAnchorMiddleLeft.png', 'SKPresetResizeAnchorMiddleRight.png',
    'SKPresetResizeAnchorSelected.png', 'SKPresetResizeAnchorTopCenter.png',
    'SKPresetResizeAnchorTopLeft.png', 'SKPresetResizeAnchorTopRight.png', 'SKResizeLimitDimension.png',
    'SKResizeLimitHeight.png', 'SKResizeLimitWidth.png', 'SaveToHistoryArrow.png',
    'SaveToHistoryArrowOver.png', 'Separator.png', 'Share.png', 'ShareCopyToClipboard.png',
    'ShareCopyToClipboardOver.png', 'ShareError.png', 'ShareErrorOver.png', 'ShareOver.png',
    'ShareShowPrevious.png', 'ShareShowPreviousOver.png', 'Sharing.thrift', 'SkitchCount1.png',
    'SkitchCount2.png', 'SkitchCount3.png', 'SkitchMac.icns', 'SkitchTitle.png', 'SkitchTitle_Plus.png',
    'SkitchWebPost.html', 'Skitch_Cancel_DragMe.png', 'Skitch_ShowSkitch.png',
    'Skitch_ShowSkitch_mouseover.png', 'Skitch_magnifier_btn_minus.png', 'Skitch_magnifier_btn_minusOver.png',
    'Skitch_magnifier_btn_plus.png', 'Skitch_magnifier_btn_plusOver.png', 'Skitch_magnifier_cursor.png',
    'SnapCancel.png', 'SnapCancelOver.png', 'SnapCrosshair.png', 'SnapCrosshairOver.png', 'SnapFrame.png',
    'SnapFullscreen.png', 'SnapISight.png', 'SnapISightDisabled.png', 'SnapISightOver.png', 'SnapSnap.png',
    'SnapSnapOver.png', 'TipSnapBezel.png', 'ToolOffArrow.png', 'ToolOffBrush.png', 'ToolOffCircle.png',
    'ToolOffCursor.png', 'ToolOffEraser.png', 'ToolOffFill.png', 'ToolOffLine.png', 'ToolOffRect.png',
    'ToolOffText.png', 'ToolOnArrow.png', 'ToolOnBrush.png', 'ToolOnCircle.png', 'ToolOnCursor.png',
    'ToolOnEraser.png', 'ToolOnFill.png', 'ToolOnLine.png', 'ToolOnRect.png', 'ToolOnText.png', 'Toolbox.png',
    'ToolboxOver.png', 'Types.thrift', 'UserStore.thrift', 'WebSnap.nib', 'WebWindow.nib',
    'WebpostDotMac.nib', 'WebpostEvernote.nib', 'WebpostEvernoteLogin.nib', 'WebpostMySkitch.nib',
    'WebpostNetfiles.nib', 'Webpostflickr.nib', 'actionArchived.png', 'actionDragged.png', 'actionPtw.png',
    'archive_1st.m4a', 'autoSave-01.png', 'autoSave-02.png', 'autoSave-03.png', 'autoSave-04.png',
    'autoSave-05.png', 'autoSave-06.png', 'autoSave-07.png', 'autoSave-08.png', 'autoSave-09.png',
    'autoSave-10.png', 'autoSave-11.png', 'autoSave-12.png', 'autoSave-13.png', 'autoSave-14.png',
    'curl-ca-bundle.crt', 'cursorArrow-dark.png', 'cursorArrow-light.png', 'cursorArrow-overlay.png',
    'cursorBucket-dark.png', 'cursorBucket-light.png', 'cursorBucket-overlay.png', 'cursorCircle-dark.png',
    'cursorCircle-light.png', 'cursorCircle-overlay.png', 'cursorEraser.png', 'cursorLine-dark.png',
    'cursorLine-light.png', 'cursorLine-overlay.png', 'cursorPencil-dark.png', 'cursorPencil-light.png',
    'cursorPencil-overlay.png', 'cursorRectangle-dark.png', 'cursorRectangle-light.png',
    'cursorRectangle-overlay.png', 'cursorText-dark.png', 'cursorText-light.png', 'cursorText-overlay.png',
    'docWin_Bottom.png', 'docWin_BottomLeft.png', 'docWin_BottomLeftBlank.png', 'docWin_BottomRight.png',
    'docWin_BottomRightBlank.png', 'docWin_Grabbable.png', 'docWin_Left.png', 'docWin_Right.png',
    'docWin_Top.png', 'docWin_TopLeft.png', 'docWin_TopLeftBlank.png', 'docWin_TopRight.png',
    'docWin_TopRightBlank.png', 'dsa_pub.pem', 'enml.dtd', 'enml2.dtd', 'evernote-export.dtd',
    'evernote-export2.dtd', 'feedbackLoader.html', 'filename.png', 'firstlaunch.skitch', 'menu-sel.png',
    'menu.png', 'pre-snap-countdown.m4a', 'promotions.dtd', 'recoIndex.dtd', 'register-logo.png',
    'relaunch.sh', 'sizeSlider-indicator.png', 'sizeSlider.png', 'snap.m4a', 'status-icon-error.png',
    'status-icon-valid.png', 'tickbox-ticked.png', 'tickbox.png', 'wipe_already_blank.m4a',
    'wipe_brushlayer.m4a', 'wipe_snap.m4a', 'xhtml-lat1.ent', 'xhtml-special.ent', 'xhtml-symbol.ent',
    'xhtml1-strict.dtd', 'xhtml1-transitional.dtd'
)}
PATTERNS = [re.compile(p, re.I) for p in (
    r"\.(m4a|wav|aiff?|caf|mp3)$", r"\.skitch$", r"^ToolO(ff|n)[A-Za-z]+\.png$", r"^docWin_", r"^SkitchCount\d", r"^Skitch_",
    r"^Cursor[A-Za-z]+(-dark|-light|-overlay)?\.png$", r"^autoSave-\d+\.png$", r"^SKPresetResize", r"^Snap[A-Za-z]+\.png$",
)]

HASHES = set()
hash_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "original-resource-hashes.txt")
if os.path.isfile(hash_file):
    HASHES = {l.strip() for l in open(hash_file) if l.strip() and not l.startswith("#")}


def is_original(name):
    base = os.path.basename(name)
    stems = {base.lower(), (base + ".png").lower()}
    return any(n in ORIGINAL_NAMES for n in stems) or any(p.search(base) for p in PATTERNS)


def catalog_names(car):
    out = subprocess.run(["xcrun", "assetutil", "--info", car], capture_output=True, text=True)
    if out.returncode != 0:
        return None
    try:
        entries = json.loads(out.stdout)
    except ValueError:
        return None
    return {e["Name"] for e in entries if isinstance(e, dict) and e.get("Name")} | \
           {e["RenditionName"] for e in entries if isinstance(e, dict) and e.get("RenditionName")}


root = sys.argv[1] if len(sys.argv) > 1 else None
if not root or not os.path.isdir(root):
    print("usage: check-no-original.py APP_BUNDLE", file=sys.stderr)
    sys.exit(2)
hits = []
for directory, _, names in os.walk(root):
    for name in names:
        path = os.path.join(directory, name)
        if is_original(name):
            hits.append("original asset in bundle: " + path)
        if HASHES and not os.path.islink(path) and os.path.isfile(path):
            with open(path, "rb") as handle:
                if hashlib.sha256(handle.read()).hexdigest() in HASHES:
                    hits.append("bundle file is byte-identical to an original resource: " + path)
        if name.lower().endswith(".car"):
            inside = catalog_names(path)
            if inside is None:
                hits.append("cannot read asset catalog (assetutil failed): " + path)
            else:
                hits.extend("original asset in catalog %s: %s" % (path, n) for n in sorted(inside) if is_original(n))
for line in sorted(set(hits)):
    print(line, file=sys.stderr)
if hits:
    sys.exit(1)
print("PASS check-no-original (%s: no original assets by name, catalog entry or hash; no sound files)" % root)
