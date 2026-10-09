import AppKit

enum GlassShape: Equatable {
    case capsule, rounded(CGFloat), circle

    /// Capsule and circle round to half the short side; a fixed radius never exceeds it.
    func radius(for size: NSSize) -> CGFloat {
        let half = max(0, min(size.width, size.height) / 2)
        if case .rounded(let radius) = self { return min(max(0, radius), half) }
        return half
    }
}

/// A command button whose bezel is the glass surface behind it: borderless, icon from the Font Awesome / SF Symbol /
/// recovered-artwork chain, tint driven by state. Available on macOS 13 so the unit tests run anywhere; the surface
/// reads this button's state through `onInteractionChange`. Click, Control-click and menu handling stay OriginalActionButton's.
@MainActor
class GlassChromeButton: OriginalActionButton {
    var icon: FAIcon? { didSet { refreshIcon() } }
    /// Glyph shown while `state == .on` (Actual Size swaps maximize for minimize); falls back to `icon`.
    var selectedIcon: FAIcon? { didSet { refreshIcon() } }
    var iconFamily: FAFamily = .regular { didSet { refreshIcon() } }
    var selectedFamily: FAFamily = .solid { didSet { refreshIcon() } }
    var classicArtworkName: String? { didSet { refreshIcon() } }
    var selectedClassicArtworkName: String? { didSet { refreshIcon() } }
    var iconPointSize: CGFloat = 22 { didSet { refreshIcon() } }
    var onInteractionChange: ((GlassChromeButton) -> Void)?
    /// The single tinted command (Snap): its icon and title take the contrasting color too.
    var isPrimary = false { didSet { applyForeground() } }
    /// False for toggles that only change glyph (Actual Size): `.on` neither tints the surface nor flips the label color.
    var selectionTints = true { didSet { applyForeground() } }
    /// Mirrors the host surface so the keyboard focus ring hugs the glass instead of the button rectangle.
    var focusShape: GlassShape = .rounded(12) { didSet { noteFocusRingMaskChanged() } }
    private(set) var iconSource: ChromeIconSource = .none
    private(set) var activeFamily: FAFamily = .regular
    /// Whether the button presents as selected. Assigning `state` always counts; AppKit's own flips count only for
    /// two-state button types, because a momentary button reads `.on` while it is merely being clicked.
    private(set) var showsSelection = false
    private(set) var tracksState = false
    var isPressing: Bool { primaryTracking || secondaryHighlight }
    private var primaryTracking = false, secondaryHighlight = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        isBordered = false
        focusRingType = .exterior
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        if (font?.pointSize ?? 0) < 18 { font = .systemFont(ofSize: 20) }
        applyForeground()
    }

    // NSButton's title convenience initializer assigns its small standard font after init(frame:);
    // keep the caller's face but never fall under the 18-point floor ToolButton enforces too.
    override var font: NSFont? {
        didSet {
            if let font, font.pointSize < 18 {
                super.font = NSFont(descriptor: font.fontDescriptor, size: 18) ?? .systemFont(ofSize: 18)
            } else if font == nil {
                super.font = .systemFont(ofSize: 20)
            }
        }
    }

    /// Icon-only commands keep their name here instead of drawing it: the name feeds the tooltip and VoiceOver, so
    /// retitles (Snap / Snap Frame, Actual Size / Normal View, Blank / Clear / Wipe) still land without showing text.
    private(set) var iconOnlyName: String?
    /// Keyboard shortcut appended to the derived tooltip, e.g. "⌘Z".
    var shortcutHint: String? { didSet { refreshDerivedToolTip() } }
    private var derivesToolTip = true

    /// What is actually drawn beside the glyph; empty for every icon-only command.
    var visibleTitle: String { super.title }

    override var title: String {
        get { iconOnlyName ?? super.title }
        set {
            if iconOnlyName != nil { iconOnlyName = newValue; refreshDerivedToolTip() } else { super.title = newValue }
            updatePresentation()
        }
    }

    func makeIconOnly(name: String, shortcut: String? = nil, derivesToolTip: Bool = true) {
        super.title = ""
        iconOnlyName = name
        self.derivesToolTip = derivesToolTip
        shortcutHint = shortcut
        refreshDerivedToolTip()
        updatePresentation()
    }

    private func refreshDerivedToolTip() {
        guard derivesToolTip, let name = iconOnlyName else { return }
        toolTip = shortcutHint.map { "\(name) (\($0))" } ?? name
    }

    private var explicitAccessibilityLabel: String?

    // Without Font Awesome the icon is an SF Symbol with no description of its own, and AppKit then reads the symbol's
    // ("download" for Save) instead of the command. An explicit label wins; otherwise the live title is what is read,
    // so Snap / Snap Frame, Actual Size / Normal View and Blank / Clear / Wipe follow their retitles like Classic's.
    override func setAccessibilityLabel(_ label: String?) {
        explicitAccessibilityLabel = label
        super.setAccessibilityLabel(label)
    }

    override func accessibilityLabel() -> String? {
        if let explicitAccessibilityLabel { return explicitAccessibilityLabel }
        return title.isEmpty ? super.accessibilityLabel() : title
    }

    // Symbol artwork carries alignment insets that make the frame outgrow the surface's constraints; the glass is the bezel here.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override var state: NSControl.StateValue {
        didSet {
            showsSelection = state == .on
            refreshIcon()
            notifyChange()
        }
    }

    override func setButtonType(_ type: NSButton.ButtonType) {
        super.setButtonType(type)
        tracksState = [.toggle, .pushOnPushOff, .onOff, .switch, .radio].contains(type)
    }

    override var isEnabled: Bool {
        didSet {
            applyForeground()
            noteFocusRingMaskChanged()
            notifyChange()
        }
    }

    override var isHidden: Bool {
        didSet { notifyChange() }
    }

    func refreshIcon() {
        if tracksState { showsSelection = state == .on }
        let selected = showsSelection
        activeFamily = selected ? selectedFamily : iconFamily
        guard let glyph = (selected ? selectedIcon : nil) ?? icon else {
            iconSource = .none
            image = nil
            updatePresentation()
            return
        }
        let classic = selected ? (selectedClassicArtworkName ?? classicArtworkName) : classicArtworkName
        let resolved = ChromeIcons.resolve(glyph, family: activeFamily, pointSize: iconPointSize, classic: classic)
        iconSource = resolved.source
        image = resolved.image
        updatePresentation()
    }

    private func updatePresentation() {
        imagePosition = image == nil ? .noImage : (visibleTitle.isEmpty ? .imageOnly : .imageLeading)
        applyForeground()
    }

    /// Selected and primary buttons sit on an accent-tinted surface and take the contrasting color; the rest follow the label color.
    private var usesAccentForeground: Bool { isPrimary || (selectionTints && showsSelection) }

    private func applyForeground() {
        var color = NSColor.labelColor
        if !isEnabled {
            color = .disabledControlTextColor
        } else if usesAccentForeground {
            effectiveAppearance.performAsCurrentDrawingAppearance { color = ToolButton.textColor(on: .controlAccentColor) }
        }
        if contentTintColor != color { contentTintColor = color }
    }

    private func notifyChange() { onInteractionChange?(self) }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        secondaryHighlight = flag
        notifyChange()
    }

    // NSButton highlights its cell directly while tracking a primary click and never calls highlight(_:),
    // so the press is bracketed here. The secondary and menu paths stay entirely OriginalActionButton's.
    override func mouseDown(with event: NSEvent) {
        let tracksPrimary = isEnabled && !event.modifierFlags.contains(.control) && !(showMenuOnLeftClick && menu != nil)
        if tracksPrimary { primaryTracking = true; notifyChange() }
        super.mouseDown(with: event)
        if primaryTracking { primaryTracking = false }
        syncIconToState()
        notifyChange()
    }

    // AppKit toggles a button's state inside its cell, bypassing the `state` override above.
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        syncIconToState()
        notifyChange()
        return super.sendAction(action, to: target)
    }

    private func syncIconToState() {
        if tracksState, showsSelection != (state == .on) { refreshIcon() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyForeground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyForeground()
    }

    private var focusBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }

    override var focusRingMaskBounds: NSRect {
        isEnabled && !focusBounds.isEmpty ? focusBounds : .zero
    }

    override func drawFocusRingMask() {
        guard isEnabled, !focusBounds.isEmpty else { return }
        let radius = focusShape.radius(for: focusBounds.size)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: focusBounds, xRadius: radius, yRadius: radius).fill()
    }
}

/// One Liquid Glass surface around one control. State lives here (hover, press, selection, prominence, disabled)
/// and maps to a tint, an alpha and, with Increase Contrast, a 1-point ring; the control inside only draws its glyph and label.
@available(macOS 26, *)
@MainActor
final class GlassSurfaceView: NSGlassEffectView {
    enum Prominence { case neutral, primary }

    static let animationDuration: TimeInterval = 0.15

    var shape: GlassShape { didSet { syncShape() } }
    var prominence: Prominence = .neutral {
        didSet {
            (contentView as? GlassChromeButton)?.isPrimary = prominence == .primary
            applyState()
        }
    }
    var isSelected = false { didSet { applyState() } }
    var isPressed = false { didSet { applyState() } }
    var isDisabled = false { didSet { applyState() } }
    var accessibility: ChromeAccessibility { didSet { applyState() } }
    private(set) var isHovered = false
    private(set) var currentTint: NSColor?
    private(set) var lastAnimationDuration: TimeInterval = 0
    private(set) var fixedSize: NSSize?
    var showsContrastRing: Bool { isSelected && accessibility.increaseContrast }
    private var sizeConstraints: [NSLayoutConstraint] = []
    private var hoverArea: NSTrackingArea?
    private var batching = false

    init(content: NSView, shape: GlassShape, interactive: Bool, accessibility: ChromeAccessibility) {
        self.shape = shape
        self.accessibility = accessibility
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        style = .regular
        contentView = content
        // The glass pins its content with weak constraints, so a content view larger than the surface would spill out of it.
        NSLayoutConstraint.activate([content.widthAnchor.constraint(equalTo: widthAnchor), content.heightAnchor.constraint(equalTo: heightAnchor)])
        if #available(macOS 27, *) { effectIsInteractive = interactive }
        if let button = content as? GlassChromeButton {
            button.onInteractionChange = { [weak self] changed in self?.sync(from: changed) }
            sync(from: button)
        }
        syncShape()
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Glass collapses to its content's fitting size inside a stack view, so every surface carries explicit constraints.
    func setSize(_ size: NSSize, flexibleWidth: Bool = false) {
        NSLayoutConstraint.deactivate(sizeConstraints)
        sizeConstraints = [
            heightAnchor.constraint(equalToConstant: size.height),
            flexibleWidth ? widthAnchor.constraint(greaterThanOrEqualToConstant: size.width) : widthAnchor.constraint(equalToConstant: size.width)
        ]
        NSLayoutConstraint.activate(sizeConstraints)
        fixedSize = size
    }

    /// Hover state entry point for the tracking area; tests drive it directly.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        applyState()
    }

    private func sync(from button: GlassChromeButton) {
        batching = true
        isSelected = button.selectionTints && button.showsSelection
        isPressed = button.isPressing
        isDisabled = !button.isEnabled
        if isHidden != button.isHidden { isHidden = button.isHidden }
        batching = false
        applyState()
    }

    /// Normal is untinted; hover and press wash the label color over the glass; selected tools and the primary command
    /// carry the accent. Disabled drops hover and press and dims through alpha instead.
    private func resolvedTint() -> NSColor? {
        let contrast = accessibility.increaseContrast
        if isSelected || prominence == .primary {
            let pressing = isPressed && !isDisabled
            return NSColor.controlAccentColor.withAlphaComponent(pressing || contrast ? 1.0 : 0.85)
        }
        if isDisabled { return nil }
        if isPressed { return NSColor.labelColor.withAlphaComponent(contrast ? 0.28 : 0.16) }
        if isHovered { return NSColor.labelColor.withAlphaComponent(contrast ? 0.16 : 0.08) }
        return nil
    }

    func applyState() {
        guard !batching else { return }
        let tint = resolvedTint()
        let alpha: CGFloat = isDisabled ? 0.5 : 1
        let duration = accessibility.reduceMotion ? 0 : Self.animationDuration
        currentTint = tint
        lastAnimationDuration = duration
        updateRing()
        if duration > 0, window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.allowsImplicitAnimation = true
                animator().tintColor = tint
                animator().alphaValue = alpha
            }
        } else {
            tintColor = tint
            alphaValue = alpha
        }
    }

    private func updateRing() {
        layer?.borderWidth = showsContrastRing ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = NSColor.labelColor.cgColor }
    }

    private func syncShape() {
        let radius = shape.radius(for: bounds.size)
        if cornerRadius != radius { cornerRadius = radius }
        layer?.cornerRadius = radius
        if let button = contentView as? GlassChromeButton, button.focusShape != shape { button.focusShape = shape }
    }

    override func layout() {
        super.layout()
        syncShape()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncShape()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    // A hidden or detached surface never receives mouseExited, so drop transient state here.
    override func viewDidHide() {
        super.viewDidHide()
        setHovered(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRing()
    }
}

@available(macOS 26, *)
@MainActor
enum GlassChrome {
    enum Metrics {
        static let toolButton = NSSize(width: 48, height: 40)
        /// Every icon-only command shares this glass; Snap, the primary one, is the larger `primaryButton`.
        static let iconButton = NSSize(width: 48, height: 36)
        /// The Toolbox glyph plus its chevron needs more room than a plain icon.
        static let toolboxButton = NSSize(width: 60, height: 36)
        /// Resize is an image command, not a drawing tool: it sits well apart from the tool row.
        static let resizeSeparation: CGFloat = 28
        static let primaryButton = NSSize(width: 56, height: 44)
        static let commandHeight: CGFloat = 36
        static let railWidth: CGFloat = 64, rightRailWidth: CGFloat = 64, headerHeight: CGFloat = 44
        static let iconPointSize: CGFloat = 22, primaryIconPointSize: CGFloat = 26, labelPointSize: CGFloat = 20
        static let groupSpacing: CGFloat = 10, surfaceSpacing: CGFloat = 6, containerSpacing: CGFloat = 2
        /// Icon beside a 20-point label is drawn at 20 points; icon-only controls use `iconPointSize`.
        static let labeledIconPointSize: CGFloat = 20
        static let pillPadding: CGFloat = 12
        static let railPillWidth: CGFloat = 148
        static let toolSpacing: CGFloat = 4
        // NSGlassEffectContainerView fuses glass shapes closer than its spacing, so it must stay below every stack gap (smallest: toolSpacing).
        static let toolRadius: CGFloat = 12, dragRadius: CGFloat = 14
    }

    /// Apple's over-glass Extra Large control size (36 pt) for every control that supports a control size;
    /// the caller's font survives the size change so text stays at 20 pt.
    static func useExtraLarge(_ control: NSControl) {
        let font = control.font
        control.controlSize = .extraLarge
        if let font { control.font = font }
    }

    /// Experimental canvas bleed under the rails; off falls back to the plain window backdrop.
    static var usesCanvasBleed = false

    /// Wraps `control` in a glass surface. Without an explicit size the surface is a command-height pill that
    /// is never narrower than its content (flexible width) or, for circles, a command-height square.
    static func surface(_ control: NSView, shape: GlassShape, interactive: Bool = true, accessibility: ChromeAccessibility, size: NSSize? = nil) -> GlassSurfaceView {
        let fitting = control.fittingSize
        let fallback = shape == .circle
            ? NSSize(width: Metrics.commandHeight, height: Metrics.commandHeight)
            : NSSize(width: max(Metrics.commandHeight, ceil(fitting.width) + 2 * Metrics.pillPadding), height: Metrics.commandHeight)
        let view = GlassSurfaceView(content: control, shape: shape, interactive: interactive, accessibility: accessibility)
        view.setSize(size ?? fallback, flexibleWidth: size == nil && shape != .circle)
        return view
    }

    /// Surfaces that share one container so nearby glass blends instead of sampling itself.
    static func group(_ surfaces: [NSView], orientation: NSUserInterfaceLayoutOrientation, identifier: String, spacing: CGFloat = Metrics.surfaceSpacing) -> NSGlassEffectContainerView {
        let stack = NSStackView(views: surfaces)
        stack.orientation = orientation
        stack.spacing = spacing
        stack.alignment = orientation == .horizontal ? .centerY : .centerX
        let container = NSGlassEffectContainerView()
        container.spacing = Metrics.containerSpacing
        container.contentView = stack
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }
}
