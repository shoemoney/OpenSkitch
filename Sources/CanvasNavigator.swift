import AppKit

/// All rectangles and points use top-left coordinates, including view bounds.
/// The parent supplies a preview and applies navigation in document coordinates.
public struct NavigatorGeometry {
    public static let padding: CGFloat = 12
    public static let headerHeight: CGFloat = 30
    public static let headerGap: CGFloat = 10

    public static func imageRect(documentSize: CGSize, bounds: CGRect) -> CGRect? {
        guard valid(documentSize), valid(bounds) else { return nil }
        let available = CGRect(x: bounds.minX + padding,
                               y: bounds.minY + padding + headerHeight + headerGap,
                               width: bounds.width - 2 * padding,
                               height: bounds.height - 2 * padding - headerHeight - headerGap)
        guard valid(available) else { return nil }
        // Normalize first so even very large finite document sizes cannot overflow.
        let longest = max(documentSize.width, documentSize.height)
        let aspect = CGSize(width: documentSize.width / longest,
                            height: documentSize.height / longest)
        let scale = min(available.width / aspect.width, available.height / aspect.height)
        let size = CGSize(width: aspect.width * scale, height: aspect.height * scale)
        let result = CGRect(x: available.minX + (available.width - size.width) / 2,
                            y: available.minY + (available.height - size.height) / 2,
                            width: size.width, height: size.height)
        return valid(result) ? result : nil
    }

    /// Clips the visible document region before mapping it into the thumbnail.
    public static func viewportRect(viewport: CGRect, documentSize: CGSize,
                                    imageRect: CGRect) -> CGRect? {
        guard valid(documentSize), valid(viewport), valid(imageRect) else { return nil }
        let left = max(0, viewport.minX), top = max(0, viewport.minY)
        let right = min(documentSize.width, viewport.maxX)
        let bottom = min(documentSize.height, viewport.maxY)
        guard right > left, bottom > top else { return nil }
        let result = CGRect(x: imageRect.minX + (left / documentSize.width) * imageRect.width,
                            y: imageRect.minY + (top / documentSize.height) * imageRect.height,
                            width: ((right - left) / documentSize.width) * imageRect.width,
                            height: ((bottom - top) / documentSize.height) * imageRect.height)
        return valid(result) ? result : nil
    }

    /// Centers the viewport on the pointer, then clamps its origin to the canvas.
    /// Outside pointers are allowed so a drag can continue past thumbnail edges.
    public static func targetOrigin(pointer: CGPoint, documentSize: CGSize,
                                    viewportSize: CGSize, imageRect: CGRect) -> CGPoint? {
        guard pointer.x.isFinite, pointer.y.isFinite, valid(documentSize),
              valid(viewportSize), valid(imageRect) else { return nil }
        let x = min(max(pointer.x, imageRect.minX), imageRect.maxX)
        let y = min(max(pointer.y, imageRect.minY), imageRect.maxY)
        let centerX = ((x - imageRect.minX) / imageRect.width) * documentSize.width
        let centerY = ((y - imageRect.minY) / imageRect.height) * documentSize.height
        return CGPoint(x: min(max(0, centerX - viewportSize.width / 2),
                              max(0, documentSize.width - viewportSize.width)),
                       y: min(max(0, centerY - viewportSize.height / 2),
                              max(0, documentSize.height - viewportSize.height)))
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite && valid(rect.size)
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.maxX > rect.minX && rect.maxY > rect.minY
    }
}

/// Standalone Actual Mode overview. No document model, renderer, or window policy.
@MainActor
public final class CanvasNavigator: NSView {
    public var image: NSImage? { didSet { needsDisplay = true } }
    public var documentSize: CGSize = .zero {
        didSet {
            if documentSize != oldValue { isDragging = false }
            invalidateOverview()
        }
    }
    /// Origin is measured from the document's top-left corner.
    public var viewport: CGRect = .zero { didSet { invalidateOverview() } }
    /// Receives a viewport origin; the parent remains the owner of viewport state.
    public var onNavigate: ((CGPoint) -> Void)?

    private var isDragging = false
    private lazy var navigationActions: [NSAccessibilityCustomAction] = [
        NSAccessibilityCustomAction(name: "Center viewport", target: self, selector: #selector(centerViewport)),
        NSAccessibilityCustomAction(name: "Pan left", target: self, selector: #selector(panLeft)),
        NSAccessibilityCustomAction(name: "Pan right", target: self, selector: #selector(panRight)),
        NSAccessibilityCustomAction(name: "Pan up", target: self, selector: #selector(panUp)),
        NSAccessibilityCustomAction(name: "Pan down", target: self, selector: #selector(panDown))
    ]

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 190) }

    public func update(image: NSImage?, documentSize: CGSize, viewport: CGRect) {
        self.image = image
        self.documentSize = documentSize
        self.viewport = viewport
    }

    private var thumbnailRect: CGRect? {
        NavigatorGeometry.imageRect(documentSize: documentSize, bounds: bounds)
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Overview")
        setAccessibilityHelp("Shows the whole canvas and visible region. Click or drag to center the viewport. Use pan actions or arrow keys to move the visible region.")
    }

    private func invalidateOverview() {
        needsDisplay = true
        if window != nil { NSAccessibility.post(element: self, notification: .valueChanged) }
    }

    public override func accessibilityValue() -> Any? {
        guard let rect = thumbnailRect,
              NavigatorGeometry.viewportRect(viewport: viewport, documentSize: documentSize,
                                             imageRect: rect) != nil else { return "No visible canvas region" }
        return String(format: "Visible region: x %.0f, y %.0f, width %.0f, height %.0f. Canvas: %.0f by %.0f.",
                      viewport.origin.x, viewport.origin.y, viewport.width, viewport.height,
                      documentSize.width, documentSize.height)
    }

    public override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        navigationActions
    }

    public override func accessibilityPerformPress() -> Bool { centerViewport() }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let header = CGRect(x: bounds.minX + NavigatorGeometry.padding,
                            y: bounds.minY + NavigatorGeometry.padding,
                            width: max(0, bounds.width - 2 * NavigatorGeometry.padding),
                            height: NavigatorGeometry.headerHeight)
        ("Overview" as NSString).draw(in: header, withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        guard let rect = thumbnailRect else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: rect).addClip()
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        // Draw the supplied image into a bounded destination; never create a renderer
        // or allocate another image during display or pointer navigation.
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        if let visible = NavigatorGeometry.viewportRect(viewport: viewport,
                                                        documentSize: documentSize, imageRect: rect) {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).setFill()
            visible.fill()
            NSColor.selectedContentBackgroundColor.setStroke()
            let outline = NSBezierPath(rect: visible.insetBy(dx: min(1, visible.width / 4),
                                                            dy: min(1, visible.height / 4)))
            outline.lineWidth = 2
            outline.stroke()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(rect: rect.insetBy(dx: 2, dy: 2))
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    public override func mouseDown(with event: NSEvent) {
        isDragging = false
        let pointer = convert(event.locationInWindow, from: nil)
        guard let rect = thumbnailRect, pointer.x >= rect.minX, pointer.x <= rect.maxX,
              pointer.y >= rect.minY, pointer.y <= rect.maxY else { return }
        window?.makeFirstResponder(self)
        // Set tracking before delivery: a parent document change may cancel it.
        isDragging = true
        if !navigate(to: pointer) { isDragging = false }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        if !navigate(to: convert(event.locationInWindow, from: nil)) { isDragging = false }
    }

    public override func mouseUp(with event: NSEvent) { isDragging = false }

    @discardableResult
    private func navigate(to pointer: CGPoint) -> Bool {
        guard let callback = onNavigate, let rect = thumbnailRect,
              let origin = NavigatorGeometry.targetOrigin(pointer: pointer, documentSize: documentSize,
                                                           viewportSize: viewport.size, imageRect: rect) else { return false }
        callback(origin)
        return true
    }

    @objc private func centerViewport() -> Bool {
        guard let rect = thumbnailRect else { return false }
        return navigate(to: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func pan(x: CGFloat, y: CGFloat) -> Bool {
        guard let rect = thumbnailRect, viewport.origin.x.isFinite, viewport.origin.y.isFinite,
              let current = NavigatorGeometry.targetOrigin(
                pointer: CGPoint(x: rect.minX, y: rect.minY), documentSize: documentSize,
                viewportSize: viewport.size, imageRect: rect) else { return false }
        // Clamp current origin before arithmetic to avoid overflowing stale input.
        let origin = CGPoint(x: min(max(current.x, viewport.origin.x), max(0, documentSize.width - viewport.width)),
                             y: min(max(current.y, viewport.origin.y), max(0, documentSize.height - viewport.height)))
        let center = CGPoint(x: origin.x + min(viewport.width, documentSize.width) / 2,
                             y: origin.y + min(viewport.height, documentSize.height) / 2)
        let pointer = CGPoint(x: rect.minX + min(max(0, center.x / documentSize.width + x * 0.1), 1) * rect.width,
                              y: rect.minY + min(max(0, center.y / documentSize.height + y * 0.1), 1) * rect.height)
        return navigate(to: pointer)
    }

    @objc private func panLeft() -> Bool { pan(x: -1, y: 0) }
    @objc private func panRight() -> Bool { pan(x: 1, y: 0) }
    @objc private func panUp() -> Bool { pan(x: 0, y: -1) }
    @objc private func panDown() -> Bool { pan(x: 0, y: 1) }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: _ = panLeft()
        case 124: _ = panRight()
        case 125: _ = panDown()
        case 126: _ = panUp()
        case 115: _ = centerViewport()
        default: super.keyDown(with: event)
        }
    }
}
