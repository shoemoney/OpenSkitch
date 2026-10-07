import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class SketchTextEditor: NSTextView {
    // Native typing history stays separate from document transactions. Committing
    // an annotation registers one canvas undo step, regardless of keystroke count.
    private let typingHistory = UndoManager()
    override var undoManager: UndoManager? { typingHistory }
}

/// Native AppKit canvas. All model geometry stays in top-left document pixels.
/// Assign as NSScrollView.documentView; frame/intrinsic size follow canvasSize * zoom.
final class CanvasView: NSView, NSTextViewDelegate {
    var tool: SketchTool = .arrow { didSet { finishTextEditing(); needsDisplay = true; resetCursorRects() } }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 5
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
    var document = SketchDocument() { didSet { updateCanvasSize(); needsDisplay = true } }
    var onChange: (() -> Void)?
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
    private var dragMode: DragMode = .none
    private var resizingHandle: Int?
    private var resizeBounds: CGRect = .zero
    private var strokePoints: [CGPoint] = []
    private var textEditor: NSTextView?
    private var editingTextID: UUID?
    private var textBeforeEditing: EditorState?
    private var isFinishingText = false
    private var pasteOffset: CGFloat = 0
    private static let pasteboardType = NSPasteboard.PasteboardType("com.skitch-redux.editable-selection")
    private enum DragMode { case none, create, move, resize, marquee, crop, erase }
    private struct EditorState {
        var document: SketchDocument
        var selection: Set<UUID>
        var cropRect: CGRect?
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
    private var state: EditorState { EditorState(document: document, selection: selection, cropRect: cropRect) }
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
        guard before.document != document else { return }
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
    func undo() { finishTextEditing(); editingUndoManager.undo() }
    func redo() { finishTextEditing(); editingUndoManager.redo() }
    func setZoom(_ value: CGFloat) { zoom = value }

    func newBlank(size: NSSize) {
        guard SketchDocument.validSize(size) else { return }
        edit("New Canvas") {
            document = SketchDocument(size: integralSize(size))
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
            document.size = size; document.backgroundPNG = png
            selection.removeAll(); cropRect = nil
        }
    }
    func setBackgroundColor(_ color: NSColor) {
        edit("Background Color") { document.backgroundColor = SketchColor(color) }
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
    func documentData() throws -> Data { finishTextEditing(); return try document.encoded() }
    /// Recovery/autosave serialization. Does not end typing, change the live model,
    /// register undo, move the caret, or notify onChange. Empty pending text is omitted.
    func snapshotDocumentData() throws -> Data { try documentIncludingPendingText().encoded() }
    func loadDocument(data: Data) throws {
        let loaded = try SketchDocument.decode(data)
        finishTextEditing()
        document = loaded
        selection.removeAll(); cropRect = nil; preview = nil
        gestureState = nil; dragMode = .none
        editingUndoManager.removeAllActions()
        onChange?()
    }

    // MARK: Pixel tools

    /// A four-connected scanline flood fill samples the visible composite but adds a
    /// transparent raster overlay; it does not destroy editable objects underneath.
    func floodFill(at point: CGPoint) {
        finishTextEditing()
        var fillSource = document
        fillSource.elements.removeAll { $0.kind == .text }
        guard document.canvasRect.contains(point), let bitmap = SketchRenderer.bitmap(document: fillSource),
              let bytes = bitmap.bitmapData else { return }
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh, stride = bitmap.bytesPerRow
        let sx = Int(point.x), sy = Int(point.y)
        let start = sy * stride + sx * 4
        let target = (bytes[start], bytes[start + 1], bytes[start + 2], bytes[start + 3])
        let tolerance = 12
        func matches(_ x: Int, _ y: Int) -> Bool {
            let i = y * stride + x * 4
            return abs(Int(bytes[i]) - Int(target.0)) <= tolerance &&
                abs(Int(bytes[i + 1]) - Int(target.1)) <= tolerance &&
                abs(Int(bytes[i + 2]) - Int(target.2)) <= tolerance &&
                abs(Int(bytes[i + 3]) - Int(target.3)) <= tolerance
        }
        guard let overlay = SketchRenderer.bitmap(size: canvasSize, draw: {}), let output = overlay.bitmapData else { return }
        var visited = [UInt8](repeating: 0, count: width * height)
        var stack: [(Int, Int)] = [(sx, sy)]
        let color = SketchColor(strokeColor)
        let alpha = UInt8((color.alpha * 255).rounded())
        // NSBitmapImageRep uses premultiplied RGBA by default.
        let rgba: [UInt8] = [UInt8((color.red * CGFloat(alpha)).rounded()),
            UInt8((color.green * CGFloat(alpha)).rounded()), UInt8((color.blue * CGFloat(alpha)).rounded()), alpha]
        if alpha == 0 || rgba == [target.0, target.1, target.2, target.3] { return }
        var minX = width, minY = height, maxX = 0, maxY = 0
        while let (x, y) = stack.popLast() {
            if visited[y * width + x] != 0 || !matches(x, y) { continue }
            var left = x, right = x
            while left > 0 && visited[y * width + left - 1] == 0 && matches(left - 1, y) { left -= 1 }
            while right + 1 < width && visited[y * width + right + 1] == 0 && matches(right + 1, y) { right += 1 }
            for px in left...right {
                visited[y * width + px] = 1
                let out = y * overlay.bytesPerRow + px * 4
                for channel in 0..<4 { output[out + channel] = rgba[channel] }
            }
            minX = min(minX, left); maxX = max(maxX, right); minY = min(minY, y); maxY = max(maxY, y)
            for nextY in [y - 1, y + 1] where nextY >= 0 && nextY < height {
                var inSpan = false
                for px in left...right {
                    let eligible = visited[nextY * width + px] == 0 && matches(px, nextY)
                    if eligible && !inSpan { stack.append((px, nextY)) }
                    inSpan = eligible
                }
            }
        }
        guard minX <= maxX, minY <= maxY else { return }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let image = NSImage(size: canvasSize); image.addRepresentation(overlay)
        guard let png = SketchRenderer.bitmap(size: rect.size, draw: {
            SketchRenderer.drawImage(image, in: CGRect(x: -rect.minX, y: -rect.minY, width: canvasSize.width, height: canvasSize.height))
        })?.representation(using: .png, properties: [:]) else { return }
        let contacts = fillContacts(mask: visited, width: width, height: height, region: rect)
        edit("Flood Fill") {
            var element = SketchElement(kind: .raster)
            element.rect = rect; element.imagePNG = png
            if !contacts.isEmpty {
                let group = UUID()
                for index in document.elements.indices where contacts.contains(document.elements[index].id) {
                    document.elements[index].groupID = group
                }
                element.groupID = group
            }
            document.elements.append(element); selection = contacts.union([element.id])
        }
    }
    /// Flood-filled pixels glue only annotations whose actual painted pixels contact
    /// the region (not every shape with an overlapping bounding box).
    private func fillContacts(mask: [UInt8], width: Int, height: Int, region: CGRect) -> Set<UUID> {
        var contacts: Set<UUID> = []
        for element in document.elements where element.kind != .text && element.paintBounds.intersects(region.insetBy(dx: -2, dy: -2)) {
            let rect = element.paintBounds.integral.intersection(document.canvasRect)
            guard let bitmap = SketchRenderer.bitmap(size: rect.size, draw: {
                NSGraphicsContext.current?.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                SketchRenderer.draw(element)
            }), let pixels = bitmap.bitmapData else { continue }
            var touches = false
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 8 {
                    let px = Int(rect.minX) + x, py = Int(rect.minY) + y
                    for (nx, ny) in [(px, py), (px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                        if nx >= 0 && nx < width && ny >= 0 && ny < height && mask[ny * width + nx] != 0 { touches = true; break }
                    }
                    if touches { break }
                }
                if touches { break }
            }
            if touches { contacts.formUnion(groupMembers(of: element)) }
        }
        return contacts
    }

    /// Line/freehand outlines split into independent editable fragments. Filled areas
    /// and existing raster marks use real pixel clearing. Photos and text are untouched.
    func eraseStroke(points: [CGPoint], width: CGFloat) {
        guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              width.isFinite, width > 0 else { return }
        finishTextEditing()
        var pathElement = SketchElement(kind: .brush)
        pathElement.points = points; pathElement.strokeWidth = min(4096, width)
        let affected = pathElement.paintBounds
        edit("Erase") {
            var result: [SketchElement] = []
            for original in document.elements {
                guard original.kind != .text, original.paintBounds.intersects(affected) else {
                    result.append(original); continue
                }
                if [.line, .arrow, .brush].contains(original.kind) ||
                    ([.rectangle, .ellipse].contains(original.kind) && !original.filled) {
                    result.append(contentsOf: splitElement(original, eraser: points, width: pathElement.strokeWidth))
                } else {
                    result.append(erasedElement(original, points: points, width: pathElement.strokeWidth) ?? original)
                }
            }
            document.elements = result
            selection.formIntersection(Set(result.map(\.id)))
        }
    }
    /// Subtract analytical eraser capsules from each line segment. Intersections are
    /// evaluated in world coordinates so rotated/flipped paths still split correctly.
    private func splitElement(_ element: SketchElement, eraser: [CGPoint], width: CGFloat) -> [SketchElement] {
        var local = element.points
        if element.kind == .rectangle {
            let r = element.rect.standardized
            local = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                     CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)]
        } else if element.kind == .ellipse {
            let r = element.rect.standardized
            let steps = min(2048, max(64, Int(ceil(max(r.width, r.height) * .pi / 2))))
            local = (0...steps).map { index in
                let angle = CGFloat(index) / CGFloat(steps) * 2 * .pi
                return CGPoint(x: r.midX + cos(angle) * r.width / 2, y: r.midY + sin(angle) * r.height / 2)
            }
        }
        let path = local.map { element.transform.applying($0) }
        let scale = max(hypot(element.transform.a, element.transform.b), hypot(element.transform.c, element.transform.d))
        let worldWidth = element.strokeWidth * scale
        let radius = (width + worldWidth) / 2
        if path.count == 1, let point = path.first {
            let touches = eraser.count == 1 ? hypot(point.x - eraser[0].x, point.y - eraser[0].y) <= radius :
                zip(eraser, eraser.dropFirst()).contains { distance(point, to: $0.0, and: $0.1) <= radius }
            return touches ? [] : [element]
        }
        var fragments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var didCut = false
        func flush() {
            if current.count >= 2 { fragments.append(current) }
            current = []
        }
        for (a, b) in zip(path, path.dropFirst()) {
            let cuts = erasedIntervals(from: a, to: b, eraser: eraser, radius: radius)
            if !cuts.isEmpty { didCut = true }
            var cursor: CGFloat = 0
            let keeps: [(CGFloat, CGFloat)] = cuts.map { interval -> (CGFloat, CGFloat) in
                defer { cursor = max(cursor, interval.1) }
                return (cursor, interval.0)
            } + [(cuts.last?.1 ?? 0, 1)]
            for (low, high) in keeps where high - low > 0.000001 {
                let start = CGPoint(x: a.x + (b.x - a.x) * low, y: a.y + (b.y - a.y) * low)
                let end = CGPoint(x: a.x + (b.x - a.x) * high, y: a.y + (b.y - a.y) * high)
                if let previous = current.last, hypot(previous.x - start.x, previous.y - start.y) > 0.001 { flush() }
                if current.isEmpty { current.append(start) }
                current.append(end)
                if high < 0.999999 { flush() }
            }
            if keeps.allSatisfy({ $0.1 - $0.0 <= 0.000001 }) { flush() }
        }
        flush()
        guard didCut else { return [element] }
        // Closed outlines may join around the original path's start after a cut.
        if fragments.count > 1, let first = fragments.first?.first, let last = fragments.last?.last,
           hypot(first.x - last.x, first.y - last.y) < 0.001 {
            let tail = fragments.removeLast()
            fragments[0] = tail + fragments[0].dropFirst()
        }
        return fragments.enumerated().map { index, points in
            var fragment = element
            fragment.id = index == 0 ? element.id : UUID()
            fragment.groupID = nil // Erased pieces must be independently movable.
            fragment.kind = [.rectangle, .ellipse].contains(element.kind) ? .brush : element.kind
            if element.kind == .arrow, let oldEnd = path.last, let end = points.last,
               hypot(oldEnd.x - end.x, oldEnd.y - end.y) > 0.001 { fragment.kind = .line }
            fragment.transform = .identity; fragment.points = points
            fragment.strokeWidth = worldWidth
            fragment.filled = false
            return fragment
        }
    }
    private func erasedIntervals(from p: CGPoint, to q: CGPoint, eraser: [CGPoint], radius: CGFloat) -> [(CGFloat, CGFloat)] {
        let vx = q.x - p.x, vy = q.y - p.y
        let lengthSquared = vx * vx + vy * vy
        var intervals: [(CGFloat, CGFloat)] = []
        func circle(_ center: CGPoint) {
            let dx = p.x - center.x, dy = p.y - center.y
            if lengthSquared < 0.00000001 {
                if dx * dx + dy * dy <= radius * radius { intervals.append((0, 1)) }
                return
            }
            let linear = 2 * (dx * vx + dy * vy)
            let constant = dx * dx + dy * dy - radius * radius
            let discriminant = linear * linear - 4 * lengthSquared * constant
            guard discriminant >= 0 else { return }
            let low = max(0, (-linear - sqrt(discriminant)) / (2 * lengthSquared))
            let high = min(1, (-linear + sqrt(discriminant)) / (2 * lengthSquared))
            if low <= high { intervals.append((low, high)) }
        }
        for center in eraser { circle(center) }
        for (a, b) in zip(eraser, eraser.dropFirst()) {
            let ex = b.x - a.x, ey = b.y - a.y
            let length = hypot(ex, ey)
            if length < 0.00001 { continue }
            let ux = ex / length, uy = ey / length
            var low: CGFloat = 0, high: CGFloat = 1
            func slab(origin: CGFloat, delta: CGFloat, min: CGFloat, max: CGFloat) -> Bool {
                if abs(delta) < 0.00000001 { return origin >= min && origin <= max }
                let t0 = (min - origin) / delta, t1 = (max - origin) / delta
                low = Swift.max(low, Swift.min(t0, t1)); high = Swift.min(high, Swift.max(t0, t1))
                return low <= high
            }
            let dx = p.x - a.x, dy = p.y - a.y
            if slab(origin: dx * ux + dy * uy, delta: vx * ux + vy * uy, min: 0, max: length) &&
                slab(origin: -dx * uy + dy * ux, delta: -vx * uy + vy * ux, min: -radius, max: radius) {
                intervals.append((low, high))
            }
        }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var merged: [(CGFloat, CGFloat)] = []
        for interval in sorted {
            if let last = merged.last, interval.0 <= last.1 + 0.000001 {
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else { merged.append(interval) }
        }
        return merged
    }
    private func erasedElement(_ element: SketchElement, points: [CGPoint], width: CGFloat) -> SketchElement? {
        let rect = element.paintBounds.integral.intersection(document.canvasRect)
        guard SketchDocument.validSize(rect.size) else { return nil }
        var originalPixels: Data?
        guard let bitmap = SketchRenderer.bitmap(size: rect.size, draw: {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.translateBy(x: -rect.minX, y: -rect.minY)
            SketchRenderer.draw(element)
            // Clear with Core Graphics blending rather than painting background-colored ink.
            context.setShadow(offset: .zero, blur: 0, color: nil)
            if let data = context.data { originalPixels = Data(bytes: data, count: context.bytesPerRow * context.height) }
            context.setBlendMode(.clear)
            context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round)
            if points.count == 1, let point = points.first {
                context.fillEllipse(in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
            } else if let point = points.first {
                context.beginPath(); context.move(to: point)
                for next in points.dropFirst() { context.addLine(to: next) }
                context.strokePath()
            }
        }), let pixels = bitmap.bitmapData,
           originalPixels != Data(bytes: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh),
           let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        var erased = SketchElement(kind: .raster)
        erased.id = element.id; erased.groupID = element.groupID
        erased.rect = rect; erased.imagePNG = png
        return erased
    }

    // MARK: Drawing and interaction

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.scaleBy(x: zoom, y: zoom)
        drawCheckerboard(in: document.canvasRect)
        var visible = document
        if let id = editingTextID { visible.elements.removeAll { $0.id == id } }
        SketchRenderer.draw(visible)
        if let preview { SketchRenderer.draw(preview) }
        NSGraphicsContext.restoreGraphicsState()
        drawSelectionChrome()
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
            NSBezierPath(ovalIn: viewRect(CGRect(x: point.x - effectiveStrokeWidth / 2,
                y: point.y - effectiveStrokeWidth / 2, width: effectiveStrokeWidth, height: effectiveStrokeWidth))).stroke()
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : (tool == .text ? .iBeam : .crosshair))
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
        let point = documentPoint(event)
        guard document.canvasRect.contains(point) else { return }
        gestureStart = point; gestureState = state; strokePoints = [point]
        dragMode = .none; resizingHandle = nil
        if event.clickCount >= 2, let element = hitElement(point), element.kind == .text {
            selection = [element.id]; beginTextEditing(element.id); return
        }
        let activeTool: SketchTool = event.modifierFlags.contains(.command) ? .select : tool
        if activeTool == .brush && event.modifierFlags.contains(.option) {
            if let bitmap = SketchRenderer.bitmap(document: document),
               let color = bitmap.colorAt(x: Int(point.x), y: Int(point.y)) { strokeColor = color; onChange?() }
            gestureState = nil
            return
        }
        switch activeTool {
        case .select:
            if let handle = hitHandle(point), let bounds = selectionBounds {
                resizingHandle = handle; resizeBounds = bounds; dragMode = .resize
            } else if let element = hitElement(point) {
                let members = groupMembers(of: element)
                if event.modifierFlags.contains(.shift) {
                    if selection.isSuperset(of: members) { selection.subtract(members) } else { selection.formUnion(members) }
                } else if !selection.contains(element.id) { selection = members }
                dragMode = .move
            } else {
                if !event.modifierFlags.contains(.shift) { selection.removeAll() }
                dragMode = .marquee; marquee = CGRect(origin: point, size: .zero)
            }
            // Snapshot after selecting so moving undo preserves the selected objects.
            gestureState = state
        case .fill: floodFill(at: point)
        case .eraser: dragMode = .erase
        case .crop:
            selection.removeAll(); cropRect = CGRect(origin: point, size: .zero); dragMode = .crop
        case .text:
            var element = styledElement(.text)
            element.rect = CGRect(x: point.x, y: point.y, width: max(100, min(360, canvasSize.width - point.x)), height: 90)
            document.elements.append(element); selection = [element.id]
            beginTextEditing(element.id, before: gestureState)
        default:
            guard let kind = SketchElement.Kind(rawValue: tool.rawValue) else { return }
            var element = styledElement(kind)
            element.points = [point, point]
            if kind == .brush { element.points = [point] }
            element.rect = CGRect(origin: point, size: .zero)
            preview = element; selection.removeAll(); dragMode = .create
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        autoscroll(with: event)
        var point = documentPoint(event)
        let dx = point.x - gestureStart.x, dy = point.y - gestureStart.y
        switch dragMode {
        case .create:
            guard var element = preview else { return }
            if element.kind == .brush {
                if let previous = element.points.last, hypot(previous.x - point.x, previous.y - point.y) > 0.1 {
                    element.points.append(point)
                }
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
            guard let before = gestureState else { return }
            var moved = before.document
            for index in moved.elements.indices where selection.contains(moved.elements[index].id) {
                moved.elements[index].translate(x: dx, y: dy)
            }
            document = moved
        case .resize: resizeSelected(to: point, preserveAspect: event.modifierFlags.contains(.shift))
        case .marquee: marquee = rect(from: gestureStart, to: point)
        case .crop: cropRect = rect(from: gestureStart, to: point).intersection(document.canvasRect)
        case .erase: strokePoints.append(point)
        case .none: break
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if dragMode != .none { mouseDragged(with: event) }
        switch dragMode {
        case .create:
            if let element = preview,
               element.kind == .brush || element.bounds.width > 0.5 || element.bounds.height > 0.5 {
                document.elements.append(element); selection = [element.id]
                if let before = gestureState { recordUndo(before, name: "Draw \(element.kind.rawValue.capitalized)") }
            }
        case .move, .resize:
            if let before = gestureState { recordUndo(before, name: dragMode == .move ? "Move" : "Resize") }
        case .marquee:
            if let rect = marquee {
                for element in document.elements where element.paintBounds.intersects(rect) { selection.formUnion(groupMembers(of: element)) }
            }
        case .erase: eraseStroke(points: strokePoints, width: effectiveStrokeWidth)
        default: break
        }
        preview = nil; marquee = nil; gestureState = nil; dragMode = .none; strokePoints = []
        needsDisplay = true
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
            finishTextEditing(cancel: true); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            finishTextEditing(); return true
        }
        return false
    }
    private func finishTextEditing(cancel: Bool = false) {
        guard !isFinishingText, let editor = textEditor, let id = editingTextID else { return }
        let hadPendingChanges = hasPendingTextChanges
        isFinishingText = true
        let before = textBeforeEditing
        if cancel, let before {
            document = before.document; selection = before.selection
        } else {
            document = documentIncludingPendingText()
            if !document.elements.contains(where: { $0.id == id }) { selection.remove(id) }
        }
        editor.delegate = nil
        textEditor = nil; editingTextID = nil; textBeforeEditing = nil
        editor.removeFromSuperview()
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        isFinishingText = false
        if !cancel, let before { recordUndo(before, name: "Edit Text") }
        if cancel && hadPendingChanges { onChange?() }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
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
        case 53: cancelOperation(nil)
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
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) {
        if textEditor != nil { finishTextEditing(cancel: true); return }
        if let before = gestureState { document = before.document; selection = before.selection }
        preview = nil; marquee = nil; cropRect = nil; gestureState = nil; dragMode = .none
        selection.removeAll(); needsDisplay = true
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
