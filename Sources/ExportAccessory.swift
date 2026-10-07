import AppKit

enum ExportAccessoryFormat: String, CaseIterable {
    case png, jpeg, tiff, gif, bmp, pdf, svg, skitch

    var title: String { self == .skitch ? "Skitch" : rawValue.uppercased() }

    static func validated(_ value: String) -> ExportAccessoryFormat {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "jpg": return .jpeg
        case "tif": return .tiff
        case let value: return ExportAccessoryFormat(rawValue: value) ?? .png
        }
    }
}

/// Value validation and selection persistence independent of any exporter or preferences.
struct ExportAccessoryOptions: Equatable {
    // File export starts at 70%; the separate drag-export default is 60%.
    static let defaultJPEGQuality = 0.7
    static let minimumJPEGQuality = 0.1
    static let maximumJPEGQuality = 1.0
    static let jpegTickCount = 10

    private(set) var selectedFormat: ExportAccessoryFormat
    private(set) var originalSize: Bool
    private(set) var jpegQuality: Double

    init(format: String = "png", originalSize: Bool = false,
         jpegQuality: Double = defaultJPEGQuality) {
        selectedFormat = ExportAccessoryFormat.validated(format)
        self.originalSize = originalSize
        self.jpegQuality = Self.validatedQuality(jpegQuality)
    }

    var format: String { selectedFormat.rawValue }
    var jpegControlsEnabled: Bool { selectedFormat == .jpeg }
    var qualityLabel: String { "JPEG quality: \(Int((jpegQuality * 100).rounded()))%" }

    static func validatedQuality(_ quality: Double) -> Double {
        guard quality.isFinite else { return defaultJPEGQuality }
        let bounded = min(maximumJPEGQuality, max(minimumJPEGQuality, quality))
        return (bounded * 10).rounded() / 10
    }

    @discardableResult
    mutating func setFormat(_ value: String) -> Bool {
        let format = ExportAccessoryFormat.validated(value)
        guard selectedFormat != format else { return false }
        selectedFormat = format
        return true
    }

    @discardableResult
    mutating func setOriginalSize(_ value: Bool) -> Bool {
        guard originalSize != value else { return false }
        originalSize = value
        return true
    }

    @discardableResult
    mutating func setJPEGQuality(_ value: Double) -> Bool {
        let quality = Self.validatedQuality(value)
        guard jpegQuality != quality else { return false }
        jpegQuality = quality
        return true
    }
}

/// Displays only caller-supplied preview results; never estimates encoded bytes.
struct ExportAccessoryPreview: Equatable {
    private(set) var byteCount: Int?
    private(set) var size: CGSize?

    init(byteCount: Int? = nil, size: CGSize? = nil) {
        self.byteCount = byteCount.flatMap { $0 >= 0 ? $0 : nil }
        if let size, let width = Int(exactly: size.width), let height = Int(exactly: size.height),
           width > 0, height > 0 {
            self.size = size
        } else {
            self.size = nil
        }
    }

    var dimensionsLabel: String {
        guard let size, let width = Int(exactly: size.width), let height = Int(exactly: size.height) else {
            return "Dimensions: Not available"
        }
        return "Dimensions: \(width) × \(height) pixels"
    }

    var byteCountLabel: String {
        guard let byteCount else { return "Encoded size: Not available" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.includesActualByteCount = true
        return "Encoded size: " + formatter.string(fromByteCount: Int64(byteCount))
    }
}

@MainActor
final class ExportAccessory: NSObject {
    private var options: ExportAccessoryOptions
    private(set) var preview = ExportAccessoryPreview()
    var onChange: () -> Void
    private var contentView: NSView?
    private var formatPopup: NSPopUpButton?
    private var qualitySlider: NSSlider?
    private var qualityLabel: NSTextField?
    private var originalSizeCheckbox: NSButton?
    private var dimensionsLabel: NSTextField?
    private var byteCountLabel: NSTextField?

    init(format: String = "png", originalSize: Bool = false, jpegQuality: Double = 0.7,
         onChange: @escaping () -> Void = {}) {
        options = ExportAccessoryOptions(format: format, originalSize: originalSize, jpegQuality: jpegQuality)
        self.onChange = onChange
        super.init()
    }

    /// Assign this stable view to NSSavePanel.accessoryView. UI creation is lazy.
    var view: NSView {
        if let contentView { return contentView }
        let content = buildContent()
        contentView = content
        return content
    }

    /// Canonical lowercase format; jpg/tif inputs normalize to jpeg/tiff.
    var format: String {
        get { options.format }
        set { optionsChanged(options.setFormat(newValue)) }
    }

    var originalSize: Bool {
        get { options.originalSize }
        set { optionsChanged(options.setOriginalSize(newValue)) }
    }

    /// Finite 0.1...1.0 value, snapped to the slider's ten 10% ticks.
    var jpegQuality: Double {
        get { options.jpegQuality }
        set { optionsChanged(options.setJPEGQuality(newValue)) }
    }

    func updateByteCount(_ count: Int?, size: CGSize) {
        preview = ExportAccessoryPreview(byteCount: count, size: size)
        render()
    }

    private func optionsChanged(_ changed: Bool) {
        guard changed else { return }
        // Old bytes and dimensions describe the old options, not the new ones.
        // The callback can synchronously provide a fresh actual encoded preview.
        preview = ExportAccessoryPreview()
        render()
        onChange()
    }

    private func buildContent() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
        let heading = label("Export options", size: 24, weight: .semibold)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .systemFont(ofSize: 20)
        popup.addItems(withTitles: ExportAccessoryFormat.allCases.map(\.title))
        for (item, format) in zip(popup.itemArray, ExportAccessoryFormat.allCases) {
            item.representedObject = format.rawValue
            item.attributedTitle = NSAttributedString(string: format.title,
                attributes: [.font: NSFont.systemFont(ofSize: 20)])
        }
        popup.target = self
        popup.action = #selector(selectFormat(_:))
        popup.setAccessibilityLabel("Export format")
        formatPopup = popup
        let formatLabel = NSTextField(labelWithString: "Format")
        formatLabel.font = .systemFont(ofSize: 20)
        formatLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let formatRow = NSStackView(views: [formatLabel, popup])
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = 20

        let quality = label(options.qualityLabel)
        qualityLabel = quality
        let slider = NSSlider(value: options.jpegQuality,
                              minValue: ExportAccessoryOptions.minimumJPEGQuality,
                              maxValue: ExportAccessoryOptions.maximumJPEGQuality,
                              target: self, action: #selector(selectQuality(_:)))
        slider.numberOfTickMarks = ExportAccessoryOptions.jpegTickCount
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        slider.setAccessibilityLabel("JPEG quality, 10 to 100 percent")
        qualitySlider = slider
        let sliderRow = NSStackView(views: [label("10%"), slider, label("100%")])
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.spacing = 14

        let checkbox = NSButton(checkboxWithTitle: "Export at original size", target: self,
                                action: #selector(selectOriginalSize(_:)))
        checkbox.font = .systemFont(ofSize: 20)
        originalSizeCheckbox = checkbox
        let dimensions = label(preview.dimensionsLabel)
        dimensionsLabel = dimensions
        let bytes = label(preview.byteCountLabel)
        byteCountLabel = bytes
        dimensions.setAccessibilityLabel("Export dimensions")
        bytes.setAccessibilityLabel("Actual encoded file size")

        let stack = NSStackView(views: [heading, formatRow, quality, sliderRow, checkbox, dimensions, bytes])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            sliderRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            slider.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            checkbox.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            dimensions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bytes.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // Reserve wrapping space for exact byte counts without shrinking text.
            bytes.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        render()
        content.setFrameSize(NSSize(width: 600, height: stack.fittingSize.height + 40))
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20).isActive = true
        popup.nextKeyView = slider
        slider.nextKeyView = checkbox
        return content
    }

    private func label(_ text: String, size: CGFloat = 20,
                       weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private func render() {
        // Optional controls keep property changes and preview tests UI-free.
        if let index = ExportAccessoryFormat.allCases.firstIndex(of: options.selectedFormat) {
            formatPopup?.selectItem(at: index)
        }
        qualitySlider?.doubleValue = options.jpegQuality
        qualitySlider?.isEnabled = options.jpegControlsEnabled
        qualityLabel?.isEnabled = options.jpegControlsEnabled
        qualityLabel?.stringValue = options.qualityLabel
        originalSizeCheckbox?.state = options.originalSize ? .on : .off
        dimensionsLabel?.stringValue = preview.dimensionsLabel
        byteCountLabel?.stringValue = preview.byteCountLabel
    }

    @objc private func selectFormat(_ sender: NSPopUpButton) {
        guard let selected = sender.selectedItem?.representedObject as? String else { return }
        format = selected
    }

    @objc private func selectQuality(_ sender: NSSlider) {
        guard options.jpegControlsEnabled else { return }
        jpegQuality = sender.doubleValue
    }

    @objc private func selectOriginalSize(_ sender: NSButton) {
        originalSize = sender.state == .on
    }
}
