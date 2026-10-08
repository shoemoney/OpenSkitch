import AppKit
import CoreGraphics

/// Recovered from -[CrosshairScreenshot flashTimer:] (decompiled.c:18155-18195),
/// flashScreen:duration: (18196-18297) and deflashScreen:waitUntilDone: (18299-18348).
enum OriginalCaptureFlashTiming {
    static let timerInterval: TimeInterval = 0.02
    /// 0x3dcccccd: flash-up duration, also used by the screen capture path.
    static let captureDuration = Float32(bitPattern: 0x3dcccccd)
    /// 0x3e4ccccd: deflash duration used after a capture (decompiled.c:22301).
    static let cameraDeflashDuration = Float32(bitPattern: 0x3e4ccccd)

    enum Phase { case flash, deflash }

    /// Flash ramps 0 -> 1, deflash ramps 1 -> 0; both clamp once the duration has elapsed.
    static func alpha(elapsed: TimeInterval, duration: Float32, phase: Phase) -> Float32 {
        let fraction: Float32 = finished(elapsed: elapsed, duration: duration)
            ? 1 : max(0, Float32(elapsed) / duration)
        return phase == .flash ? fraction : 1 - fraction
    }

    static func finished(elapsed: TimeInterval, duration: Float32) -> Bool {
        Float32(elapsed) >= duration
    }
}

/// pqFlashView: solid white fill.
final class OriginalCaptureFlashView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.set()
        dirtyRect.fill()
    }
}

/// pqFlashWindow (decompiled.c:31365-31417): transparent, shadowless, click-through-level
/// panel that never becomes key or main.
final class OriginalCaptureFlashWindow: NSPanel {
    /// contentRect is in global screen coordinates, so the screen argument needs no extra placement.
    init(contentRect: NSRect, screen: NSScreen?) {
        super.init(contentRect: contentRect, styleMask: NSWindow.StyleMask(rawValue: 0x180),
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 200)
        isMovableByWindowBackground = false
        hasShadow = false
        let view = OriginalCaptureFlashView(frame: NSRect(origin: .zero, size: contentRect.size))
        contentView = view
        view.needsDisplay = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol CaptureFlashPresenting: AnyObject, Sendable {
    /// Plays the white flash-up then deflash for a successful capture.
    func play(frame: NSRect)
    func cancel()
}

@MainActor
protocol CaptureFlashWindowing: AnyObject {
    func setAlpha(_ alpha: Float32)
    func orderFront()
    func orderOut()
}

extension OriginalCaptureFlashWindow: CaptureFlashWindowing {
    func setAlpha(_ alpha: Float32) { alphaValue = CGFloat(alpha) }
    func orderFront() { orderFrontRegardless() }
    func orderOut() { orderOut(nil) }
}

/// Drives flash then deflash with an injected clock, timer and window so tests never
/// show a real window.
@MainActor
final class OriginalCaptureFlashController: CaptureFlashPresenting {
    typealias Invalidate = @MainActor () -> Void
    typealias Clock = @MainActor () -> TimeInterval
    typealias WindowFactory = @MainActor (NSRect) -> any CaptureFlashWindowing
    typealias TimerFactory = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Invalidate

    private let clock: Clock
    private let windowFactory: WindowFactory
    private let timerFactory: TimerFactory
    private var window: (any CaptureFlashWindowing)?
    private var invalidate: Invalidate?
    private var phase = OriginalCaptureFlashTiming.Phase.flash
    private var start: TimeInterval = 0
    private let flashDuration: Float32
    private let deflashDuration: Float32
    var isRunning: Bool { window != nil }

    init(flashDuration: Float32 = OriginalCaptureFlashTiming.captureDuration,
         deflashDuration: Float32 = OriginalCaptureFlashTiming.cameraDeflashDuration,
         clock: Clock? = nil, windowFactory: WindowFactory? = nil, timerFactory: TimerFactory? = nil) {
        self.flashDuration = flashDuration
        self.deflashDuration = deflashDuration
        self.clock = clock ?? { Date.timeIntervalSinceReferenceDate }
        self.windowFactory = windowFactory ?? { OriginalCaptureFlashWindow(contentRect: $0, screen: nil) }
        self.timerFactory = timerFactory ?? { interval, tick in
            let timer = Timer(timeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { tick() }
            }
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.add(timer, forMode: .eventTracking)
            RunLoop.current.add(timer, forMode: .modalPanel)
            return { timer.invalidate() }
        }
    }

    /// A zero or empty frame covers every screen (original passes NSZeroRect -> totalFrame).
    func play(frame: NSRect) {
        guard window == nil else { return }
        let target = frame.isEmpty ? NSScreen.screens.map(\.frame).reduce(NSRect.null) { $0.union($1) } : frame
        guard !target.isNull, !target.isEmpty else { return }
        let created = windowFactory(target)
        window = created
        created.orderFront()
        beginPhase(.flash)
    }

    func cancel() { tearDown() }

    func tick() {
        guard let window else { return }
        let elapsed = clock() - start
        let duration = phase == .flash ? flashDuration : deflashDuration
        window.setAlpha(OriginalCaptureFlashTiming.alpha(elapsed: elapsed, duration: duration, phase: phase))
        guard OriginalCaptureFlashTiming.finished(elapsed: elapsed, duration: duration) else { return }
        if phase == .flash { beginPhase(.deflash) } else { tearDown() }
    }

    private func beginPhase(_ next: OriginalCaptureFlashTiming.Phase) {
        invalidate?()
        phase = next
        start = clock()
        invalidate = timerFactory(OriginalCaptureFlashTiming.timerInterval) { [weak self] in self?.tick() }
    }

    private func tearDown() {
        invalidate?(); invalidate = nil
        window?.setAlpha(0)
        window?.orderOut()
        window = nil
    }
}
