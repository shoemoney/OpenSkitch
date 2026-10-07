import AppKit

/// The original Default Skitch Style restores Helvetica Bold, outline and
/// shadow, retaining the current point size (textSelectDefaultFont:).
final class TextStyleForm: NSView {
    let family = NSComboBox()
    let size = NSTextField()
    let outline = NSButton(checkboxWithTitle: "Text outline", target: nil, action: nil)
    let shadowControl = NSButton(checkboxWithTitle: "Text shadow", target: nil, action: nil)
    let defaults = NSButton(title: "Default Skitch Style", target: nil, action: nil)
    private var referenceFont: NSFont

    init(font: NSFont, outlined: Bool, shadowed: Bool) {
        referenceFont = font
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        family.addItems(withObjectValues: NSFontManager.shared.availableFontFamilies.sorted())
        family.stringValue = font.familyName ?? font.fontName
        size.stringValue = String(format: "%g", Double(font.pointSize))
        outline.state = outlined ? .on : .off
        shadowControl.state = shadowed ? .on : .off
        defaults.target = self; defaults.action = #selector(restoreDefault)
        let labels = [NSTextField(labelWithString: "Font family"), NSTextField(labelWithString: "Size in pixels")]
        let stack = NSStackView(views: [labels[0], family, labels[1], size, outline, shadowControl, defaults])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        for control in [family, size, outline, shadowControl, defaults] as [NSControl] {
            control.font = .systemFont(ofSize: 20)
        }
        for label in labels { label.font = .systemFont(ofSize: 20) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            family.widthAnchor.constraint(equalTo: widthAnchor),
            size.widthAnchor.constraint(equalTo: widthAnchor)
        ])
        family.setAccessibilityLabel("Text font family")
        size.setAccessibilityLabel("Text size in pixels")
        frame.size.height = stack.fittingSize.height
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resolvedFont() -> NSFont? {
        guard let value = Double(size.stringValue), value.isFinite, value >= 18, value <= 4096 else { return nil }
        // A family control must not silently turn Helvetica Bold into regular
        // Helvetica when only size, outline or shadowControl changed.
        if family.stringValue == (referenceFont.familyName ?? referenceFont.fontName) {
            return NSFont(name: referenceFont.fontName, size: value)
        }
        return NSFont(name: family.stringValue, size: value) ??
            NSFontManager.shared.font(withFamily: family.stringValue, traits: [], weight: 5, size: value)
    }

    @objc func restoreDefault() {
        referenceFont = NSFont(name: "Helvetica-Bold", size: referenceFont.pointSize) ?? .boldSystemFont(ofSize: referenceFont.pointSize)
        family.stringValue = referenceFont.familyName ?? referenceFont.fontName
        outline.state = .on; shadowControl.state = .on
    }
}
