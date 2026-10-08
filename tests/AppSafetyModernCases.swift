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
            ("Frame enter and leave swap Snap, Cancel and Cam, clear and restore the Fullscreen alternate, and dim Resize", modernFrameMode),
            ("updateDragPreview feeds the canvas bleed, and Frame mode and Reduce Transparency hide it", modernCanvasBleed),
            ("Injected display options reach every glass surface and clear again", modernAccessibilityInjection),
            ("Header and footer buttons reach the real AppDelegate actions", modernActionRouting),
            ("Preferences Appearance row writes the stored choice without switching the running window", modernPreferencesAppearance),
            ("relaunch() requests termination once and launches only after quit, never from a cancelled Save", modernRelaunch),
            ("The relaunch launcher waits, bounded, for LaunchServices to accept the request before the old instance exits", modernRelaunchLauncher),
            ("writeLayoutEvidence reports the Modern style and finds the header and brand one level deeper", modernLayoutEvidence),
            ("Main menu items carry symbols in Modern only and keep validating", modernMenus),
            ("Color popover follows the system appearance in Modern and stays aqua in Classic", modernPalettePopover)
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
        try expect(app.snapButton === chrome.snapButton && app.cameraButton === chrome.cameraButton && app.cancelFrameButton === chrome.cancelFrameButton
                   && app.actualButton === chrome.actualButton && app.resizeButton === chrome.resizeButton, "AppDelegate controls Snap, Cam, Cancel, Actual Size and Resize through the chrome's buttons")
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
    private static func modernFrameMode() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "Frame content view") }
        let fullscreen = #selector(AppDelegate.fullscreenSnap)
        let snap = chrome.snapButton, cancel = chrome.cancelFrameButton, camera = chrome.cameraButton
        func state(_ label: String, frame: Bool) throws {
            try expect(app.frameMode == frame && chrome.frameMode == frame, "\(label): both layers agree on Frame mode")
            try expect(snap.title == (frame ? "Snap Frame" : "Snap") && snap.icon == (frame ? .cameraViewfinder : .crosshairs), "\(label): Snap title and glyph '\(snap.title)'")
            try expect(snap.toolTip == (frame ? ModernEditorChrome.snapFrameToolTip : ModernEditorChrome.snapToolTip), "\(label): Snap tooltip")
            try expect(snap.alternateAction == (frame ? nil : fullscreen), "\(label): the Fullscreen alternate is \(frame ? "cleared" : "restored")")
            try expect(snap.alternateTarget === app, "\(label): the alternate target")
            try expect(snap.isPrimary && (try surface(chrome, snap)).prominence == .primary, "\(label): Snap stays the one primary command")
            try expect(cancel.isHidden == !frame && (try surface(chrome, cancel)).isHidden == !frame, "\(label): Cancel \(frame ? "shows" : "hides") with its glass")
            try expect(camera.isHidden == frame && (try surface(chrome, camera)).isHidden == frame, "\(label): Cam \(frame ? "hides" : "shows") with its glass")
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
        try expect(chrome.bleedIsVisible && chrome.backdropIsVisible, "updateDragPreview shows the bleed over the backdrop")
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

    @available(macOS 26, *)
    private static func modernAccessibilityInjection() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let surfaces = collect(GlassSurfaceView.self, in: app.window.contentView!)
        try expect(surfaces.count >= 29, "Header, rails and footer have their glass surfaces (\(surfaces.count))")
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
            ("Snap", chrome.snapButton, #selector(AppDelegate.snapButtonPressed)), ("Cam", chrome.cameraButton, #selector(AppDelegate.cameraSnap)),
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
        let app = fixture.app
        try expect(app.relaunchRequest == nil, "Only the production entry point installs a launcher")
        var launched: [URL] = []
        app.relaunchRequest = { launched.append($0) }

        app.dirty = true
        AppSafetyAlert.answers.append(.init(title: "Save your drawing?", response: .alertSecondButtonReturn))
        app.relaunch()
        try expect(AppSafetyTermination.requests == 0 && app.pendingRelaunch == nil && launched.isEmpty, "Cancelling the Save prompt neither quits nor schedules a launch")

        // A quit AppKit itself cancels after Relaunch was requested must not leave a launch waiting for the next ordinary Quit.
        app.pendingRelaunch = Bundle.main.bundleURL
        AppSafetyAlert.answers.append(.init(title: "Save your drawing?", response: .alertSecondButtonReturn))
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "The cancelled quit is reported to AppKit")
        try expect(app.pendingRelaunch == nil && launched.isEmpty, "A cancelled quit drops the pending relaunch")
        app.dirty = false

        app.relaunch()
        try expect(AppSafetyTermination.requests == 1, "relaunch() requests termination exactly once (\(AppSafetyTermination.requests))")
        try expect(launched.isEmpty && app.pendingRelaunch == Bundle.main.bundleURL, "Nothing launches while the old instance is still holding its shortcuts")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(launched == [Bundle.main.bundleURL] && app.pendingRelaunch == nil, "The fresh instance starts once, after the old one has finished quitting")
        try expect(AppSafetyTermination.requests == 1, "No second termination request")

        // A quit that fails to finish cleanup must not relaunch later.
        let failure = NSError(domain: "AppSafety", code: 7, userInfo: [NSLocalizedDescriptionKey: "Modern relaunch cleanup failed"])
        app.pendingRelaunch = Bundle.main.bundleURL
        app.shutdownError = failure
        AppSafetyAlert.answers.append(.init(title: failure.localizedDescription, response: .alertFirstButtonReturn))
        try expect(!app.finishShutdownDecision() && app.pendingRelaunch == nil, "A failed shutdown cancels the pending relaunch")
        try waitForMain("The failure alert is presented") { AppSafetyAlert.answers.isEmpty }
        try expect(launched.count == 1, "Still exactly one launch")
    }

    /// What a stub LaunchServices saw, shared with the queue that answers it.
    private final class LaunchLog: @unchecked Sendable {
        var url: URL?
        var configuration: NSWorkspace.OpenConfiguration?
        var answered = false
    }

    /// The old instance exits right after the launcher returns, so the launcher must not return before LaunchServices has the request.
    @available(macOS 26, *)
    private static func modernRelaunchLauncher() throws {
        let target = URL(fileURLWithPath: "/Applications/OpenSkitch.app")
        func launch(after delay: TimeInterval, on queue: DispatchQueue?, error: Error? = nil, timeout: TimeInterval = 5,
                    environment: [String: String] = [:]) -> (accepted: Bool, elapsed: TimeInterval, log: LaunchLog) {
            let log = LaunchLog(), started = Date()
            let accepted = RelaunchLauncher.launch(target, environment: environment, timeout: timeout) { url, configuration, completion in
                log.url = url; log.configuration = configuration
                queue?.asyncAfter(deadline: .now() + delay) { log.answered = true; completion(nil, error) }
            }
            return (accepted, Date().timeIntervalSince(started), log)
        }

        let background = launch(after: 0.3, on: .global())
        try expect(background.accepted && background.log.answered, "The launcher returns true only after LaunchServices answered")
        try expect(background.elapsed >= 0.29 && background.elapsed < 2, "It waited for the answer instead of returning at once (\(background.elapsed) s)")
        try expect(background.log.url == target && background.log.configuration?.createsNewApplicationInstance == true, "It asks for a new instance of the same bundle")

        let main = launch(after: 0.2, on: .main)
        try expect(main.accepted && main.log.answered && main.elapsed >= 0.19 && main.elapsed < 2, "An answer delivered on the main queue is not starved by the wait (\(main.elapsed) s)")

        let refused = launch(after: 0.05, on: .global(), error: NSError(domain: "AppSafety", code: 9))
        try expect(!refused.accepted && refused.log.answered && refused.elapsed < 2, "A refused launch reports failure promptly")

        let silent = launch(after: 0, on: nil, timeout: 0.3)
        try expect(!silent.accepted && !silent.log.answered, "A launch nobody answers is reported as not accepted")
        try expect(silent.elapsed >= 0.29 && silent.elapsed < 2, "The wait is bounded by its timeout (\(silent.elapsed) s)")

        let inherited = launch(after: 0, on: .global(), environment: ["SKITCH_APP_SUPPORT": "/isolated", "SKITCH_APPEARANCE": "modern", "HOME": "/home", "PATH": "/bin"])
        try expect(inherited.log.configuration?.environment == ["SKITCH_APP_SUPPORT": "/isolated", "SKITCH_APPEARANCE": "modern"],
                   "Only SKITCH_ overrides reach the new instance: \(String(describing: inherited.log.configuration?.environment))")
        try expect(launch(after: 0, on: .global()).log.configuration?.environment == [:], "Without overrides the new instance inherits nothing")

        // The wiring OpenSkitchMain installs, driven from the Modern window: the real Preferences button, the quit, then the launcher.
        let (fixture, _) = try modernFixture()
        let app = fixture.app, seen = LaunchLog()
        app.relaunchRequest = { url in
            _ = RelaunchLauncher.launch(url, environment: ["SKITCH_APPEARANCE": "modern", "SKITCH_APP_SUPPORT": "/isolated", "PATH": "/bin"], timeout: 2) { opened, configuration, completion in
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
                   && seen.configuration?.environment == ["SKITCH_APPEARANCE": "modern", "SKITCH_APP_SUPPORT": "/isolated"],
                   "The new instance is a separate process that keeps the pinned appearance and support folder: \(String(describing: seen.configuration?.environment))")
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
        // while drawing at the button's font; those sit wholly inside their button's rectangle.
        let rects = controls.map { NSRectFromString($0["frame"] as? String ?? "") }
        for (index, entry) in controls.enumerated() where entry["hidden"] as? Bool != true {
            let label = entry["label"] as? String ?? "?"
            let frame = rects[index], visible = NSRectFromString(entry["visibleFrame"] as? String ?? "")
            let isButtonInternal = rects.enumerated().contains { $0.offset != index && $0.element != frame && $0.element.contains(frame) }
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
