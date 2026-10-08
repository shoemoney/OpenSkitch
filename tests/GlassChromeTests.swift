// Offscreen controls, glass views and a never-ordered window only; no desktop windows and no input.
// Set OPENSKITCH_FA_FONT_DIR (or keep build/fonts) to also run the layout with the Font Awesome glyph branch.
// xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete -target arm64-apple-macosx13.0 -D GLASS_CHROME_TESTS \
//   Sources/Appearance.swift Sources/OriginalActionButton.swift Sources/ToolButton.swift Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift \
//   Sources/BezelDrawingControls.swift Sources/LegacySkitch.swift Sources/DocumentModel.swift Sources/GlassChrome.swift Sources/ModernEditorChrome.swift \
//   tests/GlassChromeTests.swift -o build/glass-chrome-tests
// build/glass-chrome-tests
#if GLASS_CHROME_TESTS
import AppKit

@MainActor
private final class ActionTarget: NSObject {
    var hits: [String] = []
    @objc func hide(_ sender: Any?) { hits.append("hide") }
    @objc func photos(_ sender: Any?) { hits.append("photos") }
    @objc func saveHistory(_ sender: Any?) { hits.append("saveHistory") }
    @objc func showHistory(_ sender: Any?) { hits.append("showHistory") }
    @objc func chooseTool(_ sender: Any?) { hits.append("tool:" + ((sender as? NSControl)?.identifier?.rawValue ?? "?")) }
    @objc func snap(_ sender: Any?) { hits.append("snap") }
    @objc func camera(_ sender: Any?) { hits.append("camera") }
    @objc func cancelFrame(_ sender: Any?) { hits.append("cancelFrame") }
    @objc func font(_ sender: Any?) { hits.append("font") }
    @objc func undo(_ sender: Any?) { hits.append("undo") }
    @objc func wipe(_ sender: Any?) { hits.append("wipe") }
    @objc func actualSize(_ sender: Any?) { hits.append("actualSize") }
    @objc func resize(_ sender: Any?) { hits.append("resize") }
    @objc func share(_ sender: Any?) { hits.append("share") }
    @objc func alternate(_ sender: Any?) { hits.append("alternate") }
}

@MainActor
private final class SwatchView: NSView {
    let color: NSColor
    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

@MainActor
private final class AccessibilityBox {
    var value = ChromeAccessibility.none
}

@MainActor
private final class NonorderingWindow: NSWindow {
    override func orderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
    override func orderFrontRegardless() { preconditionFailure("No desktop windows") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
}

@main
@MainActor
private enum GlassChromeTests {
    private static var checks = 0, notes: [String] = []
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]
    private static let snapToolTip = "Drag an area or click a window; right-click or Control-click for Fullscreen"
    private static let snapFrameToolTip = "Capture the area inside the frame; hold Shift for a six-second timer"
    private static let plain = ChromeAccessibility.none
    private static let contrast = ChromeAccessibility(reduceTransparency: false, increaseContrast: true, reduceMotion: false)
    private static let calm = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: true)

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        FontAwesomeFont.resetForTesting()
        buttonTests()
        sliderTests()
        if #available(macOS 26, *) {
            surfaceTests()
            let fonts = fontDirectory()
            chromeTests(glyphs: false)
            if let fonts {
                for family in FAFamily.allCases {
                    expect(FontAwesomeFont.register(url: fonts.appendingPathComponent(family.resourceName + ".ttf"), family: family), "Subset font \(family) registers")
                }
                buttonGlyphTests()
                chromeTests(glyphs: true)
                FontAwesomeFont.resetForTesting()
            } else {
                notes.append("glyph branch (no OPENSKITCH_FA_FONT_DIR or build/fonts)")
            }
        } else {
            print("SKIP glass surface and chrome checks: macOS < 26")
        }
        let note = notes.isEmpty ? "" : "; SKIPPED: " + notes.joined(separator: ", ")
        print("GlassChromeTests: \(checks) checks passed (offscreen; no desktop input)\(note)")
    }

    // MARK: helpers

    private static func fontDirectory() -> URL? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["OPENSKITCH_FA_FONT_DIR"], !path.isEmpty {
            candidates.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        var parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(parent.appendingPathComponent("build/fonts", isDirectory: true))
            parent = parent.deletingLastPathComponent()
        }
        return candidates.first { directory in
            FAFamily.allCases.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.resourceName + ".ttf").path) }
        }
    }

    private static func rgb(_ color: NSColor?) -> [CGFloat]? {
        guard let converted = color?.usingColorSpace(.deviceRGB) else { return nil }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent]
    }

    private static func sameColor(_ a: NSColor?, _ b: NSColor?, tolerance: CGFloat = 0.01) -> Bool {
        guard let x = rgb(a), let y = rgb(b) else { return a == nil && b == nil }
        return zip(x, y).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private static func window(_ size: NSSize) -> (NonorderingWindow, NSView) {
        let window = NonorderingWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = content
        return (window, content)
    }

    private static func event(_ type: NSEvent.EventType, in window: NSWindow, at point: NSPoint = NSPoint(x: 5, y: 5), flags: NSEvent.ModifierFlags = [], number: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
    }

    // MARK: GlassChromeButton (available on every supported macOS)

    private static func buttonTests() {
        // Font floor: the title initializer assigns a small system font after init(frame:).
        let titled = GlassChromeButton(title: "Wipe", target: nil, action: nil)
        expect((titled.font?.pointSize ?? 0) >= 18, "Title initializer never leaves a font under 18 pt")
        expect((GlassChromeButton(frame: .zero).font?.pointSize ?? 0) == 20, "Default label size is 20 pt")
        titled.font = .systemFont(ofSize: 9)
        expect(titled.font?.pointSize == 18, "Assigning a small font floors at 18 pt")
        titled.font = nil
        expect(titled.font?.pointSize == 20, "Clearing the font restores 20 pt")
        titled.font = .systemFont(ofSize: 24)
        expect(titled.font?.pointSize == 24, "Larger fonts are kept")
        expect(!titled.isBordered && titled.focusRingType == .exterior, "The glass is the bezel; the focus ring stays AppKit's exterior ring")
        expect(titled.alignmentRectInsets.top == 0 && titled.alignmentRectInsets.left == 0 && titled.alignmentRectInsets.bottom == 0 && titled.alignmentRectInsets.right == 0,
               "No alignment insets, so the frame equals what the surface constrains")

        // Icon family follows the state; Actual Size swaps the glyph as well.
        let tool = GlassChromeButton(title: "", target: nil, action: nil)
        tool.setButtonType(.toggle)
        tool.icon = .paintbrush
        expect(tool.activeFamily == .regular && tool.iconFamily == .regular && tool.selectedFamily == .solid, "Regular off, solid selected by default")
        expect(tool.image != nil && tool.imagePosition == .imageOnly, "Icon-only tool shows an image only")
        let offImage = tool.image
        tool.state = .on
        expect(tool.activeFamily == .solid, "Selecting switches to the selected family")
        expect(tool.image !== offImage, "Selecting re-renders the glyph")
        tool.state = .off
        expect(tool.activeFamily == .regular, "Deselecting restores the regular family")
        tool.selectedFamily = .regular
        tool.state = .on
        expect(tool.activeFamily == .regular, "selectedFamily is honored")
        tool.state = .off
        tool.selectedFamily = .solid

        let actual = GlassChromeButton(title: "Actual Size", target: nil, action: nil)
        actual.setButtonType(.toggle)
        actual.icon = .maximize
        actual.selectedIcon = .minimize
        expect(actual.imagePosition == .imageLeading, "Icon beside a label leads it")
        if case .sfSymbol(let name) = actual.iconSource { expect(name == FAIcon.maximize.sfSymbolFallback, "Off shows maximize") }
        actual.state = .on
        if case .sfSymbol(let name) = actual.iconSource { expect(name == FAIcon.minimize.sfSymbolFallback, "On shows minimize") }
        expect(actual.activeFamily == .solid, "Actual Size on is the solid family")
        let blank = GlassChromeButton(title: "Cam", target: nil, action: nil)
        expect(blank.iconSource == .none && blank.image == nil && blank.imagePosition == .noImage, "Without an icon the title stands alone")

        // contentTintColor per state.
        let accentContrast = ToolButton.textColor(on: .controlAccentColor)
        let tinted = GlassChromeButton(title: "Snap", target: nil, action: nil)
        tinted.setButtonType(.toggle)
        tinted.icon = .crosshairs
        expect(sameColor(tinted.contentTintColor, .labelColor), "Normal content uses the label color")
        tinted.state = .on
        expect(sameColor(tinted.contentTintColor, accentContrast), "Selected content contrasts with the accent")
        tinted.selectionTints = false
        expect(sameColor(tinted.contentTintColor, .labelColor), "A glyph-only toggle keeps the label color when on")
        tinted.selectionTints = true
        tinted.state = .off
        tinted.isPrimary = true
        expect(sameColor(tinted.contentTintColor, accentContrast), "Primary content contrasts with the accent")
        tinted.isEnabled = false
        expect(sameColor(tinted.contentTintColor, .disabledControlTextColor), "Disabled content uses the disabled color")
        tinted.isEnabled = true
        tinted.isPrimary = false
        expect(sameColor(tinted.contentTintColor, .labelColor), "Re-enabling restores the label color")

        // Notifications.
        let watched = GlassChromeButton(title: "Wipe", target: nil, action: nil)
        var snapshots: [(pressing: Bool, enabled: Bool, on: Bool, hidden: Bool)] = []
        watched.onInteractionChange = { button in snapshots.append((button.isPressing, button.isEnabled, button.state == .on, button.isHidden)) }
        watched.highlight(true)
        expect(snapshots.count == 1 && snapshots[0].pressing, "highlight(true) notifies a press")
        watched.highlight(false)
        expect(snapshots.count == 2 && !snapshots[1].pressing && !watched.isPressing, "highlight(false) notifies the release")
        watched.state = .on
        expect(snapshots.count == 3 && snapshots[2].on, "State changes notify")
        watched.isEnabled = false
        expect(snapshots.count == 4 && !snapshots[3].enabled, "Disabling notifies")
        watched.isHidden = true
        expect(snapshots.count == 5 && snapshots[4].hidden, "Hiding notifies")
        watched.isHidden = false
        watched.isEnabled = true
        expect(snapshots.count == 7, "Showing and enabling notify")

        // Focus ring mask follows the host shape and vanishes while disabled.
        let ring = GlassChromeButton(title: "", target: nil, action: nil)
        ring.frame = NSRect(x: 0, y: 0, width: 148, height: 40)
        expect(!ring.focusRingMaskBounds.isEmpty, "Enabled button has focus-ring bounds")
        func mask(_ shape: GlassShape) -> NSBitmapImageRep {
            ring.focusShape = shape
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 148, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.cgContext.clear(ring.bounds)
            ring.drawFocusRingMask()
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        let capsule = mask(.capsule), rounded = mask(.rounded(6))
        expect(alpha(capsule, 74, 20) > 0.9, "Mask covers the center")
        expect(alpha(capsule, 3, 3) < 0.1, "A capsule mask leaves the corner clear")
        expect(alpha(rounded, 3, 3) > 0.5, "A small radius fills the corner a capsule leaves clear")
        ring.isEnabled = false
        expect(ring.focusRingMaskBounds.isEmpty, "Disabled button has no focus ring")
        expect(alpha(mask(.capsule), 74, 20) == 0, "Disabled button draws no focus mask")
        ring.isEnabled = true

        // Primary clicks are bracketed because NSButton never calls highlight(_:) for them; the action still fires once.
        let target = ActionTarget()
        let (_, content) = window(NSSize(width: 200, height: 80))
        let click = GlassChromeButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
        click.frame = NSRect(x: 10, y: 10, width: 120, height: 40)
        content.addSubview(click)
        var pressing: [Bool] = []
        click.onInteractionChange = { pressing.append($0.isPressing) }
        let down = event(.leftMouseDown, in: content.window!, at: NSPoint(x: 30, y: 30))
        NSApp.postEvent(event(.leftMouseUp, in: content.window!, at: NSPoint(x: 30, y: 30)), atStart: false)
        click.mouseDown(with: down)
        expect(pressing.first == true && pressing.last == false && !click.isPressing, "A primary click presses then releases the surface state")
        expect(target.hits == ["snap"], "The primary action fires exactly once")

        // OriginalActionButton's secondary routing is untouched and also reports its press.
        let secondary = GlassChromeButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
        secondary.frame = NSRect(x: 10, y: 10, width: 120, height: 40)
        secondary.alternateTarget = target
        secondary.alternateAction = #selector(ActionTarget.alternate(_:))
        content.addSubview(secondary)
        target.hits.removeAll()
        var secondaryPress: [Bool] = []
        secondary.onInteractionChange = { secondaryPress.append($0.isPressing) }
        secondary.rightMouseDown(with: event(.rightMouseDown, in: content.window!, number: 2))
        expect(secondary.isPressing && target.hits.isEmpty, "Secondary press highlights without dispatching")
        secondary.rightMouseUp(with: event(.rightMouseUp, in: content.window!, number: 2))
        expect(target.hits == ["alternate"], "The alternate action still fires on release")
        expect(secondaryPress.contains(true) && secondaryPress.last == false && !secondary.isPressing, "The secondary press is reported and cleared")

        // A momentary click reads .on inside AppKit; that must never look like a selection. Assigning state still does.
        let momentary = GlassChromeButton(title: "Undo", target: target, action: #selector(ActionTarget.undo(_:)))
        momentary.icon = .arrowRotateLeft
        content.addSubview(momentary)
        target.hits.removeAll()
        momentary.performClick(nil)
        expect(target.hits == ["undo"] && !momentary.tracksState, "A momentary button is not a two-state button")
        expect(!momentary.showsSelection && momentary.activeFamily == .regular && sameColor(momentary.contentTintColor, .labelColor), "A momentary click never reads as selected")
        momentary.icon = .camera
        momentary.refreshIcon()
        expect(!momentary.showsSelection && momentary.activeFamily == .regular, "Redrawing a clicked momentary button keeps the regular glyph")
        momentary.state = .on
        expect(momentary.showsSelection && momentary.activeFamily == .solid, "Assigning state is always honored")
        momentary.state = .off

        // Toggles flip state inside the cell, so the glyph syncs when the action is sent.
        let toggled = GlassChromeButton(title: "", target: target, action: #selector(ActionTarget.chooseTool(_:)))
        toggled.setButtonType(.toggle)
        toggled.identifier = NSUserInterfaceItemIdentifier("brush")
        toggled.icon = .paintbrush
        content.addSubview(toggled)
        target.hits.removeAll()
        toggled.performClick(nil)
        expect(target.hits == ["tool:brush"], "A tool click delivers its identifier to the action")
        expect(toggled.state == .on && toggled.activeFamily == .solid, "A click-toggled button switches to the selected glyph")
    }

    @available(macOS 13, *)
    private static func buttonGlyphTests() {
        let tool = GlassChromeButton(title: "", target: nil, action: nil)
        tool.setButtonType(.toggle)
        tool.icon = .paintbrush
        expect(tool.iconSource == .fontAwesome(.regular), "With the subset registered, off renders Font Awesome Regular")
        tool.state = .on
        expect(tool.iconSource == .fontAwesome(.solid), "On renders Font Awesome Solid")
        tool.state = .off
        expect(tool.iconSource == .fontAwesome(.regular), "Off returns to Regular")
        tool.iconPointSize = 30
        expect((tool.image?.size.width ?? 0) == ceil(30 * 1.25), "iconPointSize drives the rendered canvas")
    }

    // MARK: BezelSizeSlider

    private static func sliderTests() {
        let slider = BezelSizeSlider(frame: NSRect(x: 0, y: 0, width: 40, height: 82))
        let (window, content) = window(NSSize(width: 60, height: 100))
        window.appearance = NSAppearance(named: .aqua)
        content.addSubview(slider)
        slider.frame = NSRect(x: 10, y: 9, width: 40, height: 82)
        expect(slider.style == .classic, "The slider is classic unless the chrome asks otherwise")

        func raster() -> NSBitmapImageRep {
            let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds)!
            slider.cacheDisplay(in: slider.bounds, to: rep)
            return rep
        }
        func opaquePixels(_ rep: NSBitmapImageRep) -> Int {
            var count = 0
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { count += 1 } }
            return count
        }
        func pixel(_ rep: NSBitmapImageRep, at point: NSPoint) -> NSColor? {
            let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
            return rep.colorAt(x: Int(point.x * scale), y: Int((slider.bounds.height - point.y) * scale))?.usingColorSpace(.deviceRGB)
        }
        // Wide-gamut accents come back from a bitmap tone-mapped, so the reference goes through the same raster path.
        let swatch = SwatchView(frame: NSRect(x: 0, y: 0, width: 20, height: 20), color: .controlAccentColor)
        content.addSubview(swatch)
        let swatchRep = swatch.bitmapImageRepForCachingDisplay(in: swatch.bounds)!
        swatch.cacheDisplay(in: swatch.bounds, to: swatchRep)
        let accent = swatchRep.colorAt(x: swatchRep.pixelsWide / 2, y: swatchRep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) ?? .black
        swatch.removeFromSuperview()

        // The classic branch paints only the recovered PNGs, which a bare test binary does not carry.
        expect(opaquePixels(raster()) == 0, "Classic drawing is the PNG path only: nothing is painted without the artwork")
        slider.doubleValue = 12
        expect(opaquePixels(raster()) == 0, "Classic stays PNG-only at every value")
        slider.doubleValue = OriginalDrawingControls.initialSize

        slider.style = .modern
        let modern = raster()
        expect(opaquePixels(modern) > 200, "Modern paints a vector track, ticks and knob")
        let knob = slider.pointForValue(slider.doubleValue)
        expect(sameColor(pixel(modern, at: NSPoint(x: knob.x + 7, y: knob.y + 7)), accent, tolerance: 0.05), "The knob is the accent color at pointForValue")
        let track = pixel(modern, at: NSPoint(x: slider.bounds.midX, y: 20))
        expect((track?.alphaComponent ?? 0) > 0.03 && !sameColor(track, accent, tolerance: 0.1), "The track is a quiet fill, not the accent")
        let beside = pixel(modern, at: NSPoint(x: slider.bounds.midX + 12, y: 20))
        expect((beside?.alphaComponent ?? 1) < 0.02, "Nothing is painted beside the track")
        expect(OriginalDrawingControls.sizeSteps.count == 5, "There are five steps")
        for step in OriginalDrawingControls.sizeSteps where step != OriginalDrawingControls.initialSize {
            let center = slider.pointForValue(step)
            let dot = pixel(modern, at: NSPoint(x: center.x + 7, y: center.y + 7))
            expect((dot?.alphaComponent ?? 0) > (track?.alphaComponent ?? 1) + 0.25, "Step \(step) carries a tick dot darker than the bare track")
        }
        slider.doubleValue = 12
        let moved = raster()
        let top = slider.pointForValue(12)
        expect(sameColor(pixel(moved, at: NSPoint(x: top.x + 7, y: top.y + 7)), accent, tolerance: 0.05), "The knob follows the value")
        let old = pixel(moved, at: NSPoint(x: knob.x + 7, y: knob.y + 7))
        expect(!sameColor(old, accent, tolerance: 0.1), "The knob left its previous position")

        // Style never changes the value mapping, the points or what a gesture does.
        for style in [BezelSizeSlider.Style.classic, .modern] {
            slider.style = style
            expect(slider.pointForValue(12).y == 0 && abs(slider.pointForValue(1.5).y - 64) < 0.0001 && slider.pointForValue(6.75).x == 13, "Geometry is identical in \(style)")
            slider.doubleValue = 6.75
            var changes = 0
            slider.target = nil
            slider.performValueChange(12, continuous: false)
            changes += slider.doubleValue == 12 ? 1 : 0
            slider.performValueChange(1.5, continuous: false)
            changes += slider.doubleValue == 1.5 ? 1 : 0
            expect(changes == 2, "Value changes behave the same in \(style)")
            slider.doubleValue = 6.75
        }
    }

    // MARK: GlassSurfaceView

    @available(macOS 26, *)
    private static func surface(_ accessibility: ChromeAccessibility = plain, shape: GlassShape = .capsule, interactive: Bool = true, content: NSView = NSView()) -> GlassSurfaceView {
        GlassSurfaceView(content: content, shape: shape, interactive: interactive, accessibility: accessibility)
    }

    @available(macOS 26, *)
    private static func expectTint(_ surface: GlassSurfaceView, _ base: NSColor?, _ alpha: CGFloat, _ message: String) {
        guard let base else {
            expect(surface.currentTint == nil && surface.tintColor == nil, message + " (untinted)")
            return
        }
        expect(surface.currentTint.map { sameColor($0, base) && abs($0.alphaComponent - alpha) < 0.001 } == true, message + " (computed)")
        expect(surface.tintColor.map { sameColor($0, base) && abs($0.alphaComponent - alpha) < 0.001 } == true, message + " (applied)")
    }

    @available(macOS 26, *)
    private static func surfaceTests() {
        for increased in [false, true] {
            let acc = increased ? contrast : plain
            let name = increased ? "IC " : ""
            let glass = surface(acc)
            expectTint(glass, nil, 0, name + "Normal")
            expect(glass.alphaValue == 1 && !glass.showsContrastRing, name + "Normal is opaque and ringless")
            glass.setHovered(true)
            expectTint(glass, .labelColor, increased ? 0.16 : 0.08, name + "Hover")
            glass.isPressed = true
            expectTint(glass, .labelColor, increased ? 0.28 : 0.16, name + "Pressed")
            glass.isPressed = false
            glass.setHovered(false)
            expectTint(glass, nil, 0, name + "Back to normal")
            glass.isSelected = true
            expectTint(glass, .controlAccentColor, increased ? 1.0 : 0.85, name + "Selected")
            expect(glass.showsContrastRing == increased && glass.layer?.borderWidth == (increased ? 1 : 0), name + "Selected ring only with Increase Contrast")
            expect(increased ? sameColor(NSColor(cgColor: glass.layer?.borderColor ?? NSColor.clear.cgColor), .labelColor, tolerance: 0.05) : true, name + "Ring is the label color")
            glass.setHovered(true)
            expectTint(glass, .controlAccentColor, increased ? 1.0 : 0.85, name + "Hover does not wash out a selected surface")
            glass.isPressed = true
            expectTint(glass, .controlAccentColor, 1.0, name + "Pressing a selected surface deepens it")
            glass.isPressed = false
            glass.setHovered(false)
            glass.isSelected = false
            expect(glass.layer?.borderWidth == 0, name + "Deselecting removes the ring")
            glass.prominence = .primary
            expectTint(glass, .controlAccentColor, increased ? 1.0 : 0.85, name + "Primary")
            expect(!glass.showsContrastRing && glass.layer?.borderWidth == 0, name + "Primary never rings")
            glass.prominence = .neutral
            expectTint(glass, nil, 0, name + "Neutral again")
            glass.isDisabled = true
            expect(glass.alphaValue == 0.5, name + "Disabled dims through alpha")
            glass.setHovered(true)
            glass.isPressed = true
            expectTint(glass, nil, 0, name + "Disabled ignores hover and press")
            glass.isPressed = false
            glass.setHovered(false)
            glass.isSelected = true
            expectTint(glass, .controlAccentColor, increased ? 1.0 : 0.85, name + "Disabled selection keeps its tint")
            expect(glass.alphaValue == 0.5, name + "Disabled selection is still dimmed")
            glass.isDisabled = false
            expect(glass.alphaValue == 1, name + "Enabling restores alpha")
        }

        // Accessibility injection re-evaluates the live state.
        let live = surface()
        live.setHovered(true)
        expectTint(live, .labelColor, 0.08, "Hover before injection")
        live.accessibility = contrast
        expectTint(live, .labelColor, 0.16, "Hover after Increase Contrast is injected")
        live.accessibility = plain
        expectTint(live, .labelColor, 0.08, "Hover after it is removed")

        // Animation: 0.15 s, zero under Reduce Motion.
        let animated = surface(plain)
        animated.isSelected = true
        expect(animated.lastAnimationDuration == 0.15, "State changes animate over 0.15 s")
        animated.accessibility = calm
        animated.isSelected = false
        expect(animated.lastAnimationDuration == 0, "Reduce Motion makes state changes instant")
        animated.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        animated.isSelected = true
        expect(animated.lastAnimationDuration == 0.15, "Reduce Transparency alone keeps the animation")

        // Shape: capsule radius is half the short side after layout; rounded keeps its radius.
        let (_, content) = window(NSSize(width: 400, height: 200))
        let wide = surface(shape: .capsule), square = surface(shape: .circle), tool = surface(shape: .rounded(12)), tall = surface(shape: .capsule)
        wide.setSize(NSSize(width: 148, height: 36))
        square.setSize(NSSize(width: 36, height: 36))
        tool.setSize(NSSize(width: 48, height: 40))
        tall.setSize(NSSize(width: 40, height: 90))
        var x: CGFloat = 10
        for glass in [wide, square, tool, tall] {
            content.addSubview(glass)
            glass.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: x).isActive = true
            glass.topAnchor.constraint(equalTo: content.topAnchor, constant: 10).isActive = true
            x += 60
        }
        content.layoutSubtreeIfNeeded()
        expect(wide.frame.size == NSSize(width: 148, height: 36) && wide.cornerRadius == 18, "Capsule radius is half of the 36 pt command height after layout")
        expect(square.cornerRadius == 18, "Circle radius is half the side")
        expect(tool.cornerRadius == 12, "Rounded keeps its radius")
        expect(tall.cornerRadius == 20, "A tall capsule rounds to half its 40 pt width")
        expect(wide.layer?.cornerRadius == 18, "The ring layer follows the corner radius")
        wide.shape = .rounded(14)
        expect(wide.cornerRadius == 14, "Changing the shape updates the radius")
        wide.shape = .capsule
        expect(wide.cornerRadius == 18, "Changing back restores the capsule radius")
        expect(GlassShape.rounded(99).radius(for: NSSize(width: 48, height: 40)) == 20, "A radius never exceeds half the short side")

        // effectIsInteractive exists only on macOS 27.
        if #available(macOS 27, *) {
            expect(surface(interactive: true).effectIsInteractive, "Interactive surfaces opt into system press feedback on macOS 27")
            expect(!surface(interactive: false).effectIsInteractive, "Static surfaces stay static")
        } else {
            notes.append("effectIsInteractive (macOS 27 only)")
        }
        expect(surface().style == .regular, "One glass variant: Regular")

        // A button inside a surface fills it and drives the state from its own interaction.
        let button = GlassChromeButton(title: "Snap", target: nil, action: nil)
        button.setButtonType(.toggle)
        button.icon = .crosshairs
        let host = surface(shape: .capsule, content: button)
        host.setSize(NSSize(width: 148, height: 36))
        content.addSubview(host)
        host.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10).isActive = true
        host.topAnchor.constraint(equalTo: content.topAnchor, constant: 100).isActive = true
        content.layoutSubtreeIfNeeded()
        expect(button.frame.size == host.bounds.size, "The control fills its surface")
        expect(button.focusShape == .capsule, "The button's focus ring takes the surface shape")
        button.state = .on
        expect(host.isSelected && host.currentTint != nil, "A selected button selects its surface")
        button.state = .off
        button.highlight(true)
        expect(host.isPressed, "A pressed button presses its surface")
        button.highlight(false)
        button.isEnabled = false
        expect(host.isDisabled && host.alphaValue == 0.5, "A disabled button disables its surface")
        button.isEnabled = true
        button.isHidden = true
        expect(host.isHidden, "Hiding the button hides its surface")
        button.isHidden = false
        expect(!host.isHidden, "Showing the button shows its surface")
        host.prominence = .primary
        expect(button.isPrimary, "Primary prominence reaches the button's label color")
        host.prominence = .neutral
        host.setHovered(true)
        host.isHidden = true
        expect(!host.isHovered, "Hiding a surface clears hover")
        host.isHidden = false
        let before = host.fixedSize
        host.setSize(NSSize(width: 100, height: 36))
        expect(before == NSSize(width: 148, height: 36) && host.fixedSize == NSSize(width: 100, height: 36), "Resizing replaces the explicit constraints")
        content.layoutSubtreeIfNeeded()
        expect(host.frame.width == 100, "Replaced constraints take effect")

        // The factory sizes every surface explicitly and groups hold surfaces in one container.
        let made = GlassChrome.surface(GlassChromeButton(title: "Hide", target: nil, action: nil), shape: .capsule, accessibility: plain)
        expect(made.fixedSize.map { $0.height == GlassChrome.Metrics.commandHeight && $0.width >= GlassChrome.Metrics.commandHeight } == true, "The factory always sets an explicit command-height size")
        let circle = GlassChrome.surface(NSView(), shape: .circle, accessibility: plain)
        expect(circle.fixedSize == NSSize(width: 36, height: 36), "A circle is a command-height square")
        let group = GlassChrome.group([made, circle], orientation: .horizontal, identifier: "Test")
        expect(group.identifier?.rawValue == "Test" && group.spacing == GlassChrome.Metrics.containerSpacing, "Group carries its identifier and the container spacing")
        let stack = group.contentView as? NSStackView
        expect(stack?.arrangedSubviews.count == 2 && stack?.spacing == GlassChrome.Metrics.surfaceSpacing && stack?.orientation == .horizontal, "Group stacks its surfaces")
        let metrics = GlassChrome.Metrics.self
        expect(metrics.toolButton == NSSize(width: 48, height: 40) && metrics.commandHeight == 36 && metrics.railWidth == 64 && metrics.rightRailWidth == 160 && metrics.headerHeight == 44, "Metrics match the plan with Apple's 36 pt Extra Large commands")
        expect(metrics.iconPointSize == 22 && metrics.labelPointSize == 20 && metrics.groupSpacing == 10 && metrics.surfaceSpacing == 6 && metrics.containerSpacing == 8, "Spacing and type metrics match the plan")
    }

    // MARK: ModernEditorChrome

    @available(macOS 26, *)
    private struct Rig {
        let window: NSWindow, content: NSView, chrome: ModernEditorChrome, controls: ModernEditorChrome.SharedControls
        let target: ActionTarget, box: AccessibilityBox, size: NSSize
    }

    @available(macOS 26, *)
    private static func makeRig(_ size: NSSize) -> Rig {
        let target = ActionTarget(), box = AccessibilityBox()
        let (window, content) = window(size)
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 12)
            return field
        }
        let zoom = NSPopUpButton(frame: .zero, pullsDown: false)
        zoom.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        zoom.font = .systemFont(ofSize: 13)
        zoom.setAccessibilityLabel("Canvas zoom")
        let format = NSPopUpButton(frame: .zero, pullsDown: false)
        format.addItems(withTitles: ["PNG", "JPEG 100%", "JPEG 80%", "JPEG 60%", "JPEG 30%", "JPEG 10%", "TIFF", "GIF", "BMP", "PDF", "SVG", "Skitch"])
        format.font = .systemFont(ofSize: 20)
        format.setAccessibilityLabel("Drag Me format")
        let toolbox = NSPopUpButton(frame: .zero, pullsDown: true)
        toolbox.addItems(withTitles: ["Toolbox", "About OpenSkitch", "Quit OpenSkitch"])
        toolbox.font = .systemFont(ofSize: 20)
        toolbox.setAccessibilityLabel("Toolbox")
        let palette = BezelHoverButton(title: "Color…", target: nil, action: nil)
        palette.font = .systemFont(ofSize: 18)
        palette.setAccessibilityLabel("Drawing colors")
        palette.image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let name = NSTextField(string: "Untitled")
        name.font = .systemFont(ofSize: 14)
        let original = NSButton(checkboxWithTitle: "Original size", target: nil, action: nil)
        original.font = .systemFont(ofSize: 11)
        let controls = ModernEditorChrome.SharedControls(
            canvas: NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)), canvasBorder: NSView(),
            nameField: name, status: label("Ready"), sizeLabel: label("Size · 6.75"),
            widthControl: BezelSizeSlider(frame: .zero), paletteButton: palette, zoomControl: zoom, dragFormatControl: format,
            dragOriginalControl: original, dragSizeLabel: label("1000 × 700 · 48 KB"), dragExportView: NSView(), toolbox: toolbox,
            brandLogo: NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in NSColor.orange.setFill(); rect.fill(); return true })
        let actions = ModernEditorChrome.Actions(
            target: target, hide: #selector(ActionTarget.hide(_:)), photos: #selector(ActionTarget.photos(_:)), saveHistory: #selector(ActionTarget.saveHistory(_:)),
            showHistory: #selector(ActionTarget.showHistory(_:)), chooseTool: #selector(ActionTarget.chooseTool(_:)), snap: #selector(ActionTarget.snap(_:)),
            camera: #selector(ActionTarget.camera(_:)), cancelFrame: #selector(ActionTarget.cancelFrame(_:)), font: #selector(ActionTarget.font(_:)),
            undo: #selector(ActionTarget.undo(_:)), wipe: #selector(ActionTarget.wipe(_:)), actualSize: #selector(ActionTarget.actualSize(_:)),
            resize: #selector(ActionTarget.resize(_:)), share: #selector(ActionTarget.share(_:)))
        let chrome = ModernEditorChrome(controls: controls, actions: actions, toolOrder: toolOrder, accessibility: { box.value })
        chrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor), chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: content.topAnchor), chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.layoutSubtreeIfNeeded()
        return Rig(window: window, content: content, chrome: chrome, controls: controls, target: target, box: box, size: size)
    }

    @available(macOS 26, *)
    private static func visibleControls(_ rig: Rig) -> [NSControl] {
        var found: [NSControl] = []
        func walk(_ view: NSView) {
            if view.isHidden || view === rig.chrome.scrollView || view === rig.controls.canvasBorder { return }
            if let control = view as? NSControl { found.append(control); return }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    @available(macOS 26, *)
    private static func containers(_ rig: Rig) -> [NSGlassEffectContainerView] {
        var found: [NSGlassEffectContainerView] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let container = view as? NSGlassEffectContainerView { found.append(container) }
            if view === rig.chrome.scrollView { return }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    @available(macOS 26, *)
    private static func surfaces(_ rig: Rig) -> [GlassSurfaceView] {
        var found: [GlassSurfaceView] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let glass = view as? GlassSurfaceView { found.append(glass) }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    @available(macOS 26, *)
    private static func rect(_ view: NSView, in rig: Rig) -> NSRect { view.convert(view.bounds, to: rig.content) }

    private static func describe(_ view: NSView) -> String {
        (view.identifier?.rawValue).map { "#" + $0 } ?? (view as? NSButton).map { "'" + $0.title + "'" } ?? String(describing: type(of: view))
    }

    @available(macOS 26, *)
    private static func verifyLayout(_ rig: Rig, _ label: String) {
        rig.content.layoutSubtreeIfNeeded()
        expect(rig.content.bounds.size == rig.size, "\(label): the chrome fits without growing the window (\(rig.content.bounds.size) vs \(rig.size))")
        let chrome = rig.chrome
        let controls = visibleControls(rig)
        expect(controls.count >= 24, "\(label): the visible controls were found (\(controls.count))")
        for control in controls {
            let frame = rect(control, in: rig)
            expect(rig.content.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(label): \(describe(control)) lies inside the window content \(frame)")
            if let parent = control.superview {
                // Layout places alignment rects; a label's frame legitimately extends 2 pt past it for its text inset.
                let placed = control.alignmentRect(forFrame: control.frame)
                expect(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(placed), "\(label): \(describe(control)) lies inside its superview \(placed) in \(parent.bounds)")
            }
            expect(!frame.isEmpty && frame.height >= 18, "\(label): \(describe(control)) has a real size \(frame)")
            if !(control is NSImageView) {
                expect((control.font?.pointSize ?? 0) >= 18, "\(label): \(describe(control)) is at least 18 pt (\(control.font?.pointSize ?? 0))")
            }
            if let button = control as? GlassChromeButton, !button.title.isEmpty {
                expect(button.fittingSize.width <= button.frame.width + 0.5, "\(label): \(describe(button)) title fits its surface (\(button.fittingSize.width) in \(button.frame.width))")
            }
        }
        for (index, a) in controls.enumerated() {
            for b in controls[(index + 1)...] {
                let overlap = rect(a, in: rig).intersection(rect(b, in: rig))
                expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): \(describe(a)) overlaps \(describe(b)) by \(overlap)")
            }
        }
        for glass in surfaces(rig) {
            let frame = rect(glass, in: rig)
            expect(rig.content.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(label): surface around \(describe(glass.contentView ?? glass)) lies inside the content")
            if let fixed = glass.fixedSize {
                expect(abs(frame.height - fixed.height) < 0.5 && frame.width >= fixed.width - 0.5, "\(label): surface around \(describe(glass.contentView ?? glass)) kept its explicit size \(frame.size) vs \(fixed)")
            }
            expect(frame.height >= 36 && frame.width >= 36, "\(label): no surface collapsed below 36 pt \(frame.size)")
            expect(glass.contentView.map { abs($0.frame.width - glass.bounds.width) < 0.5 && abs($0.frame.height - glass.bounds.height) < 0.5 } == true, "\(label): the content fills its surface")
        }
        let scroll = rect(chrome.scrollView, in: rig)
        expect(scroll.width > 300 && scroll.height > 300, "\(label): the canvas keeps room \(scroll.size)")
        let glassContainers = containers(rig)
        expect(glassContainers.count >= 7, "\(label): glass groups exist (\(glassContainers.count))")
        for container in glassContainers {
            let frame = rect(container, in: rig)
            let overlap = frame.intersection(scroll)
            expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): scroll view is disjoint from \(describe(container)) \(frame) vs \(scroll)")
        }
        for (index, a) in glassContainers.enumerated() {
            for b in glassContainers[(index + 1)...] {
                let overlap = rect(a, in: rig).intersection(rect(b, in: rig))
                expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): glass groups \(describe(a)) and \(describe(b)) are disjoint")
            }
        }
        // Order: header left to right, tools top to bottom in archive order, footer left to right.
        let brand = chrome.header.subviews.first { $0.identifier?.rawValue == "OpenSkitchBrand" }
        expect(brand != nil, "\(label): the brand is a direct child of the header")
        if let brand {
            let frame = rect(brand, in: rig)
            expect(abs(frame.midX - rig.content.bounds.midX) <= 1, "\(label): brand is centered on the window (\(frame.midX) vs \(rig.content.bounds.midX))")
            expect(rect(chrome.hideButton, in: rig).maxX < frame.minX && rect(chrome.saveButton, in: rig).minX > frame.maxX, "\(label): brand sits between the header groups")
        }
        let headerOrder = [chrome.hideButton, rig.controls.toolbox, chrome.photosButton].map { rect($0, in: rig).minX }
        expect(headerOrder == headerOrder.sorted(), "\(label): Hide, Toolbox, Photos run left to right")
        expect(rect(chrome.saveButton, in: rig).minX < rect(chrome.historyButton, in: rig).minX, "\(label): Save precedes History")
        let toolsByHeight = chrome.toolButtons.values.sorted { rect($0, in: rig).minY > rect($1, in: rig).minY }
        expect(toolsByHeight.map { $0.identifier?.rawValue ?? "" } == toolOrder, "\(label): tools run top to bottom in archive order, crop last")
        let footerOrder = [chrome.actualButton, chrome.resizeButton, rig.controls.nameField, rig.controls.dragFormatControl, rig.controls.dragExportView, chrome.shareButton].map { rect($0, in: rig).minX }
        expect(footerOrder == footerOrder.sorted(), "\(label): the footer row runs Actual Size to Webpost")
        let footerY = rect(chrome.actualButton, in: rig).midY
        expect(abs(footerY - rect(chrome.shareButton, in: rig).midY) < 0.5, "\(label): footer controls share a baseline")
        expect(rect(rig.controls.status, in: rig).maxY < rect(chrome.actualButton, in: rig).minY, "\(label): the status row sits below the command row")
        expect(rect(chrome.undoButton, in: rig).minY < rect(rig.controls.widthControl, in: rig).minY, "\(label): Undo and Wipe are pinned below the drawing controls")
        let rightEdge = [chrome.snapButton, chrome.fontButton, chrome.undoButton].map { rect($0, in: rig).maxX }
        expect(Set(rightEdge).count == 1 && rightEdge[0] < rig.content.bounds.maxX, "\(label): the right rail is one aligned column")
        // The canvas border lives where classic puts it, beside the scroll view and above everything.
        expect(rig.controls.canvasBorder.superview === chrome.scrollView.superview && chrome.subviews.last === rig.controls.canvasBorder, "\(label): the canvas border is a topmost sibling of the scroll view")
        expect(chrome.scrollView.documentView === rig.controls.canvas && !chrome.scrollView.drawsBackground && !chrome.scrollView.contentView.drawsBackground, "\(label): the scroll view hosts the canvas without a background")
    }

    @available(macOS 26, *)
    private static func chromeTests(glyphs: Bool) {
        let tag = glyphs ? "glyphs" : "symbols"
        let minimum = NSWindow.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
        for size in [minimum, NSSize(width: 1024, height: 740)] {
            let label = "\(tag) \(Int(size.width))x\(Int(size.height))"
            let rig = makeRig(size)
            verifyLayout(rig, label)
            semantics(rig, label)
            rig.chrome.frameMode = true
            verifyLayout(rig, label + " frame mode")
            frameModeChecks(rig, label)
            rig.chrome.frameMode = false
            verifyLayout(rig, label + " after frame mode")
            if size == minimum {
                bleedChecks(rig, label)
                accessibilityChecks(rig, label)
            }
        }
    }

    @available(macOS 26, *)
    private static func semantics(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        expect(chrome.header.identifier?.rawValue == "OpenSkitchHeader", "\(label): header identifier")
        let brand = chrome.header.subviews.first { $0.identifier?.rawValue == "OpenSkitchBrand" } as? NSStackView
        let logo = brand?.arrangedSubviews.first as? NSImageView, name = brand?.arrangedSubviews.last as? NSTextField
        expect(logo?.accessibilityLabel() == "ShoeMoney logo" && logo?.image === rig.controls.brandLogo, "\(label): logo keeps the classic label")
        expect(name?.stringValue == "OpenSkitch" && name?.font?.pointSize == 20, "\(label): brand name is 20 pt")
        expect(abs((logo?.frame.width ?? 0) - 32) < 0.5 && abs((logo?.frame.height ?? 0) - 32) < 0.5, "\(label): logo is 32 pt")
        expect((name?.font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat == NSFont.Weight.semibold.rawValue, "\(label): brand name is semibold")
        expect(chrome.toolButtons.count == 10 && Set(chrome.toolButtons.keys) == Set(toolOrder), "\(label): ten tool buttons, crop included")
        for id in toolOrder {
            guard let button = chrome.toolButtons[id] else { continue }
            expect(button.identifier?.rawValue == id, "\(label): tool identifier \(id)")
            expect(button.accessibilityLabel() == id.capitalized, "\(label): tool AX label \(id)")
            expect(button.toolTip == id.capitalized + " tool", "\(label): tool tooltip \(id)")
            expect(button.imagePosition == .imageOnly && button.image != nil, "\(label): tool \(id) is icon only")
            expect(button.action == #selector(ActionTarget.chooseTool(_:)) && button.target === rig.target, "\(label): tool \(id) sends chooseTool")
            expect(button.isEnabled && !button.isHidden, "\(label): tool \(id) is live")
            expect(chrome.surface(for: button) != nil && chrome.surface(for: button) === button.superview?.superview, "\(label): tool \(id) has its own surface")
            expect(chrome.surface(for: button)?.shape == .rounded(12) && chrome.surface(for: button)?.fixedSize == NSSize(width: 48, height: 40), "\(label): tool \(id) surface is 48x40 r=12")
            expect(abs(rect(button, in: rig).width - 48) < 0.5 && abs(rect(button, in: rig).height - 40) < 0.5, "\(label): tool \(id) button is 48x40")
        }
        expect(Set(chrome.toolButtons.values.compactMap { chrome.surface(for: $0).map(ObjectIdentifier.init) }).count == 10, "\(label): tool surfaces are distinct")
        for (button, title, hit) in [(chrome.hideButton, "Hide", "hide"), (chrome.photosButton, "Photos", "photos"), (chrome.saveButton, "Save", "saveHistory"),
                                     (chrome.historyButton, "History", "showHistory"), (chrome.snapButton, "Snap", "snap"), (chrome.cameraButton, "Cam", "camera"),
                                     (chrome.cancelFrameButton, "Cancel", "cancelFrame"), (chrome.fontButton, "Font", "font"), (chrome.undoButton, "Undo", "undo"),
                                     (chrome.wipeButton, "Wipe", "wipe"), (chrome.actualButton, "Actual Size", "actualSize"), (chrome.resizeButton, "Resize…", "resize")] {
            expect(button.title == title, "\(label): \(title) keeps its classic title")
            expect(button.controlSize == .extraLarge, "\(label): \(title) uses Apple's Extra Large control size")
            expect(button.icon != nil && button.image != nil && button.imagePosition == .imageLeading, "\(label): \(title) shows icon and label")
            expect((button.font?.pointSize ?? 0) == 20, "\(label): \(title) label is 20 pt")
            expect(button.identifier == nil, "\(label): \(title) has no identifier, as in classic")
            expect(chrome.surface(for: button)?.shape == .capsule, "\(label): \(title) is a capsule")
            expect(chrome.surface(for: button)?.fixedSize?.height == 36 && abs(rect(button, in: rig).height - 36) < 0.5, "\(label): \(title) is a 36 pt command")
            expect(36 - (button.font.map { $0.ascender - $0.descender + $0.leading } ?? 99) >= 8, "\(label): \(title) keeps 8 pt of vertical breathing room in its capsule")
            rig.target.hits.removeAll()
            button.performClick(nil)
            expect(rig.target.hits == [hit], "\(label): \(title) sends its action (\(rig.target.hits))")
            expect(chrome.surface(for: button)?.isSelected == false, "\(label): clicking \(title) never leaves its glass selected")
        }
        chrome.actualButton.state = .off
        expect(chrome.shareButton.accessibilityLabel() == "Upload to destination" && chrome.shareButton.title.isEmpty && chrome.shareButton.imagePosition == .imageOnly,
               "\(label): the upload button is icon-only with an explicit label")
        rig.target.hits.removeAll(); chrome.shareButton.performClick(nil)
        expect(rig.target.hits == ["share"], "\(label): the upload button sends its action")
        expect(chrome.snapButton.toolTip == snapToolTip, "\(label): Snap keeps its classic tooltip")
        expect(chrome.surface(for: chrome.snapButton)?.prominence == .primary && chrome.snapButton.isPrimary, "\(label): Snap is the single primary command")
        let primaries = surfaces(rig).filter { $0.prominence == .primary }
        expect(primaries.count == 1, "\(label): exactly one primary surface")
        expect(chrome.cancelFrameButton.isHidden && chrome.surface(for: chrome.cancelFrameButton)?.isHidden == true, "\(label): Cancel starts hidden")
        expect(!chrome.cameraButton.isHidden && !chrome.frameMode, "\(label): Cam starts visible")
        expect(chrome.actualButton.selectedIcon == .minimize && !chrome.actualButton.selectionTints, "\(label): Actual Size swaps its glyph without tinting")
        expect(chrome.surface(for: chrome.actualButton)?.fixedSize?.width ?? 0 >= 160, "\(label): Actual Size is wide enough for Normal View")
        chrome.actualButton.title = "Normal View"
        rig.content.layoutSubtreeIfNeeded()
        expect(chrome.actualButton.fittingSize.width <= chrome.actualButton.frame.width + 0.5, "\(label): Normal View fits the Actual Size surface")
        chrome.actualButton.title = "Actual Size"

        // Shared controls: re-parented, floors applied, caller-owned strings untouched.
        let shared = rig.controls
        expect(shared.toolbox.accessibilityLabel() == "Toolbox" && shared.paletteButton.accessibilityLabel() == "Drawing colors" && shared.zoomControl.accessibilityLabel() == "Canvas zoom" && shared.dragFormatControl.accessibilityLabel() == "Drag Me format", "\(label): caller labels are untouched")
        for control in [shared.toolbox, shared.dragFormatControl, shared.paletteButton, shared.nameField] as [NSControl] {
            expect(control.controlSize == .extraLarge && (control.font?.pointSize ?? 0) >= 18, "\(label): \(describe(control)) is Extra Large and keeps its readable font")
        }
        expect(shared.toolbox.imagePosition == .imageOnly && shared.toolbox.itemArray.first?.image != nil, "\(label): Toolbox shows its icon")
        expect(chrome.surface(for: shared.sizeLabel) === chrome.surface(for: shared.widthControl) && chrome.surface(for: shared.widthControl)?.shape == .rounded(12), "\(label): Size label and slider share one rounded surface")
        expect((shared.widthControl as? BezelSizeSlider)?.style == .modern, "\(label): the slider uses the vector style")
        expect(abs(rect(shared.widthControl, in: rig).width - 36) < 0.5 && abs(rect(shared.widthControl, in: rig).height - 82) < 0.5, "\(label): the slider is Apple's 36 pt wide Extra Large slider, 82 pt tall")
        expect(chrome.surface(for: shared.dragExportView)?.shape == .rounded(14), "\(label): Drag Me is a rounded r=14 surface")
        expect(chrome.surface(for: shared.nameField)?.shape == .capsule && !shared.nameField.drawsBackground, "\(label): the name field sits in a glass capsule")
        expect(chrome.surface(for: shared.dragFormatControl)?.shape == .capsule, "\(label): the format popup sits in a glass capsule")
        expect(chrome.surface(for: shared.paletteButton) != nil && chrome.surface(for: chrome.fontButton) != nil, "\(label): Color and Font have surfaces")
        for plainControl in [shared.zoomControl, shared.dragOriginalControl, shared.dragSizeLabel, shared.status] as [NSControl] {
            expect(chrome.surface(for: plainControl) == nil, "\(label): \(describe(plainControl)) stays plain, outside any glass")
            expect(plainControl.superview is NSStackView && !(plainControl.superview?.superview is GlassSurfaceView), "\(label): \(describe(plainControl)) lives in the plain status row")
        }
        for control in [shared.status, shared.dragSizeLabel] { expect(sameColor(control.textColor, .labelColor), "\(label): status text uses the label color") }
        expect(chrome.surface(for: shared.canvas) == nil, "\(label): the canvas never sits in glass")
        var ancestor: NSView? = shared.canvas
        var insideGlass = false
        while let view = ancestor { if view is NSGlassEffectView || view is NSGlassEffectContainerView { insideGlass = true }; ancestor = view.superview }
        expect(!insideGlass, "\(label): no glass above the canvas")
        let order = chrome.subviews
        func position(_ view: NSView?) -> Int { view.flatMap { order.firstIndex(of: $0) } ?? -1 }
        let backdrop = order.first { $0 is NSVisualEffectView }, bleed = order.first { $0 is NSBackgroundExtensionView }
        expect(position(backdrop) == 0 && position(bleed) == 1 && position(chrome.scrollView) == 2 && position(chrome.header) == 3, "\(label): backdrop, bleed, canvas, then glass")
        expect((backdrop as? NSVisualEffectView).map { $0.material == .underWindowBackground && $0.blendingMode == .behindWindow && $0.state == .followsWindowActiveState } == true, "\(label): backdrop material")
        expect(chrome.backdropIsVisible, "\(label): backdrop shows")
        expect(!surfaces(rig).contains { $0.contentView === rig.controls.canvas || $0.contentView === chrome.scrollView }, "\(label): glass never wraps the scroll view")
        expect(surfaces(rig).allSatisfy { $0.style == .regular }, "\(label): one glass variant")

        // Selecting a tool tints its surface and flips its glyph; the others stay quiet.
        chrome.toolButtons["brush"]?.state = .on
        let selected = chrome.surface(for: chrome.toolButtons["brush"]!)
        expect(selected?.isSelected == true && selected?.currentTint != nil, "\(label): the selected tool's surface is tinted")
        expect(chrome.toolButtons["brush"]?.activeFamily == .solid, "\(label): the selected tool uses the solid family")
        expect(sameColor(chrome.toolButtons["brush"]?.contentTintColor, ToolButton.textColor(on: .controlAccentColor)), "\(label): the selected glyph contrasts with the accent")
        expect(toolOrder.filter { $0 != "brush" }.allSatisfy { chrome.surface(for: chrome.toolButtons[$0]!)?.isSelected == false }, "\(label): other tools stay untinted")
        chrome.toolButtons["brush"]?.state = .off
        expect(selected?.isSelected == false && selected?.currentTint == nil, "\(label): deselecting clears the tint")

        // Hiding a button hides its glass wherever the caller does it.
        chrome.cameraButton.isHidden = true
        expect(chrome.surface(for: chrome.cameraButton)?.isHidden == true, "\(label): a hidden Cam leaves no empty glass")
        chrome.cameraButton.isHidden = false
        expect(chrome.surface(for: chrome.cameraButton)?.isHidden == false, "\(label): Cam returns with its glass")
        for toolbox in [shared.toolbox] { expect(chrome.surface(for: toolbox)?.fixedSize?.width ?? 0 >= 64, "\(label): the Toolbox surface has room for icon and chevron") }
    }

    @available(macOS 26, *)
    private static func frameModeChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        expect(chrome.snapButton.title == "Snap Frame" && chrome.snapButton.icon == .cameraViewfinder, "\(label): Snap becomes Snap Frame with the viewfinder")
        expect(chrome.snapButton.toolTip == snapFrameToolTip, "\(label): Snap Frame tooltip")
        expect(chrome.snapButton.isPrimary && chrome.surface(for: chrome.snapButton)?.prominence == .primary, "\(label): Snap Frame stays primary")
        expect(!chrome.cancelFrameButton.isHidden && chrome.surface(for: chrome.cancelFrameButton)?.isHidden == false, "\(label): Cancel appears in Frame mode")
        expect(chrome.cameraButton.isHidden && chrome.surface(for: chrome.cameraButton)?.isHidden == true, "\(label): Cam hides in Frame mode")
        expect(!chrome.backdropIsVisible && !chrome.bleedIsVisible, "\(label): backdrop and bleed give way to the Frame hole")
        let cancel = rect(chrome.cancelFrameButton, in: rig), snap = rect(chrome.snapButton, in: rig)
        expect(abs(cancel.width - 148) < 0.5 && abs(cancel.height - 36) < 0.5 && cancel.maxY <= snap.minY, "\(label): Cancel is a full pill under Snap Frame")
        expect(abs(snap.width - 148) < 0.5, "\(label): Snap Frame keeps the 148 pt pill")
        expect(rig.controls.canvas.window === rig.window && chrome.scrollView.frame.size != .zero, "\(label): the canvas stays in place in Frame mode")
    }

    @available(macOS 26, *)
    private static func bleedChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        expect(GlassChrome.usesCanvasBleed, "\(label): bleed defaults on")
        expect(!chrome.bleedIsVisible, "\(label): bleed is hidden until there is a thumbnail")
        let thumbnail = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemPink.setFill(); rect.fill(); return true }
        chrome.updateCanvasBleed(thumbnail)
        expect(chrome.bleedIsVisible && chrome.backdropIsVisible, "\(label): a thumbnail shows the bleed")
        rig.content.layoutSubtreeIfNeeded()
        let bleed = chrome.subviews.compactMap { $0 as? NSBackgroundExtensionView }.first
        expect(bleed?.alphaValue == 0.6, "\(label): bleed is drawn at 0.6")
        expect(bleed.map { $0.contentView?.frame == chrome.scrollView.frame } == true, "\(label): the thumbnail sits exactly on the canvas area; only its extension reaches under the rails")
        chrome.frameMode = true
        expect(!chrome.bleedIsVisible, "\(label): Frame mode hides the bleed")
        chrome.frameMode = false
        expect(chrome.bleedIsVisible, "\(label): leaving Frame mode brings the bleed back")
        chrome.updateCanvasBleed(nil)
        expect(!chrome.bleedIsVisible, "\(label): no image, no bleed")
        chrome.updateCanvasBleed(thumbnail)
        GlassChrome.usesCanvasBleed = false
        chrome.updateCanvasBleed(thumbnail)
        expect(!chrome.bleedIsVisible, "\(label): the flag disables the bleed")
        GlassChrome.usesCanvasBleed = true
        chrome.updateCanvasBleed(thumbnail)
        expect(chrome.bleedIsVisible, "\(label): re-enabling the flag restores it")
        chrome.updateCanvasBleed(nil)
    }

    @available(macOS 26, *)
    private static func accessibilityChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let thumbnail = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemPink.setFill(); rect.fill(); return true }
        chrome.updateCanvasBleed(thumbnail)
        expect(chrome.bleedIsVisible, "\(label): bleed visible before injection")
        let hovered = chrome.surface(for: chrome.undoButton)!
        hovered.setHovered(true)
        expect(abs((hovered.currentTint?.alphaComponent ?? 0) - 0.08) < 0.001, "\(label): hover tint before injection")
        chrome.toolButtons["line"]?.state = .on
        let selected = chrome.surface(for: chrome.toolButtons["line"]!)!
        expect(!selected.showsContrastRing, "\(label): no ring before Increase Contrast")

        chrome.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true)
        expect(!chrome.bleedIsVisible, "\(label): Reduce Transparency hides the bleed")
        expect(abs((hovered.currentTint?.alphaComponent ?? 0) - 0.16) < 0.001, "\(label): Increase Contrast strengthens the hover tint")
        expect(selected.showsContrastRing && selected.layer?.borderWidth == 1, "\(label): Increase Contrast rings the selected tool")
        expect(surfaces(rig).allSatisfy { $0.accessibility.increaseContrast && $0.accessibility.reduceMotion && $0.accessibility.reduceTransparency }, "\(label): every surface receives the injected options")
        expect(hovered.lastAnimationDuration == 0, "\(label): Reduce Motion reaches the surfaces")
        chrome.updateCanvasBleed(thumbnail)
        expect(!chrome.bleedIsVisible, "\(label): a new thumbnail stays hidden under Reduce Transparency")
        chrome.accessibility = .none
        expect(chrome.bleedIsVisible && abs((hovered.currentTint?.alphaComponent ?? 0) - 0.08) < 0.001 && !selected.showsContrastRing, "\(label): clearing the options restores everything")
        hovered.setHovered(false)
        chrome.toolButtons["line"]?.state = .off

        // The live path: the provider is read again when the system posts a display-options change.
        rig.box.value = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        expect(chrome.accessibility.reduceTransparency && !chrome.bleedIsVisible, "\(label): the display-options notification re-reads the provider")
        rig.box.value = .none
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        expect(chrome.accessibility == .none && chrome.bleedIsVisible, "\(label): and again when the options clear")
        chrome.updateCanvasBleed(nil)
    }
}

#endif
