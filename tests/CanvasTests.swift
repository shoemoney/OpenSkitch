// Executable regression suite, deliberately gated to avoid an App.swift @main conflict.
// Run (excluding App.swift):
// swiftc -D CANVAS_TESTS -target arm64-apple-macosx13.0 Sources/SVGPath.swift Sources/LegacyBridge.swift Sources/DocumentModel.swift Sources/VectorGeometry.swift Sources/StrokeFitting.swift Sources/ImageExport.swift Sources/Canvas.swift tests/CanvasTests.swift -o /tmp/opensnap-canvas-tests
// /tmp/opensnap-canvas-tests
// Fixture-only check without windows/captures: /tmp/opensnap-canvas-tests --fixture-only
// tools/test.py runs the live-view visual proof. Manual escape hatch without it: /tmp/opensnap-canvas-tests --skip-visual-proof
//
// Fidelity checklist: vectors/text/zoom/crop/background transforms, independent erased
// line and freehand fragments, raster pixel erasing, text above shapes/protected from
// eraser, grouping/layer order/clipboard/undo, Command-select and Shift/Option shapes.
// Recovered gestures: Control eraser (Command precedence/Fill exception), Space pan
// of snap and drawing together, Tab Pencil toggle, Option eyedropper/copy, Escape
// rollback, two-stage Wipe and white Wipe Snap, fixed-size Re-Snap and frame preview.
// Shift+Command eyedropper is not implemented: bundled help and recovered modifier
// dispatch establish Command cursor/Shift selection, rather than that color shortcut.
// Justype forwards printable canvas keys to native text input; original editor Escape
// commits/leaves editing. Explicit programmatic cancel still abandons pending text.
// Remaining original-engine gaps: exact Boolean tolerance/growth/inflection behavior,
// real tablet pressure and proximity hardware, Option-polygon creation, original
// adaptive text outline/font panel, generic SVG arcs, and original arrow/shadow
// metrics. Curve-fitting fixtures do not replace original-runtime comparisons. These tests do
// not assert full visual/behavioral equivalence to the original 32-bit drawing engine.

#if CANVAS_TESTS
import AppKit
import CoreGraphics

private final class CanvasTabletEvent: NSEvent {
    var inputType: NSEvent.EventType = .leftMouseDown
    var inputLocation: CGPoint = .zero
    var inputPressure: Float = 1
    var inputModifiers: NSEvent.ModifierFlags = []
    var entering = true
    var eraser = true
    override var type: NSEvent.EventType { inputType }
    override var locationInWindow: NSPoint { inputLocation }
    override var pressure: Float { inputPressure }
    override var subtype: NSEvent.EventSubtype { .tabletPoint }
    override var modifierFlags: NSEvent.ModifierFlags { inputModifiers }
    override var clickCount: Int { 1 }
    override var isEnteringProximity: Bool { entering }
    override var pointingDeviceType: NSEvent.PointingDeviceType { eraser ? .eraser : .pen }
}

private final class TextGripDragEvent: NSEvent {
    let movement: CGSize
    init(_ x: CGFloat, _ y: CGFloat) { movement = CGSize(width: x, height: y); super.init() }
    required init?(coder: NSCoder) { fatalError("Not an archived event") }
    override var type: NSEvent.EventType { .leftMouseDragged }
    override var deltaX: CGFloat { movement.width }
    override var deltaY: CGFloat { movement.height }
}

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
    /// A case that cannot run here (git-ignored original/ archive absent); reported as SKIP, never as a failure.
    struct Skip: Error, CustomStringConvertible { let description: String }
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
        let location = view.convert(CGPoint(x: point.x * view.displayScale.width, y: point.y * view.displayScale.height), to: nil)
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
    static func key(_ view: CanvasView, _ code: UInt16, type: NSEvent.EventType = .keyDown,
                    flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
        let characters = code == 49 ? " " : (code == 48 ? "\t" : (code == 53 ? "\u{1b}" : ""))
        guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code) else {
            throw Failure(description: "Key event allocation")
        }
        return event
    }
    static func backdrop(_ size: NSSize = NSSize(width: 100, height: 80)) -> NSImage {
        let bitmap = SketchRenderer.bitmap(size: size) {
            NSColor.blue.setFill(); CGRect(origin: .zero, size: size).fill()
            NSColor.green.setFill(); CGRect(x: 5, y: 5, width: size.width / 4, height: size.height / 4).fill()
        }!
        let image = NSImage(size: size); image.addRepresentation(bitmap); return image
    }
    static func main() {
        _ = NSApplication.shared
        let tests: [(String, () throws -> Void)] = [
            ("render orientation, alpha and zoom", render),
            ("crop background pixels and editable coordinates", crop),
            ("add shadow grows the canvas 27 x 27 with the picture at 14,6 in one undo", addShadow),
            ("border crop retains hidden raster and vectors across save and expansion", reframe),
            ("independent output sizing and coordinate mapping retain source pixels", outputSizing),
            ("viewport crop previews anchor to base and retain full source", viewportCropAnchoring),
            ("viewport width resize is one undo with prior history intact", viewportResizeHistory),
            ("viewport cancellation restores complete state and undo/redo branches", viewportCancellation),
            ("invalid viewport previews never mutate or commit a transaction", viewportInvalidPreviews),
            ("viewport begins after committing pending text as a separate edit", viewportPendingText),
            ("viewport rejects nested transactions and active drawing", viewportUnsafeBegin),
            ("document replacement and undo cancel pending viewport previews", viewportReplacement),
            ("normal and Actual presentation retain pixels vectors pan and history", presentationOutput),
            ("presentation sizing preserves pending text and validates before mutation", presentationPendingText),
            ("Actual edits keep normal undo output and normalized no-op equality", actualHistoryIsolation),
            ("pre-Actual undo restores normal history while presenting full source", actualPreexistingHistory),
            ("Actual geometry transforms retain source and normal output in history", actualTransformHistory),
            ("Actual native drag snapshots cancel and undo without mode leakage", actualNativeState),
            ("Actual pending text snapshots commit and cancel with normal history", actualPendingTextState),
            ("Actual saved snapshots and lifecycle guards preserve presentation", actualLifecycleGuards),
            ("viewport cancellation callback fires once on interruptions only", viewportCancellationCallback),
            ("serialization and rejection without mutation", serialization),
            ("undo/redo, grouping, layers and style", history),
            ("rotate, flip and resize preserve vectors/pixels", transforms),
            ("PNG JPEG TIFF BMP PDF export", exports),
            ("flood fill stays inside an enclosure", fill),
            ("vector fill ignores photo colors and preserves relative layers", vectorFillBackground),
            ("shadow fill recolors without replacing geometry or selection", shadowFill),
            ("translucent path fill blends alpha and Shift preserves groups", alphaFill),
            ("same-color fill merges editable paths without selecting them", matchingFill),
            ("Shift fill is visible above same-color overlapping paths", layeredShiftFill),
            ("mixed-style path fill preserves contacted annotations", mixedPathFill),
            ("vector eraser protects pasted photographs and text", protectedErase),
            ("Pencil commits fitted geometry without a release-only tail", fittedPencil),
            ("native tablet pressure and pen eraser precedence", tabletInput),
            ("Undo and Redo cancel active drawing gestures", gestureHistory),
            ("later matching-color fill retains alpha and Shift behavior", separatedColorFill),
            ("eraser splits vectors and protects text/photos", eraser),
            ("eraser preserves editable filled paths and holes", pixelEraser),
            ("native mouse create/move/resize and modifiers", mouseInteraction),
            ("native brush dot, freehand and keyboard delete", brushAndKeyboard),
            ("native text edit, doubleclick and text undo", textEditing),
            ("clipboard editable selection and image paste", clipboard),
            ("editable cubic paths, font flags and old version-1 fields", paths),
            ("native image/document drag acceptance", drop),
            ("pending typing dirty notifications, recovery snapshots and active undo", pendingTextRecovery),
            ("pending text deletion/cancel recovery", pendingTextDeletion),
            ("canvas shortcuts respect annotation and name-field focus", shortcutFocus),
            ("document-drop callback preserves pending editor and history", pendingDocumentDrop),
            ("text-only font changes fit natural width while preserving colors and shapes", textStyleSelection),
            ("text-only style safely commits pending typing with separate undo", pendingTextStyle),
            ("text style shadow changes preserve non-text artwork and separate typing Undo", textShadowStyle),
            ("Default Text Style restores face and effects while preserving mixed sizes", defaultTextStyle),
            ("text context routes Font without disrupting Control eraser", textContextStyle),
            ("text grip preserves typing focus and commits movement with one Undo", textGripEditing),
            ("recovered native text completion keys preserve pending edits and history", textCompletionKeys),
            ("recovered tapered arrow outline and Shift thresholds", originalArrowGeometry),
            ("arrow defaults temporary reversal release cancellation and one Undo", originalArrowGestures),
            ("natural text layout grows shrinks and preserves source geometry through Undo", naturalTextLayout),
            ("text grip retains transformed geometry through zoom snapshots and reopening", textGripGeometry),
            ("text grip cancel invalid deltas and new annotation preserve history", textGripCancellation),
            ("active text grip replaces stale selection chrome through move zoom commit and cancel", textGripSelectionChrome),
            ("live font conversion preserves mixed sizes traits effects and validates all items", liveTextFontConversion),
            ("live font panel changes retain typing grip recovery and combined Undo", pendingFontPanelStyle),
            ("Recovered text effects retain contrast thickness alpha and pending typing", originalTextEffects),
            ("empty text accepts live style and cancel preserves prior history", pendingEmptyFontStyle),
            ("Control eraser, secondary mouse and recovered modifier precedence", controlEraser),
            ("Space pans snap and drawing, preserves offscreen pixels and undo", spacePan),
            ("Tab Pencil toggle and Option eyedropper only notify UI", toolAndColorGestures),
            ("Option drag copies groups as one undoable edit", optionDragCopy),
            ("Escape restores gestures, selection, crop and existing undo/redo", gestureCancellation),
            ("two-stage Wipe and Wipe Snap preserve undo and white backdrop", wipeLifecycle),
            ("Wipe resets viewport rect when no snap remains", wipeResetsViewport),
            ("Re-Snap validates before mutation and fits retina background", resnap),
            ("frame preview retains annotation pixels and capture boundary only", framePreview),
            ("Justype focus, native typing/recovery/undo, Escape commit and pointer clamp", justype),
            ("Option key arms the Line polygon, release commits one element and one Undo step", linePolygon),
            ("shadows fall down-right on screen and in export", shadowDirection),
            ("text editor group shadow and grip chrome shadow fall downward", editorShadowDirection),
            ("native canvas visual proof", visualProof)
        ]
        let selectedTests = tests.filter { name, _ in
            if CommandLine.arguments.contains("--fixture-only") { return name == "original firstlaunch import stays editable" }
            return !CommandLine.arguments.contains("--skip-visual-proof") || name != "native canvas visual proof"
        }
        var failures = 0, skipped = 0
        for (name, test) in selectedTests {
            do { try autoreleasepool { try test() }; print("PASS \(name)") }
            catch let skip as Skip { skipped += 1; print("SKIP \(name): \(skip)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(selectedTests.count - failures - skipped)/\(selectedTests.count) canvas tests passed" + (skipped > 0 ? ", \(skipped) skipped" : ""))
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
    static func addShadow() throws {
        let c = canvas(NSSize(width: 100, height: 50))
        let blank = c.document
        c.addShadow()
        try expect(c.document == blank, "Add Shadow is a no-op without a snapshot")
        let bitmap = SketchRenderer.bitmap(size: c.canvasSize) { NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 100, height: 50).fill() }!
        let image = NSImage(size: c.canvasSize); image.addRepresentation(bitmap)
        c.setBackground(image)
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 8, height: 8))]
        let before = c.document
        c.addShadow()
        let after = c.document
        try expect(after.size == CGSize(width: 127, height: 77), "Canvas grows by 27 x 27, got \(after.size)")
        try expect(after.elements[0].bounds.origin == CGPoint(x: 24, y: 16), "Annotations follow the picture to (14,6)")
        let inside = try pixel(c, 14, 6), outside = try pixel(c, 13, 5)
        try expect(inside.blueComponent > 0.9 && inside.redComponent < 0.1, "Picture top-left lands at (14,6)")
        try expect(outside.redComponent > 0.5 || outside.blueComponent < 0.9, "Nothing blue above-left of (14,6)")
        let below = try pixel(c, 64, 62), above = try pixel(c, 64, 2)
        try expect(below.brightnessComponent < above.brightnessComponent - 0.15, "Shadow falls below the picture, not above it")
        let corner = try pixel(c, 120, 72), origin = try pixel(c, 1, 1)
        try expect(corner.brightnessComponent < origin.brightnessComponent, "Bottom-right is darker than top-left")
        c.undo(); try expect(c.document == before, "One Undo restores the pre-shadow document")
        c.redo(); try expect(c.document == after, "Redo reapplies the shadow")
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
        try expect(c.document.elements.count == 2 && c.document.elements[0].kind == .rectangle, "Keep hidden editable shapes as well as visible ones")
        try expect(c.document.elements[0].bounds.origin == CGPoint(x: 5, y: 5), "Translate annotations")
        let color = try pixel(c, 1, 1)
        try expect(color.greenComponent > 0.9 && color.blueComponent < 0.1, "Crop actual background, not stretch it")
        c.undo(); try expect(c.document == before, "Undo crop restores background, size and annotations")
        c.redo(); try expect(c.canvasSize.width == 30, "Redo crop")
    }
    static func reframe() throws {
        let c = canvas()
        let bitmap = SketchRenderer.bitmap(size: c.canvasSize) {
            NSColor.blue.setFill(); CGRect(origin: .zero, size: c.canvasSize).fill()
            NSColor.green.setFill(); CGRect(x: 20, y: 10, width: 30, height: 20).fill()
        }!
        let image = NSImage(size: c.canvasSize); image.addRepresentation(bitmap); c.setBackground(image)
        let hidden = rectangle(CGRect(x: 80, y: 60, width: 5, height: 5))
        c.document.elements = [hidden]; c.selection = [hidden.id]; c.editingUndoManager.removeAllActions()
        let original = c.document, originalImage = c.imageData(format: "png")
        try expect(c.reframe(to: CGRect(x: 20, y: 10, width: 30, height: 20)), "Border crop accepted")
        try expect(c.selection == [hidden.id] && c.document.elements.count == 1, "Hidden selection and object identity retained")
        let cropped = try c.documentData(), croppedDocument = c.document
        let restored = canvas(); try restored.loadDocument(data: cropped)
        try expect(restored.reframe(to: CGRect(x: -20, y: -10, width: 100, height: 80)), "Expand saved crop")
        try expect(restored.document.elements == original.elements && restored.imageData(format: "png") == originalImage,
                   "Crop/save/reopen/expand restores original photo pixels and vectors exactly")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Crop is one undo transaction")
        c.redo(); try expect(c.document == croppedDocument, "Redo restores hidden source crop")
        c.trimSnapAtCurrentEdges(); let trimmed = try c.documentData()
        let trimmedCanvas = canvas(); try trimmedCanvas.loadDocument(data: trimmed)
        _ = trimmedCanvas.reframe(to: CGRect(x: -20, y: -10, width: 100, height: 80))
        let color = try pixel(trimmedCanvas, 5, 5)
        try expect(color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9,
                   "Permanent snap trim leaves white space when expanded")
        try expect(trimmedCanvas.document.elements == original.elements, "Permanent snap trim keeps hidden annotations")
        c.undo(); _ = c.reframe(to: CGRect(x: -20, y: -10, width: 100, height: 80))
        try expect(c.imageData(format: "png") == originalImage, "Undo permanent trim recovers original hidden photo")
        for clockwise in [true, false] {
            let rotated = canvas(); try rotated.loadDocument(data: cropped)
            rotated.rotate(clockwise: clockwise)
            let full = canvas(); full.document = original; full.rotate(clockwise: clockwise)
            let origin = clockwise ? CGPoint(x: -50, y: -20) : CGPoint(x: -10, y: -50)
            _ = rotated.reframe(to: CGRect(origin: origin, size: CGSize(width: 80, height: 100)))
            try expect(rotated.document.elements == full.document.elements && rotated.imageData(format: "png") == full.imageData(format: "png"),
                       "Hidden snap and editable objects survive cropped quarter-turn and expansion")
        }
        for horizontal in [true, false] {
            let flipped = canvas(); try flipped.loadDocument(data: cropped)
            flipped.flip(horizontal: horizontal)
            let full = canvas(); full.document = original; full.flip(horizontal: horizontal)
            let origin = horizontal ? CGPoint(x: -50, y: -10) : CGPoint(x: -20, y: -50)
            _ = flipped.reframe(to: CGRect(origin: origin, size: CGSize(width: 100, height: 80)))
            try expect(flipped.document.elements == full.document.elements && flipped.imageData(format: "png") == full.imageData(format: "png"),
                       "Hidden snap and editable objects survive cropped flip and expansion")
        }
        let before = try c.documentData()
        try expect(!c.reframe(to: CGRect(x: CGFloat.infinity, y: 0, width: 2, height: 2)) &&
                   !c.reframe(to: CGRect(x: 0, y: 0, width: 0, height: 2)) &&
                   !c.reframe(to: CGRect(x: 0, y: 0, width: 16384, height: 16384)), "Reject invalid or excessive crop")
        try expect(try c.documentData() == before, "Invalid crop preserves all document state")
        let small = canvas(NSSize(width: 100, height: 80)); small.document.elements = [hidden]
        try expect(small.cropCanvas(to: NSSize(width: 140, height: 120), anchor: CGPoint(x: 0.5, y: 0.5)), "Centered border expansion")
        try expect(small.document.elements[0].bounds.origin == CGPoint(x: 100, y: 80), "Center expansion adds equal margins")
    }
    static func outputSizing() throws {
        let c = canvas(); c.setBackground(backdrop(c.canvasSize))
        let object = rectangle(CGRect(x: 20, y: 20, width: 60, height: 50))
        c.document.elements = [object]; c.selection = [object.id]; c.editingUndoManager.removeAllActions()
        let original = c.document
        try expect(c.resizeImage(to: CGSize(width: 50, height: 60)), "Independent output resize")
        try expect(c.canvasSize == original.size && c.document.elements == original.elements && c.document.backgroundPNG == original.backgroundPNG,
                   "Resize keeps source pixels and vector geometry untouched")
        try expect(c.outputSize == CGSize(width: 50, height: 60) && c.frame.size == c.outputSize, "Normal output and native canvas frame follow resize")
        let encoded = try c.documentData(), undoName = c.editingUndoManager.undoActionName
        let normal = NSBitmapImageRep(data: c.imageData(format: "png")!)!
        let full = NSBitmapImageRep(data: c.imageData(format: "png", originalSize: true)!)!
        try expect(normal.pixelsWide == 50 && normal.pixelsHigh == 60 && full.pixelsWide == 100 && full.pixelsHigh == 80,
                   "Normal and original-size exports use different sizes")
        try expect(try c.documentData() == encoded && c.selection == [object.id] && c.editingUndoManager.undoActionName == undoName,
                   "Original-size render does not change document, selection or undo")
        c.tool = .select; try drag(c, from: CGPoint(x: 50, y: 45), to: CGPoint(x: 60, y: 55))
        try expect(c.document.elements[0].bounds.origin == CGPoint(x: 30, y: 30), "Nonuniform native display maps mouse motion to document pixels: \(c.document.elements[0].bounds)")
        c.undo(); c.undo(); try expect(c.document == original, "Undo resize restores exact source geometry and output")
        c.redo(); try expect(c.outputSize == CGSize(width: 50, height: 60), "Redo output resize")
        c.crop(to: CGRect(x: 20, y: 10, width: 30, height: 20))
        try expect(c.outputSize == CGSize(width: 15, height: 15), "Cropping retains normal display density")
        let fractional = canvas(NSSize(width: 800, height: 600))
        _ = fractional.resizeImage(to: CGSize(width: 1600, height: 1200))
        _ = fractional.cropCanvas(to: CGSize(width: 399.5, height: 299.5), anchor: CGPoint(x: 0.5, y: 0.5), outputSize: CGSize(width: 799, height: 599))
        try expect(fractional.outputSize == CGSize(width: 799, height: 599) && fractional.canvasSize == CGSize(width: 399.5, height: 299.5),
                   "Odd output crop retains exact requested pixels and fractional source geometry")
        let saved = try c.documentData(), loaded = canvas(); try loaded.loadDocument(data: saved)
        try expect(loaded.outputSize == c.outputSize && loaded.document == c.document, "Output size persists with hidden source")
        loaded.setSnapToNormalSize(); try expect(loaded.outputSize == loaded.canvasSize, "Set Snap to Normal Size restores source pixel density")
        loaded.rotate(clockwise: true); try expect(loaded.outputSize == loaded.canvasSize, "Rotated normal size follows swapped axes")
    }
    // Retained raster extends beyond the visible canvas, with a nonzero source
    // offset, grouped vectors, text, selection and an unrelated crop overlay.
    static func viewportCanvas() throws -> CanvasView {
        let c = canvas(); c.setBackground(backdrop())
        var shape = rectangle(CGRect(x: 40, y: 35, width: 20, height: 15))
        var text = SketchElement(kind: .text)
        text.text = "Source"; text.rect = CGRect(x: 65, y: 5, width: 30, height: 30)
        shape.groupID = UUID(); text.groupID = shape.groupID
        c.document.elements = [shape, text]; c.selection = [shape.id]
        try expect(c.reframe(to: CGRect(x: 20, y: 10, width: 70, height: 60),
                             outputSize: CGSize(width: 35, height: 30)), "Retained viewport fixture")
        c.cropRect = CGRect(x: 3, y: 4, width: 40, height: 35)
        c.editingUndoManager.removeAllActions()
        return c
    }
    static func viewportCropAnchoring() throws {
        let c = try viewportCanvas(), original = c.document
        let saved = try c.snapshotDocumentData(), selected = c.selection, crop = c.cropRect
        let reference = canvas(); try reference.loadDocument(data: saved)
        reference.selection = selected; reference.cropRect = crop
        var dirty = 0; c.onChange = { dirty += 1 }
        try expect(c.beginViewportEdit(name: "Border Crop"), "Begin crop")
        let steps = [CGRect(x: 8, y: 5, width: 52, height: 40),
                     CGRect(x: -12, y: -6, width: 80, height: 65),
                     CGRect(x: 6, y: 3, width: 55.5, height: 44.5)]
        for rect in steps {
            let output = CGSize(width: ceil(rect.width * 2), height: ceil(rect.height * 2))
            try expect(c.previewViewportCrop(to: rect, outputSize: output), "Crop preview")
            try reference.loadDocument(data: saved)
            reference.selection = selected; reference.cropRect = crop
            try expect(reference.reframe(to: rect, outputSize: output), "Independent one-step reference")
            try expect(c.document == reference.document && c.snapshotDocumentData() == reference.snapshotDocumentData(),
                       "Each crop uses original raster offset/coordinates, never earlier preview translations")
            var elements = original.elements
            for index in elements.indices { elements[index].translate(x: -rect.minX, y: -rect.minY) }
            try expect(c.document.elements == elements && c.selection == selected && c.cropRect == nil &&
                       dirty == 0 && !c.editingUndoManager.canUndo, "Previews preserve IDs/groups and remain silent")
        }
        let committed = try c.snapshotDocumentData(), final = c.document
        c.endViewportEdit()
        try expect(dirty == 1 && c.editingUndoManager.undoActionName == "Border Crop", "One crop gesture notification/history")
        c.undo()
        try expect(c.document == original && c.snapshotDocumentData() == saved && c.selection == selected &&
                   c.cropRect == crop && !c.editingUndoManager.canUndo, "Undo restores complete crop base/source")
        c.redo()
        try expect(c.document == final && c.snapshotDocumentData() == committed && c.cropRect == nil,
                   "Redo restores exact last preview including source retention")
        let reopened = canvas(); try reopened.loadDocument(data: committed)
        try expect(reopened.reframe(to: CGRect(x: -26, y: -13, width: 100, height: 80),
                                    outputSize: CGSize(width: 100, height: 80)), "Expand final saved viewport")
        let full = canvas(); full.setBackground(backdrop()); full.document.elements = original.elements
        for index in full.document.elements.indices { full.document.elements[index].translate(x: 20, y: 10) }
        try expect(reopened.document.elements == full.document.elements && reopened.imageData(format: "png") == full.imageData(format: "png"),
                   "Saved crop gesture retains hidden photo pixels and editable graphics")
    }
    static func viewportResizeHistory() throws {
        let c = try viewportCanvas()
        c.setBackgroundColor(.clear); let prior = c.document
        try expect(c.resizeImage(to: CGSize(width: 45, height: 30)), "Prior resize")
        let original = c.document, saved = try c.snapshotDocumentData(), crop = c.cropRect, selected = c.selection
        var dirty = 0; c.onChange = { dirty += 1 }
        try expect(c.beginViewportEdit(name: "Resize Window"), "Begin width gesture")
        for width in [40.2, 25, 50.1] {
            try expect(c.previewViewportResize(to: CGSize(width: width, height: 30)), "Width preview")
            try expect(c.outputSize.width == ceil(width) && c.outputSize.height == 30 &&
                       c.document.size == original.size && c.document.backgroundPNG == original.backgroundPNG &&
                       c.document.elements == original.elements && c.selection == selected && c.cropRect == crop &&
                       dirty == 0 && c.editingUndoManager.undoActionName == "Resize Image", "Silent integral output-only preview")
        }
        let resized = c.document, resizedData = try c.snapshotDocumentData()
        c.endViewportEdit(); c.endViewportEdit()
        try expect(dirty == 1 && c.editingUndoManager.undoActionName == "Resize Window", "One width gesture edit")
        c.undo(); try expect(c.document == original && c.snapshotDocumentData() == saved, "One Undo restores base")
        c.undo(); try expect(c.document == prior, "Earlier output resize remains undoable")
        c.redo(); try expect(c.document == original, "Prior resize redo")
        c.redo(); try expect(c.document == resized && c.snapshotDocumentData() == resizedData, "Whole gesture redo")
        c.undo(); c.undo(); c.undo()
        try expect(c.document.backgroundColor == .white && !c.editingUndoManager.canUndo, "All earlier edits survive gesture")
    }
    static func viewportCancellation() throws {
        let c = try viewportCanvas()
        c.setBackgroundColor(.clear); _ = c.resizeImage(to: CGSize(width: 45, height: 30)); c.undo()
        let saved = try c.snapshotDocumentData(), original = c.document, selected = c.selection, crop = c.cropRect
        let undoName = c.editingUndoManager.undoActionName, redoName = c.editingUndoManager.redoActionName
        var dirty = 0; c.onChange = { dirty += 1 }
        for keyboardCancel in [false, true] {
            try expect(c.beginViewportEdit(name: "Cancelled Border"), "Begin cancelled gesture")
            try expect(c.previewViewportCrop(to: CGRect(x: 10, y: 8, width: 40, height: 35),
                                             outputSize: CGSize(width: 80, height: 70)), "Cancelled crop preview")
            try expect(c.previewViewportResize(to: CGSize(width: 21, height: 19)), "Switch to resize anchored at original state")
            try expect(c.document.elements == original.elements && c.document.size == original.size && c.cropRect == crop,
                       "Resize after crop also uses base state")
            if keyboardCancel { c.cancelOperation(nil) } else { c.endViewportEdit(cancelled: true) }
            try expect(c.document == original && c.snapshotDocumentData() == saved && c.selection == selected &&
                       c.cropRect == crop && dirty == 0, "Cancel exactly restores document/pan/selection/crop silently")
            try expect(c.editingUndoManager.canUndo && c.editingUndoManager.canRedo &&
                       c.editingUndoManager.undoActionName == undoName && c.editingUndoManager.redoActionName == redoName,
                       "Cancel preserves existing undo and redo branches")
        }
        c.redo(); try expect(c.outputSize == CGSize(width: 45, height: 30), "Existing redo remains usable")
        c.undo(); c.undo(); try expect(c.document.backgroundColor == .white, "Existing undo remains usable")
    }
    static func viewportInvalidPreviews() throws {
        let c = try viewportCanvas(), original = c.document, saved = try c.snapshotDocumentData()
        let selected = c.selection, crop = c.cropRect
        var dirty = 0; c.onChange = { dirty += 1 }
        try expect(!c.previewViewportResize(to: CGSize(width: 30, height: 20)) &&
                   !c.previewViewportCrop(to: CGRect(x: 1, y: 1, width: 30, height: 20),
                                          outputSize: CGSize(width: 30, height: 20)), "Preview never implicitly begins a transaction")
        let invalidSizes = [CGSize(width: CGFloat.nan, height: 20), CGSize(width: 20, height: CGFloat.infinity),
                            CGSize(width: 0, height: 20), CGSize(width: -1, height: 20),
                            CGSize(width: 16385, height: 1), CGSize(width: 16384, height: 16384),
                            CGSize(width: 8000, height: 4000.1)]
        let invalidRects = [CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
                            CGRect(x: 0, y: 0, width: -20, height: 20), CGRect(x: 0, y: 0, width: 0, height: 20),
                            CGRect(x: 0, y: 0, width: 16384, height: 16384),
                            CGRect(x: 1_000_001, y: 0, width: 20, height: 20),
                            CGRect(x: 999_990, y: 0, width: 20, height: 20)]
        try expect(c.beginViewportEdit(name: "Invalid Only"), "Begin validation transaction")
        for size in invalidSizes {
            try expect(!c.previewViewportResize(to: size) &&
                       !c.previewViewportCrop(to: CGRect(x: 0, y: 0, width: 20, height: 20), outputSize: size), "Reject invalid output")
        }
        for rect in invalidRects {
            try expect(!c.previewViewportCrop(to: rect, outputSize: CGSize(width: 20, height: 20)), "Reject invalid source rectangle/offset")
        }
        try expect(c.document == original && c.snapshotDocumentData() == saved && c.selection == selected && c.cropRect == crop &&
                   dirty == 0 && !c.editingUndoManager.canUndo, "Invalid previews leave every state field and history intact")
        c.endViewportEdit()
        try expect(dirty == 0 && !c.editingUndoManager.canUndo, "Invalid-only gesture creates no undo/notification")
        try expect(c.beginViewportEdit(name: "Valid Then Invalid") && c.previewViewportResize(to: CGSize(width: 31, height: 22)), "Begin fresh valid preview")
        let preview = try c.snapshotDocumentData()
        try expect(!c.previewViewportResize(to: invalidSizes.last!) && c.snapshotDocumentData() == preview && dirty == 0 &&
                   !c.editingUndoManager.canUndo && !c.beginViewportEdit(name: "Nested"), "Invalid update keeps last preview and transaction open, never commits it")
        c.endViewportEdit(cancelled: true)
        try expect(try c.snapshotDocumentData() == saved, "Invalid update cannot replace the cancellation base")
    }
    static func viewportPendingText() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text)
        text.text = "Before"; text.rect = CGRect(x: 10, y: 10, width: 80, height: 50)
        c.document.elements = [text]; c.tool = .select
        let original = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 30, y: 25), clicks: 2))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Viewport text editor") }
        editor.insertText("Committed first", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        var dirty = 0; var reentrantBegins: [Bool] = []
        c.onChange = { dirty += 1; reentrantBegins.append(c.beginViewportEdit(name: "Reentrant")) }
        try expect(c.beginViewportEdit(name: "Crop After Typing"), "Begin commits pending text")
        let typed = c.document
        try expect(editor.superview == nil && !c.hasPendingTextChanges && typed.elements[0].text == "Committed first" &&
                   dirty == 1 && reentrantBegins == [false] && c.editingUndoManager.undoActionName == "Edit Text", "Typing commits separately before snapshot; begin is not reentrant")
        c.onChange = { dirty += 1 }
        try expect(c.previewViewportCrop(to: CGRect(x: 5, y: 4, width: 90, height: 70), outputSize: CGSize(width: 45, height: 35)), "Crop typed text")
        c.endViewportEdit(); let cropped = c.document
        try expect(cropped.elements[0].text == "Committed first" && cropped.elements[0].bounds.origin == CGPoint(x: 5, y: 6) && dirty == 2,
                   "Crop captures and translates committed text")
        c.undo(); try expect(c.document == typed, "First Undo restores typed base")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Second Undo restores original text")
        c.redo(); c.redo(); try expect(c.document == cropped, "Text and crop redo independently")
        try expect(c.beginViewportEdit(name: "Return To Base") && c.previewViewportResize(to: CGSize(width: 20, height: 10)), "No-op gesture preview")
        try expect(c.previewViewportResize(to: cropped.outputSize), "Return to original output")
        let undoName = c.editingUndoManager.undoActionName, notifications = dirty
        c.endViewportEdit()
        try expect(c.document == cropped && c.editingUndoManager.undoActionName == undoName && dirty == notifications, "Return-to-base creates no extra undo")
    }
    static func viewportUnsafeBegin() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        let original = c.document
        c.tool = .brush
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 10, y: 10)))
        c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 30, y: 20)))
        try expect(!c.beginViewportEdit(name: "Unsafe") && !c.previewViewportResize(to: CGSize(width: 50, height: 40)), "In-flight drawing cannot become a viewport base")
        c.cancelOperation(nil)
        try expect(c.document == original && !c.editingUndoManager.canUndo, "Rejected begin leaves drawing cancellation/history intact")
        try expect(c.beginViewportEdit(name: "Safe"), "Begin after drawing cancelled")
        try expect(!c.beginViewportEdit(name: "Nested"), "Reject nested begin")
        try expect(c.previewViewportResize(to: CGSize(width: 50, height: 40)), "Outer transaction still works")
        var cancelled = 0
        c.onViewportEditCancelled = { cancelled += 1 }
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 10, y: 10)))
        try expect(c.document == original && cancelled == 1 && !c.editingUndoManager.canUndo,
                   "New canvas mouseDown cancels the external gesture before drawing")
        c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 30, y: 20)))
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 30, y: 20)))
        try expect(c.document.elements.count == 1 && c.outputSize == original.outputSize, "New drawing never inherits half-preview output")
        c.undo(); c.endViewportEdit(cancelled: true)
        try expect(c.document == original && cancelled == 1, "Only new drawing is undoable; interruption cannot cancel twice")
    }
    static func viewportReplacement() throws {
        for action in ["undo", "direct undo", "redo", "load", "assign", "mutation", "blank"] {
            let c = try viewportCanvas()
            c.setBackgroundColor(.clear)
            _ = c.resizeImage(to: CGSize(width: 45, height: 30)); c.undo()
            let base = c.document, source = try c.snapshotDocumentData()
            try expect(c.beginViewportEdit(name: "Interrupted") &&
                       c.previewViewportCrop(to: CGRect(x: 8, y: 5, width: 40, height: 35), outputSize: CGSize(width: 40, height: 35)), "Begin interrupted crop")
            switch action {
            case "undo": c.undo(); try expect(c.document.backgroundColor == .white && c.document.size == base.size, "Undo cancels preview before undoing prior edit")
            case "direct undo":
                c.editingUndoManager.undo()
                try expect(c.document.backgroundColor == .white && c.document.size == base.size, "Direct UndoManager path also cancels preview")
            case "redo": c.redo(); try expect(c.outputSize == CGSize(width: 45, height: 30) && c.document.elements == base.elements, "Redo cancels preview before replaying history")
            case "load":
                let preview = try c.snapshotDocumentData()
                do { try c.loadDocument(data: Data("invalid".utf8)); throw Failure(description: "Invalid load should fail") }
                catch is DecodingError { }
                try expect(try c.snapshotDocumentData() == preview && !c.beginViewportEdit(name: "Still Active"), "Failed replacement preserves pending transaction")
                try c.loadDocument(data: source, clearingUndo: false)
                try expect(c.document == base && c.snapshotDocumentData() == source && c.editingUndoManager.canUndo && c.editingUndoManager.canRedo, "Validated load cancels transaction and keeps requested history")
            case "assign":
                c.document = SketchDocument(size: CGSize(width: 120, height: 90))
                try expect(c.document.backgroundPNG == nil && c.document.elements.isEmpty && c.document.size.width == 120, "Direct document assignment survives old transaction")
            case "mutation":
                let reference = canvas(); try reference.loadDocument(data: c.snapshotDocumentData())
                reference.document.backgroundColor = SketchColor(.blue)
                c.document.backgroundColor = SketchColor(.blue)
                try expect(c.snapshotDocumentData() == reference.snapshotDocumentData() && c.cropRect == nil,
                           "Direct document mutation invalidates the base without corrupting the live retained pan offset")
            default:
                c.newBlank(size: CGSize(width: 120, height: 90)); let replacement = c.document
                c.undo(); try expect(c.document == base && c.snapshotDocumentData() == source, "New canvas Undo restores pre-gesture base")
                c.redo(); try expect(c.document == replacement, "New canvas redo")
            }
            let interrupted = try c.snapshotDocumentData()
            c.endViewportEdit(cancelled: true); c.endViewportEdit()
            try expect(c.snapshotDocumentData() == interrupted && !c.previewViewportResize(to: CGSize(width: 20, height: 20)) &&
                       c.beginViewportEdit(name: "Fresh"), "Interrupted transaction cannot revive or block replacement/history")
            c.endViewportEdit(cancelled: true)
        }
    }
    static func presentationOutput() throws {
        let c = try viewportCanvas()
        try expect(c.reframe(to: CGRect(x: 0.5, y: 0.5, width: 60.25, height: 50.25), outputSize: CGSize(width: 30, height: 25)), "Fractional visible source")
        c.editingUndoManager.removeAllActions(); c.setBackgroundColor(.clear); c.setBackgroundColor(.white); c.undo()
        let original = c.document, saved = try c.snapshotDocumentData(), selected = c.selection, crop = c.cropRect
        let normal = c.outputSize, fullSize = c.fullResolutionOutputSize, sourcePNG = c.document.backgroundPNG
        let undoName = c.editingUndoManager.undoActionName, redoName = c.editingUndoManager.redoActionName
        var dirty = 0; c.onChange = { dirty += 1 }; c.setZoom(1.5)
        try expect(fullSize == CGSize(width: 60, height: 50), "Actual rounds visible source to nearest, not hidden full photo")
        for _ in 0..<3 {
            try expect(c.setPresentationOutputSize(fullSize), "Enter Actual")
            try expect(c.outputSize == fullSize && c.frame.size == CGSize(width: 90, height: 75) &&
                       c.document.backgroundPNG == sourcePNG && c.document.size == original.size &&
                       c.document.elements == original.elements && c.selection == selected && c.cropRect == crop,
                       "Actual changes native frame/output while retaining source/vector/overlay state")
            let exported = NSBitmapImageRep(data: c.imageData(format: "png")!)!
            try expect(exported.pixelsWide == 60 && exported.pixelsHigh == 50, "Actual uses nearest visible source pixels")
            let originalExport = NSBitmapImageRep(data: c.imageData(format: "png", originalSize: true)!)!
            try expect(originalExport.pixelsWide == 61 && originalExport.pixelsHigh == 51,
                       "Original-size raster export still rounds source coordinates up independently of Actual")
            try expect(c.setPresentationOutputSize(normal) && c.snapshotDocumentData() == saved && c.document == original,
                       "Leaving Actual restores normal output and exact retained pan supplement")
        }
        try expect(dirty == 0 && c.editingUndoManager.canUndo && c.editingUndoManager.canRedo &&
                   c.editingUndoManager.undoActionName == undoName && c.editingUndoManager.redoActionName == redoName, "Presentation never dirties or consumes history")
        c.redo(); c.undo(); try expect(c.document == original, "Prior history still works after repeated Actual transitions")
        let expanded = canvas(); try expanded.loadDocument(data: saved)
        _ = expanded.reframe(to: CGRect(x: -20.5, y: -10.5, width: 100, height: 80), outputSize: CGSize(width: 100, height: 80))
        try expect(try pixel(expanded, 10, 10).greenComponent > 0.9, "Hidden original pixels survive output mutations")
        let plain = canvas(); plain.document.size = CGSize(width: 33.2, height: 21.4)
        try expect(plain.fullResolutionOutputSize == CGSize(width: 33, height: 21), "Nearest source sizing also works without photo")
        let fractional = plain.document
        try expect(plain.setPresentationOutputSize(plain.fullResolutionOutputSize) &&
                   plain.setPresentationOutputSize(fractional.outputSize) && plain.document == fractional,
                   "Presentation can restore an exact fractional normal size with nil renderSize")
        for (source, expected) in [(CGSize(width: 100.2, height: 100.8), CGSize(width: 100, height: 101)),
                                   (CGSize(width: 100.8, height: 100.2), CGSize(width: 101, height: 100)),
                                   (CGSize(width: 100.5, height: 1.2), CGSize(width: 101, height: 1))] {
            plain.document.size = source
            try expect(plain.fullResolutionOutputSize == expected, "Nearest source pixels distinguish below/above half on both axes and round ties up")
        }
        plain.document.renderSize = CGSize(width: 10, height: 10)
        plain.document.size = CGSize(width: 0.2, height: 100.8)
        try expect(plain.fullResolutionOutputSize == CGSize(width: 1, height: 101), "Actual clamps each rounded source dimension to at least one")
        plain.document.size = CGSize(width: CGFloat.nan, height: CGFloat.infinity)
        try expect(SketchDocument.validSize(plain.fullResolutionOutputSize), "Invalid transient source size returns a safe finite output")
    }
    static func presentationPendingText() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text)
        text.text = "Before"; text.rect = CGRect(x: 10, y: 10, width: 80, height: 50)
        c.document.elements = [text]; c.tool = .select
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 30, y: 25), clicks: 2))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Presentation text editor") }
        editor.insertText("Pending", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let original = c.document, saved = try c.snapshotDocumentData(), selected = c.selection
        var dirty = 0; c.onChange = { dirty += 1 }
        let invalid = CGSize(width: 16384, height: 16384)
        try expect(!c.setPresentationOutputSize(invalid) && !c.previewViewportResize(to: invalid) &&
                   !c.previewViewportCrop(to: CGRect(x: 0, y: 0, width: 20, height: 20), outputSize: invalid), "Invalid sizes never implicitly begin or commit text")
        try expect(c.setPresentationOutputSize(CGSize(width: 50.2, height: 40.2)) && c.outputSize == CGSize(width: 50.2, height: 40.2), "Presentation preserves requested valid size")
        try expect(editor.string == "Pending" && editor.superview === c && window.firstResponder === editor &&
                   c.hasPendingTextChanges && c.document.elements == original.elements && c.selection == selected &&
                   dirty == 0 && !c.editingUndoManager.canUndo, "Presentation leaves native typing and document text untouched")
        try expect(c.setPresentationOutputSize(original.outputSize) && c.snapshotDocumentData() == saved, "Normal restores pending snapshot exactly")
        c.cancelOperation(nil)
    }
    static func actualHistoryIsolation() throws {
        let c = try viewportCanvas(), normal = c.outputSize
        let original = c.document, saved = try c.snapshotDocumentData()
        var changes = 0, reentry = false, recursive = false
        c.onChange = {
            if reentry { recursive = true }; reentry = true; changes += 1
            _ = c.setPresentationOutputSize(c.fullResolutionOutputSize)
            reentry = false
        }
        try expect(c.beginActualPresentation(), "Begin transient Actual")
        let actual = try c.snapshotDocumentData()
        try expect(!c.beginActualPresentation() && c.snapshotDocumentData() == actual, "Nested Actual begin is rejected without mutation")
        c.setBackgroundColor(.white); _ = c.resizeImage(to: normal)
        try expect(changes == 0 && !c.editingUndoManager.canUndo && c.outputSize == c.fullResolutionOutputSize,
                   "Normalized equality suppresses no-op history despite live Actual output")
        c.duplicateSelection(); let edited = c.document.elements
        try expect(changes == 1 && !recursive && c.outputSize == c.fullResolutionOutputSize, "One edit callback may reapply presentation without reentry")
        c.endActualPresentation(); c.endActualPresentation(); c.onChange = { changes += 1 }
        try expect(c.outputSize == normal && changes == 1, "Mode exit restores normal silently")
        c.undo()
        try expect(c.document == original && c.snapshotDocumentData() == saved && c.outputSize == normal,
                   "Actual edit then exit then Undo restores normal output and all retained source")
        c.redo()
        let exported = NSBitmapImageRep(data: c.imageData(format: "png")!)!
        try expect(c.document.elements == edited && c.outputSize == normal && exported.pixelsWide == 35 && exported.pixelsHigh == 30,
                   "Redo cannot leak Actual output into normal export")
    }
    static func actualPreexistingHistory() throws {
        let c = try viewportCanvas(), original = c.document, saved = try c.snapshotDocumentData()
        _ = c.resizeImage(to: CGSize(width: 45, height: 40))
        let resized = c.document
        var changes = 0; c.onChange = { changes += 1 }
        try expect(c.beginActualPresentation(), "Begin after normal resize")
        c.undo()
        var expected = original; expected.renderSize = nil
        try expect(c.document == expected && c.outputSize == c.fullResolutionOutputSize && changes == 1,
                   "Pre-Actual Undo restores source/content while retaining full live presentation")
        c.endActualPresentation()
        try expect(c.document == original && c.snapshotDocumentData() == saved && changes == 1, "Exit uses undone normal output, not original entry size")
        c.redo()
        try expect(c.document == resized && c.editingUndoManager.canUndo && !c.editingUndoManager.canRedo,
                   "Normal resize -> Actual -> Undo -> leave -> Redo restores output and registers an inverse")
        c.undo()
        try expect(c.document == original && c.snapshotDocumentData() == saved && c.editingUndoManager.canRedo,
                   "Resize remains undoable after Redo outside Actual")
        c.redo(); try expect(c.document == resized && c.editingUndoManager.canUndo, "Repeated resize history stays reversible")
        try expect(c.beginActualPresentation(), "Re-enter Actual")
        c.undo(); c.redo()
        try expect(c.outputSize == c.fullResolutionOutputSize, "Both old Undo and Redo stay in Actual")
        c.endActualPresentation(); try expect(c.document == resized, "Redo while Actual updates retained normal output")
    }
    static func actualTransformHistory() throws {
        let actions: [(String, (CanvasView) -> Void)] = [
            ("rotate", { $0.rotate(clockwise: true) }), ("flip", { $0.flip(horizontal: true) }),
            ("crop", { _ = $0.reframe(to: CGRect(x: 5, y: 3, width: 50, height: 40)) }),
            ("resize", { _ = $0.resizeImage(to: CGSize(width: 47, height: 33)) })
        ]
        for (name, action) in actions {
            let c = try viewportCanvas(), original = c.document, saved = try c.snapshotDocumentData()
            let reference = canvas(); try reference.loadDocument(data: saved); action(reference)
            let transformed = reference.document, transformedData = try reference.snapshotDocumentData()
            try expect(c.beginActualPresentation(), "Begin Actual \(name)")
            action(c)
            try expect(c.outputSize == c.fullResolutionOutputSize && c.document.elements == transformed.elements &&
                       c.document.backgroundPNG == transformed.backgroundPNG, "\(name) transforms source while retaining Actual display")
            c.undo(); try expect(c.outputSize == c.fullResolutionOutputSize && c.document.elements == original.elements, "\(name) Undo while Actual")
            c.redo(); c.endActualPresentation()
            try expect(c.document == transformed && c.snapshotDocumentData() == transformedData, "\(name) normal dimensions/source exactly match independent normal edit")
            c.undo(); try expect(c.document == original && c.snapshotDocumentData() == saved, "\(name) Undo after exit restores original normal source")
            c.redo(); try expect(c.document == transformed && c.snapshotDocumentData() == transformedData, "\(name) Redo after exit has normal output")
            try expect(c.beginActualPresentation(), "Begin before controller exit \(name)")
            c.undo(); c.endActualPresentation()
            try expect(c.document == original && c.snapshotDocumentData() == saved,
                       "\(name) exit retains the normal output restored by source Undo")
            c.redo()
            try expect(c.document == transformed && c.snapshotDocumentData() == transformedData && c.editingUndoManager.canUndo,
                       "\(name) Redo after exit recovers normalized source history and remains undoable")
            c.undo()
            try expect(c.document == original && c.snapshotDocumentData() == saved,
                       "\(name) inverse history restores source and normal output after exit")
        }
    }
    static func actualNativeState() throws {
        for mode in ["pan", "move", "draw", "erase"] {
            let c = try viewportCanvas(); let window = host(c); defer { window.close() }
            c.tool = mode == "draw" ? .brush : (mode == "erase" ? .eraser : .select)
            let original = c.document, saved = try c.snapshotDocumentData(), selected = c.selection, crop = c.cropRect
            try expect(c.beginActualPresentation(), "Begin Actual native \(mode)")
            let actual = try c.snapshotDocumentData()
            let start = CGPoint(x: 30, y: 32), end = CGPoint(x: 40, y: 42)
            if mode == "pan" { c.keyDown(with: try key(c, 49)) }
            c.mouseDown(with: try mouse(c, .leftMouseDown, start))
            c.mouseDragged(with: try mouse(c, .leftMouseDragged, end))
            c.cancelOperation(nil)
            try expect(c.snapshotDocumentData() == actual && c.selection == selected && c.cropRect == crop &&
                       !c.editingUndoManager.canUndo, "Cancelled native \(mode) uses full raw gesture state without history")
            try drag(c, from: start, to: end)
            if mode == "pan" { c.keyUp(with: try key(c, 49, type: .keyUp)) }
            try expect(c.editingUndoManager.canUndo && c.outputSize == c.fullResolutionOutputSize, "Native \(mode) edit preserves Actual mode")
            c.endActualPresentation(); let edited = c.document, editedData = try c.snapshotDocumentData()
            c.undo()
            try expect(c.document == original && c.snapshotDocumentData() == saved && c.selection == selected && c.cropRect == crop,
                       "Native \(mode) history restores normal output plus complete source/selection/crop")
            c.redo(); try expect(c.document == edited && c.snapshotDocumentData() == editedData && c.outputSize == original.outputSize,
                                "Native \(mode) redo does not restore transient Actual renderSize")
        }
    }
    static func actualPendingTextState() throws {
        for startsActual in [false, true] {
            for cancelAfterExit in [false, true] {
                let c = canvas(); let window = host(c); defer { window.close() }
                var text = SketchElement(kind: .text)
                text.text = "Before"; text.rect = CGRect(x: 10, y: 10, width: 80, height: 50)
                c.document.elements = [text]; c.tool = .select
                _ = c.resizeImage(to: CGSize(width: 50, height: 40)); c.editingUndoManager.removeAllActions()
                let original = c.document
                if startsActual { try expect(c.beginActualPresentation(), "Begin before editor") }
                c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 30, y: 25), clicks: 2))
                if !startsActual { try expect(c.beginActualPresentation(), "Begin with unchanged pending editor") }
                guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Actual text editor") }
                try expect(!c.hasPendingTextChanges, "Actual presentation alone never marks pending text changed")
                editor.insertText("Typed in Actual", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
                let pending = try SketchDocument.decode(c.snapshotDocumentData())
                try expect(pending.outputSize == c.fullResolutionOutputSize && pending.elements[0].text == "Typed in Actual" &&
                           c.hasPendingTextChanges, "Recovery exports raw Actual output and pending text, independent of normalized history")
                if cancelAfterExit {
                    c.endActualPresentation(); c.cancelOperation(nil)
                    try expect(c.document == original && !c.editingUndoManager.canUndo && !c.hasPendingTextChanges,
                               "Cancelling an editor captured in Actual after exit cannot restore Actual output")
                } else {
                    c.commitPendingTextEditing(); let actual = c.document
                    c.endActualPresentation(); let edited = c.document
                    try expect(actual.outputSize == c.fullResolutionOutputSize && edited.outputSize == original.outputSize,
                               "Native text commit retains live Actual until silent exit")
                    c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Actual text Undo restores normal output")
                    c.redo(); try expect(c.document == edited, "Actual text Redo restores normal output")
                }
            }
        }
        let unchanged = canvas(); let window = host(unchanged); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Same"; text.rect = CGRect(x: 10, y: 10, width: 80, height: 50)
        unchanged.document.elements = [text]; unchanged.tool = .select
        _ = unchanged.setPresentationOutputSize(CGSize(width: 50, height: 40))
        unchanged.mouseDown(with: try mouse(unchanged, .leftMouseDown, CGPoint(x: 30, y: 25), clicks: 2))
        try expect(unchanged.beginActualPresentation(), "Begin Actual with unchanged text")
        unchanged.commitPendingTextEditing(); unchanged.endActualPresentation()
        try expect(!unchanged.editingUndoManager.canUndo, "Committing unchanged pre-Actual text creates no undo")
        let typing = canvas(); let typingWindow = host(typing); defer { typingWindow.close() }
        _ = typing.setPresentationOutputSize(CGSize(width: 50, height: 40)); let beforeTyping = typing.document
        try expect(typingWindow.makeFirstResponder(typing) && typing.beginActualPresentation(), "Justype Actual focus")
        let character = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: typingWindow.windowNumber, context: nil, characters: "T", charactersIgnoringModifiers: "t",
            isARepeat: false, keyCode: 17)!
        typing.keyDown(with: character)
        let pendingTyping = try SketchDocument.decode(typing.snapshotDocumentData())
        try expect(pendingTyping.outputSize == typing.fullResolutionOutputSize && pendingTyping.elements.last?.text == "T",
                   "Actual Justype retains full live output and native pending text")
        typing.endActualPresentation(); typing.commitPendingTextEditing(); let typed = typing.document
        typing.undo(); try expect(typing.document == beforeTyping && !typing.editingUndoManager.canUndo, "Justype creation captured in Actual undoes normally after exit")
        typing.redo(); try expect(typing.document == typed && typing.outputSize == beforeTyping.outputSize, "Actual Justype redo keeps normal export size")
    }
    static func actualLifecycleGuards() throws {
        let c = try viewportCanvas(), saved = try c.snapshotDocumentData(), original = c.document
        var changes = 0, cancellations = 0
        c.onChange = { changes += 1 }; c.onViewportEditCancelled = { cancellations += 1 }
        try expect(c.beginViewportEdit(name: "Before Actual") && c.previewViewportResize(to: CGSize(width: 20, height: 15)), "Start viewport")
        let preview = try c.snapshotDocumentData()
        try expect(!c.beginActualPresentation() && c.snapshotDocumentData() == preview && cancellations == 0,
                   "Actual begin cannot silently cancel/commit an active viewport")
        c.endViewportEdit(cancelled: true)
        try expect(c.beginActualPresentation() && !c.beginViewportEdit(name: "Unsafe Actual"), "Viewport edit is guarded under Actual")
        c.endViewportEdit(cancelled: true)
        try expect(cancellations == 1 && changes == 0 && c.outputSize == c.fullResolutionOutputSize, "Rejected viewport cancellation cannot change Actual or notify")
        let actual = try c.snapshotDocumentData(), committed = try c.documentData()
        let actualDocument = try SketchDocument.decode(actual)
        try expect(actual == committed && actualDocument.outputSize == c.fullResolutionOutputSize && actualDocument.size == original.size,
                   "Save/recovery retain full Actual output with original source coordinates")
        do { try c.loadDocument(data: Data("invalid".utf8)); throw Failure(description: "Invalid load should fail") }
        catch is DecodingError { }
        c.endActualPresentation()
        try expect(c.document == original && c.snapshotDocumentData() == saved && changes == 0, "Failed load retains transient normal output for exit")
        for replacement in ["load", "assign", "blank", "background"] {
            try c.loadDocument(data: saved)
            try expect(c.beginActualPresentation(), "Begin before \(replacement)")
            switch replacement {
            case "load": try c.loadDocument(data: actual)
            case "assign":
                var new = SketchDocument(size: CGSize(width: 120, height: 90)); new.renderSize = CGSize(width: 83, height: 43)
                c.document = new
            case "blank": c.newBlank(size: CGSize(width: 120, height: 90))
            default: c.setBackground(backdrop(CGSize(width: 120, height: 90)))
            }
            let replaced = c.document
            c.endActualPresentation()
            try expect(c.document == replaced && c.beginActualPresentation(), "\(replacement) clears old Actual retention so exit cannot revive it")
            c.endActualPresentation()
        }
    }
    static func viewportCancellationCallback() throws {
        let c = try viewportCanvas(), original = c.document
        var callbacks = 0, observed: [SketchDocument] = []
        c.onViewportEditCancelled = {
            callbacks += 1; observed.append(c.document)
            c.endViewportEdit(cancelled: true)
        }
        try expect(c.beginViewportEdit(name: "Commit") && c.previewViewportResize(to: CGSize(width: 40, height: 30)), "Begin callback commit")
        c.endViewportEdit(); c.endViewportEdit(cancelled: true)
        try expect(callbacks == 0, "Normal completion and late cancel never notify cancellation")
        try expect(c.beginViewportEdit(name: "Cancel") && c.previewViewportResize(to: CGSize(width: 20, height: 10)), "Begin callback cancellation")
        c.endViewportEdit(cancelled: true)
        try expect(callbacks == 1 && observed.last == c.document, "Cancel restores before callback and clears transaction before recursive cancel")
        try expect(c.beginViewportEdit(name: "Undo Interruption") && c.previewViewportResize(to: CGSize(width: 20, height: 10)), "Begin before Undo")
        c.undo(); try expect(callbacks == 2 && c.document == original, "Undo cancels external gesture exactly once")
        try expect(c.beginViewportEdit(name: "Direct Replacement") && c.previewViewportResize(to: CGSize(width: 20, height: 10)), "Begin before direct replacement")
        let replacement = SketchDocument(size: CGSize(width: 120, height: 90))
        c.document = replacement
        try expect(callbacks == 3 && observed.last == replacement && c.document == replacement,
                   "didSet cancellation notifies shell without overwriting incoming document")
        c.endViewportEdit(cancelled: true); try expect(callbacks == 3, "Replacement clears stale transaction")
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
        try expect(c.imageData(format: "opensnap") == nil, "Unsupported original format must not masquerade as image export")
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
        try expect(c.document.elements.count == 2, "Fill adds editable geometry while preserving the boundary")
        let inside = try pixel(c, 30, 30), outside = try pixel(c, 80, 60)
        try expect(inside.greenComponent > 0.9 && inside.redComponent < 0.1, "Fill chosen region")
        try expect(outside.redComponent > 0.9, "Fill cannot leak outside the closed shape")
        try expect(c.document.elements[0].groupID != nil && c.document.elements[0].groupID == c.document.elements[1].groupID,
                   "Paint fill glues contacting shape to fill")
        c.undo(); try expect(c.document.elements.count == 1, "Fill undo")
    }
    static func vectorFillBackground() throws {
        let c = canvas(); c.setBackground(backdrop())
        let boundary = rectangle(CGRect(x: 15, y: 15, width: 40, height: 30), color: .black, filled: false)
        var text = SketchElement(kind: .text); text.text = "Label"; text.rect = CGRect(x: 25, y: 5, width: 50, height: 25)
        c.document.elements = [boundary, text]; let background = c.document.backgroundPNG
        c.strokeColor = .red; c.floodFill(at: CGPoint(x: 30, y: 30))
        let fill = c.document.elements.first { $0.id != boundary.id && $0.id != text.id }!
        let path = try SVGPathParser.makeCGPath(fill.pathCommands)
        try expect(fill.kind == .path && fill.imagePNG == nil && path.contains(CGPoint(x: 45, y: 35)), "Photo color transitions never stop geometric fill")
        try expect(!path.contains(CGPoint(x: 80, y: 60)) && c.document.backgroundPNG == background, "Enclosure bounds and photo retained")
        try expect(c.document.elements.map(\.id) == [fill.id, boundary.id, text.id], "Fill inserted below its boundary and text")
        try expect(c.selection.isEmpty, "Fill does not add a selection")
    }
    static func shadowFill() throws {
        let c = canvas(); var shape = rectangle(CGRect(x: 15, y: 15, width: 50, height: 40))
        shape.shadowed = true; shape.groupID = UUID(); c.document.elements = [shape]; c.selection = [shape.id]
        c.strokeColor = .green; c.floodFill(at: CGPoint(x: 30, y: 30))
        var expected = shape; expected.color = SketchColor(.green)
        try expect(c.document.elements == [expected] && c.selection == [shape.id], "Shadow branch only changes the contacted object's RGBA")
        c.undo(); try expect(c.document.elements == [shape], "Recolor undo retains exact original")
        c.editingUndoManager.removeAllActions(); c.strokeColor = .red; c.floodFill(at: CGPoint(x: 30, y: 30))
        try expect(!c.editingUndoManager.canUndo && c.document.elements == [shape], "Repeated identical opaque fill is a no-op")
    }
    static func alphaFill() throws {
        let c = canvas(); var shape = rectangle(CGRect(x: 15, y: 15, width: 50, height: 40))
        shape.color = SketchColor(NSColor.red.withAlphaComponent(0.5)); c.document.elements = [shape]
        c.strokeColor = NSColor.red.withAlphaComponent(0.5); c.floodFill(at: CGPoint(x: 30, y: 30))
        try expect(c.document.elements.count == 1 && abs(c.document.elements[0].color.alpha - 0.75) < 0.000001,
            "Repeated half-alpha fill composites to three-quarter alpha")
        try expect(c.document.elements[0].id != shape.id && c.selection.isEmpty, "Merged region gets a fresh unselected ID")
        c.undo(); shape.groupID = UUID(); c.document.elements = [shape]; c.selection = [shape.id]
        c.strokeColor = .green; c.floodFill(at: CGPoint(x: 30, y: 30), grouping: false)
        try expect(c.document.elements.count == 2 && c.document.elements.contains(shape), "Shift leaves original style and group untouched")
        try expect(c.document.elements.last?.groupID == nil && c.selection == [shape.id], "Shift result is ungrouped and preserves selection")
    }
    static func matchingFill() throws {
        let c = canvas(); let boundary = rectangle(CGRect(x: 15, y: 15, width: 40, height: 30), color: .black, filled: false)
        c.document.elements = [boundary]; c.selection = [boundary.id]; c.strokeColor = .black
        c.floodFill(at: CGPoint(x: 30, y: 30))
        try expect(c.document.elements.count == 1 && c.document.elements[0].kind == .path && c.document.elements[0].imagePNG == nil,
            "Same-style boundary and region merge into editable geometry")
        try expect(c.document.elements[0].id != boundary.id && c.selection.isEmpty, "Replacement is fresh and unselected")
        c.undo(); try expect(c.document.elements == [boundary] && c.selection == [boundary.id], "Merged fill undo restores old selection")
    }
    static func layeredShiftFill() throws {
        let c = canvas(); var first = rectangle(CGRect(x: 10, y: 10, width: 45, height: 45), color: .blue)
        var second = rectangle(CGRect(x: 35, y: 15, width: 45, height: 45), color: .blue)
        first.groupID = UUID(); second.groupID = first.groupID
        c.document.elements = [first, second]; c.strokeColor = .green
        c.floodFill(at: CGPoint(x: 45, y: 30), grouping: false)
        try expect(Array(c.document.elements.prefix(2)) == [first, second] && c.document.elements.last?.groupID == nil,
            "Shift leaves existing overlapping groups and appends the region above them")
        try expect(try pixel(c, 45, 30).greenComponent > 0.9, "New color is actually visible in the overlap")
    }
    static func mixedPathFill() throws {
        let c = canvas(); let blue = rectangle(CGRect(x: 10, y: 10, width: 70, height: 50), color: .blue)
        let green = rectangle(CGRect(x: 65, y: 20, width: 25, height: 25), color: .green)
        c.document.elements = [blue, green]; c.strokeColor = .green
        c.floodFill(at: CGPoint(x: 30, y: 30))
        try expect(c.document.elements.contains { $0.id == blue.id && $0.color == blue.color } &&
            c.document.elements.contains { $0.id == green.id && $0.color == green.color }, "Mixed hit groups without deleting matching-color contacts")
        try expect(c.document.elements.count == 3 && c.document.elements.allSatisfy { $0.groupID != nil }, "Contact and new region form a group")
        try expect(try pixel(c, 30, 30).greenComponent > 0.9, "Mixed hit region is inserted above clicked paint")
    }
    static func protectedErase() throws {
        let c = canvas(); var photo = SketchElement(kind: .raster)
        photo.imagePNG = SketchRenderer.png(image: backdrop(NSSize(width: 20, height: 20)))!; photo.rect = CGRect(x: 20, y: 20, width: 40, height: 40)
        var text = SketchElement(kind: .text); text.text = "Safe"; text.rect = photo.rect; text.groupID = UUID(); photo.groupID = text.groupID
        let drawing = rectangle(photo.rect); c.document.elements = [photo, drawing, text]
        c.eraseStroke(points: [CGPoint(x: 40, y: 10), CGPoint(x: 40, y: 70)], width: 10)
        try expect(c.document.elements.first == photo && c.document.elements.last == text, "Positioned photo and text retain exact bytes, groups, transforms and order")
        try expect(c.document.elements.dropFirst().dropLast().count == 2 && c.document.elements.dropFirst().dropLast().allSatisfy { $0.kind == .path && $0.id != drawing.id }, "Only pen geometry splits with fresh IDs")
    }
    static func fittedPencil() throws {
        let c = canvas(); let window = host(c); defer { window.close() }; c.tool = .brush; c.strokeWidth = 5
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 10, y: 20)))
        c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 30, y: 20)))
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 90, y: 70)))
        let stroke = c.document.elements[0]
        try expect(stroke.kind == .path && stroke.filled && stroke.strokeWidth == 0 && stroke.imagePNG == nil, "Fitted Pencil stays one editable filled path")
        try expect(stroke.bounds.maxX < 40 && stroke.bounds.maxY < 30, "Release-only location and zero pressure cannot add a false tail")
        try expect(stroke.pathCommands.contains { if case .cubic = $0 { return true }; return false }, "Pencil stores cubic curves")
        c.undo(); try expect(c.document.elements.isEmpty, "Entire fitted stroke is one undo")
        c.redo(); try expect(c.document.elements == [stroke], "Redo preserves exact curve geometry")
    }
    static func tabletInput() throws {
        let c = canvas(); let window = host(c); defer { window.close() }; c.tool = .brush; c.strokeWidth = 12
        var widths: [CGFloat] = []
        for pressure: Float in [0, 0.5, 1] {
            let input = CanvasTabletEvent(); input.inputPressure = pressure
            input.inputLocation = c.convert(CGPoint(x: 40, y: 40), to: nil)
            c.mouseDown(with: input)
            input.inputType = .leftMouseUp; input.inputPressure = 0
            c.mouseUp(with: input)
            widths.append(c.document.elements.last!.bounds.width)
            c.undo()
        }
        try expect(abs(widths[0] / widths[2] - 0.25) < 0.00001 && abs(widths[1] / widths[2] - 0.625) < 0.00001,
            "Canvas reads actual tablet pressure, including genuine zero input")
        let proximity = CanvasTabletEvent(); proximity.inputType = .tabletProximity
        c.tool = .arrow; c.tabletProximity(with: proximity)
        try expect(c.effectiveTool == .eraser && c.tool == .arrow, "Pen eraser proximity temporarily changes the effective tool")
        c.flagsChanged(with: try key(c, 55, type: .flagsChanged, flags: [.command]))
        try expect(c.effectiveTool == .select, "Command cursor takes precedence over tablet eraser")
        c.flagsChanged(with: try key(c, 55, type: .flagsChanged)); c.tool = .fill
        try expect(c.effectiveTool == .fill, "Existing tablet Fill handling is preserved independently of Control routing")
        c.tool = .arrow; proximity.entering = false; c.tabletProximity(with: proximity)
        try expect(c.effectiveTool == .arrow, "Leaving tablet proximity restores the selected tool")
    }
    static func separatedColorFill() throws {
        let c = canvas(); var first = rectangle(CGRect(x: 5, y: 5, width: 15, height: 15))
        first.color = SketchColor(NSColor.red.withAlphaComponent(0.5))
        let middle = rectangle(CGRect(x: 30, y: 5, width: 15, height: 15), color: .blue)
        var last = first; last.id = UUID(); last.rect.origin.x = 60; last.groupID = UUID()
        let originals = [first, middle, last]; c.document.elements = originals
        c.strokeColor = NSColor.red.withAlphaComponent(0.5); c.floodFill(at: CGPoint(x: 65, y: 10))
        try expect(c.document.elements.prefix(2).elementsEqual(originals.prefix(2)) && abs(c.document.elements.last!.color.alpha - 0.75) < 0.000001,
            "Later matching run blends independently without changing earlier layers")
        c.undo(); try expect(c.document.elements == originals, "Later alpha fill undo is exact")
        c.strokeColor = .green; c.floodFill(at: CGPoint(x: 65, y: 10), grouping: false)
        try expect(c.document.elements.prefix(3).elementsEqual(originals) && c.document.elements.last?.groupID == nil,
            "Shift appends a fresh region and retains the later original group")
        c.undo(); try expect(c.document.elements == originals, "Later Shift undo is exact")
    }
    static func gestureHistory() throws {
        for tool in [SketchTool.brush, .select, .eraser] {
            let c = canvas(); let window = host(c); defer { window.close() }
            c.tool = .rectangle; try drag(c, from: CGPoint(x: 15, y: 15), to: CGPoint(x: 45, y: 45))
            let drawn = c.document; c.tool = tool
            c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20)))
            c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 30, y: 25)))
            c.undo(); try expect(c.document.elements.isEmpty && c.editingUndoManager.canRedo, "Undo cancels active \(tool) before changing history")
            c.cancelOperation(nil); c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 50, y: 50)))
            try expect(c.document.elements.isEmpty && !c.editingUndoManager.canUndo, "Escape/delayed release cannot resurrect old geometry")
            c.redo(); try expect(c.document == drawn, "Redo restores original rectangle exactly")
            c.undo()
            c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20)))
            c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 30, y: 25)))
            c.redo(); c.cancelOperation(nil); c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 50, y: 50)))
            try expect(c.document == drawn && c.editingUndoManager.canUndo && !c.editingUndoManager.canRedo,
                "Redo cancels active gesture, preserving both history branches")
        }
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
        let fragments = c.document.elements.filter { $0.kind == .path }
        try expect(fragments.count == 2 && fragments[0].id != fragments[1].id, "Cut line into two editable independent paths")
        try expect(fragments.allSatisfy { $0.groupID == nil && $0.imagePNG == nil }, "Fragments stay vectors")
        try expect(c.document.elements.first { $0.id == text.id } == text, "Eraser leaves text intact")
        try expect(try pixel(c, 50, 30).blueComponent > 0.9, "Erase gap reveals unchanged background")
        c.undo(); try expect(c.document == before, "Undo eraser restores exact editable objects")
        var brush = line; brush.kind = .brush
        brush.points = [CGPoint(x: 5, y: 30), CGPoint(x: 40, y: 30), CGPoint(x: 80, y: 30)]
        c.document.elements = [brush]
        c.eraseStroke(points: [CGPoint(x: 50, y: 30)], width: 12)
        try expect(c.document.elements.count == 2 && c.document.elements.allSatisfy { $0.kind == .path && $0.imagePNG == nil }, "Freehand splits into independent editable outlines")
    }
    static func pixelEraser() throws {
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 70, height: 50))]
        c.eraseStroke(points: [CGPoint(x: 40, y: 15), CGPoint(x: 40, y: 55)], width: 12)
        try expect(c.document.elements.count == 1 && c.document.elements[0].kind == .path && c.document.elements[0].imagePNG == nil, "Filled area retains an editable vector with a hole")
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
        try expect(c.document.elements.last?.kind == .path && c.document.elements.last?.imagePNG == nil, "Native freehand produces editable fitted geometry")
        c.tool = .brush
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 40, y: 30), flags: [.option]))
        try expect(c.strokeColor.usingColorSpace(.deviceRGB)!.redComponent > 0.9, "Option brush eyedropper")
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 40, y: 30), flags: [.option]))
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
        let liveBefore = c.document
        let pending = try c.snapshotDocumentData()
        let blank = SketchRenderer.bitmap(document: c.document)?.representation(using: .png, properties: [:])
        _ = c.renderedImage()
        try expect(c.document == liveBefore && c.hasPendingTextChanges && c.imageData(format: "png") != blank &&
                   (try c.snapshotDocumentData()) == pending && c.subviews.contains(editor),
                   "Export includes pending text without committing editor, model, or undo")
        c.commitPendingTextEditing()
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
        let saved = try c.documentData()
        try expect(try CanvasView.validatedDocumentData(saved) == c.document,
                   "Native supplement validator returns the matching model while preserving complete input JSON")
        let loaded = canvas(); try loaded.loadDocument(data: saved)
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
        // White contrast outlines are invisible against a white canvas; use
        // a gray backdrop to check the effect rather than obscured interiors.
        c.document.backgroundColor = SketchColor(.gray)
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
        let file = directory.appendingPathComponent("drawing.opensnap")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".OPENSNAP")
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
        expected.rect.size = updated.rect.size
        try expect(updated == expected && updated.color == SketchColor(.blue),
                   "Font action changes only selected text typography/outline/reflow height; red pen does not recolor blue text")
        try expect(c.document.elements[1] == shape && c.document.elements[2] == unselected,
                   "Selected shapes and unselected text remain completely unchanged")
        let naturalWidth = (updated.text as NSString).size(withAttributes: [.font: NSFont(name: updated.fontName, size: updated.fontSize)!]).width
        try expect(abs(updated.rect.width - naturalWidth - 20) < 0.001 && updated.rect.height > text.rect.height,
                   "Recovered natural width includes four points and two capped eight-point margins")
        try expect(updated.rect.width > text.rect.width && updated.rect.origin == text.rect.origin && updated.transform == text.transform,
                   "Font changes grow natural width and retain the anchor and transform")
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
                   styled.elements[0].strokeWidth == text.strokeWidth && styled.elements[0].rect.origin == text.rect.origin,
                   "Pending font action preserves blue color, shadow, pen width and anchor")
        c.undo(); try expect(c.document == committedTyping, "Undo font action retains the committed pending text at its previous font")
        c.undo(); try expect(c.document == original, "Separate typing undo restores the pre-editor document")
        c.redo(); c.redo(); try expect(c.document == styled, "Redo typing then font preserves both edits")
    }
    static func textShadowStyle() throws {
        let c = canvas(NSSize(width: 400, height: 200)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Blue annotation"; text.color = SketchColor(.blue)
        text.rect = CGRect(x: 10, y: 10, width: 200, height: 70); text.shadowed = true
        let shape = rectangle(CGRect(x: 270, y: 20, width: 80, height: 40))
        c.document.elements = [text, shape]; c.tool = .select
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 20, y: 20), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        editor.insertText("Edited annotation", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let pending = try SketchDocument.decode(c.snapshotDocumentData())
        c.selection.insert(shape.id); c.fontName = text.fontName; c.fontSize = text.fontSize
        c.strokeColor = .red; c.strokeWidth = 40; c.filled = true; c.shadowed = false
        c.applyTextStyleToSelection(includingShadow: true)
        let styled = c.document
        try expect(!styled.elements[0].shadowed && styled.elements[0].color == text.color && styled.elements[0].strokeWidth == text.strokeWidth, "Only requested text shadow changes")
        try expect(styled.elements[1] == shape && styled.elements[0].text == "Edited annotation", "Protected shape and pending typing")
        c.undo(); try expect(c.document == pending, "Text style Undo preserves committed typing")
        c.undo(); try expect(c.document.elements == [text, shape], "Separate typing Undo")
        c.redo(); c.redo(); try expect(c.document == styled, "Both Redo steps reproduce style")
    }
    static func defaultTextStyle() throws {
        let c = canvas(NSSize(width: 500, height: 300))
        var a = SketchElement(kind: .text); a.text = "First"; a.fontName = "Courier"; a.fontSize = 23
        a.outlined = false; a.shadowed = false; a.rect = CGRect(x: 10, y: 10, width: 150, height: 50); a.color = SketchColor(.blue)
        var b = a; b.id = UUID(); b.text = "Second"; b.fontSize = 48; b.rect.origin.y = 100
        let shape = rectangle(CGRect(x: 300, y: 30, width: 100, height: 100))
        c.document.elements = [a, b, shape]; c.selection = [a.id, b.id, shape.id]
        c.fontSize = 31; c.fontName = "Courier"; c.outlined = false; c.shadowed = false
        let before = c.document; c.restoreDefaultTextStyle(); let after = c.document
        try expect(c.fontName == "Helvetica-Bold" && c.fontSize == 31 && c.outlined && c.shadowed, "Future text default restored without a size reset")
        for (old, new) in zip([a,b], after.elements.prefix(2)) {
            try expect(new.fontName == "Helvetica-Bold" && new.fontSize == old.fontSize && new.outlined && new.shadowed, "Mixed selected sizes preserved")
            try expect(new.color == old.color && new.text == old.text && new.rect.origin == old.rect.origin && new.transform == old.transform, "Color anchor transform and text preserved")
        }
        try expect(after.elements[2] == shape, "Default text action does not restyle shape")
        c.undo(); try expect(c.document == before, "Default style one Undo")
        c.redo(); try expect(c.document == after, "Default style Redo")
        c.undo(); c.fontName = "Helvetica"; c.fontSize = 80
        c.applyTextEffectsToSelection(outline: true, shadow: true)
        for (old, new) in zip([a,b], c.document.elements.prefix(2)) {
            try expect(new.fontName == old.fontName && new.fontSize == old.fontSize && new.rect == old.rect, "Effect controls preserve every selected font and size")
        }
    }
    static func textContextStyle() throws {
        let c = canvas(NSSize(width: 300, height: 200)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Context"; text.rect = CGRect(x: 10, y: 10, width: 150, height: 70)
        c.document.elements = [text]; c.tool = .brush
        let before = c.document
        let event = try mouse(c, .rightMouseDown, CGPoint(x: 20, y: 20))
        guard let menu = c.menu(for: event) else { throw Failure(description: "Text context menu") }
        try expect(menu.items.map(\.title) == ["Text Style…", "Default Text Style"], "Original reachable text font/default controls")
        try expect(c.selection == [text.id] && c.tool == .brush && c.document == before && !c.editingUndoManager.canUndo, "Context selects text without document or tool mutation")
        var requests = 0; c.onTextStyleRequested = { requests += 1 }
        try expect(NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0]) && requests == 1, "Font context callback")
        try expect(c.menu(for: try mouse(c, .rightMouseDown, CGPoint(x: 20, y: 20), flags: [.control])) == nil, "Control secondary gesture remains eraser")
        try expect(c.menu(for: try mouse(c, .rightMouseDown, CGPoint(x: 220, y: 150))) == nil, "Blank canvas has no text context menu")
    }
    static func textGripEditing() throws {
        let c = canvas(NSSize(width: 600, height: 400)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Before grip"; text.color = SketchColor(.blue)
        text.rect = CGRect(x: 80, y: 60, width: 250, height: 70)
        c.document.elements = [text]; c.tool = .select
        let before = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 90, y: 70), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        try expect(editor.isContinuousSpellCheckingEnabled, "Recovered original starts continuous spelling enabled")
        try expect(!grip.acceptsFirstResponder && !grip.canBecomeKeyView && grip.isFlipped,
                   "Grip cannot replace native typing focus")
        let editorIndex = c.subviews.firstIndex(of: editor)!, gripIndex = c.subviews.firstIndex(of: grip)!
        try expect(gripIndex < editorIndex && grip.frame == CGRect(x: editor.frame.minX - 11, y: editor.frame.minY - 3, width: editor.frame.width + 15, height: editor.frame.height + 6).integral.insetBy(dx: -5, dy: -5),
                   "Original integral frame and exposed left pill are below the editor")
        try expect(c.hitTest(CGPoint(x: 71, y: 80)) === grip && c.hitTest(CGPoint(x: 100, y: 80)) === editor,
                   "Exposed pill receives mouse input while text retains interior selection")
        editor.insertText("After grip", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let selection = editor.selectedRange(), typing = c.activeEditorUndoManager
        var changes = 0; c.onChange = { changes += 1 }
        grip.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 71, y: 80)))
        grip.mouseDragged(with: TextGripDragEvent(30, -12))
        grip.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 101, y: 68)))
        try expect(c.document == before && c.hasPendingTextChanges && !c.editingUndoManager.canUndo && changes == 1,
                   "Move stays pending with dirty notification, without a separate document history entry")
        try expect(window.firstResponder === editor && c.activeEditorUndoManager === typing && editor.selectedRange() == selection,
                   "Dragging preserves active editor, typing Undo and insertion range")
        let snapshot = try SketchDocument.decode(c.snapshotDocumentData())
        try expect(snapshot.elements[0].text == "After grip" && snapshot.elements[0].transform.tx == 30 && snapshot.elements[0].transform.ty == -12,
                   "Recovery snapshot includes pending text and movement together")
        editor.keyDown(with: try key(c, 53))
        try expect(editor.superview == nil && grip.superview == nil && window.firstResponder === c && !c.hasPendingTextChanges,
                   "Escape completes original field editor and removes its grip")
        try expect(c.document == snapshot, "Completion preserves pending snapshot exactly")
        c.undo(); try expect(c.document == before && !c.editingUndoManager.canUndo, "One Undo restores text and placement together")
        c.redo(); try expect(c.document == snapshot, "Redo restores text and placement")
    }
    static func originalArrowGeometry() throws {
        let commands = OriginalArrowGeometry.commands(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 210, y: 50), width: 6.75, reversed: false)
        // Independent coordinates calculated from the original Float32 constants:
        // _createArrow receives 3.375, giving neck 3.65625 and head 14.625.
        let expected: [SVGPathCommand] = [.move(to: CGPoint(x: 10, y: 49)),
            .cubic(control1: CGPoint(x: 102.6875, y: 48.3359375), control2: CGPoint(x: 152.6875, y: 47.671875), to: CGPoint(x: 195.375, y: 46.34375)),
            .line(to: CGPoint(x: 193.9125, y: 41.95625)), .line(to: CGPoint(x: 210, y: 50)),
            .line(to: CGPoint(x: 193.9125, y: 58.04375)), .line(to: CGPoint(x: 195.375, y: 53.65625)),
            .cubic(control1: CGPoint(x: 152.6875, y: 52.328125), control2: CGPoint(x: 102.6875, y: 51.6640625), to: CGPoint(x: 10, y: 51)),
            .cubic(control1: CGPoint(x: 8.500154, y: 50.978508), control2: CGPoint(x: 8.500154, y: 49.021492), to: CGPoint(x: 10, y: 49)), .close]
        let actualPath = try SVGPathParser.makeCGPath(commands), expectedPath = try SVGPathParser.makeCGPath(expected)
        var actualPoints: [CGPoint] = [], expectedPoints: [CGPoint] = []
        func points(_ path: CGPath, into values: inout [CGPoint]) {
            path.applyWithBlock { entry in
                let n = entry.pointee.type == .addCurveToPoint ? 3 : (entry.pointee.type == .closeSubpath ? 0 : 1)
                for i in 0..<n { values.append(entry.pointee.points[i]) }
            }
        }
        points(actualPath, into: &actualPoints); points(expectedPath, into: &expectedPoints)
        try expect(commands.count == 9 && actualPoints.count == expectedPoints.count, "Original closed outline retains three cubic segments and four straight edges")
        for (a, e) in zip(actualPoints, expectedPoints) {
            try expect(hypot(a.x - e.x, a.y - e.y) < 0.0001, "Recovered coordinate \(a) matches independent original fixture \(e)")
        }
        let start = CGPoint(x: 30, y: 40)
        for (dx, dy, ex, ey) in [(100.0, 49.0, 130.0, 40.0), (100, 50, 130, 140), (49, 100, 30, 140),
                                 (50, 100, 130, 140), (-60, 80, -50, 120), (60, -80, 110, -40)] {
            try expect(OriginalArrowGeometry.constrained(CGPoint(x: start.x + dx, y: start.y + dy), from: start) == CGPoint(x: ex, y: ey), "Shift uses strict 2:1 axis thresholds and max-axis diagonal length")
        }
        for (from, to) in [(CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 20)), (CGPoint(x: 20, y: 20), CGPoint(x: 21, y: 20))] {
            let tiny = try SVGPathParser.makeCGPath(OriginalArrowGeometry.commands(from: from, to: to, width: 0.5, reversed: false))
            try expect(!tiny.isEmpty && tiny.boundingBoxOfPath.width > 1 && tiny.boundingBoxOfPath.height > 0, "Zero/short original arrows remain finite with five-pixel minimum length")
        }
        for pref in [0, 1, 2, 9] {
            try expect(OriginalArrowGeometry.reversed(preference: pref, option: false) == (pref == 1) &&
                       OriginalArrowGeometry.reversed(preference: pref, option: true) == (pref != 1), "Option XORs the original preference == 1 predicate, including End tag 2")
        }
    }
    static func originalArrowGestures() throws {
        let start = CGPoint(x: 40, y: 90), end = CGPoint(x: 260, y: 90)
        for pref in [0, 1, 2] {
            for option in [false, true] {
                let c = canvas(NSSize(width: 320, height: 180)), window = host(c); defer { window.close() }
                c.tool = .arrow; c.arrowHeadPreference = pref; c.strokeWidth = 6.75
                c.strokeColor = NSColor(deviceRed: 0.1, green: 0.3, blue: 0.8, alpha: 0.4); c.shadowed = true
                var legacy = SketchElement(kind: .arrow); legacy.points = [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 30)]
                c.document.elements = [legacy]; let before = c.document
                var changes = 0; c.onChange = { changes += 1 }
                c.mouseDown(with: try mouse(c, .leftMouseDown, start))
                c.mouseDragged(with: try mouse(c, .leftMouseDragged, end))
                c.flagsChanged(with: try key(c, 58, type: .flagsChanged, flags: option ? [.option] : []))
                try expect(c.document == before && changes == 0 && !c.editingUndoManager.canUndo, "Temporary preview does not dirty source artwork")
                // Release elsewhere: original ToolArrow retains the dragged endpoint.
                c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 300, y: 140), flags: option ? [.option] : []))
                let after = c.document, arrow = after.elements.last!
                let reversed = (pref == 1) != option
                try expect(after.elements.first == legacy && arrow.kind == .path && arrow.filled && arrow.strokeWidth == 0 &&
                           arrow.color == SketchColor(c.strokeColor) && arrow.shadowed && arrow.pathCommands.count == 9,
                           "New arrows store editable original-style filled paths; old arrow representation and alpha survive")
                try expect(arrow.pathCommands[3] == .line(to: reversed ? start : end) && c.arrowHeadPreference == pref,
                           "Current Option release flag reverses the head without changing the saved default")
                try expect(changes == 1 && c.editingUndoManager.undoActionName == "Draw Arrow", "Drawing is one named transaction")
                let restored = canvas(); try restored.loadDocument(data: c.documentData())
                try expect(restored.document == after, "Arrow curves, style, legacy objects and IDs survive editable serialization")
                c.undo(); try expect(c.document == before && !c.editingUndoManager.canUndo, "One Undo removes exactly the arrow")
                c.redo(); try expect(c.document == after, "Redo restores exact controls and identity")
                c.editingUndoManager.removeAllActions(); let count = changes
                c.mouseDown(with: try mouse(c, .leftMouseDown, start, flags: [.option]))
                c.mouseDragged(with: try mouse(c, .leftMouseDragged, end, flags: [.option]))
                c.cancelOperation(nil); c.mouseUp(with: try mouse(c, .leftMouseUp, end))
                try expect(c.document == after && changes == count && !c.editingUndoManager.canUndo, "Cancel discards arrow preview and delayed release")
            }
        }
        let c = canvas(NSSize(width: 320, height: 180)), window = host(c); defer { window.close() }
        c.tool = .arrow; c.arrowHeadPreference = 2
        c.mouseDown(with: try mouse(c, .leftMouseDown, start, flags: [.option]))
        c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 240, y: 170), flags: [.option, .shift]))
        c.flagsChanged(with: try key(c, 58, type: .flagsChanged))
        c.mouseUp(with: try mouse(c, .leftMouseUp, end))
        try expect(c.document.elements.last!.pathCommands[3] == .line(to: CGPoint(x: 240, y: 90)), "Releasing Option restores End while retaining the last Shift-constrained endpoint")
    }
    static func textCompletionKeys() throws {
        // Independent original machine-code masks: 0x80000 Option, 0x200000
        // numericPad, and device-only flags below 0x10000. Command is 0x100000.
        let cases: [(String, UInt16, UInt, Bool)] = [
            ("Escape", 53, 0, true), ("modified Escape", 53, 0x140000, true),
            ("Option Return", 36, 0x80000, true), ("Shift Option Return", 36, 0xa0000, true),
            ("Command Option Return", 36, 0x180000, true),
            ("ordinary Return", 36, 0, false), ("Shift Return", 36, 0x20000, false),
            ("Command Return", 36, 0x100000, false), ("Control Return", 36, 0x40000, false),
            ("numericPad Return keycode", 36, 0x200000, false),
            ("bare Enter", 76, 0, true), ("device-only Enter", 76, 0x80, true),
            ("keypad Enter", 76, 0x200000, true), ("Shift keypad Enter", 76, 0x220000, true),
            ("Command keypad Enter", 76, 0x300000, true),
            ("Shift Enter without keypad flag", 76, 0x20000, false),
            ("Command Enter without keypad flag", 76, 0x100000, false),
            ("Caps Lock Enter without keypad flag", 76, 0x10000, false)
        ]
        try expect(NSEvent.ModifierFlags.option.rawValue == 0x80000 && NSEvent.ModifierFlags.numericPad.rawValue == 0x200000 && NSEvent.ModifierFlags.command.rawValue == 0x100000,
                   "Modern AppKit names match the recovered original masks")
        for (name, code, raw, commits) in cases {
            let c = canvas(NSSize(width: 700, height: 400)); let window = host(c); defer { window.close() }
            var text = SketchElement(kind: .text); text.text = "Before"
            text.rect = CGRect(x: 50, y: 50, width: 250, height: 70); text.color = SketchColor(.blue)
            c.document.elements = [text]; c.tool = .select
            let before = c.document
            c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 60, y: 60), clicks: 2))
            let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
            editor.insertText("Pending", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            let typing = editor.undoManager
            try expect(c.convertSelectedTextFonts({ _ in NSFont(name: "Courier-Bold", size: 34) }, outline: false, shadow: true), "Stage typography for \(name)")
            let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
            grip.mouseDragged(with: TextGripDragEvent(20, 12))
            let pending = try SketchDocument.decode(c.snapshotDocumentData())
            let characters = code == 53 ? "\u{1b}" : (code == 76 ? "\u{3}" : "\r")
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: raw), timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code)!
            editor.keyDown(with: event)
            if commits {
                try expect(editor.superview == nil && grip.superview == nil && window.firstResponder === c && c.activeEditorUndoManager == nil,
                           "\(name) completes and returns focus to canvas")
                try expect(c.document == pending && !c.hasPendingTextChanges, "\(name) preserves words typography color effects and grip movement")
                c.undo(); try expect(c.document == before && !c.editingUndoManager.canUndo, "\(name) commits exactly one drawing Undo")
                c.redo(); try expect(c.document == pending, "\(name) Redo restores the complete edit")
            } else {
                try expect(editor.superview === c && grip.superview === c && window.firstResponder === editor && editor.undoManager === typing,
                           "\(name) retains native text input focus and history")
                try expect(c.document == before && !c.editingUndoManager.canUndo && c.hasPendingTextChanges,
                           "\(name) never commits pending work")
                if code == 36 && raw == 0 {
                    try expect(editor.string == "Pending\n", "Ordinary Return inserts a native line break")
                }
                c.cancelOperation(nil); try expect(c.document == before && !c.editingUndoManager.canUndo, "Cancel after \(name) restores source")
            }
        }
    }
    static func naturalTextLayout() throws {
        let c = canvas(NSSize(width: 1400, height: 600)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text)
        text.text = "Old text"; text.fontName = "Courier-Bold"; text.fontSize = 30
        text.rect = CGRect(x: 40, y: 50, width: 90, height: 90)
        c.document.elements = [text]; c.tool = .select
        let before = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 50, y: 60), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        editor.undoManager!.groupsByEvent = false
        try expect(editor.isHorizontallyResizable && editor.isVerticallyResizable && editor.textContainer?.widthTracksTextView == false && editor.textContainer?.heightTracksTextView == false,
                   "Recovered unbounded container resizes in both dimensions")
        try expect(editor.textContainerInset == NSSize(width: 4, height: 2) && editor.textContainer?.lineFragmentPadding == 2,
                   "Recovered inset and line padding")
        try expect((try SketchDocument.decode(c.snapshotDocumentData())) == before, "Opening an imported fixed box never rewrites its stored model")
        let long = "A long annotation grows without automatic word wrapping"
        editor.breakUndoCoalescing()
        editor.undoManager!.beginUndoGrouping()
        editor.insertText(long, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.undoManager!.endUndoGrouping()
        let longFrame = editor.frame
        let snapshot = try SketchDocument.decode(c.snapshotDocumentData())
        let font = NSFont(name: text.fontName, size: 30)!
        let width = (long as NSString).size(withAttributes: [.font: font]).width
        try expect(abs(snapshot.elements[0].rect.width - width - 16) < 0.001 && longFrame.width > text.rect.width * 5,
                   "Thirty-point natural width includes two six-point margins, without wrapping")
        var lineCount = 0
        editor.layoutManager!.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: editor.layoutManager!.numberOfGlyphs)) { _, _, _, _, _ in lineCount += 1 }
        try expect(lineCount == 1, "Long text stays on one native line")
        editor.breakUndoCoalescing()
        editor.undoManager!.beginUndoGrouping()
        editor.insertText("First\nSecond\n", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.undoManager!.endUndoGrouping()
        try expect(editor.frame.height > longFrame.height * 2 && editor.frame.width < longFrame.width,
                   "Explicit rows, including trailing newline, grow height and shrink width")
        let multiline = try SketchDocument.decode(c.snapshotDocumentData())
        c.zoom = 0.5
        try expect((try SketchDocument.decode(c.snapshotDocumentData())) == multiline && editor.font!.pointSize == 18,
                   "Readable display font at small zoom does not change source text size")
        editor.breakUndoCoalescing()
        editor.undoManager!.beginUndoGrouping()
        editor.insertText("Hi", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.undoManager!.endUndoGrouping()
        let shortFrame = editor.frame
        try expect(shortFrame.height < longFrame.height && shortFrame.width < longFrame.width, "Shorter words shrink both dimensions after zoom")
        editor.breakUndoCoalescing()
        c.activeEditorUndoManager?.undo()
        try expect(editor.string == "First\nSecond\n" && editor.frame.height > shortFrame.height * 2,
                   "Native typing Undo restores words and grows their live box: \(editor.string), \(editor.frame), short \(shortFrame)")
        c.activeEditorUndoManager?.redo()
        try expect(editor.string == "Hi" && editor.frame == shortFrame, "Typing Redo restores short fitted box")
        let pending = try SketchDocument.decode(c.snapshotDocumentData())
        c.commitPendingTextEditing()
        try expect(c.document == pending, "Commit uses source font dimensions independently of display zoom")
        let data = try c.documentData(); let reopened = canvas(); try reopened.loadDocument(data: data)
        try expect(reopened.document == pending, "Natural text box saves and reopens exactly")
        c.undo(); try expect(c.document == before && !c.editingUndoManager.canUndo, "One canvas Undo restores original imported bounds and words")
        c.redo(); try expect(c.document == pending, "Canvas Redo restores the fitted edit")
    }
    static func textGripGeometry() throws {
        let c = canvas(NSSize(width: 600, height: 400)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Transformed annotation"
        text.rect = CGRect(x: 60.25, y: 50.75, width: 210.5, height: 70.25)
        text.transform = SketchTransform(a: 0.8, b: 0.6, c: -0.6, d: 0.8, tx: 90, ty: 20)
        text.groupID = UUID(); text.fontName = "Courier-Bold"; text.fontSize = 37
        text.shadowed = true; text.outlined = false; text.color = SketchColor(.blue)
        c.document.elements = [text]; c.document.renderSize = CGSize(width: 900, height: 200); c.zoom = 2; c.tool = .select
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: text.bounds.midX, y: text.bounds.midY), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        let expandedFrame = editor.frame
        editor.frame = CGRect(origin: expandedFrame.origin, size: CGSize(width: expandedFrame.width, height: expandedFrame.height + 40))
        try expect(editor.frame == expandedFrame, "Recovered frame setter retains natural sizing instead of an arbitrary requested height")
        let observedFrame = CGRect(x: editor.frame.minX - 11, y: editor.frame.minY - 3,
                                   width: editor.frame.width + 15, height: editor.frame.height + 6).integral.insetBy(dx: -5, dy: -5)
        try expect(grip.frame == observedFrame, "Native text-container frame changes immediately resize the attached grip")
        let baseFrame = editor.frame
        grip.mouseDragged(with: TextGripDragEvent(45, 20))
        var expected = text; expected.translate(x: 15, y: 20)
        try expect(editor.frame == baseFrame.offsetBy(dx: 45, dy: 20), "Nonuniform display scale converts each delta independently while preserving grown editor height")
        let snapshot = try SketchDocument.decode(c.snapshotDocumentData())
        try expect(snapshot.elements[0] == expected && c.document.elements[0] == text,
                   "World translation preserves rotation, local wrap bounds, group, color and effects")
        c.zoom = 0.5
        let frame = CGRect(x: expected.bounds.minX * c.displayScale.width, y: expected.bounds.minY * c.displayScale.height,
                           width: expected.bounds.width * c.displayScale.width, height: expected.bounds.height * c.displayScale.height)
        try expect(abs(editor.frame.minX - frame.minX) < 0.00001 && abs(editor.frame.minY - frame.minY) < 0.00001,
                   "Zoom retains source-space pending placement rather than jumping back")
        let fit = OriginalTextGeometry.size(text: editor.string, font: editor.font!)
        try expect(abs(editor.frame.width - fit.width) < 0.001 && abs(editor.frame.height - fit.height) < 0.001 && editor.frame.height < baseFrame.height,
                   "Zoom recomputes the fitted editor using its readable displayed font, allowing shrinkage")
        let expectedGrip = CGRect(x: frame.minX - 11, y: frame.minY - 3, width: fit.width + 15, height: fit.height + 6)
            .integral.insetBy(dx: -5, dy: -5)
        try expect(grip.frame == expectedGrip, "Fractional editor frames round grip outwards after zoom; editor \(editor.frame), expected editor \(frame), grip \(grip.frame), expected grip \(expectedGrip)")
        let start = CGPoint(x: expected.bounds.minX - 5, y: expected.bounds.midY)
        grip.mouseDown(with: try mouse(c, .leftMouseDown, start))
        let end = CGPoint(x: start.x + 20, y: start.y + 12)
        grip.mouseDragged(with: try mouse(c, .leftMouseDragged, end))
        expected.translate(x: 20, y: 12)
        grip.mouseDragged(with: try mouse(c, .leftMouseDragged, end))
        grip.mouseUp(with: try mouse(c, .leftMouseUp, end))
        try expect((try SketchDocument.decode(c.snapshotDocumentData())).elements[0] == expected,
                   "Location-only native events move in fixed parent space exactly once")
        let data = try c.documentData()
        let reopened = canvas(); try reopened.loadDocument(data: data)
        try expect(reopened.document.elements[0] == expected && reopened.document.outputSize == CGSize(width: 900, height: 200),
                   "Save and reopen preserve transformed editable placement and normal output")
        c.undo(); try expect(c.document.elements[0] == text, "Movement undo leaves rotated original exact")
    }
    static func textGripCancellation() throws {
        let c = canvas(NSSize(width: 500, height: 300)); let window = host(c); defer { window.close() }
        c.tool = .text
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 80, y: 70)))
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 80, y: 70)))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        editor.insertText("New and moved", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let frame = editor.frame, data = try c.snapshotDocumentData()
        var changes = 0; c.onChange = { changes += 1 }
        for delta in [TextGripDragEvent(0, 0), TextGripDragEvent(.nan, 4), TextGripDragEvent(2, .infinity), TextGripDragEvent(2_000_000, 0)] {
            grip.mouseDragged(with: delta)
        }
        try expect(editor.frame == frame && (try c.snapshotDocumentData()) == data && changes == 0,
                   "Zero, nonfinite and unrepresentable moves do not dirty or corrupt pending editor")
        grip.mouseDragged(with: TextGripDragEvent(-14, 22))
        try expect(changes == 1 && c.hasPendingTextChanges, "New annotation also supports grip movement")
        c.cancelOperation(nil)
        try expect(c.document.elements.isEmpty && editor.superview == nil && grip.superview == nil && !c.editingUndoManager.canUndo && changes == 2,
                   "Explicit cancel abandons newly created text and position without a phantom Undo")
        var existing = SketchElement(kind: .text); existing.text = "Existing"
        existing.rect = CGRect(x: 60, y: 60, width: 200, height: 60)
        c.document.elements = [existing]; c.tool = .select
        c.setBackgroundColor(.blue); c.setBackgroundColor(.green); c.undo()
        let original = c.document, undoName = c.editingUndoManager.undoActionName, redoName = c.editingUndoManager.redoActionName
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 70, y: 70), clicks: 2))
        let secondEditor = c.subviews.compactMap { $0 as? NSTextView }.first!
        let secondGrip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        secondEditor.isContinuousSpellCheckingEnabled = false
        secondGrip.mouseDragged(with: TextGripDragEvent(20, 30))
        c.cancelOperation(nil)
        try expect(c.document == original && c.editingUndoManager.undoActionName == undoName && c.editingUndoManager.redoActionName == redoName,
                   "Existing annotation cancel leaves prior Undo and Redo unchanged")
        c.redo(); try expect(c.document.backgroundColor == SketchColor(.green), "Prior redo remains usable after grip cancel")
    }
    static func textGripSelectionChrome() throws {
        let c = canvas(NSSize(width: 500, height: 300)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Move this text"
        text.rect = CGRect(x: 80, y: 60, width: 220, height: 60)
        let shape = rectangle(CGRect(x: 350, y: 180, width: 60, height: 50), color: .blue)
        c.document.elements = [text, shape]; c.tool = .select; c.selection = [text.id]
        let before = c.document
        let reference = canvas(c.canvasSize)
        reference.document = before; reference.document.elements.removeAll { $0.id == text.id }
        func rendered(_ view: CanvasView) throws -> Data {
            guard let data = SketchRenderer.bitmap(size: view.bounds.size, draw: { view.draw(view.bounds) })?
                .representation(using: .png, properties: [:]) else {
                throw Failure(description: "Selection chrome render")
            }
            return data
        }
        let selected = try rendered(c)
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 90, y: 70), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        try expect(try rendered(c) == rendered(reference), "Active text is represented by its native editor and grip, without stale selection pixels")
        try expect(c.selection == [text.id] && c.selectionBounds == text.bounds && c.document == before,
                   "Hiding editing chrome preserves committed selection geometry and document")
        grip.mouseDragged(with: TextGripDragEvent(45, 25))
        try expect(try rendered(c) == rendered(reference), "Movement does not leave resize handles at the old text position")
        c.selection = [text.id, shape.id]; reference.selection = [shape.id]
        try expect(try rendered(c) == rendered(reference), "Other selected artwork retains its own resize handles while text is pending")
        c.zoom = 0.75; reference.zoom = 0.75
        try expect(try rendered(c) == rendered(reference), "Zoom retains only non-editor chrome at the new display scale")
        try expect(window.firstResponder === editor && c.hasPendingTextChanges && !c.editingUndoManager.canUndo,
                   "Chrome drawing and zoom preserve typing focus and pending movement history")
        let moved = try SketchDocument.decode(c.snapshotDocumentData())
        c.commitPendingTextEditing(); reference.document = moved; reference.selection = c.selection
        try expect(try rendered(c) == rendered(reference), "Committed text regains resize handles at its moved bounds")
        try expect(editor.superview == nil && grip.superview == nil && c.document == moved,
                   "Commit removes native editor and grip without losing the moved document")
        c.undo(); c.selection = [text.id]; c.zoom = 1
        try expect(c.document == before && (try rendered(c)) == selected, "Undo restores original text and selection pixels")
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 90, y: 70), clicks: 2))
        c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!.mouseDragged(with: TextGripDragEvent(-20, 30))
        c.cancelOperation(nil)
        try expect(c.document == before && c.selection == [text.id] && (try rendered(c)) == selected,
                   "Cancel restores original selection chrome without retaining pending editor geometry")
    }
    static func liveTextFontConversion() throws {
        let c = canvas(NSSize(width: 600, height: 400))
        var a = SketchElement(kind: .text); a.text = "Bold"; a.fontName = "Helvetica-Bold"; a.fontSize = 23
        a.outlined = false; a.shadowed = true; a.rect = CGRect(x: 30, y: 30, width: 180, height: 70)
        var b = a; b.id = UUID(); b.text = "Italic"; b.fontName = "Helvetica-Oblique"; b.fontSize = 42
        b.outlined = true; b.shadowed = false; b.rect.origin.y = 150
        let shape = rectangle(CGRect(x: 350, y: 40, width: 150, height: 100), color: .blue)
        c.document.elements = [a,b,shape]; c.selection = [a.id,b.id,shape.id]
        let before = c.document; let manager = NSFontManager.shared
        try expect(c.convertSelectedTextFonts({ manager.convert($0, toFamily: "Courier") }), "Valid per-item family conversion")
        let changed = c.document
        for (old,new) in zip([a,b],changed.elements.prefix(2)) {
            let font = NSFont(name: new.fontName, size: new.fontSize)!
            let original = NSFont(name: old.fontName, size: old.fontSize)!
            try expect(font.familyName == "Courier" && new.fontSize == old.fontSize && manager.traits(of: font).intersection([.boldFontMask, .italicFontMask]) == manager.traits(of: original).intersection([.boldFontMask, .italicFontMask]), "Family conversion keeps each distinct size and face traits")
            try expect(new.outlined == old.outlined && new.shadowed == old.shadowed && new.color == old.color && new.rect.origin == old.rect.origin && new.transform == old.transform, "Mixed flags color anchor and transform are retained")
        }
        try expect(changed.elements[2] == shape, "Font panel never restyles a selected shape")
        c.undo(); try expect(c.document == before, "Mixed family change is one Undo"); c.redo(); try expect(c.document == changed, "Mixed conversion Redo")
        let history = c.editingUndoManager.undoActionName, selection = c.selection
        var notifications = 0; c.onChange = { notifications += 1 }
        try expect(!c.convertSelectedTextFonts({ $0.pointSize == 42 ? nil : manager.convert($0, toSize: 30) }, outline: false), "A rejected later font invalidates the whole change")
        try expect(c.document == changed && c.selection == selection && c.editingUndoManager.undoActionName == history && notifications == 0, "Rejected conversion has no partial mutation history or dirty callback")
        try expect(c.convertSelectedTextFonts(nil, outline: true), "Effect-only conversion")
        try expect(c.document.elements.prefix(2).allSatisfy(\.outlined) && c.document.elements[0].shadowed && !c.document.elements[1].shadowed, "Explicit outline changes without flattening mixed shadows")
    }
    static func originalTextEffects() throws {
        // Expected values come from original constants and SSE outlineSize,
        // rather than today's renderer or an image generated by that renderer.
        let outlineCases: [(CGFloat, CGFloat)] = [(10,40),(18,24),(20,20),(40,20),(80,10),(100,8),(4096,0.1953125)]
        for (size, expected) in outlineCases {
            try expect(abs(OriginalTextEffects.outlinePercentage(fontSize: size)-expected) < 0.00001, "Original font outline width at \(size)")
        }
        for color in [NSColor.black, .blue, .red] {
            try expect(OriginalTextEffects.outlineColor(SketchColor(color)) == .white, "Dark text has a contrasting white outline")
        }
        for color in [NSColor.white, .yellow, .green] {
            try expect(OriginalTextEffects.outlineColor(SketchColor(color)) == .black, "Bright text has a contrasting black outline")
        }
        let shadow = OriginalTextEffects.shadow()
        try expect(shadow.shadowOffset == NSSize(width: 0, height: -1) && shadow.shadowBlurRadius == 3 &&
                   abs((shadow.shadowColor as! NSColor).alphaComponent-0.8) < 0.00001, "Original text shadow geometry and opacity")
        var text = SketchElement(kind: .text); text.text = "Outline"; text.fontSize = 40
        text.rect = CGRect(x: 30, y: 30, width: 220, height: 90); text.shadowed = true
        text.color = SketchColor(NSColor.yellow.withAlphaComponent(0.25))
        var document = SketchDocument(size: CGSize(width: 300, height: 160)); document.backgroundColor = .clear; document.elements = [text]
        let bitmap = SketchRenderer.bitmap(document: document)!
        var painted = 0, maximumAlpha: CGFloat = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
            maximumAlpha = max(maximumAlpha, alpha); if alpha > 0 { painted += 1 }
        } }
        try expect(painted > 300 && maximumAlpha <= 0.255 && maximumAlpha > 0.24, "Text fill outline and shadow share the annotation alpha instead of opaque rims")
        var compact = SketchDocument(size: CGSize(width: 500, height: 100))
        var courier = text; courier.fontName = "Courier-Bold"; courier.fontSize = 37
        courier.rect = CGRect(x: 30, y: 10, width: 430, height: 70)
        courier.text = "Second mixed font"; courier.color = SketchColor(.red); courier.shadowed = false
        compact.elements = [courier]
        let compactBitmap = SketchRenderer.bitmap(document: compact)!
        var coloredFill = 0
        for y in 0..<100 { for x in 0..<500 {
            let pixel = compactBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if pixel.redComponent > 0.8 && pixel.greenComponent < 0.3 && pixel.blueComponent < 0.3 { coloredFill += 1 }
        } }
        try expect(coloredFill > 500, "Original-sized outlined Courier text keeps its colored fill visible in a compact annotation")
        let c = canvas(document.size); c.document = document; c.tool = .select
        let window = host(c); defer { window.close() }
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 40, y: 40), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        try expect((editor.typingAttributes[.strokeColor] as? NSColor) == .black &&
                   (editor.typingAttributes[.strokeWidth] as? CGFloat) == -20, "Native pending editor uses bright text outline and original width")
        let typing = editor.undoManager; editor.insertText("Typed", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        c.applyColorToSelection(.blue.withAlphaComponent(0.25))
        try expect((editor.typingAttributes[.strokeColor] as? NSColor) == .white && editor.undoManager === typing && window.firstResponder === editor, "Live recolor changes outline contrast without replacing typing history or focus")
        editor.breakUndoCoalescing(); typing?.undo()
        try expect(editor.string == text.text && (editor.typingAttributes[.strokeColor] as? NSColor) == .white, "Typing Undo retains the staged adaptive outline")
        try expect(c.selectedTextElements[0].color.alpha == 0.25 && c.document == document, "Effects never rewrite pending source alpha or committed artwork")
        // Selection foreground is system-owned; inspect the unselected glyph fill.
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let editorBitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds)!
        editor.cacheDisplay(in: editor.bounds, to: editorBitmap)
        var editorFill = 0
        for y in 0..<editorBitmap.pixelsHigh { for x in 0..<editorBitmap.pixelsWide {
            let pixel = editorBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            // Cache display may composite the transparent editor over its white parent.
            if pixel.blueComponent > pixel.redComponent + 0.15 && pixel.blueComponent > pixel.greenComponent + 0.15 && pixel.alphaComponent > 0.2 { editorFill += 1 }
        } }
        try expect(editorFill > 50, "Native editor paints colored glyph interiors after the thick outline pass: \(editorFill), \(editor.frame), \(editor.string)")
        c.commitPendingTextEditing(); try expect(c.document.elements[0].color.alpha == 0.25, "Commit retains translucent text")
        c.undo(); try expect(c.document == document, "Recolor and pending words remain one document Undo")
    }
    static func pendingFontPanelStyle() throws {
        let c = canvas(NSSize(width: 600, height: 400)); let window = host(c); defer { window.close() }
        var text = SketchElement(kind: .text); text.text = "Original"; text.fontName = "Courier-Bold"; text.fontSize = 24
        text.outlined = false; text.shadowed = false; text.rect = CGRect(x: 50, y: 50, width: 230, height: 60)
        var other = text; other.id = UUID(); other.fontSize = 37; other.rect.origin.y = 200; other.outlined = true
        let shape = rectangle(CGRect(x: 350, y: 80, width: 120, height: 100), color: .blue)
        c.document.elements = [text,other,shape]; c.tool = .select; let before = c.document
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 60, y: 60), clicks: 2))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!, typing = editor.undoManager
        let grip = c.subviews.first { $0.accessibilityIdentifier() == "text-grip" }!
        editor.insertText("Typed while Fonts stays open", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let caret = editor.selectedRange(); c.selection = [text.id,other.id,shape.id]
        try expect(c.convertSelectedTextFonts({ NSFont(name: "Helvetica-Bold", size: $0.pointSize + 10) }, shadow: true), "Live style change")
        try expect(c.document == before && editor.superview === c && window.firstResponder === editor && editor.undoManager === typing && editor.selectedRange() == caret && !c.editingUndoManager.canUndo, "Font changes stay pending without replacing the editor caret or typing history")
        try expect(editor.font?.fontName == "Helvetica-Bold" && editor.font?.pointSize == 34 && c.hasPendingTextChanges, "Native field reflects the staged source font immediately")
        try expect(!editor.drawsBackground && editor.typingAttributes[.shadow] is NSShadow && editor.typingAttributes[.strokeWidth] == nil,
                   "Live editor displays shadow without an outline or an opaque editing background")
        editor.breakUndoCoalescing(); typing?.undo()
        try expect(editor.string == "Original", "Native typing Undo restores the original words")
        try expect(c.selectedTextElements[0].fontSize == 34, "Typing Undo retains the staged source font")
        try expect(editor.font?.fontName == "Helvetica-Bold" && editor.font?.pointSize == 34,
                   "Typing Undo must retain live displayed font; actual \(editor.font?.fontName ?? "nil") \(editor.font?.pointSize ?? 0)")
        try expect(editor.textStorage?.attribute(.shadow, at: 0, effectiveRange: nil) is NSShadow &&
                   editor.textStorage?.attribute(.strokeWidth, at: 0, effectiveRange: nil) == nil,
                   "Typing Undo retains the live effects on restored glyphs")
        typing?.redo()
        try expect(editor.string == "Typed while Fonts stays open" && editor.font?.pointSize == 34 && window.firstResponder === editor,
                   "Typing Redo remains usable after a live font action")
        grip.mouseDragged(with: TextGripDragEvent(30, 20)); c.zoom = 0.5
        try expect(editor.font?.pointSize == 18 && c.selectedTextElements[0].fontSize == 34 && c.selectedTextElements[1].fontSize == 47, "Editor readability floor and zoom do not corrupt source font sizes")
        let pending = try SketchDocument.decode(c.snapshotDocumentData())
        try expect(pending.elements[0].text == editor.string && pending.elements[0].transform.tx == 30 && pending.elements[0].transform.ty == 20 && pending.elements[0].fontSize == 34 && !pending.elements[0].outlined && pending.elements[0].shadowed, "Recovery includes live text font effects and grip placement")
        try expect(pending.elements[1].fontSize == 47 && pending.elements[1].outlined && pending.elements[1].shadowed && pending.elements[2] == shape, "Other selected text styles are staged while shapes remain exact")
        let reference = canvas(c.canvasSize); reference.document = pending; reference.document.elements.removeAll { $0.id == text.id }
        reference.selection = [other.id,shape.id]; reference.zoom = c.zoom
        let actualPixels = SketchRenderer.bitmap(size: c.bounds.size) { c.draw(c.bounds) }!.representation(using: .png, properties: [:])
        let expectedPixels = SketchRenderer.bitmap(size: reference.bounds.size) { reference.draw(reference.bounds) }!.representation(using: .png, properties: [:])
        try expect(actualPixels == expectedPixels, "Other selected fonts and their resize handles render live before the editor transaction is committed")
        let reopened = canvas(); try reopened.loadDocument(data: c.documentData())
        try expect(c.document == pending && reopened.document == pending && editor.superview == nil && grip.superview == nil, "Save completes and round-trips all staged text style changes")
        c.undo(); try expect(c.document == before, "One document Undo restores the pre-editor text font and placement")
        c.redo(); try expect(c.document == pending, "One Redo restores the combined editor transaction")
    }
    static func pendingEmptyFontStyle() throws {
        let c = canvas(NSSize(width: 400, height: 250)); let window = host(c); defer { window.close() }
        c.setBackgroundColor(.blue); c.setBackgroundColor(.green); c.undo(); let before = c.document
        let undoName = c.editingUndoManager.undoActionName, redoName = c.editingUndoManager.redoActionName
        c.tool = .text; c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 40, y: 40)))
        let editor = c.subviews.compactMap { $0 as? NSTextView }.first!
        try expect(c.convertSelectedTextFonts({ _ in NSFont(name: "Courier-Bold", size: 37) }, outline: false, shadow: false), "Empty new field accepts a live font")
        try expect(editor.font?.fontName == "Courier-Bold" && editor.font?.pointSize == 37 && editor.string.isEmpty && c.selectedTextElements[0].fontSize == 37, "New empty editor shows the requested font before typing")
        editor.insertText("New styled text", replacementRange: NSRange(location: 0, length: 0))
        let staged = try SketchDocument.decode(c.snapshotDocumentData())
        try expect(staged.elements[0].fontSize == 37 && !staged.elements[0].outlined && !staged.elements[0].shadowed, "First typing retains the staged empty-field style")
        c.cancelOperation(nil)
        try expect(c.document == before && c.editingUndoManager.undoActionName == undoName && c.editingUndoManager.redoActionName == redoName, "Cancelling live style and new typing preserves prior Undo and Redo")
        c.redo(); try expect(c.document.backgroundColor == SketchColor(.green), "Prior redo still executes after font-panel cancellation")
    }
    static func controlEraser() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        c.setBackground(backdrop()); c.tool = .arrow; c.strokeWidth = 12
        var line = SketchElement(kind: .line)
        line.points = [CGPoint(x: 10, y: 40), CGPoint(x: 90, y: 40)]
        line.color = SketchColor(.red); line.strokeWidth = 4
        c.document.elements = [line]; c.editingUndoManager.removeAllActions()
        let original = c.document
        c.flagsChanged(with: try key(c, 59, type: .flagsChanged, flags: [.control]))
        try expect(c.effectiveTool == .eraser && c.tool == .arrow, "Control temporarily selects Eraser")
        c.rightMouseDown(with: try mouse(c, .rightMouseDown, CGPoint(x: 50, y: 30), flags: [.control]))
        c.rightMouseDragged(with: try mouse(c, .rightMouseDragged, CGPoint(x: 50, y: 50), flags: [.control]))
        c.rightMouseUp(with: try mouse(c, .rightMouseUp, CGPoint(x: 50, y: 50), flags: [.control]))
        try expect(c.document.elements.count == 2 && c.document.elements.allSatisfy { $0.kind == .path },
                   "Control secondary-button erasing creates independent vector pieces")
        try expect(try pixel(c, 50, 40).blueComponent > 0.9 && pixel(c, 20, 40).redComponent > 0.9,
                   "Eraser exposes protected photo, retaining line pixels elsewhere")
        c.undo(); try expect(c.document == original, "Control erasing is one exact undo")
        c.flagsChanged(with: try key(c, 59, type: .flagsChanged))
        try expect(c.effectiveTool == .arrow, "Releasing Control restores current tool")
        c.flagsChanged(with: try key(c, 55, type: .flagsChanged, flags: [.control, .command]))
        try expect(c.effectiveTool == .select, "Original Command cursor takes precedence over Control")
        c.tool = .fill
        c.flagsChanged(with: try key(c, 59, type: .flagsChanged, flags: [.control]))
        try expect(c.effectiveTool == .eraser, "Recovered setModifiers index 4 exempts Text, so Control Fill uses Eraser")
        c.rightMouseDown(with: try mouse(c, .rightMouseDown, CGPoint(x: 50, y: 30), flags: [.control]))
        c.rightMouseDragged(with: try mouse(c, .rightMouseDragged, CGPoint(x: 50, y: 50), flags: [.control]))
        c.rightMouseUp(with: try mouse(c, .rightMouseUp, CGPoint(x: 50, y: 50), flags: [.control]))
        try expect(c.document.elements.count == 2 && c.document.elements.allSatisfy { $0.kind == .path }, "Control Fill erases the vector instead of flood-filling its background")
        c.undo(); try expect(c.document == original, "Control Fill erasure remains one exact Undo")
        c.tool = .text
        try expect(c.effectiveTool == .text, "Recovered Text exception retains typing under Control")
        c.flagsChanged(with: try key(c, 55, type: .flagsChanged, flags: [.control, .command]))
        try expect(c.effectiveTool == .select, "Command still overrides the Text exception")
    }
    static func spacePan() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        c.setBackground(backdrop()); c.setZoom(2)
        var shape = rectangle(CGRect(x: 40, y: 40, width: 15, height: 12))
        var text = SketchElement(kind: .text)
        text.text = "X"; text.rect = CGRect(x: 65, y: 5, width: 25, height: 35)
        shape.groupID = UUID(); text.groupID = shape.groupID
        c.document.elements = [shape, text]; c.selection = [shape.id]
        c.cropRect = CGRect(x: 5, y: 5, width: 50, height: 40)
        c.editingUndoManager.removeAllActions()
        let original = c.document, originalCrop = c.cropRect, originalPNG = c.imageData(format: "png")
        let viewport = (c.enclosingScrollView?.contentView.bounds)!
        c.keyDown(with: try key(c, 49))
        try drag(c, from: CGPoint(x: 35, y: 30), to: CGPoint(x: 45, y: 42))
        c.keyUp(with: try key(c, 49, type: .keyUp))
        var expectedShape = shape, expectedText = text
        expectedShape.translate(x: 10, y: 12); expectedText.translate(x: 10, y: 12)
        try expect(c.document.elements == [expectedShape, expectedText] && c.selection == [shape.id],
                   "Space moves all vector/text geometry, preserving IDs/groups/selection at zoom")
        try expect(c.cropRect == originalCrop!.offsetBy(dx: 10, dy: 12) && c.canvasSize == original.size,
                   "Space preserves dimensions and translates crop with content")
        try expect(c.enclosingScrollView?.contentView.bounds == viewport, "Space moves document contents rather than viewport")
        try expect(try pixel(c, 20, 20).greenComponent > 0.9 && pixel(c, 10, 10).redComponent > 0.9 &&
                   pixel(c, 52, 55).redComponent > 0.9, "Snap and annotations move together, leaving white uncovered pixels")
        let panned = c.document
        c.undo(); try expect(c.document == original && c.cropRect == originalCrop && !c.editingUndoManager.canUndo,
                             "Space pan has one exact undo")
        c.redo(); try expect(c.document == panned, "Space pan redo restores pixels and geometry")
        c.undo(); c.editingUndoManager.removeAllActions()
        c.keyDown(with: try key(c, 49))
        try drag(c, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20))
        try expect(c.document == original && !c.editingUndoManager.canUndo, "Space click is not an edit")
        try drag(c, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 20))
        c.keyUp(with: try key(c, 49, type: .keyUp))
        let saved = try c.documentData()
        try expect(try CanvasView.validatedDocumentData(saved) == c.document,
                   "Native supplement validator accepts the full hidden pan source")
        var invalidFile = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        guard var invalidBackground = invalidFile["canvasPanBackground"] as? [String: Any] else {
            throw Failure(description: "Serialized pan source must be present")
        }
        invalidBackground["sourcePNG"] = Data([1, 2, 3]).base64EncodedString()
        invalidFile["canvasPanBackground"] = invalidBackground
        let invalidData = try JSONSerialization.data(withJSONObject: invalidFile)
        do {
            _ = try CanvasView.validatedDocumentData(invalidData)
            throw Failure(description: "Malformed hidden pan pixels must not pass native supplement validation")
        } catch SketchDocumentError.invalidDocument { }
        let loaded = canvas(); try loaded.loadDocument(data: saved)
        let secondWindow = host(loaded); defer { secondWindow.close() }
        loaded.keyDown(with: try key(loaded, 49))
        try drag(loaded, from: CGPoint(x: 90, y: 20), to: CGPoint(x: 20, y: 20))
        loaded.keyUp(with: try key(loaded, 49, type: .keyUp))
        try expect(loaded.document.elements == original.elements && loaded.imageData(format: "png") == originalPNG,
                   "Offscreen snap pixels survive pan/save/reopen/pan back without clipping loss")
    }
    static func toolAndColorGestures() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        c.tool = .ellipse; c.setBackground(backdrop())
        c.document.elements = [rectangle(CGRect(x: 35, y: 25, width: 30, height: 30), color: .red.withAlphaComponent(0.5))]
        c.editingUndoManager.removeAllActions()
        let original = c.document
        var tools: [SketchTool] = [], colors: [SketchColor] = [], dirty = 0
        c.onToolChange = { tools.append($0) }; c.onColorChange = { colors.append(SketchColor($0)) }; c.onChange = { dirty += 1 }
        c.keyDown(with: try key(c, 48)); c.keyDown(with: try key(c, 48, repeatKey: true))
        try expect(c.tool == .brush && tools == [.brush], "Tab selects Pencil; autorepeat cannot toggle back")
        c.keyDown(with: try key(c, 48))
        try expect(c.tool == .ellipse && tools == [.brush, .ellipse], "Tab restores remembered current tool")
        for tool in [SketchTool.brush, .fill, .eraser] {
            c.tool = tool; c.strokeColor = .black
            try drag(c, from: CGPoint(x: 45, y: 40), to: CGPoint(x: 45, y: 40), flags: [.option])
            try expect(SketchColor(c.strokeColor) == SketchColor(.red.withAlphaComponent(0.5)),
                       "Option \(tool) samples editable graphic color including alpha")
            try drag(c, from: CGPoint(x: 80, y: 60), to: CGPoint(x: 10, y: 10), flags: [.option])
            try expect(c.strokeColor.usingColorSpace(.deviceRGB)!.greenComponent > 0.9,
                       "Dragging Option eyedropper samples the new snap pixel")
        }
        c.strokeColor = .black; c.tool = .brush
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 80, y: 60), flags: [.option]))
        c.keyDown(with: try key(c, 53))
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 80, y: 60), flags: [.option]))
        try expect(SketchColor(c.strokeColor) == SketchColor(.black), "Escape restores eyedropper's prior color")
        try drag(c, from: CGPoint(x: 45, y: 40), to: CGPoint(x: 45, y: 40), flags: [.shift, .command])
        try expect(c.selection == [original.elements[0].id] && SketchColor(c.strokeColor) == SketchColor(.black),
                   "Evidence establishes Shift+Command cursor selection, not eyedropper")
        try expect(c.document == original && dirty == 0 && !c.editingUndoManager.canUndo && colors.count >= 7,
                   "Tool/color gestures notify shell UI without dirtying document or history")
    }
    static func optionDragCopy() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        var a = rectangle(CGRect(x: 15, y: 15, width: 30, height: 30))
        var b = rectangle(CGRect(x: 55, y: 15, width: 20, height: 25), color: .blue)
        a.groupID = UUID(); b.groupID = a.groupID; c.document.elements = [a, b]
        c.tool = .arrow; let original = c.document
        var dirty = 0; c.onChange = { dirty += 1 }
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 40, y: 40), flags: [.command, .option])
        let copied = c.document, copies = Array(copied.elements.dropFirst(2))
        try expect(Array(copied.elements.prefix(2)) == [a, b] && copies.count == 2, "Option cursor drag retains originals and copies entire contacted group")
        var ea = a, eb = b; ea.translate(x: 10, y: 10); eb.translate(x: 10, y: 10)
        ea.id = copies[0].id; eb.id = copies[1].id; ea.groupID = copies[0].groupID; eb.groupID = copies[1].groupID
        try expect(copies == [ea, eb] && copies[0].groupID == copies[1].groupID && copies[0].groupID != a.groupID &&
                   Set(copied.elements.map(\.id)).count == 4 && c.selection == Set(copies.map(\.id)),
                   "Copies preserve exact styles/geometry with independent IDs/group and selected copies")
        try expect(dirty == 1 && c.tool == .arrow, "Copy/move is one edit and Command tool is temporary")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "One undo removes copies and movement")
        c.redo(); try expect(c.document == copied, "Redo retains copied identities")
        c.undo(); c.editingUndoManager.removeAllActions(); let notifications = dirty
        try drag(c, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 30, y: 30), flags: [.command, .option])
        try expect(c.document == original && !c.editingUndoManager.canUndo && dirty == notifications,
                   "Option click without movement does not duplicate")
    }
    static func gestureCancellation() throws {
        let cases: [(SketchTool, CGPoint, CGPoint, NSEvent.ModifierFlags, Bool)] = [
            (.select, CGPoint(x: 40, y: 35), CGPoint(x: 50, y: 45), [], false),
            (.select, CGPoint(x: 60, y: 50), CGPoint(x: 75, y: 65), [], false),
            (.rectangle, CGPoint(x: 70, y: 60), CGPoint(x: 95, y: 75), [], false),
            (.eraser, CGPoint(x: 40, y: 10), CGPoint(x: 40, y: 65), [], false),
            (.crop, CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 70), [], false),
            (.select, CGPoint(x: 40, y: 35), CGPoint(x: 50, y: 45), [.option], false),
            (.arrow, CGPoint(x: 40, y: 35), CGPoint(x: 50, y: 45), [], true)
        ]
        for (tool, start, end, flags, pan) in cases {
            let c = canvas(); let window = host(c); defer { window.close() }
            c.setBackground(backdrop()); c.setBackgroundColor(.clear); c.undo()
            let shape = rectangle(CGRect(x: 20, y: 20, width: 40, height: 30))
            c.document.elements = [shape]; c.selection = [shape.id]
            c.cropRect = CGRect(x: 5, y: 5, width: 80, height: 60); c.tool = tool
            let original = c.document, crop = c.cropRect, selected = c.selection
            let undoName = c.editingUndoManager.undoActionName, redoName = c.editingUndoManager.redoActionName
            var dirty = 0; c.onChange = { dirty += 1 }
            if pan { c.keyDown(with: try key(c, 49)) }
            c.mouseDown(with: try mouse(c, .leftMouseDown, start, flags: flags))
            c.mouseDragged(with: try mouse(c, .leftMouseDragged, end, flags: flags))
            c.keyDown(with: try key(c, 53))
            c.mouseUp(with: try mouse(c, .leftMouseUp, end, flags: flags))
            if pan { c.keyUp(with: try key(c, 49, type: .keyUp)) }
            try expect(c.document == original && c.selection == selected && c.cropRect == crop && dirty == 0,
                       "Escape rolls back \(tool)/pan=\(pan) gesture and ignores delayed mouseUp")
            try expect(c.editingUndoManager.canUndo && c.editingUndoManager.canRedo &&
                       c.editingUndoManager.undoActionName == undoName && c.editingUndoManager.redoActionName == redoName,
                       "Cancelled gesture preserves existing undo and redo branches")
            c.redo(); try expect(c.document.backgroundColor == .clear, "Pre-existing redo still operates after cancelled gesture")
        }
    }
    static func linePolygon() throws {
        let c = canvas(NSSize(width: 200, height: 160)); let window = host(c); defer { window.close() }
        c.editingUndoManager.removeAllActions(); c.tool = .line
        func flags(_ f: NSEvent.ModifierFlags) throws { c.flagsChanged(with: try key(c, 58, type: .flagsChanged, flags: f)) }
        func click(_ p: CGPoint, _ f: NSEvent.ModifierFlags = [.option]) throws {
            c.mouseDown(with: try mouse(c, .leftMouseDown, p, flags: f))
            c.mouseUp(with: try mouse(c, .leftMouseUp, p, flags: f))
        }
        func move(_ p: CGPoint, _ f: NSEvent.ModifierFlags = [.option]) throws { c.mouseMoved(with: try mouse(c, .mouseMoved, p, flags: f)) }
        let a = CGPoint(x: 20, y: 20), b = CGPoint(x: 80, y: 20), d = CGPoint(x: 120, y: 90), e = CGPoint(x: 160, y: 40)
        // Plain drag without Option is still a two-point line.
        c.mouseDown(with: try mouse(c, .leftMouseDown, a)); c.mouseDragged(with: try mouse(c, .leftMouseDragged, b))
        c.mouseUp(with: try mouse(c, .leftMouseUp, b))
        try expect(c.document.elements.count == 1 && c.document.elements[0].points == [a, b], "plain drag makes a two-point line")
        c.editingUndoManager.removeAllActions(); c.document.elements = []
        // Option down arms polygon mode; clicks push vertices, releases and moves never commit.
        try flags([.option])
        try click(a); try move(CGPoint(x: 50, y: 60)); try click(b)
        c.mouseDown(with: try mouse(c, .leftMouseDown, d))
        c.mouseDragged(with: try mouse(c, .leftMouseDragged, CGPoint(x: 130, y: 100)))
        c.mouseUp(with: try mouse(c, .leftMouseUp, CGPoint(x: 130, y: 100)))
        try move(e)
        try expect(c.document.elements.isEmpty && !c.editingUndoManager.canUndo, "nothing is in the document before Option is released")
        // Shift snaps the rubber-band tip to 45 degrees from the previous vertex.
        try move(CGPoint(x: 190, y: 95), [.option, .shift])
        // Escape discards the pending polygon.
        c.keyDown(with: try key(c, 53))
        try expect(c.document.elements.isEmpty, "Escape drops the pending polygon")
        try click(a); try click(b); try click(d)
        try move(CGPoint(x: 150, y: 100))
        try flags([])
        try expect(c.document.elements.count == 1 && c.document.elements[0].kind == .line, "Option release commits one line")
        try expect(c.document.elements[0].points == [a, b, d], "vertices are the mouse-down points: \(c.document.elements[0].points)")
        try expect(c.editingUndoManager.undoActionName == "Draw Line", "one named Undo step")
        c.undo(); try expect(c.document.elements.isEmpty, "one Undo removes the whole polygon")
        c.redo(); try expect(c.document.elements.count == 1, "Redo restores it")
        // Shift constrains a vertex to 45 degrees from the previous vertex.
        c.document.elements = []; c.editingUndoManager.removeAllActions()
        try flags([.option]); try click(a); try click(CGPoint(x: 100, y: 25), [.option, .shift]); try flags([])
        let tip = c.document.elements[0].points.last!
        try expect(abs(tip.y - a.y) < 0.01 && tip.x > a.x, "Shift keeps the 45 degree constraint: \(tip)")
        // Leaving the tool commits the pending polygon the same way.
        c.document.elements = []; c.editingUndoManager.removeAllActions()
        try flags([.option]); try click(a); try click(b); c.tool = .rectangle
        try expect(c.document.elements.count == 1 && c.document.elements[0].points == [a, b], "tool change commits the polygon")
    }
    static func wipeLifecycle() throws {
        let c = canvas(); c.setBackground(backdrop()); c.setBackgroundColor(.clear)
        var a = rectangle(CGRect(x: 15, y: 15, width: 30, height: 30)); a.groupID = UUID()
        c.document.elements = [a]; c.selection = [a.id]; c.cropRect = CGRect(x: 3, y: 4, width: 60, height: 50)
        c.editingUndoManager.removeAllActions(); let original = c.document
        var dirty = 0
        c.onChange = { dirty += 1 }
        c.wipe(); let noDrawing = c.document
        try expect(noDrawing.elements.isEmpty && noDrawing.backgroundPNG == original.backgroundPNG &&
                   noDrawing.backgroundColor == .clear, "First Wipe clears drawing only")
        c.undo(); try expect(c.document == original, "Undo first Wipe restores drawing/groups")
        c.wipe(); try expect(c.document == noDrawing, "Wipe stage comes from restored content")
        c.wipe(); let blank = c.document
        try expect(blank.backgroundPNG == nil && blank.backgroundColor == .white && blank.size == original.size, "Second Wipe removes snap and resets backdrop white without resize")
        let notifications = dirty, undoName = c.editingUndoManager.undoActionName
        c.wipe(); try expect(dirty == notifications && c.editingUndoManager.undoActionName == undoName, "Wiping blank canvas is a no-op")
        c.undo(); try expect(c.document == noDrawing, "Undo snap Wipe restores photo and transparency")
        c.undo(); try expect(c.document == original, "Second undo restores first-stage drawing")
        c.selectAll(); let selected = c.selection, crop = c.cropRect
        c.editingUndoManager.removeAllActions(); c.wipeSnap()
        let withoutSnap = c.document
        try expect(withoutSnap.elements == original.elements && withoutSnap.backgroundPNG == nil &&
                   withoutSnap.backgroundColor == .white && c.selection == selected && c.cropRect == crop,
                   "Wipe Snap Only preserves editable annotations/IDs/groups/crop/selection and sets white")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Wipe Snap Only is one exact undo")
        c.redo(); try expect(c.document == withoutSnap, "Wipe Snap redo")
    }
    static func wipeResetsViewport() throws {
        let crop = CGRect(x: 3, y: 4, width: 60, height: 50), render = CGSize(width: 200, height: 160)
        let c = canvas()
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 30, height: 30))]
        c.cropRect = crop; c.document.renderSize = render; c.editingUndoManager.removeAllActions()
        let before = c.document
        c.wipe()
        try expect(c.document.elements.isEmpty && c.cropRect == nil && c.document.renderSize == nil,
                   "Wipe resets crop/render rect when no snap remains")
        c.undo(); try expect(c.document == before && c.cropRect == crop, "One Undo restores drawing, renderSize and crop")
        let d = canvas(); d.setBackground(backdrop())
        d.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 30, height: 30))]
        d.cropRect = crop; d.document.renderSize = render; d.editingUndoManager.removeAllActions()
        d.wipe()
        try expect(d.document.elements.isEmpty && d.cropRect == crop && d.document.renderSize == render,
                   "Wipe keeps crop/render rect while a snap remains")
        let withSnap = d.document
        d.wipe()
        try expect(d.document.backgroundPNG == nil && d.cropRect == nil && d.document.renderSize == nil,
                   "Clear stage resets crop/render rect")
        d.undo(); try expect(d.document == withSnap && d.cropRect == crop, "Undo of Clear restores rect")
    }
    static func resnap() throws {
        let c = canvas(); let window = host(c); defer { window.close() }
        c.setBackground(backdrop()); c.tool = .select
        var text = SketchElement(kind: .text)
        text.text = "Keep"; text.rect = CGRect(x: 55, y: 5, width: 40, height: 40)
        var shape = rectangle(CGRect(x: 30, y: 40, width: 20, height: 20))
        shape.groupID = UUID(); text.groupID = shape.groupID
        c.document.elements = [shape, text]; c.selection = [shape.id, text.id]
        c.cropRect = CGRect(x: 3, y: 4, width: 60, height: 50); c.editingUndoManager.removeAllActions()
        let original = c.document, crop = c.cropRect, selected = c.selection
        let retina = backdrop(NSSize(width: 200, height: 160)); retina.size = NSSize(width: 100, height: 80)
        var dirty = 0; c.onChange = { dirty += 1 }; c.framePreview = true
        try expect(c.replaceSnapPreservingAnnotations(retina), "Valid retina Re-Snap succeeds")
        let replaced = c.document
        let bg = NSBitmapImageRep(data: replaced.backgroundPNG!)!
        try expect(bg.pixelsWide == 100 && bg.pixelsHigh == 80 && replaced.size == original.size &&
                   replaced.elements == original.elements && c.selection == selected && c.cropRect == crop && c.framePreview,
                   "Re-Snap resamples only backdrop, preserving dimensions/all annotations/preview/crop/selection")
        try expect(try pixel(c, 10, 10).greenComponent > 0.9 && pixel(c, 70, 60).blueComponent > 0.9,
                   "Retina image is fitted to existing document coordinates")
        try expect(dirty == 1, "Re-Snap sends one dirty notification")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Re-Snap is one exact undo")
        c.redo(); try expect(c.document == replaced, "Re-Snap redo")
        c.mouseDown(with: try mouse(c, .leftMouseDown, CGPoint(x: 65, y: 15), clicks: 2))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Re-Snap pending editor") }
        editor.insertText("Pending", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let pending = try c.snapshotDocumentData(), notifications = dirty, history = c.editingUndoManager.undoActionName
        try expect(!c.replaceSnapPreservingAnnotations(NSImage(size: NSSize(width: 100, height: 80))), "Empty image is rejected")
        try expect(c.document == replaced && c.hasPendingTextChanges && editor.superview === c &&
                   window.firstResponder === editor && dirty == notifications && c.editingUndoManager.undoActionName == history &&
                   c.snapshotDocumentData() == pending, "Invalid Re-Snap validates before touching editor, recovery, selection, history or dirty")
        c.cancelOperation(nil)
    }
    static func framePreview() throws {
        let c = canvas(); c.setBackground(backdrop()); c.setBackgroundColor(.clear)
        c.document.elements = [rectangle(CGRect(x: 40, y: 35, width: 20, height: 20))]
        c.editingUndoManager.removeAllActions()
        let original = c.document, data = try c.snapshotDocumentData(), png = c.imageData(format: "png")
        var dirty = 0; c.onChange = { dirty += 1 }; c.framePreview = true
        let preview = SketchRenderer.bitmap(size: c.canvasSize) { c.draw(c.bounds) }!
        try expect(preview.colorAt(x: 80, y: 65)!.alphaComponent < 0.01 &&
                   preview.colorAt(x: 50, y: 45)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9,
                   "Preview clears backdrop/checkerboard while retaining visible annotation pixels")
        try expect(preview.colorAt(x: 1, y: 40)!.alphaComponent > 0.5, "Preview displays visible capture boundary")
        try expect(c.document == original && c.snapshotDocumentData() == data && c.imageData(format: "png") == png &&
                   dirty == 0 && !c.editingUndoManager.canUndo, "Preview leaves document, recovery, export and undo untouched")
        c.framePreview = false
        let normal = SketchRenderer.bitmap(size: c.canvasSize) { c.draw(c.bounds) }!
        try expect(normal.colorAt(x: 80, y: 65)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9,
                   "Leaving preview restores full background display")
    }
    static func justype() throws {
        let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
        c.tool = .arrow; c.shadowed = true; c.setZoom(2)
        c.document.elements = [rectangle(CGRect(x: 10, y: 10, width: 25, height: 20), color: .blue)]
        let original = c.document
        func printable(_ characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 38)!
        }
        let name = NSTextField(frame: CGRect(x: 110, y: 10, width: 250, height: 35))
        name.stringValue = "Name field"; window.contentView!.addSubview(name)
        try expect(window.makeFirstResponder(name), "Justype name-field focus")
        let fieldEditor = window.firstResponder
        c.keyDown(with: printable("J", flags: [.shift]))
        try expect(c.document == original && c.subviews.isEmpty && window.firstResponder === fieldEditor &&
                   !c.editingUndoManager.canUndo, "Printable keys cannot create canvas text while a name field owns focus")
        try expect(window.makeFirstResponder(c), "Justype canvas focus")
        c.mouseMoved(with: try mouse(c, .mouseMoved, CGPoint(x: 80, y: 50)))
        var dirty = 0; var toolChanges = 0
        c.onChange = { dirty += 1 }; c.onToolChange = { _ in toolChanges += 1 }
        c.keyDown(with: printable("J", flags: [.shift]))
        guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Justype native editor") }
        try expect(window.firstResponder === editor && editor.string == "J" && c.tool == .arrow && toolChanges == 0,
                   "First printable key creates and reaches the real editor without changing chosen tool")
        try expect(c.document.elements.last!.rect.origin == CGPoint(x: 80, y: 50) &&
                   c.document.elements.last!.fontSize == 24 && c.document.elements.last!.outlined && c.document.elements.last!.shadowed,
                   "Justype anchors to last pointer in document coordinates at zoom, preserving default text style")
        editor.keyDown(with: printable("é"))
        try expect(editor.string == "Jé" && dirty > 0 && c.hasPendingTextChanges && c.activeEditorUndoManager === editor.undoManager,
                   "Subsequent composed characters use native typing history and immediately dirty recovery")
        let pending = try c.snapshotDocumentData()
        try expect(try SketchDocument.decode(pending).elements.last!.text == "Jé" && editor.superview === c,
                   "Justype recovery includes typed text without committing")
        editor.breakUndoCoalescing(); editor.undoManager!.undo()
        try expect(editor.string != "Jé" && window.firstResponder === editor, "Native Justype typing undo stays inside editor")
        editor.undoManager!.redo(); try expect(editor.string == "Jé", "Native Justype typing redo")
        editor.keyDown(with: try key(c, 53))
        let committed = c.document
        try expect(editor.superview == nil && window.firstResponder === c && !c.hasPendingTextChanges &&
                   committed.elements.last!.text == "Jé" && c.tool == .arrow && toolChanges == 0,
                   "Original native Escape commits text and returns focus while preserving drawing tool (removed=\(editor.superview == nil), focus=\(window.firstResponder === c), pending=\(c.hasPendingTextChanges), text=\(committed.elements.last?.text ?? "nil"), tool=\(c.tool), toolChanges=\(toolChanges))")
        try expect(try c.snapshotDocumentData() == pending, "Escape commits exactly the pending recovery document")
        c.undo(); try expect(c.document == original && !c.editingUndoManager.canUndo, "Justype creation commits as one canvas undo")
        c.redo(); try expect(c.document == committed, "Justype canvas redo retains text ID/style/geometry")
        c.mouseMoved(with: try mouse(c, .mouseMoved, CGPoint(x: -100, y: 900)))
        c.keyDown(with: printable("K"))
        let clamped = c.document.elements.last!
        try expect(clamped.rect.minX == 0 && clamped.rect.maxX <= c.canvasSize.width &&
                   clamped.rect.minY >= 0 && clamped.rect.maxY <= c.canvasSize.height,
                   "Justype clamps stale/outside pointer so the annotation stays within canvas")
        c.commitPendingTextEditing()
        try expect(c.document.elements.last!.text == "K" && c.subviews.isEmpty && !c.hasPendingTextChanges,
                   "Parent commitPendingTextEditing API closes and saves native pending text")
        c.undo(); try expect(c.document == committed, "Explicit parent text commit is also one undoable edit")
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
        let w = Int(c.canvasSize.width), h = Int(c.canvasSize.height)
        // Capture into an explicit 1x device-RGB bitmap so the result never depends on the host display's backing scale or profile.
        func capture() throws -> NSBitmapImageRep {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw Failure(description: "Native view capture") }
            rep.size = c.bounds.size
            c.cacheDisplay(in: c.bounds, to: rep)
            return rep
        }
        func rgba(_ rep: NSBitmapImageRep?) throws -> [UInt8] {
            guard let rep, rep.pixelsWide == w, rep.pixelsHigh == h, let bytes = rgbaBytes(rep, width: w, height: h) else {
                throw Failure(description: "Visual proof needs a 1x \(w)x\(h) bitmap, got \(rep.map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "none")")
            }
            return bytes
        }
        let screenshot = try capture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-canvas-proof.png")
        try screenshot.representation(using: .png, properties: [:])!.write(to: url)
        print("Visual proof: \(url.path)")
        let live = try rgba(screenshot), offscreen = try rgba(SketchRenderer.bitmap(document: c.document))
        func channels(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [CGFloat] { (0..<3).map { CGFloat(bytes[(y * w + x) * 4 + $0]) / 255 } }
        func describe(_ rgb: [CGFloat]) -> String { rgb.map { String(format: "%.2f", $0) }.joined(separator: ",") }
        // System colours may resolve slightly differently per appearance, so inks get a loose band; white must be exact enough to tell it from the 0.88 checkerboard.
        func expectInk(_ bytes: [UInt8], _ x: Int, _ y: Int, _ expected: NSColor, _ what: String, tolerance: CGFloat = 0.15) throws {
            let want = expected.usingColorSpace(.sRGB)!, got = channels(bytes, x, y)
            try expect(abs(got[0] - want.redComponent) < tolerance && abs(got[1] - want.greenComponent) < tolerance && abs(got[2] - want.blueComponent) < tolerance,
                       "\(what) at (\(x),\(y)) must render rgb(\(describe([want.redComponent, want.greenComponent, want.blueComponent]))) but rendered rgb(\(describe(got)))")
        }
        let red = SketchColor(.systemRed).nsColor, green = SketchColor(.systemGreen).nsColor
        let purple = SketchColor(.systemPurple).nsColor, blue = SketchColor(.systemBlue).nsColor
        try expectInk(live, 132, 90, red, "Live red arrow shaft")
        try expectInk(live, 509, 81, green, "Live green ellipse stroke (upper right)")
        try expectInk(live, 509, 159, green, "Live green ellipse stroke (lower right)")
        try expectInk(live, 440, 232, blue, "Live filled blue rectangle")
        for (x, y) in [(95, 225), (157, 221), (193, 235), (260, 235)] { try expectInk(live, x, y, purple, "Live purple brush stroke") }
        try expectInk(live, 175, 228, .white, "Live brush where the eraser cut through it", tolerance: 0.03)
        try expectInk(live, 435, 120, .white, "Live unfilled ellipse interior", tolerance: 0.03)
        try expectInk(live, 6, 6, .white, "Live document background covering the checkerboard", tolerance: 0.03)
        try expectInk(live, 610, 390, .white, "Live empty canvas corner", tolerance: 0.03)
        try expectInk(offscreen, 435, 65, green, "Offscreen ellipse top edge")
        try expectInk(live, 435, 65, .white, "Live selection handle drawn over the ellipse top edge", tolerance: 0.03)
        let textBounds = text.rect.integral
        var ink = 0
        for y in Int(textBounds.minY)..<Int(textBounds.maxY) { for x in Int(textBounds.minX)..<Int(textBounds.maxX) where channels(live, x, y).min()! < 0.8 { ink += 1 } }
        try expect(ink > 300, "Live text block must leave glyph pixels in its rect (found \(ink))")
        // Full-frame parity with SketchRenderer, the export path, with every shadow (arrow and text) switched on.
        let plainLive = try rgba(try capture()), plainOffscreen = try rgba(SketchRenderer.bitmap(document: c.document))
        let chromeOuter = ellipse.rect.insetBy(dx: -8, dy: -8), chromeInner = ellipse.rect.insetBy(dx: 8, dy: 8)
        var compared = 0, mismatched = 0, worst: CGFloat = 0, firstMismatch = ""
        for y in 0..<h { for x in 0..<w {
            if chromeOuter.contains(CGPoint(x: x, y: y)) && !chromeInner.contains(CGPoint(x: x, y: y)) { continue }
            compared += 1
            let delta = zip(channels(plainLive, x, y), channels(plainOffscreen, x, y)).map { abs($0 - $1) }.max()!
            worst = max(worst, delta)
            if delta >= 0.05 {
                mismatched += 1
                if firstMismatch.isEmpty { firstMismatch = "(\(x),\(y)) live rgb(\(describe(channels(plainLive, x, y)))) vs offscreen rgb(\(describe(channels(plainOffscreen, x, y))))" }
            }
        } }
        print("Visual proof: \(mismatched) of \(compared) pixels differ from the offscreen render, worst channel delta \(String(format: "%.3f", worst))")
        try expect(mismatched == 0, "Live canvas draw must match SketchRenderer output outside the selection chrome (\(mismatched) of \(compared) pixels differ, first \(firstMismatch))")
    }
    /// Centroid, in top-down pixel coordinates, of the darkness cast outside `shape`.
    static func shadowCentroid(_ bytes: [UInt8], width: Int, height: Int, excluding shape: CGRect) -> CGPoint? {
        var weight: CGFloat = 0, sumX: CGFloat = 0, sumY: CGFloat = 0
        for y in 0..<height { for x in 0..<width where !shape.contains(CGPoint(x: x, y: y)) {
            let i = (y * width + x) * 4
            let dark = 1 - CGFloat(min(bytes[i], bytes[i + 1], bytes[i + 2])) / 255
            weight += dark; sumX += dark * (CGFloat(x) + 0.5); sumY += dark * (CGFloat(y) + 0.5)
        } }
        return weight > 0 ? CGPoint(x: sumX / weight, y: sumY / weight) : nil
    }
    static func shadowDirection() throws {
        let size = NSSize(width: 160, height: 120)
        let c = canvas(size)
        var shape = rectangle(CGRect(x: 60, y: 40, width: 40, height: 30), color: .systemBlue)
        shape.shadowed = true
        var text = SketchElement(kind: .text)
        text.rect = CGRect(x: 20, y: 85, width: 120, height: 30)
        text.text = "Shadow"; text.fontSize = 22; text.color = SketchColor(.white); text.outlined = false; text.shadowed = true
        let window = host(c); defer { window.close() }
        window.setContentSize(c.canvasSize)
        let w = Int(size.width), h = Int(size.height)
        func liveBytes() throws -> [UInt8] {
            c.displayIfNeeded()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let bytes = { () -> [UInt8]? in rep.size = c.bounds.size; c.cacheDisplay(in: c.bounds, to: rep); return rgbaBytes(rep, width: w, height: h) }()
            else { throw Failure(description: "Native view capture") }
            return bytes
        }
        func exportBytes() throws -> [UInt8] {
            guard let rep = SketchRenderer.bitmap(document: c.document), let bytes = rgbaBytes(rep, width: w, height: h) else {
                throw Failure(description: "Export render")
            }
            return bytes
        }
        let center = CGPoint(x: shape.rect.midX, y: shape.rect.midY)
        let footprint = shape.rect.insetBy(dx: -shape.strokeWidth, dy: -shape.strokeWidth)
        c.document.elements = [shape]
        for (name, bytes) in [("on screen", try liveBytes()), ("in export", try exportBytes())] {
            guard let centroid = shadowCentroid(bytes, width: w, height: h, excluding: footprint) else {
                throw Failure(description: "Rect shadow \(name) cast no pixels outside the shape")
            }
            try expect(centroid.x > center.x + 0.3 && centroid.y > center.y + 0.3,
                       "Rect shadow \(name) must fall below and right of the shape, centroid (\(centroid.x), \(centroid.y)) vs centre (\(center.x), \(center.y))")
        }
        // Text shadow (original offset is straight down): the extra darkness the shadow adds over the unshadowed glyphs
        // must sit below the ink, and not drift sideways.
        text.color = SketchColor(.black)
        var plain = text; plain.shadowed = false
        c.document.elements = [plain]
        let plainLive = try liveBytes(), plainExport = try exportBytes()
        c.document.elements = [text]
        for (name, bytes, base) in [("on screen", try liveBytes(), plainLive), ("in export", try exportBytes(), plainExport)] {
            var added: CGFloat = 0, addedX: CGFloat = 0, addedY: CGFloat = 0, ink: CGFloat = 0, inkX: CGFloat = 0, inkY: CGFloat = 0
            for y in 0..<h { for x in 0..<w {
                let i = (y * w + x) * 4
                let extra = CGFloat(Int(base[i]) - Int(bytes[i])) / 255
                if extra > 0 { added += extra; addedX += extra * CGFloat(x); addedY += extra * CGFloat(y) }
                let dark = 1 - CGFloat(base[i]) / 255
                ink += dark; inkX += dark * CGFloat(x); inkY += dark * CGFloat(y)
            } }
            try expect(added > 1 && ink > 1, "Text shadow \(name) cast no pixels")
            let dx = addedX / added - inkX / ink, dy = addedY / added - inkY / ink
            try expect(dy > 0.5 && abs(dx) < 1.5, "Text shadow \(name) must fall below the glyphs, offset from ink (\(dx), \(dy))")
        }
    }
    /// While a text annotation is being edited its glyphs (SketchTextLayoutManager) and the grip chrome
    /// draw their own shadows; both must fall down the page like the committed text.
    static func editorShadowDirection() throws {
        func capture(_ view: NSView, _ w: Int, _ h: Int) throws -> [UInt8] {
            view.displayIfNeeded()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw Failure(description: "Native view capture") }
            rep.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let bytes = rgbaBytes(rep, width: w, height: h) else { throw Failure(description: "Native view bytes") }
            return bytes
        }
        func editing(shadowed: Bool) throws -> (bytes: [UInt8], grip: [UInt8], gripSize: (Int, Int), glyphs: CGRect) {
            let c = canvas(NSSize(width: 300, height: 150)); let window = host(c); defer { window.close() }
            window.setContentSize(c.canvasSize)
            c.tool = .arrow; c.shadowed = shadowed; c.strokeColor = .black; c.outlined = false
            try expect(window.makeFirstResponder(c), "Editor shadow canvas focus")
            c.mouseMoved(with: try mouse(c, .mouseMoved, CGPoint(x: 60, y: 50)))
            c.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "H", charactersIgnoringModifiers: "H",
                isARepeat: false, keyCode: 4)!)
            guard let editor = c.subviews.compactMap({ $0 as? NSTextView }).first else { throw Failure(description: "Editor shadow native editor") }
            editor.insertText("HHHH", replacementRange: editor.selectedRange())
            editor.insertionPointColor = .clear
            guard let grip = c.subviews.first(where: { String(describing: type(of: $0)).contains("SketchTextGrip") }) else {
                throw Failure(description: "Editor shadow grip chrome")
            }
            let gw = Int(ceil(grip.bounds.width)), gh = Int(ceil(grip.bounds.height))
            return (try capture(c, 300, 150), try capture(grip, gw, gh), (gw, gh), editor.frame.insetBy(dx: 2, dy: 2))
        }
        let shadowed = try editing(shadowed: true), plain = try editing(shadowed: false)
        var added: CGFloat = 0, addedY: CGFloat = 0, ink: CGFloat = 0, inkY: CGFloat = 0
        for y in 0..<150 { for x in 0..<300 where shadowed.glyphs.contains(CGPoint(x: x, y: y)) {
            let i = (y * 300 + x) * 4
            let extra = CGFloat(Int(plain.bytes[i]) - Int(shadowed.bytes[i])) / 255
            if extra > 0 { added += extra; addedY += extra * CGFloat(y) }
            let dark = 1 - CGFloat(plain.bytes[i]) / 255
            ink += dark; inkY += dark * CGFloat(y)
        } }
        try expect(added > 1 && ink > 1, "Editing text shadow cast no pixels (added \(added), ink \(ink))")
        let dy = addedY / added - inkY / ink
        try expect(dy > 0.5, "Editing text group shadow must fall below the glyphs, offset from ink \(dy)")
        // Grip chrome: the five-point margin outside the border holds only its shadow.
        let (gw, gh) = shadowed.gripSize
        var top: Int = 0, bottom: Int = 0
        for x in 8..<(gw - 8) {
            for y in 0..<4 { top += Int(shadowed.grip[(y * gw + x) * 4 + 3]) }
            for y in (gh - 4)..<gh { bottom += Int(shadowed.grip[(y * gw + x) * 4 + 3]) }
        }
        try expect(bottom > top, "Grip chrome shadow must fall below the border (alpha above \(top), below \(bottom))")
    }
    /// Top-down premultiplied sRGB RGBA bytes of a bitmap, drawn 1:1 at the given pixel size.
    static func rgbaBytes(_ bitmap: NSBitmapImageRep, width: Int, height: Int) -> [UInt8]? {
        guard let image = bitmap.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
#endif
