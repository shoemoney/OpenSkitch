import AppKit
import CoreGraphics

struct OriginalCaptureSelection: Equatable, Sendable {
    /// CG global coordinates, top-left origin at the primary display's top.
    let rect: NSRect
    /// Only click-window selections carry an ID; a dragged region stays a region.
    let windowID: CGWindowID?
    let modifiers: NSEvent.ModifierFlags
}

@MainActor
protocol CaptureSelectionPicking: AnyObject, Sendable {
    func begin(windowOnly: Bool, completion: @escaping (Result<OriginalCaptureSelection, Error>) -> Void)
    func cancel()
}

/// Front-to-back, on-screen window metadata. No window image or title is needed.
struct OriginalCaptureWindowRecord: Equatable, Sendable {
    let windowID: CGWindowID
    let rect: NSRect // CG global top-left coordinates.
    var ownerName: String = ""
    var alpha: CGFloat = 1
}

private func pickerFailure(_ code: Int, _ message: String) -> NSError {
    NSError(domain: "OpenSkitch.CapturePicker", code: code,
            userInfo: [NSLocalizedDescriptionKey: message])
}

private func pickerCancellation() -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "Capture selection cancelled."])
}

/// Owns selection only: no screenshot, waiting, app activation, document, or history changes.
@MainActor
final class OriginalCapturePicker: CaptureSelectionPicking {
    typealias DisplayFrames = @MainActor () -> [NSRect]
    typealias WindowRecords = @MainActor () -> [OriginalCaptureWindowRecord]
    typealias PanelFactory = @MainActor (NSRect) -> NSPanel

    private final class Session {
        let id = UUID()
        let windowOnly: Bool
        let completion: (Result<OriginalCaptureSelection, Error>) -> Void
        var displays: [NSRect] = []
        init(windowOnly: Bool, completion: @escaping (Result<OriginalCaptureSelection, Error>) -> Void) {
            self.windowOnly = windowOnly
            self.completion = completion
        }
    }

    private let displayFrames: DisplayFrames
    private let windowRecords: WindowRecords
    private let makePanel: PanelFactory
    private var session: Session?
    private var cleaningUp = false
    private var lifetime: OriginalCapturePicker?
    private(set) var panels: [NSPanel] = []
    var isPicking: Bool { session != nil }

    /// Display frames are AppKit global bottom-left, primary display FIRST.
    /// Records are CG global top-left, in WindowServer front-to-back order.
    /// Tests must inject a factory overriding ALL ordering/focus/close methods.
    init(displayFrames: DisplayFrames? = nil, windowRecords: WindowRecords? = nil,
         makePanel: PanelFactory? = nil) {
        self.displayFrames = displayFrames ?? { NSScreen.screens.map(\.frame) }
        self.windowRecords = windowRecords ?? { Self.nativeWindowRecords() }
        self.makePanel = makePanel ?? { frame in
            OriginalCaptureOverlayPanel(contentRect: frame,
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: true)
        }
    }

    func begin(windowOnly: Bool, completion: @escaping (Result<OriginalCaptureSelection, Error>) -> Void) {
        guard session == nil, !cleaningUp else {
            completion(.failure(pickerFailure(1, "Another capture selection is already in progress.")))
            return
        }
        let request = Session(windowOnly: windowOnly, completion: completion)
        session = request
        lifetime = self // Even a temporary picker survives until selection/cancel.
        let frames = displayFrames()
        guard session?.id == request.id else { return }
        guard !frames.isEmpty, frames.allSatisfy(Self.validRect) else {
            finish(.failure(pickerFailure(2, "No valid display geometry is available.")), id: request.id)
            return
        }
        request.displays = frames
        // CrosshairScreenshot.totalFrame (0x1ce8e): one overlay spans ALL screens.
        let total = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let panel = makePanel(total)
        guard session?.id == request.id else {
            panel.orderOut(nil); panel.close()
            return
        }
        panels = [panel]
        panel.isReleasedWhenClosed = false
        panel.setFrame(total, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false // NSApp.hide must not suppress this owned overlay.
        panel.isFloatingPanel = true
        // pqCHSWindow (0x1fd32): CGWindowLevelForKey(13) + 100.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 100)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        let view = OriginalCaptureSelectionView(frame: NSRect(origin: .zero, size: total.size),
                                                windowOnly: windowOnly)
        view.onSelection = { [weak self] rect, modifiers in
            self?.selected(rect, modifiers: modifiers, id: request.id)
        }
        view.onCancel = { [weak self] in
            self?.finish(.failure(pickerCancellation()), id: request.id)
        }
        panel.contentView = view
        panel.makeFirstResponder(view)
        guard session?.id == request.id else { return }
        // No unhide/activate or editor restoration. The nonactivating panel takes
        // temporary keyboard focus for local Escape instead of original PTHotKey.
        panel.orderFrontRegardless()
        guard session?.id == request.id else { return }
        panel.makeKey()
    }

    func cancel() {
        guard let id = session?.id else { return }
        finish(.failure(pickerCancellation()), id: id)
    }

    private func selected(_ localRect: NSRect, modifiers: NSEvent.ModifierFlags, id: UUID) {
        guard let request = session, request.id == id, let panel = panels.first else { return }
        let global = localRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        guard global.origin.x.isFinite, global.origin.y.isFinite,
              global.width.isFinite, global.height.isFinite,
              global.width >= 0, global.height >= 0 else {
            finish(.failure(pickerCancellation()), id: id)
            return
        }
        let primaryTop = request.displays[0].maxY
        // CrosshairScreenshot.didSnap (0x1d0e3), kMinCrosshairSize at
        // 0x2606d4 = Float(3); DAT_0026045c = Float(3), read from Mach-O.
        if !request.windowOnly && (global.width > 3 || global.height > 3) {
            guard global.width > 0, global.height > 0,
                  request.displays.contains(where: { $0.intersects(global) }) else {
                finish(.failure(pickerCancellation()), id: id)
                return
            }
            finish(.success(OriginalCaptureSelection(rect: Self.flip(global, primaryTop: primaryTop),
                                                    windowID: nil, modifiers: modifiers)), id: id)
            return
        }
        // windowAtLocation is a 1x1 AppKit probe, NOT point containment. Preserve
        // that edge behavior and the original no-layer-filter hit policy.
        let probe = NSRect(origin: global.origin, size: NSSize(width: 1, height: 1))
        let ignored = Set(panels.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
        let records = windowRecords() // Refresh at SELECTION, not at begin.
        guard session?.id == id else { return } // Injected/provider callbacks may cancel/reenter.
        let hit = Self.windowHit(in: records, ignoring: ignored, appKitProbe: probe, primaryTop: primaryTop)
        if let hit {
            finish(.success(OriginalCaptureSelection(rect: hit.rect, windowID: hit.windowID,
                                                    modifiers: modifiers)), id: id)
        } else if !request.windowOnly,
                  let display = request.displays.first(where: { $0.contains(global.origin) }) {
            finish(.success(OriginalCaptureSelection(rect: Self.flip(display, primaryTop: primaryTop),
                                                    windowID: nil, modifiers: modifiers)), id: id)
        } else {
            finish(.failure(pickerCancellation()), id: id)
        }
    }

    /// The actual native hit boundary is pure so ownership filtering can be
    /// tested without allocating/ordering WindowServer overlays to obtain IDs.
    static func windowHit(in records: [OriginalCaptureWindowRecord], ignoring ignored: Set<CGWindowID>,
                          appKitProbe probe: NSRect, primaryTop: CGFloat) -> OriginalCaptureWindowRecord? {
        records.first {
            !ignored.contains($0.windowID) && $0.windowID != 0 && $0.windowID != CGWindowID.max &&
            $0.ownerName != "Dock" && $0.alpha > 0 && Self.validRect($0.rect) &&
            Self.flip($0.rect, primaryTop: primaryTop).intersects(probe)
        }
    }

    private func finish(_ result: Result<OriginalCaptureSelection, Error>, id: UUID) {
        guard let request = session, request.id == id else { return }
        session = nil // Invalidate BEFORE anything that can dispatch late input.
        cleaningUp = true
        let owned = panels
        panels = []
        for panel in owned {
            (panel.contentView as? OriginalCaptureSelectionView)?.invalidate()
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        cleaningUp = false
        lifetime = nil
        request.completion(result) // No overlays remain when the parent starts delay/capture.
    }

    private static func flip(_ rect: NSRect, primaryTop: CGFloat) -> NSRect {
        NSRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func validRect(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
        rect.width > 0 && rect.height > 0
    }

    private static func nativeWindowRecords() -> [OriginalCaptureWindowRecord] {
        // SKCGWindowController.windowIDInRect (0x67ba5): options 0x11,
        // ignore overlay ID, Dock, zero alpha; first intersecting record wins.
        // Bounds/owner/alpha only. This never requests screen image permissions.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { item in
            guard let number = item[kCGWindowNumber as String] as? NSNumber,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return OriginalCaptureWindowRecord(windowID: number.uint32Value, rect: rect,
                                               ownerName: item[kCGWindowOwnerName as String] as? String ?? "",
                                               alpha: (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0)
        }
    }
}

/// Local event routing works without global monitors or app activation.
/// Unlike original canBecomeKey=false + PTHotKey, this panel can receive Escape.
class OriginalCaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        guard !ignoresMouseEvents, let view = contentView as? OriginalCaptureSelectionView else { return }
        switch event.type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        case .mouseMoved: view.mouseMoved(with: event)
        case .rightMouseUp: view.rightMouseUp(with: event)
        case .keyDown: view.keyDown(with: event)
        default: super.sendEvent(event)
        }
    }
}

final class OriginalCaptureSelectionView: NSView {
    var onSelection: ((NSRect, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    private let windowOnly: Bool
    private var live = true
    private var anchor: NSPoint?
    private var cursorPoint: NSPoint?
    private(set) var selectionRect: NSRect?
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, windowOnly: Bool) {
        self.windowOnly = windowOnly
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }

    func invalidate() {
        live = false; anchor = nil; cursorPoint = nil; selectionRect = nil
        onSelection = nil; onCancel = nil
    }
    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        // Original converts local coordinates to int (truncation toward zero).
        return NSPoint(x: p.x.rounded(.towardZero), y: p.y.rounded(.towardZero))
    }
    override func mouseMoved(with event: NSEvent) {
        guard live else { return }
        cursorPoint = point(event); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard live, anchor == nil else { return }
        let p = point(event)
        // pqCHSView.mouseDown (0x1f140), DAT_00260470 = Float(1).
        anchor = NSPoint(x: p.x + 1, y: p.y)
        selectionRect = NSRect(origin: anchor!, size: .zero)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard live, let a = anchor, !windowOnly else { return }
        let p = point(event)
        selectionRect = NSRect(x: min(a.x, p.x), y: min(a.y, p.y),
                               width: abs(a.x - p.x), height: abs(a.y - p.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard live, anchor != nil, var rect = selectionRect else { return }
        if windowOnly {
            let p = point(event)
            rect = NSRect(x: p.x + 1, y: p.y, width: 0, height: 0)
        }
        live = false // Reject duplicate up before callback reentry/cleanup.
        onSelection?(rect, event.modifierFlags)
    }
    override func rightMouseUp(with event: NSEvent) {
        guard live else { return }
        live = false; onCancel?()
    }
    override func keyDown(with event: NSEvent) {
        guard live else { return }
        if event.keyCode == 53 { live = false; onCancel?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard live else { return }
        if let rect = selectionRect {
            // pqCHSView.drawRect (0x1e574): 0x181818 / alpha .65,
            // outside the reversed rectangle path; clear inside the cutout.
            let shade = NSBezierPath(rect: bounds)
            shade.windingRule = .evenOdd
            shade.append(NSBezierPath(rect: rect))
            NSColor(deviceRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 0.65).setFill()
            shade.fill()
            if rect.width > 3, rect.height > 3 { drawSize(rect) }
        } else if let p = cursorPoint {
            // Original 3-point white .2 stroke, then 1-point black .4.
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: p.x + 0.5, y: bounds.minY))
            cross.line(to: NSPoint(x: p.x + 0.5, y: bounds.maxY))
            cross.move(to: NSPoint(x: bounds.minX, y: p.y + 2.5))
            cross.line(to: NSPoint(x: bounds.maxX, y: p.y + 2.5))
            NSColor(calibratedWhite: 1, alpha: 0.2).setStroke(); cross.lineWidth = 3; cross.stroke()
            NSColor(calibratedWhite: 0, alpha: 0.4).setStroke(); cross.lineWidth = 1; cross.stroke()
        }
    }

    private func drawSize(_ rect: NSRect) {
        // Original "%dx%dpx", rounded white .75/radius5 bezel. Font20
        // replaces original LucidaGrande10 for the user's readability floor.
        let text = "\(Int(rect.width))x\(Int(rect.height))px" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]
        let size = text.size(withAttributes: attributes)
        guard bounds.width >= size.width + 12, bounds.height >= size.height + 8 else { return }
        let origin = NSPoint(x: min(max(rect.maxX + 4, bounds.minX + 6), bounds.maxX - size.width - 6),
                             y: min(max(rect.maxY + 4, bounds.minY + 4), bounds.maxY - size.height - 4))
        let bezel = NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -4)
        NSColor(calibratedWhite: 1, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: bezel, xRadius: 5, yRadius: 5).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
