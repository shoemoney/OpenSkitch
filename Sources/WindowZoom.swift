import AppKit
import CoreImage

enum WindowZoomDirection { case shrink, restore }

struct WindowZoomCorners: Equatable {
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let topLeft: CGPoint
    let topRight: CGPoint

    var bounds: CGRect {
        let points = [bottomLeft, bottomRight, topLeft, topRight]
        let left = points.map(\.x).min()!, right = points.map(\.x).max()!
        let bottom = points.map(\.y).min()!, top = points.map(\.y).max()!
        return CGRect(x: left, y: bottom, width: right-left, height: top-bottom)
    }

    // SkitchIconifiedWindow appear:/disappear: and its 2x2 setCorners mesh.
    static func frame(source: CGRect, destination: CGRect, direction: WindowZoomDirection, index: Int, count: Int) -> Self {
        let t = CGFloat(max(0, min(index, max(1, count)))) / CGFloat(max(1, count))
        let curved = direction == .shrink ? sqrt(t) : t*t
        func mix(_ a: CGFloat, _ b: CGFloat, _ progress: CGFloat) -> CGFloat { a*(1-progress) + b*progress }
        let lowerY = mix(source.minY, destination.minY, curved)
        let upperY = mix(source.maxY, destination.maxY, t)
        return Self(
            bottomLeft: CGPoint(x: mix(source.minX, destination.minX, t), y: lowerY),
            bottomRight: CGPoint(x: mix(source.maxX, destination.maxX, t), y: lowerY),
            topLeft: CGPoint(x: mix(source.minX, destination.minX, curved), y: upperY),
            topRight: CGPoint(x: mix(source.maxX, destination.maxX, curved), y: upperY))
    }
}

final class WindowZoomView: NSView {
    let sourceImage: CIImage
    let screenOrigin: CGPoint
    var corners: WindowZoomCorners { didSet { needsDisplay = true } }
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(frame: CGRect, image: CGImage, corners: WindowZoomCorners) {
        sourceImage = CIImage(cgImage: image); screenOrigin = frame.origin; self.corners = corners
        super.init(frame: CGRect(origin: .zero, size: frame.size))
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func renderedFrame(scale: CGFloat) -> (CGImage, CGRect)? {
        guard scale.isFinite, scale > 0 else { return nil }
        func vector(_ point: CGPoint) -> CIVector {
            CIVector(x: (point.x-screenOrigin.x)*scale, y: (point.y-screenOrigin.y)*scale)
        }
        guard let filter = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(vector(corners.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(vector(corners.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(corners.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(corners.topRight), forKey: "inputTopRight")
        let rect = corners.bounds.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        let pixels = CGRect(x: rect.minX*scale, y: rect.minY*scale, width: rect.width*scale, height: rect.height*scale).integral
        guard !pixels.isEmpty, pixels.width <= 32_768, pixels.height <= 32_768,
              let output = filter.outputImage,
              let image = context.createCGImage(output, from: pixels, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else { return nil }
        return (image, CGRect(x: pixels.minX/scale, y: pixels.minY/scale, width: pixels.width/scale, height: pixels.height/scale))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let drawing = NSGraphicsContext.current?.cgContext else { return }
        drawing.clear(bounds)
        if let (image, rect) = renderedFrame(scale: window?.backingScaleFactor ?? 1) { drawing.draw(image, in: rect) }
    }
}

@MainActor
final class WindowZoomAnimation {
    enum State { case idle, running, completed, cancelled }
    static let interval = 0.02
    static let shrinkFrames = 25
    static let restoreFrames = 15
    let source: CGRect
    let destination: CGRect
    let direction: WindowZoomDirection
    let frameCount: Int
    let view: WindowZoomView
    private(set) var state: State = .idle
    private(set) var lastRenderedFrame = 0
    private(set) var timer: Timer?
    private(set) var panel: NSPanel?
    private var nextFrame: Int
    private var completion: (() -> Void)?

    init?(image: NSImage, source: CGRect, destination: CGRect, direction: WindowZoomDirection,
          panelFactory: @MainActor (CGRect) -> NSPanel = { rect in NSPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false) },
          completion: @escaping () -> Void) {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0,
              let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.source = source; self.destination = destination; self.direction = direction
        frameCount = direction == .shrink ? Self.shrinkFrames : Self.restoreFrames
        nextFrame = direction == .shrink ? 0 : 1
        self.completion = completion
        let rect = source.union(destination).integral
        view = WindowZoomView(frame: rect, image: pixels, corners: .frame(source: source, destination: destination, direction: direction, index: 0, count: frameCount))
        let panel = panelFactory(rect)
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = false; panel.level = .statusBar; panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true; panel.contentView = view
        self.panel = panel
    }
    func start() {
        guard state == .idle else { return }
        state = .running; panel?.orderFrontRegardless()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        self.timer = timer
        for mode in [RunLoop.Mode.default, .eventTracking, .modalPanel] { RunLoop.main.add(timer, forMode: mode) }
    }
    func advance() {
        guard state == .running else { return }
        lastRenderedFrame = nextFrame
        view.corners = .frame(source: source, destination: destination, direction: direction, index: nextFrame, count: frameCount)
        if nextFrame >= frameCount {
            state = .completed; timer?.invalidate(); timer = nil
            panel?.orderOut(nil); panel?.close(); panel = nil
            let callback = completion; completion = nil; callback?()
        } else { nextFrame += 1 }
    }
    func cancel() {
        guard state != .completed && state != .cancelled else { return }
        state = .cancelled; timer?.invalidate(); timer = nil; completion = nil
        panel?.orderOut(nil); panel?.close(); panel = nil
    }
}
