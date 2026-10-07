import AppKit

/// Original NSFontPanel accessory. Nil means mixed and preserves each item.
final class TextStyleForm: NSView {
    let outline = NSButton(checkboxWithTitle: "Text outline", target: nil, action: nil)
    let shadowControl = NSButton(checkboxWithTitle: "Text shadow", target: nil, action: nil)
    let defaults = NSButton(title: "Default Skitch Style", target: nil, action: nil)
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
        let stack = NSStackView(views: [outline, shadowControl, defaults])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        for control in [outline, shadowControl, defaults] { control.font = .systemFont(ofSize: 20) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
        setChoices(outlined: outlined, shadowed: shadowed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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

    /// Leave room for the collection title and full family names at readable sizes.
    /// Apply on Show only; subsequent refreshes must not fight a user's divider drag.
    static func prepareFontPanelLayout(_ panel: NSFontPanel) {
        func visit(_ view: NSView) {
            if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count >= 2,
               split.bounds.width >= 800, let first = split.arrangedSubviews.min(by: { $0.frame.minX < $1.frame.minX }) {
                if first.frame.width < 360 { split.setPosition(360, ofDividerAt: 0) }
            }
            for child in view.subviews { visit(child) }
        }
        if let content = panel.contentView { visit(content) }
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
                (browser.cellPrototype as? NSCell)?.font = .systemFont(ofSize: 20)
                browser.rowHeight = max(32, browser.rowHeight)
                if browser.lastColumn >= 0 {
                    for column in 0...browser.lastColumn {
                        if let matrix = browser.matrix(inColumn: column) {
                            for cell in matrix.cells { cell.font = .systemFont(ofSize: 20) }
                        }
                    }
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
                    // AppKit's collection menu supplies an attributed title,
                    // which otherwise ignores the popup control's larger font.
                    for choice in popup.itemArray {
                        let title = NSMutableAttributedString(attributedString: choice.attributedTitle ?? NSAttributedString(string: choice.title))
                        if title.length > 0 {
                            title.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: NSRange(location: 0, length: title.length))
                            choice.attributedTitle = title
                        }
                    }
                    popup.sizeToFit()
                    let required = NSSize(width: max(220, popup.frame.width), height: max(32, popup.frame.height))
                    item.minSize = required; item.maxSize = required
                }
            }
            if let search = item as? NSSearchToolbarItem { visit(search.searchField) }
        }
    }
}
