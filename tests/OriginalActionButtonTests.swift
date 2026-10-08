// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D ORIGINAL_ACTION_BUTTON_TESTS \
//   Sources/OriginalActionButton.swift tests/OriginalActionButtonTests.swift \
//   -o /tmp/original-action-button-tests
// rtk proxy /tmp/original-action-button-tests
#if ORIGINAL_ACTION_BUTTON_TESTS
import AppKit

@MainActor
private final class ActionReceiver: NSObject {
    var primarySenders: [AnyObject] = []
    var alternateSenders: [AnyObject] = []
    var onAlternate: (() -> Void)?
    @objc func primary(_ sender: AnyObject) { primarySenders.append(sender) }
    @objc func alternate(_ sender: AnyObject) {
        alternateSenders.append(sender)
        onAlternate?()
    }
}

/// Observe tracking without NSButton's blocking native mouse-tracking loop. Returning
/// true ends tracking at once; returning false makes NSControl.mouseDown wait for input
/// forever, which a test only discovers once its click really reaches the cell.
@MainActor
private final class TrackingCell: NSButtonCell {
    var trackedEvents: [NSEvent] = []
    var trackedViews: [NSView] = []
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect,
                             of controlView: NSView, untilMouseUp flag: Bool) -> Bool {
        trackedEvents.append(event)
        trackedViews.append(controlView)
        return true
    }
}

@MainActor
private final class TestButton: OriginalActionButton {
    var highlights: [Bool] = []
    override func highlight(_ flag: Bool) {
        highlights.append(flag)
        super.highlight(flag)
    }
}

@MainActor
private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

@main
@MainActor
private enum OriginalActionButtonTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    @MainActor
    private struct Rig {
        let button = TestButton(frame: NSRect(x: 35, y: 20, width: 120, height: 40))
        let receiver = ActionReceiver()
        let cell = TrackingCell(textCell: "Test")
        init() {
            button.cell = cell
            button.showMenuOnLeftClick = false // Exercise the original SkitchButton contract by default.
            button.target = receiver
            button.action = #selector(ActionReceiver.primary(_:))
            button.alternateTarget = receiver
            button.alternateAction = #selector(ActionReceiver.alternate(_:))
            // Fail closed if a test accidentally reaches native menu tracking.
            button.menuPresenter = { _, _, _ in preconditionFailure("unexpected menu presentation") }
        }
    }

    /// NSControl.mouseDown only reaches the cell's tracking for a click inside the control,
    /// so a left-down built at the default foreign location (999,888) can never be observed
    /// tracking and every "never enters primary tracking" check would pass vacuously. Left-downs
    /// must therefore be built `inside:` their button; all other events keep the foreign
    /// location so anchoring checks cannot pass by echoing the click.
    private static func mouse(_ type: NSEvent.EventType,
                              flags: NSEvent.ModifierFlags = [],
                              inside view: NSView? = nil) -> NSEvent {
        precondition(type != .leftMouseDown || view != nil,
                     "A left-down outside its button never reaches native tracking, so it proves nothing")
        let location = view.map { $0.convert(NSPoint(x: $0.bounds.maxX - 5, y: $0.bounds.minY + 5), to: nil) }
            ?? NSPoint(x: 999, y: 888)
        return NSEvent.mouseEvent(with: type, location: location,
                                  modifierFlags: flags, timestamp: 123.25, windowNumber: 731,
                                  context: nil, eventNumber: 91, clickCount: 2, pressure: 0.625)!
    }

    private static func populatedMenu() -> NSMenu {
        let menu = NSMenu(title: "Recovered menu fixture")
        let item = NSMenuItem(title: "Secondary command", action: nil, keyEquivalent: "")
        menu.addItem(item)
        return menu
    }

    private static func clean(_ rig: Rig, alternateCount: Int = 0) {
        expect(rig.receiver.primarySenders.isEmpty, "Secondary input never fires primary action")
        expect(rig.receiver.alternateSenders.count == alternateCount, "Expected alternate dispatch count")
        expect(!rig.cell.isHighlighted, "Secondary completion/cancellation clears native highlight")
        expect(rig.cell.trackedEvents.isEmpty, "Secondary input never enters primary tracking")
    }

    static func main() {
        _ = NSApplication.shared
        expect(NSApplication.shared.windows.isEmpty, "Test begins without native windows")
        primaryAndAlternate()
        menuPriorityAndMetadata()
        bezelLeftMenuBehavior()
        controlRouting()
        accessibilityAndKeyboardMenus()
        cancellationAndLifecycle()
        reentryCleanup()
        weakTarget()
        expect(NSApplication.shared.windows.isEmpty, "Tests create/order no native windows")
        print("PASS OriginalActionButtonTests (\(checks) checks; injected menus, no native windows or desktop input)")
    }

    private static func primaryAndAlternate() {
        let rig = Rig()
        let flags: NSEvent.ModifierFlags = [.shift, .option, .command]
        let down = mouse(.leftMouseDown, flags: flags, inside: rig.button)
        let baseline = NSButton(frame: rig.button.frame)
        let baselineCell = TrackingCell(textCell: "Test")
        baseline.cell = baselineCell
        baseline.target = rig.receiver
        baseline.action = #selector(ActionReceiver.primary(_:))
        let baselineDown = mouse(.leftMouseDown, flags: flags, inside: baseline)
        baseline.mouseDown(with: baselineDown)
        rig.button.mouseDown(with: down)
        // Fixture guard: a stock NSButton must be seen tracking this very event, otherwise
        // the "never enters primary tracking" checks below could not fail.
        expect(baselineCell.trackedEvents.count == 1 && baselineCell.trackedEvents[0] === baselineDown
               && baselineCell.trackedViews[0] === baseline,
               "Fixture observes native NSButton tracking of an in-bounds left down")
        expect(rig.cell.trackedEvents.count == 1 && rig.cell.trackedEvents[0] === down
               && rig.cell.trackedViews[0] === rig.button,
               "Ordinary left down tracks exactly the incoming event on the actual button")
        baseline.mouseUp(with: mouse(.leftMouseUp))
        rig.button.mouseUp(with: mouse(.leftMouseUp))
        expect(rig.receiver.alternateSenders.isEmpty && rig.button.highlights.isEmpty,
               "Ordinary click never touches alternate state")
        rig.button.performClick(nil)
        expect(rig.receiver.primarySenders.count == 1 && rig.receiver.primarySenders[0] === rig.button,
               "Native performClick retains the actual primary selector, target and sender")
        expect(rig.receiver.alternateSenders.isEmpty, "Native primary action cannot also fire alternate")

        // Press/highlight/release transitions of a secondary click, as an exact sequence.
        let secondary = Rig()
        secondary.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: secondary.button))
        expect(secondary.cell.trackedEvents.isEmpty && secondary.cell.isHighlighted
               && secondary.button.highlights == [true],
               "Control-left down highlights once and never enters primary tracking")
        secondary.button.mouseUp(with: mouse(.leftMouseUp))
        expect(!secondary.cell.isHighlighted && secondary.button.highlights == [true, false]
               && secondary.receiver.alternateSenders.count == 1,
               "Control-left up dispatches once and releases the highlight")
        secondary.button.rightMouseDown(with: mouse(.rightMouseDown))
        expect(secondary.cell.isHighlighted && secondary.button.highlights == [true, false, true],
               "Right down highlights once")
        secondary.button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(secondary.button.highlights == [true, false, true, false],
               "Right up releases the highlight")
        clean(secondary, alternateCount: 2)

        // A populated menu does not hijack a native left click when the left-menu policy is off.
        let menuIdle = Rig()
        menuIdle.button.menu = populatedMenu()
        let plainDown = mouse(.leftMouseDown, inside: menuIdle.button)
        menuIdle.button.mouseDown(with: plainDown)
        menuIdle.button.mouseUp(with: mouse(.leftMouseUp))
        expect(menuIdle.cell.trackedEvents.count == 1 && menuIdle.cell.trackedEvents[0] === plainDown
               && menuIdle.button.highlights.isEmpty && menuIdle.receiver.alternateSenders.isEmpty,
               "Left click with showMenuOnLeftClick off tracks natively even when a menu is assigned")

        for emptyMenu in [false, true] {
            let r = Rig()
            if emptyMenu { r.button.menu = NSMenu() }
            r.button.rightMouseUp(with: mouse(.rightMouseUp))
            clean(r)
            r.button.rightMouseDown(with: mouse(.rightMouseDown))
            expect(r.cell.isHighlighted && r.receiver.alternateSenders.isEmpty,
                   "No/empty menu highlights alternate on down without dispatching")
            r.receiver.onAlternate = {
                expect(r.cell.isHighlighted, "Original action observes highlighted sender before cleanup")
            }
            r.button.rightMouseUp(with: mouse(.rightMouseUp))
            r.receiver.onAlternate = nil
            expect(r.receiver.alternateSenders[0] === r.button,
                   "NSApplication sends alternate selector to actual alternateTarget from button")
            r.button.rightMouseUp(with: mouse(.rightMouseUp))
            clean(r, alternateCount: 1)
        }

        let none = Rig()
        none.button.alternateAction = nil
        none.button.rightMouseDown(with: mouse(.rightMouseDown))
        expect(!none.cell.isHighlighted, "Absent alternate action does not highlight")
        none.button.alternateAction = #selector(ActionReceiver.alternate(_:))
        none.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(none)

        let cleared = Rig()
        cleared.button.rightMouseDown(with: mouse(.rightMouseDown))
        cleared.button.alternateAction = nil
        cleared.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(cleared)

        let distinct = Rig()
        let alternate = ActionReceiver()
        distinct.button.alternateTarget = alternate
        distinct.button.rightMouseDown(with: mouse(.rightMouseDown))
        distinct.button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(alternate.alternateSenders.count == 1 && alternate.alternateSenders[0] === distinct.button,
               "Alternate target is independent of primary target")
        clean(distinct)
    }

    private static func menuPriorityAndMetadata() {
        for flipped in [false, true] {
            let rig = Rig()
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
            let container: NSView = flipped
                ? FlippedContainer(frame: NSRect(x: 40, y: 60, width: 300, height: 200))
                : NSView(frame: NSRect(x: 40, y: 60, width: 300, height: 200))
            root.addSubview(container)
            container.addSubview(rig.button)
            rig.button.bounds.origin = NSPoint(x: 7, y: 9)
            let menu = populatedMenu()
            rig.button.menu = menu
            var presentations = 0
            let flags: NSEvent.ModifierFlags = [.shift, .option, .command, .capsLock, .function]
            let incoming = mouse(.rightMouseDown, flags: flags)
            let expectedAnchor = NSPoint(x: 75, y: flipped ? 220 : 100)
            rig.button.menuPresenter = { receivedMenu, anchored, sender in
                presentations += 1
                guard let anchored else { preconditionFailure("Mouse menu requires actual relocated event") }
                expect(receivedMenu === menu && sender === rig.button,
                       "Presenter receives exact configured menu and button")
                expect(anchored !== incoming && anchored.locationInWindow == expectedAnchor,
                       "Rebuilt event anchors at converted button left edge and window y center")
                expect(anchored.type == incoming.type && anchored.modifierFlags == incoming.modifierFlags,
                       "Popup preserves actual incoming event type and every modifier")
                expect(anchored.timestamp == incoming.timestamp && anchored.windowNumber == incoming.windowNumber,
                       "Popup preserves incoming time and window metadata")
                expect(anchored.eventNumber == incoming.eventNumber && anchored.clickCount == incoming.clickCount
                       && anchored.pressure == incoming.pressure, "Popup preserves event number, clicks and pressure")
                expect(!rig.cell.isHighlighted, "Populated menu takes priority over alternate highlight")
            }
            expect(rig.button.menu(for: incoming) == nil, "Original menuForEvent always returns nil")
            rig.button.rightMouseDown(with: incoming)
            expect(presentations == 1, "Populated menu presents on down exactly once")
            rig.button.rightMouseUp(with: mouse(.rightMouseUp))
            clean(rig)
        }

        let removedMenu = Rig()
        removedMenu.button.menu = populatedMenu()
        var presentations = 0
        removedMenu.button.menuPresenter = { _, _, button in
            presentations += 1
            button.menu = nil
        }
        removedMenu.button.rightMouseDown(with: mouse(.rightMouseDown))
        removedMenu.button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(presentations == 1, "Menu may be removed by its callback")
        clean(removedMenu) // A menu gesture cannot fall through after mutation.
        removedMenu.button.rightMouseDown(with: mouse(.rightMouseDown))
        removedMenu.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(removedMenu, alternateCount: 1)

        let addedMenu = Rig()
        addedMenu.button.rightMouseDown(with: mouse(.rightMouseDown))
        addedMenu.button.menu = populatedMenu()
        addedMenu.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(addedMenu) // Original right-up also gives a current menu priority.

        let menuOnly = Rig()
        menuOnly.button.alternateAction = nil
        menuOnly.button.menu = populatedMenu()
        menuOnly.button.menuPresenter = { _, _, _ in presentations += 1 }
        menuOnly.button.rightMouseDown(with: mouse(.rightMouseDown))
        menuOnly.button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(presentations == 2, "Menu does not require alternateAction")
        clean(menuOnly)
    }

    private static func bezelLeftMenuBehavior() {
        expect(OriginalActionButton().showMenuOnLeftClick, "SKBezelButton left-menu policy defaults true")
        for populated in [false, true] {
            for control in [false, true] {
                let rig = Rig()
                rig.button.showMenuOnLeftClick = true
                let menu = populated ? populatedMenu() : NSMenu()
                rig.button.menu = menu
                let event = mouse(.leftMouseDown, flags: control ? [.control, .shift] : [.shift], inside: rig.button)
                var presentations = 0
                rig.button.menuPresenter = { receivedMenu, receivedEvent, button in
                    presentations += 1
                    expect(receivedMenu === menu && button === rig.button, "Left menu retains actual parent-owned menu and sender")
                    expect(receivedEvent === event, "SKBezelButton left menu passes original event without relocating anchor")
                    expect(!rig.cell.isHighlighted, "Left menu takes precedence over alternate highlight")
                    // A synchronous native popup may change its button's menu.
                    button.menu = nil
                }
                rig.button.mouseDown(with: event)
                rig.button.mouseUp(with: mouse(.leftMouseUp))
                expect(presentations == 1, "Left-menu policy presents assigned menu, including empty and Control-left cases")
                clean(rig)
                rig.button.rightMouseDown(with: mouse(.rightMouseDown))
                rig.button.rightMouseUp(with: mouse(.rightMouseUp))
                clean(rig, alternateCount: 1)
                rig.button.menuPresenter = { _, _, _ in preconditionFailure("unexpected menu presentation") }
            }
        }
        let disabled = Rig()
        disabled.button.showMenuOnLeftClick = true
        disabled.button.menu = populatedMenu()
        disabled.button.isEnabled = false
        disabled.button.mouseDown(with: mouse(.leftMouseDown, inside: disabled.button))
        disabled.button.isEnabled = true
        disabled.button.menu = nil
        disabled.button.mouseUp(with: mouse(.leftMouseUp))
        clean(disabled)

        let menuFree = Rig()
        menuFree.button.showMenuOnLeftClick = true
        menuFree.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: menuFree.button))
        menuFree.button.mouseUp(with: mouse(.leftMouseUp))
        clean(menuFree, alternateCount: 1)
        let menuFreeDown = mouse(.leftMouseDown, inside: menuFree.button)
        menuFree.button.mouseDown(with: menuFreeDown)
        expect(menuFree.cell.trackedEvents.count == 1 && menuFree.cell.trackedEvents[0] === menuFreeDown,
               "Menu-free bezel tracks a plain left click natively instead of swallowing it")
        menuFree.button.performClick(nil)
        expect(menuFree.receiver.primarySenders.count == 1 && menuFree.receiver.primarySenders[0] === menuFree.button,
               "Menu-free bezel keeps ordinary native primary action")
    }

    private static func controlRouting() {
        for upFlags: NSEvent.ModifierFlags in [[.control], []] {
            let rig = Rig()
            rig.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control, .shift], inside: rig.button))
            expect(rig.cell.isHighlighted, "Control-left down routes to secondary highlight")
            rig.button.rightMouseUp(with: mouse(.rightMouseUp))
            expect(rig.receiver.alternateSenders.isEmpty && rig.cell.isHighlighted,
                   "Unrelated right release cannot finish a Control-left gesture")
            rig.button.mouseUp(with: mouse(.leftMouseUp, flags: upFlags))
            rig.button.mouseUp(with: mouse(.leftMouseUp, flags: [.control]))
            clean(rig, alternateCount: 1)
        }
        let orphan = Rig()
        orphan.button.mouseUp(with: mouse(.leftMouseUp, flags: [.control]))
        clean(orphan)

        let rig = Rig()
        rig.button.menu = populatedMenu()
        var presentations = 0
        rig.button.menuPresenter = { _, event, sender in
            presentations += 1
            guard let event else { preconditionFailure("Control menu requires actual relocated event") }
            expect(event.type == .leftMouseDown && event.modifierFlags == [.control, .option, .shift],
                   "Control menu retains left event type and Control flag, never fabricates right input")
            expect(sender === rig.button && event.locationInWindow == NSPoint(x: 35, y: 40),
                   "Control menu uses the same original anchor and actual sender")
        }
        rig.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control, .option, .shift], inside: rig.button))
        rig.button.mouseUp(with: mouse(.leftMouseUp))
        expect(presentations == 1, "Control menu presents once despite Control released before up")
        clean(rig)

        let right = Rig()
        right.button.rightMouseDown(with: mouse(.rightMouseDown, flags: [.control]))
        right.button.mouseUp(with: mouse(.leftMouseUp, flags: [.control]))
        expect(right.cell.isHighlighted && right.receiver.alternateSenders.isEmpty,
               "Control modifier does not change a real right gesture's release button")
        right.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(right, alternateCount: 1)
    }

    private static func accessibilityAndKeyboardMenus() {
        let rig = Rig()
        let showMenu = #selector(OriginalActionButton.accessibilityPerformShowMenu)
        expect(!rig.button.accessibilityPerformShowMenu(), "AX without a menu reports unavailable")
        expect(!rig.button.isAccessibilitySelectorAllowed(showMenu), "AX does not advertise an absent menu")
        rig.button.menu = NSMenu()
        expect(!rig.button.accessibilityPerformShowMenu(), "AX empty menu reports unavailable")
        expect(!rig.button.isAccessibilitySelectorAllowed(showMenu), "AX empty menu is not an allowed action")
        let menu = populatedMenu()
        rig.button.menu = menu
        var presentations = 0
        rig.button.menuPresenter = { receivedMenu, event, sender in
            presentations += 1
            expect(receivedMenu === menu && sender === rig.button,
                   "AX/keyboard present the parent's actual menu from its button")
            expect(event == nil, "AX/keyboard must never synthesize or pass a mouse event")
            expect(!sender.accessibilityPerformShowMenu(), "Reentrant AX request cannot reopen menu")
            expect(!sender.isAccessibilitySelectorAllowed(showMenu), "AX action is unavailable during presentation")
            sender.rightMouseDown(with: mouse(.rightMouseDown))
            sender.rightMouseUp(with: mouse(.rightMouseUp))
        }
        expect(rig.button.isAccessibilitySelectorAllowed(showMenu), "Populated menu exposes native AX ShowMenu")
        expect(rig.button.accessibilityPerformShowMenu(), "AX with populated menu reports handled")
        expect(presentations == 1 && rig.button.isAccessibilitySelectorAllowed(showMenu),
               "AX cleanup makes the next independent menu request available")
        expect(rig.button.menu === menu && menu.numberOfItems == 1, "AX leaves menu ownership and contents unchanged")
        clean(rig)
        if #available(macOS 15.0, *) {
            rig.button.showContextMenuForSelection(rig.button)
            expect(presentations == 2, "Native AppKit keyboard context-menu action uses injected presenter")
            clean(rig)
            let before = presentations
            rig.button.isEnabled = false
            rig.button.showContextMenuForSelection(rig.button)
            expect(presentations == before, "Disabled native keyboard request does not display menu")
            rig.button.isEnabled = true
        }
        let beforeDisable = presentations
        rig.button.isEnabled = false
        expect(!rig.button.accessibilityPerformShowMenu() && !rig.button.isAccessibilitySelectorAllowed(showMenu),
               "Disabled menu cannot be shown or advertised through AX")
        expect(presentations == beforeDisable, "Disabled AX never enters presenter")
        rig.button.isEnabled = true

        // AX can arrive while a Control-left alternate is armed. Displaying
        // the menu consumes that intention even if its callback removes it.
        rig.button.menu = nil
        rig.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: rig.button))
        expect(rig.cell.isHighlighted, "AX cancellation fixture has pending alternate")
        rig.button.menu = menu
        rig.button.menuPresenter = { receivedMenu, event, button in
            expect(receivedMenu === menu && event == nil && !rig.cell.isHighlighted,
                   "AX menu cancels pending alternate highlight before presentation")
            button.menu = nil
        }
        expect(rig.button.accessibilityPerformShowMenu(), "AX may replace armed alternate with menu")
        rig.button.mouseUp(with: mouse(.leftMouseUp))
        clean(rig)
        rig.button.rightMouseDown(with: mouse(.rightMouseDown))
        rig.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(rig, alternateCount: 1)

        let base = NSButton()
        let primaryPress = #selector(NSButton.accessibilityPerformPress)
        expect(rig.button.isAccessibilitySelectorAllowed(primaryPress) == base.isAccessibilitySelectorAllowed(primaryPress),
               "ShowMenu override preserves native primary AX action policy")
    }

    private static func cancellationAndLifecycle() {
        for control in [false, true] {
            for reason in 0..<5 {
                let rig = Rig()
                let parent = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
                parent.addSubview(rig.button)
                let down = mouse(control ? .leftMouseDown : .rightMouseDown,
                                 flags: control ? [.control] : [], inside: control ? rig.button : nil)
                if control { rig.button.mouseDown(with: down) }
                else { rig.button.rightMouseDown(with: down) }
                expect(rig.cell.isHighlighted, "Cancellation fixture begins with an armed alternate")
                switch reason {
                case 0: rig.button.cancelOperation(nil)
                case 1:
                    rig.button.isEnabled = false
                    rig.button.isEnabled = true
                case 2:
                    rig.button.removeFromSuperview()
                    parent.addSubview(rig.button)
                case 3:
                    let replacement = NSView()
                    replacement.addSubview(rig.button)
                    parent.addSubview(rig.button)
                default:
                    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                  timestamp: 125, windowNumber: 731, context: nil,
                                                  characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                  isARepeat: false, keyCode: 53)!
                    rig.button.keyDown(with: escape)
                }
                expect(!rig.cell.isHighlighted, "Cancel/disable/removal/reparent/Escape clears highlight immediately")
                if control { rig.button.mouseUp(with: mouse(.leftMouseUp)) }
                else { rig.button.rightMouseUp(with: mouse(.rightMouseUp)) }
                clean(rig)
                rig.button.rightMouseDown(with: mouse(.rightMouseDown))
                rig.button.rightMouseUp(with: mouse(.rightMouseUp))
                clean(rig, alternateCount: 1)
            }
        }
        for withMenu in [false, true] {
            let rig = Rig()
            if withMenu { rig.button.menu = populatedMenu() }
            rig.button.isEnabled = false
            rig.button.rightMouseDown(with: mouse(.rightMouseDown))
            rig.button.rightMouseUp(with: mouse(.rightMouseUp))
            rig.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: rig.button))
            rig.button.isEnabled = true
            rig.button.mouseUp(with: mouse(.leftMouseUp))
            clean(rig)
        }
        let replacement = Rig()
        replacement.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: replacement.button))
        let ordinary = mouse(.leftMouseDown, inside: replacement.button)
        replacement.button.mouseDown(with: ordinary)
        expect(!replacement.cell.isHighlighted && replacement.button.highlights == [true, false],
               "A new ordinary primary gesture clears pending secondary highlight")
        expect(replacement.cell.trackedEvents.count == 1 && replacement.cell.trackedEvents[0] === ordinary,
               "The replacing ordinary gesture then tracks natively as a primary press")
        replacement.button.rightMouseUp(with: mouse(.rightMouseUp))
        expect(replacement.receiver.alternateSenders.isEmpty, "Replaced gesture has no latent alternate")
    }

    private static func reentryCleanup() {
        let rig = Rig()
        rig.receiver.onAlternate = {
            rig.button.rightMouseUp(with: mouse(.rightMouseUp))
            rig.button.rightMouseDown(with: mouse(.rightMouseDown))
            rig.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: rig.button))
            rig.button.mouseDown(with: mouse(.leftMouseDown, inside: rig.button))
            rig.button.mouseUp(with: mouse(.leftMouseUp))
            rig.button.cancelOperation(nil)
        }
        rig.button.rightMouseDown(with: mouse(.rightMouseDown))
        rig.button.rightMouseUp(with: mouse(.rightMouseUp))
        rig.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(rig, alternateCount: 1)
        rig.receiver.onAlternate = nil
        rig.button.rightMouseDown(with: mouse(.rightMouseDown))
        rig.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(rig, alternateCount: 2)

        for change in 0..<3 {
            let r = Rig()
            let parent = NSView()
            parent.addSubview(r.button)
            r.button.menu = populatedMenu()
            var presentations = 0
            r.button.menuPresenter = { _, _, button in
                presentations += 1
                button.menu = nil
                button.rightMouseDown(with: mouse(.rightMouseDown))
                button.rightMouseUp(with: mouse(.rightMouseUp))
                button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: button))
                button.mouseUp(with: mouse(.leftMouseUp))
                if change == 0 { button.cancelOperation(nil) }
                if change == 1 { button.isEnabled = false; button.isEnabled = true }
                if change == 2 { button.removeFromSuperview(); parent.addSubview(button) }
            }
            r.button.mouseDown(with: mouse(.leftMouseDown, flags: [.control], inside: r.button))
            r.button.mouseUp(with: mouse(.leftMouseUp))
            expect(presentations == 1, "Menu callback reentry cannot recursively present")
            clean(r)
            r.button.rightMouseDown(with: mouse(.rightMouseDown))
            r.button.rightMouseUp(with: mouse(.rightMouseUp))
            clean(r, alternateCount: 1)
        }
        rig.receiver.onAlternate = nil
    }

    private static func weakTarget() {
        let rig = Rig()
        weak var observed: ActionReceiver?
        autoreleasepool {
            let ephemeral = ActionReceiver()
            observed = ephemeral
            rig.button.alternateTarget = ephemeral
            expect(rig.button.alternateTarget === ephemeral, "Alternate target property preserves identity")
            rig.button.rightMouseDown(with: mouse(.rightMouseDown))
        }
        expect(observed == nil && rig.button.alternateTarget == nil, "Button does not retain alternate target")
        rig.button.rightMouseUp(with: mouse(.rightMouseUp))
        clean(rig)
    }
}
#endif
