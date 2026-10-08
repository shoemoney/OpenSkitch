import AppKit

private final class TextStyleContentView: NSView {
    override var isFlipped: Bool { true }
}

/// Original NSFontPanel accessory. Nil means mixed and preserves each item.
final class TextStyleForm: NSView {
    let outline = NSButton(checkboxWithTitle: "Text outline", target: nil, action: nil)
    let shadowControl = NSButton(checkboxWithTitle: "Text shadow", target: nil, action: nil)
    let defaults = NSButton(title: "Default Skitch Style", target: nil, action: nil)
    private let overflow = NSScrollView()
    private let content = TextStyleContentView()
    private let stack = NSStackView()
    var onOutlineChange: ((Bool) -> Void)?
    var onShadowChange: ((Bool) -> Void)?
    var onDefaultRequested: (() -> Void)?
    var outlineChoice: Bool? { outline.state == .mixed ? nil : outline.state == .on }
    var shadowChoice: Bool? { shadowControl.state == .mixed ? nil : shadowControl.state == .on }

    init(outlined: Bool?, shadowed: Bool?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 140))
        outline.allowsMixedState = true; shadowControl.allowsMixedState = true
        outline.target = self; outline.action = #selector(changeOutline)
        shadowControl.target = self; shadowControl.action = #selector(changeShadow)
        defaults.target = self; defaults.action = #selector(restoreDefault)
        for control in [outline, shadowControl, defaults] { stack.addArrangedSubview(control) }
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        overflow.frame = bounds; overflow.autoresizingMask = [.width, .height]
        overflow.drawsBackground = false; overflow.borderType = .noBorder
        overflow.hasVerticalScroller = true; overflow.hasHorizontalScroller = true
        overflow.autohidesScrollers = true; overflow.scrollerStyle = .overlay
        overflow.documentView = content; addSubview(overflow)
        for control in [outline, shadowControl, defaults] {
            control.font = .systemFont(ofSize: 20)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -10)
        ])
        setChoices(outlined: outlined, shadowed: shadowed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let controls = [outline, shadowControl, defaults]
        let required = NSSize(width: (controls.map { $0.fittingSize.width }.max() ?? 0) + 24,
                              height: controls.reduce(0) { $0 + $1.fittingSize.height } + 40)
        let viewport = overflow.contentSize
        content.setFrameSize(NSSize(width: max(required.width, viewport.width),
                                    height: max(required.height, viewport.height)))
        content.layoutSubtreeIfNeeded()
    }

    func setChoices(outlined: Bool?, shadowed: Bool?) {
        outline.state = outlined.map { $0 ? .on : .off } ?? .mixed
        shadowControl.state = shadowed.map { $0 ? .on : .off } ?? .mixed
    }
    @objc func changeOutline() {
        if outline.state == .mixed { outline.state = .on }
        onOutlineChange?(outline.state == .on)
    }
    @objc func changeShadow() {
        if shadowControl.state == .mixed { shadowControl.state = .on }
        onShadowChange?(shadowControl.state == .on)
    }
    @objc func restoreDefault() {
        outline.state = .on; shadowControl.state = .on; onDefaultRequested?()
    }

    /// Read-only metrics from the loaded native controls, alongside desktop proof.
    static func fontPanelTypographyEvidence(_ panel: NSFontPanel) -> [[String: Any]] {
        var records: [[String: Any]] = []
        func visit(_ view: NSView) {
            if !view.isHidden, let control = view as? NSControl, let font = control.font {
                var record: [String: Any] = ["class": NSStringFromClass(type(of: control)),
                                            "pointSize": font.pointSize, "frame": NSStringFromRect(control.frame)]
                if let field = control as? NSTextField {
                    record["text"] = String(field.stringValue.prefix(80))
                    var sizes: [CGFloat] = []
                    field.attributedStringValue.enumerateAttribute(.font, in: NSRange(location: 0, length: field.attributedStringValue.length)) { value, _, _ in
                        if let font = value as? NSFont { sizes.append(font.pointSize) }
                    }
                    record["attributedPointSizes"] = sizes
                }
                records.append(record)
            }
            for child in view.subviews { visit(child) }
        }
        if let content = panel.contentView { visit(content) }
        for item in panel.toolbar?.items ?? [] {
            if let view = item.view { visit(view) }
            if let search = item as? NSSearchToolbarItem { visit(search.searchField) }
        }
        return records
    }

    static func fontPanelLayoutEvidence(_ panel: NSFontPanel) -> [[String: Any]] {
        var records: [[String: Any]] = []
        func visit(_ view: NSView, depth: Int) {
            var item: [String: Any] = ["class": NSStringFromClass(type(of: view)), "depth": depth,
                                       "frame": NSStringFromRect(view.frame)]
            if let split = view as? NSSplitView {
                item["vertical"] = split.isVertical
                item["paneWidths"] = split.arrangedSubviews.map { $0.frame.width }
            }
            records.append(item)
            for child in view.subviews { visit(child, depth: depth + 1) }
        }
        if let content = panel.contentView { visit(content, depth: 0) }
        return records
    }

    /// Fonts panel frame for a desired FRAME size (convert content with `frameRect(forContentRect:)`).
    /// The size is bounded to `visible` first, so the origin clamp can always keep the whole frame on screen.
    static func fontPanelFrame(size: NSSize, visible: NSRect, anchor: NSRect) -> NSRect {
        let fitted = NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        return NSRect(origin: CGPoint(x: min(max(anchor.midX - fitted.width / 2, visible.minX), visible.maxX - fitted.width),
                                      y: min(max(anchor.midY - fitted.height / 2, visible.minY), visible.maxY - fitted.height)),
                      size: fitted)
    }

    /// Leave room for the collection title and full family names at readable sizes.
    /// Returns true once the matching loaded native structure was found and checked.
    /// The presenter applies this until it succeeds, then never again for that
    /// presentation, so later refreshes cannot fight a user's divider drag.
    @discardableResult
    static func prepareFontPanelLayout(_ panel: NSFontPanel) -> Bool {
        guard let content = panel.contentView, let accessory = panel.accessoryView else { return false }
        func contains(_ root: NSView, matching predicate: (NSView) -> Bool) -> Bool {
            predicate(root) || root.subviews.contains { contains($0, matching: predicate) }
        }
        // The loaded native panel has one outer vertical split: the family
        // outline on the left, and font table plus accessory on the right.
        // Do not touch nested preview/accessory splits or unknown hierarchies.
        var matched = false
        for case let split as NSSplitView in content.subviews {
            let panes = split.arrangedSubviews.sorted { $0.frame.minX < $1.frame.minX }
            guard split.isVertical, panes.count == 2, split.bounds.width >= 800,
                  contains(panes[0], matching: { $0 is NSOutlineView }),
                  contains(panes[1], matching: { $0 is NSTableView && !($0 is NSOutlineView) }),
                  contains(panes[1], matching: { $0 === accessory }) else { continue }
            matched = true
            if panes[0].frame.width < 360 { split.setPosition(360, ofDividerAt: 0) }
        }
        return matched
    }

    /// Floors a toolbar item view with Auto Layout (NSToolbarItem.minSize/maxSize are deprecated) and
    /// never sets a maximum, so AppKit keeps its flexible allocation. Constraints are found by
    /// identifier and updated in place, so repeated preparation never stacks duplicates.
    private static func constrainToolbarView(_ view: NSView, minimum: NSSize) {
        // Frame-derived (autoresizing-mask) constraints would pin the size and make the floors inert.
        if view.translatesAutoresizingMaskIntoConstraints { view.translatesAutoresizingMaskIntoConstraints = false }
        for (identifier, anchor, constant) in [("skitch.toolbar.minWidth", view.widthAnchor, minimum.width),
                                               ("skitch.toolbar.minHeight", view.heightAnchor, minimum.height)] {
            if let existing = view.constraints.first(where: { $0.identifier == identifier }) {
                if existing.constant != constant { existing.constant = constant }
            } else {
                let floor = anchor.constraint(greaterThanOrEqualToConstant: constant)
                floor.identifier = identifier
                floor.isActive = true
            }
        }
    }

    static func prepareFontPanel(_ panel: NSFontPanel) {
        func visit(_ view: NSView) {
            if let control = view as? NSControl, let font = control.font, font.pointSize < 20 {
                control.font = NSFontManager.shared.convert(font, toSize: 20)
            }
            if let field = view as? NSTextField {
                let value = NSMutableAttributedString(attributedString: field.attributedStringValue)
                var updates: [(NSRange, NSFont)] = []
                value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, range, _ in
                    if let font = font as? NSFont, font.pointSize < 20 {
                        updates.append((range, NSFontManager.shared.convert(font, toSize: 20)))
                    }
                }
                for (range, font) in updates { value.addAttribute(.font, value: font, range: range) }
                if !updates.isEmpty { field.attributedStringValue = value }
            }
            if let browser = view as? NSBrowser {
                browser.rowHeight = max(32, browser.rowHeight)
                if let prototype = browser.cellPrototype as? NSCell, prototype.font != .systemFont(ofSize: 20) {
                    prototype.font = .systemFont(ofSize: 20)
                }
            }
            if let table = view as? NSTableView {
                table.rowHeight = max(32, table.rowHeight)
                for column in table.tableColumns {
                    column.headerCell.font = .systemFont(ofSize: 20)
                    (column.dataCell as? NSCell)?.font = .systemFont(ofSize: 20)
                }
            }
            for child in view.subviews { visit(child) }
        }
        if let content = panel.contentView { visit(content) }
        for item in panel.toolbar?.items ?? [] {
            if let view = item.view {
                visit(view)
                if let popup = view as? NSPopUpButton {
                    popup.cell?.lineBreakMode = .byTruncatingTail
                    // Keep attributed menu styling and native flexible sizing.
                    // sizeToFit here used to overwrite AppKit's toolbar allocation
                    // and pin both minSize and maxSize to the same small width.
                    popup.menu?.font = .systemFont(ofSize: 20)
                    for choice in popup.itemArray {
                        let title = NSMutableAttributedString(attributedString: choice.attributedTitle ?? NSAttributedString(string: choice.title))
                        var updates: [(NSRange, NSFont)] = []
                        title.enumerateAttribute(.font, in: NSRange(location: 0, length: title.length)) { value, range, _ in
                            let font = value as? NSFont ?? popup.font ?? .systemFont(ofSize: 20)
                            if value == nil || font.pointSize < 20 {
                                updates.append((range, NSFontManager.shared.convert(font, toSize: max(20, font.pointSize))))
                            }
                        }
                        for (range, font) in updates { title.addAttribute(.font, value: font, range: range) }
                        if !updates.isEmpty { choice.attributedTitle = title }
                    }
                    constrainToolbarView(popup, minimum: NSSize(width: 220, height: max(32, popup.intrinsicContentSize.height)))
                }
            }
            if let search = item as? NSSearchToolbarItem { visit(search.searchField) }
        }
    }
}
