import AppKit

enum ResizePanelMode: Int {
    case resize, crop, limit
}

enum ResizePanelLimitMode: Int, CaseIterable {
    case greatest, width, height
    var title: String {
        switch self { case .greatest: return "Longest side"; case .width: return "Width"; case .height: return "Height" }
    }
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
    var constrainProportions = true
}

enum ResizePanelGeometry {
    /// Original Scale first fits proportionally; an unconstrained request then
    /// expands/crops the centered viewport to the requested output dimensions.
    static func preview(source: CGSize, output: CGSize, request: ResizePanelSubmission) throws -> (rect: CGRect?, output: CGSize) {
        guard source.width.isFinite, source.height.isFinite, output.width.isFinite, output.height.isFinite,
              source.width > 0, source.height > 0, output.width > 0, output.height > 0 else { throw ResizePanelValidation.Failure.dimension }
        let target = try ResizePanelValidation.validate(request.size)
        if request.isCrop {
            let size = CGSize(width: target.width * source.width / output.width, height: target.height * source.height / output.height)
            return (CGRect(x: (source.width-size.width)*request.anchor.x, y: (source.height-size.height)*request.anchor.y,
                           width: size.width, height: size.height), target)
        }
        let factor = min(target.width / output.width, target.height / output.height)
        let fitted = CGSize(width: max(1, (output.width * factor).rounded()), height: max(1, (output.height * factor).rounded()))
        if request.constrainProportions { return (nil, try ResizePanelValidation.validate(fitted)) }
        let size = CGSize(width: target.width * source.width / (output.width * factor),
                          height: target.height * source.height / (output.height * factor))
        return (CGRect(x: (source.width-size.width)/2, y: (source.height-size.height)/2, width: size.width, height: size.height), target)
    }
}

/// Pure edit state used by the sheet and by tests without AppKit controls.
struct ResizePanelState {
    enum Dimension { case width, height }

    private(set) var mode: ResizePanelMode = .resize
    private(set) var preserveRatio: Bool
    private(set) var widthText: String
    private(set) var heightText: String
    var anchor: ResizePanelAnchor = .center
    var limitMode: ResizePanelLimitMode = .greatest
    var limitText: String
    private let originalSize: CGSize
    private let originalRatio: CGFloat?
    private var lastEdited: Dimension = .width

    init(size: CGSize) {
        originalSize = size
        limitText = ResizePanelValidation.text(for: max(size.width, size.height))
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

    mutating func selectPreset(_ preset: ResizePreset) {
        switch preset.mode { case .scale: mode = .resize; case .crop: mode = .crop; case .limit: mode = .limit }
        widthText = String(preset.width); heightText = String(preset.height)
        preserveRatio = preset.proportions && originalRatio != nil
        anchor = ResizePanelAnchor(rawValue: preset.anchor) ?? .center
        limitMode = ResizePanelLimitMode(rawValue: preset.limitMode.rawValue) ?? .greatest
        limitText = String(preset.limitSize)
    }

    func preset(id: String = UUID().uuidString, name: String, format: Int = 0) throws -> ResizePreset {
        let dimensions = try ResizePanelValidation.size(width: widthText, height: heightText)
        let resizeMode: PresetResizeMode
        switch mode { case .resize: resizeMode = .scale; case .crop: resizeMode = .crop; case .limit: resizeMode = .limit }
        let preset = ResizePreset(id: id, name: name, width: Int(dimensions.width), height: Int(dimensions.height),
            mode: resizeMode, format: format, anchor: anchor.rawValue, proportions: preserveRatio,
            limitSize: Int(try ResizePanelValidation.dimension(from: limitText)),
            limitMode: ResizeLimitMode(rawValue: limitMode.rawValue) ?? .greatest)
        try preset.validate()
        return preset
    }

    func submission() throws -> ResizePanelSubmission {
        if mode == .limit {
            let limit = try ResizePanelValidation.dimension(from: limitText)
            let reference: CGFloat
            switch limitMode { case .greatest: reference = max(originalSize.width, originalSize.height)
            case .width: reference = originalSize.width; case .height: reference = originalSize.height }
            guard reference.isFinite, reference > 0 else { throw ResizePanelValidation.Failure.dimension }
            let factor = limit / reference
            let size = CGSize(width: max(1, (originalSize.width * factor).rounded()), height: max(1, (originalSize.height * factor).rounded()))
            return ResizePanelSubmission(size: try ResizePanelValidation.validate(size), isCrop: false, anchor: anchor.point)
        }
        return ResizePanelSubmission(size: try ResizePanelValidation.size(width: widthText, height: heightText),
                              isCrop: mode == .crop, anchor: anchor.point, constrainProportions: preserveRatio)
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
    private var onPreview: ((ResizePanelSubmission) throws -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var isDelivering = false
    private(set) var lastPreview: ResizePanelSubmission?
    var onCompletion: ((Bool) -> Void)?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        state = ResizePanelState(size: size)
        self.onApply = onApply
    }

    init(size: CGSize, onPreview: @escaping (ResizePanelSubmission) throws -> Void,
         onFinish: @escaping (Bool) -> Void) {
        state = ResizePanelState(size: size)
        self.onPreview = onPreview
        self.onFinish = onFinish
    }

    @discardableResult
    func preview(force: Bool = false) throws -> Bool {
        guard !isFinished, !isDelivering, let callback = onPreview else { return false }
        let submission = try state.submission()
        guard force || submission != lastPreview else { return true }
        isDelivering = true
        defer { isDelivering = false }
        try callback(submission)
        guard !isFinished else { return false }
        lastPreview = submission
        return true
    }

    @discardableResult
    func apply(beforeDelivery: () -> Void = {}) throws -> Bool {
        guard !isFinished, !isDelivering else { return false }
        let submission = try state.submission()
        if onPreview != nil, try !preview(force: true) { return false }
        let callback = onApply
        let finish = onFinish
        let completion = onCompletion
        isFinished = true
        onApply = nil
        onPreview = nil
        onFinish = nil
        onCompletion = nil
        beforeDelivery()
        callback?(submission.size, submission.isCrop, submission.anchor)
        finish?(false)
        completion?(false)
        return true
    }

    func cancel() {
        guard !isFinished else { return }
        let finish = onFinish
        let completion = onCompletion
        isFinished = true
        onApply = nil
        onPreview = nil
        onFinish = nil
        onCompletion = nil
        finish?(true)
        completion?(true)
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
    private var dimensionGrid: NSGridView?
    private var limitRow: NSStackView?
    private var limitField: NSTextField?
    private var limitPopup: NSPopUpButton?
    private var previewTimer: Timer?
    private let presets: ResizePresetStore
    private var selectedPresetID: String?
    private var presetPopup: NSPopUpButton?
    private var presetName: NSTextField?
    private var savePresetButton: NSButton?
    private var removePresetButton: NSButton?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        session = ResizePanelSession(size: size, onApply: onApply)
        presets = ResizePresetStore()
        super.init()
    }

    init(session: ResizePanelSession, presets: ResizePresetStore = ResizePresetStore()) {
        self.session = session
        self.presets = presets
        super.init()
    }

    init(size: CGSize, onPreview: @escaping (ResizePanelSubmission) throws -> Void,
         onFinish: @escaping (Bool) -> Void) {
        session = ResizePanelSession(size: size, onPreview: onPreview, onFinish: onFinish)
        presets = ResizePresetStore()
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
        session.onCompletion = { [weak self] cancelled in
            self?.persistSelectedPreset()
            self?.previewTimer?.invalidate(); self?.previewTimer = nil
            self?.endSheet(cancelled ? .cancel : .OK)
        }
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
        let presetChoice = NSPopUpButton(frame: .zero, pullsDown: false)
        presetChoice.font = .systemFont(ofSize: 20)
        presetChoice.target = self; presetChoice.action = #selector(selectPreset(_:))
        presetChoice.setAccessibilityLabel("Size preset")
        presetPopup = presetChoice
        let presetTitle = dimensionField(value: "New Size", name: "Preset name")
        presetName = presetTitle
        let addPreset = button("Add Preset", action: #selector(addPreset(_:)))
        let savePreset = button("Save Preset", action: #selector(savePreset(_:)))
        let removePreset = button("Remove", action: #selector(removePreset(_:)))
        savePresetButton = savePreset; removePresetButton = removePreset
        let presetActions = NSStackView(views: [addPreset, savePreset, removePreset])
        presetActions.orientation = .horizontal; presetActions.spacing = 16
        reloadPresets()
        let mode = NSSegmentedControl(labels: ["Resize", "Crop", "Limit"], trackingMode: .selectOne,
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
        dimensionGrid = grid
        let limit = dimensionField(value: session.state.limitText, name: "Size limit in pixels")
        limitField = limit
        let limitChoice = NSPopUpButton(frame: .zero, pullsDown: false)
        limitChoice.font = .systemFont(ofSize: 20)
        limitChoice.addItems(withTitles: ResizePanelLimitMode.allCases.map(\.title))
        limitChoice.target = self; limitChoice.action = #selector(changeLimit(_:))
        limitChoice.setAccessibilityLabel("Limit by")
        limitPopup = limitChoice
        let limitControls = NSStackView(views: [limitChoice, limit])
        limitControls.orientation = .horizontal; limitControls.spacing = 20
        limitRow = limitControls

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
        let apply = button("Apply", action: #selector(previewSheet(_:)))
        let ok = button("OK", action: #selector(applySheet(_:)))
        ok.keyEquivalent = "\r"
        panel.defaultButtonCell = ok.cell as? NSButtonCell
        let buttons = NSStackView(views: [cancel, apply, ok])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        let stack = NSStackView(views: [heading, presetChoice, presetTitle, presetActions, mode, help, grid, ratio, anchor, limitControls, error, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetChoice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetChoice.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            presetTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetTitle.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            error.widthAnchor.constraint(equalTo: stack.widthAnchor),
            error.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
            width.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            height.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            mode.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            ratio.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            limit.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            limit.widthAnchor.constraint(equalToConstant: 190),
            limitChoice.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            anchor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            apply.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            ok.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
        ])
        renderState()
        if presets.hasMalformedData { errorLabel?.stringValue = ResizePresetError.malformedDefaults.localizedDescription }
        panel.setContentSize(NSSize(width: 600, height: max(500, stack.fittingSize.height + 56)))
        // Measure before pinning the bottom so the initial frame cannot compress
        // the controls. Both mode-specific rows reserve the same readable height.
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28).isActive = true
        width.nextKeyView = height
        height.nextKeyView = ratio
        ratio.nextKeyView = popup
        popup.nextKeyView = cancel
        cancel.nextKeyView = apply
        apply.nextKeyView = ok
        ok.nextKeyView = mode
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
        modeControl?.selectedSegment = session.state.mode.rawValue
        if field !== widthField { widthField?.stringValue = session.state.widthText }
        if field !== heightField { heightField?.stringValue = session.state.heightText }
        let crop = session.state.mode == .crop
        let limit = session.state.mode == .limit
        if field !== limitField { limitField?.stringValue = session.state.limitText }
        limitPopup?.selectItem(at: session.state.limitMode.rawValue)
        dimensionGrid?.isHidden = limit
        limitRow?.isHidden = !limit
        ratioButton?.isHidden = crop || limit
        ratioButton?.state = session.state.preserveRatio ? .on : .off
        anchorRow?.isHidden = !crop
        anchorPopup?.selectItem(at: session.state.anchor.rawValue)
        helpLabel?.stringValue = crop ? "Choose crop dimensions and the part of the image to keep."
            : limit ? "Set the width, height, or longest side. Larger limits enlarge the image."
            : "Fit the image to these dimensions. Unlock proportions to add space around it without stretching."
        errorLabel?.stringValue = ""
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === widthField { session.state.edit(.width, text: field.stringValue) }
        else if field === heightField { session.state.edit(.height, text: field.stringValue) }
        else if field === limitField { session.state.limitText = field.stringValue }
        else if field === presetName { return }
        else { return }
        renderState(editing: field)
        schedulePreview()
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        guard let mode = ResizePanelMode(rawValue: sender.selectedSegment) else { return }
        panel?.makeFirstResponder(nil)
        session.state.setMode(mode)
        renderState()
        panel?.contentView?.layoutSubtreeIfNeeded()
        panel?.display()
        schedulePreview()
    }

    @objc private func changeRatio(_ sender: NSButton) {
        panel?.makeFirstResponder(nil)
        session.state.setPreserveRatio(sender.state == .on)
        renderState()
        schedulePreview()
    }

    @objc private func changeAnchor(_ sender: NSPopUpButton) {
        guard let anchor = ResizePanelAnchor(rawValue: sender.indexOfSelectedItem) else { return }
        session.state.anchor = anchor
        schedulePreview()
    }

    @objc private func changeLimit(_ sender: NSPopUpButton) {
        guard let mode = ResizePanelLimitMode(rawValue: sender.indexOfSelectedItem) else { return }
        session.state.limitMode = mode
        schedulePreview()
    }

    private func schedulePreview() {
        previewTimer?.invalidate()
        guard !session.isFinished else { return }
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.previewTimer = nil
                self.persistSelectedPreset()
                do { _ = try self.session.preview() }
                catch { self.errorLabel?.stringValue = error.localizedDescription }
            }
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
    }

    private func reloadPresets() {
        guard let popup = presetPopup else { return }
        popup.removeAllItems(); popup.addItem(withTitle: "Custom size")
        for preset in presets.presets {
            popup.addItem(withTitle: preset.name); popup.lastItem?.representedObject = preset.id
        }
        for item in popup.itemArray {
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 20)])
        }
        if let id = selectedPresetID, let item = popup.itemArray.first(where: { ($0.representedObject as? String) == id }) { popup.select(item) }
        else { popup.selectItem(at: 0) }
        let selected = presets.presets.first(where: { $0.id == selectedPresetID })
        presetName?.stringValue = selected?.name ?? "New Size"
        presetName?.isEnabled = selected == nil || selected?.editable == true
        savePresetButton?.isEnabled = selected?.editable == true && !presets.hasMalformedData
        removePresetButton?.isEnabled = selected?.editable == true && !presets.hasMalformedData
    }

    @objc private func selectPreset(_ sender: NSPopUpButton) {
        persistSelectedPreset()
        selectedPresetID = sender.selectedItem?.representedObject as? String
        if let preset = presets.presets.first(where: { $0.id == selectedPresetID }) { session.state.selectPreset(preset) }
        reloadPresets(); renderState(); schedulePreview()
    }

    @objc private func addPreset(_ sender: Any?) {
        panel?.makeFirstResponder(nil)
        do {
            let selected = presets.presets.first(where: { $0.id == selectedPresetID })
            let name = selected?.editable == false ? (selected?.name ?? "New Size") + " Copy" : (presetName?.stringValue ?? "New Size")
            let preset = try session.state.preset(name: name, format: selected?.format ?? 0)
            try presets.add(preset); selectedPresetID = preset.id
            reloadPresets(); errorLabel?.stringValue = ""
        } catch { errorLabel?.stringValue = error.localizedDescription }
    }

    @objc private func savePreset(_ sender: Any?) {
        panel?.makeFirstResponder(nil)
        persistSelectedPreset(); reloadPresets()
    }

    private func persistSelectedPreset() {
        guard let selected = presets.presets.first(where: { $0.id == selectedPresetID }), selected.editable else { return }
        do {
            let replacement = try session.state.preset(id: selected.id, name: presetName?.stringValue ?? selected.name, format: selected.format)
            if replacement != selected { try presets.update(replacement) }
        } catch { errorLabel?.stringValue = error.localizedDescription }
    }

    @objc private func removePreset(_ sender: Any?) {
        guard let id = selectedPresetID else { return }
        do { try presets.remove(id: id); selectedPresetID = nil; reloadPresets(); errorLabel?.stringValue = "" }
        catch { errorLabel?.stringValue = error.localizedDescription }
    }

    @objc private func applySheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
        panel?.makeFirstResponder(nil)
        do {
            try session.apply(beforeDelivery: { self.endSheet(.OK) })
        } catch {
            // Failed admission never ends the sheet or delivers the callback.
            errorLabel?.stringValue = error.localizedDescription
        }
    }

    @objc private func previewSheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
        panel?.makeFirstResponder(nil)
        do { _ = try session.preview() }
        catch { errorLabel?.stringValue = error.localizedDescription }
    }

    @objc private func cancelSheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
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
