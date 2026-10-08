import AppKit

/// The original SkitchButton delegates ordinary mouse tracking to NSButton
/// (recovered 0x36446/0x364b7). Keep the native cell, image/alternateImage,
/// button type, state transitions and target/action owned by AppKit.
/// The existing rounded accent styling, pressed contrast, disabled dimming
/// and native focus-ring mask are reconstruction adaptations, not recovered art.
final class ToolButton: OriginalActionButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        focusRingType = .exterior
        if (font?.pointSize ?? 0) < 18 { font = .systemFont(ofSize: 20) }
    }

    // NSButton's title convenience initializer assigns its standard small
    // font after init(frame:). Preserve the caller's face while honoring the
    // app's readable-text minimum, including archived or later title changes.
    override var font: NSFont? {
        didSet {
            if let font, font.pointSize < 18 {
                super.font = NSFont(descriptor: font.fontDescriptor, size: 18) ?? .systemFont(ofSize: 18)
            } else if font == nil {
                super.font = .systemFont(ofSize: 20)
            }
        }
    }

    static func textColor(on background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return .labelColor }
        func linear(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance > 0.179 ? .black : .white
    }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet {
            needsDisplay = true
            noteFocusRingMaskChanged()
        }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    private var shapeBounds: NSRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    private var shape: NSBezierPath {
        NSBezierPath(roundedRect: shapeBounds, xRadius: 6, yRadius: 6)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !shapeBounds.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        var background = state == .on ? NSColor.controlAccentColor : NSColor.controlColor
        if !isEnabled {
            background = background.blended(withFraction: 0.55, of: .controlBackgroundColor) ?? background
        } else if cell?.isHighlighted == true {
            background = background.blended(withFraction: 0.18, of: Self.textColor(on: background)) ?? background
        }
        let foreground: NSColor = !isEnabled ? .disabledControlTextColor :
            (state == .on ? Self.textColor(on: background) : .labelColor)
        if contentTintColor != foreground { contentTintColor = foreground }
        background.setFill()
        shape.fill()

        // Original ToolOff/ToolOn images remain on the native NSButtonCell;
        // do not substitute images or toggle state while painting a press.
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        cell?.draw(withFrame: bounds.insetBy(dx: imagePosition == .imageOnly || bounds.width < 64 ? 2 : 10, dy: 0), in: self)
    }

    // AppKit decides when keyboard focus is visible, respecting Full Keyboard
    // Access and the responder chain. No custom key handling or focus watcher.
    override var focusRingMaskBounds: NSRect {
        isEnabled && !shapeBounds.isEmpty ? shapeBounds : .zero
    }

    override func drawFocusRingMask() {
        guard isEnabled, !shapeBounds.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        shape.fill()
    }
}
