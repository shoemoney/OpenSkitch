import AppKit

enum OriginalDrawingControls {
    struct Preset {
        let tag: Int
        let name: String
        let bits: [UInt32]
        var color: NSColor {
            let rgba = bits.map { CGFloat(Float(bitPattern: $0)) }
            // The original DocumentController takes the raw table floats.
            // A calibrated swatch converted to deviceRGB would alter them.
            return NSColor(deviceRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
        var swatchColor: NSColor {
            let rgba = bits.map { CGFloat(Float(bitPattern: $0)) }
            return NSColor(calibratedRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
    }
    // Original __GLOBAL__I_a at0x001dc570 initializes tags100...110.
    static let presets: [Preset] = [
        Preset(tag: 100, name: "Red", bits: [0x3f800000,0,0,0x3f800000]),
        Preset(tag: 101, name: "Yellow", bits: [0x3f800000,0x3f77f7f8,0,0x3f800000]),
        Preset(tag: 102, name: "Blue", bits: [0x3dc8c8c9,0x3eeeeeef,0x3f800000,0x3f800000]),
        Preset(tag: 103, name: "Pink", bits: [0x3f7cfcfd,0x3d40c0c1,0x3eb2b2b3,0x3f800000]),
        Preset(tag: 104, name: "Translucent gray", bits: [0,0,0,0x3edc28f6]),
        Preset(tag: 105, name: "Orange", bits: [0x3f800000,0x3f008081,0x3db8b8b9,0x3f800000]),
        Preset(tag: 106, name: "Green", bits: [0,0x3f68e8e9,0,0x3f800000]),
        Preset(tag: 107, name: "White", bits: [0x3f800000,0x3f800000,0x3f800000,0x3f800000]),
        Preset(tag: 108, name: "Black", bits: [0,0,0,0x3f800000]),
        Preset(tag: 109, name: "Highlighter", bits: [0x3f800000,0x3f800000,0,0x3eb33333])
    ]
    static let minimum = 1.5, maximum = 12.0, initialSize = 6.75
    static let sizeSteps = (0..<5).map { minimum + Double($0) * (maximum - minimum) / 4 }
    static func size(_ raw: Double, continuous: Bool) -> Double {
        guard raw.isFinite else { return initialSize }
        let clamped = min(maximum, max(minimum, raw))
        return continuous ? clamped : minimum + ((clamped-minimum)/(maximum-minimum)*4).rounded()*(maximum-minimum)/4
    }
    // Recovered float polynomial at Document::fontSizeFromCurrentBrushSize,
    //0x001c2312. Annotation readability policy supplies the18-point floor.
    static func originalFontSize(_ brush: Double) -> Double {
        let x = (Float(size(brush, continuous: true)) - 1.5) / 10.5
        let x2 = x*x, x3 = x2*x
        let value = x * Float(bitPattern: 0xbf2aaaab) + x2*44 + x3*x*64 + x3*Float(bitPattern: 0xc2555555) + 10
        return Double((value*10).rounded()*Float(bitPattern: 0x3dcccccd))
    }
    static func readableFontSize(_ brush: Double, displayFontScale: CGFloat = 1) -> CGFloat {
        // Original Document::displayFontScale is output height / logical height,
        // independent of the editor zoom. Store logical points so Size stays
        // consistent when the document output has been resized.
        let scale = displayFontScale.isFinite && displayFontScale > 0 ? displayFontScale : 1
        return min(4096, max(18, max(18, CGFloat(originalFontSize(brush))) / scale))
    }
}

final class BezelColorButton: NSButton {
    var drawingColor: NSColor = .red { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).addClip()
        for row in 0..<Int(ceil(rect.height/6)) {
            for column in 0..<Int(ceil(rect.width/6)) {
                ((row+column)%2 == 0 ? NSColor.white : NSColor(white: 0.72, alpha: 1)).setFill()
                NSRect(x: rect.minX+CGFloat(column)*6, y: rect.minY+CGFloat(row)*6, width: 6, height: 6).fill()
            }
        }
        drawingColor.setFill(); rect.fill()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (state == .on ? NSColor.controlAccentColor : NSColor.darkGray).setStroke()
        outline.lineWidth = state == .on ? 3 : 1; outline.stroke()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            focus.lineWidth = 2; focus.stroke()
        }
    }
}

/// The recovered vertical Size control: native artwork and point mapping,
/// five ordinary steps, and Shift-continuous updates throughout a drag.
final class BezelSizeSlider: NSControl {
    var onBegin: (() -> Bool)?
    var onEnd: (() -> Void)?
    private var tracking = false
    private var value = OriginalDrawingControls.initialSize
    private lazy var trackImage = Bundle.main.url(forResource: "sizeSlider", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    private lazy var indicatorImage = Bundle.main.url(forResource: "sizeSlider-indicator", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    override var acceptsFirstResponder: Bool { true }
    override var doubleValue: Double {
        get { value }
        set { value = OriginalDrawingControls.size(newValue, continuous: true); needsDisplay = true }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = NSActionCell(); isEnabled = true
        font = .systemFont(ofSize: 18)
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel("Drawing size")
        toolTip = "Five drawing sizes; hold Shift for continuous adjustment"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityValue() -> Any? { NSNumber(value: value) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: OriginalDrawingControls.minimum) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: OriginalDrawingControls.maximum) }
    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber else { return }
        performValueChange(number.doubleValue, continuous: true)
    }
    override func accessibilityPerformIncrement() -> Bool { performValueChange(value+2.625, continuous: false); return isEnabled }
    override func accessibilityPerformDecrement() -> Bool { performValueChange(value-2.625, continuous: false); return isEnabled }
    func pointForValue(_ size: Double) -> NSPoint {
        NSPoint(x: (bounds.width-14)/2, y: 64*(12-size)/10.5)
    }
    override func draw(_ dirtyRect: NSRect) {
        trackImage?.draw(in: NSRect(x: (bounds.width-10)/2, y: 7, width: 10, height: 63))
        let point = pointForValue(value)
        indicatorImage?.draw(in: NSRect(origin: point, size: NSSize(width: 14, height: 14)))
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            focus.lineWidth = 2; focus.stroke()
        }
    }
    private func begin() -> Bool {
        guard isEnabled else { return false }
        if tracking { return true }
        guard onBegin?() ?? true else { return false }
        tracking = true; return true
    }
    func endTracking() { guard tracking else { return }; tracking = false; onEnd?() }
    func setValueForPoint(_ point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard point.y.isFinite else { return }
        update(12-point.y/64*10.5, continuous: modifiers.contains(.shift))
    }
    private func update(_ raw: Double, continuous: Bool) {
        let chosen = OriginalDrawingControls.size(raw, continuous: continuous)
        guard chosen != value else { return }
        doubleValue = chosen; _ = sendAction(action, to: target)
    }
    func performValueChange(_ raw: Double, continuous: Bool) {
        guard raw.isFinite, begin() else { return }
        update(raw, continuous: continuous); endTracking()
    }
    override func mouseDown(with event: NSEvent) {
        guard begin() else { return }
        // The original slider does not end native annotation typing. Keep that
        // editor's focus; keyboard access to Size remains available via Tab/AX.
        if !(window?.firstResponder is NSTextView) { window?.makeFirstResponder(self) }
        if event.clickCount > 1 { update(6.75, continuous: true) }
        else { setValueForPoint(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
        setValueForPoint(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }
    override func mouseUp(with event: NSEvent) { endTracking() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: performValueChange(value+(event.modifierFlags.contains(.shift) ? 0.1 : 2.625), continuous: event.modifierFlags.contains(.shift))
        case 126: performValueChange(value-(event.modifierFlags.contains(.shift) ? 0.1 : 2.625), continuous: event.modifierFlags.contains(.shift))
        case 53: endTracking()
        default: super.keyDown(with: event)
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endTracking() }
        super.viewWillMove(toWindow: newWindow)
    }
}
