import AppKit

/// The parent owns persistence and application side effects.
@MainActor
struct GeneralPreferencesState: Equatable {
    var drawingPrecision: StrokeSmoothing
    var arrowHead: Int
    var includeSkitch: Bool
    var playSounds: Bool
    var statusMenu: Int
    var showToolTips: Bool
    var showKeyboardTips: Bool

    init(drawingPrecision: StrokeSmoothing, arrowHead: Int, includeSkitch: Bool,
         playSounds: Bool, statusMenu: Int, showToolTips: Bool = false,
         showKeyboardTips: Bool = false) {
        self.drawingPrecision = drawingPrecision
        self.arrowHead = arrowHead
        self.includeSkitch = includeSkitch
        self.playSounds = playSounds
        self.statusMenu = statusMenu
        self.showToolTips = showToolTips
        self.showKeyboardTips = showKeyboardTips
    }
}

/// A native content view only; its parent owns presentation and storage.
@MainActor
final class GeneralPreferencesForm: NSView {
    var onChange: ((GeneralPreferencesState) -> Void)?
    var onDone: (() -> Void)?
    var onShortcuts: (() -> Void)?
    var onSharing: (() -> Void)?

    private var state: GeneralPreferencesState
    private var precisionButtons: [NSButton] = []
    private var arrowButtons: [NSButton] = []
    private var visibilityButtons: [NSButton] = []
    private let snap = NSButton(checkboxWithTitle: "Show Skitch window in fullscreen and crosshairs Snap", target: nil, action: nil)
    private let sounds = NSButton(checkboxWithTitle: "Play sounds", target: nil, action: nil)
    private let toolTips = NSButton(checkboxWithTitle: "Show tool tip overlays", target: nil, action: nil)
    private let keyboardTips = NSButton(checkboxWithTitle: "Show keyboard tip overlay", target: nil, action: nil)

    override var intrinsicContentSize: NSSize { NSSize(width: 780, height: 570) }

    init(state: GeneralPreferencesState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 780, height: 570))
        identifier = NSUserInterfaceItemIdentifier("generalPreferences")
        widthAnchor.constraint(greaterThanOrEqualToConstant: 650).isActive = true

        precisionButtons = [radio("Precise", tag: 0, action: #selector(changePrecision(_:))),
                            radio("Medium", tag: 1, action: #selector(changePrecision(_:))),
                            radio("Loose", tag: 2, action: #selector(changePrecision(_:)))]
        arrowButtons = [radio("End", tag: 2, action: #selector(changeArrow(_:))),
                        radio("Start", tag: 1, action: #selector(changeArrow(_:)))]
        visibilityButtons = [radio("Dock", tag: 2, action: #selector(changeVisibility(_:))),
                             radio("Menu bar", tag: 1, action: #selector(changeVisibility(_:))),
                             radio("Both", tag: 0, action: #selector(changeVisibility(_:)))]
        let help = NSTextField(wrappingLabelWithString: "Holding Option reverses the setting.")
        help.font = .systemFont(ofSize: 18)
        help.textColor = .labelColor
        help.setContentCompressionResistancePriority(.required, for: .vertical)
        let arrowChoices = vertical([horizontal(arrowButtons), help], spacing: 6)
        configure(snap, action: #selector(changeSnap(_:)))
        snap.identifier = NSUserInterfaceItemIdentifier("includeSkitch")
        snap.cell?.wraps = true
        snap.cell?.isScrollable = false
        snap.cell?.lineBreakMode = .byWordWrapping
        // Two comfortable lines at the minimum width, without reducing the font.
        snap.heightAnchor.constraint(equalToConstant: 60).isActive = true
        configure(sounds, action: #selector(changeSounds(_:)))
        sounds.identifier = NSUserInterfaceItemIdentifier("playSounds")
        configure(toolTips, action: #selector(changeToolTips(_:)))
        toolTips.identifier = NSUserInterfaceItemIdentifier("showToolTips")
        configure(keyboardTips, action: #selector(changeKeyboardTips(_:)))
        keyboardTips.identifier = NSUserInterfaceItemIdentifier("showKeyboardTips")

        let shortcuts = button("Capture Shortcuts…", action: #selector(requestShortcuts))
        let tabs = NSTabView()
        tabs.identifier = NSUserInterfaceItemIdentifier("preferencesTabs")
        tabs.font = .systemFont(ofSize: 20)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        // Recovered MainMenu.nib ownership, rather than the older help image.
        let sections: [(String, [NSView])] = [
            ("General", [sounds, toolTips, keyboardTips,
                         row("Show Skitch in:", choices: horizontal(visibilityButtons))]),
            ("Drawing", [row("Drawing precision:", choices: horizontal(precisionButtons)),
                         row("Arrow head:", choices: arrowChoices)]),
            ("Snapping", [snap, shortcuts])
        ]
        for (title, rows) in sections {
            let host = NSView()
            let content = vertical(rows, spacing: 20)
            host.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
                content.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20)
            ])
            for view in rows where view !== shortcuts {
                view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = host
            tabs.addTabViewItem(item)
        }
        addSubview(tabs)

        let sharing = button("Sharing Settings…", action: #selector(requestSharing))
        let done = button("Done", action: #selector(requestDone))
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        let actions = horizontal([sharing, spacer, done])
        addSubview(actions)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            tabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            tabs.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -20),
            actions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
        synchronize(state)
    }

    required init?(coder: NSCoder) { fatalError("Use init(state:)") }

    /// Refreshes controls without delivering edits, including invalid stored tags.
    func synchronize(_ state: GeneralPreferencesState) {
        var normalized = state
        if ![1, 2].contains(normalized.arrowHead) { normalized.arrowHead = 2 }
        if ![0, 1, 2].contains(normalized.statusMenu) { normalized.statusMenu = 0 }
        self.state = normalized
        let precision: Int
        switch normalized.drawingPrecision { case .precise: precision = 0; case .medium: precision = 1; case .loose: precision = 2 }
        select(precisionButtons, tag: precision)
        select(arrowButtons, tag: normalized.arrowHead)
        select(visibilityButtons, tag: normalized.statusMenu)
        snap.state = normalized.includeSkitch ? .on : .off
        sounds.state = normalized.playSounds ? .on : .off
        toolTips.state = normalized.showToolTips ? .on : .off
        keyboardTips.state = normalized.showKeyboardTips ? .on : .off
    }

    private func select(_ buttons: [NSButton], tag: Int) {
        for button in buttons { button.state = button.tag == tag ? .on : .off }
    }

    private func configure(_ button: NSButton, action: Selector) {
        button.font = .systemFont(ofSize: 20)
        button.controlSize = .large
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func radio(_ title: String, tag: Int, action: Selector) -> NSButton {
        let result = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
        result.tag = tag
        configure(result, action: action)
        return result
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let result = NSButton(title: title, target: nil, action: nil)
        result.bezelStyle = .rounded
        configure(result, action: action)
        return result
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func row(_ title: String, choices: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 20)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 184).isActive = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let result = horizontal([label, choices])
        result.alignment = .top
        return result
    }

    private func publish() {
        synchronize(state)
        onChange?(state)
    }

    @objc private func changePrecision(_ sender: NSButton) {
        switch sender.tag { case 0: state.drawingPrecision = .precise; case 2: state.drawingPrecision = .loose; default: state.drawingPrecision = .medium }
        publish()
    }
    @objc private func changeArrow(_ sender: NSButton) { state.arrowHead = sender.tag; publish() }
    @objc private func changeVisibility(_ sender: NSButton) { state.statusMenu = sender.tag; publish() }
    @objc private func changeSnap(_ sender: NSButton) { state.includeSkitch = sender.state == .on; publish() }
    @objc private func changeSounds(_ sender: NSButton) { state.playSounds = sender.state == .on; publish() }
    @objc private func changeToolTips(_ sender: NSButton) { state.showToolTips = sender.state == .on; publish() }
    @objc private func changeKeyboardTips(_ sender: NSButton) { state.showKeyboardTips = sender.state == .on; publish() }
    @objc private func requestDone() { onDone?() }
    @objc private func requestShortcuts() { onShortcuts?() }
    @objc private func requestSharing() { onSharing?() }
}
