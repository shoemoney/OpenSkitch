import AppKit

enum ResizePanelMode: Int {
    case resize, crop
}

enum ResizePanelAnchor: Int, CaseIterable {
    case topLeft, topCenter, topRight, middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Normalized coordinates with the origin at the top left.
    var point: CGPoint {
        CGPoint(x: CGFloat(rawValue % 3) / 2, y: CGFloat(rawValue / 3) / 2)
    }
}

enum ResizePanelValidation {
    // UI admission limits, deliberately independent of the document model.
    static let maximumDimension: CGFloat = 16_384
    static let maximumPixelCount: CGFloat = 32_000_000

    enum Failure: LocalizedError, Equatable {
        case dimension, pixelCount

        var errorDescription: String? {
            switch self {
            case .dimension:
                return "Enter whole pixel dimensions from 1 to 16,384."
            case .pixelCount:
                return "Choose a size with no more than 32 million pixels."
            }
        }
    }

    static func isValidDimension(_ value: CGFloat) -> Bool {
        value.isFinite && value >= 1 && value <= maximumDimension && value.rounded() == value
    }

    static func dimension(from text: String) throws -> CGFloat {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let integer = Int(text), isValidDimension(CGFloat(integer)) else {
            throw Failure.dimension
        }
        return CGFloat(integer)
    }

    static func validate(_ size: CGSize) throws -> CGSize {
        guard isValidDimension(size.width), isValidDimension(size.height) else {
            throw Failure.dimension
        }
        guard size.width * size.height <= maximumPixelCount else { throw Failure.pixelCount }
        return size
    }

    static func size(width: String, height: String) throws -> CGSize {
        try validate(CGSize(width: dimension(from: width), height: dimension(from: height)))
    }

    static func text(for value: CGFloat) -> String {
        // Never convert nonfinite or unbounded floating-point input to Int.
        if isValidDimension(value) { return String(Int(value)) }
        return String(Double(value))
    }
}

struct ResizePanelSubmission: Equatable {
    let size: CGSize
    let isCrop: Bool
    let anchor: CGPoint
}

/// Pure edit state used by the sheet and by tests without AppKit controls.
struct ResizePanelState {
    enum Dimension { case width, height }

    private(set) var mode: ResizePanelMode = .resize
    private(set) var preserveRatio: Bool
    private(set) var widthText: String
    private(set) var heightText: String
    var anchor: ResizePanelAnchor = .center
    private let originalRatio: CGFloat?
    private var lastEdited: Dimension = .width

    init(size: CGSize) {
        widthText = ResizePanelValidation.text(for: size.width)
        heightText = ResizePanelValidation.text(for: size.height)
        originalRatio = (try? ResizePanelValidation.validate(size)) == nil ? nil : size.width / size.height
        preserveRatio = originalRatio != nil
    }

    var locksProportions: Bool { mode == .resize && preserveRatio }

    mutating func setMode(_ mode: ResizePanelMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        synchronizeProportions()
    }

    mutating func setPreserveRatio(_ preserve: Bool) {
        preserveRatio = preserve && originalRatio != nil
        synchronizeProportions()
    }

    mutating func edit(_ dimension: Dimension, text: String) {
        lastEdited = dimension
        switch dimension {
        case .width: widthText = text
        case .height: heightText = text
        }
        synchronizeProportions()
    }

    func submission() throws -> ResizePanelSubmission {
        ResizePanelSubmission(size: try ResizePanelValidation.size(width: widthText, height: heightText),
                              isCrop: mode == .crop, anchor: anchor.point)
    }

    private mutating func synchronizeProportions() {
        guard locksProportions, let ratio = originalRatio else { return }
        switch lastEdited {
        case .width:
            guard let width = try? ResizePanelValidation.dimension(from: widthText) else { return }
            heightText = pixelText(width / ratio)
        case .height:
            guard let height = try? ResizePanelValidation.dimension(from: heightText) else { return }
            widthText = pixelText(height * ratio)
        }
    }

    private func pixelText(_ value: CGFloat) -> String {
        // Round the paired dimension once against the original ratio, avoiding
        // cumulative drift. A subpixel result occupies at least one pixel.
        let rounded = max(1, value.rounded())
        if rounded.isFinite && rounded <= ResizePanelValidation.maximumDimension {
            return String(Int(rounded))
        }
        // Keep an oversized result invalid; never silently clamp the ratio.
        return String(Double(rounded))
    }
}

/// Callback lifetime is also testable without constructing a window.
@MainActor
final class ResizePanelSession {
    var state: ResizePanelState
    private(set) var isFinished = false
    private var onApply: ((CGSize, Bool, CGPoint) -> Void)?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        state = ResizePanelState(size: size)
        self.onApply = onApply
    }

    @discardableResult
    func apply(beforeDelivery: () -> Void = {}) throws -> Bool {
        guard !isFinished else { return false }
        let submission = try state.submission()
        let callback = onApply
        isFinished = true
        onApply = nil
        beforeDelivery()
        callback?(submission.size, submission.isCrop, submission.anchor)
        return true
    }

    func cancel() {
        isFinished = true
        onApply = nil
    }
}

@MainActor
final class ResizePanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private let session: ResizePanelSession
    private var panel: NSPanel?
    private var widthField: NSTextField?
    private var heightField: NSTextField?
    private var ratioButton: NSButton?
    private var modeControl: NSSegmentedControl?
    private var anchorPopup: NSPopUpButton?
    private var anchorRow: NSStackView?
    private var errorLabel: NSTextField?
    private var helpLabel: NSTextField?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        session = ResizePanelSession(size: size, onApply: onApply)
        super.init()
    }

    func show(attachedTo parent: NSWindow) {
        guard panel == nil, !session.isFinished else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 660),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Resize or Crop"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        self.panel = panel
        buildContent(in: panel)
        // Retain the controller until sheet completion, even for a temporary caller.
        parent.beginSheet(panel) { [self] _ in
            session.cancel()
            self.panel = nil
            panel.orderOut(nil)
        }
        panel.makeFirstResponder(widthField)
    }

    private func buildContent(in panel: NSPanel) {
        let content = NSView()
        panel.contentView = content
        let heading = label("Resize or Crop", size: 26, weight: .semibold)
        let mode = NSSegmentedControl(labels: ["Resize", "Crop"], trackingMode: .selectOne,
                                      target: self, action: #selector(changeMode(_:)))
        mode.font = .systemFont(ofSize: 20)
        mode.selectedSegment = session.state.mode.rawValue
        mode.setAccessibilityLabel("Size operation")
        modeControl = mode

        let help = NSTextField(wrappingLabelWithString: "")
        help.font = .systemFont(ofSize: 20)
        helpLabel = help
        let width = dimensionField(value: session.state.widthText, name: "Width in pixels")
        let height = dimensionField(value: session.state.heightText, name: "Height in pixels")
        widthField = width
        heightField = height
        let grid = NSGridView(views: [[label("Width (pixels)"), width],
                                     [label("Height (pixels)"), height]])
        grid.columnSpacing = 20
        grid.rowSpacing = 14
        grid.rowAlignment = .firstBaseline
        grid.column(at: 1).width = 240

        let ratio = NSButton(checkboxWithTitle: "Lock proportions", target: self,
                             action: #selector(changeRatio(_:)))
        ratio.font = .systemFont(ofSize: 20)
        ratioButton = ratio
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .systemFont(ofSize: 20)
        popup.addItems(withTitles: ResizePanelAnchor.allCases.map(\.title))
        for item in popup.itemArray {
            item.attributedTitle = NSAttributedString(string: item.title,
                attributes: [.font: NSFont.systemFont(ofSize: 20)])
        }
        popup.target = self
        popup.action = #selector(changeAnchor(_:))
        popup.setAccessibilityLabel("Crop anchor")
        anchorPopup = popup
        let anchor = NSStackView(views: [label("Crop anchor"), popup])
        anchor.orientation = .horizontal
        anchor.spacing = 20
        anchorRow = anchor

        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 20)
        error.textColor = .systemRed
        error.setAccessibilityLabel("Dimension validation")
        errorLabel = error
        let cancel = button("Cancel", action: #selector(cancelSheet(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let apply = button("Apply", action: #selector(applySheet(_:)))
        apply.keyEquivalent = "\r"
        panel.defaultButtonCell = apply.cell as? NSButtonCell
        let buttons = NSStackView(views: [cancel, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        let stack = NSStackView(views: [heading, mode, help, grid, ratio, anchor, error, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            error.widthAnchor.constraint(equalTo: stack.widthAnchor),
            error.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
            width.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            height.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            mode.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            ratio.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            anchor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            apply.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
        ])
        renderState()
        panel.setContentSize(NSSize(width: 600, height: max(500, stack.fittingSize.height + 56)))
        // Measure before pinning the bottom so the initial frame cannot compress
        // the controls. Both mode-specific rows reserve the same readable height.
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28).isActive = true
        width.nextKeyView = height
        height.nextKeyView = ratio
        ratio.nextKeyView = popup
        popup.nextKeyView = cancel
        cancel.nextKeyView = apply
        apply.nextKeyView = mode
        mode.nextKeyView = width
    }

    private func label(_ text: String, size: CGFloat = 20,
                       weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private func dimensionField(value: String, name: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = .systemFont(ofSize: 20)
        field.delegate = self
        field.setAccessibilityLabel(name)
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 20)
        return button
    }

    private func renderState(editing field: NSTextField? = nil) {
        if field !== widthField { widthField?.stringValue = session.state.widthText }
        if field !== heightField { heightField?.stringValue = session.state.heightText }
        let crop = session.state.mode == .crop
        ratioButton?.isHidden = crop
        ratioButton?.state = session.state.preserveRatio ? .on : .off
        anchorRow?.isHidden = !crop
        anchorPopup?.selectItem(at: session.state.anchor.rawValue)
        helpLabel?.stringValue = crop ? "Choose crop dimensions and the part of the image to keep."
            : "Set the image size in pixels. Lock proportions to keep its original shape."
        errorLabel?.stringValue = ""
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === widthField { session.state.edit(.width, text: field.stringValue) }
        else if field === heightField { session.state.edit(.height, text: field.stringValue) }
        else { return }
        renderState(editing: field)
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        guard let mode = ResizePanelMode(rawValue: sender.selectedSegment) else { return }
        panel?.makeFirstResponder(nil)
        session.state.setMode(mode)
        renderState()
        panel?.contentView?.layoutSubtreeIfNeeded()
        panel?.display()
    }

    @objc private func changeRatio(_ sender: NSButton) {
        panel?.makeFirstResponder(nil)
        session.state.setPreserveRatio(sender.state == .on)
        renderState()
    }

    @objc private func changeAnchor(_ sender: NSPopUpButton) {
        guard let anchor = ResizePanelAnchor(rawValue: sender.indexOfSelectedItem) else { return }
        session.state.anchor = anchor
    }

    @objc private func applySheet(_ sender: Any?) {
        panel?.makeFirstResponder(nil)
        do {
            try session.apply(beforeDelivery: { self.endSheet(.OK) })
        } catch {
            // Failed admission never ends the sheet or delivers the callback.
            errorLabel?.stringValue = error.localizedDescription
        }
    }

    @objc private func cancelSheet(_ sender: Any?) {
        session.cancel()
        endSheet(.cancel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelSheet(nil)
        return false
    }

    private func endSheet(_ response: NSApplication.ModalResponse) {
        guard let panel else { return }
        panel.sheetParent?.endSheet(panel, returnCode: response)
        panel.orderOut(nil)
    }
}
