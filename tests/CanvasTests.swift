// Executable regression suite, deliberately gated to avoid an App.swift @main conflict.
// Run (excluding App.swift):
// swiftc -D CANVAS_TESTS -target arm64-apple-macosx13.0 Sources/LegacySkitch.swift Sources/LegacyBridge.swift Sources/DocumentModel.swift Sources/Canvas.swift tests/CanvasTests.swift -o /tmp/skitch-redux-canvas-tests
// /tmp/skitch-redux-canvas-tests
// Fixture-only check without windows/captures: /tmp/skitch-redux-canvas-tests --fixture-only
// Full suite without the optional capture: /tmp/skitch-redux-canvas-tests --skip-visual-proof
//
// Fidelity checklist: vectors/text/zoom/crop/background transforms, independent erased
// line and freehand fragments, raster pixel erasing, text above shapes/protected from
// eraser, grouping/layer order/clipboard/undo, Command-select and Shift/Option shapes.
// Remaining original-engine gaps: vector Boolean fills and filled-shape splitting,
// exact ellipse arcs after splitting (sampled outlines), pressure-sensitive tablet
// strokes, Option-polygon creation, original adaptive text outline/font panel, original
// generic SVG arcs, and original smoothing/arrow/shadow metrics. These tests do
// not assert full visual/behavioral equivalence to the original 32-bit drawing engine.

#if CANVAS_TESTS
import AppKit
import CoreGraphics

private final class CanvasTestDrag: NSObject, NSDraggingInfo {
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

@main
struct CanvasTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func pixel(_ canvas: CanvasView, _ x: Int, _ y: Int) throws -> NSColor {
        guard let bitmap = SketchRenderer.bitmap(document: canvas.document),
              let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw Failure(description: "Cannot sample rendered pixel")
        }
        return color
    }
    static func canvas(_ size: NSSize = NSSize(width: 100, height: 80)) -> CanvasView {
        let canvas = CanvasView(frame: .zero)
        canvas.newBlank(size: size)
        canvas.editingUndoManager.removeAllActions()
        canvas.shadowed = false
        return canvas
    }
    static func rectangle(_ rect: CGRect, color: NSColor = .red, filled: Bool = true) -> SketchElement {
        var element = SketchElement(kind: .rectangle)
        element.rect = rect; element.color = SketchColor(color); element.strokeWidth = 2; element.filled = filled
        return element
    }
    static func mouse(_ view: CanvasView, _ kind: NSEvent.EventType, _ point: CGPoint,
                      flags: NSEvent.ModifierFlags = [], clicks: Int = 1) throws -> NSEvent {
        let location = view.convert(CGPoint(x: point.x * view.zoom, y: point.y * view.zoom), to: nil)
        guard let event = NSEvent.mouseEvent(with: kind, location: location, modifierFlags: flags,
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 1, clickCount: clicks, pressure: 1) else { throw Failure(description: "Mouse event allocation") }
        return event
    }
    static func drag(_ view: CanvasView, from start: CGPoint, to end: CGPoint,
                     flags: NSEvent.ModifierFlags = []) throws {
        view.mouseDown(with: try mouse(view, .leftMouseDown, start, flags: flags))
        view.mouseDragged(with: try mouse(view, .leftMouseDragged, end, flags: flags))
        view.mouseUp(with: try mouse(view, .leftMouseUp, end, flags: flags))
    }
    static func host(_ canvas: CanvasView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.documentView = canvas
        window.contentView = scroll
        return window
    }
    static func main() {
        _ = NSApplication.shared
        let tests: [(String, () throws -> Void)] = [
            ("render orientation, alpha and zoom", render),
            ("crop background pixels and editable coordinates", crop),
            ("serialization and rejection without mutation", serialization),
            ("undo/redo, grouping, layers and style", history),
            ("rotate, flip and resize preserve vectors/pixels", transforms),
            ("PNG JPEG TIFF BMP PDF export", exports),
            ("flood fill stays inside an enclosure", fill),
            ("eraser splits vectors and protects text/photos", eraser),
            ("eraser clears actual fill pixels", pixelEraser),
            ("native mouse create/move/resize and modifiers", mouseInteraction),
            ("native brush dot, freehand and keyboard delete", brushAndKeyboard),
            ("native text edit, doubleclick and text undo", textEditing),
            ("clipboard editable selection and image paste", clipboard),
            ("editable cubic paths, font flags and old version-1 fields", paths),
            ("original firstlaunch import stays editable", originalImport),
            ("native image/document drag acceptance", drop),
            ("pending typing dirty notifications, recovery snapshots and active undo", pendingTextRecovery),
            ("pending text deletion/cancel recovery", pendingTextDeletion),
            ("canvas shortcuts respect annotation and name-field focus", shortcutFocus),
            ("document-drop callback preserves pending editor and history", pendingDocumentDrop),
            ("text-only font/outline changes preserve colors, shapes and wrap width", textStyleSelection),
            ("text-only style safely commits pending typing with separate undo", pendingTextStyle),
            ("native canvas visual proof", visualProof)
        ]
        let selectedTests = tests.filter { name, _ in
            if CommandLine.arguments.contains("--fixture-only") { return name == "original firstlaunch import stays editable" }
            return !CommandLine.arguments.contains("--skip-visual-proof") || name != "native canvas visual proof"
        }
        var failures = 0
        for (name, test) in selectedTests {
            do { try autoreleasepool { try test() }; print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(selectedTests.count - failures)/\(selectedTests.count) canvas tests passed")
        if failures > 0 { exit(1) }
    }
    static func render() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 5, width: 25, height: 15))]
        let top = try pixel(c, 20, 10), bottom = try pixel(c, 20, 70)
        try expect(top.redComponent > 0.9 && top.greenComponent < 0.1, "Top-left model pixel must be red")
        try expect(bottom.greenComponent > 0.9, "Bottom pixel must stay white")
        let before = c.imageData(format: "png")
        c.setZoom(2.5)
        try expect(c.frame.size == NSSize(width: 250, height: 200), "Scrollable zoomed frame")
        try expect(c.canvasSize == NSSize(width: 100, height: 80), "Model dimensions remain unchanged")
        try expect(c.imageData(format: "png") == before, "Zoom cannot alter export")
        c.setBackgroundColor(.clear)
        try expect(try pixel(c, 90, 60).alphaComponent < 0.01, "Transparent background")
        try expect(c.renderedImage().size == c.canvasSize, "Rendered image uses document pixels")
    }
    static func crop() throws {
        let c = canvas()
        let bitmap = SketchRenderer.bitmap(size: c.canvasSize) {
            NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 100, height: 80).fill()
            NSColor.green.setFill(); CGRect(x: 20, y: 10, width: 30, height: 20).fill()
        }!
        let image = NSImage(size: c.canvasSize); image.addRepresentation(bitmap)
        c.setBackground(image)
        let kept = rectangle(CGRect(x: 25, y: 15, width: 8, height: 8))
        c.document.elements = [kept, rectangle(CGRect(x: 80, y: 60, width: 5, height: 5))]
        let before = c.document
        c.cropRect = CGRect(x: 20, y: 10, width: 30, height: 20)
        c.cropSelection()
        try expect(c.canvasSize == NSSize(width: 30, height: 20), "Crop size")
        try expect(c.document.elements.count == 1 && c.document.elements[0].kind == .rectangle, "Keep editable surviving shape")
        try expect(c.document.elements[0].bounds.origin == CGPoint(x: 5, y: 5), "Translate annotations")
        let color = try pixel(c, 1, 1)
        try expect(color.greenComponent > 0.9 && color.blueComponent < 0.1, "Crop actual background, not stretch it")
        c.undo(); try expect(c.document == before, "Undo crop restores background, size and annotations")
        c.redo(); try expect(c.canvasSize.width == 30, "Redo crop")
    }
    static func serialization() throws {
        let c = canvas()
        var text = SketchElement(kind: .text)
        text.text = "Editable outline"; text.rect = CGRect(x: 8, y: 8, width: 80, height: 40)
        text.shadowed = true
        c.document.elements = [rectangle(CGRect(x: 4, y: 4, width: 20, height: 20)), text]
        c.selectAll(); c.groupSelection(); c.rotate(clockwise: true)
        let data = try c.documentData()
        try expect(String(data: data, encoding: .utf8)!.contains(SketchDocument.formatIdentifier), "Explicit distinct format marker")
        let loaded = canvas(); try loaded.loadDocument(data: data)
        try expect(loaded.document == c.document, "Editable model roundtrip")
        try expect(loaded.imageData(format: "png") == c.imageData(format: "png"), "Roundtrip render parity")
        try expect(!loaded.editingUndoManager.canUndo, "Opening establishes a fresh history")
        var invalid = c.document; invalid.version = 99
        let invalidData = try JSONEncoder().encode(invalid)
        do { try loaded.loadDocument(data: invalidData); throw Failure(description: "Future format should fail") }
        catch SketchDocumentError.unsupportedVersion { }
        try expect(loaded.document == c.document, "Invalid load must leave document unchanged")
        invalid.version = 1; invalid.size = NSSize(width: -2, height: 20)
        do { _ = try invalid.encoded(); throw Failure(description: "Invalid size should fail") }
        catch SketchDocumentError.invalidDocument { }
    }
    static func history() throws {
        let c = canvas()
        let a = rectangle(CGRect(x: 1, y: 1, width: 30, height: 30))
        let b = rectangle(CGRect(x: 10, y: 10, width: 30, height: 30), color: .blue)
        c.document.elements = [a, b]; c.selectAll()
        var changes = 0; c.onChange = { changes += 1 }
        c.groupSelection()
        try expect(c.document.elements[0].groupID != nil && c.document.elements[0].groupID == c.document.elements[1].groupID, "Group saved")
        c.undo(); try expect(c.document.elements[0].groupID == nil, "Undo grouping")
        c.redo(); c.ungroupSelection()
        try expect(c.document.elements.allSatisfy { $0.groupID == nil }, "Ungroup")
        c.selection = [a.id]; c.bringSelectionToFront()
        try expect(c.document.elements.last?.id == a.id, "Layer front")
        c.sendSelectionToBack(); try expect(c.document.elements.first?.id == a.id, "Layer back")
        c.strokeColor = .green; c.strokeWidth = 9; c.filled = false; c.applyStyleToSelection()
        try expect(c.document.elements[0].strokeWidth == 9 && !c.document.elements[0].filled, "Style edit")
        let before = c.document
        c.duplicateSelection(); try expect(c.document.elements.count == 3, "Duplicate")
        c.undo(); try expect(c.document == before, "Undo duplicate")
        c.redo(); c.deleteSelection(); try expect(c.document.elements.count == 2, "Delete duplicate")
        c.undo(); try expect(c.document.elements.count == 3, "Undo delete")
        try expect(changes >= 10, "Edits and history notify parent")
    }
    static func transforms() throws {
        let c = canvas(NSSize(width: 60, height: 40))
        let bg = SketchRenderer.bitmap(size: c.canvasSize) {
            NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 60, height: 40).fill()
            NSColor.green.setFill(); CGRect(x: 0, y: 0, width: 15, height: 12).fill()
        }!
        let image = NSImage(size: c.canvasSize); image.addRepresentation(bg); c.setBackground(image)
        c.document.elements = [rectangle(CGRect(x: 20, y: 10, width: 10, height: 8))]
        let initial = c.document
        c.rotate(clockwise: true)
        try expect(c.canvasSize == NSSize(width: 40, height: 60), "Rotate swaps dimensions")
        try expect(c.document.elements[0].bounds == CGRect(x: 22, y: 20, width: 8, height: 10), "Rotate editable geometry")
        try expect(try pixel(c, 35, 5).greenComponent > 0.9, "Rotate background orientation")
        c.undo(); try expect(c.document == initial, "Undo exact rotate")
        c.flip(horizontal: true)
        try expect(c.document.elements[0].bounds.minX == 30, "Horizontal vector flip")
        try expect(try pixel(c, 55, 5).greenComponent > 0.9, "Horizontal background flip")
        c.undo(); c.flip(horizontal: false)
        try expect(try pixel(c, 5, 35).greenComponent > 0.9, "Vertical background flip")
        c.undo(); c.resizeCanvas(to: NSSize(width: 80, height: 50))
        try expect(c.document.elements[0] == initial.elements[0], "Canvas resize does not rescale vectors")
        try expect(try pixel(c, 5, 5).greenComponent > 0.9, "Resize preserves old background pixel positions")
    }
    static func exports() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))]
        for format in ["png", "JPEG", "tiff", "bmp"] {
            guard let data = c.imageData(format: format), let bitmap = NSBitmapImageRep(data: data) else {
                throw Failure(description: "\(format) must decode")
            }
            try expect(bitmap.pixelsWide == 100 && bitmap.pixelsHigh == 80, "\(format) dimensions")
            let color = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
            try expect(color.redComponent > 0.8 && color.greenComponent < 0.2, "\(format) actual drawing pixels")
        }
        let pdf = c.imageData(format: "pdf")!
        let provider = CGDataProvider(data: pdf as CFData)!
        let doc = CGPDFDocument(provider)!
        try expect(doc.numberOfPages == 1 && doc.page(at: 1)!.getBoxRect(.mediaBox).size == c.canvasSize, "Real PDF page")
        try expect(c.imageData(format: "skitch") == nil, "Unsupported original format must not masquerade as image export")
        c.setBackgroundColor(.clear)
        let jpeg = NSBitmapImageRep(data: c.imageData(format: "jpg")!)!
        try expect(jpeg.colorAt(x: 90, y: 60)!.usingColorSpace(.deviceRGB)!.redComponent > 0.95, "JPEG alpha composites white")
        let original = c.imageData(format: "png")!
        c.flatten()
        try expect(c.document.elements.isEmpty && c.imageData(format: "png") == original, "Flatten preserves composite pixels")
        c.undo(); try expect(c.document.elements.count == 1, "Flatten undo restores editable vectors")
    }
    static func fill() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 15, y: 15, width: 40, height: 30), color: .black, filled: false)]
        c.strokeColor = .green; c.floodFill(at: CGPoint(x: 30, y: 30))
        try expect(c.document.elements.count == 2, "Fill adds independent pixels while preserving shape")
        let inside = try pixel(c, 30, 30), outside = try pixel(c, 80, 60)
        try expect(inside.greenComponent > 0.9 && inside.redComponent < 0.1, "Fill chosen region")
        try expect(outside.redComponent > 0.9, "Fill cannot leak outside the closed shape")
        try expect(c.document.elements[0].groupID != nil && c.document.elements[0].groupID == c.document.elements[1].groupID,
                   "Paint fill glues contacting shape to fill")
        c.undo(); try expect(c.document.elements.count == 1, "Fill undo")
    }
    static func eraser() throws {
        let c = canvas()
        c.setBackgroundColor(.blue)
        var line = SketchElement(kind: .line)
        line.points = [CGPoint(x: 10, y: 30), CGPoint(x: 90, y: 30)]; line.color = SketchColor(.red); line.strokeWidth = 4
        var text = SketchElement(kind: .text)
        text.text = "Text"; text.rect = CGRect(x: 10, y: 45, width: 80, height: 30)
        c.document.elements = [line, text]
        let before = c.document
        c.eraseStroke(points: [CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 70)], width: 10)
        let fragments = c.document.elements.filter { $0.kind == .line }
        try expect(fragments.count == 2 && fragments[0].id != fragments[1].id, "Cut line into two editable independent paths")
        try expect(fragments.allSatisfy { $0.groupID == nil && $0.imagePNG == nil }, "Fragments stay vectors")
        try expect(c.document.elements.first { $0.id == text.id } == text, "Eraser leaves text intact")
        try expect(try pixel(c, 50, 30).blueComponent > 0.9, "Erase gap reveals unchanged background")
        c.undo(); try expect(c.document == before, "Undo eraser restores exact editable objects")
        var brush = line; brush.kind = .brush
        brush.points = [CGPoint(x: 5, y: 30), CGPoint(x: 40, y: 30), CGPoint(x: 80, y: 30)]
        c.document.elements = [brush]
        c.eraseStroke(points: [CGPoint(x: 50, y: 30)], width: 12)
        try expect(c.document.elements.count == 2 && c.document.elements.allSatisfy { $0.kind == .brush }, "Freehand splits independently")
    }
    static func pixelEraser() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 70, height: 50))]
        c.eraseStroke(points: [CGPoint(x: 40, y: 15), CGPoint(x: 40, y: 55)], width: 12)
        try expect(c.document.elements.count == 1 && c.document.elements[0].kind == .raster, "Only touched filled area rasterizes")
        let cleared = try pixel(c, 40, 30), retained = try pixel(c, 20, 30)
        try expect(cleared.greenComponent > 0.9, "Cleared actual pixels")
        try expect(retained.redComponent > 0.9 && retained.greenComponent < 0.1, "Un-erased portion remains")
        c.setBackgroundColor(.clear)
        try expect(try pixel(c, 40, 30).alphaComponent < 0.01, "Eraser did not fake clearing with white ink")
    }
    static func mouseInteraction() throws {
        let c = canvas(NSSize(width: 200, height: 150)); let window = host(c); defer { window.close() }
        c.tool = .rectangle; c.filled = true; c.zoom = 2
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 50, y: 45), flags: [.shift, .option])
        try expect(c.document.elements.count == 1, "Native drag creates shape")
        let rect = c.document.elements[0].bounds
        try expect(rect == CGRect(x: 10, y: 10, width: 40, height: 40), "Option center plus Shift square independent of zoom")
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 40, y: 40), flags: [.command])
        try expect(c.document.elements[0].bounds.origin == CGPoint(x: 20, y: 20), "Command temporarily selects/moves from drawing tool")
        c.tool = .select
        try drag(c, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 80, y: 75))
        try expect(c.document.elements[0].bounds.size == NSSize(width: 60, height: 55), "Native resize handles")
        c.undo(); try expect(c.document.elements[0].bounds == CGRect(x: 20, y: 20, width: 40, height: 40), "Resize gesture is one undo")
        c.tool = .line
        try drag(c, from: CGPoint(x: 100, y: 30), to: CGPoint(x: 140, y: 55), flags: [.shift])
        let points = c.document.elements.last!.points
        try expect(abs((points[1].x - points[0].x) - (points[1].y - points[0].y)) < 0.001, "Shift constrains line to 45 degrees")
    }
    static func brushAndKeyboard() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        c.tool = .brush; c.strokeWidth = 10; c.strokeColor = .red
        try drag(c, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20))
        try expect(try pixel(c, 20, 20).greenComponent < 0.1, "Click-only brush creates actual dot")
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 70, y: 30))
        try expect(c.document.elements.last?.kind == .brush, "Native freehand drawing")
        c.tool = .brush
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 40, y: 30), flags: [.option]))
        try expect(c.strokeColor.usingColorSpace(.deviceRGB)!.redComponent > 0.9, "Option brush eyedropper")
        c.selectAll()
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51)!
        c.keyDown(with: delete)
        try expect(c.document.elements.isEmpty, "Keyboard deletion")
        c.undo(); try expect(c.document.elements.count == 2, "Undo keyboard deletion")
    }
    static func textEditing() throws {
        let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
        c.tool = .text; c.shadowed = true
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 15, y: 15)))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Native text editor") }
        try expect(editor.undoManager !== c.editingUndoManager, "Typing has independent native undo history")
        editor.insertText("Native text", replacementRange: NSRange(location: 0, length: 0))
        _ = c.renderedImage() // Commit before export.
        try expect(c.document.elements.count == 1 && c.document.elements[0].text == "Native text", "Text commit")
        try expect(c.document.elements[0].fontSize == 24 && c.document.elements[0].shadowed, "Text default font and shadow")
        c.tool = .select
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20), clicks: 2))
        let edit = c.subviews.compactMap { $0 as? NSTextView }.first!
        edit.string = "Revised text"; _ = try c.documentData()
        try expect(c.document.elements[0].text == "Revised text", "Doubleclick edits existing text")
        c.undo(); try expect(c.document.elements[0].text == "Native text", "Text edit undo")
        c.undo(); try expect(c.document.elements.isEmpty, "Initial text creation is one undo")
    }
    static func clipboard() throws {
        let board = NSPasteboard.general
        let original: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        defer {
            board.clearContents()
            let items = original.map { data -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type, bytes) in data { item.setData(bytes, forType: type) }; return item
            }
            board.writeObjects(items)
        }
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))]
        c.selectAll(); c.copySelection(); c.paste()
        try expect(c.document.elements.count == 2 && c.document.elements[0].id != c.document.elements[1].id, "Editable clipboard paste assigns new identity")
        try expect(c.document.elements[1].kind == .rectangle, "Clipboard keeps shape editable")
        c.undo(); try expect(c.document.elements.count == 1, "Clipboard paste undo")
        let png = c.imageData(format: "png")!
        board.clearContents(); board.setData(png, forType: .png)
        c.paste()
        try expect(c.document.elements.count == 2 && c.document.elements.last?.kind == .raster, "External PNG paste")
        c.selection.removeAll(); c.copySelection(); c.paste()
        try expect(c.document.elements.count == 3 && c.document.elements.last?.kind == .raster,
                   "Copy without a selection includes the whole composite/background as an image")
    }
    static func paths() throws {
        let c = canvas()
        var path = SketchElement(kind: .path)
        path.pathCommands = [.move(to: CGPoint(x: 10, y: 10)),
            .cubic(control1: CGPoint(x: 20, y: 0), control2: CGPoint(x: 40, y: 0), to: CGPoint(x: 50, y: 10)),
            .line(to: CGPoint(x: 50, y: 50)), .line(to: CGPoint(x: 10, y: 50)), .close]
        path.filled = true; path.strokeWidth = 0; path.color = SketchColor(.red)
        c.document.elements = [path]
        try expect(path.localBounds.width == 40 && path.localBounds.minY < 10, "Native cubic tight bounds")
        try expect(try pixel(c, 30, 30).greenComponent < 0.1, "Filled native path renders")
        let loaded = canvas(); try loaded.loadDocument(data: c.documentData())
        try expect(loaded.document.elements[0].pathCommands == path.pathCommands, "Cubic control points survive save")
        let window = host(c); defer { window.close() }
        c.tool = .select
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 35, y: 35))
        try expect(c.document.elements[0].transform.tx == 5 && c.document.elements[0].kind == .path, "Path hit testing and movement stay editable")
        c.undo(); c.rotate(clockwise: true)
        try expect(c.document.elements[0].pathCommands == path.pathCommands, "Path transform does not flatten curves")
        var text = SketchElement(kind: .text)
        text.rect = CGRect(x: 10, y: 10, width: 90, height: 50); text.text = "Font"
        text.fontName = "Courier-Bold"; text.outlined = false
        c.document.elements = [text]
        let data = try c.documentData()
        try expect(try SketchDocument.decode(data).elements[0].fontName == "Courier-Bold", "Font retained")
        let before = c.imageData(format: "png")
        c.document.elements[0].outlined = true
        try expect(c.imageData(format: "png") != before, "Outline flag actually changes glyph rendering")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var elements = json["elements"] as! [[String: Any]]
        elements[0].removeValue(forKey: "fontName"); elements[0].removeValue(forKey: "outlined")
        elements[0].removeValue(forKey: "pathCommands"); json["elements"] = elements
        let old = try SketchDocument.decode(JSONSerialization.data(withJSONObject: json))
        try expect(old.elements[0].fontName == "Helvetica-Bold" && old.elements[0].outlined, "Defaults decode pre-path version-1 files")
        text.fontSize = 12
        c.document.elements = [text]
        try expect(try SketchDocument.decode(c.documentData()).elements[0].fontSize == 12,
                   "Historical typography survives import; new tool text minimum remains 18")
    }
    static func originalImport() throws {
        let url = URL(fileURLWithPath: "original/Skitch.app/Contents/Resources/firstlaunch.skitch")
        let original = try LegacySkitch.read(url)
        try expect(original.paths.count == 3 && original.texts.count == 1, "Original fixture must contain exactly three paths and one text")
        try expect(original.texts[0].lines.count == 3 && original.texts[0].content == "Snap\nyour\nscreen",
                   "Original fixture must retain all three text lines")
        let converted = try LegacyBridge.convert(original)
        let importedPaths = converted.elements.filter { $0.kind == .path }
        let importedTexts = converted.elements.filter { $0.kind == .text }
        try expect(importedPaths.count == 3 && importedTexts.count == 1, "Bridge preserves exactly three editable paths and one text")
        try expect(importedPaths.allSatisfy { $0.filled && $0.strokeWidth == 0 }, "Filled legacy paths accept their original zero stroke width")
        for (native, legacy) in zip(importedPaths, original.paths) {
            try expect(native.pathCommands == legacy.commands, "Every cubic/control coordinate is preserved without flattening")
        }
        try expect(importedTexts[0].text.components(separatedBy: "\n") == ["Snap", "your", "screen"], "Bridge preserves all three lines")
        try expect(importedTexts[0].fontName == original.texts[0].fontName &&
                   importedTexts[0].fontSize == original.texts[0].fontSize &&
                   importedTexts[0].outlined == original.texts[0].hasOutline &&
                   importedTexts[0].shadowed == original.texts[0].hasShadow, "Bridge preserves font and outline/shadow flags")
        _ = try converted.validated()
        let c = canvas(); try c.loadDocument(data: converted.encoded())
        try expect(c.document == converted, "Imported editable document roundtrip")
        try expect(c.imageData(format: "png") != nil, "Imported original renders and exports")
        let reloaded = try SketchDocument.decode(c.documentData())
        try expect(reloaded.elements.filter { $0.kind == .path }.count == 3 &&
                   reloaded.elements.filter { $0.kind == .text }.map(\.text) == ["Snap\nyour\nscreen"],
                   "Serialization and Canvas load preserve three paths, one text, three lines")
        print("Fixture verified: 3 editable paths, 1 text, 3 lines; filled path strokeWidth=0 accepted")
    }
    static func drop() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))]
        let image = c.imageData(format: "png")!
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setData(image, forType: .png)
        let drag = CanvasTestDrag(board: board)
        try expect(c.draggingEntered(drag) == .copy, "Image drag offered copy operation")
        try expect(c.prepareForDragOperation(drag) && c.performDragOperation(drag), "Native NSDraggingInfo destination accepts PNG")
        try expect(c.document.elements.last?.kind == .raster, "Dropped image becomes canvas content")
        c.undo(); try expect(c.document.elements.count == 1, "Drop is undoable")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("drawing.skitchredux")
        try c.documentData().write(to: file)
        board.clearContents(); board.writeObjects([file as NSURL])
        let loaded = canvas()
        let untouched = loaded.document
        try expect(loaded.draggingEntered(drag).isEmpty && !loaded.performDragOperation(drag),
                   "Document drop without a parent callback is rejected rather than loaded")
        var opened: [URL] = []
        loaded.onOpenDocument = { opened.append($0) }
        try expect(loaded.draggingEntered(drag) == .copy && loaded.performDragOperation(drag) && opened == [file],
                   "File-URL document drop is routed to the parent callback")
        try expect(loaded.document == untouched && !loaded.editingUndoManager.canUndo, "Document drop itself cannot replace model/history")
        let legacy = URL(fileURLWithPath: "original/Skitch.app/Contents/Resources/firstlaunch.skitch").standardizedFileURL
        board.clearContents(); board.writeObjects([legacy as NSURL])
        try expect(loaded.performDragOperation(drag) && opened.last == legacy && loaded.document == untouched,
                   "Original .skitch drops also route through parent open handling")
        let photo = directory.appendingPathComponent("image.png")
        try image.write(to: photo)
        board.clearContents(); board.writeObjects([photo as NSURL])
        try expect(loaded.performDragOperation(drag) && loaded.document.backgroundPNG != nil, "File-URL image becomes protected background")
        board.clearContents(); board.setString("not an image", forType: .string)
        try expect(c.draggingEntered(drag).isEmpty, "Unsupported drag is rejected")
    }
    static func pendingTextRecovery() throws {
        let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
        let original = c.document
        c.tool = .text
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 15, y: 15)))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Pending text editor") }
        try expect(!c.hasPendingTextChanges, "Empty new editor has no recoverable changes")
        try expect(try SketchDocument.decode(c.snapshotDocumentData()) == original, "Empty editor placeholder is not recovered")
        try expect(c.activeEditorUndoManager === editor.undoManager, "Parent can access the focused annotation typing history")
        var notifiedSnapshots: [SketchDocument] = []
        var notificationError: Error?
        c.onChange = {
            do { notifiedSnapshots.append(try SketchDocument.decode(c.snapshotDocumentData())) }
            catch { notificationError = error }
        }
        let typing = editor.undoManager!
        typing.groupsByEvent = false; typing.beginUndoGrouping()
        editor.insertText("Recover\nwhile typing", replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing(); typing.endUndoGrouping()
        try expect(notificationError == nil && notifiedSnapshots.last?.elements.last?.text == "Recover\nwhile typing",
                   "Real typing notifies dirty/recovery immediately, before committing")
        try expect(c.hasPendingTextChanges && c.document.elements[0].text.isEmpty, "Typing stays pending in the native editor")
        try expect(!c.editingUndoManager.canUndo && typing.canUndo, "Typing creates no document transaction")
        let caret = editor.selectedRange(), live = c.document, notifications = notifiedSnapshots.count
        let snapshot = try c.snapshotDocumentData()
        try expect(try SketchDocument.decode(snapshot).elements[0].text == editor.string, "Snapshot includes pending multiline content")
        try expect(try c.snapshotDocumentData() == snapshot, "Repeated recovery snapshots are stable")
        try expect(c.document == live && editor.superview === c && window.firstResponder === editor &&
                   editor.selectedRange() == caret && notifiedSnapshots.count == notifications && !c.editingUndoManager.canUndo,
                   "Snapshots do not commit, disturb focus/caret, notify, or add document undo")
        typing.undo()
        try expect(editor.string.isEmpty && !c.hasPendingTextChanges && window.firstResponder === editor,
                   "Active typing undo leaves editor active and reverts pending dirty state")
        try expect(try SketchDocument.decode(c.snapshotDocumentData()) == original, "Typing undo recovery excludes empty placeholder")
        typing.redo()
        try expect(c.hasPendingTextChanges && editor.string == "Recover\nwhile typing", "Active typing redo restores recovery content")
        let committed = try c.documentData()
        try expect(committed == snapshot && !c.hasPendingTextChanges && c.activeEditorUndoManager == nil,
                   "Explicit document save commits exactly the recovered model and closes the editor")
        c.undo(); try expect(c.document == original, "Committed annotation remains one document undo step")
    }
    static func pendingTextDeletion() throws {
        let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text)
        text.text = "Keep this annotation"; text.rect = CGRect(x: 15, y: 15, width: 270, height: 90)
        c.document.elements = [text]; c.tool = .select
        let original = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20), clicks: 2))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Existing text editor") }
        try expect(!c.hasPendingTextChanges && (try SketchDocument.decode(c.snapshotDocumentData())) == original,
                   "Opening unchanged text is not dirty and preserves its geometry")
        var changes = 0; c.onChange = { changes += 1 }
        editor.insertText("", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try expect(changes > 0 && c.hasPendingTextChanges, "Deleting text immediately signals pending changes")
        try expect(try SketchDocument.decode(c.snapshotDocumentData()).elements.isEmpty, "Recovery reflects pending annotation deletion")
        try expect(c.document == original && window.firstResponder === editor, "Pending deletion does not mutate the committed model")
        let beforeCancel = changes
        c.cancelOperation(nil)
        try expect(c.document == original && !c.hasPendingTextChanges && changes > beforeCancel,
                   "Cancel restores original text and notifies recovery to remove abandoned changes")
        try expect(!c.editingUndoManager.canUndo, "Cancel does not create a document undo entry")
    }
    static func shortcutFocus() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        let element = rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))
        c.document.elements = [element]; c.selection = [element.id]
        func command(_ key: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: 0)!
        }
        let name = NSTextField(frame: CGRect(x: 110, y: 10, width: 250, height: 35))
        name.font = .systemFont(ofSize: 20); name.stringValue = "Image name"
        window.contentView!.addSubview(name)
        try expect(window.makeFirstResponder(name), "Name field accepts focus")
        try expect(name.currentEditor() is NSTextView, "Name field uses a native NSTextView field editor")
        let before = c.document, selected = c.selection, fieldEditor = window.firstResponder
        for key in ["z", "a", "c", "v", "x", "d"] {
            try expect(!c.performKeyEquivalent(with: command(key)), "Canvas must not claim Command-\(key) in name field")
        }
        try expect(c.document == before && c.selection == selected && window.firstResponder === fieldEditor &&
                   name.stringValue == "Image name" && c.activeEditorUndoManager == nil,
                   "Name-field shortcuts leave canvas document, selection and focus unchanged")
        try expect(window.makeFirstResponder(c), "Canvas accepts focus")
        try expect(c.performKeyEquivalent(with: command("d")) && c.document.elements.count == 2,
                   "Canvas shortcut still works when canvas owns focus")
        c.tool = .text
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 65, y: 45)))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Annotation focus") }
        editor.insertText("Annotation", replacementRange: NSRange(location: 0, length: 0))
        let pending = try c.snapshotDocumentData(), model = c.document
        for key in ["z", "a", "c", "v", "x", "d"] {
            try expect(!c.performKeyEquivalent(with: command(key)), "Canvas must not claim Command-\(key) in annotation editor")
        }
        try expect(c.document == model && (try c.snapshotDocumentData()) == pending && window.firstResponder === editor,
                   "Annotation shortcuts are not converted into canvas transactions")
        try expect(c.activeEditorUndoManager === editor.undoManager, "Annotation focus exposes only its typing history")
        c.cancelOperation(nil)
        let detached = canvas(); detached.document.elements = [element]; detached.selection = [element.id]
        try expect(!detached.performKeyEquivalent(with: command("d")) && detached.document.elements.count == 1,
                   "A detached canvas cannot claim window shortcuts")
    }
    static func pendingDocumentDrop() throws {
        let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
        c.setBackgroundColor(.blue)
        let original = c.document, undoName = c.editingUndoManager.undoActionName
        c.tool = .text
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 15, y: 15)))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        editor.insertText("Unsaved draft", replacementRange: NSRange(location: 0, length: 0))
        let pending = try c.snapshotDocumentData(), model = c.document
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        // No file exists: the canvas must route the URL without reading/parsing it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".SKITCHREDUX")
        board.writeObjects([url as NSURL])
        let drag = CanvasTestDrag(board: board)
        var opened: [URL] = [], preservedAtCallback = false
        c.onOpenDocument = { received in
            opened.append(received)
            preservedAtCallback = c.hasPendingTextChanges && window.firstResponder === editor && c.document == model
        }
        try expect(c.draggingEntered(drag) == .copy && c.performDragOperation(drag) && opened == [url],
                   "Unsaved-document drop routes exactly one callback, including uppercase extension")
        try expect(preservedAtCallback && c.document == model && (try c.snapshotDocumentData()) == pending &&
                   window.firstResponder === editor && c.editingUndoManager.undoActionName == undoName,
                   "Parent can cancel opening without losing pending text, current model or undo history")
        c.cancelOperation(nil)
        try expect(c.document == original, "Canceled pending typing leaves original drawing intact after dropped-open cancellation")
        c.undo(); try expect(c.document.backgroundColor == .white, "Pre-drop document undo history remains usable")
    }
    static func textStyleSelection() throws {
        let c = canvas(NSSize(width: 700, height: 600))
        var text = SketchElement(kind: .text)
        text.text = "Blue annotation wraps within its existing width."
        text.rect = CGRect(x: 15, y: 15, width: 180, height: 26)
        text.color = SketchColor(.blue); text.strokeWidth = 3; text.filled = true; text.shadowed = true
        text.groupID = UUID(); text.transform = .translation(x: 4, y: 3)
        var unselected = text
        unselected.id = UUID(); unselected.text = "Unselected text"; unselected.fontName = "Menlo"
        unselected.rect = CGRect(x: 350, y: 30, width: 170, height: 80)
        let shape = rectangle(CGRect(x: 400, y: 200, width: 100, height: 80), color: .green)
        c.document.elements = [text, shape, unselected]; c.selection = [text.id, shape.id]
        let original = c.document, originalImage = c.imageData(format: "png")
        c.strokeColor = .red; c.strokeWidth = 35; c.filled = false; c.shadowed = false
        c.fontName = "Courier-Bold"; c.fontSize = 48; c.outlined = false
        var changes = 0; c.onChange = { changes += 1 }
        c.applyTextStyleToSelection()
        let updated = c.document.elements[0], styled = c.document
        var expected = text
        expected.fontName = "Courier-Bold"; expected.fontSize = 48; expected.outlined = false
        expected.rect.size.height = updated.rect.height
        try expect(updated == expected && updated.color == SketchColor(.blue),
                   "Font action changes only selected text typography/outline/reflow height; red pen does not recolor blue text")
        try expect(c.document.elements[1] == shape && c.document.elements[2] == unselected,
                   "Selected shapes and unselected text remain completely unchanged")
        let measured = (updated.text as NSString).boundingRect(
            with: NSSize(width: text.rect.width, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont(name: updated.fontName, size: updated.fontSize)!,
                         .paragraphStyle: SketchRenderer.textParagraphStyle])
        try expect(updated.rect.height > text.rect.height && updated.rect.height >= ceil(measured.height),
                   "Larger font expands text height enough for wrapped drawing")
        try expect(updated.rect.width == text.rect.width && updated.rect.origin == text.rect.origin && updated.transform == text.transform,
                   "Font reflow preserves wrap width, anchor and transform")
        try expect(c.imageData(format: "png") != originalImage && changes == 1, "Font/outline change redraws and notifies once")
        c.applyTextStyleToSelection()
        try expect(c.document == styled && changes == 1, "Repeated identical text style is not a new edit")
        c.undo(); try expect(c.document == original, "One undo restores exact typography, outline and text bounds")
        c.redo(); try expect(c.document == styled, "Redo restores text-only style")
        c.selection = [shape.id]
        c.editingUndoManager.removeAllActions(); let notifications = changes
        c.fontName = "Helvetica-Bold"; c.fontSize = 18; c.outlined = true
        c.applyTextStyleToSelection()
        try expect(c.document == styled && !c.editingUndoManager.canUndo && changes == notifications,
                   "Shape-only selection is a no-op for text style")
    }
    static func pendingTextStyle() throws {
        let c = canvas(NSSize(width: 300, height: 500)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text)
        text.text = "Original blue text"; text.color = SketchColor(.blue)
        text.rect = CGRect(x: 15, y: 15, width: 250, height: 70)
        text.shadowed = true; c.document.elements = [text]; c.tool = .select
        let original = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20), clicks: 2))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Pending font editor") }
        editor.insertText("Pending blue text\nkept during font change", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let committedTyping = try SketchDocument.decode(c.snapshotDocumentData())
        c.strokeColor = .red; c.shadowed = false; c.strokeWidth = 40
        c.fontName = "Courier-Bold"; c.fontSize = 40; c.outlined = false
        c.applyTextStyleToSelection()
        let styled = c.document
        try expect(editor.superview == nil && !c.hasPendingTextChanges && c.activeEditorUndoManager == nil,
                   "Font action safely commits and closes the pending native editor")
        try expect(styled.elements[0].text == "Pending blue text\nkept during font change" &&
                   styled.elements[0].fontName == "Courier-Bold" && styled.elements[0].fontSize == 40 && !styled.elements[0].outlined,
                   "Pending multiline text survives the new typography")
        try expect(styled.elements[0].color == text.color && styled.elements[0].shadowed == text.shadowed &&
                   styled.elements[0].strokeWidth == text.strokeWidth && styled.elements[0].rect.width == text.rect.width,
                   "Pending font action leaves blue color, shadow, pen width and wrap width intact")
        c.undo(); try expect(c.document == committedTyping, "Undo font action retains the committed pending text at its previous font")
        c.undo(); try expect(c.document == original, "Separate typing undo restores the pre-editor document")
        c.redo(); c.redo(); try expect(c.document == styled, "Redo typing then font preserves both edits")
    }
    static func visualProof() throws {
        let c = canvas(NSSize(width: 620, height: 400))
        var arrow = SketchElement(kind: .arrow)
        arrow.points = [CGPoint(x: 55, y: 70), CGPoint(x: 210, y: 110)]
        arrow.color = SketchColor(.systemRed); arrow.strokeWidth = 7; arrow.shadowed = true
        var ellipse = SketchElement(kind: .ellipse)
        ellipse.rect = CGRect(x: 330, y: 65, width: 210, height: 110)
        ellipse.color = SketchColor(.systemGreen); ellipse.strokeWidth = 6
        var text = SketchElement(kind: .text)
        text.rect = CGRect(x: 42, y: 285, width: 540, height: 80)
        text.text = "Editable native text\nOutlined with a shadow"; text.shadowed = true; text.fontSize = 24
        var brush = SketchElement(kind: .brush)
        brush.points = [CGPoint(x: 50, y: 235), CGPoint(x: 140, y: 215), CGPoint(x: 220, y: 245), CGPoint(x: 300, y: 225)]
        brush.color = SketchColor(.systemPurple); brush.strokeWidth = 10
        c.document.elements = [arrow, ellipse, rectangle(CGRect(x: 355, y: 210, width: 170, height: 45), color: .systemBlue), brush, text]
        c.eraseStroke(points: [CGPoint(x: 175, y: 220), CGPoint(x: 175, y: 260)], width: 16)
        c.selection = [ellipse.id]
        let window = host(c); defer { window.close() }
        window.setContentSize(c.canvasSize)
        c.displayIfNeeded()
        guard let screenshot = c.bitmapImageRepForCachingDisplay(in: c.bounds) else { throw Failure(description: "Native view capture") }
        c.cacheDisplay(in: c.bounds, to: screenshot)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skitch-redux-canvas-proof.png")
        try screenshot.representation(using: .png, properties: [:])!.write(to: url)
        print("Visual proof: \(url.path)")
    }
}
#endif
