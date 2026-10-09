// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -framework AppKit -D ORIGINAL_CAPTURE_COUNTDOWN_TESTS \
//   Sources/OriginalCaptureTiming.swift Sources/OriginalCaptureCountdown.swift \
//   tests/OriginalCaptureCountdownTests.swift -o build/original-capture-countdown-tests
// rtk proxy build/original-capture-countdown-tests
#if ORIGINAL_CAPTURE_COUNTDOWN_TESTS
import AppKit
import CoreGraphics

@MainActor
private final class Events {
    var log: [String] = []
}

@MainActor
private final class Clock {
    final class Entry {
        let tick: @MainActor @Sendable () -> Void
        var active = true
        var cancellations = 0
        init(_ tick: @escaping @MainActor @Sendable () -> Void) { self.tick = tick }
    }
    let events: Events
    var entries: [Entry] = []
    var intervals: [TimeInterval] = []
    var onCancel: (() -> Void)?
    var onRegister: ((Entry) -> Void)?
    init(_ events: Events) { self.events = events }
    func schedule(_ interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) -> OriginalCaptureCountdown.Cancellation {
        let entry = Entry(tick)
        entries.append(entry); intervals.append(interval)
        onRegister?(entry)
        return { [self] in
            entry.active = false; entry.cancellations += 1
            events.log.append("invalidate")
            onCancel?()
        }
    }
    func fire(_ index: Int = 0) { entries[index].tick() } // Includes deliberate stale delivery.
    var activeCount: Int { entries.filter(\.active).count }
}

/// Every presentation/focus/close route is intercepted; these tests never order a window.
@MainActor
private final class Panel: OriginalCountdownPanel {
    var events: Events!
    var frontCount = 0
    var outCount = 0
    var closeCount = 0
    var focusCount = 0
    var onOut: (() -> Void)?
    override func orderFrontRegardless() { frontCount += 1; events.log.append("front") }
    override func orderFront(_ sender: Any?) { frontCount += 1; events.log.append("front") }
    override func orderOut(_ sender: Any?) { outCount += 1; events.log.append("out"); onOut?() }
    override func orderBack(_ sender: Any?) { events.log.append("back") }
    override func makeKey() { focusCount += 1 }
    override func makeMain() { focusCount += 1 }
    override func makeKeyAndOrderFront(_ sender: Any?) { focusCount += 1 }
    override func close() { closeCount += 1; events.log.append("close") }
}

@MainActor
private final class Parent: NSPanel {
    let events: Events
    var attached: [NSWindow] = []
    var orders: [NSWindow.OrderingMode] = []
    init(_ events: Events) {
        self.events = events
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        attached.append(childWin); orders.append(place); events.log.append("attach")
    }
    override func removeChildWindow(_ childWin: NSWindow) {
        attached.removeAll { $0 === childWin }; events.log.append("detach")
    }
    override func orderFrontRegardless() { preconditionFailure("No parent ordering") }
    override func orderFront(_ sender: Any?) { preconditionFailure("No parent ordering") }
    override func orderOut(_ sender: Any?) {}
    override func close() {}
    override func makeKey() { preconditionFailure("No parent focus") }
    override func makeMain() { preconditionFailure("No parent focus") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("No parent focus") }
}

@MainActor
private final class Harness {
    let events = Events()
    lazy var clock = Clock(events)
    var panels: [Panel] = []
    var requestedImages: [Int] = []
    var resources: [Int: NSImage] = [:]
    var screens = [NSRect(x: 0, y: 23, width: 1440, height: 847)]
    var factoryHook: (() -> Void)?
    var imageHook: ((Int) -> Void)?
    var screenHook: (() -> Void)?
    init(artwork: Bool = true) {
        guard artwork else { return }
        for number in 1...3 { resources[number] = OriginalCaptureCountdown.numeral(number) }
    }
    func make() -> OriginalCaptureCountdown {
        OriginalCaptureCountdown(panelFactory: { [self] rect in
            let panel = Panel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
            panel.events = events; panels.append(panel); factoryHook?()
            return panel
        }, images: { [self] number in
            requestedImages.append(number); imageHook?(number); return resources[number]
        }, scheduler: { [self] interval, tick in clock.schedule(interval, tick) },
        screenFrames: { [self] in screenHook?(); return screens })
    }
}

@main
@MainActor
enum OriginalCaptureCountdownTests {
    private static var checks = 0
    private static let rect = NSRect(x: 200, y: 100, width: 400, height: 300)
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }
    static func main() {
        // NSApplication initializes AppKit only; no activation, run, or window ordering.
        _ = NSApplication.shared
        let _: any CaptureCountdownPresenting = OriginalCaptureCountdown()
        sequence(delay: 3, ticks: 31, cues: [1, 11, 21])
        sequence(delay: 6, ticks: 61, cues: [1, 21, 41])
        cancellationAndAttachment()
        reentrantCallbacks()
        registrationAndProviderReentry()
        boundaryInputs(artwork: true)
        drawnNumerals()
        geometry()
        print("OriginalCaptureCountdownTests: \(checks) checks passed (no window ordering)")
    }

    private static func sequence(delay: Double, ticks: Int, cues: [Int]) {
        let h = Harness(), countdown = h.make()
        var tick = 0, cueTicks: [Int] = [], completions = 0
        countdown.start(rect: rect, parent: nil, delay: delay, cue: {
            cueTicks.append(tick)
            h.events.log.append("cue")
        }, completion: {
            completions += 1; h.events.log.append("complete")
            expect(!countdown.isRunning && h.clock.activeCount == 0, "Completion sees cleared timing")
            expect(h.panels[0].contentView == nil && h.panels[0].outCount == 1 && h.panels[0].closeCount == 1,
                   "Completion sees cleared presentation")
        })
        expect(countdown.isRunning && h.clock.activeCount == 1 && h.clock.entries.count == 1, "One owned timer")
        expect(h.clock.intervals == [0.1], "Recovered interval")
        let panel = h.panels[0]
        expect(panel.frame == NSRect(x: 300, y: 150, width: 200, height: 200), "Centered drawn numeral")
        expect(panel.frontCount == 1 && panel.focusCount == 0 && !panel.canBecomeKey && !panel.canBecomeMain, "Standalone presentation never focuses")
        expect(panel.ignoresMouseEvents && !panel.isOpaque && panel.backgroundColor == .clear, "Transparent mouse pass-through")
        expect(!panel.canHide && !panel.hidesOnDeactivate, "App hiding does not hide owned countdown")
        expect(!panel.isMovable && !panel.isMovableByWindowBackground, "Immovable overlay")
        expect(panel.level.rawValue == Int(CGWindowLevelForKey(.popUpMenuWindow)) + 100, "Recovered window level")
        expect(panel.alphaValue == 0, "Initial overlay invisible")
        let view = panel.contentView as! NSImageView
        expect(view.image === h.resources[3] && view.imageScaling == .scaleNone, "Original PNG retained without rescaling")
        expect(view.accessibilityLabel() == "Capture countdown: 3", "Accessible initial numeral")
        expect(!view.acceptsFirstResponder && view.hitTest(.zero) == nil, "View owns no input")
        var policy = OriginalCaptureTiming(delay: delay)!
        for i in 1...ticks {
            tick = i
            let frame = policy.tick()
            h.clock.fire()
            expect(completions == (i == ticks ? 1 : 0), "Only Float32 expiry completes")
            if i < ticks {
                expect(panel.alphaValue == CGFloat(frame.alpha), "Native alpha matches exact policy")
                expect(view.image === h.resources[frame.imageNumber], "Native numeral matches policy")
                expect(view.accessibilityLabel() == "Capture countdown: \(frame.imageNumber)", "Accessibility follows numeral")
            }
        }
        expect(cueTicks == cues, "Recovered sound cue ticks")
        expect(h.requestedImages == [3, 3, 2, 1], "Load only original transition images")
        expect(Array(h.events.log.suffix(4)) == ["invalidate", "out", "close", "complete"], "Clear BEFORE completion")
        h.clock.fire(); countdown.cancel()
        expect(completions == 1 && h.clock.entries[0].cancellations == 1 && cueTicks == cues, "Stale ticks and cancel cannot repeat completion")
    }

    private static func cancellationAndAttachment() {
        let h = Harness(), countdown = h.make(), parent = Parent(h.events)
        var cues = 0, completions = 0
        countdown.start(rect: rect, parent: parent, delay: 6, cue: { cues += 1 }, completion: { completions += 1 })
        expect(parent.attached.count == 1 && parent.orders == [.above], "Attach above parent")
        expect(h.panels[0].frontCount == 0 && h.panels[0].focusCount == 0, "Child attachment never independently orders/focuses")
        countdown.start(rect: .zero, parent: nil, delay: 3, cue: { preconditionFailure("Busy start cue") },
                        completion: { preconditionFailure("Busy start completion") })
        expect(h.clock.entries.count == 1 && h.panels.count == 1, "Busy start preserves one timer/panel")
        h.clock.fire()
        countdown.cancel(); countdown.cancel(); h.clock.fire()
        expect(cues == 1 && completions == 0 && !countdown.isRunning, "Cancel suppresses expiry and stale cues")
        expect(parent.attached.isEmpty, "Cancel detaches child")
        expect(Array(h.events.log.suffix(4)) == ["invalidate", "detach", "out", "close"], "Cancel invalidates before native teardown")
    }

    private static func reentrantCallbacks() {
        let h = Harness(), countdown = h.make()
        var firstDone = 0, secondDone = 0, firstCues = 0
        countdown.start(rect: rect, parent: nil, delay: 3, cue: {
            firstCues += 1
            h.clock.fire() // Reentrant tick cannot double-decrement or replay cue.
            countdown.cancel()
            countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: { secondDone += 1 })
        }, completion: { firstDone += 1 })
        h.clock.fire()
        expect(firstCues == 1 && firstDone == 0 && h.clock.entries.count == 2 && h.clock.activeCount == 1,
               "Cue cancellation/restart isolates sessions")
        expect(h.panels[1].alphaValue == 0 && h.requestedImages == [3, 3], "Old cue cannot update replacement artwork/alpha")
        h.clock.fire()
        for _ in 1...31 { h.clock.fire(1) }
        expect(secondDone == 1 && firstDone == 0, "Replacement completes independently")

        countdown.start(rect: rect, parent: nil, delay: 0.1, cue: {}, completion: {
            expect(!countdown.isRunning && h.clock.activeCount == 0, "Reentrant completion begins after teardown")
            countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: {})
        })
        h.clock.fire(2); h.clock.fire(2)
        expect(h.clock.entries.count == 4 && h.clock.activeCount == 1 && countdown.isRunning, "Completion may start next countdown")
        h.clock.fire(2)
        expect(h.panels[3].alphaValue == 0, "Expired callback cannot advance new session")
        h.clock.onCancel = {
            countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: {})
            h.clock.fire(3)
        }
        h.panels[3].onOut = { h.clock.fire(3); countdown.cancel() }
        countdown.cancel()
        expect(h.clock.entries.count == 4 && h.clock.activeCount == 0 && !countdown.isRunning, "Cleanup reentry cannot resurrect session")
    }

    private static func registrationAndProviderReentry() {
        let h = Harness(), countdown = h.make()
        h.clock.onRegister = { entry in entry.tick(); countdown.cancel() }
        countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: { preconditionFailure("Cancelled registration") })
        expect(h.clock.entries[0].cancellations == 1 && h.clock.activeCount == 0 && !countdown.isRunning,
               "Synchronous scheduler cancellation invalidates late returned token")
        var synchronousDone = 0
        h.clock.onRegister = { entry in entry.tick(); entry.tick(); entry.tick() }
        countdown.start(rect: rect, parent: nil, delay: 0.1, cue: {}, completion: {
            synchronousDone += 1
            expect(h.clock.activeCount == 0 && !countdown.isRunning && h.panels[1].contentView == nil,
                   "Synchronous expiry clears returned timer token and panel before completion")
        })
        expect(synchronousDone == 1 && h.clock.entries[1].cancellations == 1, "Synchronous registration completes once")
        h.clock.onRegister = nil
        h.imageHook = { _ in countdown.cancel() }
        countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: {})
        expect(h.panels.count == 2 && h.clock.entries.count == 2, "Image provider cancellation stops setup")
        h.imageHook = nil
        h.screenHook = { countdown.cancel() }
        countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: {})
        expect(h.panels.count == 2 && h.clock.entries.count == 2, "Screen provider cancellation stops setup")
        h.screenHook = nil
        h.factoryHook = { countdown.cancel() }
        countdown.start(rect: rect, parent: nil, delay: 3, cue: {}, completion: {})
        expect(h.panels.count == 3 && h.panels[2].closeCount == 1 && h.clock.entries.count == 2,
               "Late factory result is cleared without scheduling")
    }

    private static func boundaryInputs(artwork: Bool) {
        let h = Harness(artwork: artwork), countdown = h.make()
        var complete = 0
        for delay in [-1.0, .nan, .infinity, 3600.1] {
            countdown.start(rect: rect, parent: nil, delay: delay, cue: { preconditionFailure("Invalid cue") }, completion: { complete += 1 })
        }
        countdown.start(rect: NSRect(x: CGFloat.infinity, y: 0, width: 1, height: 1), parent: nil,
                        delay: 3, cue: {}, completion: { complete += 1 })
        expect(h.clock.entries.isEmpty && h.panels.isEmpty && complete == 0, "Invalid values do not capture or schedule")
        countdown.start(rect: rect, parent: nil, delay: 0, cue: { preconditionFailure("Zero cue") }, completion: {
            complete += 1; expect(!countdown.isRunning, "Immediate completion has cleared state")
        })
        expect(complete == 1 && h.clock.entries.isEmpty && h.panels.isEmpty, "Zero delay requires no timer or panel")
        h.screens = []
        countdown.start(rect: rect, parent: nil, delay: 0.1, cue: {}, completion: { complete += 1 })
        h.clock.fire(); h.clock.fire()
        expect(complete == 2 && h.panels.isEmpty && h.clock.activeCount == 0, "No screens cannot strand expiry")
        let timer = h.clock.entries.count, expected = complete + 1
        h.screens = [NSRect(x: 0, y: 0, width: 1000, height: 1000)]
        h.resources = [:]
        countdown.start(rect: rect, parent: nil, delay: 0.1, cue: {}, completion: { complete += 1 })
        h.clock.fire(timer); h.clock.fire(timer)
        expect(complete == expected && h.panels.isEmpty && h.clock.activeCount == 0, "A missing numeral cannot strand expiry")
    }

    private static func drawnNumerals() {
        expect(OriginalCaptureCountdown.numeralFontSize >= 18, "Numeral text is at least 18pt")
        expect(OriginalCaptureCountdown.numeral(0) == nil && OriginalCaptureCountdown.numeral(4) == nil, "Only 1 to 3 draw")
        var signatures: [Data] = []
        for number in 1...3 {
            guard let image = OriginalCaptureCountdown.numeral(number),
                  let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
                expect(false, "Numeral \(number) draws"); return
            }
            expect(image.size == OriginalCaptureCountdown.numeralSize, "Numeral \(number) uses the shared size")
            var white = 0, dark = 0
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                if c.redComponent > 0.9 { white += 1 } else if c.redComponent < 0.2 { dark += 1 }
            } }
            expect(white > 500 && dark > white, "Numeral \(number) is white text on a dark backing")
            signatures.append(tiff)
        }
        expect(Set(signatures).count == 3, "Each numeral draws differently")
    }

    private static func geometry() {
        let size = NSSize(width: 138, height: 140)
        func place(_ rect: NSRect, _ screens: [NSRect]) -> NSRect {
            OriginalCaptureCountdown.placement(rect: rect, imageSize: size, screenFrames: screens)
        }
        let screen = NSRect(x: 0, y: 23, width: 1000, height: 747)
        expect(place(rect, [screen]) == NSRect(x: 331, y: 180, width: 138, height: 140), "No extra margin")
        expect(place(NSRect(x: -100, y: -100, width: 0, height: 0), [screen]).origin == NSPoint(x: 0, y: 23), "Visible-frame lower left clamp")
        expect(place(NSRect(x: 1100, y: 900, width: 0, height: 0), [screen]).origin == NSPoint(x: 862, y: 630), "Upper right preserves original size")
        let negative = NSRect(x: -1000, y: -800, width: 1000, height: 800)
        expect(place(NSRect(x: -500, y: -400, width: 1, height: 1), [negative]).origin == NSPoint(x: -569, y: -470), "Negative half origins use roundf away from zero")
        expect(place(NSRect(x: 500, y: 400, width: 1, height: 1), [screen]).origin == NSPoint(x: 432, y: 331), "Positive half origins use roundf away from zero")
        let adjacent = [NSRect(x: 0, y: 0, width: 1000, height: 800), NSRect(x: 1000, y: 0, width: 1000, height: 800)]
        expect(place(NSRect(x: 1000, y: 400, width: 0, height: 0), adjacent).origin == NSPoint(x: 931, y: 330), "Four-corner clamp permits original adjacent-screen spanning")
        let gap = [NSRect(x: 0, y: 0, width: 1000, height: 800), NSRect(x: 1200, y: 0, width: 1000, height: 800)]
        expect(place(NSRect(x: 1100, y: 400, width: 0, height: 0), gap).origin == NSPoint(x: 1062, y: 330), "Gap retains original alternating corner translations, final right edge on second display")
        let tieRect = NSRect(x: 1169, y: 400, width: 0, height: 0)
        expect(place(tieRect, gap).origin == NSPoint(x: 1062, y: 330), "Equal-distance corner keeps first screen")
        expect(place(tieRect, Array(gap.reversed())).origin == NSPoint(x: 1200, y: 330), "Screen-order tie affects original clamp")
        let tiny = NSRect(x: 0, y: 0, width: 100, height: 100)
        expect(place(.zero, [tiny]) == NSRect(x: -38, y: -40, width: 138, height: 140), "Oversized artwork keeps recovered size and final corner anchoring")
        let vertical = [NSRect(x: -1000, y: 0, width: 1000, height: 800), NSRect(x: 0, y: 800, width: 1000, height: 800)]
        let result = place(NSRect(x: 600, y: 1200, width: 200, height: 200), vertical)
        expect(result == NSRect(x: 631, y: 1230, width: 138, height: 140), "Global coordinates remain bottom-left without conversion")
    }
}
#endif
