import AppKit

/// OriginalButton secondary routing (decompiled.c:33924–34162), with the
/// SKBezelButton left-menu policy (80667–80735, 81166–81416).
@MainActor
class OriginalActionButton: NSButton {
    @objc var alternateAction: Selector?
    @objc weak var alternateTarget: AnyObject?
    /// SKBezelButton defaults this to true in both frame and coder initializers.
    /// Setting false restores OriginalButton's primary-left/secondary-Control split.
    @objc var showMenuOnLeftClick = true

    /// The only presentation seam: tests can inspect the actual menu, relocated
    /// event and sender without entering NSMenu's native tracking loop. A nil
    /// event means a keyboard/AX request; it must not synthesize mouse input.
    var menuPresenter: @MainActor (NSMenu, NSEvent?, OriginalActionButton) -> Void = {
        menu, event, button in
        guard button.window != nil else { return }
        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: button.convert(button.menuAnchorInWindow, from: nil), in: button)
        }
    }

    private enum Gesture { case right, left }
    private struct SecondaryPress {
        let gesture: Gesture
        var allowsAction: Bool
    }
    private var secondaryPress: SecondaryPress?
    private var handlingSecondaryCallback = false

    override var isEnabled: Bool {
        didSet { if !isEnabled { cancelSecondaryPress() } }
    }

    // The original deliberately bypasses AppKit's automatic contextual menu.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled, !handlingSecondaryCallback, let menu, menu.numberOfItems > 0 else { return false }
        cancelSecondaryPress()
        presentMenu(menu, event: nil)
        return true
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformShowMenu) {
            return isEnabled && !handlingSecondaryCallback && (menu?.numberOfItems ?? 0) > 0
        }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    // AppKit 15 routes the user's native context-menu keyboard command here.
    // menu(for:) must stay nil for mouse handling, so provide the explicit
    // responder hook rather than installing any application/global binding.
    @available(macOS 15.0, *)
    override func showContextMenuForSelection(_ sender: Any?) {
        _ = accessibilityPerformShowMenu()
    }

    override func mouseDown(with event: NSEvent) {
        guard !handlingSecondaryCallback else { return }
        if showMenuOnLeftClick, let menu {
            cancelSecondaryPress()
            secondaryPress = SecondaryPress(gesture: .left, allowsAction: false)
            guard isEnabled else { return }
            // SKBezelButton's left-menu path uses the original event/location,
            // even for an empty menu, and precedes the Control modifier check.
            presentMenu(menu, event: event)
        } else if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            cancelSecondaryPress()
            secondaryPress = nil
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !handlingSecondaryCallback else { return }
        // Adaptation: releasing Control mid-gesture must not reach NSButton's
        // primary path, including after cancellation or disable/re-enable.
        if secondaryPress?.gesture == .left || event.modifierFlags.contains(.control) {
            rightMouseUp(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !handlingSecondaryCallback else { return }
        cancelSecondaryPress()
        let gesture: Gesture = event.type == .leftMouseDown ? .left : .right
        secondaryPress = SecondaryPress(gesture: gesture, allowsAction: false)
        guard isEnabled else { return }

        if let menu, menu.numberOfItems > 0 {
            // Use converted bounds, not the click position or frame: this is
            // the original window-space left edge / vertical-center anchor.
            guard let anchoredEvent = NSEvent.mouseEvent(
                with: event.type, location: menuAnchorInWindow,
                modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                // Adaptation: NSEvent.context is deprecated and always nil on
                // supported macOS; the remaining original metadata is copied.
                windowNumber: event.windowNumber, context: nil,
                eventNumber: event.eventNumber, clickCount: event.clickCount,
                pressure: event.pressure
            ) else { return }

            presentMenu(menu, event: anchoredEvent)
        } else if alternateAction != nil {
            secondaryPress?.allowsAction = true
            highlight(true)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard !handlingSecondaryCallback, let press = secondaryPress else { return }
        let gesture: Gesture = event.type == .leftMouseUp ? .left : .right
        guard gesture == press.gesture else { return }
        // Adaptation: consume the press before calling external code. Stray
        // releases and callback reentry cannot dispatch the same action twice.
        secondaryPress = nil
        handlingSecondaryCallback = true
        defer {
            highlight(false)
            handlingSecondaryCallback = false
        }
        guard isEnabled, press.allowsAction, (menu?.numberOfItems ?? 0) == 0,
              let alternateAction else { return }
        NSApplication.shared.sendAction(alternateAction, to: alternateTarget, from: self)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelSecondaryPress()
    }

    override func keyDown(with event: NSEvent) {
        if secondaryPress != nil && event.keyCode == 53 {
            cancelOperation(self)
        } else {
            super.keyDown(with: event)
        }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancelSecondaryPress() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelSecondaryPress() }
        super.viewWillMove(toWindow: newWindow)
    }

    private var menuAnchorInWindow: NSPoint {
        let rect = convert(bounds, to: nil)
        return NSPoint(x: rect.minX, y: rect.midY)
    }

    private func presentMenu(_ menu: NSMenu, event: NSEvent?) {
        handlingSecondaryCallback = true
        defer {
            highlight(false)
            handlingSecondaryCallback = false
        }
        menuPresenter(menu, event, self)
    }

    private func cancelSecondaryPress() {
        guard secondaryPress != nil else { return }
        // Keep the gesture until release so a cancelled Control-click still
        // consumes its left mouse-up. No action can be resurrected by re-enable.
        secondaryPress?.allowsAction = false
        highlight(false)
    }
}
