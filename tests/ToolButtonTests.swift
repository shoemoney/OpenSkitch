// Nonordering native controls and offscreen production rendering only.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D TOOL_BUTTON_TESTS \
//   Sources/OriginalActionButton.swift Sources/ToolButton.swift tests/ToolButtonTests.swift -o build/tool-button-tests
// rtk proxy build/tool-button-tests
// The original-artwork pairs need the git-ignored original/ archive; without it they print a SKIP line and the rest still run.
#if TOOL_BUTTON_TESTS
import AppKit

@MainActor
private final class ButtonTarget: NSObject {
    var states: [NSControl.StateValue] = []
    var senders: [NSButton] = []
    @objc func choose(_ sender: NSButton) {
        states.append(sender.state)
        senders.append(sender)
    }
}

@MainActor
private final class NonorderingButtonWindow: NSWindow {
    override func orderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
    override func orderFrontRegardless() { preconditionFailure("No desktop windows") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
}

@main
@MainActor
private enum ToolButtonTests {
    private static var checks = 0
    private static var skippedArtwork = false
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static func make(_ title: String = "") -> ToolButton {
        let button = ToolButton(title: title, target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 0, width: 54, height: 34)
        button.isBordered = false
        button.setButtonType(.toggle)
        return button
    }

    private static func raster(_ button: ToolButton, mask: Bool = false) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(button.bounds.width), pixelsHigh: Int(button.bounds.height),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(button.bounds)
        // Focus coverage must be opaque even if previous drawing left a
        // translucent tint in the context. Production mask owns its fill.
        NSColor.black.withAlphaComponent(mask ? 0.2 : 1).setFill()
        if mask { button.drawFocusRingMask() } else { button.draw(button.bounds) }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }

    private static func difference(_ a: NSColor, _ b: NSColor) -> CGFloat {
        abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent)
    }

    private static func pixels(_ rep: NSBitmapImageRep) -> Data {
        Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private static func image(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    static func main() {
        _ = NSApplication.shared
        appearanceAndRendering()
        originalImages()
        nativeActions()
        secondaryActions()
        keyboardFocus()
        contrast()
        print("ToolButtonTests: \(checks) checks passed" + (skippedArtwork ? "; original artwork pairs skipped" : ""))
    }

    private static func appearanceAndRendering() {
        let button = make()
        expect(button.cell is NSButtonCell, "AppKit owns the button cell")
        expect((button.font?.pointSize ?? 0) >= 18, "Default readable title size")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            button.appearance = appearance
            appearance.performAsCurrentDrawingAppearance {
                for state in [NSControl.StateValue.off, .on] {
                    button.state = state
                    button.isEnabled = true
                    button.highlight(false)
                    let normal = raster(button)
                    expect(color(normal, 0, 0).alphaComponent == 0, "Rounded corner stays transparent")
                    expect(color(normal, 6, 17).alphaComponent > 0.1, "Native semantic rounded background paints visibly")
                    button.highlight(true)
                    expect(button.state == state && button.cell!.isHighlighted, "Press does not toggle selection")
                    let pressed = raster(button)
                    expect(difference(color(normal, 6, 17), color(pressed, 6, 17)) > 0.025,
                           "Actual pressed background is visibly different in both appearances and states")
                    button.highlight(false)
                    expect(pixels(raster(button)) == pixels(normal), "Release restores exact unpressed raster")
                    button.isEnabled = false
                    let disabled = raster(button)
                    button.highlight(true)
                    expect(pixels(raster(button)) == pixels(disabled), "Disabled press cannot brighten the background")
                    expect(button.contentTintColor == .disabledControlTextColor, "Disabled label uses semantic native color")
                    expect(button.state == state, "Disabled rendering preserves selection")
                    button.highlight(false)
                }
            }
        }
        button.isEnabled = true
        button.state = .off
        let enabled = raster(button)
        button.isEnabled = false
        expect(button.focusRingMaskBounds.isEmpty && pixels(raster(button)) != pixels(enabled),
               "Programmatic enablement changes rendering and focus geometry")

        let text = make("Crop")
        text.font = .boldSystemFont(ofSize: 13)
        expect(text.font!.pointSize == 18 && NSFontManager.shared.traits(of: text.font!).contains(.boldFontMask),
               "Small caller font retains its face/weight at the readable minimum")
        text.font = nil
        expect(text.font!.pointSize >= 18, "Nil font cannot restore the small native fallback")
        text.font = .systemFont(ofSize: 18)
        text.frame.size.width = 100
        text.imagePosition = .noImage
        text.state = .on
        let selected = raster(text)
        expect(text.contentTintColor == ToolButton.textColor(on: .controlAccentColor), "Selected title retains contrast API")
        let blank = make()
        blank.frame = text.frame; blank.imagePosition = .noImage; blank.state = .on; blank.font = text.font
        expect(pixels(selected) != pixels(raster(blank)), "Native cell paints actual readable Crop glyphs over the same background")
    }

    private static func originalImages() {
        let button = make()
        let off = image(.red), on = image(.blue)
        button.image = off; button.alternateImage = on
        button.imagePosition = .imageOnly; button.imageScaling = .scaleNone
        button.state = .off
        let offColor = color(raster(button), 27, 17)
        expect(offColor.redComponent > 0.9 && offColor.blueComponent < 0.1, "Native cell renders off image")
        button.state = .on
        let onColor = color(raster(button), 27, 17)
        expect(onColor.blueComponent > 0.9 && onColor.redComponent < 0.1, "Native toggle cell renders alternate image")
        button.isEnabled = false
        let disabled = color(raster(button), 27, 17)
        expect(difference(disabled, onColor) > 0.1, "Disabled icon visibly dims")
        expect(button.image === off && button.alternateImage === on && button.state == .on,
               "Rendering does not replace assets or selection")

        // The aggregate runner compiles a frozen snapshot under build/, but
        // runs each suite from the repository root like the standalone command.
        // The git-ignored original/ archive is absent on a fresh clone: skip only the artwork pairs.
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("original/Skitch.app/Contents/Resources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: resources.path) else {
            print("SKIP ToolButtonTests original artwork pairs: \(resources.path) not present (original/ is git-ignored)")
            skippedArtwork = true
            return
        }
        for name in ["Arrow", "Brush", "Circle", "Cursor", "Eraser", "Fill", "Line", "Rect", "Text"] {
            guard let off = NSImage(contentsOf: resources.appendingPathComponent("ToolOff" + name + ".png")),
                  let on = NSImage(contentsOf: resources.appendingPathComponent("ToolOn" + name + ".png")) else {
                preconditionFailure("Original ToolOff\(name)/ToolOn\(name) PNG missing from the archive")
            }
            button.isEnabled = true; button.highlight(false)
            button.image = off; button.alternateImage = on; button.state = .off
            let normal = raster(button)
            button.state = .on
            let selected = raster(button)
            expect(pixels(normal) != pixels(selected), "Original \(name) pair has distinct native selected rendering")
            button.isEnabled = false
            expect(pixels(raster(button)) != pixels(selected), "Original \(name) selected icon visibly disables")
            expect(button.image === off && button.alternateImage === on, "Original \(name) image ownership preserved")
        }
    }

    private static func nativeActions() {
        let button = make(), target = ButtonTarget()
        button.target = target; button.action = #selector(ButtonTarget.choose(_:))
        button.performClick(nil)
        expect(target.states == [.on] && button.state == .on, "Native toggle changes state before target/action")
        button.performClick(nil)
        expect(target.states == [.on, .off] && button.state == .off, "Native second click retains caller-requested toggle semantics")
        expect(target.senders.allSatisfy { $0 === button }, "Native action sender is the control")
        button.isEnabled = false
        button.performClick(nil)
        expect(target.states == [.on, .off] && button.state == .off, "Disabled native click sends no action or state change")
        button.isEnabled = true
        button.highlight(true); _ = raster(button); button.highlight(false)
        expect(target.states == [.on, .off], "Painting/highlighting never sends actions")
        let reference = NSButton(title: "", target: nil, action: nil), referenceTarget = ButtonTarget()
        reference.target = referenceTarget; reference.action = #selector(ButtonTarget.choose(_:))
        reference.setButtonType(.momentaryPushIn)
        button.setButtonType(.momentaryPushIn)
        reference.performClick(nil)
        button.performClick(nil)
        expect(target.states.count == 3 && target.states.last == referenceTarget.states.last && button.state == reference.state,
               "Caller-requested momentary behavior matches an actual NSButton")
        button.state = .on
        _ = raster(button)
        expect(target.states.count == 3 && button.state == .on, "Programmatic selection does not send an action")
    }

    private static func keyboardFocus() {
        let button = make(), target = ButtonTarget()
        button.target = target; button.action = #selector(ButtonTarget.choose(_:))
        expect(button.focusRingType == .exterior, "Custom-drawn button opts into AppKit keyboard focus feedback")
        expect(button.focusRingMaskBounds == button.bounds.insetBy(dx: 1, dy: 1), "Focus mask follows exact rounded button bounds")
        let mask = raster(button, mask: true)
        expect(color(mask, 27, 17).alphaComponent > 0.99, "Focus mask paints actual production shape")
        expect(color(mask, 0, 0).alphaComponent == 0, "Focus mask excludes outer corners")
        let window = NonorderingButtonWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                             styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(button)
        expect(window.makeFirstResponder(button) && window.firstResponder === button, "Native responder chain can focus button without ordering a window")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                  isARepeat: false, keyCode: 49)!
        let reference = NSButton(title: "", target: nil, action: nil), referenceTarget = ButtonTarget()
        reference.setButtonType(.toggle)
        reference.target = referenceTarget; reference.action = #selector(ButtonTarget.choose(_:))
        window.contentView!.addSubview(reference)
        // An unordered window cannot prove system Space dispatch. Compare the
        // inherited event handling with NSButton; do not invent key mappings.
        button.keyDown(with: key)
        let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0.1,
                                 windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                 isARepeat: false, keyCode: 49)!
        button.keyUp(with: up)
        window.makeFirstResponder(reference)
        reference.keyDown(with: key); reference.keyUp(with: up)
        expect(target.states == referenceTarget.states && button.state == reference.state,
               "Inherited Space handling matches NSButton in the same unordered native window")
        window.makeFirstResponder(button)
        let beforeFocusTransfer = target.states
        window.makeFirstResponder(nil)
        expect(window.firstResponder !== button && target.states == beforeFocusTransfer, "Focus transfer itself never activates control")
        button.keyEquivalent = "a"; button.keyEquivalentModifierMask = []
        let equivalent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                         windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                         isARepeat: false, keyCode: 0)!
        let beforeEquivalent = target.states.count
        expect(button.performKeyEquivalent(with: equivalent) && target.states.count == beforeEquivalent + 1,
               "Caller-configured native key equivalent dispatches once")
        button.isEnabled = false
        expect(!button.performKeyEquivalent(with: equivalent) && target.states.count == beforeEquivalent + 1,
               "Disabled native key equivalent sends no action")
        expect(button.focusRingMaskBounds == .zero, "Disabled control has no focus-ring mask")
        let disabled = raster(button, mask: true)
        expect(color(disabled, 27, 17).alphaComponent == 0, "Disabled production focus mask paints nothing")
        button.isEnabled = true; button.frame.size = NSSize(width: 100, height: 40)
        expect(button.focusRingMaskBounds == NSRect(x: 1, y: 1, width: 98, height: 38), "Focus feedback follows resize without stored geometry or observers")
        expect(button.font!.pointSize >= 18, "Focus and resize never shrink readable text")
        button.frame.size = NSSize(width: 1, height: 1)
        expect(button.focusRingMaskBounds.isEmpty, "Tiny control cannot create invalid focus-mask geometry")
        expect(color(raster(button, mask: true), 0, 0).alphaComponent == 0, "Tiny control mask paints nothing")
    }

    private static func mouse(_ type: NSEvent.EventType, control: Bool = false) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: 20, y: 15),
                          modifierFlags: control ? .control : [], timestamp: 1, windowNumber: 0, context: nil,
                          eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    private static func secondaryActions() {
        let button = make(), primary = ButtonTarget(), alternate = ButtonTarget()
        button.target = primary; button.action = #selector(ButtonTarget.choose(_:))
        button.alternateTarget = alternate; button.alternateAction = #selector(ButtonTarget.choose(_:))
        let normal = raster(button)
        button.rightMouseDown(with: mouse(.rightMouseDown))
        expect(button.cell!.isHighlighted && button.state == .off && primary.states.isEmpty && alternate.states.isEmpty,
               "Inherited secondary press highlights without selecting or prematurely dispatching")
        expect(difference(color(normal, 6, 17), color(raster(button), 6, 17)) > 0.025,
               "Recovered alternate-action press receives the same visible feedback")
        button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(alternate.states == [.off] && primary.states.isEmpty && button.state == .off && !button.cell!.isHighlighted,
               "Recovered release dispatches alternate action only and clears pressed styling")
        expect(pixels(raster(button)) == pixels(normal), "Secondary release restores normal raster")
        button.mouseDown(with: mouse(.leftMouseDown, control: true))
        button.isEnabled = false
        expect(!button.cell!.isHighlighted, "ToolButton enablement preserves superclass cancellation of a secondary press")
        button.isEnabled = true
        button.mouseUp(with: mouse(.leftMouseUp))
        expect(alternate.states == [.off] && primary.states.isEmpty && button.state == .off,
               "Cancelled Control-click cannot resurrect either action when Control is released")

        let menu = NSMenu(title: "Arrow Head")
        menu.addItem(withTitle: "Standard", action: nil, keyEquivalent: "")
        button.menu = menu
        var presented = 0
        button.menuPresenter = { received, _, sender in
            expect(received === menu && sender === button, "Native inherited menu presenter receives actual tool/menu")
            presented += 1
        }
        button.rightMouseDown(with: mouse(.rightMouseDown))
        button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(presented == 1 && primary.states.isEmpty && alternate.states == [.off] && button.state == .off,
               "Context menu retains precedence over alternate action without tool-selection changes")
        expect(!button.cell!.isHighlighted, "Menu completion clears pressed feedback")
    }

    private static func contrast() {
        expect(ToolButton.textColor(on: .yellow) == .black, "Yellow requires dark selected text")
        expect(ToolButton.textColor(on: .blue) == .white, "Blue requires light selected text")
        expect(ToolButton.textColor(on: .white) == .black, "White requires dark selected text")
        expect(ToolButton.textColor(on: .black) == .white, "Black requires light selected text")
    }
}
#endif
