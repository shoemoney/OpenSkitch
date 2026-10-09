import AppKit

/// Text fields and popups only center their text at their natural height, so inside a taller glass surface
/// they sit in this holder at that height; clicks on the holder's padding still reach the control.
@MainActor
private final class ControlHolderView: NSView {
    weak var focusTarget: NSView?

    init(_ control: NSView, inset: CGFloat) {
        super.init(frame: .zero)
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            control.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if let focusTarget { window?.makeFirstResponder(focusTarget) } else { super.mouseDown(with: event) }
    }
}

/// The Modern editor layout: a window backdrop, a header holding every command, the canvas beside one right rail and a single footer row.
/// Glass sits only on the command layer and never over the canvas; every control is owned by the caller and re-parented here.
@MainActor
final class ModernEditorChrome: NSView {
    struct SharedControls {
        let canvas: NSView, canvasBorder: NSView, status: NSTextField, sizeLabel: NSTextField
        let widthControl: NSControl, paletteButton: NSButton, zoomControl: NSPopUpButton, dragFormatControl: NSControl
        let dragOriginalControl: NSButton, dragSizeLabel: NSTextField, dragExportView: NSView, toolbox: NSPopUpButton
    }

    struct Actions {
        weak var target: AnyObject?
        var hide, photos, saveHistory, showHistory, chooseTool, snap, cancelFrame, font, undo, wipe, resize, share: Selector
    }

    static let snapToolTip = "Snap: drag an area or click a window; right-click or Control-click for Fullscreen"
    static let snapFrameToolTip = "Snap Frame: capture the area inside the frame; hold Shift for a six-second timer"
    private static let toolIcons: [String: FAIcon] = [
        "select": .arrowPointer, "brush": .paintbrush, "line": .slashForward, "ellipse": .circle, "rectangle": .square,
        "fill": .fillDrip, "eraser": .eraser, "text": .text, "arrow": .arrowUpRight, "crop": .cropSimple
    ]

    /// Narrowest window the one-row top bar fits in without clipping (measured 976 pt, rounded up).
    static let minimumWindowWidth: CGFloat = 980

    let scrollView = NSScrollView()
    let header = NSView()
    private(set) var toolButtons: [String: GlassChromeButton] = [:]
    let hideButton, photosButton, saveButton, historyButton, snapButton, cancelFrameButton,
        fontButton, undoButton, wipeButton, resizeButton, shareButton: GlassChromeButton
    var backdropIsVisible: Bool { !backdrop.isHidden }
    var bleedIsVisible: Bool { !bleed.isHidden }

    /// Snap becomes Snap Frame, Cancel appears beneath it, and the translucent backdrop gives way to the Frame-mode hole.
    var frameMode = false {
        didSet { if frameMode != oldValue { applyFrameMode() } }
    }

    var accessibility: ChromeAccessibility {
        didSet {
            for surface in surfaceList { surface.accessibility = accessibility }
            updateBackdropAndBleed()
        }
    }

    private let controls: SharedControls
    private let hideAction: Selector, undoAction: Selector
    private let toolOrder: [String]
    private let accessibilityProvider: @MainActor () -> ChromeAccessibility
    private let backdrop = NSVisualEffectView()
    private let bleed = NSBackgroundExtensionView()
    private let bleedImage = NSImageView()
    private var surfaces: [ObjectIdentifier: GlassSurfaceView] = [:]
    private var surfaceList: [GlassSurfaceView] = []

    init(controls: SharedControls, actions: Actions, toolOrder: [String],
         accessibility: @escaping @MainActor () -> ChromeAccessibility = { .live }) {
        self.controls = controls
        self.hideAction = actions.hide
        self.undoAction = actions.undo
        self.toolOrder = toolOrder
        self.accessibilityProvider = accessibility
        self.accessibility = accessibility()
        // Every command is icon-only: the old title survives as the VoiceOver label and (with the shortcut) the native tooltip.
        func make(_ name: String, _ icon: FAIcon, _ action: Selector, shortcut: String? = nil, toolTip: String? = nil,
                  pointSize: CGFloat = GlassChrome.Metrics.iconPointSize) -> GlassChromeButton {
            let button = GlassChromeButton(title: "", target: actions.target, action: action)
            GlassChrome.useExtraLarge(button)
            button.iconPointSize = pointSize
            button.icon = icon
            button.makeIconOnly(name: name, shortcut: shortcut, derivesToolTip: toolTip == nil)
            if let toolTip { button.toolTip = toolTip }
            return button
        }
        hideButton = make("Hide", .eyeSlash, actions.hide, shortcut: Self.menuShortcut(for: actions.hide))
        photosButton = make("Photos", .images, actions.photos)
        saveButton = make("Save", .floppyDisk, actions.saveHistory, toolTip: "Save to History")
        historyButton = make("History", .clockRotateLeft, actions.showHistory)
        snapButton = make("Snap", .crosshairs, actions.snap, toolTip: Self.snapToolTip, pointSize: GlassChrome.Metrics.primaryIconPointSize)
        cancelFrameButton = make("Cancel", .xmark, actions.cancelFrame)
        fontButton = make("Font", .font, actions.font)
        undoButton = make("Undo", .arrowRotateLeft, actions.undo, shortcut: Self.menuShortcut(for: actions.undo))
        wipeButton = make("Wipe", .broom, actions.wipe)
        resizeButton = make("Resize…", .rulerCombined, actions.resize)
        // Icon-only upload command: a native SF Symbol, no title, so nothing but the explicit label is read aloud.
        shareButton = GlassChromeButton(title: "", target: actions.target, action: actions.share)
        GlassChrome.useExtraLarge(shareButton)
        shareButton.image = NSImage(systemSymbolName: Self.uploadSymbolName, accessibilityDescription: "Upload")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: GlassChrome.Metrics.iconPointSize, weight: .regular))
        shareButton.imagePosition = .imageOnly
        shareButton.toolTip = "Upload"
        super.init(frame: .zero)
        build(actions: actions)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The key equivalent the main menu gives an action, written the way menus show it (⌃⌥⇧⌘ then the key); nil when no item has one.
    static func menuShortcut(for action: Selector) -> String? {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == action, !item.keyEquivalent.isEmpty { return item }
                if let submenu = item.submenu, let found = find(submenu) { return found }
            }
            return nil
        }
        guard let item = (NSApp as NSApplication?)?.mainMenu.flatMap(find) else { return nil }
        var mask = item.keyEquivalentModifierMask
        if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + item.keyEquivalent.uppercased()
    }

    /// Re-reads Hide's and Undo's shortcuts from the menu bar, so a changed key equivalent changes the tooltip.
    func refreshShortcutHints() {
        hideButton.shortcutHint = Self.menuShortcut(for: hideAction)
        undoButton.shortcutHint = Self.menuShortcut(for: undoAction)
    }

    @objc private func displayOptionsChanged(_ notification: Notification) {
        accessibility = accessibilityProvider()
    }

    /// The thumbnail that bleeds under the rails; nil, Frame mode, Reduce Transparency or the flag hide it.
    func updateCanvasBleed(_ image: NSImage?) {
        bleedImage.image = image
        updateBackdropAndBleed()
    }

    func surface(for control: NSView) -> GlassSurfaceView? {
        if let known = surfaces[ObjectIdentifier(control)] { return known }
        var view: NSView? = control
        while let current = view {
            if let glass = current as? GlassSurfaceView { return glass }
            view = current.superview
        }
        return nil
    }

    // MARK: state

    private func applyFrameMode() {
        syncSnapPresentation()
        cancelFrameButton.isHidden = !frameMode
        updateBackdropAndBleed()
    }

    /// The app re-titles and re-tips Snap itself when entering or leaving Frame mode; this puts the Modern icon, name and tooltip back.
    func syncSnapPresentation() {
        snapButton.icon = frameMode ? .frameViewfinder : .crosshairs
        snapButton.title = frameMode ? "Snap Frame" : "Snap"
        snapButton.iconPointSize = GlassChrome.Metrics.primaryIconPointSize
        snapButton.toolTip = frameMode ? Self.snapFrameToolTip : Self.snapToolTip
    }

    private func updateBackdropAndBleed() {
        backdrop.isHidden = frameMode
        bleed.isHidden = !(GlassChrome.usesCanvasBleed && !accessibility.reduceTransparency && !frameMode && bleedImage.image != nil)
    }

    // MARK: construction

    static let uploadSymbolName = "icloud.and.arrow.up"

    private func register(_ surface: GlassSurfaceView, for views: NSView...) {
        if !surfaceList.contains(where: { $0 === surface }) { surfaceList.append(surface) }
        for view in views { surfaces[ObjectIdentifier(view)] = surface }
    }

    /// Every icon-only command shares one glass size so the rails and bars read as one set.
    private func iconPill(_ control: NSView, size: NSSize = GlassChrome.Metrics.iconButton) -> GlassSurfaceView {
        let surface = GlassChrome.surface(control, shape: .capsule, accessibility: accessibility, size: size)
        register(surface, for: control)
        return surface
    }

    private func readable(_ control: NSControl, _ size: CGFloat) {
        if (control.font?.pointSize ?? 0) < 18 { control.font = .systemFont(ofSize: size) }
    }

    private func build(actions: Actions) {
        typealias Metrics = GlassChrome.Metrics
        let margin: CGFloat = 12, gap: CGFloat = 8
        let headerTop: CGFloat = 4, rowHeight: CGFloat = 44, footerBottom: CGFloat = 8

        for control in [controls.dragFormatControl, controls.toolbox, controls.paletteButton] as [NSControl] { GlassChrome.useExtraLarge(control) }
        for control in [controls.dragFormatControl, controls.toolbox] as [NSControl] { readable(control, 20) }
        for control in [controls.status, controls.dragSizeLabel, controls.zoomControl, controls.dragOriginalControl, controls.widthControl] as [NSControl] { readable(control, 18) }
        // Color shows only its swatch: the title stays on the control (and its accessibility label) but is never drawn.
        controls.paletteButton.isBordered = false
        controls.paletteButton.imagePosition = .imageOnly
        controls.paletteButton.toolTip = "Color: " + (controls.paletteButton.toolTip.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "pick a drawing color")
        controls.widthControl.toolTip = "Size"
        for label in [controls.status, controls.dragSizeLabel] { label.textColor = .labelColor }
        for label in [controls.status, controls.dragSizeLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        controls.status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        bleedImage.imageScaling = .scaleAxesIndependently
        bleed.contentView = bleedImage
        bleed.alphaValue = 0.6
        bleed.isHidden = true
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = controls.canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Header: [Hide][Toolbox][Photos] · brand · [Save][History]
        header.identifier = NSUserInterfaceItemIdentifier("OpenSnapHeader")
        let toolboxIcon = ChromeIcons.resolve(.toolbox, family: .regular, pointSize: Metrics.iconPointSize)
        if let image = toolboxIcon.image, let first = controls.toolbox.itemArray.first {
            first.image = image
            controls.toolbox.imagePosition = .imageOnly
        }
        controls.toolbox.isBordered = false
        controls.toolbox.contentTintColor = .labelColor
        let hideSurface = iconPill(hideButton)
        let toolboxHolder = ControlHolderView(controls.toolbox, inset: 8)
        let toolboxSurface = GlassChrome.surface(toolboxHolder, shape: .capsule, accessibility: accessibility,
                                                 size: Metrics.toolboxButton)
        register(toolboxSurface, for: controls.toolbox, toolboxHolder)
        let photosSurface = iconPill(photosButton)
        let saveSurface = iconPill(saveButton)
        let historySurface = iconPill(historyButton)
        let leadingGroup = GlassChrome.group([hideSurface, toolboxSurface, photosSurface], orientation: .horizontal, identifier: "GlassHeaderLeading")
        let trailingGroup = GlassChrome.group([saveSurface, historySurface], orientation: .horizontal, identifier: "GlassHeaderTrailing")

        // The ten tools, archive order, icon only, then Resize: one centred row between the two end groups.
        var toolSurfaces: [GlassSurfaceView] = []
        for id in toolOrder {
            guard let icon = Self.toolIcons[id] else { continue }
            let button = GlassChromeButton(title: "", target: actions.target, action: actions.chooseTool)
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setButtonType(.toggle)
            button.iconPointSize = Metrics.iconPointSize
            button.icon = icon
            button.setAccessibilityLabel(id.capitalized)
            button.toolTip = id.capitalized + " tool"
            let surface = GlassChrome.surface(button, shape: .rounded(Metrics.toolRadius), accessibility: accessibility, size: Metrics.toolButton)
            register(surface, for: button)
            toolButtons[id] = button
            toolSurfaces.append(surface)
        }
        let resizeSurface = iconPill(resizeButton)
        let toolGroup = GlassChrome.group(toolSurfaces + [resizeSurface], orientation: .horizontal, identifier: "GlassToolBar", spacing: Metrics.toolSpacing)
        if let stack = toolGroup.contentView as? NSStackView { stack.setCustomSpacing(Metrics.resizeSeparation, after: toolSurfaces.last ?? resizeSurface) }
        for view in [leadingGroup, toolGroup, trailingGroup] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        let centred = toolGroup.centerXAnchor.constraint(equalTo: header.centerXAnchor)
        centred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            leadingGroup.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            trailingGroup.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            centred,
            toolGroup.leadingAnchor.constraint(greaterThanOrEqualTo: leadingGroup.trailingAnchor, constant: margin),
            trailingGroup.leadingAnchor.constraint(greaterThanOrEqualTo: toolGroup.trailingAnchor, constant: margin),
            leadingGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            toolGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            trailingGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        // Right rail: Snap / Cancel · Color / Font / Size · Undo / Wipe, stacked with normal spacing, all icon-only
        snapButton.isPrimary = true
        snapButton.toolTip = Self.snapToolTip
        cancelFrameButton.isHidden = true
        let snapSurface = iconPill(snapButton, size: Metrics.primaryButton)
        snapSurface.prominence = .primary
        let cancelSurface = iconPill(cancelFrameButton)
        let colorSurface = iconPill(controls.paletteButton)
        let fontSurface = iconPill(fontButton)
        let sizeStack = NSStackView(views: [controls.widthControl])
        sizeStack.orientation = .vertical
        sizeStack.spacing = 4
        sizeStack.alignment = .centerX
        sizeStack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        let sliderWidth = controls.widthControl.widthAnchor.constraint(equalToConstant: 36)
        let sliderHeight = controls.widthControl.heightAnchor.constraint(equalToConstant: 96)
        NSLayoutConstraint.activate([sliderWidth, sliderHeight])
        let sizeSurface = GlassChrome.surface(sizeStack, shape: .rounded(Metrics.toolRadius), accessibility: accessibility,
                                              size: NSSize(width: Metrics.iconButton.width, height: ceil(sizeStack.fittingSize.height)))
        register(sizeSurface, for: sizeStack, controls.widthControl)
        let undoSurface = iconPill(undoButton)
        let wipeSurface = iconPill(wipeButton)
        let captureGroup = GlassChrome.group([snapSurface, cancelSurface], orientation: .vertical, identifier: "GlassCaptureGroup")
        let drawingGroup = GlassChrome.group([colorSurface, fontSurface, sizeSurface], orientation: .vertical, identifier: "GlassDrawingGroup")
        let historyGroup = GlassChrome.group([undoSurface, wipeSurface], orientation: .vertical, identifier: "GlassHistoryGroup")
        let rightRail = NSView()
        for group in [captureGroup, drawingGroup, historyGroup] { rightRail.addSubview(group) }

        // One footer row: [zoom][status text] ········ [format][drag][upload]
        let formatControl = controls.dragFormatControl
        let formatInset: CGFloat = 4
        let formatHolder = ControlHolderView(formatControl, inset: formatInset)
        (formatControl as? NSPopUpButton)?.isBordered = false
        // A popup sizes to its selected title, so measure every title and size the capsule once for the widest: it hugs the content and never jumps.
        let widestFormat: CGFloat
        if let popup = formatControl as? NSPopUpButton {
            let selectedFormat = popup.indexOfSelectedItem
            widestFormat = (0..<popup.numberOfItems).map { index -> CGFloat in popup.selectItem(at: index); return popup.fittingSize.width }.max() ?? 0
            popup.selectItem(at: selectedFormat)
        } else { widestFormat = formatControl.fittingSize.width }
        let formatSurface = GlassChrome.surface(formatHolder, shape: .capsule, accessibility: accessibility,
                                                size: NSSize(width: ceil(widestFormat) + 2 * formatInset, height: Metrics.commandHeight))
        register(formatSurface, for: controls.dragFormatControl, formatHolder)
        let dragSurface = GlassChrome.surface(controls.dragExportView, shape: .capsule, accessibility: accessibility,
                                              size: Metrics.iconButton)
        register(dragSurface, for: controls.dragExportView)
        let shareSurface = iconPill(shareButton)
        shareButton.setAccessibilityLabel("Upload to destination")
        let footerGroup = GlassChrome.group([formatSurface, dragSurface, shareSurface], orientation: .horizontal, identifier: "GlassFooterRow")
        if let stack = footerGroup.contentView as? NSStackView { stack.distribution = .fill }

        controls.zoomControl.isBordered = true
        let zoomWidth = controls.zoomControl.widthAnchor.constraint(equalToConstant: 160)
        zoomWidth.priority = .defaultHigh
        zoomWidth.isActive = true
        let statusRow = NSStackView(views: [controls.zoomControl, controls.dragOriginalControl, controls.dragSizeLabel, controls.status])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12
        statusRow.alignment = .centerY
        statusRow.identifier = NSUserInterfaceItemIdentifier("OpenSnapStatusRow")

        let footer = NSView()
        footer.identifier = NSUserInterfaceItemIdentifier("OpenSnapFooter")
        footer.addSubview(statusRow)
        footer.addSubview(footerGroup)
        let all: [NSView] = [backdrop, bleed, scrollView, header, rightRail, footer]
        let rails: [NSView] = [captureGroup, drawingGroup, historyGroup, footerGroup, statusRow]
        for view in all + rails { view.translatesAutoresizingMaskIntoConstraints = false }
        for view in all { addSubview(view) }
        addSubview(controls.canvasBorder)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor), backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            bleed.leadingAnchor.constraint(equalTo: leadingAnchor), bleed.trailingAnchor.constraint(equalTo: trailingAnchor),
            bleed.topAnchor.constraint(equalTo: topAnchor), bleed.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.topAnchor.constraint(equalTo: topAnchor, constant: headerTop),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            header.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerBottom),
            footer.heightAnchor.constraint(equalToConstant: rowHeight),
            statusRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor), statusRow.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            statusRow.trailingAnchor.constraint(lessThanOrEqualTo: footerGroup.leadingAnchor, constant: -margin),
            footerGroup.trailingAnchor.constraint(equalTo: footer.trailingAnchor), footerGroup.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            rightRail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            rightRail.widthAnchor.constraint(equalToConstant: Metrics.rightRailWidth),
            rightRail.topAnchor.constraint(equalTo: header.bottomAnchor, constant: gap),
            rightRail.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -gap),
            captureGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor), captureGroup.topAnchor.constraint(equalTo: rightRail.topAnchor),
            drawingGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor),
            drawingGroup.topAnchor.constraint(equalTo: captureGroup.bottomAnchor, constant: Metrics.groupSpacing),
            historyGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor),
            historyGroup.topAnchor.constraint(equalTo: drawingGroup.bottomAnchor, constant: Metrics.groupSpacing),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: rightRail.leadingAnchor, constant: -gap),
            scrollView.topAnchor.constraint(equalTo: rightRail.topAnchor), scrollView.bottomAnchor.constraint(equalTo: rightRail.bottomAnchor)
        ])

        // Only the mirrored edge of the thumbnail shows under the bars and rails; the canvas area itself stays clear.
        bleed.additionalSafeAreaInsets = NSEdgeInsets(
            top: headerTop + Metrics.headerHeight + gap, left: margin,
            bottom: footerBottom + rowHeight + gap, right: margin + Metrics.rightRailWidth + gap)
        updateBackdropAndBleed()
    }
}


/// Modern only: a document smaller than the visible area sits in the middle of it, per axis. A larger one is
/// constrained exactly as NSClipView does, so scrolling, panning and the scroll origin are unchanged.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let frame = documentView?.frame else { return rect }
        if frame.width < rect.width { rect.origin.x = frame.minX - (rect.width - frame.width) / 2 }
        if frame.height < rect.height { rect.origin.y = frame.minY - (rect.height - frame.height) / 2 }
        return rect
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recentre()
    }

    override func viewFrameChanged(_ notification: Notification) {
        super.viewFrameChanged(notification)
        recentre()
    }

    override func layout() {
        super.layout()
        recentre()
    }

    override func viewBoundsChanged(_ notification: Notification) {
        super.viewBoundsChanged(notification)
        recentre()
    }

    private func recentre() {
        let target = constrainBoundsRect(bounds).origin
        if target != bounds.origin { scroll(to: target) }
    }
}
