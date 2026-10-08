// Standalone NSMenu trees only; no application delegate, no windows, no desktop input.
// xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D MENU_SYMBOLS_TESTS Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/MenuSymbols.swift tests/MenuSymbolsTests.swift -o build/menu-symbols-tests
#if MENU_SYMBOLS_TESTS
import AppKit

@main
@MainActor
private enum MenuSymbolsTests {
    private static var checks = 0, skipped: [String] = []
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static func item(_ title: String, _ action: String?) -> NSMenuItem {
        NSMenuItem(title: title, action: action.map { NSSelectorFromString($0) }, keyEquivalent: "")
    }

    static func main() {
        _ = NSApplication.shared
        mapping()
        sourceActions()
        if #available(macOS 26, *) { application() } else { skipped.append("apply(to:) (needs macOS 26)") }
        let note = skipped.isEmpty ? "" : "; SKIPPED: " + skipped.joined(separator: ", ")
        print("MenuSymbolsTests: \(checks) checks passed (standalone menus; no desktop input)\(note)")
    }

    private static func mapping() {
        expect(MenuSymbols.map.count >= 55, "Menu symbol table covers the main menu (\(MenuSymbols.map.count) entries)")
        for (selector, name) in MenuSymbols.map {
            expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(selector) maps to \(name), which exists on this host")
        }
        expect(MenuSymbols.map[NSSelectorFromString("about")] == "info.circle" && MenuSymbols.map[NSSelectorFromString("quit")] == "power", "Spot-checked symbols")
        expect(MenuSymbols.map[NSSelectorFromString("changeSmoothing:")] == nil && MenuSymbols.map[NSSelectorFromString("hideOtherApplications:")] == nil,
               "Stateful and system items stay unmapped")
    }

    private static func sourceActions() {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [here, here.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true)]
        guard let directory = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App.swift").path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "swift" }) else {
            skipped.append("action names (App.swift not found)"); return
        }
        let text = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for selector in MenuSymbols.map.keys {
            let name = NSStringFromSelector(selector)
            let regex = try! NSRegularExpression(pattern: "@objc\\s+func\\s+\(NSRegularExpression.escapedPattern(for: name))\\(\\)")
            expect(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil, "@objc func \(name)() exists in Sources")
        }
    }

    @available(macOS 26, *)
    private static func application() {
        let preset = NSImage(size: NSSize(width: 4, height: 4))
        let root = NSMenu(title: "Root")
        let about = item("About", "about"), kept = item("Preset", "newFile"), unknown = item("Unknown", "noSuchAction"), bare = item("Bare", nil)
        kept.image = preset
        let top = item("Edit", nil), nested = item("More", nil), deep = item("Deep", nil)
        let undo = item("Undo", "undo"), snap = item("Snap", "screenSnap"), web = item("Web", "webSnap"), group = item("Group", "group")
        let editMenu = NSMenu(title: "Edit"), moreMenu = NSMenu(title: "More"), deepMenu = NSMenu(title: "Deep")
        deepMenu.addItem(web); deep.submenu = deepMenu
        moreMenu.addItem(snap); moreMenu.addItem(deep); nested.submenu = moreMenu
        editMenu.addItem(undo); editMenu.addItem(group); editMenu.addItem(nested); top.submenu = editMenu
        let separator = NSMenuItem.separator(), nestedSeparator = NSMenuItem.separator()
        separator.action = NSSelectorFromString("about"); nestedSeparator.action = NSSelectorFromString("quit")
        moreMenu.insertItem(nestedSeparator, at: 1)
        for entry in [about, separator, kept, unknown, bare, top] { root.addItem(entry) }

        MenuSymbols.apply(to: root)
        for (entry, name) in [(about, "info.circle"), (undo, "arrow.uturn.backward"), (group, "rectangle.3.group"), (snap, "scope"), (web, "link")] {
            expect(entry.image != nil && entry.image?.isTemplate == true && (entry.image?.size.width ?? 0) > 0, "\(entry.title) received a template symbol")
            expect(entry.image?.size == NSImage(systemSymbolName: name, accessibilityDescription: nil)?.size, "\(entry.title) received \(name)")
        }
        expect(kept.image === preset, "Existing images are left alone")
        expect(unknown.image == nil && bare.image == nil && top.image == nil && nested.image == nil && deep.image == nil, "Unmapped, action-less and container items stay bare")
        expect(separator.isSeparatorItem && separator.image == nil && nestedSeparator.isSeparatorItem && nestedSeparator.image == nil, "Separators are skipped, even with an action")

        let applied = about.image
        MenuSymbols.apply(to: root)
        expect(about.image === applied, "Applying twice keeps the first symbols")
        MenuSymbols.apply(to: NSMenu(title: "Empty"))

        let original = MenuSymbols.symbolImage
        defer { MenuSymbols.symbolImage = original }
        MenuSymbols.symbolImage = { _ in nil }
        let fresh = NSMenu(title: "Fresh"), missing = item("Missing", "about")
        fresh.addItem(missing)
        let sub = item("Sub", nil), subMenu = NSMenu(title: "Sub"), inner = item("Inner", "quit")
        subMenu.addItem(inner); sub.submenu = subMenu; fresh.addItem(sub)
        MenuSymbols.apply(to: fresh)
        expect(missing.image == nil && inner.image == nil, "A symbol missing on the host leaves the item bare instead of crashing")
    }
}
#endif
