// Standalone checks: no NSApplication, window, event posting, or desktop input.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D CANVAS_NAVIGATOR_TESTS \
//   Sources/CanvasNavigator.swift tests/CanvasNavigatorTests.swift -o /tmp/opensnap-canvas-navigator-tests
// rtk proxy /tmp/opensnap-canvas-navigator-tests
#if CANVAS_NAVIGATOR_TESTS
import AppKit

@MainActor
private final class NavigatorImageProbe: NSImage {
    var destinations: [CGRect] = []
    var respectsFlipped = false

    nonisolated override func draw(in rect: NSRect, from source: NSRect, operation: NSCompositingOperation,
                                   fraction: CGFloat, respectFlipped: Bool, hints: [NSImageRep.HintKey: Any]?) {
        MainActor.assumeIsolated {
            destinations.append(rect)
            respectsFlipped = respectFlipped
            NSColor.systemBlue.setFill()
            rect.fill()
        }
    }
}

@main @MainActor
private enum CanvasNavigatorTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000_001 }
    static func near(_ a: CGPoint?, _ b: CGPoint) -> Bool {
        guard let a else { return false }
        return near(a.x, b.x) && near(a.y, b.y)
    }
    static func near(_ a: CGRect?, _ b: CGRect) -> Bool {
        guard let a else { return false }
        return near(a.minX, b.minX) && near(a.minY, b.minY)
            && near(a.width, b.width) && near(a.height, b.height)
    }

    static func mouse(_ type: NSEvent.EventType, at point: CGPoint, in view: NSView) throws -> NSEvent {
        // Convert back to the coordinate space used by locationInWindow. No window
        // is constructed and this event is only passed directly to this view.
        guard let event = NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1) else {
            throw Failure(description: "Cannot construct internal event")
        }
        return event
    }

    static func geometry() throws {
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 190)
        let doc = CGSize(width: 1000, height: 500)
        let image = CGRect(x: 12, y: 66, width: 196, height: 98)
        try expect(near(NavigatorGeometry.imageRect(documentSize: doc, bounds: bounds), image),
                   "Landscape fits whole canvas below header with bottom and side padding")
        try expect(near(NavigatorGeometry.imageRect(documentSize: CGSize(width: 500, height: 1000),
                   bounds: bounds), CGRect(x: 78.5, y: 52, width: 63, height: 126)), "Portrait is letterboxed")
        try expect(near(NavigatorGeometry.imageRect(documentSize: CGSize(width: 500, height: 500),
                   bounds: bounds), CGRect(x: 47, y: 52, width: 126, height: 126)), "Square is aspect fitted")
        try expect(near(NavigatorGeometry.imageRect(documentSize: doc,
                   bounds: bounds.offsetBy(dx: 30, dy: 40)), image.offsetBy(dx: 30, dy: 40)),
                   "Nonzero bounds origin is respected")
        try expect(near(NavigatorGeometry.viewportRect(viewport: CGRect(x: 250, y: 100, width: 400, height: 100),
                   documentSize: doc, imageRect: image), CGRect(x: 61, y: 85.6, width: 78.4, height: 19.6)),
                   "Nonuniform viewport uses document width and height independently")
        try expect(near(NavigatorGeometry.viewportRect(viewport: CGRect(x: -50, y: 450, width: 200, height: 200),
                   documentSize: doc, imageRect: image), CGRect(x: 12, y: 154.2, width: 29.4, height: 9.8)),
                   "Viewport clips negative origins and bottom overhang")
        try expect(near(NavigatorGeometry.viewportRect(viewport: CGRect(x: -100, y: -100, width: 2000, height: 1000),
                   documentSize: doc, imageRect: image), image), "Oversized viewport highlight fills canvas")
        try expect(NavigatorGeometry.viewportRect(viewport: CGRect(x: 1000, y: 0, width: 10, height: 10),
                   documentSize: doc, imageRect: image) == nil, "Disjoint viewport has no highlight")

        let viewportSize = CGSize(width: 200, height: 100)
        let corners = [(CGPoint(x: image.minX, y: image.minY), CGPoint.zero),
                       (CGPoint(x: image.maxX, y: image.minY), CGPoint(x: 800, y: 0)),
                       (CGPoint(x: image.minX, y: image.maxY), CGPoint(x: 0, y: 400)),
                       (CGPoint(x: image.maxX, y: image.maxY), CGPoint(x: 800, y: 400)),
                       (CGPoint(x: image.midX, y: image.midY), CGPoint(x: 400, y: 200)),
                       (CGPoint(x: -1000, y: 1000), CGPoint(x: 0, y: 400))]
        for (pointer, expected) in corners {
            try expect(near(NavigatorGeometry.targetOrigin(pointer: pointer, documentSize: doc,
                       viewportSize: viewportSize, imageRect: image), expected), "Pointer center and corner clamp: \(pointer)")
        }
        try expect(near(NavigatorGeometry.targetOrigin(pointer: CGPoint(x: image.midX, y: image.midY),
                   documentSize: doc, viewportSize: CGSize(width: 1600, height: 100), imageRect: image),
                   CGPoint(x: 0, y: 200)), "Oversized width only clamps horizontal axis")
        try expect(near(NavigatorGeometry.targetOrigin(pointer: CGPoint(x: image.maxX, y: image.maxY),
                   documentSize: doc, viewportSize: CGSize(width: 200, height: 600), imageRect: image),
                   CGPoint(x: 800, y: 0)), "Oversized height only clamps vertical axis")
        try expect(near(NavigatorGeometry.targetOrigin(pointer: CGPoint(x: image.midX, y: image.midY),
                   documentSize: doc, viewportSize: doc, imageRect: image), .zero), "Whole canvas cannot pan")

        for value: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            for size in [CGSize(width: value, height: 500), CGSize(width: 1000, height: value)] {
                try expect(NavigatorGeometry.imageRect(documentSize: size, bounds: bounds) == nil, "Invalid document rejected")
                try expect(NavigatorGeometry.viewportRect(viewport: CGRect(origin: .zero, size: viewportSize),
                           documentSize: size, imageRect: image) == nil, "Invalid document highlight rejected")
                try expect(NavigatorGeometry.targetOrigin(pointer: .zero, documentSize: doc,
                           viewportSize: size, imageRect: image) == nil, "Invalid viewport size rejected")
                try expect(NavigatorGeometry.targetOrigin(pointer: .zero, documentSize: size,
                           viewportSize: viewportSize, imageRect: image) == nil, "Invalid navigation document rejected")
            }
        }
        let invalidRects = [CGRect.zero, CGRect.null, CGRect.infinite,
                            CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                            CGRect(x: 0, y: CGFloat.infinity, width: 10, height: 10),
                            CGRect(x: 0, y: 0, width: -1, height: 10),
                            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                                   width: CGFloat.greatestFiniteMagnitude, height: 10)]
        for rect in invalidRects {
            try expect(NavigatorGeometry.imageRect(documentSize: doc, bounds: rect) == nil, "Invalid bounds rejected: \(rect)")
            try expect(NavigatorGeometry.viewportRect(viewport: rect, documentSize: doc, imageRect: image) == nil,
                       "Invalid viewport rejected")
            try expect(NavigatorGeometry.targetOrigin(pointer: .zero, documentSize: doc,
                       viewportSize: viewportSize, imageRect: rect) == nil, "Invalid thumbnail rectangle rejected")
            try expect(NavigatorGeometry.viewportRect(viewport: CGRect(origin: .zero, size: viewportSize),
                       documentSize: doc, imageRect: rect) == nil, "Invalid highlight destination rejected")
        }
        for pointer in [CGPoint(x: CGFloat.nan, y: 10), CGPoint(x: 10, y: CGFloat.infinity),
                        CGPoint(x: -CGFloat.infinity, y: 10)] {
            try expect(NavigatorGeometry.targetOrigin(pointer: pointer, documentSize: doc,
                       viewportSize: viewportSize, imageRect: image) == nil, "Nonfinite pointer rejected")
        }
        try expect(NavigatorGeometry.imageRect(documentSize: doc,
                   bounds: CGRect(x: 0, y: 0, width: 24, height: 190)) == nil, "No horizontal drawing space")
        try expect(NavigatorGeometry.imageRect(documentSize: doc,
                   bounds: CGRect(x: 0, y: 0, width: 220, height: 64)) == nil, "No space below readable header")
        let huge = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude / 2)
        try expect(near(NavigatorGeometry.imageRect(documentSize: huge, bounds: bounds), image), "Large finite aspect fit")
        let extreme = NavigatorGeometry.targetOrigin(pointer: CGPoint(x: CGFloat.greatestFiniteMagnitude,
            y: -CGFloat.greatestFiniteMagnitude), documentSize: huge, viewportSize: viewportSize, imageRect: image)
        try expect(extreme?.x.isFinite == true && extreme?.y == 0, "Extreme finite pointer remains bounded")

        // Check many aspect ratios and both independent oversized viewport axes.
        for docSize in [CGSize(width: 123, height: 987), CGSize(width: 987, height: 123), doc] {
            guard let rect = NavigatorGeometry.imageRect(documentSize: docSize, bounds: bounds) else {
                throw Failure(description: "Missing valid image rectangle")
            }
            for size in [CGSize(width: 17, height: 91), CGSize(width: 2000, height: 10),
                         CGSize(width: 10, height: 2000), CGSize(width: 2000, height: 2000)] {
                for fraction: CGFloat in [-2, 0, 0.25, 0.5, 0.75, 1, 3] {
                    let pointer = CGPoint(x: rect.minX + fraction * rect.width, y: rect.minY + fraction * rect.height)
                    guard let origin = NavigatorGeometry.targetOrigin(pointer: pointer, documentSize: docSize,
                        viewportSize: size, imageRect: rect) else { throw Failure(description: "Valid target rejected") }
                    try expect(origin.x.isFinite && origin.y.isFinite && origin.x >= 0 && origin.y >= 0
                        && origin.x <= max(0, docSize.width - size.width)
                        && origin.y <= max(0, docSize.height - size.height), "Navigation range invariant")
                }
            }
        }
    }

    static func interaction() throws {
        let view = CanvasNavigator(frame: CGRect(x: 40, y: 30, width: 220, height: 190))
        let preview = NSImage(size: CGSize(width: 100, height: 50))
        let doc = CGSize(width: 1000, height: 500)
        let initial = CGRect(x: 10, y: 20, width: 200, height: 100)
        var delivered: [CGPoint] = []
        view.onNavigate = { delivered.append($0) }
        view.update(image: preview, documentSize: doc, viewport: initial)
        let rect = NavigatorGeometry.imageRect(documentSize: doc, bounds: view.bounds)!
        try expect(view.window == nil && view.isFlipped && view.acceptsFirstResponder, "Unattached top-left native view")
        try expect(view.intrinsicContentSize == CGSize(width: 220, height: 190), "Typical overview size")
        try expect(view.image === preview && view.documentSize == doc && view.viewport == initial, "Public update payload")
        try expect(view.accessibilityLabel() == "Overview", "Accessible label")
        try expect((view.accessibilityValue() as? String)?.contains("x 10, y 20, width 200, height 100") == true,
                   "Accessible value describes viewport in document coordinates")
        try expect(view.accessibilityCustomActions()?.map(\.name) == ["Center viewport", "Pan left", "Pan right", "Pan up", "Pan down"],
                   "Meaningful accessible navigation actions")
        try expect(view.accessibilityPerformPress(), "Accessible center action succeeds")
        try expect(near(delivered.last, CGPoint(x: 400, y: 200)), "Accessible center maps to document")
        delivered.removeAll()

        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        try expect(delivered.isEmpty, "Drag without click is ignored")
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20), in: view))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        try expect(delivered.isEmpty, "Header click never begins navigation")
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        try expect(near(delivered.last, CGPoint(x: 400, y: 200)), "Click centers viewport")
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.maxX + 100, y: rect.maxY + 100), in: view))
        try expect(near(delivered.last, CGPoint(x: 800, y: 400)), "Drag outside bottom-right clamps")
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.minX - 100, y: rect.minY - 100), in: view))
        try expect(near(delivered.last, .zero), "Drag outside top-left clamps")
        view.mouseUp(with: try mouse(.leftMouseUp, at: .zero, in: view))
        let count = delivered.count
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        try expect(delivered.count == count && count == 3, "Mouse-up ends tracking without duplicate callback")
        try expect(view.image === preview && view.viewport == initial, "Mouse navigation retains supplied image and parent viewport")

        // Reentrant parent updates keep tracking when document dimensions match.
        view.onNavigate = { point in
            delivered.append(point)
            view.update(image: preview, documentSize: doc, viewport: CGRect(origin: point, size: initial.size))
        }
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.maxX, y: rect.minY), in: view))
        try expect(near(delivered.last, CGPoint(x: 800, y: 0)) && delivered.count == count + 2,
                   "Parent update during callback does not interrupt drag")
        view.documentSize = CGSize(width: 500, height: 250)
        let before = delivered.count
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: rect.midX, y: rect.midY), in: view))
        try expect(delivered.count == before, "Document change cancels stale drag")

        view.onNavigate = { delivered.append($0) }
        view.update(image: nil, documentSize: doc, viewport: CGRect(x: 0, y: 0, width: 1600, height: 600))
        try expect(view.accessibilityPerformPress() && near(delivered.last, .zero), "Oversized native viewport clamps to zero")
        view.viewport = .zero
        try expect(!view.accessibilityPerformPress(), "Invalid viewport cannot navigate")
        try expect(view.accessibilityValue() as? String == "No visible canvas region", "Accessible empty state")
        view.update(image: preview, documentSize: doc, viewport: initial)
        view.onNavigate = nil
        try expect(!view.accessibilityPerformPress(), "Missing parent callback reports unavailable action")

        view.onNavigate = { delivered.append($0) }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        view.keyDown(with: key)
        try expect(near(delivered.last, CGPoint(x: 110, y: 20)), "Keyboard pan advances 10 percent of canvas width")

        // Exercise every accessible selector without posting input to the system.
        view.viewport = CGRect(x: 400, y: 200, width: 200, height: 100)
        let actionTargets: [(String, CGPoint)] = [
            ("panLeft", CGPoint(x: 300, y: 200)), ("panRight", CGPoint(x: 500, y: 200)),
            ("panUp", CGPoint(x: 400, y: 150)), ("panDown", CGPoint(x: 400, y: 250))
        ]
        for (name, expected) in actionTargets {
            let selector = NSSelectorFromString(name)
            try expect(view.responds(to: selector), "Accessible action selector exists")
            // Bool-returning Objective-C selectors must not be called with perform,
            // whose object return contract is incompatible with these methods.
            typealias Action = @convention(c) (AnyObject, Selector) -> Bool
            let invoke = unsafeBitCast(view.method(for: selector), to: Action.self)
            try expect(invoke(view, selector) && near(delivered.last, expected), "Accessible \(name) maps and clamps")
        }
        view.viewport = CGRect(x: -CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude,
                               width: 200, height: 100)
        view.keyDown(with: key)
        try expect(near(delivered.last, CGPoint(x: 100, y: 400)), "Keyboard safely clamps stale finite origins")
        view.viewport = CGRect(x: CGFloat.nan, y: 0, width: 200, height: 100)
        let beforeInvalidKey = delivered.count
        view.keyDown(with: key)
        try expect(delivered.count == beforeInvalidKey, "Nonfinite keyboard origin does not navigate")
    }

    static func offscreenDrawing() throws {
        let view = CanvasNavigator(frame: CGRect(x: 0, y: 0, width: 220, height: 190))
        let preview = NavigatorImageProbe(size: CGSize(width: 2000, height: 1000))
        view.update(image: preview, documentSize: CGSize(width: 1000, height: 500),
                    viewport: CGRect(x: 250, y: 100, width: 200, height: 100))
        guard let bitmap = CGContext(data: nil, width: 220, height: 190, bitsPerComponent: 8,
            bytesPerRow: 220 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "Cannot create local drawing context")
        }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        defer { NSGraphicsContext.current = previous }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            guard let appearance = NSAppearance(named: name) else {
                throw Failure(description: "Missing native appearance")
            }
            appearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
        }
        try expect(preview.destinations.count == 2 && preview.respectsFlipped,
                   "Both native appearances draw supplied image with top-left orientation")
        try expect(preview.destinations.allSatisfy { near($0, CGRect(x: 12, y: 66, width: 196, height: 98)) },
                   "Full supplied image draws only into bounded thumbnail destination")
        view.onNavigate = { _ in }
        let point = CGPoint(x: 110, y: 115)
        view.mouseDown(with: try mouse(.leftMouseDown, at: point, in: view))
        for _ in 0..<100 {
            view.mouseDragged(with: try mouse(.leftMouseDragged, at: point, in: view))
        }
        try expect(preview.destinations.count == 2 && view.image === preview,
                   "Mouse handlers do not draw, create, or replace preview images")
        view.documentSize = .zero
        view.draw(view.bounds)
        try expect(preview.destinations.count == 2, "Invalid document never draws thumbnail")
    }

    static func main() throws {
        try geometry()
        try interaction()
        try offscreenDrawing()
        print("CanvasNavigatorTests: \(checks) checks passed (standalone; no windows or desktop input)")
    }
}
#endif
