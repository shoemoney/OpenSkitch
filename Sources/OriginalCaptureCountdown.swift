import AppKit
import CoreGraphics

@MainActor
protocol CaptureCountdownPresenting: AnyObject, Sendable {
    func start(rect: NSRect, parent: NSWindow?, delay: Double,
               cue: @escaping () -> Void, completion: @escaping () -> Void)
    func cancel()
}

/// Native presentation for snapTimer: (0x23d28). Capture and sound remain parent-owned.
@MainActor
final class OriginalCaptureCountdown: CaptureCountdownPresenting {
    typealias PanelFactory = @MainActor (NSRect) -> NSPanel
    typealias Images = @MainActor (Int) -> NSImage?
    typealias ScreenFrames = @MainActor () -> [NSRect]
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Cancellation

    private final class Session {
        var timing: OriginalCaptureTiming
        let cue: () -> Void
        let completion: () -> Void
        weak var parent: NSWindow?
        var panel: NSPanel?
        var imageView: NSImageView?
        var cancelTimer: Cancellation?
        var advancing = false
        var registering = false
        var completionPending = false
        init(timing: OriginalCaptureTiming, cue: @escaping () -> Void, completion: @escaping () -> Void) {
            self.timing = timing; self.cue = cue; self.completion = completion
        }
    }

    private let panelFactory: PanelFactory
    private let images: Images
    private let scheduler: Scheduler
    private let screenFrames: ScreenFrames
    private var session: Session?
    private var cleaningUp = false
    private var lifetime: OriginalCaptureCountdown?
    var isRunning: Bool { session != nil }

    /// Frames and rect use AppKit global bottom-left coordinates. Supply VISIBLE
    /// screen frames in NSScreen order. Test factories must suppress window ordering.
    init(panelFactory: PanelFactory? = nil, images: Images? = nil,
         scheduler: Scheduler? = nil, screenFrames: ScreenFrames? = nil) {
        self.panelFactory = panelFactory ?? { rect in
            OriginalCountdownPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        }
        self.images = images ?? { number in
            Self.numeral(number)
        }
        self.scheduler = scheduler ?? Self.schedule
        self.screenFrames = screenFrames ?? { NSScreen.screens.map(\.visibleFrame) }
    }

    func start(rect: NSRect, parent: NSWindow?, delay: Double,
               cue: @escaping () -> Void, completion: @escaping () -> Void) {
        // Original startCountdownForRect: (0x23876) ignores a second active start.
        guard session == nil, !cleaningUp, Self.valid(rect, allowZero: true),
              let timing = OriginalCaptureTiming(delay: delay) else { return }
        let request = Session(timing: timing, cue: cue, completion: completion)
        session = request
        lifetime = self
        if timing.total == 0 { finish(request, complete: true); return }

        let initialImage = images(3)
        guard session === request else { return }
        let frames = screenFrames().filter { Self.valid($0) }
        guard session === request else { return }
        // Missing resources/displays must not strand the parent's capture phase.
        // Timing still runs, without inventing replacement artwork or geometry.
        if let image = initialImage, Self.valid(NSRect(origin: .zero, size: image.size)), !frames.isEmpty {
            let frame = Self.placement(rect: rect, imageSize: image.size, screenFrames: frames)
            let panel = panelFactory(frame)
            guard session === request else { panel.orderOut(nil); panel.close(); return }
            request.panel = panel
            panel.isReleasedWhenClosed = false
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 100)
            panel.hidesOnDeactivate = false
            panel.canHide = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            let view = OriginalCountdownImageView(frame: NSRect(origin: .zero, size: frame.size))
            view.imageScaling = .scaleNone
            view.imageAlignment = .alignCenter
            view.image = image
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.image)
            view.setAccessibilityLabel("Capture countdown: 3")
            request.imageView = view
            panel.contentView = view
            request.parent = parent
            if let parent { parent.addChildWindow(panel, ordered: .above) }
            else { panel.orderFrontRegardless() }
            guard session === request else { return }
        }
        request.registering = true
        let cancellation = scheduler(OriginalCaptureTiming.timerInterval) { [weak self, weak request] in
            guard let self, let request else { return }
            self.advance(request)
        }
        // An injected scheduler may fire/cancel synchronously during registration.
        request.registering = false
        if session === request {
            request.cancelTimer = cancellation
            if request.completionPending { finish(request, complete: true) }
        } else { cancellation() }
    }

    /// Plain drawn digit: bold system font, white, on a dark rounded backing. No artwork files.
    static let numeralSize = NSSize(width: 200, height: 200)
    static let numeralFontSize: CGFloat = 140
    static func numeral(_ number: Int) -> NSImage? {
        guard (1...3).contains(number) else { return nil }
        return NSImage(size: numeralSize, flipped: false) { bounds in
            NSColor(white: 0.08, alpha: 0.78).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 44, yRadius: 44).fill()
            let text = NSAttributedString(string: String(number), attributes: [
                .font: NSFont.systemFont(ofSize: numeralFontSize, weight: .bold),
                .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            return true
        }
    }

    func cancel() {
        guard let request = session else { return }
        finish(request, complete: false)
    }

    private func advance(_ request: Session) {
        guard session === request, !request.advancing, !request.completionPending else { return }
        request.advancing = true
        defer { request.advancing = false }
        let frame = request.timing.tick()
        // Original cue precedes image/alpha changes. It may cancel or start anew.
        if frame.playCue { request.cue() }
        guard session === request else { return }
        if frame.playCue {
            let image = images(frame.imageNumber)
            guard session === request else { return }
            request.imageView?.image = image
            request.imageView?.setAccessibilityLabel("Capture countdown: \(frame.imageNumber)")
        }
        request.panel?.alphaValue = CGFloat(frame.alpha)
        guard session === request else { return }
        if frame.finished { finish(request, complete: true) }
    }

    private func finish(_ request: Session, complete: Bool) {
        guard session === request else { return }
        // A synchronous injected scheduler has not returned its cancellation yet.
        // Defer expiry completion until we can invalidate that token first.
        if complete && request.registering { request.completionPending = true; return }
        session = nil // Reject stale ticks before calling injected/native code.
        cleaningUp = true
        let cancellation = request.cancelTimer
        request.cancelTimer = nil
        cancellation?()
        if let panel = request.panel {
            request.parent?.removeChildWindow(panel)
            request.parent = nil
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        request.panel = nil
        request.imageView = nil
        lifetime = nil
        cleaningUp = false
        // 0x2020f cancelTimedSnap precedes 0x205f4 endSnap. No sound-stop here.
        if complete { request.completion() }
    }

    private static func schedule(interval: TimeInterval,
                                 tick: @escaping @MainActor @Sendable () -> Void) -> Cancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        // ONE timer, in the three modes registered by original 0x23c97–0x23d1d.
        for mode: RunLoop.Mode in [.default, .eventTracking, .modalPanel] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return { timer.invalidate() }
    }

    private static func valid(_ rect: NSRect, allowZero: Bool = false) -> Bool {
        let values = [rect.origin.x, rect.origin.y, rect.width, rect.height]
        return values.allSatisfy { $0.isFinite && Float32($0).isFinite }
            && (allowZero ? rect.width >= 0 && rect.height >= 0 : rect.width > 0 && rect.height > 0)
    }

    /// 0x23961/0x23973 roundf centering, then 0x906d5 keepRectInsideScreens:
    /// translate BL, BR, TL, TR against all visible frames; do not choose one screen.
    static func placement(rect: NSRect, imageSize: NSSize, screenFrames: [NSRect]) -> NSRect {
        let width = Float32(imageSize.width), height = Float32(imageSize.height)
        let centerX = Float32(rect.origin.x) + Float32(rect.width) * Float32(0.5)
        let centerY = Float32(rect.origin.y) + Float32(rect.height) * Float32(0.5)
        var x = (centerX - width * Float32(0.5)).rounded(.toNearestOrAwayFromZero)
        var y = (centerY - height * Float32(0.5)).rounded(.toNearestOrAwayFromZero)
        for corner in [(Float32(0), Float32(0)), (width, 0), (0, height), (width, height)] {
            let px = x + corner.0, py = y + corner.1
            let clamped = keepPoint(px, py, frames: screenFrames)
            x = (clamped.0 - px) + x
            y = (clamped.1 - py) + y
        }
        return NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    private static func keepPoint(_ x: Float32, _ y: Float32, frames: [NSRect]) -> (Float32, Float32) {
        // Original 0x901d0: squared Float32 distance, strict comparison, first tie.
        var best: Float32 = 1e10
        var result: (Float32, Float32) = (-1e10, -1e10)
        for frame in frames {
            let minX = Float32(frame.origin.x), minY = Float32(frame.origin.y)
            let maxX = minX + Float32(frame.width), maxY = minY + Float32(frame.height)
            if x >= minX && x < maxX && y >= minY && y < maxY { return (x, y) }
            let cx = min(max(x, minX), maxX), cy = min(max(y, minY), maxY)
            let dx = x - cx, dy = y - cy
            let distance = dx * dx + dy * dy
            if distance < best { best = distance; result = (cx, cy) }
        }
        return result
    }
}

/// Never key/main, never a mouse or keyboard responder. No event monitor is installed.
class OriginalCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OriginalCountdownImageView: NSImageView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
