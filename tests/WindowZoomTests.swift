#if WINDOW_ZOOM_TESTS
import AppKit

final class ZoomTestPanel: NSPanel {
    var fronts = 0
    var hides = 0
    var closes = 0
    override func orderFrontRegardless() { fronts += 1 }
    override func orderOut(_ sender: Any?) { hides += 1 }
    override func close() { closes += 1 }
}

@main @MainActor
enum WindowZoomTests {
    static var checks = 0
    struct Failure: Error { let message: String }
    static func expect(_ value: Bool, _ message: String) throws {
        checks += 1
        if !value { throw Failure(message: message) }
    }
    static func near(_ value: CGFloat, _ expected: CGFloat) -> Bool { abs(value-expected) < 0.00001 }
    static func image() -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (color, rect) in [(NSColor.red, CGRect(x: 0, y: 0, width: 32, height: 24)),
                              (.green, CGRect(x: 32, y: 0, width: 32, height: 24)),
                              (.blue, CGRect(x: 0, y: 24, width: 32, height: 24)),
                              (.yellow, CGRect(x: 32, y: 24, width: 32, height: 24))] {
            context.setFillColor(color.cgColor); context.fill(rect)
        }
        return context.makeImage()!
    }
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = image.dataProvider!.data! as Data, i = y*image.bytesPerRow+x*4
        return Array(bytes[i..<i+4])
    }
    static func main() throws {
        _ = NSApplication.shared
        let full = CGRect(x: 100, y: 200, width: 800, height: 600)
        let small = CGRect(x: 1000, y: 50, width: 128, height: 90)
        let first = WindowZoomCorners.frame(source: full, destination: small, direction: .shrink, index: 0, count: 25)
        let last = WindowZoomCorners.frame(source: full, destination: small, direction: .shrink, index: 25, count: 25)
        try expect(first.bottomLeft == CGPoint(x: 100, y: 200) && first.topRight == CGPoint(x: 900, y: 800), "Shrink begins at original corners")
        try expect(last.bottomLeft == CGPoint(x: 1000, y: 50) && last.topRight == CGPoint(x: 1128, y: 140), "Shrink ends at thumbnail corners")
        let sample = WindowZoomCorners.frame(source: full, destination: small, direction: .shrink, index: 6, count: 25)
        try expect(near(sample.bottomLeft.x, 316) && near(sample.bottomLeft.y, 126.51530771650465), "Recovered disappear lower-left uses linear x and square-root y")
        try expect(near(sample.bottomRight.x, 954.72), "Recovered disappear lower-right x")
        try expect(near(sample.topLeft.x, 540.908153700972) && near(sample.topLeft.y, 641.6), "Recovered disappear upper-left uses square-root x and linear y")
        try expect(near(sample.topRight.x, 1011.696732270913), "Recovered disappear upper-right x")
        let restore = WindowZoomCorners.frame(source: small, destination: full, direction: .restore, index: 3, count: 15)
        try expect(near(restore.bottomLeft.x, 820) && near(restore.bottomLeft.y, 56), "Recovered appear lower-left uses linear x and quadratic y")
        try expect(near(restore.bottomRight.x, 1082.4), "Recovered appear lower-right x")
        try expect(near(restore.topLeft.x, 964) && near(restore.topLeft.y, 272), "Recovered appear upper-left uses quadratic x and linear y")
        try expect(near(restore.topRight.x, 1118.88), "Recovered appear upper-right x")
        try expect(WindowZoomCorners.frame(source: full, destination: small, direction: .shrink, index: -4, count: 25) == first, "Negative frame cannot extrapolate")
        try expect(WindowZoomCorners.frame(source: full, destination: small, direction: .shrink, index: 90, count: 25) == last, "Late frame cannot extrapolate")
        try expect(first.bounds == full && last.bounds == small, "Corner bounds retain absolute screen origin")
        let pixels = image(), input = NSImage(cgImage: pixels, size: NSSize(width: 64, height: 48))
        let source = CGRect(x: 100, y: 200, width: 64, height: 48), target = CGRect(x: 300, y: 20, width: 32, height: 24)
        let view = WindowZoomView(frame: source.union(target), image: pixels,
                                  corners: .frame(source: source, destination: target, direction: .shrink, index: 0, count: 25))
        let (initialPixels, initialRect) = view.renderedFrame(scale: 1)!
        try expect(initialPixels.width == 64 && initialPixels.height == 48 && initialRect.origin == CGPoint(x: 0, y: 180), "Snapshot projection retains size and panel-relative origin")
        for (x, y) in [(8, 8), (48, 8), (8, 36), (48, 36)] {
            try expect(pixel(initialPixels, x, y) == pixel(pixels, x, y), "Projection cannot mirror or rotate source quadrants")
        }
        view.corners = .frame(source: source, destination: target, direction: .shrink, index: 25, count: 25)
        let (tiny, tinyRect) = view.renderedFrame(scale: 1)!
        try expect(tiny.width == 32 && tiny.height == 24 && tinyRect.origin == CGPoint(x: 200, y: 0), "Final projection places the thumbnail at the absolute target")
        for (x, y) in [(4, 4), (24, 4), (4, 18), (24, 18)] {
            try expect(pixel(tiny, x, y) == pixel(pixels, x*2, y*2), "Thumbnail preserves all source quadrants")
        }
        let (retina, retinaRect) = view.renderedFrame(scale: 2)!
        try expect(retina.width == 64 && retina.height == 48 && retinaRect == tinyRect, "Retina increases raster pixels without changing point geometry")
        view.corners = .frame(source: source, destination: target, direction: .shrink, index: 5, count: 25)
        let (warped, _) = view.renderedFrame(scale: 1)!
        let cornerAlpha = [(0, 0), (warped.width-1, 0), (0, warped.height-1), (warped.width-1, warped.height-1)].map { pixel(warped, $0.0, $0.1)[3] }
        try expect(cornerAlpha.contains(0), "Projection clears space outside the warped quadrilateral")
        if let folder = ProcessInfo.processInfo.environment["SKITCH_ZOOM_TEST_EVIDENCE"] {
            let destination = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try NSBitmapImageRep(cgImage: warped).representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("projected-quadrants.png"))
        }
        try expect(view.renderedFrame(scale: 0) == nil && view.renderedFrame(scale: .nan) == nil, "Invalid scale cannot allocate a frame")
        var finishes = 0
        let animation = WindowZoomAnimation(image: input, source: full, destination: small, direction: .shrink,
            panelFactory: { ZoomTestPanel(contentRect: $0, styleMask: [], backing: .buffered, defer: false) }, completion: { finishes += 1 })!
        let panel = animation.panel as! ZoomTestPanel
        animation.start(); animation.start()
        try expect(panel.fronts == 1 && panel.ignoresMouseEvents && !panel.hidesOnDeactivate, "Snapshot orders once and never intercepts an active drag")
        try expect(animation.timer?.timeInterval == 0.02 && animation.state == .running, "Recovered timer is20ms")
        for _ in 0..<25 { animation.advance() }
        try expect(animation.lastRenderedFrame == 24 && finishes == 0, "Original disappear visits zero through24 before completion")
        animation.advance()
        try expect(animation.lastRenderedFrame == 25 && finishes == 1 && animation.state == .completed && animation.timer == nil, "Original disappear completes on frame25 and invalidates its timer")
        animation.advance(); animation.cancel()
        try expect(finishes == 1 && panel.closes == 1, "Completion and teardown run once")
        let returning = WindowZoomAnimation(image: input, source: small, destination: full, direction: .restore,
            panelFactory: { ZoomTestPanel(contentRect: $0, styleMask: [], backing: .buffered, defer: false) }, completion: { finishes += 1 })!
        returning.start()
        for _ in 0..<14 { returning.advance() }
        try expect(returning.lastRenderedFrame == 14 && finishes == 1, "Original appear renders frame0 immediately then1 through14")
        returning.advance()
        try expect(returning.lastRenderedFrame == 15 && finishes == 2 && returning.view.corners.bounds == full, "Original appear restores the unwarped editor after frame15")
        let cancelled = WindowZoomAnimation(image: input, source: full, destination: small, direction: .shrink,
            panelFactory: { ZoomTestPanel(contentRect: $0, styleMask: [], backing: .buffered, defer: false) }, completion: { finishes += 1 })!
        let cancelledPanel = cancelled.panel as! ZoomTestPanel
        cancelled.start(); cancelled.advance(); cancelled.cancel(); cancelled.advance()
        try expect(cancelled.state == .cancelled && cancelled.timer == nil && cancelled.panel == nil && finishes == 2 && cancelledPanel.closes == 1, "Cancelled animation discards its completion and overlay")
        try expect(WindowZoomAnimation(image: input, source: .zero, destination: small, direction: .shrink, completion: {}) == nil, "Zero-sized geometry cannot create an overlay")
        let menuHide = WindowZoomAnimation(image: input, source: full, destination: small, direction: .shrink, frames: 15,
            panelFactory: { ZoomTestPanel(contentRect: $0, styleMask: [], backing: .buffered, defer: false) }, completion: { finishes += 1 })!
        menuHide.start()
        for _ in 0..<15 { menuHide.advance() }
        try expect(menuHide.lastRenderedFrame == 14 && menuHide.state == .running && finishes == 2, "Menu hide uses its recovered15-frame count instead of the drag25 count")
        menuHide.advance()
        try expect(menuHide.lastRenderedFrame == 15 && menuHide.state == .completed && finishes == 3, "Menu hide completes exactly on its own last frame")
        try expect(WindowZoomAnimation(image: input, source: full, destination: small, direction: .shrink, frames: 0, completion: {}) == nil &&
                   WindowZoomAnimation(image: input, source: full, destination: small, direction: .restore, frames: -1, completion: {}) == nil,
                   "Invalid frame counts cannot allocate a live transition")
        for mode in [RunLoop.Mode.eventTracking, .modalPanel] {
            let tracking = WindowZoomAnimation(image: input, source: small, destination: full, direction: .restore,
                panelFactory: { ZoomTestPanel(contentRect: $0, styleMask: [], backing: .buffered, defer: false) }, completion: {})!
            tracking.start()
            let deadline = Date(timeIntervalSinceNow: 2)
            repeat {
                _ = RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: 0.03))
            } while tracking.lastRenderedFrame == 0 && Date() < deadline
            try expect(tracking.lastRenderedFrame > 0, "Recovered animation timer runs during \(mode.rawValue)")
            tracking.cancel()
        }
        print("WindowZoomTests: \(checks) checks passed")
    }
}
#endif
