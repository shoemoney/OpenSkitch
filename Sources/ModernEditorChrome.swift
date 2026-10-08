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

/// The Modern editor layout: a window backdrop, the canvas between two glass rails, a header and a two-row footer.
/// Glass sits only on the command layer and never over the canvas; every control is owned by the caller and re-parented here.
@available(macOS 26, *)
@MainActor
final class ModernEditorChrome: NSView {
    struct SharedControls {
        let canvas: NSView, canvasBorder: NSView, nameField: NSTextField, status: NSTextField, sizeLabel: NSTextField
        let widthControl: NSControl, paletteButton: NSButton, zoomControl: NSPopUpButton, dragFormatControl: NSPopUpButton
        let dragOriginalControl: NSButton, dragSizeLabel: NSTextField, dragExportView: NSView, toolbox: NSPopUpButton
        let brandLogo: NSImage?
    }

    struct Actions {
        weak var target: AnyObject?
        var hide, photos, saveHistory, showHistory, chooseTool, snap, cancelFrame, font, undo, wipe, actualSize, resize, share: Selector
    }

    static let snapToolTip = "Drag an area or click a window; right-click or Control-click for Fullscreen"
    static let snapFrameToolTip = "Capture the area inside the frame; hold Shift for a six-second timer"
    private static let toolIcons: [String: FAIcon] = [
        "select": .arrowPointer, "brush": .paintbrush, "line": .slashForward, "ellipse": .circle, "rectangle": .square,
        "fill": .fillDrip, "eraser": .eraser, "text": .text, "arrow": .arrowUpRight, "crop": .cropSimple
    ]

    let scrollView = NSScrollView()
    let header = NSView()
    private(set) var toolButtons: [String: GlassChromeButton] = [:]
    let hideButton, photosButton, saveButton, historyButton, snapButton, cancelFrameButton,
        fontButton, undoButton, wipeButton, actualButton, resizeButton, shareButton: GlassChromeButton
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
        self.toolOrder = toolOrder
        self.accessibilityProvider = accessibility
        self.accessibility = accessibility()
        func make(_ title: String, _ icon: FAIcon, _ action: Selector) -> GlassChromeButton {
            let button = GlassChromeButton(title: title, target: actions.target, action: action)
            GlassChrome.useExtraLarge(button)
            button.font = .systemFont(ofSize: GlassChrome.Metrics.labelPointSize)
            button.iconPointSize = GlassChrome.Metrics.labeledIconPointSize
            button.icon = icon
            button.classicArtworkName = ChromeIcons.classicArtworkName(for: icon)
            return button
        }
        hideButton = make("Hide", .eyeSlash, actions.hide)
        photosButton = make("Photos", .images, actions.photos)
        saveButton = make("Save", .floppyDisk, actions.saveHistory)
        historyButton = make("History", .clockRotateLeft, actions.showHistory)
        snapButton = make("Snap", .crosshairs, actions.snap)
        cancelFrameButton = make("Cancel", .xmark, actions.cancelFrame)
        fontButton = make("Font", .font, actions.font)
        undoButton = make("Undo", .arrowRotateLeft, actions.undo)
        wipeButton = make("Wipe", .broom, actions.wipe)
        actualButton = make("Actual Size", .maximize, actions.actualSize)
        resizeButton = make("Resize…", .rulerCombined, actions.resize)
        // Icon-only upload command: a native SF Symbol, no title, so nothing but the explicit label is read aloud.
        shareButton = GlassChromeButton(title: "", target: actions.target, action: actions.share)
        GlassChrome.useExtraLarge(shareButton)
        shareButton.image = NSImage(systemSymbolName: Self.uploadSymbolName, accessibilityDescription: "Upload")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: GlassChrome.Metrics.iconPointSize, weight: .regular))
        shareButton.imagePosition = .imageOnly
        super.init(frame: .zero)
        build(actions: actions)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        snapButton.icon = frameMode ? .frameViewfinder : .crosshairs
        snapButton.classicArtworkName = ChromeIcons.classicArtworkName(for: frameMode ? .frameViewfinder : .crosshairs)
        snapButton.title = frameMode ? "Snap Frame" : "Snap"
        snapButton.toolTip = frameMode ? Self.snapFrameToolTip : Self.snapToolTip
        cancelFrameButton.isHidden = !frameMode
        updateBackdropAndBleed()
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

    private func pill(_ control: NSView, shape: GlassShape = .capsule, width: CGFloat? = nil) -> GlassSurfaceView {
        let size = width.map { NSSize(width: $0, height: GlassChrome.Metrics.commandHeight) }
        let surface = GlassChrome.surface(control, shape: shape, accessibility: accessibility, size: size)
        register(surface, for: control)
        return surface
    }

    private func readable(_ control: NSControl, _ size: CGFloat) {
        if (control.font?.pointSize ?? 0) < 18 { control.font = .systemFont(ofSize: size) }
    }

    private static func widest(_ button: NSButton, titles: [String]) -> CGFloat {
        let original = button.title
        defer { button.title = original }
        return titles.map { button.title = $0; return ceil(button.fittingSize.width) }.max() ?? 0
    }

    private func build(actions: Actions) {
        typealias Metrics = GlassChrome.Metrics
        let margin: CGFloat = 12, gap: CGFloat = 8
        let headerTop: CGFloat = 4, rowHeight: CGFloat = 44, statusHeight: CGFloat = 30, rowGap: CGFloat = 4, footerBottom: CGFloat = 8
        let pillPadding = Metrics.pillPadding
        let railPill = Metrics.railPillWidth

        for control in [controls.nameField, controls.dragFormatControl, controls.toolbox, controls.paletteButton] as [NSControl] { GlassChrome.useExtraLarge(control) }
        for control in [controls.nameField, controls.dragFormatControl, controls.toolbox] as [NSControl] { readable(control, 20) }
        for control in [controls.status, controls.sizeLabel, controls.dragSizeLabel, controls.zoomControl, controls.dragOriginalControl, controls.widthControl] as [NSControl] { readable(control, 18) }
        controls.paletteButton.font = .systemFont(ofSize: Metrics.labelPointSize)
        controls.paletteButton.isBordered = false
        controls.paletteButton.imagePosition = .imageLeading
        controls.paletteButton.imageHugsTitle = true
        for label in [controls.status, controls.sizeLabel, controls.dragSizeLabel] { label.textColor = .labelColor }
        for label in [controls.status, controls.dragSizeLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        controls.status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (controls.widthControl as? BezelSizeSlider)?.style = .modern

        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        bleedImage.imageScaling = .scaleAxesIndependently
        bleed.contentView = bleedImage
        bleed.alphaValue = 0.6
        bleed.isHidden = true
        scrollView.documentView = controls.canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Header: [Hide][Toolbox][Photos] · brand · [Save][History]
        header.identifier = NSUserInterfaceItemIdentifier("OpenSkitchHeader")
        let toolboxIcon = ChromeIcons.resolve(.toolbox, family: .regular, pointSize: Metrics.iconPointSize, classic: nil)
        if let image = toolboxIcon.image, let first = controls.toolbox.itemArray.first {
            first.image = image
            controls.toolbox.imagePosition = .imageOnly
        }
        controls.toolbox.isBordered = false
        controls.toolbox.contentTintColor = .labelColor
        let hideSurface = pill(hideButton)
        let toolboxHolder = ControlHolderView(controls.toolbox, inset: 6)
        let toolboxSurface = GlassChrome.surface(toolboxHolder, shape: .capsule, accessibility: accessibility,
                                                 size: NSSize(width: max(64, ceil(controls.toolbox.fittingSize.width) + 12), height: Metrics.commandHeight))
        register(toolboxSurface, for: controls.toolbox, toolboxHolder)
        let photosSurface = pill(photosButton)
        let saveSurface = pill(saveButton)
        let historySurface = pill(historyButton)
        let leadingGroup = GlassChrome.group([hideSurface, toolboxSurface, photosSurface], orientation: .horizontal, identifier: "GlassHeaderLeading")
        let trailingGroup = GlassChrome.group([saveSurface, historySurface], orientation: .horizontal, identifier: "GlassHeaderTrailing")

        let logo = NSImageView()
        logo.image = controls.brandLogo
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("ShoeMoney logo")
        let name = NSTextField(labelWithString: "OpenSkitch")
        name.font = .systemFont(ofSize: Metrics.labelPointSize, weight: .semibold)
        name.setContentCompressionResistancePriority(.required, for: .horizontal)
        let brand = NSStackView(views: [logo, name])
        brand.orientation = .horizontal
        brand.spacing = 8
        brand.alignment = .centerY
        brand.identifier = NSUserInterfaceItemIdentifier("OpenSkitchBrand")
        for view in [leadingGroup, brand, trailingGroup] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 32), logo.heightAnchor.constraint(equalToConstant: 32),
            leadingGroup.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            trailingGroup.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            brand.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            brand.leadingAnchor.constraint(greaterThanOrEqualTo: leadingGroup.trailingAnchor, constant: margin),
            trailingGroup.leadingAnchor.constraint(greaterThanOrEqualTo: brand.trailingAnchor, constant: margin),
            leadingGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brand.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            trailingGroup.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        // Left rail: the ten tools, archive order, icon only.
        var toolSurfaces: [GlassSurfaceView] = []
        for id in toolOrder {
            guard let icon = Self.toolIcons[id] else { continue }
            let button = GlassChromeButton(title: "", target: actions.target, action: actions.chooseTool)
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setButtonType(.toggle)
            button.iconPointSize = Metrics.iconPointSize
            button.icon = icon
            button.classicArtworkName = ChromeIcons.classicArtworkName(for: icon)
            button.setAccessibilityLabel(id.capitalized)
            button.toolTip = id.capitalized + " tool"
            let surface = GlassChrome.surface(button, shape: .rounded(Metrics.toolRadius), accessibility: accessibility, size: Metrics.toolButton)
            register(surface, for: button)
            toolButtons[id] = button
            toolSurfaces.append(surface)
        }
        let toolGroup = GlassChrome.group(toolSurfaces, orientation: .vertical, identifier: "GlassToolRail", spacing: Metrics.toolSpacing)
        let leftRail = NSView()
        leftRail.addSubview(toolGroup)

        // Right rail: Snap / Cancel · Color / Font / Size · (flexible) · Undo / Wipe
        snapButton.isPrimary = true
        snapButton.toolTip = Self.snapToolTip
        cancelFrameButton.isHidden = true
        let snapSurface = pill(snapButton, width: railPill)
        snapSurface.prominence = .primary
        let cancelSurface = pill(cancelFrameButton, width: railPill)
        let colorSurface = pill(controls.paletteButton, width: railPill)
        let fontSurface = pill(fontButton, width: railPill)
        let sizeStack = NSStackView(views: [controls.sizeLabel, controls.widthControl])
        sizeStack.orientation = .vertical
        sizeStack.spacing = 4
        sizeStack.alignment = .centerX
        sizeStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        let sliderWidth = controls.widthControl.widthAnchor.constraint(equalToConstant: 36)
        let sliderHeight = controls.widthControl.heightAnchor.constraint(equalToConstant: 82)
        NSLayoutConstraint.activate([sliderWidth, sliderHeight])
        let sizeSurface = GlassChrome.surface(sizeStack, shape: .rounded(Metrics.toolRadius), accessibility: accessibility,
                                              size: NSSize(width: railPill, height: ceil(sizeStack.fittingSize.height)))
        register(sizeSurface, for: sizeStack, controls.sizeLabel, controls.widthControl)
        let undoSurface = pill(undoButton, width: railPill)
        let wipeSurface = pill(wipeButton, width: railPill)
        let captureGroup = GlassChrome.group([snapSurface, cancelSurface], orientation: .vertical, identifier: "GlassCaptureGroup")
        let drawingGroup = GlassChrome.group([colorSurface, fontSurface, sizeSurface], orientation: .vertical, identifier: "GlassDrawingGroup")
        let historyGroup = GlassChrome.group([undoSurface, wipeSurface], orientation: .vertical, identifier: "GlassHistoryGroup")
        let rightRail = NSView()
        for group in [captureGroup, drawingGroup, historyGroup] { rightRail.addSubview(group) }

        // Footer row 1: [Actual Size][Resize…] · name · format · Drag Me · Webpost…
        actualButton.setButtonType(.toggle)
        actualButton.selectedIcon = .minimize
        actualButton.selectedClassicArtworkName = ChromeIcons.classicArtworkName(for: .minimize)
        actualButton.selectionTints = false
        let actualWidth = Self.widest(actualButton, titles: ["Actual Size", "Normal View"]) + 2 * pillPadding
        let actualSurface = pill(actualButton, width: actualWidth)
        let resizeSurface = pill(resizeButton)
        controls.nameField.isBezeled = false
        controls.nameField.isBordered = false
        controls.nameField.drawsBackground = false
        controls.nameField.borderShape = .capsule
        let nameHolder = ControlHolderView(controls.nameField, inset: pillPadding)
        nameHolder.focusTarget = controls.nameField
        let nameSurface = GlassChrome.surface(nameHolder, shape: .capsule, accessibility: accessibility,
                                              size: NSSize(width: 120, height: Metrics.commandHeight))
        nameSurface.setSize(NSSize(width: 120, height: Metrics.commandHeight), flexibleWidth: true)
        nameSurface.setContentHuggingPriority(.defaultLow, for: .horizontal)
        register(nameSurface, for: controls.nameField, nameHolder)
        let formatFont = controls.dragFormatControl.font ?? .systemFont(ofSize: Metrics.labelPointSize)
        let widestFormat = controls.dragFormatControl.itemTitles.map { ($0 as NSString).size(withAttributes: [.font: formatFont]).width }.max() ?? 0
        let formatHolder = ControlHolderView(controls.dragFormatControl, inset: 8)
        controls.dragFormatControl.isBordered = false
        let formatSurface = GlassChrome.surface(formatHolder, shape: .capsule, accessibility: accessibility,
                                                size: NSSize(width: ceil(widestFormat) + 44, height: Metrics.commandHeight))
        register(formatSurface, for: controls.dragFormatControl, formatHolder)
        let dragSurface = GlassChrome.surface(controls.dragExportView, shape: .rounded(Metrics.dragRadius), accessibility: accessibility,
                                              size: NSSize(width: 112, height: Metrics.commandHeight))
        register(dragSurface, for: controls.dragExportView)
        let shareSurface = pill(shareButton, width: Metrics.commandHeight + 12)
        shareButton.setAccessibilityLabel("Upload to destination")
        let footerGroup = GlassChrome.group([actualSurface, resizeSurface, nameSurface, formatSurface, dragSurface, shareSurface],
                                            orientation: .horizontal, identifier: "GlassFooterRow")
        if let stack = footerGroup.contentView as? NSStackView {
            stack.distribution = .fill
            for view in [resizeSurface, nameSurface, formatSurface, dragSurface] { stack.setCustomSpacing(Metrics.groupSpacing, after: view) }
        }

        // Footer row 2: plain 18-point labels.
        controls.zoomControl.isBordered = true
        let zoomWidth = controls.zoomControl.widthAnchor.constraint(equalToConstant: 160)
        zoomWidth.priority = .defaultHigh
        zoomWidth.isActive = true
        let statusRow = NSStackView(views: [controls.zoomControl, controls.dragOriginalControl, controls.dragSizeLabel, controls.status])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12
        statusRow.alignment = .centerY

        let row1 = NSView(), row2 = NSView()
        row1.addSubview(footerGroup)
        row2.addSubview(statusRow)
        let all: [NSView] = [backdrop, bleed, scrollView, header, leftRail, rightRail, row1, row2]
        let rails: [NSView] = [toolGroup, captureGroup, drawingGroup, historyGroup, footerGroup, statusRow]
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

            row2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            row2.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            row2.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerBottom),
            row2.heightAnchor.constraint(equalToConstant: statusHeight),
            statusRow.leadingAnchor.constraint(equalTo: row2.leadingAnchor), statusRow.trailingAnchor.constraint(equalTo: row2.trailingAnchor),
            statusRow.centerYAnchor.constraint(equalTo: row2.centerYAnchor),
            row1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            row1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            row1.bottomAnchor.constraint(equalTo: row2.topAnchor, constant: -rowGap),
            row1.heightAnchor.constraint(equalToConstant: rowHeight),
            footerGroup.leadingAnchor.constraint(equalTo: row1.leadingAnchor), footerGroup.trailingAnchor.constraint(equalTo: row1.trailingAnchor),
            footerGroup.centerYAnchor.constraint(equalTo: row1.centerYAnchor),

            leftRail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            leftRail.widthAnchor.constraint(equalToConstant: Metrics.railWidth),
            leftRail.topAnchor.constraint(equalTo: header.bottomAnchor, constant: gap),
            leftRail.bottomAnchor.constraint(equalTo: row1.topAnchor, constant: -gap),
            toolGroup.centerXAnchor.constraint(equalTo: leftRail.centerXAnchor), toolGroup.topAnchor.constraint(equalTo: leftRail.topAnchor),
            rightRail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            rightRail.widthAnchor.constraint(equalToConstant: Metrics.rightRailWidth),
            rightRail.topAnchor.constraint(equalTo: leftRail.topAnchor), rightRail.bottomAnchor.constraint(equalTo: leftRail.bottomAnchor),
            captureGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor), captureGroup.topAnchor.constraint(equalTo: rightRail.topAnchor),
            drawingGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor),
            drawingGroup.topAnchor.constraint(equalTo: captureGroup.bottomAnchor, constant: Metrics.groupSpacing),
            historyGroup.centerXAnchor.constraint(equalTo: rightRail.centerXAnchor), historyGroup.bottomAnchor.constraint(equalTo: rightRail.bottomAnchor),
            historyGroup.topAnchor.constraint(greaterThanOrEqualTo: drawingGroup.bottomAnchor, constant: Metrics.groupSpacing),

            scrollView.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: gap),
            scrollView.trailingAnchor.constraint(equalTo: rightRail.leadingAnchor, constant: -gap),
            scrollView.topAnchor.constraint(equalTo: leftRail.topAnchor), scrollView.bottomAnchor.constraint(equalTo: leftRail.bottomAnchor)
        ])

        // Only the mirrored edge of the thumbnail shows under the bars and rails; the canvas area itself stays clear.
        bleed.additionalSafeAreaInsets = NSEdgeInsets(
            top: headerTop + Metrics.headerHeight + gap, left: margin + Metrics.railWidth + gap,
            bottom: footerBottom + statusHeight + rowGap + rowHeight + gap, right: margin + Metrics.rightRailWidth + gap)
        updateBackdropAndBleed()
    }
}
