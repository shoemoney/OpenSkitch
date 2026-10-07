import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class SketchTextEditor: NSTextView {
    // Native typing history stays separate from document transactions. Committing
    // an annotation registers one canvas undo step, regardless of keystroke count.
    private let typingHistory = UndoManager()
    override var undoManager: UndoManager? { typingHistory }
    override func keyDown(with event: NSEvent) {
        // Original SkitchTextFieldEditor_keyDown: handles Escape before NSTextView
        // completion handling, then textDidEndEditing: saves the field contents.
        if event.keyCode == 53, let canvas = delegate as? CanvasView {
            canvas.commitPendingTextEditing(); return
        }
        super.keyDown(with: event)
    }
}

/// Native AppKit canvas. All model geometry stays in top-left document pixels.
/// Assign as NSScrollView.documentView; frame/intrinsic size follow canvasSize * zoom.
final class CanvasView: NSView, NSTextViewDelegate {
    var tool: SketchTool = .arrow {
        didSet {
            finishTextEditing(); needsDisplay = true; resetCursorRects()
            if oldValue != tool {
                if !togglingPencil { pencilReturnTool = nil }
                onToolChange?(tool)
            }
        }
    }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 5
    var strokeSmoothing: StrokeSmoothing = .medium
    var filled = false
    var shadowed = true
    var fontName = "Helvetica-Bold"
    var fontSize: CGFloat = 24
    var outlined = true
    var zoom: CGFloat = 1 {
        didSet {
            if !zoom.isFinite { zoom = oldValue; return }
            zoom = min(16, max(0.05, zoom))
            updateCanvasSize()
        }
    }
    var document = SketchDocument() {
        didSet {
            if !settingPanBackground && oldValue.backgroundPNG != document.backgroundPNG { panBackground = nil }
            updateCanvasSize(); needsDisplay = true
        }
    }
    var onChange: (() -> Void)?
    var onToolChange: ((SketchTool) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    /// Original resource stems: wipe_brushlayer, wipe_snap, wipe_already_blank.
    var onSound: ((String) -> Void)?
    /// See-through framing is a view state; rendering/export/recovery keep the full document.
    var framePreview = false { didSet { needsDisplay = true } }
    /// The shell owns open/replace decisions, including unsaved-work prompts and file identity.
    var onOpenDocument: ((URL) -> Void)?
    let editingUndoManager = UndoManager()
    /// The annotation editor's typing history, only while it owns keyboard focus.
    /// The parent should check the window's first responder for other field editors.
    var activeEditorUndoManager: UndoManager? {
        guard let editor = textEditor, window?.firstResponder === editor else { return nil }
        return editor.undoManager
    }
    var hasPendingTextChanges: Bool {
        guard textEditor != nil, let before = textBeforeEditing else { return false }
        return documentIncludingPendingText() != before.document
    }
    var canvasSize: NSSize { document.size }
    override var undoManager: UndoManager? { editingUndoManager }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: canvasSize.width * zoom, height: canvasSize.height * zoom) }

    // Internal access also makes the executable tests independent of a visible window.
    var selection: Set<UUID> = [] { didSet { needsDisplay = true } }
    var cropRect: CGRect? { didSet { needsDisplay = true } }
    private var preview: SketchElement?
    private var marquee: CGRect?
    private var gestureStart: CGPoint = .zero
    private var gestureState: EditorState?
    private var gestureDocument: SketchDocument?
    private var gestureColor: NSColor?
    private var lastMousePoint: CGPoint?
    private var pointerTrackingArea: NSTrackingArea?
    private var copyOnDrag = false
    private var copiesCreated = false
    private var spaceHeld = false
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var pencilReturnTool: SketchTool?
    private var togglingPencil = false
    private var panBackground: PanBackground?
    private var settingPanBackground = false
    private var dragMode: DragMode = .none
    private var resizingHandle: Int?
    private var resizeBounds: CGRect = .zero
    private var strokePoints: [CGPoint] = []
    private var strokeSamples: [StrokeSample] = []
    private var drawingPencil = false
    private var tabletEraser = false
    private var textEditor: NSTextView?
    private var editingTextID: UUID?
    private var textBeforeEditing: EditorState?
    private var isFinishingText = false
    private var pasteOffset: CGFloat = 0
    private static let pasteboardType = NSPasteboard.PasteboardType("com.skitch-redux.editable-selection")
    private enum DragMode { case none, create, move, resize, marquee, crop, erase, pan, sampleColor }
    /// The raster cache in SketchDocument is the visible viewport. Preserve the full
    /// source separately so panning away/back (even after save/reopen) loses no pixels.
    private struct PanBackground: Codable, Equatable {
        var sourcePNG: Data
        var sourceSize: CGSize
        var offset: CGPoint
    }
    private struct CanvasFile: Codable {
        var document: SketchDocument
        var canvasPanBackground: PanBackground?
        private enum CodingKeys: String, CodingKey { case canvasPanBackground }
        func encode(to encoder: Encoder) throws {
            try document.encode(to: encoder)
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(canvasPanBackground, forKey: .canvasPanBackground)
        }
        init(document: SketchDocument, background: PanBackground?) {
            self.document = document; canvasPanBackground = background
        }
        init(from decoder: Decoder) throws {
            document = try SketchDocument(from: decoder)
            canvasPanBackground = try decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(PanBackground.self, forKey: .canvasPanBackground)
        }
    }
    private struct EditorState {
        var document: SketchDocument
        var selection: Set<UUID>
        var cropRect: CGRect?
        var panBackground: PanBackground?
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        editingUndoManager.groupsByEvent = false
        setAccessibilityRole(.image)
        setAccessibilityLabel("Drawing canvas")
        registerForDraggedTypes([.fileURL, .png, .tiff, Self.pasteboardType])
        updateCanvasSize()
    }
    private var state: EditorState {
        EditorState(document: document, selection: selection, cropRect: cropRect, panBackground: panBackground)
    }
    private func updateCanvasSize() {
        let size = intrinsicContentSize
        if frame.size != size { setFrameSize(size) }
        invalidateIntrinsicContentSize()
        if let editor = textEditor, let id = editingTextID,
           let element = document.elements.first(where: { $0.id == id }) {
            editor.frame = viewRect(element.bounds)
        }
        needsDisplay = true
    }
    private func recordUndo(_ before: EditorState, name: String) {
        guard before.document != document || before.panBackground != panBackground else { return }
        let explicitGroup = !editingUndoManager.isUndoing && !editingUndoManager.isRedoing
        if explicitGroup { editingUndoManager.beginUndoGrouping() }
        editingUndoManager.registerUndo(withTarget: self) { canvas in canvas.restore(before, name: name) }
        editingUndoManager.setActionName(name)
        if explicitGroup { editingUndoManager.endUndoGrouping() }
        onChange?()
    }
    private func restore(_ restored: EditorState, name: String) {
        finishTextEditing()
        let inverse = state
        document = restored.document
        panBackground = restored.panBackground
        selection = restored.selection
        cropRect = restored.cropRect
        recordUndo(inverse, name: name)
    }
    private func edit(_ name: String, _ body: () -> Void) {
        finishTextEditing()
        let before = state
        body()
        recordUndo(before, name: name)
    }
    func undo() { finishTextEditing(); if dragMode != .none { cancelOperation(nil) }; editingUndoManager.undo() }
    func redo() { finishTextEditing(); if dragMode != .none { cancelOperation(nil) }; editingUndoManager.redo() }
    func setZoom(_ value: CGFloat) { zoom = value }

    func newBlank(size: NSSize) {
        guard SketchDocument.validSize(size) else { return }
        edit("New Canvas") {
            document = SketchDocument(size: integralSize(size)); panBackground = nil
            selection.removeAll(); cropRect = nil
        }
    }
    func setBackground(_ image: NSImage) {
        // Use actual bitmap pixels, rather than a TIFF's 72/144-DPI point size.
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return }
        let size = NSSize(width: cg.width, height: cg.height)
        guard SketchDocument.validSize(size) else { return }
        let normalized = NSImage(cgImage: cg, size: size)
        guard let png = SketchRenderer.png(image: normalized) else { return }
        edit("Set Background") {
            document.size = size; document.backgroundPNG = png; panBackground = nil
            selection.removeAll(); cropRect = nil
        }
    }
    func setBackgroundColor(_ color: NSColor) {
        edit("Background Color") { document.backgroundColor = SketchColor(color) }
    }
    /// Re-snap fits the new image into the existing viewport. Validation and raster
    /// creation finish before touching the document, pending editor, or undo history.
    @discardableResult
    func replaceSnapPreservingAnnotations(_ image: NSImage) -> Bool {
        // NSImage(size:) reports isValid and can synthesize a blank CGImage even
        // without image content. Reject that placeholder before committing text.
        guard !image.representations.isEmpty, image.isValid, image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0, SketchDocument.validSize(canvasSize) else { return false }
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let png = SketchRenderer.png(image: NSImage(cgImage: cg, size: canvasSize)) else { return false }
        edit("Re-Snap") { document.backgroundPNG = png; panBackground = nil }
        return true
    }
    /// Stage is derived from content, so Undo naturally restores the next Wipe action.
    func wipe() {
        finishTextEditing()
        if !document.elements.isEmpty {
            clearAnnotations()
            onSound?("wipe_brushlayer")
        } else if document.backgroundPNG != nil || document.backgroundColor != .white {
            edit("Wipe Snap") { document.backgroundPNG = nil; document.backgroundColor = .white; panBackground = nil }
            onSound?("wipe_snap")
        } else {
            onSound?("wipe_already_blank")
        }
    }
    /// Recovered keepPenEraseSnap:/setBackgroundTA removes the snap and sets white.
    func wipeSnap() {
        finishTextEditing()
        guard document.backgroundPNG != nil || document.backgroundColor != .white else {
            onSound?("wipe_already_blank"); return
        }
        edit("Wipe Snap Only") { document.backgroundPNG = nil; document.backgroundColor = .white; panBackground = nil }
        onSound?("wipe_snap")
    }
    func clearAnnotations() {
        edit("Clear Annotations") { document.elements.removeAll(); selection.removeAll() }
    }
    func flatten() {
        finishTextEditing()
        guard let png = SketchRenderer.bitmap(document: document)?.representation(using: .png, properties: [:]) else { return }
        edit("Flatten") {
            document.backgroundPNG = png; document.backgroundColor = .clear
            document.elements.removeAll(); selection.removeAll()
        }
    }
    func deleteSelection() {
        edit("Delete") {
            document.elements.removeAll { selection.contains($0.id) }
            selection.removeAll()
        }
    }
    func selectAll() { finishTextEditing(); selection = Set(document.elements.map(\.id)) }
    func duplicateSelection() {
        edit("Duplicate") {
            let originals = document.elements.filter { selection.contains($0.id) }
            let copies = remappedCopies(originals, offset: 12)
            document.elements.append(contentsOf: copies)
            selection = Set(copies.map(\.id))
        }
    }
    private func remappedCopies(_ elements: [SketchElement], offset: CGFloat) -> [SketchElement] {
        var groups: [UUID: UUID] = [:]
        return elements.map { original in
            var copy = original
            copy.id = UUID()
            if let group = copy.groupID {
                if groups[group] == nil { groups[group] = UUID() }
                copy.groupID = groups[group]
            }
            copy.translate(x: offset, y: offset)
            return copy
        }
    }
    func bringSelectionToFront() {
        edit("Bring to Front") {
            document.elements = document.elements.filter { !selection.contains($0.id) } +
                document.elements.filter { selection.contains($0.id) }
        }
    }
    func sendSelectionToBack() {
        edit("Send to Back") {
            document.elements = document.elements.filter { selection.contains($0.id) } +
                document.elements.filter { !selection.contains($0.id) }
        }
    }
    func groupSelection() {
        guard selection.count > 1 else { return }
        edit("Group") {
            let id = UUID()
            for index in document.elements.indices where selection.contains(document.elements[index].id) {
                document.elements[index].groupID = id
            }
        }
    }
    func ungroupSelection() {
        edit("Ungroup") {
            for index in document.elements.indices where selection.contains(document.elements[index].id) {
                document.elements[index].groupID = nil
            }
        }
    }
    func applyStyleToSelection() {
        edit("Change Style") {
            for index in document.elements.indices where selection.contains(document.elements[index].id) {
                // Raster pixels retain their actual colors; changing a raster's metadata is misleading.
                if document.elements[index].kind == .raster { continue }
                document.elements[index].color = SketchColor(strokeColor)
                document.elements[index].strokeWidth = effectiveStrokeWidth
                document.elements[index].filled = filled
                document.elements[index].shadowed = shadowed
                if document.elements[index].kind == .text {
                    document.elements[index].fontName = fontName
                    document.elements[index].fontSize = fontSize.isFinite ? min(4096, max(18, fontSize)) : 24
                    document.elements[index].outlined = outlined
                }
            }
        }
    }
    /// Font/outline controls must not apply the current pen color or shape style.
    /// Pending typing commits first through edit(), retaining its own undo step.
    func applyTextStyleToSelection() {
        edit("Change Text Style") {
            for index in document.elements.indices where selection.contains(document.elements[index].id) &&
                document.elements[index].kind == .text {
                var element = document.elements[index]
                let size = fontSize.isFinite ? min(4096, max(18, fontSize)) : 24
                let typographyChanged = element.fontName != fontName || element.fontSize != size
                element.fontName = fontName
                element.fontSize = size
                element.outlined = outlined
                // Keep the existing wrap width, anchor, and affine transform. Only
                // reflow height when typography changes so larger text is not clipped.
                if typographyChanged { element.rect.size.height = textHeight(for: element) }
                document.elements[index] = element
            }
        }
    }

    func copySelection() {
        finishTextEditing()
        let selected = document.elements.filter { selection.contains($0.id) }
        let board = NSPasteboard.general
        var copied = document
        if !selected.isEmpty {
            copied.elements = selected; copied.backgroundPNG = nil; copied.backgroundColor = .clear
            let painted = selected.dropFirst().reduce(selected.first!.paintBounds) { $0.union($1.paintBounds) }
            let bounds = painted.integral.intersection(document.canvasRect)
            if !bounds.isEmpty {
                copied.size = integralSize(bounds.size)
                for index in copied.elements.indices {
                    copied.elements[index].translate(x: -bounds.minX, y: -bounds.minY)
                }
            }
        }
        guard let bitmap = SketchRenderer.bitmap(document: copied),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        board.clearContents()
        if !selected.isEmpty, let editable = try? copied.encoded() { board.setData(editable, forType: Self.pasteboardType) }
        board.setData(png, forType: .png)
        if let tiff = bitmap.representation(using: .tiff, properties: [:]) { board.setData(tiff, forType: .tiff) }
        pasteOffset = 0
    }
    func paste() {
        paste(from: .general)
    }
    private func paste(from board: NSPasteboard) {
        finishTextEditing()
        if let data = board.data(forType: Self.pasteboardType), let source = try? SketchDocument.decode(data) {
            if !source.elements.isEmpty {
                edit("Paste") {
                    pasteOffset += 12
                    let copies = remappedCopies(source.elements, offset: pasteOffset)
                    document.elements.append(contentsOf: copies)
                    selection = Set(copies.map(\.id))
                }
                return
            }
        }
        if let image = NSImage(pasteboard: board), let png = SketchRenderer.png(image: image) {
            edit("Paste Image") {
                var element = SketchElement(kind: .raster)
                let size = image.size
                element.rect = CGRect(x: max(0, (canvasSize.width - size.width) / 2),
                                      y: max(0, (canvasSize.height - size.height) / 2),
                                      width: size.width, height: size.height)
                element.imagePNG = png
                document.elements.append(element); selection = [element.id]
            }
        } else if let text = board.string(forType: .string), !text.isEmpty {
            edit("Paste Text") {
                var element = styledElement(.text)
                element.text = text
                element.rect = CGRect(x: 20, y: 20, width: max(80, min(400, canvasSize.width - 20)), height: 100)
                document.elements.append(element); selection = [element.id]
            }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let board = sender.draggingPasteboard
        if let url = droppedFileURL(from: board), isDocumentURL(url) {
            return onOpenDocument == nil ? [] : .copy
        }
        return board.availableType(from: [.fileURL, .png, .tiff, Self.pasteboardType]) == nil ? [] : .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    private func droppedFileURL(from board: NSPasteboard) -> URL? {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
    private func isDocumentURL(_ url: URL) -> Bool {
        [SketchDocument.fileExtension, "skitch"].contains(url.pathExtension.lowercased())
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        if let url = droppedFileURL(from: board) {
            if isDocumentURL(url) {
                guard let open = onOpenDocument else { return false }
                // Do not read/load the file or commit pending text here. The parent
                // may cancel opening and must retain the current editor and history.
                open(url)
                return true
            }
            guard let image = NSImage(contentsOf: url), SketchDocument.validSize(image.size) else { return false }
            let before = document
            setBackground(image)
            return document != before
        }
        let before = document
        paste(from: board)
        return document != before
    }

    func rotate(clockwise: Bool) {
        let oldSize = canvasSize
        let matrix = clockwise ? SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: oldSize.height, ty: 0) :
            SketchTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: oldSize.width)
        transformDocument(matrix, size: NSSize(width: oldSize.height, height: oldSize.width), name: "Rotate")
    }
    func flip(horizontal: Bool) {
        let matrix = horizontal ? SketchTransform(a: -1, d: 1, tx: canvasSize.width) :
            SketchTransform(a: 1, d: -1, ty: canvasSize.height)
        transformDocument(matrix, size: canvasSize, name: "Flip")
    }
    private func transformDocument(_ matrix: SketchTransform, size: NSSize, name: String) {
        finishTextEditing()
        let background = transformedBackground(matrix, size: size)
        if document.backgroundPNG != nil && background == nil { return }
        edit(name) {
            document.backgroundPNG = background
            document.size = size
            for index in document.elements.indices {
                document.elements[index].transform = document.elements[index].transform.followed(by: matrix)
            }
            cropRect = nil
        }
    }
    private func transformedBackground(_ matrix: SketchTransform, size: NSSize) -> Data? {
        guard let image = document.backgroundImage else { return nil }
        let oldRect = document.canvasRect
        return SketchRenderer.bitmap(size: size) {
            NSGraphicsContext.current?.cgContext.concatenate(matrix.cg)
            SketchRenderer.drawImage(image, in: oldRect)
        }?.representation(using: .png, properties: [:])
    }
    /// Canvas resize changes the viewport, preserving annotation geometry at the top left.
    func resizeCanvas(to size: NSSize) {
        guard SketchDocument.validSize(size) else { return }
        finishTextEditing()
        let newSize = integralSize(size)
        let background = transformedBackground(.identity, size: newSize)
        if document.backgroundPNG != nil && background == nil { return }
        edit("Resize Canvas") { document.size = newSize; document.backgroundPNG = background; cropRect = nil }
    }
    func cropSelection() {
        guard let rect = cropRect ?? selectionBounds else { return }
        crop(to: rect)
    }
    /// Crop both the underlying bitmap and the viewport, translating surviving editable objects.
    func crop(to rect: CGRect) {
        finishTextEditing()
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return }
        let clipped = rect.standardized.integral.intersection(document.canvasRect)
        guard clipped.width >= 1, clipped.height >= 1 else { return }
        let background = transformedBackground(.translation(x: -clipped.minX, y: -clipped.minY), size: clipped.size)
        if document.backgroundPNG != nil && background == nil { return }
        edit("Crop") {
            document.backgroundPNG = background
            document.size = clipped.size
            document.elements.removeAll { !$0.paintBounds.intersects(clipped) }
            for index in document.elements.indices {
                document.elements[index].translate(x: -clipped.minX, y: -clipped.minY)
            }
            selection.formIntersection(Set(document.elements.map(\.id)))
            cropRect = nil
        }
    }

    func renderedImage() -> NSImage {
        finishTextEditing()
        let image = NSImage(size: canvasSize)
        if let bitmap = SketchRenderer.bitmap(document: document) { image.addRepresentation(bitmap) }
        return image
    }
    func imageData(format: String) -> Data? {
        finishTextEditing()
        let format = format.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if format == "pdf" { return pdfData() }
        var exported = document
        // JPEG/BMP do not reliably support alpha; composite transparent pixels onto white.
        if ["jpeg", "jpg", "bmp"].contains(format) {
            let background = exported.backgroundColor.nsColor
            exported.backgroundColor = SketchColor(NSColor.white.blended(withFraction: background.alphaComponent,
                of: background.withAlphaComponent(1)) ?? .white)
        }
        guard let bitmap = SketchRenderer.bitmap(document: exported) else { return nil }
        switch format {
        case "png": return bitmap.representation(using: .png, properties: [:])
        case "jpg", "jpeg": return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        case "tif", "tiff": return bitmap.representation(using: .tiff, properties: [:])
        case "bmp":
            guard let cg = bitmap.cgImage else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.bmp.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, cg, nil)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        default: return nil
        }
    }
    private func pdfData() -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var box = document.canvasRect
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        context.translateBy(x: 0, y: canvasSize.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        SketchRenderer.draw(document)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return data as Data
    }
    func documentData() throws -> Data { finishTextEditing(); return try encodeCanvasDocument(document) }
    /// Recovery/autosave serialization. Does not end typing, change the live model,
    /// register undo, move the caret, or notify onChange. Empty pending text is omitted.
    func snapshotDocumentData() throws -> Data { try encodeCanvasDocument(documentIncludingPendingText()) }
    private func encodeCanvasDocument(_ value: SketchDocument) throws -> Data {
        _ = try value.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CanvasFile(document: value, background: panBackground))
    }
    /// Validate a native-file canvas supplement before writing/opening it. The
    /// returned document can be compared to SkitchFile.document; retain the input
    /// bytes, since re-encoding this model alone would drop hidden pan source pixels.
    static func validatedDocumentData(_ data: Data) throws -> SketchDocument {
        try decodeValidatedCanvasFile(data).document
    }
    private static func decodeValidatedCanvasFile(_ data: Data) throws -> CanvasFile {
        var file = try JSONDecoder().decode(CanvasFile.self, from: data)
        file.document = try file.document.validated()
        if let background = file.canvasPanBackground {
            guard SketchDocument.validSize(background.sourceSize), background.offset.x.isFinite,
                  background.offset.y.isFinite, abs(background.offset.x) <= 1_000_000,
                  abs(background.offset.y) <= 1_000_000,
                  let bitmap = NSBitmapImageRep(data: background.sourcePNG),
                  bitmap.pixelsWide == Int(ceil(background.sourceSize.width)),
                  bitmap.pixelsHigh == Int(ceil(background.sourceSize.height)),
                  bitmap.cgImage != nil, file.document.backgroundPNG != nil else {
                throw SketchDocumentError.invalidDocument
            }
        }
        return file
    }
    func loadDocument(data: Data, clearingUndo: Bool = true) throws {
        let file = try Self.decodeValidatedCanvasFile(data)
        finishTextEditing()
        document = file.document
        panBackground = file.canvasPanBackground
        selection.removeAll(); cropRect = nil; preview = nil
        resetGesture()
        if clearingUndo { editingUndoManager.removeAllActions() }
        onChange?()
    }

    // MARK: Vector paint tools

    /// Fill operates on annotation geometry, never the photograph's pixel colors.
    /// Shift bypasses contact grouping and merging, as in the original ToolFill.
    func floodFill(at point: CGPoint, grouping: Bool = true) {
        finishTextEditing()
        guard document.canvasRect.contains(point) else { return }
        let color = SketchColor(strokeColor)
        let paths = document.elements.enumerated().compactMap { index, element in
            VectorGeometry.paintedPath(for: element).map { (index: index, element: element, path: $0) }
        }
        let hit = paths.last { $0.path.contains(point, using: .winding) }
        if let hit {
            if hit.element.color == color && color.alpha == 1 { return }
            if hit.element.shadowed {
                edit("Flood Fill") { document.elements[hit.index].color = color }
                return
            }
        }
        let candidate: CGPath
        var visited = paths
        var differentStyleMarker: UUID? = paths.first?.element.id
        // Confirmed first pass; separated matching-run resume remains unverified.
        if let hit, let hitIndex = paths.firstIndex(where: { $0.element.id == hit.element.id }) {
            // Resolve the consecutive run that contains the clicked layer. Original
            // separated-run iterator behavior still needs i386-runtime comparison.
            var start = hitIndex
            while start > 0 && paths[start - 1].element.color == hit.element.color && !paths[start - 1].element.shadowed { start -= 1 }
            var runEnd = start
            var region = paths[start].path
            while runEnd + 1 < paths.count && paths[runEnd + 1].element.color == hit.element.color && !paths[runEnd + 1].element.shadowed {
                runEnd += 1; region = region.union(paths[runEnd].path)
            }
            visited = Array(paths[start...runEnd]); differentStyleMarker = nil
            for entry in paths.dropFirst(runEnd + 1) where entry.element.color != hit.element.color || entry.element.shadowed {
                region = region.subtracting(entry.path); visited.append(entry)
                if differentStyleMarker == nil { differentStyleMarker = entry.element.id }
            }
            guard let component = VectorGeometry.components(of: region).first(where: { $0.contains(point, using: .winding) }) else {
                edit("Flood Fill") { document.elements[hit.index].color = color }
                return
            }
            candidate = component
        } else {
            var region = CGPath(rect: document.canvasRect, transform: nil)
            for entry in paths { region = region.subtracting(entry.path) }
            guard let component = VectorGeometry.components(of: region).first(where: { $0.contains(point, using: .winding) }) else { return }
            candidate = component
        }
        // Original growth is measured in display pixels: opaque fills hide seams;
        // translucent fills use the smaller overlap to avoid a dark boundary.
        let growth: CGFloat = (color.alpha == 1 ? 1 : 0.2) / zoom
        let rim = candidate.copy(strokingWithWidth: 2 * growth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        var region = candidate.union(rim)
        var style = SketchElement(kind: .path)
        style.color = color; style.shadowed = false
        var contacts = visited.filter { $0.path.intersects(region) }
        var removed: Set<UUID> = []
        var anchor: UUID?
        if let marker = differentStyleMarker, let start = visited.firstIndex(where: { $0.element.id == marker }) {
            anchor = visited.dropFirst(start).first { $0.element.id != hit?.element.id && $0.path.intersects(region) }?.element.id
        }
        var group: UUID?
        var groupedMembers: Set<UUID> = []
        if grouping && !contacts.isEmpty {
            group = UUID()
            for entry in contacts { groupedMembers.formUnion(groupMembers(of: entry.element)) }
            let uniform = contacts.allSatisfy { $0.element.color == contacts[0].element.color && $0.element.shadowed == contacts[0].element.shadowed }
            var merge = contacts
            if hit != nil && uniform {
                style.color = blended(color, over: contacts[0].element.color)
                style.shadowed = contacts[0].element.shadowed
            } else if hit != nil {
                merge = []
            } else if !uniform || contacts[0].element.color != color {
                // Preserve the original order-sensitive final matching run.
                var pending = Array(contacts.prefix(0)), subset = pending
                for (index, entry) in contacts.enumerated() {
                    if entry.element.color == color && !entry.element.shadowed { pending.append(entry) }
                    else if index > 0, entry.path.intersects(contacts[index - 1].path) { subset = pending; pending = [] }
                }
                if !pending.isEmpty { subset = pending }
                merge = subset
            }
            if !merge.isEmpty {
                var combined = region
                for entry in merge { combined = combined.union(entry.path) }
                let components = VectorGeometry.components(of: combined)
                if (hit != nil && uniform) || components.count == 1 {
                    if let first = components.first {
                        region = first; removed = Set(merge.map { $0.element.id })
                        style.shadowed = merge[0].element.shadowed
                        if hit == nil { anchor = merge.first?.element.id }
                    }
                }
            }
        } else { contacts = [] }
        var element = VectorGeometry.element(path: region, style: style)
        element.groupID = group
        edit("Flood Fill") {
            var result: [SketchElement] = []
            var inserted = false
            for var original in document.elements {
                if original.id == anchor { result.append(element); inserted = true }
                if removed.contains(original.id) { continue }
                if groupedMembers.contains(original.id) { original.groupID = group }
                result.append(original)
            }
            if !inserted { result.append(element) }
            document.elements = result
            selection.formIntersection(Set(result.map(\.id)))
        }
    }
    private func blended(_ foreground: SketchColor, over background: SketchColor) -> SketchColor {
        let alpha = foreground.alpha + background.alpha * (1 - foreground.alpha)
        guard alpha > 0 else { return .clear }
        var result = foreground; result.alpha = alpha
        result.red = (foreground.red * foreground.alpha + background.red * background.alpha * (1 - foreground.alpha)) / alpha
        result.green = (foreground.green * foreground.alpha + background.green * background.alpha * (1 - foreground.alpha)) / alpha
        result.blue = (foreground.blue * foreground.alpha + background.blue * background.alpha * (1 - foreground.alpha)) / alpha
        return result
    }

    /// Subtract the eraser from annotation geometry, preserving editable curves,
    /// holes and connected fragments. Text and photographs are protected.
    func eraseStroke(points: [CGPoint], width: CGFloat) {
        guard let mask = VectorGeometry.eraserPath(points: points, width: width) else { return }
        erasePath(mask)
    }
    private func erasePath(_ mask: CGPath) {
        finishTextEditing()
        var result: [SketchElement] = []
        let affectedGroups = Set(document.elements.compactMap { VectorGeometry.paintedPath(for: $0) == nil ? nil : $0.groupID })
        var didErase = false
        for original in document.elements {
            if let fragments = VectorGeometry.subtract(element: original, eraser: mask) {
                result.append(contentsOf: fragments); didErase = true
            } else { result.append(original) }
        }
        guard didErase else { return }
        let regrouped = VectorGeometry.regroup(elements: result, affectedGroups: affectedGroups)
        edit("Erase") {
            document.elements = regrouped
            selection.formIntersection(Set(regrouped.map(\.id)))
        }
    }

    // MARK: Drawing and interaction

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        if framePreview { context?.clear(dirtyRect) }
        context?.scaleBy(x: zoom, y: zoom)
        if !framePreview { drawCheckerboard(in: document.canvasRect) }
        var visible = document
        if let id = editingTextID { visible.elements.removeAll { $0.id == id } }
        SketchRenderer.draw(visible, includeBackground: !framePreview)
        if let preview { SketchRenderer.draw(preview) }
        NSGraphicsContext.restoreGraphicsState()
        drawSelectionChrome()
        if framePreview {
            NSColor.controlAccentColor.setStroke()
            let boundary = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            boundary.lineWidth = 2; boundary.stroke()
        }
    }
    private func drawCheckerboard(in rect: CGRect) {
        NSColor.white.setFill(); rect.fill()
        NSColor(white: 0.88, alpha: 1).setFill()
        let tile: CGFloat = 12 / zoom
        // Restrict checkerboard work to the visible viewport at large canvas sizes.
        let visible = documentRect(visibleRect).intersection(rect)
        guard !visible.isEmpty else { return }
        for y in Int(floor(visible.minY / tile))...Int(ceil(visible.maxY / tile)) {
            for x in Int(floor(visible.minX / tile))...Int(ceil(visible.maxX / tile)) where (x + y) % 2 == 0 {
                CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile, width: tile, height: tile).intersection(rect).fill()
            }
        }
    }
    private func drawSelectionChrome() {
        NSColor.controlAccentColor.setStroke()
        if let bounds = selectionBounds, !selection.isEmpty {
            let path = NSBezierPath(rect: viewRect(bounds).insetBy(dx: -2, dy: -2))
            path.lineWidth = 1.5; path.stroke()
            for point in handlePoints(for: bounds) {
                let rect = CGRect(x: point.x * zoom - 5, y: point.y * zoom - 5, width: 10, height: 10)
                NSColor.white.setFill(); rect.fill()
                NSColor.controlAccentColor.setStroke(); NSBezierPath(rect: rect).stroke()
            }
        }
        if let rect = cropRect ?? marquee {
            let path = NSBezierPath(rect: viewRect(rect))
            path.lineWidth = 2; path.setLineDash([6, 4], count: 2, phase: 0); path.stroke()
            if cropRect != nil {
                NSColor.black.withAlphaComponent(0.25).setFill()
                let mask = NSBezierPath(rect: bounds)
                mask.appendRect(viewRect(rect)); mask.windingRule = .evenOdd; mask.fill()
            }
        }
        if dragMode == .erase, let point = strokePoints.last {
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(ovalIn: viewRect(CGRect(x: point.x - effectiveStrokeWidth,
                y: point.y - effectiveStrokeWidth, width: effectiveStrokeWidth * 2, height: effectiveStrokeWidth * 2))).stroke()
        }
    }
    override func resetCursorRects() {
        let cursor: NSCursor = spaceHeld ? (dragMode == .pan ? .closedHand : .openHand) :
            (effectiveTool == .select ? .arrow : (effectiveTool == .text ? .iBeam : .crosshair))
        addCursorRect(bounds, cursor: cursor)
    }
    /// Modifier precedence follows recovered setModifiers: Command overrides Control;
    /// Fill keeps its own Control handling instead of selecting the temporary eraser.
    var effectiveTool: SketchTool {
        if currentModifiers.contains(.command) { return .select }
        if (currentModifiers.contains(.control) || tabletEraser) && tool != .fill { return .eraser }
        return tool
    }
    override func flagsChanged(with event: NSEvent) {
        currentModifiers = event.modifierFlags
        window?.invalidateCursorRects(for: self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = pointerTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area); pointerTrackingArea = area
    }
    override func mouseMoved(with event: NSEvent) { lastMousePoint = documentPoint(event) }
    override func resignFirstResponder() -> Bool {
        if dragMode != .none { cancelOperation(nil) }
        spaceHeld = false; currentModifiers = []
        return super.resignFirstResponder()
    }
    private func resetGesture() {
        preview = nil; marquee = nil; gestureState = nil; gestureDocument = nil
        gestureColor = nil; dragMode = .none; strokePoints = []; strokeSamples = []; drawingPencil = false; resizingHandle = nil
        copyOnDrag = false; copiesCreated = false
    }
    private func sampleColor(at point: CGPoint) {
        guard document.canvasRect.contains(point) else { return }
        let color: NSColor?
        if let element = hitElement(point), element.kind != .raster && element.kind != .text {
            color = element.color.nsColor
        } else {
            color = SketchRenderer.bitmap(document: document)?.colorAt(x: Int(point.x), y: Int(point.y))
        }
        if let color, SketchColor(color) != SketchColor(strokeColor) {
            strokeColor = color; onColorChange?(color)
        }
    }
    private func panContents(dx: CGFloat, dy: CGFloat) {
        guard let before = gestureState else { return }
        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            document = before.document; panBackground = before.panBackground; cropRect = before.cropRect
            return
        }
        var moved = before.document
        var background = before.panBackground
        if background == nil, let png = before.document.backgroundPNG {
            background = PanBackground(sourcePNG: png, sourceSize: before.document.size, offset: .zero)
        }
        if var source = background {
            source.offset.x += dx; source.offset.y += dy
            guard let image = NSImage(data: source.sourcePNG),
                  let png = SketchRenderer.bitmap(size: moved.size, draw: {
                    SketchRenderer.drawImage(image, in: CGRect(origin: source.offset, size: source.sourceSize))
                  })?.representation(using: .png, properties: [:]) else { return }
            moved.backgroundPNG = png; background = source
        }
        for index in moved.elements.indices { moved.elements[index].translate(x: dx, y: dy) }
        settingPanBackground = true; document = moved; settingPanBackground = false
        panBackground = background
        if let rect = before.cropRect { cropRect = rect.offsetBy(dx: dx, dy: dy) }
    }
    private var effectiveStrokeWidth: CGFloat { strokeWidth.isFinite ? min(4096, max(0.5, strokeWidth)) : 5 }
    private func integralSize(_ size: CGSize) -> CGSize { CGSize(width: ceil(size.width), height: ceil(size.height)) }
    private func documentPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x / zoom, y: point.y / zoom)
    }
    private func documentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / zoom, y: rect.minY / zoom, width: rect.width / zoom, height: rect.height / zoom)
    }
    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
    }
    var selectionBounds: CGRect? {
        let elements = document.elements.filter { selection.contains($0.id) }
        return elements.dropFirst().reduce(elements.first?.bounds) { result, element in
            result?.union(element.bounds) ?? element.bounds
        }
    }
    private func handlePoints(for rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }
    private func hitHandle(_ point: CGPoint) -> Int? {
        guard let bounds = selectionBounds else { return nil }
        return handlePoints(for: bounds).firstIndex { hypot($0.x - point.x, $0.y - point.y) <= 8 / zoom }
    }
    private func hitElement(_ point: CGPoint) -> SketchElement? {
        let hitOrder = document.elements.filter { $0.kind != .text } + document.elements.filter { $0.kind == .text }
        return hitOrder.reversed().first { element in
            let local = point.applying(element.transform.cg.inverted())
            let tolerance = max(4 / zoom, element.strokeWidth / 2 + 2)
            switch element.kind {
            case .path:
                guard let path = try? SVGPathParser.makeCGPath(element.pathCommands) else { return false }
                if element.filled { return path.contains(local, using: .winding, transform: .identity) }
                return path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round,
                                 miterLimit: 10).contains(local)
            case .text: return element.rect.contains(local)
            case .raster:
                guard element.rect.contains(local), let png = element.imagePNG,
                      let bitmap = NSBitmapImageRep(data: png) else { return false }
                let x = min(bitmap.pixelsWide - 1, max(0, Int((local.x - element.rect.minX) / element.rect.width * CGFloat(bitmap.pixelsWide))))
                let y = min(bitmap.pixelsHigh - 1, max(0, Int((local.y - element.rect.minY) / element.rect.height * CGFloat(bitmap.pixelsHigh))))
                return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            case .rectangle:
                let rect = element.rect.standardized
                return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(local) &&
                    (element.filled || !rect.insetBy(dx: tolerance, dy: tolerance).contains(local))
            case .ellipse:
                let rect = element.rect.standardized
                guard rect.width > 0, rect.height > 0 else { return false }
                let radius = hypot((local.x - rect.midX) / (rect.width / 2), (local.y - rect.midY) / (rect.height / 2))
                let normalizedTolerance = tolerance / max(1, min(rect.width, rect.height) / 2)
                return radius <= 1 + normalizedTolerance && (element.filled || radius >= 1 - normalizedTolerance)
            case .arrow, .line, .brush:
                if element.points.count == 1, let p = element.points.first { return hypot(p.x - local.x, p.y - local.y) <= tolerance }
                if element.kind == .arrow, let end = element.points.last,
                   hypot(local.x - end.x, local.y - end.y) <= max(14, element.strokeWidth * 4) { return true }
                return zip(element.points, element.points.dropFirst()).contains { distance(local, to: $0.0, and: $0.1) <= tolerance }
            }
        }
    }
    private func distance(_ p: CGPoint, to a: CGPoint, and b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
    private func groupMembers(of element: SketchElement) -> Set<UUID> {
        guard let group = element.groupID else { return [element.id] }
        return Set(document.elements.filter { $0.groupID == group }.map(\.id))
    }
    private func styledElement(_ kind: SketchElement.Kind) -> SketchElement {
        var element = SketchElement(kind: kind)
        element.color = SketchColor(strokeColor); element.strokeWidth = effectiveStrokeWidth
        element.filled = filled; element.shadowed = shadowed
        element.fontName = fontName; element.fontSize = fontSize.isFinite ? min(4096, max(18, fontSize)) : 24
        element.outlined = outlined
        return element
    }
    override func mouseDown(with event: NSEvent) {
        finishTextEditing()
        window?.makeFirstResponder(self)
        currentModifiers = event.modifierFlags
        let point = documentPoint(event)
        lastMousePoint = point
        guard document.canvasRect.contains(point) else { return }
        resetGesture()
        gestureStart = point; gestureState = state; gestureDocument = document
        gestureColor = strokeColor; strokePoints = [point]
        strokeSamples = [strokeSample(event, at: point)]
        if spaceHeld { dragMode = .pan; needsDisplay = true; return }
        let activeTool = effectiveTool
        if [.brush, .fill, .eraser].contains(activeTool) && event.modifierFlags.contains(.option) {
            dragMode = .sampleColor; sampleColor(at: point); return
        }
        if activeTool != .eraser, !event.modifierFlags.contains(.option),
           event.clickCount >= 2, let element = hitElement(point), element.kind == .text {
            selection = [element.id]; resetGesture(); beginTextEditing(element.id); return
        }
        switch activeTool {
        case .select:
            if !event.modifierFlags.contains(.option), let handle = hitHandle(point), let bounds = selectionBounds {
                resizingHandle = handle; resizeBounds = bounds; dragMode = .resize
            } else if let element = hitElement(point) {
                let members = groupMembers(of: element)
                if event.modifierFlags.contains(.shift) {
                    if selection.isSuperset(of: members) { selection.subtract(members) } else { selection.formUnion(members) }
                } else if !selection.contains(element.id) { selection = members }
                dragMode = .move
                copyOnDrag = event.modifierFlags.contains(.option)
            } else {
                if !event.modifierFlags.contains(.shift) { selection.removeAll() }
                dragMode = .marquee; marquee = CGRect(origin: point, size: .zero)
            }
        case .fill: floodFill(at: point, grouping: !event.modifierFlags.contains(.shift)); resetGesture()
        case .eraser: dragMode = .erase
        case .crop:
            selection.removeAll(); cropRect = CGRect(origin: point, size: .zero); dragMode = .crop
        case .text:
            var element = styledElement(.text)
            element.rect = CGRect(x: point.x, y: point.y, width: max(100, min(360, canvasSize.width - point.x)), height: 90)
            document.elements.append(element); selection = [element.id]
            beginTextEditing(element.id, before: gestureState)
        default:
            guard let kind = SketchElement.Kind(rawValue: activeTool.rawValue) else { return }
            var element = styledElement(kind)
            element.points = [point, point]
            if kind == .brush {
                drawingPencil = true
                element = pencilPreview(style: element, modifiers: event.modifierFlags)
            } else { element.rect = CGRect(origin: point, size: .zero) }
            preview = element; selection.removeAll(); dragMode = .create
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if dragMode != .pan { autoscroll(with: event) }
        var point = documentPoint(event)
        lastMousePoint = point
        let dx = point.x - gestureStart.x, dy = point.y - gestureStart.y
        switch dragMode {
        case .create:
            guard var element = preview else { return }
            if drawingPencil {
                if strokeSamples.count < StrokeFitter.maximumSamples { strokeSamples.append(strokeSample(event, at: point)) }
                element = pencilPreview(style: element, modifiers: event.modifierFlags)
            } else {
                if event.modifierFlags.contains(.shift) {
                    if [.rectangle, .ellipse].contains(element.kind) {
                        let side = max(abs(dx), abs(dy))
                        point = CGPoint(x: gestureStart.x + (dx < 0 ? -side : side), y: gestureStart.y + (dy < 0 ? -side : side))
                    } else {
                        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                        let length = hypot(dx, dy)
                        point = CGPoint(x: gestureStart.x + cos(angle) * length, y: gestureStart.y + sin(angle) * length)
                    }
                }
                element.points = [gestureStart, point]
                element.rect = rect(from: gestureStart, to: point)
                if [.rectangle, .ellipse].contains(element.kind), event.modifierFlags.contains(.option) {
                    element.rect = CGRect(x: gestureStart.x - abs(point.x - gestureStart.x),
                                          y: gestureStart.y - abs(point.y - gestureStart.y),
                                          width: abs(point.x - gestureStart.x) * 2, height: abs(point.y - gestureStart.y) * 2)
                }
            }
            preview = element
        case .move:
            guard var baseline = gestureDocument else { return }
            if copyOnDrag && !copiesCreated && hypot(dx, dy) > 0.1 {
                let copies = remappedCopies(baseline.elements.filter { selection.contains($0.id) }, offset: 0)
                baseline.elements.append(contentsOf: copies); gestureDocument = baseline
                selection = Set(copies.map(\.id)); copiesCreated = true
            }
            var moved = baseline
            for index in moved.elements.indices where selection.contains(moved.elements[index].id) {
                moved.elements[index].translate(x: dx, y: dy)
            }
            document = moved
        case .resize: resizeSelected(to: point, preserveAspect: event.modifierFlags.contains(.shift))
        case .marquee: marquee = rect(from: gestureStart, to: point)
        case .crop: cropRect = rect(from: gestureStart, to: point).intersection(document.canvasRect)
        case .erase:
            if strokeSamples.count < StrokeFitter.maximumSamples {
                strokePoints.append(point); strokeSamples.append(strokeSample(event, at: point))
            }
        case .pan: panContents(dx: dx, dy: dy)
        case .sampleColor: sampleColor(at: point)
        case .none: break
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        // ToolBrush and ToolEraser do not add the zero-pressure release event.
        if dragMode != .none && dragMode != .erase && !drawingPencil { mouseDragged(with: event) }
        switch dragMode {
        case .create:
            if let element = preview,
               !element.pathCommands.isEmpty || element.kind == .brush || element.bounds.width > 0.5 || element.bounds.height > 0.5 {
                document.elements.append(element); selection = [element.id]
                if let before = gestureState { recordUndo(before, name: "Draw \(element.kind.rawValue.capitalized)") }
            }
        case .move, .resize, .pan:
            if let before = gestureState {
                let name = dragMode == .pan ? "Pan Drawing and Snap" : (dragMode == .resize ? "Resize" : (copiesCreated ? "Copy and Move" : "Move"))
                recordUndo(before, name: name)
            }
        case .marquee:
            if let rect = marquee {
                for element in document.elements where element.paintBounds.intersects(rect) { selection.formUnion(groupMembers(of: element)) }
            }
        case .erase:
            let commands = StrokeFitter.outline(samples: strokeSamples, size: effectiveStrokeWidth,
                smoothing: strokeSmoothing, shiftPrecision: event.modifierFlags.contains(.shift), nib: .eraser)
            if let mask = try? SVGPathParser.makeCGPath(commands), !mask.isEmpty { erasePath(mask.normalized()) }
        default: break
        }
        resetGesture()
        needsDisplay = true
    }
    private func strokeSample(_ event: NSEvent, at point: CGPoint) -> StrokeSample {
        let tablet = event.type == .tabletPoint || event.subtype == .tabletPoint
        return StrokeSample(point: point, pressure: tablet ? CGFloat(event.pressure) : 1)
    }
    private func pencilPreview(style: SketchElement, modifiers: NSEvent.ModifierFlags) -> SketchElement {
        var result = style
        result.kind = .path; result.points = []; result.filled = true; result.strokeWidth = 0
        result.pathCommands = StrokeFitter.outline(samples: strokeSamples, size: effectiveStrokeWidth,
            smoothing: strokeSmoothing, shiftPrecision: modifiers.contains(.shift), nib: .pencil)
        result.rect = (try? SVGPathParser.makeCGPath(result.pathCommands).boundingBoxOfPath) ?? .zero
        return result
    }
    override func tabletProximity(with event: NSEvent) {
        tabletEraser = event.isEnteringProximity && event.pointingDeviceType == .eraser
        resetCursorRects(); needsDisplay = true
    }

    // AppKit may deliver Control-click as a secondary-button event; it is still a pen eraser gesture.
    override func rightMouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { mouseDown(with: event) } else { super.rightMouseDown(with: event) }
    }
    override func rightMouseDragged(with event: NSEvent) {
        if dragMode != .none { mouseDragged(with: event) } else { super.rightMouseDragged(with: event) }
    }
    override func rightMouseUp(with event: NSEvent) {
        if dragMode != .none { mouseUp(with: event) } else { super.rightMouseUp(with: event) }
    }
    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    private func resizeSelected(to point: CGPoint, preserveAspect: Bool) {
        guard let handle = resizingHandle, let before = gestureState else { return }
        let old = resizeBounds
        var left = old.minX, right = old.maxX, top = old.minY, bottom = old.maxY
        if [0, 6, 7].contains(handle) { left = min(point.x, right - 1) }
        if [2, 3, 4].contains(handle) { right = max(point.x, left + 1) }
        if [0, 1, 2].contains(handle) { top = min(point.y, bottom - 1) }
        if [4, 5, 6].contains(handle) { bottom = max(point.y, top + 1) }
        var sx = (right - left) / max(1, old.width), sy = (bottom - top) / max(1, old.height)
        if preserveAspect {
            let uniform = max(sx, sy); sx = uniform; sy = uniform
            if [0, 6, 7].contains(handle) { left = old.maxX - old.width * uniform }
            if [0, 1, 2].contains(handle) { top = old.maxY - old.height * uniform }
        }
        let matrix = SketchTransform(a: sx, d: sy, tx: left - old.minX * sx, ty: top - old.minY * sy)
        var resized = before.document
        for index in resized.elements.indices where selection.contains(resized.elements[index].id) {
            resized.elements[index].transform = resized.elements[index].transform.followed(by: matrix)
        }
        document = resized
    }

    // MARK: Text editor and responder commands

    private func textHeight(for element: SketchElement) -> CGFloat {
        let measured = (element.text as NSString).boundingRect(
            with: NSSize(width: max(1, element.rect.width), height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont(name: element.fontName, size: element.fontSize) ?? NSFont.boldSystemFont(ofSize: element.fontSize),
                         .paragraphStyle: SketchRenderer.textParagraphStyle])
        return max(element.fontSize * 1.5, ceil(measured.height) + 8)
    }
    private func documentIncludingPendingText() -> SketchDocument {
        var snapshot = document
        guard let editor = textEditor, let id = editingTextID,
              let index = snapshot.elements.firstIndex(where: { $0.id == id }) else { return snapshot }
        if editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.elements.remove(at: index)
        } else if snapshot.elements[index].text != editor.string {
            snapshot.elements[index].text = editor.string
            snapshot.elements[index].rect.size.height = textHeight(for: snapshot.elements[index])
        }
        return snapshot
    }
    private func beginTextEditing(_ id: UUID, before: EditorState? = nil) {
        guard let element = document.elements.first(where: { $0.id == id }) else { return }
        textBeforeEditing = before ?? state
        resetGesture()
        editingTextID = id
        let editor = SketchTextEditor(frame: viewRect(element.bounds))
        editor.isRichText = false; editor.isEditable = true; editor.isSelectable = true
        editor.allowsUndo = true; editor.drawsBackground = true
        editor.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96)
        editor.font = NSFont(name: element.fontName, size: max(18, element.fontSize * zoom)) ??
            NSFont.boldSystemFont(ofSize: max(18, element.fontSize * zoom))
        editor.textColor = element.color.nsColor
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.string = element.text
        editor.delegate = self
        editor.setAccessibilityLabel("Annotation text")
        textEditor = editor; addSubview(editor)
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        needsDisplay = true
    }
    func textDidChange(_ notification: Notification) {
        guard !isFinishingText, let editor = textEditor, notification.object as? NSTextView === editor else { return }
        needsDisplay = true
        onChange?()
    }
    func textDidEndEditing(_ notification: Notification) { finishTextEditing() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            finishTextEditing(); return true
        }
        return false
    }
    /// Commit after a successful save or before entering frame preview. Validation
    /// and failed saves can leave the editor and native typing history intact.
    func commitPendingTextEditing() { finishTextEditing() }
    private func finishTextEditing(cancel: Bool = false) {
        guard !isFinishingText, let editor = textEditor, let id = editingTextID else { return }
        let hadPendingChanges = hasPendingTextChanges
        isFinishingText = true
        let before = textBeforeEditing
        if cancel, let before {
            document = before.document; selection = before.selection
            panBackground = before.panBackground
        } else {
            document = documentIncludingPendingText()
            if !document.elements.contains(where: { $0.id == id }) { selection.remove(id) }
        }
        let returnFocusToCanvas = window?.firstResponder === editor
        editor.delegate = nil
        textEditor = nil; editingTextID = nil; textBeforeEditing = nil
        editor.removeFromSuperview()
        if returnFocusToCanvas { window?.makeFirstResponder(self) }
        isFinishingText = false
        if !cancel, let before { recordUndo(before, name: "Edit Text") }
        if cancel && hadPendingChanges { onChange?() }
        needsDisplay = true
    }
    private func startTyping(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, textEditor == nil, dragMode == .none, !spaceHeld,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
              }) else { return false }
        var point = lastMousePoint
        if point == nil, let window {
            let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let pointer = CGPoint(x: viewPoint.x / zoom, y: viewPoint.y / zoom)
            if document.canvasRect.contains(pointer) { point = pointer }
        }
        let visible = documentRect(visibleRect).intersection(document.canvasRect)
        let fallback = visible.isNull ? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2) :
            CGPoint(x: visible.midX, y: visible.midY)
        var element = styledElement(.text)
        let anchor = point ?? fallback
        let x = min(max(0, anchor.x), max(0, canvasSize.width - min(100, canvasSize.width)))
        let y = min(max(0, anchor.y), max(0, canvasSize.height - min(element.fontSize * 1.5, canvasSize.height)))
        element.rect = CGRect(x: x, y: y, width: min(360, canvasSize.width - x), height: min(90, canvasSize.height - y))
        let before = state
        document.elements.append(element); selection = [element.id]
        beginTextEditing(element.id, before: before)
        // Forward the original event through native text input, including composed
        // characters, rather than assigning its string and bypassing typing undo.
        textEditor?.keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.command) && event.keyCode == 49 {
            spaceHeld = true; window?.invalidateCursorRects(for: self); return
        }
        if event.keyCode == 48 && !event.isARepeat && !event.modifierFlags.contains(.command) && dragMode == .none {
            togglingPencil = true
            if tool == .brush {
                if let previous = pencilReturnTool { tool = previous; pencilReturnTool = nil }
            } else {
                pencilReturnTool = tool; tool = .brush
            }
            togglingPencil = false; return
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z": event.modifierFlags.contains(.shift) ? redo() : undo()
            case "a": selectAll()
            case "c": copySelection()
            case "v": paste()
            case "x": copySelection(); deleteSelection()
            case "d": duplicateSelection()
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 51, 117: deleteSelection()
        case 53: textEditor != nil ? finishTextEditing() : cancelOperation(nil)
        case 36, 76: if tool == .crop { cropSelection() }
        case 123, 124, 125, 126:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
            let dy: CGFloat = event.keyCode == 126 ? -step : (event.keyCode == 125 ? step : 0)
            edit("Nudge") {
                for index in document.elements.indices where selection.contains(document.elements[index].id) {
                    document.elements[index].translate(x: dx, y: dy)
                }
            }
        default: if !startTyping(with: event) { super.keyDown(with: event) }
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false; window?.invalidateCursorRects(for: self); return }
        super.keyUp(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        // Programmatic cancellation retains explicit abandonment semantics; the
        // native editor/keyboard Escape handlers above commit the text instead.
        if textEditor != nil { finishTextEditing(cancel: true); return }
        if let before = gestureState {
            document = before.document; panBackground = before.panBackground
            selection = before.selection; cropRect = before.cropRect
            if dragMode == .sampleColor, let previous = gestureColor, SketchColor(previous) != SketchColor(strokeColor) {
                strokeColor = previous; onColorChange?(previous)
            }
        } else {
            selection.removeAll(); cropRect = nil
        }
        resetGesture(); needsDisplay = true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Window key equivalents visit views even when an unrelated name field or
        // NSTextView is focused. Let that responder retain its own edit shortcuts.
        guard window?.firstResponder === self else { return false }
        guard event.modifierFlags.contains(.command), textEditor == nil,
              let key = event.charactersIgnoringModifiers?.lowercased(), ["z", "a", "c", "v", "x", "d"].contains(key) else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event); return true
    }
    // Standard responder actions support menu items even when the shell uses selectors.
    @objc func copy(_ sender: Any?) { copySelection() }
    @objc func paste(_ sender: Any?) { paste() }
    @objc func cut(_ sender: Any?) { copySelection(); deleteSelection() }
    @objc func delete(_ sender: Any?) { deleteSelection() }
    override func selectAll(_ sender: Any?) { selectAll() }
    @objc func undo(_ sender: Any?) { undo() }
    @objc func redo(_ sender: Any?) { redo() }
}
