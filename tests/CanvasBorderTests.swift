// Internal native events only: no event posting, visible UI, or desktop input.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D CANVAS_BORDER_TESTS \
//   Sources/WindowSizing.swift Sources/CanvasBorderView.swift \
//   tests/CanvasBorderTests.swift -o /tmp/skitch-canvas-border-tests
// /tmp/skitch-canvas-border-tests
#if CANVAS_BORDER_TESTS
import AppKit

@main @MainActor
private enum CanvasBorderTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private enum Callback: Equatable {
        case begin(CanvasBorderHandle, NSEvent.ModifierFlags)
        case drag(CGPoint, NSEvent.ModifierFlags)
        case end(cancelled: Bool)
    }

    @MainActor
    private final class Fixture {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 440, height: 320))
        let canvas = NSView(frame: CGRect(x: 37, y: 41, width: 240, height: 160))
        let border = CanvasBorderView(frame: CGRect(x: 37, y: 41, width: 240, height: 160))
        var callbacks: [Callback] = []
        var acceptsBegin = true

        init() {
            host.addSubview(canvas)
            host.addSubview(border)
            border.onBegin = { [unowned self] handle, flags in
                callbacks.append(.begin(handle, flags))
                return acceptsBegin
            }
            border.onDrag = { [unowned self] delta, flags in callbacks.append(.drag(delta, flags)) }
            border.onEnd = { [unowned self] cancelled in callbacks.append(.end(cancelled: cancelled)) }
        }

        func mouse(_ type: NSEvent.EventType, at local: CGPoint,
                   flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try CanvasBorderTests.mouse(type, location: border.convert(local, to: nil),
                                        windowNumber: border.window?.windowNumber ?? 0, flags: flags)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static func mouse(_ type: NSEvent.EventType, location: CGPoint,
                              windowNumber: Int = 0, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags,
            timestamp: 1, windowNumber: windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else {
            throw Failure(description: "Cannot create internal mouse event")
        }
        return event
    }

    private static func escape() throws -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 2, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
            throw Failure(description: "Cannot create internal Escape event")
        }
        return event
    }

    private static let handles: [(CGPoint, CanvasBorderHandle)] = [
        (CGPoint(x: 12, y: 12), .corner(.topLeft)),
        (CGPoint(x: 228, y: 12), .corner(.topRight)),
        (CGPoint(x: 12, y: 148), .corner(.bottomLeft)),
        (CGPoint(x: 228, y: 148), .corner(.bottomRight)),
        (CGPoint(x: 2, y: 80), .edge(.left)),
        (CGPoint(x: 238, y: 80), .edge(.right)),
        (CGPoint(x: 120, y: 2), .edge(.top)),
        (CGPoint(x: 120, y: 158), .edge(.bottom))
    ]

    private static func hitTesting() throws {
        let f = Fixture()
        try expect(f.border.isFlipped && f.border.acceptsFirstResponder,
                   "Border uses top-left coordinates and can receive Escape")
        for (point, handle) in handles {
            let parentPoint = f.border.convert(point, to: f.host)
            try expect(f.border.handle(at: point) == handle, "Handle classification: \(handle)")
            try expect(f.border.hitTest(parentPoint) === f.border,
                       "Offset, flipped border hit: \(handle)")
            try expect(f.host.hitTest(parentPoint) === f.border, "Border wins over underlying canvas: \(handle)")
        }
        for point in [CGPoint(x: 120, y: 80), CGPoint(x: 8, y: 80),
                      CGPoint(x: 232, y: 80), CGPoint(x: 120, y: 8),
                      CGPoint(x: 120, y: 152), CGPoint(x: 16, y: 16)] {
            let parentPoint = f.border.convert(point, to: f.host)
            try expect(f.border.handle(at: point) == nil, "Interior has no handle: \(point)")
            try expect(f.border.hitTest(parentPoint) == nil, "Interior passes through border: \(point)")
            try expect(f.host.hitTest(parentPoint) === f.canvas, "Interior reaches editable canvas: \(point)")
        }
        for point in [CGPoint(x: -1, y: 80), CGPoint(x: 241, y: 80),
                      CGPoint(x: 120, y: -1), CGPoint(x: 120, y: 161)] {
            try expect(f.border.handle(at: point) == nil, "Outside bounds has no handle")
            try expect(f.border.hitTest(f.border.convert(point, to: f.host)) == nil,
                       "Outside bounds cannot capture input")
        }
        f.border.isHidden = true
        for (point, _) in handles {
            let parentPoint = f.border.convert(point, to: f.host)
            try expect(f.border.hitTest(parentPoint) == nil, "Hidden border ignores handle hit")
            try expect(f.host.hitTest(parentPoint) === f.canvas, "Hidden border lets canvas receive handle hit")
        }
        f.border.isHidden = false
        try expect(f.host.hitTest(f.border.convert(handles[0].0, to: f.host)) === f.border,
                   "Unhiding restores border hit testing")
        try expect(f.callbacks.isEmpty, "Hit testing never starts or commits a gesture")
    }

    private static func beginAndCommit() throws {
        let flags: NSEvent.ModifierFlags = [.option, .shift, .command]
        for (point, handle) in handles {
            let f = Fixture()
            f.border.mouseDown(with: try f.mouse(.leftMouseDown, at: point, flags: flags))
            try expect(f.callbacks == [.begin(handle, flags)], "Down passes exact handle and flags: \(handle)")
            let up = try f.mouse(.leftMouseUp, at: point, flags: [])
            f.border.mouseUp(with: up)
            try expect(f.callbacks == [.begin(handle, flags), .end(cancelled: false)],
                       "Accepted click commits exactly once without needing a drag")
            f.border.mouseUp(with: up)
            f.border.cancelOperation(nil)
            f.border.mouseDragged(with: try f.mouse(.leftMouseDragged, at: CGPoint(x: 100, y: 100)))
            try expect(f.callbacks == [.begin(handle, flags), .end(cancelled: false)],
                       "Repeated up, cancel and late drag cannot finish an ended gesture again")
        }
    }

    private static func rejectedDown() throws {
        let point = handles[0].0
        let f = Fixture()
        let drag = try f.mouse(.leftMouseDragged, at: CGPoint(x: 90, y: 70), flags: .option)
        let up = try f.mouse(.leftMouseUp, at: point)
        f.border.mouseDragged(with: drag)
        f.border.mouseUp(with: up)
        f.border.keyDown(with: try escape())
        f.border.cancelOperation(nil)
        try expect(f.callbacks.isEmpty, "Idle drag, up, and cancellation emit no callbacks")

        f.acceptsBegin = false
        f.border.mouseDown(with: try f.mouse(.leftMouseDown, at: point, flags: .control))
        try expect(f.callbacks == [.begin(.corner(.topLeft), .control)], "Parent may reject begin with flags")
        f.border.mouseDragged(with: drag)
        f.border.mouseUp(with: up)
        f.border.keyDown(with: try escape())
        try expect(f.callbacks == [.begin(.corner(.topLeft), .control)],
                   "Rejected down does not arm drag, commit, or cancel")

        f.callbacks.removeAll()
        f.acceptsBegin = true
        for (type, local) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 120, y: 80)),
                              (.leftMouseDown, CGPoint(x: -1, y: 12)),
                              (.rightMouseDown, point), (.otherMouseDown, point)] {
            let down: NSEvent
            if type == .leftMouseDown {
                down = try f.mouse(type, at: local)
            } else {
                // mouseEvent(with:) gives even right/other events button zero.
                // Construct actual button metadata without posting the event anywhere.
                let synthetic = try f.mouse(type, at: local)
                guard let cgEvent = synthetic.cgEvent else {
                    throw Failure(description: "Cannot obtain internal mouse event metadata")
                }
                let button: Int64 = type == .rightMouseDown ? 1 : 2
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: button)
                guard let event = NSEvent(cgEvent: cgEvent) else {
                    throw Failure(description: "Cannot create internal non-primary event")
                }
                down = event
                try expect(down.buttonNumber == Int(button) && down.type == type,
                           "Constructed event has exact non-primary button metadata")
                try expect(f.border.handle(at: f.border.convert(down.locationInWindow, from: nil))
                           == .corner(.topLeft), "Non-primary rejection is tested inside a valid handle")
            }
            f.border.mouseDown(with: down)
            f.border.mouseDragged(with: drag)
            f.border.mouseUp(with: up)
            f.border.cancelOperation(nil)
            try expect(f.callbacks.isEmpty, "Invalid down is rejected before begin and never arms tracking: \(type)")
        }
        f.border.onBegin = nil
        f.border.mouseDown(with: try f.mouse(.leftMouseDown, at: point))
        f.border.mouseDragged(with: drag)
        f.border.mouseUp(with: up)
        try expect(f.callbacks.isEmpty, "Missing begin callback cannot authorize a gesture")

        // Restore the callback after rejection to prove the next valid gesture can start.
        f.border.onBegin = { handle, flags in
            f.callbacks.append(.begin(handle, flags))
            return true
        }
        defer { f.border.onBegin = nil }
        f.border.mouseDown(with: try f.mouse(.leftMouseDown, at: point))
        f.border.mouseUp(with: up)
        try expect(f.callbacks == [.begin(.corner(.topLeft), []), .end(cancelled: false)],
                   "Valid down after rejection starts a fresh gesture")
    }

    private static func screenDeltasAndDynamicFlags() throws {
        // NSApplication initialization supplies AppKit internals; it is never run or activated.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 400, y: 300, width: 440, height: 320),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let f = Fixture()
        window.contentView = f.host
        try expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow,
                   "Coordinate fixture starts hidden and inactive")
        let down = try f.mouse(.leftMouseDown, at: handles[0].0, flags: .command)
        f.border.mouseDown(with: down)
        try expect(f.callbacks == [.begin(.corner(.topLeft), .command)], "Screen gesture starts with down flags")

        // Expected deltas are deliberately fixed, rather than calculated with the code under test.
        // Movement of the window and view makes a local-space implementation fail this test.
        window.setFrameOrigin(CGPoint(x: window.frame.minX + 100, y: window.frame.minY - 50))
        f.border.setFrameOrigin(CGPoint(x: 57, y: 61))
        let firstLocation = CGPoint(x: down.locationInWindow.x + 7, y: down.locationInWindow.y - 11)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: firstLocation,
                                              windowNumber: window.windowNumber, flags: .option))
        try expect(f.callbacks == [.begin(.corner(.topLeft), .command),
                                   .drag(CGPoint(x: 107, y: 61), .option)],
                   "Drag measures screen motion from down with positive Y down")
        window.setFrameOrigin(CGPoint(x: window.frame.minX - 140, y: window.frame.minY + 80))
        let secondLocation = CGPoint(x: down.locationInWindow.x - 13, y: down.locationInWindow.y + 17)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: secondLocation,
                                              windowNumber: window.windowNumber, flags: [.shift, .control]))
        try expect(f.callbacks.last == .drag(CGPoint(x: -53, y: -47), [.shift, .control]),
                   "Second drag stays cumulative from down, with negative X left and Y up")
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: secondLocation,
                                              windowNumber: window.windowNumber, flags: []))
        try expect(f.callbacks.last == .drag(CGPoint(x: -53, y: -47), []),
                   "Releasing modifiers at the same point delivers current flags and cumulative delta")
        let up = try mouse(.leftMouseUp, location: secondLocation, windowNumber: window.windowNumber)
        f.border.mouseUp(with: up)
        let expected: [Callback] = [.begin(.corner(.topLeft), .command),
            .drag(CGPoint(x: 107, y: 61), .option),
            .drag(CGPoint(x: -53, y: -47), [.shift, .control]),
            .drag(CGPoint(x: -53, y: -47), []), .end(cancelled: false)]
        try expect(f.callbacks == expected, "Drag gesture delivers current flags in order and one commit")
        f.border.mouseUp(with: up)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: firstLocation,
                                              windowNumber: window.windowNumber))
        try expect(f.callbacks == expected, "Mouse-up clears screen tracking")
        try expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow,
                   "Window stays hidden and inactive throughout internal events")
    }

    private static func windowMovesDuringBegin() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 400, y: 300, width: 440, height: 320),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let f = Fixture()
        window.contentView = f.host
        try expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow,
                   "Begin-resize fixture starts hidden and inactive")

        let down = try f.mouse(.leftMouseDown, at: CGPoint(x: 228, y: 12), flags: .shift)
        // Capture the physical pointer before the parent performs its Shift resize.
        let originalScreenPoint = window.convertPoint(toScreen: down.locationInWindow)
        let oldFrame = window.frame
        let resizedFrame = CGRect(x: oldFrame.minX + 137, y: oldFrame.minY - 83,
                                  width: oldFrame.width + 200, height: oldFrame.height + 120)
        f.border.onBegin = { [unowned f, unowned window] handle, flags in
            f.callbacks.append(.begin(handle, flags))
            window.setFrame(resizedFrame, display: false)
            return true
        }
        f.border.mouseDown(with: down)
        try expect(f.callbacks == [.begin(.corner(.topRight), .shift)],
                   "Shift begin is delivered before the parent moves and resizes its window")
        try expect(window.frame == resizedFrame,
                   "Parent actually moves and resizes the hidden window inside onBegin")
        try expect(window.convertPoint(toScreen: down.locationInWindow) != originalScreenPoint,
                   "Reinterpreting down after onBegin would give a different screen point")

        // Subsequent events describe physical screen points, converted using the new frame.
        let stationary = window.convertPoint(fromScreen: originalScreenPoint)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: stationary,
                                              windowNumber: window.windowNumber, flags: .shift))
        try expect(f.callbacks.last == .drag(.zero, .shift),
                   "Stationary pointer has zero drag delta despite onBegin window movement")
        let movedScreenPoint = CGPoint(x: originalScreenPoint.x + 19, y: originalScreenPoint.y - 23)
        let moved = window.convertPoint(fromScreen: movedScreenPoint)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: moved,
                                              windowNumber: window.windowNumber, flags: .option))
        try expect(f.callbacks.last == .drag(CGPoint(x: 19, y: 23), .option),
                   "Drag delta excludes onBegin window movement and uses top-left screen coordinates")
        let returnedScreenPoint = CGPoint(x: originalScreenPoint.x - 11, y: originalScreenPoint.y + 7)
        let returned = window.convertPoint(fromScreen: returnedScreenPoint)
        f.border.mouseDragged(with: try mouse(.leftMouseDragged, location: returned,
                                              windowNumber: window.windowNumber))
        let up = try mouse(.leftMouseUp, location: returned, windowNumber: window.windowNumber)
        f.border.mouseUp(with: up)
        let expected: [Callback] = [.begin(.corner(.topRight), .shift), .drag(.zero, .shift),
            .drag(CGPoint(x: 19, y: 23), .option), .drag(CGPoint(x: -11, y: -7), []),
            .end(cancelled: false)]
        try expect(f.callbacks == expected,
                   "Begin resize preserves original cumulative screen anchor, dynamic flags and one commit")
        f.border.mouseUp(with: up)
        try expect(f.callbacks == expected, "Begin-resize gesture cannot commit twice")
        try expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow,
                   "Begin-resize window remains hidden and inactive throughout internal events")
    }

    private static func escapeCancellation() throws {
        let f = Fixture()
        let point = CGPoint(x: 120, y: 2)
        let down = try f.mouse(.leftMouseDown, at: point, flags: .option)
        let drag = try f.mouse(.leftMouseDragged, at: CGPoint(x: 125, y: 11), flags: .shift)
        let up = try f.mouse(.leftMouseUp, at: point)
        let esc = try escape()
        f.border.mouseDown(with: down)
        f.border.mouseDragged(with: drag)
        f.border.keyDown(with: esc)
        let expected: [Callback] = [.begin(.edge(.top), .option),
                                   .drag(CGPoint(x: 5, y: 9), .shift), .end(cancelled: true)]
        try expect(f.callbacks == expected, "Escape cancels an active gesture once after its preview")
        f.border.keyDown(with: esc)
        f.border.cancelOperation(nil)
        f.border.mouseDragged(with: drag)
        f.border.mouseUp(with: up)
        f.border.mouseUp(with: up)
        try expect(f.callbacks == expected, "Escape clears tracking: no later drag or up commit")

        f.border.mouseDown(with: down)
        f.border.mouseUp(with: up)
        try expect(f.callbacks == expected + [.begin(.edge(.top), .option), .end(cancelled: false)],
                   "Next gesture commits independently after cancellation")

        f.callbacks.removeAll()
        f.border.mouseDown(with: down)
        f.border.keyDown(with: esc)
        f.border.mouseUp(with: up)
        try expect(f.callbacks == [.begin(.edge(.top), .option), .end(cancelled: true)],
                   "Escape before any drag cancels once without a commit")
    }

    static func main() throws {
        try hitTesting()
        try beginAndCommit()
        try rejectedDown()
        try screenDeltasAndDynamicFlags()
        try windowMovesDuringBegin()
        try escapeCancellation()
        print("CanvasBorderTests: \(checks) checks passed (internal events; hidden window; no desktop input)")
    }
}
#endif
