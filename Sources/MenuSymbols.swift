import AppKit

/// SF Symbols for the main menu (macOS 26 menus show leading icons). Keys are the real @objc action names in App.swift.
@MainActor
enum MenuSymbols {
    static let map: [Selector: String] = Dictionary(uniqueKeysWithValues: [
        ("about", "info.circle"), ("showPreferences", "gearshape"), ("sharingSettings", "network"),
        ("shortcutSettings", "keyboard"), ("quit", "power"), ("toggleVisible", "eye.slash"),
        ("newFile", "doc"), ("openFile", "folder"), ("showPhotos", "photo.on.rectangle"),
        ("saveFile", "square.and.arrow.down"), ("saveAs", "square.and.arrow.down.on.square"),
        ("saveHistory", "tray.and.arrow.down"), ("showHistory", "clock.arrow.circlepath"),
        ("exportFile", "square.and.arrow.up"), ("publishImage", "globe"), ("printImage", "printer"),
        ("pageSetup", "doc.badge.gearshape"), ("closeCurrentWindow", "xmark.circle"),
        ("undo", "arrow.uturn.backward"), ("redo", "arrow.uturn.forward"), ("cut", "scissors"),
        ("copyArtwork", "doc.on.doc"), ("copyImage", "doc.on.clipboard"), ("paste", "clipboard"),
        ("deleteSelection", "trash"), ("selectAll", "square.dashed"), ("duplicate", "plus.square.on.square"),
        ("wipe", "clear"), ("wipeSnap", "rectangle.slash"), ("clear", "pencil.slash"),
        ("toggleActualSize", "arrow.up.left.and.arrow.down.right"), ("resize", "ruler"), ("crop", "crop"),
        ("trimSnap", "rectangle.compress.vertical"), ("rotateCW", "rotate.right"), ("rotateCCW", "rotate.left"),
        ("flipH", "arrow.left.and.right.righttriangle.left.righttriangle.right"),
        ("flipV", "arrow.up.and.down.righttriangle.up.righttriangle.down"),
        ("transparent", "checkerboard.rectangle"), ("white", "rectangle.fill"),
        ("flatten", "square.3.layers.3d.down.right"), ("front", "square.3.layers.3d.top.filled"),
        ("back", "square.3.layers.3d.bottom.filled"), ("group", "rectangle.3.group"),
        ("ungroup", "square.on.square.dashed"), ("chooseFont", "textformat"), ("defaultTextStyle", "textformat.abc"),
        ("toggleOutline", "a.square"), ("toggleTextShadow", "shadow"), ("screenSnap", "scope"),
        ("fullscreenSnap", "rectangle.inset.filled"), ("windowSnap", "macwindow"), ("frameSnap", "camera.viewfinder"),
        ("resnap", "arrow.triangle.2.circlepath.camera"), ("cancelFrame", "xmark"), ("timedSnap", "timer"),
        ("cancelSnapshot", "xmark.circle"), ("cameraSnap", "camera"), ("webSnap", "link"),
    ].map { (Selector($0.0), $0.1) })

    /// Test seam for a symbol that is missing on the host.
    static var symbolImage: (String) -> NSImage? = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }

    @available(macOS 26, *)
    static func apply(to menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            if item.image == nil, let action = item.action, let name = map[action], let image = symbolImage(name) {
                image.isTemplate = true
                item.image = image
            }
            if let submenu = item.submenu { apply(to: submenu) }
        }
    }
}
