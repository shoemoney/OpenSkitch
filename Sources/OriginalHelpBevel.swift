import AppKit

@MainActor
protocol OriginalHelpBevelScheduling {
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer
}

@MainActor
private struct NativeHelpBevelScheduler: OriginalHelpBevelScheduling {
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { timer in
            let keepRunning = MainActor.assumeIsolated { action() }
            if !keepRunning { timer.invalidate() }
        }
        // SKTopBevelWindow_setFadeTimer:, including mouse tracking/modal loops.
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return timer
    }
}

private final class OriginalHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OriginalHelpBevelView: NSView {
    static let font = NSFont(name: "LucidaGrande", size: 20) ?? .systemFont(ofSize: 20)
    static let originalBodyHeight: CGFloat = 44
    static let heightAllowance: CGFloat = 3
    static let horizontalInset: CGFloat = 3
    private(set) var message = ""
    private(set) var attributedMessage = NSAttributedString(string: "")
    private(set) var textRect = NSRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var isOpaque: Bool { false }

    func update(message: String, width: CGFloat) -> CGFloat {
        self.message = message
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.5
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1
        shadow.shadowColor = .black
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        attributedMessage = NSAttributedString(string: message, attributes: [
            .font: Self.font, .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph, .shadow: shadow
        ])
        let textWidth = max(1, width - 2 * Self.horizontalInset)
        let measured = attributedMessage.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let bodyHeight = max(Self.originalBodyHeight, ceil(measured.height))
        let height = bodyHeight + Self.heightAllowance
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        textRect = NSRect(x: Self.horizontalInset, y: (height - ceil(measured.height)) / 2,
                          width: textWidth, height: ceil(measured.height))
        setAccessibilityValue(message)
        needsDisplay = true
        return height
    }

    var backgroundPath: NSBezierPath {
        // SKTopBevelAttachmentBackgroundView_drawRect:. Mach-O floats at
        // 0x2609e0 / 0x260aec are -12 / +12: bottom corners join the host.
        var rect = bounds.insetBy(dx: 1, dy: 1)
        rect.origin.y -= 12
        rect.size.height += 12
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        path.lineWidth = 2
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let path = backgroundPath
        NSColor(calibratedWhite: 0, alpha: 0.85).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.95, alpha: 1).setStroke()
        path.stroke()
        attributedMessage.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Parent supplies local hover/modifier events and clears on focus, hide, sheet,
/// miniaturization and termination. This controller installs no event monitors.
@MainActor
final class OriginalHelpBevel {
    static let hoverDelay: TimeInterval = 0.25 // SkitchCropView_mouseEntered:.
    static let fadeInterval: TimeInterval = 0.02
    static let showStep: CGFloat = 0.15 // Mach-O double DAT_00260af8.
    static let hideStep: CGFloat = 0.1 // Negated DAT_00260b00.

    var enabled = false { didSet { if !enabled { clear() } } }
    private(set) var displayedMessage: String?
    private(set) var panel: NSPanel?
    private weak var host: NSWindow?
    private let makePanel: () -> NSPanel
    private let scheduler: any OriginalHelpBevelScheduling
    private var hoverOwner: String?
    private var hoverMessage: String?
    private var hoverReady = false
    private var modifierMessage: String?
    private var hoverTimer: Timer?
    private var fadeTimer: Timer?
    private var hoverGeneration = UUID()
    private var fadeGeneration = UUID()
    private var fadingIn = false
    private var stopped = false

    init(host: NSWindow, makePanel: (() -> NSPanel)? = nil,
         scheduler: (any OriginalHelpBevelScheduling)? = nil) {
        self.host = host
        self.makePanel = makePanel ?? {
            OriginalHelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        }
        self.scheduler = scheduler ?? NativeHelpBevelScheduler()
    }

    private var canRender: Bool {
        guard enabled, !stopped, let host else { return false }
        return host.isVisible && host.isKeyWindow && !host.isMiniaturized && host.attachedSheet == nil
    }

    private func normalized(_ message: String?) -> String? {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return message
    }

    func hover(owner: String, message: String?) {
        guard canRender else { clear(); return }
        cancelHover()
        hoverOwner = owner
        hoverMessage = normalized(message)
        hoverReady = false
        updateDisplay()
        guard hoverMessage != nil else { return }
        let generation = hoverGeneration
        hoverTimer = scheduler.timer(interval: Self.hoverDelay, repeats: false) { [weak self] in
            guard let self, self.hoverGeneration == generation else { return false }
            self.cancelHover()
            guard self.canRender else { self.clear(); return false }
            self.hoverReady = true
            self.updateDisplay()
            return false
        }
    }

    func exit(owner: String) {
        guard hoverOwner == owner else { return }
        resetMessages()
        updateDisplay() // Original matched mouse exit calls hideHelp (both slots).
    }

    func modifiers(message: String?) {
        guard canRender else { clear(); return }
        guard let message = normalized(message) else {
            resetMessages()
            updateDisplay() // Original hideHelp clears both slots, then fades out.
            return
        }
        modifierMessage = message
        updateDisplay()
    }

    /// Lifecycle clearing is immediate, so hidden/unfocused hosts have no child
    /// left fading onscreen and no delayed message can reappear after a sheet.
    func clear() {
        resetMessages()
        cancelFade()
        displayedMessage = nil
        hidePanel()
    }

    func reposition() {
        guard canRender else { clear(); return }
        guard let message = displayedMessage else { return }
        _ = layout(message)
    }

    func shutdown() {
        stopped = true
        enabled = false
        clear()
        panel?.close()
        panel = nil
    }

    private func resetMessages() {
        cancelHover()
        hoverOwner = nil; hoverMessage = nil; hoverReady = false
        modifierMessage = nil
    }

    private func updateDisplay() {
        guard canRender else { clear(); return }
        let message = modifierMessage ?? (hoverReady ? hoverMessage : nil)
        guard let message else {
            displayedMessage = nil
            fade(show: false)
            return
        }
        displayedMessage = message
        guard layout(message) else { return }
        guard let panel, let host else { return }
        if panel.parent == nil {
            panel.orderFront(nil)
            host.addChildWindow(panel, ordered: .below)
        }
        fade(show: true)
    }

    private func layout(_ message: String) -> Bool {
        guard let host else { clear(); return false }
        // SKTopBevelAttachmentController_updateAttachedWindowSize:
        // DAT_002609d4 = 40, DAT_00260af0 = -80, read via Mach-O VM/file map.
        let width = host.frame.width - 80
        guard width.isFinite, width > 2 * OriginalHelpBevelView.horizontalInset,
              host.frame.minX.isFinite, host.frame.maxY.isFinite else { clear(); return false }
        if panel == nil {
            let panel = makePanel()
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
            panel.contentView = OriginalHelpBevelView(frame: .zero)
            self.panel = panel
        }
        guard let panel, let view = panel.contentView as? OriginalHelpBevelView else { return false }
        let height = view.update(message: message, width: width)
        panel.setFrame(NSRect(x: host.frame.minX + 40, y: host.frame.maxY,
                              width: width, height: height), display: false)
        return true
    }

    private func fade(show: Bool) {
        cancelFade()
        guard let panel else { return }
        fadingIn = show
        if show && panel.alphaValue >= 1 { return }
        if !show && panel.alphaValue <= 0 { hidePanel(); return }
        let generation = fadeGeneration
        fadeTimer = scheduler.timer(interval: Self.fadeInterval, repeats: true) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return false }
            guard self.canRender else { self.clear(); return false }
            guard let panel = self.panel else { self.cancelFade(); return false }
            // Original fpret alpha is rounded to float before/after its double
            // step. Preserve that arithmetic (ten hide ticks, seven show ticks).
            let stepped = CGFloat(Float(Double(Float(panel.alphaValue)) +
                                        (self.fadingIn ? Double(Self.showStep) : -Double(Self.hideStep))))
            let alpha = self.fadingIn ? min(1, stepped) : max(0, stepped)
            panel.alphaValue = alpha
            if (self.fadingIn && alpha >= 1) || (!self.fadingIn && alpha <= 0) {
                self.cancelFade()
                if !self.fadingIn { self.hidePanel() }
                return false
            }
            return true
        }
    }

    private func cancelHover() {
        hoverGeneration = UUID()
        hoverTimer?.invalidate(); hoverTimer = nil
    }

    private func cancelFade() {
        fadeGeneration = UUID()
        fadeTimer?.invalidate(); fadeTimer = nil
    }

    private func hidePanel() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 0
    }
}
