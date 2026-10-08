// Standalone native tests; no windows or desktop automation.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -framework AppKit -D GENERAL_PREFERENCES_FORM_TESTS \
//   Sources/LegacySkitch.swift Sources/StrokeFitting.swift Sources/Appearance.swift Sources/GeneralPreferencesForm.swift \
//   tests/GeneralPreferencesFormTests.swift -o build/general-preferences-form-tests
// rtk proxy build/general-preferences-form-tests
#if GENERAL_PREFERENCES_FORM_TESTS
import AppKit

@main
@MainActor
private enum GeneralPreferencesFormTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    static func main() throws {
        _ = NSApplication.shared
        let initial = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                                              includeSkitch: true, playSounds: false, statusMenu: 0)
        expect(!initial.showToolTips && !initial.showKeyboardTips, "Existing initializer call sites default both tips off")
        let toolOnly = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                       includeSkitch: true, playSounds: false, statusMenu: 0, showToolTips: true)
        let keyboardOnly = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                           includeSkitch: true, playSounds: false, statusMenu: 0, showKeyboardTips: true)
        expect(toolOnly.showToolTips && !toolOnly.showKeyboardTips, "Keyboard tips default independently")
        expect(!keyboardOnly.showToolTips && keyboardOnly.showKeyboardTips, "Tool tips default independently")
        expect(initial != toolOnly && initial != keyboardOnly && toolOnly != keyboardOnly,
               "Equatable includes each tip preference")
        expect(initial.appearance == .classic && toolOnly.appearance == .classic, "Existing initializer call sites default to Classic")
        let modernOnly = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                         includeSkitch: true, playSounds: false, statusMenu: 0, appearance: .modern)
        expect(modernOnly.appearance == .modern && !modernOnly.showToolTips && modernOnly != initial, "Equatable includes the appearance choice")
        let form = GeneralPreferencesForm(state: initial, modernAvailable: true)
        if CommandLine.arguments.contains("--render") {
            form.appearance = NSAppearance(named: .aqua)
        }
        let tabs = descendants(form).compactMap { $0 as? NSTabView }.first!
        expect(tabs.tabViewItems.map(\.label) == ["General", "Drawing", "Snapping"], "Only recovered native tabs")
        expect(tabs.font.pointSize == 20, "Readable native tabs")
        var views = descendants(form)
        for item in tabs.tabViewItems {
            for view in descendants(item.view!) where !views.contains(where: { $0 === view }) {
                views.append(view)
            }
        }
        let buttons = views.compactMap { $0 as? NSButton }
        func button(_ title: String) -> NSButton {
            let matches = buttons.filter { $0.title == title }
            expect(matches.count == 1, "Exactly one native control: \(title)")
            return matches[0]
        }
        let precise = button("Precise"), medium = button("Medium"), loose = button("Loose")
        let end = button("End"), start = button("Start")
        let dock = button("Dock"), menu = button("Menu bar"), both = button("Both")
        let snap = button("Show Skitch window in fullscreen and crosshairs Snap")
        let sounds = button("Play sounds")
        let toolTips = button("Show tool tip overlays")
        let keyboardTips = button("Show keyboard tip overlay")
        let done = button("Done"), shortcuts = button("Capture Shortcuts…"), sharing = button("Sharing Settings…")
        let modern = button("Modern"), classic = button("Classic"), relaunch = button("Relaunch OpenSkitch")
        let groups = [[precise, medium, loose], [end, start], [dock, menu, both], [modern, classic]]
        let tabButtons = [[sounds, toolTips, keyboardTips, dock, menu, both, modern, classic, relaunch],
                          [precise, medium, loose, end, start], [snap, shortcuts]]
        for (index, controls) in tabButtons.enumerated() {
            expect(controls.allSatisfy { $0.isDescendant(of: tabs.tabViewItems[index].view!) },
                   "Controls belong to recovered tab \(tabs.tabViewItems[index].label)")
        }
        expect(!sharing.isDescendant(of: tabs) && !done.isDescendant(of: tabs), "Sharing and Done stay in footer")
        expect(buttons.count == 18 && buttons.filter { ![modern, classic, relaunch].contains($0) }.count == 15, "Only the supported controls")
        expect(modern.identifier?.rawValue == "appearanceModern" && classic.identifier?.rawValue == "appearanceClassic", "Appearance radios are addressable")
        expect(modern.accessibilityLabel() == "Modern appearance" && classic.accessibilityLabel() == "Classic appearance",
               "Appearance radios say what they choose")
        expect(modern.tag == 1 && classic.tag == 0, "Appearance tags follow AppearanceStyle order")
        expect(modern.accessibilityHelp() == "Takes effect the next time OpenSkitch opens." && classic.accessibilityHelp() == modern.accessibilityHelp(),
               "Radios carry the relaunch note for VoiceOver")
        expect(modern.state == .off && classic.state == .on, "Classic is the initial appearance")
        let appearanceLabel = views.compactMap { $0 as? NSTextField }.filter { $0.stringValue == "Appearance:" }
        let appearanceNote = views.compactMap { $0 as? NSTextField }.filter { $0.stringValue == "Takes effect the next time OpenSkitch opens." }
        expect(appearanceLabel.count == 1 && appearanceNote.count == 1, "Appearance row has its label and relaunch note")
        expect(appearanceLabel[0].font?.pointSize == 20 && appearanceNote[0].font!.pointSize >= 18, "Appearance row text is readable")
        expect(relaunch.identifier?.rawValue == "appearanceRelaunch" && relaunch.bezelStyle == .rounded, "Relaunch is a standard push button")
        expect(appearanceNote[0].identifier?.rawValue == "appearanceNote", "Relaunch note is addressable")
        expect(precise.tag == 0 && medium.tag == 1 && loose.tag == 2, "Original precision tags")
        expect(end.tag == 2 && start.tag == 1, "Original arrow tags")
        expect(dock.tag == 2 && menu.tag == 1 && both.tag == 0, "Original visibility tags")
        expect(medium.state == .on && end.state == .on && both.state == .on,
               "Initial radio choices")
        expect(snap.state == .on && sounds.state == .off, "Initial booleans")
        expect(toolTips.state == .off && keyboardTips.state == .off, "New native checkboxes initially unchecked")
        expect(!toolTips.allowsMixedState && !keyboardTips.allowsMixedState, "Tip checkboxes have two states")
        expect(done.keyEquivalent == "\r", "Done is the Return action")
        expect(form.intrinsicContentSize == NSSize(width: 780, height: 570), "Preferred form size")
        expect(form.constraints.contains { $0.firstAttribute == .width && $0.relation == .greaterThanOrEqual && $0.constant == 650 },
               "Minimum width is enforced")
        var delivered: [GeneralPreferencesState] = []
        form.onChange = { delivered.append($0) }
        var expected = initial
        func reveal(_ control: NSButton) {
            for item in tabs.tabViewItems where control.isDescendant(of: item.view!) {
                tabs.selectTabViewItem(item)
            }
        }
        func click(_ control: NSButton, _ update: (inout GeneralPreferencesState) -> Void) {
            let previousCount = delivered.count
            update(&expected)
            reveal(control)
            control.performClick(nil)
            expect(delivered.count == previousCount + 1, "One immediate callback for \(control.title)")
            expect(delivered.last == expected, "Complete current state for \(control.title)")
            for group in groups {
                expect(group.filter { $0.state == .on }.count == 1, "Radio group stays exclusive after \(control.title)")
            }
        }
        click(precise) { $0.drawingPrecision = .precise }
        click(loose) { $0.drawingPrecision = .loose }
        click(medium) { $0.drawingPrecision = .medium }
        click(medium) { $0.drawingPrecision = .medium }
        click(start) { $0.arrowHead = 1 }
        click(end) { $0.arrowHead = 2 }
        click(dock) { $0.statusMenu = 2 }
        click(menu) { $0.statusMenu = 1 }
        click(both) { $0.statusMenu = 0 }
        click(snap) { $0.includeSkitch = false }
        click(snap) { $0.includeSkitch = true }
        click(sounds) { $0.playSounds = true }
        click(sounds) { $0.playSounds = false }
        click(toolTips) { $0.showToolTips = true }
        click(keyboardTips) { $0.showKeyboardTips = true }
        click(toolTips) { $0.showToolTips = false }
        click(keyboardTips) { $0.showKeyboardTips = false }
        click(modern) { $0.appearance = .modern }
        expect(modern.state == .on && classic.state == .off, "Modern radio shows the choice")
        click(modern) { $0.appearance = .modern }
        click(classic) { $0.appearance = .classic }
        expect(modern.state == .off && classic.state == .on, "Classic radio shows the choice")
        click(classic) { $0.appearance = .classic }
        click(modern) { $0.appearance = .modern }
        var relaunches = 0
        form.onRelaunch = { relaunches += 1 }
        let beforeRelaunch = delivered.count
        relaunch.performClick(nil)
        expect(relaunches == 1 && delivered.count == beforeRelaunch, "Relaunch calls its callback once and publishes no edit")
        relaunch.performClick(nil)
        expect(relaunches == 2 && modern.state == .on && delivered.last == expected, "Relaunch keeps the chosen appearance")
        form.onRelaunch = nil
        relaunch.performClick(nil)
        expect(relaunches == 2 && delivered.count == beforeRelaunch, "An unbound relaunch callback is safe")
        click(classic) { $0.appearance = .classic }

        let count = delivered.count
        expected = GeneralPreferencesState(drawingPrecision: .loose, arrowHead: 1,
                                          includeSkitch: false, playSounds: true, statusMenu: 1,
                                          showToolTips: true, showKeyboardTips: true, appearance: .modern)
        reveal(precise) // Synchronize tips while the General tab is not visible.
        let selectedBeforeSync = tabs.selectedTabViewItem
        form.synchronize(expected)
        expect(tabs.selectedTabViewItem === selectedBeforeSync, "Synchronization preserves the current tab")
        expect(delivered.count == count, "Synchronization suppresses callbacks")
        expect(loose.state == .on && start.state == .on && menu.state == .on
               && snap.state == .off && sounds.state == .on && toolTips.state == .on
               && keyboardTips.state == .on, "Synchronization updates every field, including hidden tips")
        expect(modern.state == .on && classic.state == .off, "Synchronization updates the appearance radios")
        click(precise) { $0.drawingPrecision = .precise }

        for (tool, keyboard) in [(false, false), (true, false), (false, true), (true, true)] {
            expected.showToolTips = tool
            expected.showKeyboardTips = keyboard
            let count = delivered.count
            form.synchronize(expected)
            form.synchronize(expected)
            expect(delivered.count == count, "Tip refreshes, including unchanged state, never publish writes")
            expect(toolTips.state == (tool ? .on : .off) && keyboardTips.state == (keyboard ? .on : .off),
                   "Tip selections synchronize independently")
            click(keyboardTips) { $0.showKeyboardTips = !keyboard }
            click(keyboardTips) { $0.showKeyboardTips = keyboard }
        }

        for invalid in [-1, 3, Int.min, Int.max] {
            let count = delivered.count
            form.synchronize(GeneralPreferencesState(drawingPrecision: .medium, arrowHead: invalid,
                             includeSkitch: false, playSounds: true, statusMenu: invalid))
            expect(delivered.count == count, "Malformed tags do not publish during sync")
            expect(end.state == .on && start.state == .off && both.state == .on
                   && dock.state == .off && menu.state == .off, "Malformed tags use End and Both")
            expected = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                         includeSkitch: false, playSounds: true, statusMenu: 0)
            click(snap) { $0.includeSkitch = true }
        }
        let malformed = GeneralPreferencesForm(state: GeneralPreferencesState(drawingPrecision: .precise,
                          arrowHead: -10, includeSkitch: true, playSounds: false, statusMenu: 99))
        let malformedTabs = descendants(malformed).compactMap { $0 as? NSTabView }.first!
        let initialButtons = malformedTabs.tabViewItems.flatMap { descendants($0.view!) }.compactMap { $0 as? NSButton }
        expect(initialButtons.first { $0.title == "End" }?.state == .on
               && initialButtons.first { $0.title == "Both" }?.state == .on, "Initialization also normalizes tags")

        // The Appearance row only exists where Modern can run; elsewhere Classic is forced and nothing is reachable.
        func appearanceControls(in form: GeneralPreferencesForm) -> [NSView] {
            let tabs = descendants(form).compactMap { $0 as? NSTabView }.first!
            return tabs.tabViewItems.flatMap { descendants($0.view!) }.filter {
                ["appearanceModern", "appearanceClassic", "appearanceRelaunch", "appearanceNote"].contains($0.identifier?.rawValue ?? "")
                    || ($0 as? NSTextField)?.stringValue == "Appearance:"
                    || ($0 as? NSButton)?.title == "Modern" || ($0 as? NSButton)?.title == "Classic"
                    || ($0 as? NSButton)?.title == "Relaunch OpenSkitch"
            }
        }
        expect(appearanceControls(in: form).count == 5, "Available form shows label, two radios, note and Relaunch")
        let modernState = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeSkitch: true,
                                                  playSounds: false, statusMenu: 0, appearance: .modern)
        let availableModern = GeneralPreferencesForm(state: modernState, modernAvailable: true)
        let availableButtons = descendants(availableModern).compactMap { $0 as? NSTabView }.first!.tabViewItems
            .flatMap { descendants($0.view!) }.compactMap { $0 as? NSButton }
        expect(availableButtons.first { $0.title == "Modern" }?.state == .on && availableButtons.first { $0.title == "Classic" }?.state == .off,
               "Initialization selects the stored appearance")
        let unavailable = GeneralPreferencesForm(state: modernState, modernAvailable: false)
        expect(appearanceControls(in: unavailable).isEmpty, "No Appearance row, radios, note or Relaunch where Modern cannot run")
        var unavailableDelivered: [GeneralPreferencesState] = []
        unavailable.onChange = { unavailableDelivered.append($0) }
        let unavailableTabs = descendants(unavailable).compactMap { $0 as? NSTabView }.first!
        let unavailableButtons = unavailableTabs.tabViewItems.flatMap { descendants($0.view!) }.compactMap { $0 as? NSButton }
        expect(unavailableButtons.count == 13, "Unavailable form keeps exactly the original tab controls")
        unavailableButtons.first { $0.title == "Play sounds" }!.performClick(nil)
        expect(unavailableDelivered.count == 1 && unavailableDelivered[0].appearance == .classic && unavailableDelivered[0].playSounds,
               "Classic is forced even when the stored state asks for Modern")
        unavailable.synchronize(modernState)
        expect(appearanceControls(in: unavailable).isEmpty && unavailableDelivered.count == 1, "Synchronizing Modern never reveals the row or publishes")
        unavailableButtons.first { $0.title == "Play sounds" }!.performClick(nil)
        expect(unavailableDelivered.count == 2 && unavailableDelivered[1].appearance == .classic, "Forced Classic persists across edits")
        for size in [NSSize(width: 650, height: 500), NSSize(width: 780, height: 570)] {
            unavailable.setFrameSize(size)
            for item in unavailableTabs.tabViewItems {
                unavailableTabs.selectTabViewItem(item)
                unavailable.needsLayout = true
                unavailable.layoutSubtreeIfNeeded()
                for control in descendants(unavailable).compactMap({ $0 as? NSControl }) {
                    let frame = control.convert(control.bounds, to: unavailable)
                    expect(!control.hasAmbiguousLayout && unavailable.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                           "Unavailable form still lays out at \(size)")
                }
            }
        }
        let automatic = GeneralPreferencesForm(state: initial)
        expect(appearanceControls(in: automatic).isEmpty == !AppearanceResolver().supportsModern,
               "Default availability follows the running macOS")

        // A parent may immediately refresh the form from its persisted state.
        var reentrant = 0
        form.onChange = { value in reentrant += 1; form.synchronize(value) }
        reveal(sounds)
        sounds.performClick(nil)
        expect(reentrant == 1, "Parent synchronization cannot recurse into onChange")
        for control in [toolTips, keyboardTips] {
            form.synchronize(initial)
            var updates: [GeneralPreferencesState] = []
            form.onChange = { value in
                updates.append(value)
                form.synchronize(value)
            }
            reveal(control)
            control.performClick(nil)
            control.performClick(nil)
            var enabled = initial
            if control === toolTips { enabled.showToolTips = true }
            else { enabled.showKeyboardTips = true }
            expect(updates == [enabled, initial], "Tip callback can synchronously echo persisted state without duplicate delivery")
            expect(control.state == .off, "Reentrant tip updates leave the native control current")
        }
        form.synchronize(initial)
        var corrected: [GeneralPreferencesState] = []
        form.onChange = { value in
            corrected.append(value)
            var persisted = value
            persisted.showToolTips = false
            form.synchronize(persisted)
        }
        reveal(toolTips)
        toolTips.performClick(nil)
        expect(corrected.count == 1 && corrected[0].showToolTips && toolTips.state == .off,
               "Parent correction during a tip action is authoritative and does not recurse")
        keyboardTips.performClick(nil)
        expect(corrected.count == 2 && !corrected[1].showToolTips && corrected[1].showKeyboardTips,
               "Next action carries the corrected state, without stale tip values")
        form.onChange = { delivered.append($0) }
        let routeCount = delivered.count
        var routes: [String] = []
        form.onDone = { routes.append("done") }
        form.onShortcuts = { routes.append("shortcuts") }
        form.onSharing = { routes.append("sharing") }
        reveal(shortcuts)
        shortcuts.performClick(nil); sharing.performClick(nil); done.performClick(nil)
        expect(routes == ["shortcuts", "sharing", "done"], "Real native actions route once to their parent callbacks")
        expect(delivered.count == routeCount, "Action routes never send preference edits")
        form.onDone = nil; form.onShortcuts = nil; form.onSharing = nil; form.onChange = nil
        done.performClick(nil); shortcuts.performClick(nil); sharing.performClick(nil); snap.performClick(nil)
        expect(routes.count == 3 && delivered.count == routeCount, "Unbound callbacks are safe")

        form.onChange = { delivered.append($0) }
        form.synchronize(initial)
        for size in [NSSize(width: 650, height: 500), NSSize(width: 650, height: 570),
                     NSSize(width: 780, height: 570), NSSize(width: 1000, height: 570)] {
            let width = size.width
            form.setFrameSize(size)
            for item in tabs.tabViewItems {
                let tabCount = delivered.count
                tabs.selectTabViewItem(item)
                form.needsLayout = true
                form.layoutSubtreeIfNeeded()
                expect(tabs.selectedTabViewItem === item && item.view!.isDescendant(of: form), "Native tab switching shows its content")
                let fitted = tabs.alignmentRect(forFrame: tabs.frame)
                expect(fitted.minX >= 23 && fitted.maxX <= form.bounds.maxX - 23 && fitted.minY >= 79 && fitted.maxY <= form.bounds.maxY - 23,
                       "Tabs keep the form's margins at \(size) on \(item.label): \(fitted)")
                expect(delivered.count == tabCount, "Tab selection does not publish preference edits")
                expect(medium.state == .on && end.state == .on && both.state == .on
                       && snap.state == .on && sounds.state == .off && toolTips.state == .off
                       && keyboardTips.state == .off && classic.state == .on && modern.state == .off, "Tab changes preserve every preference")
                let controls = descendants(form).compactMap { $0 as? NSControl }
                for control in controls {
                    let frame = control.convert(control.bounds, to: form)
                    expect((control.font?.pointSize ?? 0) >= 18, "Readable native text at \(width): \(control)")
                    expect(frame.width > 0 && frame.height > 0, "Nonempty layout at \(width): \(frame)")
                    expect(!control.hasAmbiguousLayout, "Unambiguous native layout at \(width)")
                    expect(form.bounds.insetBy(dx: -1, dy: -1).contains(frame), "Control stays inside form at \(width): \(frame)")
                    if let button = control as? NSButton {
                        expect((button.font?.pointSize ?? 0) >= 20, "20pt control at \(width)")
                        expect(button.target === form && button.action != nil, "Every button has a native action")
                        expect(frame.height >= 36, "Comfortable control height")
                        let available = button.bounds.size
                        let needed = button.cell!.cellSize(forBounds: NSRect(origin: .zero, size: available))
                        expect(needed.width <= available.width + 1 && needed.height <= available.height + 1,
                               "Title fits without clipping at \(width): \(button.title), needed \(needed), available \(available)")
                    }
                }
                for all in groups + [[sharing, done], [sounds, toolTips, keyboardTips], [modern, classic, relaunch], [toolTips, keyboardTips, modern, relaunch]] {
                    let group = all.filter { $0.isDescendant(of: form) }
                    for index in group.indices {
                        for other in group.indices where index < other {
                            expect(!group[index].convert(group[index].bounds, to: form).intersects(
                                   group[other].convert(group[other].bounds, to: form)), "Choices/actions do not overlap at \(width)")
                        }
                    }
                }
                if item.label == "General" {
                    for control in [toolTips, keyboardTips, modern, classic, relaunch] {
                        let frame = control.convert(control.bounds, to: item.view!)
                        expect(item.view!.bounds.contains(frame), "\(control.title) fits inside General at \(size)")
                    }
                    let note = appearanceNote[0].convert(appearanceNote[0].bounds, to: item.view!)
                    expect(item.view!.bounds.contains(note) && !note.intersects(relaunch.convert(relaunch.bounds, to: item.view!)),
                           "Relaunch note fits inside General and stays clear of the button at \(size)")
                }
                for field in controls.compactMap({ $0 as? NSTextField }) {
                    let minimum: CGFloat = field.stringValue.hasPrefix("Holding Option") || field.stringValue.hasPrefix("Takes effect") ? 18 : 20
                    expect((field.font?.pointSize ?? 0) >= minimum, "Body labels are 20pt; Option help and the relaunch note are at least 18pt")
                    let needed = field.cell!.cellSize(forBounds: field.bounds)
                    expect(needed.width <= field.bounds.width + 1 && needed.height <= field.bounds.height + 1,
                           "Label/help fits at \(width): \(field.stringValue)")
                }
                expect(snap.cell?.wraps == true && snap.cell?.lineBreakMode == .byWordWrapping,
                       "Long Snap title wraps at readable size")
                if CommandLine.arguments.contains("--render") {
                    // Offscreen evidence only, saved in ignored build/. No desktop input.
                    if let bitmap = form.bitmapImageRepForCachingDisplay(in: form.bounds) {
                        form.effectiveAppearance.performAsCurrentDrawingAppearance {
                            form.cacheDisplay(in: form.bounds, to: bitmap)
                        }
                        let image = NSImage(size: form.bounds.size)
                        image.lockFocus()
                        form.effectiveAppearance.performAsCurrentDrawingAppearance {
                            NSColor.windowBackgroundColor.setFill()
                            form.bounds.fill()
                            let overlay = NSImage(size: form.bounds.size)
                            overlay.addRepresentation(bitmap)
                            overlay.draw(in: form.bounds, from: .zero, operation: .sourceOver, fraction: 1)
                        }
                        image.unlockFocus()
                        if let tiff = image.tiffRepresentation, let composed = NSBitmapImageRep(data: tiff),
                           let png = composed.representation(using: .png, properties: [:]) {
                            try png.write(to: URL(fileURLWithPath: "build/general-preferences-\(item.label.lowercased())-\(Int(width)).png"))
                        }
                    }
                }
            }
        }
        print("GeneralPreferencesFormTests: \(checks) checks passed (native actions and offscreen layout; no desktop input)")
    }
}
#endif
