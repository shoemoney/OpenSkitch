#!/usr/bin/env python3
"""Exit 1 if a built bundle contains any recovered original-app asset or any sound file.

Usage: check-no-original.py PATH   (the whole .app)
The name list is static on purpose: this gate must work with no original/ folder on disk.
Names are matched case-insensitively against every file in the bundle; ".m4a" and the
original's numbered families are also matched by pattern.
"""
import os
import re
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
    r"\.m4a$", r"\.skitch$", r"^ToolO(ff|n)[A-Za-z]+\.png$", r"^docWin_", r"^SkitchCount\d", r"^Skitch_",
    r"^Cursor[A-Za-z]+(-dark|-light|-overlay)?\.png$", r"^autoSave-\d+\.png$", r"^SKPresetResize", r"^Snap[A-Za-z]+\.png$",
)]

root = sys.argv[1] if len(sys.argv) > 1 else None
if not root or not os.path.isdir(root):
    print("usage: check-no-original.py APP_BUNDLE", file=sys.stderr)
    sys.exit(2)
hits = []
for directory, _, names in os.walk(root):
    for name in names:
        if name.lower() in ORIGINAL_NAMES or any(p.search(name) for p in PATTERNS):
            hits.append(os.path.join(directory, name))
for path in hits:
    print("original asset in bundle: " + path, file=sys.stderr)
if hits:
    sys.exit(1)
print("PASS check-no-original (%s: no original assets, no .m4a)" % root)
