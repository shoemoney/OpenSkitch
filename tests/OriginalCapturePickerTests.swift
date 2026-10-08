// All events are constructed locally and delivered to a NONORDERING panel.
// No screen/window providers, desktop input, capture processes, or permissions.
// rtk proxy xcrun swiftc -swift-version 6 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D ORIGINAL_CAPTURE_PICKER_TESTS \
//   Sources/OriginalCapturePicker.swift tests/OriginalCapturePickerTests.swift -o build/original-capture-picker-tests
// rtk proxy build/original-capture-picker-tests
#if ORIGINAL_CAPTURE_PICKER_TESTS
import AppKit
import CoreGraphics

private final class PickerPanel: OriginalCaptureOverlayPanel {
    var fronts = 0
    var keys = 0
    var outs = 0
    var closes = 0
    var onClose: (() -> Void)?
    var onFront: (() -> Void)?
    var onResponder: (() -> Void)?
    override func orderFrontRegardless() { fronts += 1; onFront?() }
    override func makeKey() { keys += 1 }
    override func orderFront(_ sender: Any?) { preconditionFailure("must use intercepted ordering") }
    override func orderBack(_ sender: Any?) { preconditionFailure("must never order real panels") }
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        preconditionFailure("must never order real panels")
    }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("must not activate/order") }
    override func orderOut(_ sender: Any?) { outs += 1 }
    override func close() { closes += 1; onClose?() }
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        onResponder?()
        return true // No WindowServer focus; events use the production sendEvent path.
    }
}

@MainActor
private final class PickerRig {
    var displays = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
    var records: [OriginalCaptureWindowRecord] = []
    var displayCalls = 0
    var recordCalls = 0
    var created: [PickerPanel] = []
    var results: [Result<OriginalCaptureSelection, Error>] = []
    var onRecords: (() -> Void)?
    var onFactory: ((PickerPanel) -> Void)?
    lazy var picker = OriginalCapturePicker(displayFrames: { [unowned self] in
        self.displayCalls += 1; return self.displays
    }, windowRecords: { [unowned self] in
        self.recordCalls += 1; self.onRecords?(); return self.records
    }, makePanel: { [unowned self] rect in
        let panel = PickerPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
        self.created.append(panel); self.onFactory?(panel)
        return panel
    }, screenImage: { _ in nil })
    var panel: PickerPanel { picker.panels.first as! PickerPanel }
    var view: OriginalCaptureSelectionView { panel.contentView as! OriginalCaptureSelectionView }
    func begin(windowOnly: Bool = false, onResult: ((Result<OriginalCaptureSelection, Error>) -> Void)? = nil) {
        picker.begin(windowOnly: windowOnly) { [unowned self] result in
            self.results.append(result); onResult?(result)
        }
    }
    func event(_ type: NSEvent.EventType, _ global: NSPoint = .zero,
               flags: NSEvent.ModifierFlags = [], panel supplied: PickerPanel? = nil) -> NSEvent {
        let panel = supplied ?? self.panel
        let local = NSPoint(x: global.x - panel.frame.minX, y: global.y - panel.frame.minY)
        return NSEvent.mouseEvent(with: type, location: local, modifierFlags: flags, timestamp: 1,
                                 windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                                 clickCount: 1, pressure: 1)!
    }
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, flags: NSEvent.ModifierFlags = []) {
        panel.sendEvent(event(type, point, flags: flags))
    }
    func click(_ point: NSPoint, downFlags: NSEvent.ModifierFlags = [], upFlags: NSEvent.ModifierFlags = []) {
        mouse(.leftMouseDown, point, flags: downFlags); mouse(.leftMouseUp, point, flags: upFlags)
    }
    func drag(_ a: NSPoint, _ b: NSPoint, downFlags: NSEvent.ModifierFlags = [], upFlags: NSEvent.ModifierFlags = []) {
        mouse(.leftMouseDown, a, flags: downFlags)
        mouse(.leftMouseDragged, b)
        mouse(.leftMouseUp, b, flags: upFlags)
    }
    func key(_ code: UInt16, panel supplied: PickerPanel? = nil) {
        let panel = supplied ?? self.panel
        panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 1, windowNumber: panel.windowNumber, context: nil,
                                        characters: code == 53 ? "\u{1b}" : "a",
                                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    var selection: OriginalCaptureSelection {
        guard case .success(let selection) = results.last! else { preconditionFailure("Expected selection") }
        return selection
    }
    var error: NSError {
        guard case .failure(let error) = results.last! else { preconditionFailure("Expected failure") }
        return error as NSError
    }
}

@main
@MainActor
private enum OriginalCapturePickerTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        _ = NSApplication.shared
        geometryAndModifiers()
        originalTinyAndWindowHitPolicy()
        cancellationAndBusy()
        reentrancyAndStaleEvents()
        rendering()
        reachability()
        magnifier()
        print("PASS OriginalCapturePickerTests (\(checks) checks; nonordering panels, local events, no desktop/permissions)")
    }
    private static func magnifier() {
        typealias G = OriginalCaptureMagnifierGeometry
        expect(G.zoom == 10 && G.sourcePixels == NSSize(width: 10, height: 10), "Zoom 10 over 10x10 source (decompiled.c:68880)")
        expect(G.magnifierRect == NSRect(x: 6, y: 6, width: 100, height: 100), "magnifierRect (69416)")
        expect(G.magnifierBorderRect == NSRect(x: 3, y: 3, width: 106, height: 106), "border inset -3 (69437)")
        expect(G.requiredDisplaySize(labelRect: NSRect(x: 6, y: 112, width: 80, height: 14)) == NSSize(width: 112, height: 129),
               "requiredDisplaySize is inset(-3) of border union label (69338)")
        // DAT_00260520 = -2.0f (disassembly 0x1e417: movss 0x242463(%ebx), ebx=0x1e0bd).
        expect(G.placementOffset == -2, "Placement offset DAT_00260520")
        expect(G.sourceRect(mousePoint: NSPoint(x: 40, y: 50)) == NSRect(x: 35, y: 45, width: 11, height: 11),
               "Source square (mouse+0.5 inset by 5) made integral spans 11 points")
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 112, height: 129)
        expect(G.placementFrame(mousePoint: NSPoint(x: 500, y: 400), requiredSize: size, in: bounds)
               == NSRect(x: 386, y: 269, width: 112, height: 129), "Frame = mouse - required size - 2")
        expect(G.placementFrame(mousePoint: NSPoint(x: 5, y: 5), requiredSize: size, in: bounds).origin == .zero,
               "Clamped to the overlay origin side")
        expect(G.placementFrame(mousePoint: NSPoint(x: 5000, y: 5000), requiredSize: size, in: bounds)
               == NSRect(x: 888, y: 671, width: 112, height: 129), "Clamped to the far overlay side")

        let suite = "OpenSkitch.magnifier.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let off = OriginalCaptureSelectionView(frame: bounds, windowOnly: false, defaults: defaults)
        off.mountMagnifierIfEnabled(pointer: NSPoint(x: 500, y: 400))
        expect(off.magnifier == nil && off.subviews.isEmpty, "Preference off mounts nothing")
        defaults.set(true, forKey: G.defaultsKey)
        let view = OriginalCaptureSelectionView(frame: bounds, windowOnly: false, defaults: defaults)
        view.mountMagnifierIfEnabled(pointer: NSPoint(x: 500, y: 400))
        guard let mag = view.magnifier else { preconditionFailure("Preference on mounts the magnifier") }
        expect(mag.superview === view && mag.isFlipped && mag.mousePoint == NSPoint(x: 500, y: 400) && mag.labelString == "500x400",
               "Mounted, flipped, fed the pointer and the %dx%d label")
        expect(mag.frame.size == mag.requiredDisplaySize && mag.frame.origin.x == 500 - mag.frame.width - 2
               && mag.frame.origin.y == 400 - mag.frame.height - 2, "Placed up-left of the pointer by required size + offset")
        view.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 3, y: 4), modifierFlags: [], timestamp: 1,
                                                 windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!)
        expect(mag.mousePoint == NSPoint(x: 3, y: 4) && bounds.contains(mag.frame) && mag.frame.origin == .zero,
               "Follows the pointer and stays clamped inside the overlay")
        view.invalidate()
        expect(mag.superview == nil && view.magnifier == nil, "Invalidate unmounts the magnifier")

        // Live feed: the picker asks the provider once for the total frame and hands the pixels to the view.
        let pixel = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixel.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); pixel.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let screen = pixel.makeImage()!
        var asked: [NSRect] = []
        let feeding = OriginalCapturePicker(displayFrames: { [NSRect(x: 0, y: 0, width: 600, height: 400), NSRect(x: 600, y: 0, width: 400, height: 800)] },
                                            windowRecords: { [] },
                                            makePanel: { PickerPanel(contentRect: $0, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true) },
                                            screenImage: { asked.append($0); return OriginalCaptureScreenImage(image: screen, scale: 2) })
        feeding.begin(windowOnly: false) { _ in }
        expect(asked == [bounds], "Provider called once with the total overlay frame at begin")
        let fed = feeding.panels[0].contentView as! OriginalCaptureSelectionView
        expect(fed.magnifierImage === screen && fed.magnifierImageScale == 2, "View carries the provided image and scale")
        defaults.set(true, forKey: G.defaultsKey)
        let live = OriginalCaptureSelectionView(frame: bounds, windowOnly: false, defaults: defaults)
        live.magnifierImage = screen; live.magnifierImageScale = 2
        live.mountMagnifierIfEnabled(pointer: NSPoint(x: 500, y: 400))
        expect(live.magnifier?.sourceImage === screen && live.magnifier?.imageScale == 2, "Mounted lens samples the provided image")
        feeding.cancel()
    }
    private static func cleaned(_ rig: PickerRig, _ count: Int = 1) {
        expect(!rig.picker.isPicking && rig.picker.panels.isEmpty && rig.results.count == count,
               "One result, selection no longer busy, overlays removed")
        expect(rig.created.allSatisfy { $0.closes == 1 && $0.outs == 1 && $0.contentView == nil && $0.ignoresMouseEvents },
               "Every owned panel closed once and cannot dispatch input")
    }

    private static func geometryAndModifiers() {
        let rig = PickerRig()
        expect(rig.created.isEmpty && !rig.picker.isPicking && rig.displayCalls == 0, "Construction is lazy")
        rig.displays += [NSRect(x: -600, y: -100, width: 600, height: 500),
                         NSRect(x: 250, y: 800, width: 500, height: 400),
                         NSRect(x: 100, y: -400, width: 600, height: 400)]
        rig.begin { _ in
            expect(rig.picker.panels.isEmpty && rig.created[0].closes == 1,
                   "Parent countdown/capture callback sees complete overlay cleanup")
        }
        let panel = rig.panel
        expect(panel.frame == NSRect(x: -600, y: -400, width: 1600, height: 1600), "Original overlay union covers left/above/below displays")
        expect(panel.fronts == 1 && panel.keys == 1 && panel.canBecomeKey && !panel.canBecomeMain,
               "Local keyboard input uses temporary nonactivating key panel")
        expect(panel.styleMask.contains(.nonactivatingPanel) && !panel.canHide && !panel.hidesOnDeactivate,
               "App hiding and deactivation cannot intentionally hide the overlay")
        expect(panel.level.rawValue == Int(CGWindowLevelForKey(.popUpMenuWindow)) + 100 && !panel.hasShadow && !panel.isOpaque && !panel.isMovable,
               "Recovered popup level+100, transparency, no shadow or window dragging")
        rig.drag(NSPoint(x: -300.9, y: -150.8), NSPoint(x: 450.7, y: 990.9), downFlags: [.option], upFlags: [.shift, .command])
        expect(rig.selection.rect == NSRect(x: -300, y: -190, width: 750, height: 1141),
               "Local truncation/+1 x and PRIMARY top baseline, not union top, across all displays")
        expect(rig.selection.windowID == nil && rig.selection.modifiers == [.shift, .command],
               "Dragged region and modifiers at selection, independent of initial Option")
        expect(rig.recordCalls == 0 && rig.displayCalls == 1, "Region selection never needs a window list or another wait")
        cleaned(rig)

        let cases: [(NSPoint, NSRect)] = [
            (NSPoint(x: 170.9, y: 150.9), NSRect(x: 101, y: 650, width: 69, height: 50)),
            (NSPoint(x: 30.9, y: 150.9), NSRect(x: 30, y: 650, width: 71, height: 50)),
            (NSPoint(x: 30.9, y: 50.9), NSRect(x: 30, y: 700, width: 71, height: 50)),
            (NSPoint(x: 170.9, y: 50.9), NSRect(x: 101, y: 700, width: 69, height: 50))
        ]
        for (end, expected) in cases {
            let r = PickerRig(); r.begin()
            r.drag(NSPoint(x: 100.9, y: 100.9), end, downFlags: [.shift], upFlags: [])
            expect(r.selection.rect == expected && r.selection.modifiers.isEmpty,
                   "All four drag quadrants; initial Shift cannot make delayed capture sticky")
            cleaned(r)
        }
        let r = PickerRig(); r.begin()
        r.mouse(.leftMouseDown, NSPoint(x: 100, y: 100))
        r.mouse(.leftMouseDragged, NSPoint(x: 170, y: 150))
        r.mouse(.leftMouseUp, NSPoint(x: 190, y: 190))
        expect(r.selection.rect == NSRect(x: 101, y: 650, width: 69, height: 50),
               "Original mouse-up uses the last drag rectangle rather than inventing a new endpoint")
        cleaned(r)
    }

    private static func originalTinyAndWindowHitPolicy() {
        let rig = PickerRig()
        let window = OriginalCaptureWindowRecord(windowID: 42, rect: NSRect(x: 20.5, y: 100, width: 250, height: 250))
        rig.records = [OriginalCaptureWindowRecord(windowID: 1, rect: window.rect, ownerName: "Dock"),
                       OriginalCaptureWindowRecord(windowID: 2, rect: window.rect, alpha: 0),
                       OriginalCaptureWindowRecord(windowID: 3, rect: NSRect(x: CGFloat.infinity, y: 0, width: 10, height: 10))]
        rig.begin()
        expect(rig.recordCalls == 0, "Click hit testing refreshes after selection")
        rig.records += [window, OriginalCaptureWindowRecord(windowID: 43, rect: window.rect)]
        let owned = OriginalCaptureWindowRecord(windowID: 404, rect: NSRect(x: 0, y: 0, width: 1000, height: 800))
        expect(OriginalCapturePicker.windowHit(in: [owned] + rig.records, ignoring: [404],
                                              appKitProbe: NSRect(x: 20, y: 600, width: 1, height: 1), primaryTop: 800) == window,
               "Production hit boundary skips owned overlay even when it is first and covers every screen")
        rig.click(NSPoint(x: 19, y: 600), upFlags: [.shift])
        expect(rig.selection.windowID == 42 && rig.selection.rect == window.rect && rig.recordCalls == 1,
               "Frontmost 1x1 intersecting hit includes fractional window edge; ignores Dock/transparent/invalid")
        expect(rig.selection.modifiers == [.shift], "Click-window returns selected-time Shift")
        cleaned(rig)

        for (dx, dy, isWindow) in [(3, 3, true), (0, 3, true), (3, 0, true), (4, 3, false), (3, 4, false), (1, 8, false)] {
            let r = PickerRig(); r.records = [window]; r.begin()
            r.drag(NSPoint(x: 99, y: 600), NSPoint(x: 100 + dx, y: 600 + dy))
            expect((r.selection.windowID == 42) == isWindow, "Recovered <=3 BOTH dimensions click threshold including tiny line")
            if !isWindow { expect(r.selection.rect.width == CGFloat(dx) && r.selection.rect.height == CGFloat(dy), "No invented minimum for valid thin region") }
            cleaned(r)
        }
        for end in [NSPoint(x: 100, y: 620), NSPoint(x: 120, y: 600)] {
            let r = PickerRig(); r.records = [window]; r.begin()
            r.drag(NSPoint(x: 99, y: 600), end)
            expect(r.error.domain == NSCocoaErrorDomain && r.error.code == NSUserCancelledError && r.recordCalls == 0,
                   "Original long zero-area selections abort before window hit")
            cleaned(r)
        }
        let left = PickerRig()
        left.displays += [NSRect(x: -600, y: -100, width: 600, height: 500)]
        left.begin(); left.click(NSPoint(x: -300, y: 200))
        expect(left.selection.rect == NSRect(x: -600, y: 400, width: 600, height: 500) && left.selection.windowID == nil,
               "Original empty-background click falls back to clicked display, not main/union")
        cleaned(left)
        let gap = PickerRig()
        gap.displays += [NSRect(x: 1200, y: 0, width: 800, height: 800)]
        gap.begin(); gap.click(NSPoint(x: 1100, y: 100))
        expect(gap.error.code == NSUserCancelledError, "Click in display gap cannot invent a display")
        cleaned(gap)
        let gapRegion = PickerRig(); gapRegion.displays = gap.displays; gapRegion.begin()
        gapRegion.drag(NSPoint(x: 1050, y: 50), NSPoint(x: 1150, y: 150))
        expect(gapRegion.error.code == NSUserCancelledError, "Region wholly inside display gap aborts")
        cleaned(gapRegion)

        let only = PickerRig(); only.records = [window]; only.begin(windowOnly: true)
        only.drag(NSPoint(x: 800, y: 700), NSPoint(x: 99, y: 600), upFlags: [.shift])
        expect(only.selection.windowID == 42 && only.selection.rect == window.rect,
               "Explicit windowOnly cannot accidentally return a region when mouse moves")
        cleaned(only)
        let miss = PickerRig(); miss.begin(windowOnly: true); miss.click(NSPoint(x: 400, y: 400))
        expect(miss.error.code == NSUserCancelledError, "Explicit windowOnly never returns a whole display on miss")
        cleaned(miss)
    }

    private static func cancellationAndBusy() {
        for how in 0..<3 {
            let r = PickerRig(); r.begin()
            let panel = r.panel; let view = r.view
            r.key(0)
            expect(r.picker.isPicking && r.results.isEmpty, "Non-Escape key does not cancel")
            r.mouse(.leftMouseUp, NSPoint(x: 50, y: 50))
            expect(r.results.isEmpty, "Unpaired mouse-up cannot select")
            if how == 0 { r.picker.cancel() }
            else if how == 1 { r.key(53) }
            else { r.mouse(.rightMouseUp, NSPoint(x: 100, y: 100)) }
            expect(r.error.domain == NSCocoaErrorDomain && r.error.code == NSUserCancelledError,
                   "Programmatic cancel/Escape/right-click use standard capture cancellation")
            r.picker.cancel(); r.key(53, panel: panel)
            view.mouseDown(with: r.event(.leftMouseDown, panel: panel))
            view.mouseUp(with: r.event(.leftMouseUp, panel: panel))
            cleaned(r)
        }
        let busy = PickerRig(); busy.begin()
        let accepted = busy.panel
        busy.begin(windowOnly: true)
        expect(busy.error.domain == "OpenSkitch.CapturePicker" && busy.error.code == 1 && busy.picker.isPicking && busy.panel === accepted,
               "Differently configured busy request fails without changing accepted selection")
        busy.drag(NSPoint(x: 20, y: 20), NSPoint(x: 100, y: 100))
        expect(busy.selection.windowID == nil && busy.selection.rect == NSRect(x: 21, y: 700, width: 79, height: 80),
               "Busy window-only request cannot overwrite accepted region mode")
        cleaned(busy, 2)
        for frames in [[], [NSRect(x: 0, y: 0, width: 0, height: 100)], [NSRect(x: 0, y: CGFloat.nan, width: 100, height: 100)]] {
            let r = PickerRig(); r.displays = frames; r.begin()
            expect(r.error.code == 2 && r.created.isEmpty && !r.picker.isPicking && r.results.count == 1,
                   "Missing/invalid display fails once before panel allocation")
        }
    }

    private static func reentrancyAndStaleEvents() {
        let r = PickerRig(); r.begin()
        let oldView = r.view; let oldPanel = r.panel
        let staleSelection = oldView.onSelection!
        let staleCancel = oldView.onCancel!
        r.picker.cancel(); r.begin()
        staleSelection(NSRect(x: 20, y: 20, width: 100, height: 100), [.shift]); staleCancel()
        r.key(53, panel: oldPanel)
        expect(r.results.count == 1 && r.picker.isPicking && r.created.count == 2,
               "Old closure/native input cannot finish the newer generation")
        r.drag(NSPoint(x: 20, y: 20), NSPoint(x: 100, y: 100)); cleaned(r, 2)

        let querying = PickerRig(); querying.begin()
        querying.onRecords = {
            querying.onRecords = nil
            querying.picker.cancel(); querying.begin()
        }
        querying.click(NSPoint(x: 200, y: 200))
        expect(querying.results.count == 1 && querying.picker.isPicking && querying.created.count == 2,
               "Window provider cancellation/reentry cannot complete replacement request")
        querying.picker.cancel(); cleaned(querying, 2)

        let teardown = PickerRig(); teardown.begin { result in
            if case .success = result { teardown.begin() }
        }
        teardown.panel.onClose = {
            teardown.panelIfAnyMustBeAbsent()
            teardown.begin()
        }
        teardown.drag(NSPoint(x: 20, y: 20), NSPoint(x: 100, y: 100))
        expect(teardown.results.count == 2 && teardown.picker.isPicking && teardown.created.count == 2,
               "Close-time begin rejected; success callback can begin AFTER complete cleanup")
        teardown.picker.cancel(); cleaned(teardown, 3)

        for duringResponder in [false, true] {
            let cancelling = PickerRig()
            cancelling.onFactory = { panel in
                if duringResponder { panel.onResponder = { cancelling.picker.cancel() } }
                else { panel.onFront = { cancelling.picker.cancel() } }
            }
            cancelling.begin()
            expect(cancelling.created[0].keys == 0 && cancelling.created[0].fronts == (duringResponder ? 0 : 1),
                   "Cancellation from native boundary prevents any subsequent ordering/focus")
            cleaned(cancelling)
        }
        let factory = PickerRig()
        factory.onFactory = { _ in factory.picker.cancel() }
        factory.begin()
        expect(factory.created[0].fronts == 0 && factory.created[0].keys == 0 && factory.created[0].closes == 1 && factory.results.count == 1,
               "Canceled constructor's late-returned panel closed without ever ordering")
    }

    private static func raster(_ view: NSView) -> NSBitmapImageRep {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return image
    }
    private static func rendering() {
        let r = PickerRig(); r.displays = [NSRect(x: 0, y: 0, width: 400, height: 300)]; r.begin()
        let initial = raster(r.view)
        expect(initial.colorAt(x: 200, y: 150)!.alphaComponent == 0, "Original before-first-input background stays clear")
        r.mouse(.mouseMoved, NSPoint(x: 100, y: 100))
        let cross = raster(r.view)
        expect(cross.colorAt(x: 100, y: 20)!.alphaComponent > 0 && cross.colorAt(x: 20, y: 197)!.alphaComponent > 0,
               "Production crosshair renderer draws full-height/full-width recovered strokes")
        r.mouse(.leftMouseDown, NSPoint(x: 99, y: 50))
        r.mouse(.leftMouseDragged, NSPoint(x: 240, y: 190))
        let image = raster(r.view)
        let shade = image.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        expect(abs(shade.alphaComponent - 0.65) < 0.02 && abs(shade.redComponent - 24 / 255) < 0.02,
               "Recovered 0x181818/alpha .65 dimming outside actual selection")
        expect(image.colorAt(x: 150, y: 170)!.alphaComponent == 0,
               "Real offscreen raster leaves selected cutout fully transparent")
        let labelPixels = (190..<240).contains { y in (240..<395).contains { x in image.colorAt(x: x, y: 300 - y - 1)!.redComponent > 0.4 } }
        expect(labelPixels, "Production size label renders outside cutout with readable adapted type")
        r.picker.cancel(); cleaned(r)
    }

    private static func reachability() {
        weak var observedPicker: OriginalCapturePicker?
        weak var observedView: OriginalCaptureSelectionView?
        weak var observedPanel: PickerPanel?
        var completions = 0
        autoreleasepool {
            var picker: OriginalCapturePicker? = OriginalCapturePicker(displayFrames: {
                [NSRect(x: 0, y: 0, width: 1000, height: 800)]
            }, windowRecords: { [] }, makePanel: {
                PickerPanel(contentRect: $0, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            }, screenImage: { _ in nil })
            picker!.begin(windowOnly: false) { _ in completions += 1 }
            observedPicker = picker
            observedPanel = picker!.panels[0] as? PickerPanel
            observedView = picker!.panels[0].contentView as? OriginalCaptureSelectionView
            picker = nil
            expect(observedPicker != nil, "Temporary picker owns active request until input/cancel")
            observedPanel!.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                                     windowNumber: observedPanel!.windowNumber, context: nil, characters: "\u{1b}",
                                                     charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!)
        }
        expect(completions == 1 && observedPicker == nil && observedView == nil,
               "Completion clears self lifetime and callback/view ownership; no retain cycle")
        // NSWindow's registration can retain never-ordered test windows. The
        // intercepted close intentionally avoids all WindowServer operations.
        expect(observedPanel == nil || observedPanel!.contentView == nil,
               "Any AppKit registered panel retains no picker/view/input callback")
    }
}

@MainActor
private extension PickerRig {
    func panelIfAnyMustBeAbsent() {
        precondition(picker.panels.isEmpty && !picker.isPicking, "Invalidate before native teardown")
    }
}
#endif
