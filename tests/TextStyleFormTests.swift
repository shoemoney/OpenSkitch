// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D TEXT_STYLE_FORM_TESTS \
//   Sources/TextStyleForm.swift \
//   tests/TextStyleFormTests.swift -o /tmp/skitch-text-style-form-tests
// /tmp/skitch-text-style-form-tests
#if TEXT_STYLE_FORM_TESTS
import AppKit

final class ToolbarFixture: NSObject, NSToolbarDelegate {
    let items: [NSToolbarItem]
    init(items: [NSToolbarItem]) { self.items = items }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { items.map { $0.itemIdentifier } }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { items.first { $0.itemIdentifier == identifier } }
}

@main
struct TextStyleFormTests {
    static func main() {
        _ = NSApplication.shared
        var checks = 0, failures: [String] = []
        func expect(_ condition: Bool, _ message: String) { if !condition { failures.append(message); print("FAIL: \(message)") }; checks += 1 }
        let form = TextStyleForm(outlined: nil, shadowed: nil)
        expect(form.outlineChoice == nil && form.shadowChoice == nil, "Mixed states preserve each annotation value")
        expect(form.outline.state == .mixed && form.shadowControl.state == .mixed, "Native controls display mixed selection")
        var outlines: [Bool] = [], shadows: [Bool] = [], defaults = 0
        form.onOutlineChange = { outlines.append($0) }; form.onShadowChange = { shadows.append($0) }; form.onDefaultRequested = { defaults += 1 }
        form.setChoices(outlined: true, shadowed: false)
        expect(form.outlineChoice == true && form.shadowChoice == false, "Uniform selection states")
        expect(outlines.isEmpty && shadows.isEmpty && defaults == 0, "Selection refresh does not send edit actions")
        form.outline.performClick(nil)
        expect(form.outlineChoice == false && outlines == [false], "Native click toggles outline off")
        form.outline.performClick(nil)
        expect(form.outlineChoice == true && outlines == [false,true], "Native click toggles outline on")
        form.setChoices(outlined: nil, shadowed: nil)
        form.outline.performClick(nil); form.shadowControl.performClick(nil)
        expect(form.outlineChoice == true && form.shadowChoice == true, "Clicking mixed original effect enables it")
        expect(outlines.last == true && shadows == [true], "Live mixed controls send explicit choices")
        form.shadowControl.performClick(nil)
        expect(form.shadowChoice == false && shadows == [true,false], "Shadow can be turned off after mixed selection")
        form.restoreDefault()
        expect(form.outlineChoice == true && form.shadowChoice == true && defaults == 1, "Default action enables both effects and routes one request")
        form.layoutSubtreeIfNeeded()
        for control in [form.outline,form.shadowControl,form.defaults] {
            expect((control.font?.pointSize ?? 0) >= 20, "Readable accessory text")
            expect(control.target === form && control.action != nil, "Every accessory control has a native action")
            expect(control.convert(control.bounds, to: form).maxY <= form.bounds.maxY + 1, "Accessory contains each control")
        }
        // Reproduce the public structure captured in fontpanel-arranged-layout.json,
        // without ordering a real window or depending on private AppKit classes.
        let panel = NSFontPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                                styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 940, height: 720))
        panel.contentView = root
        let unrelated = NSSplitView(frame: root.bounds)
        unrelated.isVertical = true
        unrelated.addArrangedSubview(NSView()); unrelated.addArrangedSubview(NSView())
        root.addSubview(unrelated); unrelated.adjustSubviews(); unrelated.setPosition(180, ofDividerAt: 0)
        let unrelatedBefore = unrelated.arrangedSubviews.map { $0.frame }
        expect(!TextStyleForm.prepareFontPanelLayout(panel), "Unrelated hierarchy without an accessory reports no native structure")
        expect(unrelated.arrangedSubviews.map { $0.frame } == unrelatedBefore,
               "Unrelated wide split retains its divider")
        let constrained = TextStyleForm(outlined: nil, shadowed: false)
        constrained.frame.size = NSSize(width: 160, height: 66)
        constrained.layoutSubtreeIfNeeded()
        expect(constrained.subviews.contains { $0 is NSScrollView },
               "Constrained accessory exposes overflow through a native scroll container")
        if let scroll = constrained.subviews.first as? NSScrollView, let document = scroll.documentView {
            expect(document.frame.width > scroll.contentSize.width && document.frame.height > scroll.contentSize.height,
                   "Constrained accessory keeps natural control sizes in scrollable content")
            for control in [constrained.outline, constrained.shadowControl, constrained.defaults] {
                let rectangle = control.convert(control.bounds, to: document)
                expect(document.bounds.contains(rectangle), "No accessory control lies outside its content")
                expect(control.frame.width + 1 >= control.fittingSize.width && control.frame.height + 1 >= control.fittingSize.height,
                       "Overflow preserves a control's full readable native size")
                document.scrollToVisible(rectangle)
                expect(document.visibleRect.intersects(rectangle), "Each constrained control can be scrolled into view")
            }
            constrained.frame.size = NSSize(width: 460, height: 140)
            constrained.layoutSubtreeIfNeeded()
            expect(document.frame.size == scroll.contentSize, "Growing accessory removes unnecessary overflow")
            expect(constrained.outlineChoice == nil && constrained.shadowChoice == false,
                   "Constrain and expand preserve mixed and explicit choices")
        }
        panel.accessoryView = form
        panel.contentView = root
        root.frame.size = NSSize(width: 940, height: 720)
        unrelated.removeFromSuperview()
        let split = NSSplitView(frame: root.bounds); split.isVertical = true
        let family = NSView(), detail = NSView()
        let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 180, height: 700))
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        family.addSubview(outlineView); detail.addSubview(tableView); detail.addSubview(form)
        split.addArrangedSubview(family); split.addArrangedSubview(detail)
        root.addSubview(split); split.adjustSubviews(); split.setPosition(180, ofDividerAt: 0)
        expect(TextStyleForm.prepareFontPanelLayout(panel), "Matching native structure reports that the opening layout was applied")
        expect(abs(family.frame.width - 360) <= 1, "Only the evidenced native family/detail split widens")
        split.setPosition(400, ofDividerAt: 0)
        expect(TextStyleForm.prepareFontPanelLayout(panel), "Matching structure still reports success when no widening is needed")
        expect(abs(family.frame.width - 400) <= 1, "Opening preparation preserves an already wider divider")
        let nested = NSSplitView(frame: NSRect(x: 0, y: 0, width: 900, height: 300))
        nested.isVertical = true; nested.addArrangedSubview(NSView()); nested.addArrangedSubview(NSView())
        detail.addSubview(nested); nested.adjustSubviews(); nested.setPosition(180, ofDividerAt: 0)
        let nestedBefore = nested.arrangedSubviews.map { $0.frame }
        expect(TextStyleForm.prepareFontPanelLayout(panel), "Nested preview splits do not hide the outer native structure")
        expect(nested.arrangedSubviews.map { $0.frame } == nestedBefore, "Nested wide preview split is not touched")
        form.removeFromSuperview()
        split.setPosition(180, ofDividerAt: 0)
        expect(!TextStyleForm.prepareFontPanelLayout(panel), "Detached accessory reports an unloaded native structure")
        expect(abs(family.frame.width - 180) <= 1, "Incomplete/detached native accessory does not match layout")
        detail.addSubview(form)
        split.frame.size.width = 700; split.adjustSubviews(); split.setPosition(180, ofDividerAt: 0)
        let narrowBefore = split.arrangedSubviews.map { $0.frame }
        expect(!TextStyleForm.prepareFontPanelLayout(panel), "Narrow font panel does not report the wide native structure")
        expect(split.arrangedSubviews.map { $0.frame } == narrowBefore, "Narrow font panel retains native divider allocation")
        split.frame.size.width = 940; split.addArrangedSubview(NSView()); split.adjustSubviews()
        let additionalPaneBefore = split.arrangedSubviews.map { $0.frame }
        expect(!TextStyleForm.prepareFontPanelLayout(panel), "Unknown three-pane hierarchy does not report a match")
        expect(split.arrangedSubviews.map { $0.frame } == additionalPaneBefore,
               "Unknown native three-pane hierarchy is left untouched")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
        popup.addItems(withTitles: ["All Fonts", "Favorites", String(repeating: "Long collection ", count: 12)])
        popup.font = .systemFont(ofSize: 13)
        popup.itemArray[1].attributedTitle = NSAttributedString(string: "Favorites",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.systemBlue])
        popup.itemArray[0].attributedTitle = NSAttributedString(string: "All Fonts",
                                attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("controlled-collection"))
        item.view = popup; item.minSize = NSSize(width: 220, height: 32)
        item.maxSize = NSSize(width: 600, height: 80)
        let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 325, height: 32))
        searchField.stringValue = "Helvetica"; searchField.font = .systemFont(ofSize: 13)
        let searchItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("controlled-search"))
        searchItem.view = searchField
        searchItem.minSize = NSSize(width: 100, height: 32); searchItem.maxSize = NSSize(width: 400, height: 80)
        let sizePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 80, height: 32))
        sizePopup.addItems(withTitles: ["24", "48"])
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 32)); wrapper.addSubview(sizePopup)
        let sizeItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("controlled-size"))
        sizeItem.view = wrapper
        let delegate = ToolbarFixture(items: [item, searchItem, sizeItem])
        let toolbar = NSToolbar(identifier: "controlled-font-toolbar")
        toolbar.delegate = delegate; panel.toolbar = toolbar
        toolbar.insertItem(withItemIdentifier: item.itemIdentifier, at: 0)
        toolbar.insertItem(withItemIdentifier: searchItem.itemIdentifier, at: 1)
        toolbar.insertItem(withItemIdentifier: sizeItem.itemIdentifier, at: 2)
        popup.selectItem(at: 1)
        let popupBefore = popup.frame, searchBefore = searchField.frame, sizeBefore = sizePopup.frame
        let menuBefore = popup.itemArray
        let searchMinimum = searchItem.minSize, searchMaximum = searchItem.maxSize
        let sizeMenuBefore = sizePopup.itemArray
        let callbacksBefore = (outlines, shadows, defaults)
        let accessoryActions = [form.outline.action, form.shadowControl.action, form.defaults.action]
        TextStyleForm.prepareFontPanel(panel)
        expect(popup.frame == popupBefore, "Typography refresh does not sizeToFit a toolbar view")
        expect(item.maxSize.width >= 600 && item.maxSize.height >= 80,
               "Toolbar keeps AppKit's flexible size range")
        let titleFont = popup.itemArray[0].attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(titleFont?.pointSize == 24 && NSFontManager.shared.traits(of: titleFont!).contains(.boldFontMask),
               "Readable attributed menu title retains its size and weight")
        expect(item.minSize.width == 220, "Long menu titles do not reserve the toolbar's field space")
        expect(popup.indexOfSelectedItem == 1 && popup.itemArray.elementsEqual(menuBefore, by: { $0 === $1 }),
               "Preparation preserves menu item ownership and selected collection")
        expect(searchField.frame == searchBefore && searchField.stringValue == "Helvetica"
               && searchItem.minSize == searchMinimum && searchItem.maxSize == searchMaximum,
               "Search field retains query, frame and native toolbar allocation")
        expect(sizePopup.frame == sizeBefore && sizePopup.itemArray.elementsEqual(sizeMenuBefore, by: { $0 === $1 }),
               "Wrapped native size menu retains frame and item identities")
        expect((searchField.font?.pointSize ?? 0) >= 20 && (sizePopup.font?.pointSize ?? 0) >= 20,
               "Search and size controls retain readable type")
        let resizedFont = popup.itemArray[1].attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(resizedFont?.pointSize == 20 && resizedFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true,
               "Small menu text grows without losing native weight")
        expect(popup.itemArray[1].attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemBlue,
               "Menu typography adjustment preserves unrelated attributed styling")
        let sizesBeforeRefresh = (item.minSize, item.maxSize)
        for _ in 0..<4 { TextStyleForm.prepareFontPanel(panel) }
        expect(popup.frame == popupBefore && item.minSize == sizesBeforeRefresh.0 && item.maxSize == sizesBeforeRefresh.1,
               "Repeated preparation does not grow or reset toolbar allocations")
        expect(outlines == callbacksBefore.0 && shadows == callbacksBefore.1 && defaults == callbacksBefore.2,
               "Layout and typography preparation do not send text changes")
        expect([form.outline.action, form.shadowControl.action, form.defaults.action] == accessoryActions
               && form.outline.target === form && form.shadowControl.target === form && form.defaults.target === form,
               "Preparation preserves live accessory action routing")
        expect(!panel.isVisible, "Controlled native panel is never ordered on the desktop")
        for size in [NSSize.zero, NSSize(width: 160, height: 66), NSSize(width: 460, height: 140)] {
            constrained.setFrameSize(size); constrained.layoutSubtreeIfNeeded()
            if let scroll = constrained.subviews.first as? NSScrollView, let document = scroll.documentView {
                for control in [constrained.outline, constrained.shadowControl, constrained.defaults] {
                    expect(document.bounds.contains(control.convert(control.bounds, to: document)),
                           "Accessory detach/constrain/expand retains controls inside scroll content")
                    expect(control.font?.pointSize == 20, "Resize never reduces accessory typography")
                }
            }
        }
        // Fonts panel frame: bound the SIZE to the usable area first, then center on the
        // anchor and clamp the origin. Chrome (title bar and toolbar) is part of the frame size.
        let chrome = NSSize(width: 0, height: 52)
        let desiredFrame = NSSize(width: 940 + chrome.width, height: 720 + chrome.height)
        func inside(_ frame: NSRect, _ area: NSRect) -> Bool {
            frame.minX >= area.minX - 0.001 && frame.maxX <= area.maxX + 0.001
                && frame.minY >= area.minY - 0.001 && frame.maxY <= area.maxY + 0.001
        }
        let roomy = NSRect(x: 0, y: 93, width: 2056, height: 1197).insetBy(dx: 12, dy: 12)
        let main = NSRect(x: 500, y: 400, width: 800, height: 600)
        let centered = TextStyleForm.fontPanelFrame(size: desiredFrame, visible: roomy, anchor: main)
        expect(centered.size == desiredFrame && abs(centered.midX - main.midX) < 0.001 && abs(centered.midY - main.midY) < 0.001,
               "Large display keeps the full requested panel centered on the main window")
        let corner = TextStyleForm.fontPanelFrame(size: desiredFrame, visible: roomy, anchor: NSRect(x: 1900, y: 1200, width: 120, height: 80))
        expect(corner.size == desiredFrame && inside(corner, roomy) && corner.maxX == roomy.maxX && corner.maxY == roomy.maxY,
               "A main window near the corner clamps the origin without shrinking the panel")
        let lowCorner = TextStyleForm.fontPanelFrame(size: desiredFrame, visible: roomy, anchor: NSRect(x: -200, y: 0, width: 100, height: 60))
        expect(lowCorner.size == desiredFrame && inside(lowCorner, roomy) && lowCorner.minX == roomy.minX && lowCorner.minY == roomy.minY,
               "A main window past the origin clamps to the opposite edge")
        for display in [NSSize(width: 1024, height: 640), NSSize(width: 1280, height: 720), NSSize(width: 800, height: 500), NSSize(width: 600, height: 400)] {
            let area = NSRect(origin: CGPoint(x: 0, y: 25), size: display).insetBy(dx: 12, dy: 12)
            for anchor in [main, NSRect(x: -400, y: -300, width: 200, height: 100), NSRect(x: 3000, y: 2000, width: 200, height: 100), area] {
                let frame = TextStyleForm.fontPanelFrame(size: desiredFrame, visible: area, anchor: anchor)
                expect(inside(frame, area), "Small \(Int(display.width))x\(Int(display.height)) display keeps the whole panel on screen")
                expect(frame.width == min(desiredFrame.width, area.width) && frame.height == min(desiredFrame.height, area.height),
                       "Panel shrinks only in the dimension that does not fit \(Int(display.width))x\(Int(display.height))")
            }
        }
        let secondary = NSRect(x: -1920, y: 200, width: 1920, height: 1080).insetBy(dx: 12, dy: 12)
        let onSecondary = TextStyleForm.fontPanelFrame(size: desiredFrame, visible: secondary, anchor: NSRect(x: -1500, y: 600, width: 400, height: 300))
        expect(inside(onSecondary, secondary) && onSecondary.size == desiredFrame, "Secondary displays with a negative origin are bounded the same way")
        let exact = NSRect(origin: CGPoint(x: 40, y: 60), size: desiredFrame)
        expect(TextStyleForm.fontPanelFrame(size: desiredFrame, visible: exact, anchor: main) == exact, "A display exactly the panel size places it exactly")
        // Convert between content and frame with the panel itself so title-bar chrome is honored.
        let geometryPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let wantedContent = NSSize(width: 940, height: 720)
        let wantedFrame = geometryPanel.frameRect(forContentRect: NSRect(origin: .zero, size: wantedContent)).size
        expect(wantedFrame.height > wantedContent.height, "Titled panel frame includes chrome beyond its content")
        let tight = NSRect(x: 0, y: 0, width: 1024, height: 640).insetBy(dx: 12, dy: 12)
        let placed = TextStyleForm.fontPanelFrame(size: wantedFrame, visible: tight, anchor: main)
        geometryPanel.setFrame(placed, display: false)
        let content = geometryPanel.contentRect(forFrameRect: geometryPanel.frame)
        expect(inside(geometryPanel.frame, tight) && content.width <= wantedContent.width && content.height > 0
               && abs(content.height - (placed.height - (wantedFrame.height - wantedContent.height))) < 0.5,
               "Bounded frame converts back to a smaller content area on a short display")
        precondition(failures.isEmpty, failures.joined(separator: "; "))
        print("TextStyleFormTests: \(checks) checks passed (native accessory controls; no desktop input)")
    }
}
#endif
