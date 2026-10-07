// Nonordering host/panel and deterministic timers: no desktop input/permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D ORIGINAL_HELP_BEVEL_TESTS \
//   Sources/OriginalHelpBevel.swift tests/OriginalHelpBevelTests.swift -o build/original-help-bevel-tests
// rtk proxy build/original-help-bevel-tests
#if ORIGINAL_HELP_BEVEL_TESTS
import AppKit

private final class HelpHost: NSWindow {
    var shown = true
    var key = true
    var minimized = false
    var simulatedSheet: NSWindow?
    var attachments: [(NSWindow, NSWindow.OrderingMode)] = []
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { simulatedSheet }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        attachments.append((childWin, place))
        (childWin as? HelpPanel)?.host = self
    }
    override func removeChildWindow(_ childWin: NSWindow) {
        attachments.removeAll { $0.0 === childWin }
        (childWin as? HelpPanel)?.host = nil
    }
    override func orderFront(_ sender: Any?) {}
    override func orderOut(_ sender: Any?) {}
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("must not focus host") }
}

private final class HelpPanel: NSPanel {
    weak var host: HelpHost?
    var fronts = 0
    var outs = 0
    var closes = 0
    override var parent: NSWindow? {
        get { host }
        set { host = newValue as? HelpHost }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func orderFront(_ sender: Any?) { fronts += 1 }
    override func orderFrontRegardless() { preconditionFailure("must not order regardless of host") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("must not focus help") }
    override func orderOut(_ sender: Any?) { outs += 1 }
    override func close() { closes += 1 }
}

@MainActor
private final class ControlledHelpScheduler: OriginalHelpBevelScheduling {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let timer: Timer
        let action: @MainActor @Sendable () -> Bool
    }
    var entries: [Entry] = []
    var active: Int { entries.filter { $0.timer.isValid }.count }
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { timer in
            if !MainActor.assumeIsolated({ action() }) { timer.invalidate() }
        }
        entries.append(Entry(interval: interval, repeats: repeats, timer: timer, action: action))
        return timer // Deliberately never register a test timer with a run loop.
    }
    func latest(_ interval: TimeInterval) -> Int {
        entries.lastIndex { $0.interval == interval }!
    }
    func fire(_ index: Int, stale: Bool = false) {
        let entry = entries[index]
        guard stale || entry.timer.isValid else { return }
        if !entry.action() || !entry.repeats { entry.timer.invalidate() }
    }
    func finishFade() -> Int {
        let index = latest(0.02)
        var ticks = 0
        while entries[index].timer.isValid && ticks < 20 { fire(index); ticks += 1 }
        return ticks
    }
}

@main
@MainActor
private enum OriginalHelpBevelTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }
    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000001 }

    @MainActor
    private struct Rig {
        let host: HelpHost
        let scheduler: ControlledHelpScheduler
        let bevel: OriginalHelpBevel
        let factoryCalls: NSMutableArray
        var panel: HelpPanel { bevel.panel as! HelpPanel }
    }
    private static func make() -> Rig {
        let host = HelpHost(contentRect: NSRect(x: -700, y: 100, width: 800, height: 500),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        let scheduler = ControlledHelpScheduler()
        let factoryCalls = NSMutableArray()
        let bevel = OriginalHelpBevel(host: host, makePanel: {
            factoryCalls.add(true)
            return HelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        }, scheduler: scheduler)
        return Rig(host: host, scheduler: scheduler, bevel: bevel, factoryCalls: factoryCalls)
    }

    static func main() {
        _ = NSApplication.shared
        gates()
        slotsAndStaleEvents()
        fadesAndReversal()
        layoutAndRendering()
        teardownAndReachability()
        nativeRunLoopModes()
        print("PASS OriginalHelpBevelTests (\(checks) checks; injected nonordering panels, no desktop input or permissions)")
    }

    private static func gates() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        expect(rig.bevel.panel == nil && rig.bevel.displayedMessage == nil && !rig.bevel.enabled,
               "Construction is lazy and disabled")
        rig.bevel.hover(owner: "tool", message: "Draw")
        rig.bevel.modifiers(message: "Constrain")
        expect(rig.factoryCalls.count == 0 && rig.scheduler.active == 0, "Disabled cannot allocate or schedule")
        rig.bevel.enabled = true
        for gate in 0..<4 {
            rig.host.shown = gate != 0
            rig.host.key = gate != 1
            rig.host.minimized = gate == 2
            rig.host.simulatedSheet = gate == 3 ? rig.host : nil
            rig.bevel.hover(owner: "tool", message: "Draw")
            rig.bevel.modifiers(message: "Constrain")
            expect(rig.factoryCalls.count == 0 && rig.scheduler.active == 0 && rig.bevel.displayedMessage == nil,
                   "Hidden/nonkey/miniaturized/sheet host cannot allocate or schedule")
        }
        rig.host.shown = true; rig.host.key = true; rig.host.minimized = false; rig.host.simulatedSheet = nil
        rig.bevel.reposition()
        expect(rig.bevel.panel == nil, "Regaining eligibility does not resurrect denied messages")
        rig.bevel.modifiers(message: "Constrain")
        expect(rig.factoryCalls.count == 1 && rig.bevel.displayedMessage == "Constrain", "Modifier is immediate")
        expect(!rig.panel.canBecomeKey && !rig.panel.canBecomeMain && rig.panel.ignoresMouseEvents,
               "Overlay never consumes focus or pointer interactions")
        expect(rig.panel.styleMask.contains(.nonactivatingPanel) && !rig.panel.isOpaque && !rig.panel.isFloatingPanel,
               "Native help is transparent, nonactivating and parent-owned")
        expect(rig.host.attachments.count == 1 && rig.host.attachments[0].1 == .below && rig.panel.host === rig.host,
               "Eligible overlay is attached below its host")
        for gate in 0..<4 {
            rig.host.shown = true; rig.host.key = true; rig.host.minimized = false; rig.host.simulatedSheet = nil
            rig.bevel.modifiers(message: "Live help")
            if gate == 0 { rig.host.shown = false }
            if gate == 1 { rig.host.key = false }
            if gate == 2 { rig.host.minimized = true }
            if gate == 3 { rig.host.simulatedSheet = rig.host }
            rig.bevel.reposition()
            expect(rig.bevel.displayedMessage == nil && rig.host.attachments.isEmpty && rig.scheduler.active == 0,
                   "Lifecycle gate clears a shown or fading child and all queued work")
        }
    }

    private static func slotsAndStaleEvents() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "A hover")
        let first = rig.scheduler.latest(0.25)
        expect(rig.bevel.displayedMessage == nil && rig.bevel.panel == nil, "Hover waits the recovered quarter second")
        expect(!rig.scheduler.entries[first].repeats, "Hover uses one delayed delivery")
        rig.bevel.hover(owner: "B", message: "B hover")
        let second = rig.scheduler.latest(0.25)
        expect(!rig.scheduler.entries[first].timer.isValid, "New hover invalidates old pending timer")
        rig.bevel.exit(owner: "A")
        rig.scheduler.fire(first, stale: true)
        expect(rig.bevel.displayedMessage == nil && rig.bevel.panel == nil, "Stale exit and stale timer cannot show old owner")
        rig.bevel.modifiers(message: "Modifier")
        expect(rig.bevel.displayedMessage == "Modifier", "Immediate slot outranks pending hover")
        rig.scheduler.fire(second)
        expect(rig.bevel.displayedMessage == "Modifier", "Ready hover cannot override modifier")
        rig.bevel.exit(owner: "A")
        expect(rig.bevel.displayedMessage == "Modifier", "Stale exit cannot clear either current slot")
        rig.bevel.hover(owner: "C", message: "C hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        expect(rig.bevel.displayedMessage == "Modifier", "Replacing delayed slot retains modifier priority")
        rig.bevel.modifiers(message: nil)
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Modifier release clears BOTH slots immediately, with no hover fallback")
        rig.scheduler.fire(second, stale: true)
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil, "Cleared hover never resurrects from a late callback")
        for message in ["", "  \n  "] {
            rig.bevel.hover(owner: "D", message: "Pending")
            let pending = rig.scheduler.latest(0.25)
            rig.bevel.modifiers(message: "Immediate")
            rig.bevel.modifiers(message: message)
            rig.scheduler.fire(pending, stale: true)
            expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0,
                   "Empty modifier help also clears both queued/live slots")
        }
        rig.bevel.hover(owner: "E", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        expect(rig.bevel.displayedMessage == "Hover", "Delayed slot alone becomes visible")
        rig.bevel.modifiers(message: "Key help")
        rig.bevel.exit(owner: "E")
        expect(rig.bevel.displayedMessage == nil, "Current owner exit uses original hideHelp, clearing both slots")
        rig.bevel.clear()
        rig.bevel.enabled = false
        rig.bevel.enabled = true
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0, "Re-enable cannot replay old help")
    }

    private static func fadesAndReversal() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        let show = rig.scheduler.latest(0.02)
        expect(rig.panel.alphaValue == 0 && rig.scheduler.entries[show].repeats, "Show starts from transparent at 20ms ticks")
        rig.scheduler.fire(show)
        expect(near(rig.panel.alphaValue, 0.15), "Original first show tick adds 0.15")
        rig.scheduler.fire(show)
        expect(near(rig.panel.alphaValue, 0.30), "Original second show tick adds 0.15")
        rig.bevel.exit(owner: "A")
        let hide = rig.scheduler.latest(0.02)
        expect(!rig.scheduler.entries[show].timer.isValid, "Hide replaces and invalidates show timer")
        rig.scheduler.fire(hide)
        expect(near(rig.panel.alphaValue, 0.20), "Original hide tick subtracts 0.1")
        rig.scheduler.fire(show, stale: true)
        expect(near(rig.panel.alphaValue, 0.20), "Cancelled show callback cannot alter fading child")
        rig.bevel.modifiers(message: "Replacement")
        let replacement = rig.scheduler.latest(0.02)
        expect(!rig.scheduler.entries[hide].timer.isValid, "New help reverses fade from current alpha")
        rig.scheduler.fire(hide, stale: true)
        expect(rig.bevel.displayedMessage == "Replacement" && near(rig.panel.alphaValue, 0.20),
               "Cancelled hide callback cannot detach or darken replacement help")
        expect(rig.scheduler.finishFade() == 6 && rig.panel.alphaValue == 1 && rig.scheduler.active == 0,
               "Reversed show is bounded, clamps to one and stops its timer")
        rig.bevel.hover(owner: "B", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        rig.bevel.exit(owner: "B")
        expect(rig.scheduler.finishFade() == 10 && rig.panel.alphaValue == 0 && rig.host.attachments.isEmpty,
               "Original float arithmetic gives ten hide ticks and detaches at zero")
        rig.bevel.modifiers(message: "Again")
        expect(rig.scheduler.finishFade() == 7 && rig.panel.alphaValue == 1,
               "Show from zero is seven recovered ticks")
        expect(replacement != show && rig.panel.fronts == 2, "Reuse does not duplicate attachment or order while already attached")
        rig.bevel.modifiers(message: nil)
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 1 && rig.host.attachments.count == 1,
               "Modifier release clears both slots through original fade-out, retaining child until zero")
        let release = rig.scheduler.latest(0.02)
        rig.scheduler.fire(release)
        expect(near(rig.panel.alphaValue, 0.9), "Modifier release uses recovered -0.1 alpha step")
        expect(rig.scheduler.finishFade() == 9 && rig.host.attachments.isEmpty,
               "Remaining modifier hide ticks detach without bringing hover back")
        rig.bevel.modifiers(message: "Before preference toggle")
        rig.bevel.hover(owner: "C", message: "Queued")
        let pending = rig.scheduler.latest(0.25)
        rig.bevel.enabled = false
        rig.scheduler.fire(pending, stale: true)
        expect(rig.bevel.displayedMessage == nil && rig.panel.alphaValue == 0 && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Turning off cancels every delay/fade and immediately removes child")
    }

    private static func layoutAndRendering() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.modifiers(message: "Hold Shift to constrain")
        let view = rig.panel.contentView as! OriginalHelpBevelView
        expect(rig.panel.frame == NSRect(x: -660, y: 600, width: 720, height: 47),
               "Recovered host +40/top/width-80 and nib44+3 geometry, including negative display coordinates")
        expect(view.textRect.minX == 3 && view.textRect.width == 714 && view.bounds.contains(view.textRect),
               "Recovered three-point inner inset and all text within readable body")
        let font = view.attributedMessage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let paragraph = view.attributedMessage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        expect(font.pointSize == 20 && paragraph.alignment == .center && paragraph.lineBreakMode == .byWordWrapping && paragraph.lineHeightMultiple >= 1.5,
               "Readable centered 20-point multiline text replaces original 14-point middle truncation")
        expect(view.accessibilityValue() as? String == "Hold Shift to constrain", "Full message is accessible")
        let path = view.backgroundPath
        expect(path.bounds == NSRect(x: 1, y: -11, width: 718, height: 57) && path.lineWidth == 2,
               "Original inset1/y-12/height+12 stroke2 extends behind host join")
        rig.host.setFrame(NSRect(x: 50, y: -100, width: 440, height: 300), display: false)
        rig.bevel.reposition()
        expect(rig.panel.frame.minX == 90 && rig.panel.frame.minY == 200 && rig.panel.frame.width == 360,
               "Parent move/resize repositions same attachment using original constants")
        let long = String(repeating: "Hold Option to sample a color, then continue drawing. ", count: 8)
        rig.bevel.modifiers(message: long)
        expect(rig.panel.frame.height > 47 && view.message == long && view.bounds.contains(view.textRect),
               "Long message grows vertically without clipping, truncating or shrinking font")
        let measured = view.attributedMessage.boundingRect(with: NSSize(width: view.textRect.width, height: .greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        expect(ceil(measured.height) <= view.textRect.height && rig.panel.frame.height == max(44, ceil(measured.height)) + 3,
               "Actual text measurement determines sufficient multiline body height plus original allowance")
        let raster = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: raster)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let color = raster.colorAt(x: Int(view.bounds.midX), y: 2)!.usingColorSpace(.deviceRGB)!
        expect(abs(color.alphaComponent - 0.85) < 0.03 && color.redComponent < 0.1,
               "Offscreen production renderer uses recovered translucent black background")
        let stroke = raster.colorAt(x: 1, y: Int(view.bounds.midY))!.usingColorSpace(.deviceRGB)!
        expect(abs(stroke.redComponent - 0.95) < 0.03 && stroke.alphaComponent > 0.99,
               "Offscreen production renderer uses recovered opaque 0.95 gray stroke")
        expect(raster.bitmapData!.withMemoryRebound(to: UInt8.self, capacity: raster.bytesPerRow * raster.pixelsHigh) {
            buffer in (0..<(raster.bytesPerRow * raster.pixelsHigh)).contains { buffer[$0] > 220 }
        }, "Production raster includes visible light text/stroke")
        rig.host.setFrame(NSRect(x: 0, y: 0, width: 85, height: 200), display: false)
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil && rig.host.attachments.isEmpty && rig.scheduler.active == 0,
               "Exhausted original width clears instead of producing an unreadable or resurrected child")
    }

    private static func teardownAndReachability() {
        let rig = make()
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "Pending")
        let pending = rig.scheduler.latest(0.25)
        rig.bevel.modifiers(message: "Live")
        let fade = rig.scheduler.latest(0.02)
        let panel = rig.panel
        rig.bevel.shutdown()
        rig.scheduler.fire(pending, stale: true); rig.scheduler.fire(fade, stale: true)
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "B", message: "Rejected")
        rig.bevel.modifiers(message: "Rejected")
        rig.bevel.reposition()
        rig.bevel.shutdown()
        expect(panel.closes == 1 && rig.bevel.panel == nil && rig.bevel.displayedMessage == nil,
               "Permanent idempotent shutdown closes exactly one owned panel")
        expect(rig.factoryCalls.count == 1 && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Late events and timers cannot reopen or allocate after shutdown")
        var bevel: OriginalHelpBevel?
        weak var observedHost: HelpHost?
        autoreleasepool {
            let host = HelpHost(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            observedHost = host
            bevel = OriginalHelpBevel(host: host, makePanel: {
                preconditionFailure("unreachable host cannot construct panel")
            }, scheduler: rig.scheduler)
            // Close the never-ordered native host and drain AppKit's temporary
            // autoreleased registration references before checking our ownership.
            host.close()
        }
        weak let observedBevel = bevel
        expect(observedHost == nil, "Controller does not retain its parent's host")
        bevel!.enabled = true
        bevel!.modifiers(message: "Gone host")
        expect(bevel!.panel == nil && bevel!.displayedMessage == nil, "Released host safely blocks rendering")
        bevel!.shutdown(); bevel = nil
        expect(observedBevel == nil, "No scheduler or callback retains a shut down controller")
    }

    private static func nativeRunLoopModes() {
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            let host = HelpHost(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                styleMask: [.borderless], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            let bevel = OriginalHelpBevel(host: host, makePanel: {
                HelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            })
            bevel.enabled = true
            bevel.modifiers(message: "Mode test")
            let end = Date().addingTimeInterval(0.6)
            while bevel.panel!.alphaValue < 1 && Date() < end {
                _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.03))
            }
            expect(bevel.panel!.alphaValue == 1, "Real native fade timer services \(mode.rawValue) without ordering real windows")
            bevel.shutdown()
        }
    }
}
#endif
