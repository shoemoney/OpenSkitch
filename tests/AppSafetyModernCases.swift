// Modern appearance integration cases. tools/test-app-safety.sh --appearance modern runs these instead of the
// Classic list: the same real AppDelegate launch, with ModernEditorChrome as the window content.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var modernCases: [(String, () throws -> Void)] {
        guard #available(macOS 26, *) else {
            return [("Modern appearance requires macOS 26", { throw Failure(description: "SKITCH_APPEARANCE=modern needs a macOS 26 host") })]
        }
        return [
            ("Modern chrome fills the Frame-aware content view and replaces every Classic control", modernWindowStructure),
            ("Modern shared controls keep the Classic accessibility labels, tooltips, titles and hint tracking", modernControlStrings),
            ("setTool selects one glass surface in the solid family for every path that changes the tool", modernToolSelection),
            ("Frame enter and leave swap Snap and Cancel, clear and restore the Fullscreen alternate, and dim Resize", modernFrameMode),
            ("Modern Frame mode drops the window shadow, raises the level and sets alpha 0.8, and leaving restores the pre-Frame values", modernFrameWindowShadowLevelAlpha),
            ("updateDragPreview feeds the canvas bleed, and Frame mode and Reduce Transparency hide it", modernCanvasBleed),
            ("Injected display options reach every glass surface and clear again", modernAccessibilityInjection),
            ("Header and footer buttons reach the real AppDelegate actions", modernActionRouting),
            ("Modern rail Wipe presses follow the Blank/Clear/Wipe stages with the dimmed glass and the stage spoken", modernWipeStages),
            ("Preferences Appearance row writes the stored choice without switching the running window", modernPreferencesAppearance),
            ("relaunch() requests termination once and launches only after quit, never from a cancelled Save", modernRelaunch),
            ("The relaunch launcher waits, bounded, for LaunchServices to accept the request before the old instance exits", modernRelaunchLauncher),
            ("writeLayoutEvidence reports the Modern style and finds the header and brand one level deeper", modernLayoutEvidence),
            ("Main menu items carry symbols in Modern only and keep validating", modernMenus),
            ("Color popover follows the system appearance in Modern and stays aqua in Classic", modernPalettePopover),
            ("Modern canvas border corner and edge mouse drags resize and crop like Classic with one Undo each, and Escape cancels", modernBorderGestures)
        ]
    }

    // MARK: fixtures and walkers

    @available(macOS 26, *)
    private static func modernFixture() throws -> (Fixture, ModernEditorChrome) {
        try expect(Appearance.isModern, "SKITCH_APPEARANCE=modern selects the Modern chrome")
        let fixture = try Fixture()
        guard let chrome = fixture.app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        // The host's Reduce Transparency or Increase Contrast must never decide a result.
        chrome.accessibility = .none
        return (fixture, chrome)
    }

    private static func collect<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        var found: [T] = []
        func walk(_ view: NSView) {
            if let match = view as? T { found.append(match) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    private static func descendant(_ root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        var children = root.subviews
        if let tabs = root as? NSTabView { children += tabs.tabViewItems.compactMap(\.view) }
        for child in children { if let found = descendant(child, identifier: identifier) { return found } }
        return nil
    }

    @available(macOS 26, *)
    private static func surface(_ chrome: ModernEditorChrome, _ control: NSView?) throws -> GlassSurfaceView {
        guard let control, let surface = chrome.surface(for: control) else { throw Failure(description: "A control has no glass surface") }
        return surface
    }

    private static func sameColor(_ a: NSColor?, _ b: NSColor) -> Bool {
        guard let a = a?.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }

    private static let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]

    // MARK: Classic baseline

    /// What the Classic window says about its controls, read from a real Classic AppDelegate in this same process.
    /// A Fixture clears NSApp.mainMenu when it goes away, so this finishes before any Modern fixture exists.
    private struct ClassicBaseline {
        var controls: [String: String]
        var menuImageCount: Int
        var popoverAppearance: NSAppearance.Name?
    }

    /// The 12 command buttons, each found by the Classic action it sends so both windows are read the same way.
    private static let commandActions: [(name: String, action: Selector)] = [
        ("hide", #selector(AppDelegate.vanish)), ("photos", #selector(AppDelegate.showPhotos)), ("save", #selector(AppDelegate.saveHistory)),
        ("history", #selector(AppDelegate.showHistory)), ("snap", #selector(AppDelegate.snapButtonPressed)),
        ("cancel", #selector(AppDelegate.cancelFrame)), ("font", #selector(AppDelegate.chooseFont)), ("undo", #selector(AppDelegate.undo)),
        ("wipe", #selector(AppDelegate.wipe)), ("actual", #selector(AppDelegate.toggleActualSize)), ("resize", #selector(AppDelegate.resize)),
        ("share", #selector(AppDelegate.share(_:)))
    ]

    private static func controlFacts(_ app: AppDelegate) -> [String: String] {
        guard let content = app.window.contentView else { return [:] }
        var facts: [String: String] = [:]
        for tool in SketchTool.allCases {
            let button = app.toolButtons[tool]
            facts["tool.\(tool.rawValue).id"] = button?.identifier?.rawValue ?? "<nil>"
            facts["tool.\(tool.rawValue).label"] = button?.accessibilityLabel() ?? "<nil>"
            facts["tool.\(tool.rawValue).tip"] = button?.toolTip ?? "<nil>"
        }
        facts["snap.tip"] = app.snapButton.toolTip ?? "<nil>"
        facts["palette.label"] = app.paletteButton.accessibilityLabel() ?? "<nil>"
        facts["palette.tip"] = app.paletteButton.toolTip ?? "<nil>"
        facts["zoom.label"] = app.zoomControl.accessibilityLabel() ?? "<nil>"
        facts["format.label"] = app.dragFormatControl.accessibilityLabel() ?? "<nil>"
        facts["drag.label"] = app.dragExportView?.accessibilityLabel() ?? "<nil>"
        facts["drag.tip"] = app.dragExportView?.toolTip ?? "<nil>"
        facts["original.title"] = app.dragOriginalControl.title
        facts["original.label"] = app.dragOriginalControl.accessibilityLabel() ?? "<nil>"
        facts["size.label"] = app.widthControl.accessibilityLabel() ?? "<nil>"
        facts["size.tip"] = app.widthControl.toolTip ?? "<nil>"
        facts["name.placeholder"] = app.nameField.placeholderString ?? "<nil>"
        facts["status.font"] = String(Double(app.status.font?.pointSize ?? 0))
        let toolbox = collect(NSPopUpButton.self, in: content).first { $0.accessibilityLabel() == "Toolbox" }
        facts["toolbox.label"] = toolbox?.accessibilityLabel() ?? "<nil>"
        facts["toolbox.tip"] = toolbox?.toolTip ?? "<nil>"
        facts["toolbox.items"] = toolbox?.itemTitles.joined(separator: "|") ?? "<nil>"
        let tools = Set(app.toolButtons.values.map(ObjectIdentifier.init))
        let plain = collect(NSButton.self, in: content).filter { !($0 is NSPopUpButton) && !tools.contains(ObjectIdentifier($0)) }
        facts["buttons"] = plain.map(\.title).sorted().joined(separator: "|")
        facts["share.label"] = plain.first { $0.title == "Webpost…" }?.accessibilityLabel() ?? "<nil>"
        // What VoiceOver reads for each command. Classic buttons read their titles; a symbol fallback must not read its own name instead.
        for (name, action) in commandActions { facts["axLabel.\(name)"] = plain.first { $0.action == action }?.accessibilityLabel() ?? "<nil>" }
        facts["actual.title"] = app.actualButton?.title ?? "<nil>"
        facts["resize.title"] = app.resizeButton?.title ?? "<nil>"
        return facts
    }

    @available(macOS 26, *)
    private static func classicBaseline() throws -> ClassicBaseline {
        Appearance.overrideForTesting(.classic)
        defer { Appearance.overrideForTesting(.modern) }
        let fixture = try Fixture(), app = fixture.app
        try expect(app.modernChrome == nil && app.toolButtons[.brush] is ToolButton, "The Classic baseline builds the Classic window")
        guard let bar = NSApp.mainMenu, let window = app.window as? AppSafetyWindow else { throw Failure(description: "Classic baseline fixture") }
        var images = 0
        // AppKit itself decorates its own standard commands (Hide Others, Show All, Bring All to Front); only ours count.
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.image != nil, let action = item.action, MenuSymbols.map[action] != nil { images += 1 }
                if let sub = item.submenu { walk(sub) }
            }
        }
        walk(bar)
        window.simulatesVisibility = true; window.shown = true
        app.showDrawingColors(app.paletteButton)
        let popover = app.colorPopover?.appearance?.name
        app.closeDrawingColors()
        return ClassicBaseline(controls: controlFacts(app), menuImageCount: images, popoverAppearance: popover)
    }

    // MARK: cases

    @available(macOS 26, *)
    private static func modernWindowStructure() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "The content view must stay the Frame-aware FrameChromeView") }
        content.layoutSubtreeIfNeeded()
        try expect(chrome.superview === content && !chrome.translatesAutoresizingMaskIntoConstraints, "The chrome is a constrained child of the content view")
        try expect(chrome.frame == content.bounds, "The chrome is pinned to all four content edges at origin 0: \(chrome.frame) vs \(content.bounds)")
        try expect(!content.usesRecoveredBezel && content.appearance == nil, "Modern draws no recovered bezel and never forces aqua")
        try expect(content.canvasScrollView === chrome.scrollView && app.canvas.enclosingScrollView === chrome.scrollView && chrome.scrollView.documentView === app.canvas,
                   "The Frame hole and the canvas both use the chrome's scroll view")
        try expect(app.canvasBorder.superview === chrome && chrome.subviews.last === app.canvasBorder, "The canvas border stays the topmost sibling in chrome coordinates")
        try expect(app.window.minSize == NSSize(width: 900, height: 640), "The minimum window size is unchanged")

        // Controls the app keeps by reference are the chrome's own.
        try expect(app.snapButton === chrome.snapButton && app.cancelFrameButton === chrome.cancelFrameButton
                   && app.actualButton === chrome.actualButton && app.resizeButton === chrome.resizeButton, "AppDelegate controls Snap, Cancel, Actual Size and Resize through the chrome's buttons")
        let tools = toolOrder.compactMap { SketchTool(rawValue: $0).flatMap { app.toolButtons[$0] } }
        try expect(tools.count == 10 && app.toolButtons.count == 10, "All ten tools, Crop included, are registered")
        try expect(tools.allSatisfy { $0 is GlassChromeButton && !($0 is ToolButton) }, "Modern tools are glass buttons, not the Classic ToolButton")
        try expect(tools.map { $0.identifier?.rawValue ?? "" } == toolOrder, "Tool identifiers keep the archive order and raw values")
        let top = tools.sorted { $0.convert($0.bounds, to: content).maxY > $1.convert($1.bounds, to: content).maxY }
        try expect(top.map { $0.identifier?.rawValue ?? "" } == toolOrder, "The tool rail runs top to bottom in archive order with Crop last")
        try expect(zip(tools, toolOrder).allSatisfy { button, id in chrome.toolButtons[id] === button }, "Registered tool buttons are the chrome's")
        try expect(tools.allSatisfy { $0.target === app && $0.action == #selector(AppDelegate.chooseTool(_:)) }, "Every tool sends chooseTool to the AppDelegate")

        // Shared controls take the Modern treatment but keep their behavior.
        try expect(app.widthControl.style == .modern, "The size slider uses the vector style")
        try expect(app.dragExportView?.drawsBackground == false, "Drag Me lets its glass be the plate")
        try expect(try surface(chrome, app.dragExportView).shape == .rounded(14), "Drag Me sits in a rounded r=14 surface")
        try expect(try surface(chrome, app.paletteButton).fixedSize?.width == 148 && chrome.surface(for: app.nameField)?.shape == .capsule
                   && chrome.surface(for: app.dragFormatControl)?.shape == .capsule, "Color, the name field and the format popup have their glass")
        try expect(chrome.surface(for: app.zoomControl) == nil && chrome.surface(for: app.status) == nil && chrome.surface(for: app.canvas) == nil, "Zoom, status and the canvas stay outside glass")
        try expect((app.nameField.font?.pointSize ?? 0) >= 20 && (app.status.font?.pointSize ?? 0) >= 18 && (app.zoomControl.font?.pointSize ?? 0) >= 18, "Text stays at its readable sizes")
        try expect(app.widthControl.target === app && app.widthControl.action == #selector(AppDelegate.changeWidth(_:)) && app.widthControl.onBegin != nil && app.widthControl.onEnd != nil,
                   "The size slider keeps its undo-grouping callbacks")
        try expect(app.zoomControl.target === app && app.zoomControl.action == #selector(AppDelegate.changeZoom(_:)) && app.zoomControl.titleOfSelectedItem == "100%", "Zoom keeps its action and 100% default")
        try expect(app.dragFormatControl.target === app && app.dragFormatControl.numberOfItems == 12 && app.dragOriginalControl.target === app, "Drag format and original-size controls keep their actions")
        try expect(app.paletteButton.target === app && app.paletteButton.action == #selector(AppDelegate.showDrawingColors(_:)) && app.paletteButton.onHover != nil, "Color keeps its click and hover routes")
        try expect(app.colorWell.target === app && app.colorWell.action == #selector(AppDelegate.changeColor(_:)), "The hidden color well keeps its route")
        let drag = try (app.dragExportView).unwrap("Drag Me view")
        try expect(drag.prepare != nil && drag.onBegin != nil && drag.onLeaveControl != nil && drag.onEnd != nil && drag.onDeliveryFailure != nil, "Drag Me keeps every export callback")
        try expect(app.canvasBorder.onBegin != nil && app.canvasBorder.onDrag != nil && app.canvasBorder.onEnd != nil && app.navigator.onNavigate != nil, "Canvas border and navigator callbacks are wired")
        try expect(app.canvas.tool == .arrow && app.helpBevel != nil && app.canvas.onHintHover != nil, "Launch ends on the Arrow tool with the hint shell attached")
        try expect(app.sizeLabel.stringValue.hasPrefix("Size · ") && (app.paletteButton.image?.size.width ?? 0) > 0, "Drawing controls were synchronized after the chrome was built")
        app.canvas.strokeWidth = 9.38; app.syncDrawingControls()
        try expect(app.sizeLabel.stringValue == "Size · 9" && abs(app.widthControl.doubleValue - 9.38) < 0.001, "Size label shows a whole number while the stored value keeps its fraction")
    }

    @available(macOS 26, *)
    private static func modernControlStrings() throws {
        let classic = try classicBaseline()
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        let modern = controlFacts(app)
        try expect(classic.controls.count >= 40 && modern.count == classic.controls.count, "Both windows report the same set of facts (\(classic.controls.count) vs \(modern.count))")
        let differing = classic.controls.keys.sorted().filter { classic.controls[$0] != modern[$0] }
            .map { "\($0): classic '\(classic.controls[$0] ?? "")' vs modern '\(modern[$0] ?? "")'" }
        try expect(differing.isEmpty, "Modern strings differ from Classic: " + differing.joined(separator: "; "))
        try expect(modern["tool.arrow.label"] == "Arrow" && modern["tool.crop.tip"] == "Crop tool" && modern["share.label"] == "Share drawing"
                   && modern["toolbox.label"] == "Toolbox" && modern["drag.label"] == "Drag Me", "The strings are the recovered ones, not merely equal to each other")
        // At launch the rail Wipe reads its Blank stage; every other command reads its title, and Webpost… keeps its explicit label.
        let spoken = ["hide": "Hide", "photos": "Photos", "save": "Save", "history": "History", "snap": "Snap", "cancel": "Cancel", "font": "Font",
                      "undo": "Undo", "wipe": "Blank", "actual": "Actual Size", "resize": "Resize…", "share": "Share drawing"]
        let misread = spoken.keys.sorted().filter { modern["axLabel.\($0)"] != spoken[$0] }
            .map { "\($0): '\(modern["axLabel.\($0)"] ?? "")' instead of '\(spoken[$0] ?? "")'" }
        try expect(misread.isEmpty && spoken.count == commandActions.count, "VoiceOver reads the wrong command labels: " + misread.joined(separator: "; "))
        let hinted: [(String, NSView?)] = SketchTool.allCases.map { ("tool " + $0.rawValue, app.toolButtons[$0]) }
            + [("Wipe", collect(NSButton.self, in: app.window.contentView!).first { $0.action == #selector(AppDelegate.wipe) }), ("size slider", app.widthControl), ("Drag Me", app.dragExportView)]
        for (name, view) in hinted {
            try expect(view?.subviews.contains { $0 is HintTrackingView } == true, "\(name) registers contextual hint tracking")
        }
    }

    @available(macOS 26, *)
    private static func modernToolSelection() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        func verify(_ selected: SketchTool, _ label: String) throws {
            for tool in SketchTool.allCases {
                guard let button = app.toolButtons[tool] as? GlassChromeButton else { throw Failure(description: "\(label): \(tool) is not a glass button") }
                let surface = try surface(chrome, button), isOn = tool == selected
                try expect(button.state == (isOn ? .on : .off), "\(label): \(tool) state")
                try expect(surface.isSelected == isOn, "\(label): \(tool) surface selection")
                try expect((surface.currentTint != nil) == isOn, "\(label): only the selected tool is tinted (\(tool))")
                try expect(button.activeFamily == (isOn ? .solid : .regular), "\(label): \(tool) glyph family")
                try expect(button.toolTip?.contains("(selected)") == isOn, "\(label): \(tool) tooltip '\(button.toolTip ?? "")'")
                if isOn {
                    try expect(abs((surface.currentTint?.alphaComponent ?? 0) - 0.85) < 0.001, "\(label): \(tool) carries the accent tint")
                    try expect(sameColor(button.contentTintColor, ToolButton.textColor(on: .controlAccentColor)), "\(label): \(tool) glyph contrasts with the accent")
                    let expected: ChromeIconSource = FontAwesomeFont.isAvailable(.solid) ? .fontAwesome(.solid) : .sfSymbol(button.icon?.sfSymbolFallback ?? "")
                    try expect(button.iconSource == expected, "\(label): \(tool) icon source \(button.iconSource)")
                }
            }
            try expect(app.canvas.tool == selected, "\(label): the canvas tool")
        }
        try verify(.arrow, "launch")
        app.setTool(.brush)
        try verify(.brush, "setTool")
        app.canvas.tool = .ellipse
        try verify(.ellipse, "canvas tool change")
        guard let rectangle = app.toolButtons[.rectangle] as? GlassChromeButton else { throw Failure(description: "Rectangle button") }
        rectangle.performClick(nil)
        try verify(.rectangle, "click")
        rectangle.performClick(nil)
        try verify(.rectangle, "second click on the selected tool")
        app.setTool(.crop)
        try verify(.crop, "Crop")
    }

    @available(macOS 26, *)
    private static func modernFrameWindowShadowLevelAlpha() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        let alpha = CGFloat(Float32(bitPattern: 0x3f4ccccd))
        app.window.hasShadow = true; app.window.alphaValue = 0.9; app.window.level = .floating
        app.frameSnap()
        try expect(chrome.frameMode && !app.window.hasShadow && app.window.level == level && app.window.alphaValue == alpha,
                   "Modern Frame must drop the shadow, use the screen-saver level and alpha 0.8 while the glass chrome mirrors Frame")
        app.leaveFrame()
        try expect(!chrome.frameMode && app.window.hasShadow && app.window.level == .floating && app.window.alphaValue == 0.9,
                   "Leaving Modern Frame must restore the pre-Frame values and clear the chrome mirror")
        app.frameSnap(); app.cancelFrame()
        try expect(app.window.hasShadow && app.window.level == .floating && app.window.alphaValue == 0.9, "Cancel must restore them too")
    }

    @available(macOS 26, *)
    private static func modernFrameMode() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "Frame content view") }
        let fullscreen = #selector(AppDelegate.fullscreenSnap)
        let snap = chrome.snapButton, cancel = chrome.cancelFrameButton
        func state(_ label: String, frame: Bool) throws {
            try expect(app.frameMode == frame && chrome.frameMode == frame, "\(label): both layers agree on Frame mode")
            try expect(snap.title == (frame ? "Snap Frame" : "Snap") && snap.icon == (frame ? .frameViewfinder : .crosshairs), "\(label): Snap title and glyph '\(snap.title)'")
            try expect(snap.accessibilityLabel() == (frame ? "Snap Frame" : "Snap"), "\(label): VoiceOver reads '\(snap.accessibilityLabel() ?? "nil")' for Snap")
            try expect(cancel.accessibilityLabel() == "Cancel", "\(label): Cancel keeps its spoken label")
            try expect(snap.toolTip == (frame ? ModernEditorChrome.snapFrameToolTip : ModernEditorChrome.snapToolTip), "\(label): Snap tooltip")
            try expect(snap.alternateAction == (frame ? nil : fullscreen), "\(label): the Fullscreen alternate is \(frame ? "cleared" : "restored")")
            try expect(snap.alternateTarget === app, "\(label): the alternate target")
            try expect(snap.isPrimary && (try surface(chrome, snap)).prominence == .primary, "\(label): Snap stays the one primary command")
            try expect(cancel.isHidden == !frame && (try surface(chrome, cancel)).isHidden == !frame, "\(label): Cancel \(frame ? "shows" : "hides") with its glass")
            try expect(chrome.backdropIsVisible == !frame && content.showsCanvasHole == frame, "\(label): backdrop gives way to the Frame hole")
            app.updateViewportChrome()
            try expect(chrome.resizeButton.isEnabled == !frame && (try surface(chrome, chrome.resizeButton)).isDisabled == frame, "\(label): Resize is \(frame ? "dimmed" : "live")")
        }
        try state("launch", frame: false)
        app.frameSnap()
        try state("frameSnap", frame: true)
        app.leaveFrame()
        try state("leaveFrame", frame: false)
        app.frameSnap(); app.cancelFrame()
        try state("cancelFrame", frame: false)
        app.frameSnap(); app.resnap()
        try state("resnap", frame: true)
        app.newFile()
        try state("newFile", frame: false)
    }

    @available(macOS 26, *)
    private static func modernCanvasBleed() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let image = { chrome.subviews.compactMap { $0 as? NSBackgroundExtensionView }.first?.contentView as? NSImageView }
        app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
        app.dragExportView?.overview = nil
        chrome.updateCanvasBleed(nil)
        try expect(!chrome.bleedIsVisible, "No thumbnail, no bleed")
        app.updateDragPreview()
        guard let overview = app.dragExportView?.overview else { throw Failure(description: "updateDragPreview produced no thumbnail") }
        try expect(!GlassChrome.usesCanvasBleed && !chrome.bleedIsVisible && chrome.backdropIsVisible, "The bleed is hidden by default even with a thumbnail; the backdrop stays")
        GlassChrome.usesCanvasBleed = true
        defer { GlassChrome.usesCanvasBleed = false }
        app.updateDragPreview()
        try expect(chrome.bleedIsVisible && chrome.backdropIsVisible, "updateDragPreview shows the bleed over the backdrop when the flag is on")
        guard let overview = app.dragExportView?.overview else { throw Failure(description: "updateDragPreview produced no thumbnail") }
        try expect(image()?.image === overview, "The bleed shows the Drag Me thumbnail itself")
        try expect(max(overview.size.width, overview.size.height) <= 128, "The thumbnail is the 128 px preview")
        app.frameSnap()
        try expect(!chrome.bleedIsVisible && !chrome.backdropIsVisible, "Frame mode hides the bleed and backdrop")
        app.leaveFrame()
        try expect(chrome.bleedIsVisible && chrome.backdropIsVisible, "Leaving Frame mode brings them back")
        chrome.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        try expect(!chrome.bleedIsVisible, "Reduce Transparency hides the bleed")
        app.updateDragPreview()
        try expect(!chrome.bleedIsVisible, "A fresh thumbnail stays hidden under Reduce Transparency")
        chrome.accessibility = .none
        try expect(chrome.bleedIsVisible && image()?.image === app.dragExportView?.overview, "Clearing the option restores the current thumbnail")
    }

    /// Real mouse and key events into the CanvasBorderView that ModernEditorChrome hosts, compared with the same
    /// gesture driven through beginWindowGesture/previewBorderGesture/endWindowGesture (what Classic's tests call).
    @available(macOS 26, *)
    private static func modernBorderGestures() throws {
        enum Handle { case corner(CanvasCorner), edge(CanvasEdge) }
        struct Outcome { var data: Data; var geometry: [CGRect]; var background: Data?; var output: CGSize; var canvas: CGSize; var frame: CGRect; var undoName: String? }
        let corners: [CanvasCorner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let edges: [CanvasEdge] = [.left, .right, .top, .bottom]
        let handles: [Handle] = corners.map { .corner($0) } + edges.map { .edge($0) }

        func run(_ handle: Handle, viaMouse: Bool, cancel: Bool) throws -> (Outcome, before: Data, undoneClean: Bool, borderOK: Bool, begun: Bool) {
            let (fixture, chrome) = try modernFixture()
            let app = fixture.app
            try viewportFixture(app)
            let border = app.canvasBorder
            try expect(border.superview === chrome, "canvasBorder lives inside ModernEditorChrome")
            app.window.contentView?.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            let before = try app.canvas.snapshotDocumentData()
            let flags: NSEvent.ModifierFlags = { if case .edge = handle { return [.option] } else { return [] } }()
            let delta = CGPoint(x: 20, y: 12)
            var begun = true
            if viaMouse {
                let inset = CanvasBorderView.border / 2
                let local: CGPoint
                switch handle {
                case .corner(.topLeft): local = CGPoint(x: inset, y: inset)
                case .corner(.topRight): local = CGPoint(x: border.bounds.width - inset, y: inset)
                case .corner(.bottomLeft): local = CGPoint(x: inset, y: border.bounds.height - inset)
                case .corner(.bottomRight): local = CGPoint(x: border.bounds.width - inset, y: border.bounds.height - inset)
                case .edge(.left): local = CGPoint(x: inset, y: border.bounds.midY)
                case .edge(.right): local = CGPoint(x: border.bounds.width - inset, y: border.bounds.midY)
                case .edge(.top): local = CGPoint(x: border.bounds.midX, y: inset)
                case .edge(.bottom): local = CGPoint(x: border.bounds.midX, y: border.bounds.height - inset)
                }
                // The window moves and resizes mid-drag, so each event is built from a fixed screen point like a real mouse.
                let start = app.window.convertPoint(toScreen: border.convert(local, to: nil))
                func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                    guard let event = NSEvent.mouseEvent(with: type, location: app.window.convertPoint(fromScreen: point), modifierFlags: flags, timestamp: 0,
                        windowNumber: app.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                        throw Failure(description: "Internal border mouse event allocation")
                    }
                    return event
                }
                // Screen space is y-up; the gesture delta is right/down.
                let step1 = CGPoint(x: start.x + delta.x / 2, y: start.y - delta.y / 2)
                let end = CGPoint(x: start.x + delta.x, y: start.y - delta.y)
                border.mouseDown(with: try mouse(.leftMouseDown, start))
                begun = app.windowGesture != nil
                border.mouseDragged(with: try mouse(.leftMouseDragged, step1))
                border.mouseDragged(with: try mouse(.leftMouseDragged, end))
                if cancel {
                    try expect(app.canvas.editingUndoManager.canUndo == false, "Preview registers no Undo before the gesture ends")
                    guard let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: app.window.windowNumber, context: nil, characters: "\u{1b}",
                        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
                        throw Failure(description: "Internal Escape event allocation")
                    }
                    border.keyDown(with: esc)
                } else {
                    border.mouseUp(with: try mouse(.leftMouseUp, end))
                }
            } else {
                let h: CanvasBorderHandle = { switch handle { case .corner(let c): return .corner(c); case .edge(let e): return .edge(e) } }()
                begun = app.beginWindowGesture(h, flags: flags)
                app.previewBorderGesture(delta: CGPoint(x: delta.x / 2, y: delta.y / 2), flags: flags)
                app.previewBorderGesture(delta: delta, flags: flags)
                app.endWindowGesture(cancelled: cancel)
            }
            let content = try app.window.contentView.unwrap("content view")
            let expectedFrame = app.canvas.convert(app.canvas.bounds, to: content).insetBy(dx: -8, dy: -8)
            let borderOK = border.frame == expectedFrame && !expectedFrame.isEmpty
            let outcome = Outcome(data: try app.canvas.snapshotDocumentData(), geometry: app.canvas.document.elements.flatMap { [$0.rect, $0.bounds] },
                                  background: app.canvas.document.backgroundPNG, output: app.canvas.outputSize,
                                  canvas: app.canvas.canvasSize, frame: app.window.frame,
                                  undoName: app.canvas.editingUndoManager.undoActionName)
            var clean = true
            if !cancel {
                let after = outcome.data
                try expect(app.canvas.editingUndoManager.canUndo, "A committed border gesture registers an Undo")
                app.undo()
                clean = try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo
                app.redo()
                let redone = try app.canvas.snapshotDocumentData() == after; clean = clean && redone
            } else {
                clean = !app.canvas.editingUndoManager.canUndo && outcome.data == before
            }
            return (outcome, before, clean, borderOK, begun)
        }

        for handle in handles {
            let reference = try run(handle, viaMouse: false, cancel: false)
            let mouse = try run(handle, viaMouse: true, cancel: false)
            try expect(mouse.begun, "Mouse down on \(handle) begins a border gesture")
            try expect(reference.0.output != CGSize(width: 150, height: 90) || reference.0.canvas != CGSize(width: 300, height: 180),
                       "\(handle) reference gesture changes the canvas")
            try expect(mouse.0.output == reference.0.output && mouse.0.canvas == reference.0.canvas &&
                       mouse.0.geometry == reference.0.geometry && mouse.0.background == reference.0.background &&
                       mouse.0.undoName == reference.0.undoName,
                       "Mouse drag on \(handle) yields the Classic outputSize/crop result (\(mouse.0.output) vs \(reference.0.output))")
            try expect(mouse.undoneClean, "\(handle) mouse gesture is exactly one Undo and Redo restores it")
            try expect(mouse.borderOK, "canvasBorder.frame tracks the canvas after the \(handle) gesture")
            let escaped = try run(handle, viaMouse: true, cancel: true)
            try expect(escaped.begun && escaped.undoneClean && escaped.0.output == CGSize(width: 150, height: 90) &&
                       escaped.0.canvas == CGSize(width: 300, height: 180) && escaped.borderOK,
                       "Escape during a \(handle) drag restores the document, leaves no Undo and keeps the border on the canvas")
        }
        for corner in corners {
            let width: CGFloat = (corner == .topLeft || corner == .bottomLeft) ? 130 : 170
            let result = try run(.corner(corner), viaMouse: true, cancel: false)
            try expect(result.0.output == CGSize(width: width, height: (width * 0.6).rounded()),
                       "Mouse-dragged \(corner) corner matches the Classic width-driven numbers")
        }
    }

    @available(macOS 26, *)
    private static func modernAccessibilityInjection() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let surfaces = collect(GlassSurfaceView.self, in: app.window.contentView!)
        try expect(surfaces.count >= 28, "Header, rails and footer have their glass surfaces (\(surfaces.count))")
        let snap = try surface(chrome, chrome.snapButton), arrow = try surface(chrome, app.toolButtons[.arrow]), undo = try surface(chrome, chrome.undoButton)
        undo.setHovered(true)
        try expect(surfaces.allSatisfy { $0.accessibility == .none && $0.lastAnimationDuration == GlassSurfaceView.animationDuration }, "Surfaces start with no display options and animate")
        try expect(abs((undo.currentTint?.alphaComponent ?? 0) - 0.08) < 0.001 && abs((snap.currentTint?.alphaComponent ?? 0) - 0.85) < 0.001, "Baseline hover and primary tints")
        try expect(arrow.isSelected && !arrow.showsContrastRing, "Arrow is selected without a ring")
        let options = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true)
        chrome.accessibility = options
        try expect(surfaces.allSatisfy { $0.accessibility == options && $0.lastAnimationDuration == 0 }, "Every surface receives the injected options and stops animating")
        try expect(abs((undo.currentTint?.alphaComponent ?? 0) - 0.16) < 0.001 && abs((snap.currentTint?.alphaComponent ?? 0) - 1) < 0.001, "Increase Contrast strengthens hover and primary tints")
        try expect(arrow.showsContrastRing && arrow.layer?.borderWidth == 1, "Increase Contrast rings the selected tool")
        chrome.accessibility = .none
        try expect(surfaces.allSatisfy { $0.accessibility == .none && $0.lastAnimationDuration == GlassSurfaceView.animationDuration }, "Clearing the options restores every surface")
        try expect(abs((undo.currentTint?.alphaComponent ?? 0) - 0.08) < 0.001 && !arrow.showsContrastRing && arrow.layer?.borderWidth == 0, "And the tints and ring")
        undo.setHovered(false)
    }

    @available(macOS 26, *)
    private static func modernActionRouting() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let routes: [(String, GlassChromeButton, Selector)] = [
            ("Hide", chrome.hideButton, #selector(AppDelegate.vanish)), ("Photos", chrome.photosButton, #selector(AppDelegate.showPhotos)),
            ("Save", chrome.saveButton, #selector(AppDelegate.saveHistory)), ("History", chrome.historyButton, #selector(AppDelegate.showHistory)),
            ("Snap", chrome.snapButton, #selector(AppDelegate.snapButtonPressed)),
            ("Cancel", chrome.cancelFrameButton, #selector(AppDelegate.cancelFrame)), ("Font", chrome.fontButton, #selector(AppDelegate.chooseFont)),
            ("Undo", chrome.undoButton, #selector(AppDelegate.undo)), ("Wipe", chrome.wipeButton, #selector(AppDelegate.wipe)),
            ("Actual Size", chrome.actualButton, #selector(AppDelegate.toggleActualSize)), ("Resize…", chrome.resizeButton, #selector(AppDelegate.resize)),
            ("Webpost…", chrome.shareButton, #selector(AppDelegate.share(_:)))
        ]
        for (name, button, action) in routes {
            try expect(button.target === app && button.action == action, "\(name) sends its Classic action to the AppDelegate")
        }
        try expect(chrome.snapButton.menu == nil && chrome.snapButton.alternateTarget === app && chrome.snapButton.alternateAction == #selector(AppDelegate.fullscreenSnap),
                   "Snap keeps a primary crosshair with the Fullscreen secondary and no menu")
        // Screen capture only: no Cam/Camera button or selector exists in the Modern chrome.
        try expect(!app.responds(to: NSSelectorFromString("cameraSnap")) && !app.responds(to: NSSelectorFromString("runCameraSnap:")), "The AppDelegate has no camera action")
        let modernButtons = collect(NSButton.self, in: app.window.contentView!)
        try expect(!modernButtons.contains { $0.title.lowercased().contains("cam") || ($0.accessibilityLabel() ?? "").lowercased().contains("camera") },
                   "No Cam or Camera button exists in the Modern chrome")
        // The route reaches behavior, not only selectors.
        let before = app.canvas.document
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.canvas.document != before && app.validateMenuItem(NSMenuItem(title: "Undo", action: #selector(AppDelegate.undo), keyEquivalent: "z")), "A drawing edit is undoable")
        chrome.undoButton.performClick(nil)
        try expect(app.canvas.document == before, "The Modern Undo button undoes the edit")
        // Hidden/disabled state reaches the glass the way AppDelegate toggles it for the viewport.
        app.updateViewportChrome()
        try expect(chrome.actualButton.title == "Actual Size" && chrome.actualButton.isEnabled == app.canToggleActualSize, "Actual Size follows the viewport policy")
        chrome.resizeButton.isEnabled = false
        try expect(try surface(chrome, chrome.resizeButton).isDisabled, "A disabled command dims its glass")
        chrome.resizeButton.isEnabled = true
    }

    /// The Classic stage cases, driven through the glass button: what the title, the enabled state, the glass and VoiceOver each report.
    @available(macOS 26, *)
    private static func modernWipeStages() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, canvas = app.canvas
        let button = chrome.wipeButton
        guard app.wipeRailButton === button, button.action == #selector(AppDelegate.wipe), button.target === app else {
            throw Failure(description: "The rail Wipe button must be the chrome's, located by its action")
        }
        let glass = try surface(chrome, button)
        var sounds: [String] = []
        canvas.onSound = { sounds.append($0) }
        func reads(_ title: String, _ enabled: Bool) -> Bool {
            button.title == title && button.isEnabled == enabled && button.accessibilityLabel() == title
                && button.isAccessibilityEnabled() == enabled
                && glass.isDisabled == !enabled && glass.alphaValue == (enabled ? 1 : 0.5) && glass.currentTint == nil
        }
        func detail() -> String {
            "title '\(button.title)', enabled \(button.isEnabled), VoiceOver '\(button.accessibilityLabel() ?? "nil")' enabled \(button.isAccessibilityEnabled()), "
                + "glass disabled \(glass.isDisabled), alpha \(glass.alphaValue), tint \(String(describing: glass.currentTint))"
        }
        let shape = SketchElement(kind: .rectangle)
        let untouched = canvas.editingUndoManager.undoActionName
        try expect(reads("Blank", false), "A fresh drawing reads a dimmed, disabled Blank: " + detail())
        button.performClick(nil)
        try expect(sounds.isEmpty && reads("Blank", false) && canvas.editingUndoManager.undoActionName == untouched, "A disabled Blank button ignores presses")
        app.wipe()
        try expect(sounds == ["wipe_already_blank"] && reads("Blank", false) && canvas.editingUndoManager.undoActionName == untouched,
                   "The Wipe menu command on a blank drawing is sound-only")
        sounds.removeAll()

        canvas.setBackground(try image(size: CGSize(width: 120, height: 80)))
        try expect(reads("Clear", true) && canvas.document.backgroundPNG != nil, "A snap image alone reads a live Clear: " + detail())
        canvas.document.elements = [shape]
        try expect(reads("Wipe", true), "Artwork over a snap reads a live Wipe: " + detail())
        button.performClick(nil)
        try expect(sounds == ["wipe_brushlayer"] && canvas.document.elements.isEmpty && canvas.document.backgroundPNG != nil && reads("Clear", true),
                   "Wipe removes only the artwork and the glass reads Clear: " + detail())
        button.performClick(nil)
        try expect(sounds == ["wipe_brushlayer", "wipe_snap"] && canvas.document.backgroundPNG == nil && canvas.document.backgroundColor == .white && reads("Blank", false),
                   "Clear removes the snap and the glass dims to Blank: " + detail())
        button.performClick(nil)
        try expect(sounds.count == 2, "The disabled Blank button stays silent after the last stage")

        sounds.removeAll()
        canvas.document.elements = [shape]
        try expect(reads("Wipe", true), "Artwork over a white drawing without a snap reads Wipe: " + detail())
        button.performClick(nil)
        try expect(sounds == ["wipe_brushlayer"] && canvas.document.elements.isEmpty && reads("Blank", false), "Wiping artwork with no snap lands on a dimmed Blank: " + detail())

        sounds.removeAll()
        canvas.setBackgroundColor(.red)
        try expect(reads("Clear", true), "A coloured backdrop alone reads Clear: " + detail())
        app.undo(); try expect(reads("Blank", false), "Undo returns the glass to the dimmed Blank: " + detail())
        app.redo(); try expect(reads("Clear", true), "Redo brings the live Clear back: " + detail())
        _ = try editor(app, text: "Typing")
        try expect(reads("Wipe", true), "Field editing over a coloured backdrop reads Wipe: " + detail())
        button.performClick(nil)
        try expect(sounds == ["wipe_brushlayer"] && canvas.document.elements.isEmpty && canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty && reads("Clear", true),
                   "Wipe commits and removes the field and leaves the coloured backdrop as Clear: " + detail())
    }

    @available(macOS 26, *)
    private static func modernPreferencesAppearance() throws {
        let defaults = UserDefaults.standard, key = AppearanceResolver.defaultsKey
        let previous = defaults.object(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: key)
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        try expect(AppearanceResolver(defaults: defaults).storedChoice == nil, "The run starts with no stored choice")
        app.showPreferences()
        guard let form = app.preferencesForm else { throw Failure(description: "Preferences form") }
        guard let classic = descendant(form, identifier: "appearanceClassic") as? NSButton, let modern = descendant(form, identifier: "appearanceModern") as? NSButton,
              let relaunch = descendant(form, identifier: "appearanceRelaunch") as? NSButton else { throw Failure(description: "The Appearance row is missing on a macOS 26 host") }
        try expect(form.onRelaunch != nil, "Preferences routes its Relaunch button to the AppDelegate")
        classic.performClick(nil)
        try expect(defaults.string(forKey: key) == "classic" && AppearanceResolver(defaults: defaults).storedChoice == .classic, "Choosing Classic stores the choice under \(key)")
        try expect(app.generalPreferences.state.appearance == .classic, "The Preferences model reads it back")
        try expect(Appearance.isModern && app.modernChrome === chrome && app.window.contentView?.subviews.contains(chrome) == true, "The running window keeps its Modern chrome until relaunch")
        modern.performClick(nil)
        try expect(defaults.string(forKey: key) == "modern" && app.generalPreferences.state.appearance == .modern, "Choosing Modern stores it again")
        try expect(AppSafetyTermination.requests == 0, "Choosing an appearance never quits")
        relaunch.performClick(nil)
        try expect(AppSafetyTermination.requests == 1 && app.pendingRelaunch != nil, "The Relaunch button asks to quit once")
        app.pendingRelaunch = nil
        defaults.removeObject(forKey: key)
        if let previous { defaults.set(previous, forKey: key) }
        try expect(defaults.object(forKey: key) as? String == previous as? String, "The test restored the key it changed")
    }

    @available(macOS 26, *)
    private static func modernRelaunch() throws {
        let (fixture, _) = try modernFixture()
        try relaunchQuitSequence(fixture)
    }

    @available(macOS 26, *)
    private static func modernRelaunchLauncher() throws {
        try relaunchLauncherAcknowledgement()

        // The wiring OpenSkitchMain installs, driven from the Modern window: the real Preferences button, the quit, then the launcher.
        let (fixture, _) = try modernFixture()
        let app = fixture.app, seen = LaunchLog()
        app.relaunchRequest = { url in
            _ = RelaunchLauncher.launch(url, environment: ["SKITCH_APPEARANCE": "modern", "SKITCH_FIXTURE": "/fixture.skitch", "SKITCH_APP_SUPPORT": "/isolated",
                                                           "SKITCH_EVIDENCE_DIR": "/evidence", "PATH": "/bin"], timeout: 2) { opened, configuration, completion in
                seen.url = opened; seen.configuration = configuration
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { seen.answered = true; completion(nil, nil) }
            }
        }
        app.showPreferences()
        guard let form = app.preferencesForm, let button = descendant(form, identifier: "appearanceRelaunch") as? NSButton else { throw Failure(description: "Preferences has no Relaunch button") }
        button.performClick(nil)
        try expect(AppSafetyTermination.requests == 1 && seen.url == nil, "The Relaunch button asks to quit and starts nothing yet")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(seen.answered && seen.url == Bundle.main.bundleURL, "The launcher held the quit until LaunchServices had the request for this bundle")
        try expect(seen.configuration?.createsNewApplicationInstance == true
                   && seen.configuration?.environment == ["SKITCH_APP_SUPPORT": "/isolated", "SKITCH_EVIDENCE_DIR": "/evidence"],
                   "The new instance is a separate process that keeps the support and evidence folders and drops the pinned appearance and fixture: \(String(describing: seen.configuration?.environment))")
    }

    @available(macOS 26, *)
    private static func modernLayoutEvidence() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        app.writeLayoutEvidence()
        let folder = ProcessInfo.processInfo.environment["SKITCH_EVIDENCE_DIR"] ?? app.support.path
        let data = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("layout.json"))
        guard let evidence = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(description: "layout.json is not an object") }
        let appearance = evidence["appearance"] as? [String: Any]
        try expect(appearance?["style"] as? String == "modern" && appearance?["modernChrome"] as? Bool == true, "appearance.style reports modern with its chrome: \(String(describing: appearance))")
        try expect((evidence["bezelLayout"] as? [String: Any])?["recoveredArtwork"] as? Bool == false, "Modern reports no recovered bezel artwork")
        guard let header = evidence["bezelHeader"] as? [String: Any] else { throw Failure(description: "Header evidence is missing in Modern") }
        try expect(abs(header["brandCenterOffset"] as? Double ?? 99) <= 1, "The brand is centered on the window: \(String(describing: header["brandCenterOffset"]))")
        try expect((header["commandFrames"] as? [String])?.count == 2, "The two header command groups are reported")
        let tools = evidence["toolButtons"] as? [[String: Any]] ?? []
        try expect(tools.count == 10 && tools.allSatisfy { ($0["fontSize"] as? Double ?? 0) >= 18 }, "Ten tool buttons report readable fonts")
        try expect(tools.filter { $0["selected"] as? Bool == true }.compactMap { $0["tool"] as? String } == ["arrow"], "Exactly the Arrow tool reports selected")
        let controls = evidence["bezelControls"] as? [[String: Any]] ?? []
        try expect(controls.count >= 24, "The Modern controls are inspected (\(controls.count))")
        // AppKit hosts each button's title in a private text field that reports its own 13 pt default
        // while drawing at the button's font; only a control whose parent is a button gets that exemption.
        let rects = controls.map { NSRectFromString($0["frame"] as? String ?? "") }
        for (index, entry) in controls.enumerated() where entry["hidden"] as? Bool != true {
            let label = entry["label"] as? String ?? "?"
            let frame = rects[index], visible = NSRectFromString(entry["visibleFrame"] as? String ?? "")
            let isButtonInternal = entry["parentIsButton"] as? Bool == true
            if !isButtonInternal { try expect((entry["fontSize"] as? Double ?? 0) >= 18, "\(label) is at least 18 pt: \(entry)") }
            try expect(!frame.isEmpty && abs(frame.width - visible.width) < 0.5 && abs(frame.height - visible.height) < 0.5, "\(label) is not clipped (\(frame) vs \(visible))")
        }
        try expect(chrome.header.subviews.contains { $0.identifier?.rawValue == "OpenSkitchBrand" }, "The brand is the header's direct child")
        try expect(app.window.contentView?.subviews.contains { $0.identifier?.rawValue == "OpenSkitchHeader" } == false, "The header is one level deeper than Classic, which the evidence accommodates")
    }

    @available(macOS 26, *)
    private static func modernMenus() throws {
        let classic = try classicBaseline()
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        guard let bar = NSApp.mainMenu else { throw Failure(description: "Main menu") }
        var items: [NSMenuItem] = []
        func walk(_ menu: NSMenu) { for item in menu.items { items.append(item); if let sub = item.submenu { walk(sub) } } }
        walk(bar)
        try expect(classic.menuImageCount == 0, "Classic menus carry no symbols")
        let mapped = items.filter { !$0.isSeparatorItem && $0.action.map { MenuSymbols.map[$0] != nil } == true }
        try expect(mapped.count >= 40, "The main menu holds the mapped commands (\(mapped.count))")
        let missing = mapped.filter { $0.image == nil }.map(\.title)
        try expect(missing.isEmpty, "Modern menu items without a symbol: \(missing)")
        try expect(mapped.allSatisfy { $0.image?.isTemplate == true }, "Menu symbols are template images")
        try expect(items.filter(\.isSeparatorItem).allSatisfy { $0.image == nil }, "Separators stay bare")
        guard let preferences = items.first(where: { $0.action == #selector(AppDelegate.showPreferences) }),
              let cancel = items.first(where: { $0.action == #selector(AppDelegate.cancelSnapshot) }),
              let undo = items.first(where: { $0.action == #selector(AppDelegate.undo) }) else { throw Failure(description: "Expected menu items") }
        try expect(app.validateMenuItem(preferences) && !app.validateMenuItem(cancel) && !app.validateMenuItem(undo), "Symbols do not change which commands are available")
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.validateMenuItem(undo), "Undo becomes available after an edit")
        let toolbox = collect(NSPopUpButton.self, in: app.window.contentView!).first { $0.accessibilityLabel() == "Toolbox" }
        try expect(toolbox?.menu?.items.contains { $0.title == "More Commands" } == true, "The Toolbox menu keeps its More Commands entry")
    }

    @available(macOS 26, *)
    private static func modernPalettePopover() throws {
        let classic = try classicBaseline()
        try expect(classic.popoverAppearance == .aqua, "Classic forces aqua on the color popover")
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        window.simulatesVisibility = true; window.shown = true
        app.showDrawingColors(chrome.surface(for: app.paletteButton)?.contentView as? NSButton ?? app.paletteButton)
        try expect(app.colorPopover?.isShown == true, "The Modern Color popover opens")
        try expect(app.colorPopover?.appearance == nil && app.colorPopover?.contentViewController?.view.appearance == nil, "Modern leaves the popover on the system appearance")
        try expect(app.presetColorButtons.count == OriginalDrawingControls.presets.count, "The presets are all there")
        app.closeDrawingColors()
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing " + what) }
        return self
    }
}
#endif
