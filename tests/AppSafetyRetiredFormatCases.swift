// The retired document formats (.skitch and .skitchredux) are never opened, saved, dropped or offered;
// .opensnap is the only document type. This file names the retired extensions on purpose, so it is on the
// allowlist of tools/check-skitch-strings.py. Run through tools/test-app-safety.sh.
#if APP_SAFETY_TESTS
import AppKit
import UniformTypeIdentifiers

@MainActor
private final class RetiredDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint = .zero
    var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(board: NSPasteboard) { draggingPasteboard = board; super.init() }
    func slideDraggedImage(to screenPoint: NSPoint) { }
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() { }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) { }
}

extension AppSafetyTests {
    static let retiredExtensions = ["skitch", "skitchredux"]

    static func retiredFixtureData() throws -> Data {
        for base in ["tests/fixtures", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures").path] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: base).appendingPathComponent("legacy-sample.skitch")) { return data }
        }
        throw Failure(description: "Missing legacy fixture")
    }

    static var retiredFormatCases: [(String, () throws -> Void)] {
        [
            ("Open and Save panels offer only .opensnap documents and pictures", openAndSavePanelTypes),
            ("Opening a retired-format file is refused with an error and changes nothing", openingRetiredFormatIsRefused),
            ("Dropping a retired-format file is refused; dropping .opensnap routes to Open", droppingRetiredFormatIsRefused),
            ("Save writes .opensnap, History archives .opensnap, and the saved file reopens identically", saveProducesOpenSnapAndReopens),
            ("No menu title, window title, tooltip or accessibility label names the retired product", noRetiredProductNames),
        ]
    }

    static func openAndSavePanelTypes() throws {
        let open = AppDelegate.openPanelContentTypes, save = AppDelegate.savePanelContentTypes
        try expect(AppDelegate.documentType.identifier == "com.shoemoney.opensnap.document", "Document type identifier")
        try expect(open.contains(AppDelegate.documentType) && open.contains(.image) && open.contains(.pdf), "Open offers pictures and .opensnap")
        try expect(!open.contains(.data) && !open.contains(.item), "Open must not accept arbitrary data")
        try expect(save == [AppDelegate.documentType], "Save offers only .opensnap")
        for ext in retiredExtensions {
            for type in open + save {
                try expect(!(type.tags[.filenameExtension] ?? []).contains(ext), "\(type.identifier) claims .\(ext)")
            }
            if let retired = UTType(filenameExtension: ext) {
                try expect(!open.contains { retired.conforms(to: $0) && $0 != .data }, ".\(ext) must not conform to anything Open accepts")
            }
        }
    }

    static func openingRetiredFormatIsRefused() throws {
        let bytes = try retiredFixtureData()
        for ext in retiredExtensions {
            let fixture = try Fixture(), app = fixture.app
            let url = app.support.appendingPathComponent("retired-\(UUID().uuidString).\(ext)")
            try bytes.write(to: url)
            let before = app.canvas.document, seen = AppSafetyAlert.seen.count, unexpected = AppSafetyAlert.unexpected.count
            AppSafetyAlert.answers.append(.init(title: "OpenSnap opens pictures, PDFs and its own .opensnap drawings, but not this kind of file.", response: .alertFirstButtonReturn))
            app.openURL(url)
            try expect(app.canvas.document == before && app.currentURL == nil && !app.dirty, ".\(ext) must not load into the editor")
            try expect(AppSafetyAlert.seen.count == seen + 1 && AppSafetyAlert.unexpected.count == unexpected, ".\(ext) must be reported as an unsupported file type")
            try expect(try Data(contentsOf: url) == bytes, "The refused file is not touched")
        }
    }

    static func droppingRetiredFormatIsRefused() throws {
        let bytes = try retiredFixtureData()
        let fixture = try Fixture(), app = fixture.app
        var opened: [URL] = []
        app.canvas.onOpenDocument = { opened.append($0) }
        let before = app.canvas.document
        for ext in retiredExtensions {
            let url = app.support.appendingPathComponent("dropped-\(UUID().uuidString).\(ext)")
            try bytes.write(to: url)
            let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
            board.writeObjects([url as NSURL])
            let drag = RetiredDrag(board: board)
            try expect(app.canvas.draggingEntered(drag).isEmpty, ".\(ext) drop must not be offered")
            try expect(!app.canvas.performDragOperation(drag) && opened.isEmpty && app.canvas.document == before, ".\(ext) drop must not open or change anything")
        }
        let native = app.support.appendingPathComponent("dropped-\(UUID().uuidString).opensnap")
        try OpenSnapFile(document: SketchDocument(size: CGSize(width: 50, height: 40))).write(to: native)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.writeObjects([native as NSURL])
        let drag = RetiredDrag(board: board)
        try expect(app.canvas.draggingEntered(drag) == .copy && app.canvas.performDragOperation(drag) && opened == [native], ".opensnap drop routes to Open")
    }

    static func saveProducesOpenSnapAndReopens() throws {
        let fixture = try Fixture(), app = fixture.app
        var rectangle = SketchElement(kind: .rectangle)
        rectangle.rect = CGRect(x: 10, y: 12, width: 60, height: 40); rectangle.color = SketchColor(.systemTeal); rectangle.strokeWidth = 4
        var label = SketchElement(kind: .text)
        label.text = "Round trip"; label.rect = CGRect(x: 20, y: 70, width: 120, height: 30); label.fontName = "Georgia"; label.fontSize = 22
        app.canvas.newBlank(size: NSSize(width: 200, height: 150))
        app.canvas.document.elements = [rectangle, label]
        app.drawingDefaults = DrawingDefaults(values: ["brushSize": "7", "brushColor": "rgb(1,2,3)"])
        let saved = app.canvas.document, defaults = app.drawingDefaults
        let url = fixture.file("RoundTrip"); app.currentURL = url
        try expect(app.save(), "Save succeeds")
        try expect(url.pathExtension == "opensnap", "Saved file is .opensnap")
        let bytes = try Data(contentsOf: url)
        try expect(bytes.first == UInt8(ascii: "{") && String(decoding: bytes, as: UTF8.self).contains("\"format\":\"com.shoemoney.opensnap.document\""), "Saved bytes are the native JSON format")
        try expect(!(String(decoding: bytes, as: UTF8.self).contains("<svg")), "Saved file is not the retired SVG format")
        let history = try app.archiveStore().entries
        try expect(!history.isEmpty && history.allSatisfy { $0.nativeFile.hasSuffix(".opensnap") }, "History archives .opensnap: \(history.map(\.nativeFile))")
        let restored = try Fixture()
        restored.app.openURL(url)
        try expect(restored.app.canvas.document == saved && restored.app.drawingDefaults == defaults && restored.app.currentURL == url,
                   "The saved file reopens identically, including drawing defaults")
        try expect(!restored.app.dirty, "A freshly opened file is not dirty")
    }

    static func noRetiredProductNames() throws {
        let fixture = try Fixture(), app = fixture.app
        var offending: [String] = []
        func check(_ text: String?, _ where_: String) { if let text, text.lowercased().contains("skitch") { offending.append("\(where_): \(text)") } }
        func walk(_ menu: NSMenu) {
            check(menu.title, "menu")
            for item in menu.items { check(item.title, "item"); check(item.toolTip, "item tip"); if let sub = item.submenu { walk(sub) } }
        }
        guard let main = NSApp.mainMenu else { throw Failure(description: "Main menu missing") }
        walk(main)
        try expect(main.items.count > 3 && main.items[0].submenu?.items.contains { $0.title == "About OpenSnap" } == true, "App menu is About OpenSnap")
        func visit(_ view: NSView) {
            check(view.toolTip, "tooltip"); check(view.accessibilityLabel(), "accessibility label"); check(view.accessibilityHelp(), "accessibility help")
            check((view as? NSTextField)?.stringValue, "text"); check((view as? NSButton)?.title, "button")
            for child in view.subviews { visit(child) }
        }
        check(app.window.title, "window title")
        if let content = app.window.contentView { visit(content) }
        try expect(offending.isEmpty, "Retired product name in: \(offending.prefix(5))")
    }
}
#endif
