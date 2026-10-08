import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class SketchTextLayoutManager: NSLayoutManager {
    var annotationAlpha: CGFloat = 1
    var annotationOutline: CGFloat?
    var annotationOutlineColor: NSColor = .white
    var annotationShadowed = false
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return
        }
        context.saveGState()
        context.setLineJoin(.round)
        context.setAlpha(annotationAlpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setAlpha(1)
        if annotationShadowed { OriginalTextEffects.shadow().set() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Rendering attributes are temporary: typing history and staged style
        // stay owned by the text storage. Both passes cast one group shadow.
        addTemporaryAttributes([.shadow: NSShadow(), .strokeWidth: annotationOutline ?? 0,
                                .strokeColor: annotationOutlineColor], forCharacterRange: characters)
        if annotationOutline != nil { super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin) }
        addTemporaryAttribute(.strokeWidth, value: CGFloat(0), forCharacterRange: characters)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        for key in [NSAttributedString.Key.strokeWidth, .strokeColor, .shadow] {
            removeTemporaryAttribute(key, forCharacterRange: characters)
        }
        context.endTransparencyLayer()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

private final class SketchTextEditor: NSTextView {
    // Native typing history stays separate from document transactions. Committing
    // an annotation registers one canvas undo step, regardless of keystroke count.
    private let typingHistory = UndoManager()
    private var refreshingStyle = false
    private var fittingFrame = false
    private func naturalFrameSize(_ requested: NSSize) -> NSSize {
        guard let font, !string.isEmpty else { return requested }
        return OriginalTextGeometry.size(text: string, font: font)
    }
    override func setFrameSize(_ newSize: NSSize) {
        guard !fittingFrame else { super.setFrameSize(newSize); return }
        fittingFrame = true
        defer { fittingFrame = false }
        super.setFrameSize(naturalFrameSize(newSize))
    }
    override var frame: NSRect {
        get { super.frame }
        set {
            guard !fittingFrame else { super.frame = newValue; return }
            fittingFrame = true
            defer { fittingFrame = false }
            super.frame = NSRect(origin: newValue.origin, size: naturalFrameSize(newValue.size))
        }
    }
    private var annotationStyle: (SketchElement, CGFloat)?
    private var styleObservers: [NSObjectProtocol] = []
    deinit { for observer in styleObservers { NotificationCenter.default.removeObserver(observer) } }
    func applyAnnotationStyle(_ element: SketchElement, scale: CGFloat) {
        guard !refreshingStyle else { return }
        annotationStyle = (element, scale)
        if styleObservers.isEmpty {
            for name in [NSNotification.Name.NSUndoManagerDidUndoChange, NSNotification.Name.NSUndoManagerDidRedoChange] {
                styleObservers.append(NotificationCenter.default.addObserver(forName: name, object: typingHistory, queue: nil) { [weak self] _ in
                    guard let self, let (element, scale) = self.annotationStyle else { return }
                    self.applyAnnotationStyle(element, scale: scale)
                })
            }
        }
        refreshingStyle = true
        defer { refreshingStyle = false }
        let caret = selectedRange()
        let displayedSize = max(18, element.fontSize * scale)
        let displayedFont = NSFont(name: element.fontName, size: displayedSize) ?? .boldSystemFont(ofSize: displayedSize)
        if !(layoutManager is SketchTextLayoutManager) {
            textContainer?.replaceLayoutManager(SketchTextLayoutManager())
        }
        if let manager = layoutManager as? SketchTextLayoutManager {
            manager.annotationAlpha = element.color.alpha
            manager.annotationOutline = element.outlined ? OriginalTextEffects.outlinePercentage(fontSize: displayedSize) : nil
            manager.annotationOutlineColor = OriginalTextEffects.outlineColor(element.color)
            manager.annotationShadowed = element.shadowed
        }
        // Native typing Undo restores attributed strings as well as words. The
        // annotation's staged style remains authoritative throughout editing.
        if font != displayedFont { font = displayedFont }
        textColor = element.color.nsColor.withAlphaComponent(1)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: displayedFont, .foregroundColor: element.color.nsColor.withAlphaComponent(1),
            .paragraphStyle: SketchRenderer.textParagraphStyle
        ]
        if element.outlined {
            attributes[.strokeColor] = OriginalTextEffects.outlineColor(element.color)
            attributes[.strokeWidth] = -OriginalTextEffects.outlinePercentage(fontSize: displayedSize)
        }
        if element.shadowed {
            attributes[.shadow] = OriginalTextEffects.shadow()
        }
        let range = NSRange(location: 0, length: (string as NSString).length)
        textStorage?.beginEditing()
        for key in [NSAttributedString.Key.strokeColor, .strokeWidth, .shadow] where attributes[key] == nil {
            textStorage?.removeAttribute(key, range: range)
        }
        textStorage?.addAttributes(attributes, range: range)
        textStorage?.endEditing()
        typingAttributes = attributes
        setSelectedRange(caret)
        fitContents()
        needsDisplay = true
    }
    func fitContents() {
        guard let font, !string.isEmpty else { return }
        let fitted = OriginalTextGeometry.size(text: string, font: font)
        // Set both dimensions explicitly so a previous larger frame cannot act
        // as a minimum after typing Undo, a font change, or zooming out.
        let horizontal = isHorizontallyResizable, vertical = isVerticallyResizable
        isHorizontallyResizable = false; isVerticallyResizable = false
        minSize = .zero
        setFrameSize(fitted)
        isHorizontallyResizable = horizontal; isVerticallyResizable = vertical
    }
    override var undoManager: UndoManager? { typingHistory }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.font = .systemFont(ofSize: 20)
        guard delegate is CanvasView else { return menu }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Skitch Text Style…", action: #selector(showTextStyle), keyEquivalent: "")
        item.target = self; menu.addItem(item)
        return menu
    }
    @objc private func showTextStyle() { (delegate as? CanvasView)?.onTextStyleRequested?() }
    override func keyDown(with event: NSEvent) {
        // SkitchTextFieldEditor keyDown: (0x1cae8). The original 0x200000
        // flag is numericPad, not Command; keypad Enter carries it normally.
        let flags = event.modifierFlags
        let finish = event.keyCode == 53 ||
            (event.keyCode == 36 && flags.contains(.option)) ||
            (event.keyCode == 76 && (flags.contains(.numericPad) || flags.rawValue < 0x10000))
        if finish, let canvas = delegate as? CanvasView {
            canvas.commitPendingTextEditing(); return
        }
        super.keyDown(with: event)
    }
}

/// Recovered SkitchTextGrip geometry and drag contract. The exposed left pill
/// sits behind the field editor, so its contents retain normal native text input.
private final class SketchTextGrip: NSView {
    var onMove: ((CGSize) -> Void)?
    var color: NSColor = .systemRed
    private var previousCursor: NSCursor?
    private var lastDragLocation: CGPoint?
    private var frameObserver: NSObjectProtocol?
    func attach(to editor: NSTextView) {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        editor.postsFrameChangedNotifications = true
        frame = Self.attachedFrame(editor.frame)
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: editor, queue: nil) { [weak self, weak editor] _ in
                guard let self, let editor else { return }
                self.frame = Self.attachedFrame(editor.frame); self.needsDisplay = true
            }
    }
    deinit { if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) } }
    private static let moveCursor: NSCursor = {
        if let url = Bundle.main.url(forResource: "CursorMove", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return NSCursor(image: image, hotSpot: CGPoint(x: 1, y: 1))
        }
        return .closedHand
    }()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }
    static func attachedFrame(_ rect: CGRect) -> CGRect {
        // Renderer_frameRectForTextRect: x-11, y-3, w+15, h+6,
        // rounded outwards, then SkitchTextGrip adds five points on each side.
        CGRect(x: rect.minX - 11, y: rect.minY - 3,
               width: rect.width + 15, height: rect.height + 6).integral.insetBy(dx: -5, dy: -5)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = CGSize(width: 0, height: -1); shadow.shadowBlurRadius = 3
        if let cg = NSGraphicsContext.current?.cgContext { shadow.cast(in: cg, inFlippedView: true) }
        let inner = bounds.insetBy(dx: 5, dy: 5)
        let border = inner.insetBy(dx: 0.5, dy: 0.5)
        color.withAlphaComponent(1).setStroke()
        let framePath = NSBezierPath(roundedRect: border, xRadius: 5, yRadius: 5)
        framePath.lineWidth = 1; framePath.stroke()
        let pill = NSBezierPath(roundedRect: CGRect(x: border.minX, y: border.minY,
                                                  width: 10, height: border.height), xRadius: 5, yRadius: 5)
        color.withAlphaComponent(1).setFill(); pill.fill()
        NSColor.black.setStroke(); pill.lineWidth = 1; pill.stroke()
        var y = (inner.minY + 9).rounded(.towardZero) - 0.5
        while y < inner.maxY - 8.5 {
            for (offset, ink) in [(CGFloat(0), NSColor.black.withAlphaComponent(0.8)),
                                  (CGFloat(1), NSColor.white.withAlphaComponent(0.5))] {
                let line = NSBezierPath()
                line.move(to: CGPoint(x: inner.minX + 2.5, y: y + offset))
                line.line(to: CGPoint(x: inner.minX + 8.5, y: y + offset))
                ink.setStroke(); line.lineWidth = 1; line.stroke()
            }
            y += 3
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Self.moveCursor) }
    override func mouseDown(with event: NSEvent) {
        if previousCursor == nil { previousCursor = NSCursor.current }
        lastDragLocation = superview?.convert(event.locationInWindow, from: nil)
        Self.moveCursor.set()
    }
    override func mouseDragged(with event: NSEvent) {
        let location = superview?.convert(event.locationInWindow, from: nil)
        var delta = CGSize(width: event.deltaX, height: event.deltaY)
        guard delta.width.isFinite, delta.height.isFinite else { return }
        // Modern event sources can deliver changed pointer locations with zero
        // deltas. Preserve the recovered delta contract and handle those events
        // in the fixed parent coordinate space, never the moving grip's space.
        if delta == .zero, let location, let previous = lastDragLocation {
            delta = CGSize(width: location.x - previous.x, height: location.y - previous.y)
        }
        lastDragLocation = location
        onMove?(delta)
    }
    override func mouseUp(with event: NSEvent) { restoreCursor() }
    func restoreCursor() { previousCursor?.set(); previousCursor = nil; lastDragLocation = nil }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { restoreCursor() }
        super.viewWillMove(toSuperview: newSuperview)
    }
}

/// What the next Wipe press will do (original updateWipeButton, IMP 0x25d45).
enum WipeStage: Equatable {
    case blank, clear, wipe
    var title: String {
        switch self {
        case .blank: return "Blank"
        case .clear: return "Clear"
        case .wipe: return "Wipe"
        }
    }
    var isEnabled: Bool { self != .blank }
}

/// Native AppKit canvas. All model geometry stays in top-left document pixels.
/// Assign as NSScrollView.documentView; frame/intrinsic size follow output size * display zoom.
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
    var arrowHeadPreference = 0
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
            onTextStyleContextChange?()
        }
    }
    var document = SketchDocument() {
        didSet {
            // A replacement supplied by the shell invalidates the preview's base.
            // Internal viewport assignments preserve it until endViewportEdit.
            let replacement = !applyingViewportState && documentMutationDepth == 0 && !isFinishingText
            if replacement { actualNormalOutputSize = nil; resetGesture() }
            if !settingPanBackground && oldValue.backgroundPNG != document.backgroundPNG { panBackground = nil }
            updateCanvasSize(); needsDisplay = true
            onTextStyleContextChange?()
            if replacement, viewportEdit != nil {
                // The incoming document is authoritative; cancel the shell gesture
                // without restoring the old document over its replacement.
                invalidatingViewportDocument = true
                defer { invalidatingViewportDocument = false }
                endViewportEdit(cancelled: true)
            }
        }
    }
    var onChange: (() -> Void)?
    var onTextStyleRequested: (() -> Void)?
    var onTextStyleContextChange: (() -> Void)?
    /// Called after an in-flight viewport edit has been cancelled and cleared.
    var onViewportEditCancelled: (() -> Void)?
    var onHistoryRestored: ((CGSize) -> Void)?
    var onToolChange: ((SketchTool) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    /// Original resource stems: wipe_brushlayer, wipe_snap, wipe_already_blank.
    var onSound: ((String) -> Void)?
    var onHintModifiers: ((NSEvent.ModifierFlags) -> Void)?
    var onHintHover: ((Bool) -> Void)?
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
        var pending = state
        pending.document = documentIncludingPendingText()
        return undoState(pending).document != undoState(before).document
    }
    var canvasSize: NSSize { document.size }
    var outputSize: NSSize { document.outputSize }
    /// Actual presents the currently visible source coordinates, not the retained
    /// photo's hidden extent. Original documentPixelSize rounds to the nearest
    /// source pixel; original-size raster export independently rounds up.
    var fullResolutionOutputSize: CGSize {
        func nearestSize(_ size: CGSize) -> CGSize? {
            guard size.width.isFinite, size.height.isFinite else { return nil }
            let pixels = CGSize(width: max(1, floor(size.width + 0.5)),
                                height: max(1, floor(size.height + 0.5)))
            return SketchDocument.validSize(pixels) ? pixels : nil
        }
        return nearestSize(document.size) ?? nearestSize(outputSize) ?? CGSize(width: 1, height: 1)
    }
    var displayScale: CGSize { CGSize(width: outputSize.width / canvasSize.width * zoom,
                                     height: outputSize.height / canvasSize.height * zoom) }
    private var minimumDisplayScale: CGFloat { min(displayScale.width, displayScale.height) }
    override var undoManager: UndoManager? { editingUndoManager }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: outputSize.width * zoom, height: outputSize.height * zoom) }

    // Internal access also makes the executable tests independent of a visible window.
    var selection: Set<UUID> = [] { didSet { needsDisplay = true; onTextStyleContextChange?() } }
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
    private var viewportEdit: ViewportEdit?
    private var applyingViewportState = false
    private var beginningViewportEdit = false
    private var actualNormalOutputSize: CGSize?
    private var documentMutationDepth = 0
    private var invalidatingViewportDocument = false
    private var dragMode: DragMode = .none
    private var resizingHandle: Int?
    private var resizeBounds: CGRect = .zero
    private var strokePoints: [CGPoint] = []
    private var strokeSamples: [StrokeSample] = []
    private var drawingPencil = false
    private var drawingArrow = false
    private var arrowEnd: CGPoint = .zero
    private var tabletEraser = false
    private var textEditor: SketchTextEditor?
    private var textEditorGrip: SketchTextGrip?
    private var textEditorOffset: CGPoint = .zero
    private struct PendingTextStyle: Equatable {
        var color: SketchColor
        var fontName: String
        var fontSize: CGFloat
        var outlined: Bool
        var shadowed: Bool
        init(_ element: SketchElement) {
            color = element.color
            fontName = element.fontName; fontSize = element.fontSize
            outlined = element.outlined; shadowed = element.shadowed
        }
        func apply(to element: inout SketchElement) {
            element.color = color
            element.fontName = fontName; element.fontSize = fontSize
            element.outlined = outlined; element.shadowed = shadowed
        }
    }
    private var pendingTextStyles: [UUID: PendingTextStyle] = [:]
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
        // Gesture rollback uses the live presentation; history uses this normal
        // output captured at the same time, even if a later transform changes it.
        var normalOutputSize: CGSize?
    }
    private struct ViewportEdit {
        var before: EditorState
        var name: String
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
        EditorState(document: document, selection: selection, cropRect: cropRect,
                    panBackground: panBackground, normalOutputSize: actualNormalOutputSize)
    }
    private func undoState(_ value: EditorState) -> EditorState {
        var result = value
        if let normal = result.normalOutputSize {
            result.document.renderSize = normal == result.document.size ? nil : normal
            result.normalOutputSize = nil
        }
        return result
    }
    private func mutateDocument(_ body: () -> Void) {
        documentMutationDepth += 1
        defer { documentMutationDepth -= 1 }
        body()
    }
    private func updateCanvasSize() {
        let size = intrinsicContentSize
        if frame.size != size { setFrameSize(size) }
        invalidateIntrinsicContentSize()
        if let editor = textEditor, let id = editingTextID,
           let source = document.elements.first(where: { $0.id == id }) {
            let element = elementIncludingPendingText(source)
            editor.applyAnnotationStyle(element, scale: displayScale.height)
            editor.setFrameOrigin(viewRect(element.bounds).origin)
            editor.fitContents()
            textEditorGrip?.frame = SketchTextGrip.attachedFrame(editor.frame)
        }
        needsDisplay = true
    }
    private func recordUndo(_ before: EditorState, name: String) {
        let before = undoState(before), after = undoState(state)
        guard before.document != after.document || before.panBackground != after.panBackground else { return }
        let explicitGroup = !editingUndoManager.isUndoing && !editingUndoManager.isRedoing
        if explicitGroup { editingUndoManager.beginUndoGrouping() }
        editingUndoManager.registerUndo(withTarget: self) { canvas in canvas.restore(before, name: name) }
        editingUndoManager.setActionName(name)
        if explicitGroup { editingUndoManager.endUndoGrouping() }
        onChange?()
    }
    private func restore(_ restored: EditorState, name: String) {
        endViewportEdit(cancelled: true)
        finishTextEditing()
        let inverse = state
        restoreEditorState(restored)
        recordUndo(inverse, name: name)
    }
    private func edit(_ name: String, _ body: () -> Void) {
        endViewportEdit(cancelled: true)
        finishTextEditing()
        let before = state
        mutateDocument {
            if actualNormalOutputSize != nil {
                document.renderSize = undoState(before).document.renderSize
                body()
                actualNormalOutputSize = document.outputSize
                reapplyActualPresentation()
            } else { body() }
        }
        recordUndo(before, name: name)
    }
    func undo() {
        endViewportEdit(cancelled: true); finishTextEditing(); if dragMode != .none { cancelOperation(nil) }
        let previous = outputSize; editingUndoManager.undo(); onHistoryRestored?(previous)
    }
    func redo() {
        endViewportEdit(cancelled: true); finishTextEditing(); if dragMode != .none { cancelOperation(nil) }
        let previous = outputSize; editingUndoManager.redo(); onHistoryRestored?(previous)
    }
    func setZoom(_ value: CGFloat) { zoom = value }

    /// The shell owns the gesture until endViewportEdit. Pending typing is a
    /// separate edit, committed before taking the full canvas/source snapshot.
    @discardableResult
    func beginViewportEdit(name: String) -> Bool {
        guard actualNormalOutputSize == nil, viewportEdit == nil, !beginningViewportEdit, !isFinishingText,
              dragMode == .none, gestureState == nil, preview == nil, !drawingPencil,
              !editingUndoManager.isUndoing, !editingUndoManager.isRedoing,
              SketchDocument.validSize(canvasSize), SketchDocument.validSize(outputSize) else { return false }
        beginningViewportEdit = true
        defer { beginningViewportEdit = false }
        finishTextEditing()
        guard actualNormalOutputSize == nil, viewportEdit == nil, dragMode == .none,
              SketchDocument.validSize(canvasSize), SketchDocument.validSize(outputSize) else { return false }
        viewportEdit = ViewportEdit(before: state, name: name)
        return true
    }

    @discardableResult
    func previewViewportResize(to size: CGSize) -> Bool {
        guard let transaction = viewportEdit, SketchDocument.validSize(size) else { return false }
        var resized = transaction.before
        let pixels = integralSize(size)
        resized.document.renderSize = pixels == resized.document.size ? nil : pixels
        applyViewportState(resized)
        return true
    }

    /// Rectangles are in the source coordinate system captured at begin, even
    /// after earlier previews have moved the raster and annotations.
    @discardableResult
    func previewViewportCrop(to rect: CGRect, outputSize: CGSize) -> Bool {
        guard let transaction = viewportEdit, SketchDocument.validSize(outputSize),
              let cropped = reframedState(from: transaction.before, to: rect,
                                          outputSize: integralSize(outputSize)) else { return false }
        applyViewportState(cropped)
        return true
    }

    func endViewportEdit(cancelled: Bool = false) {
        guard let transaction = viewportEdit else { return }
        viewportEdit = nil
        if cancelled {
            if !invalidatingViewportDocument { applyViewportState(transaction.before) }
            onViewportEditCancelled?()
        }
        else { recordUndo(transaction.before, name: transaction.name) }
    }

    /// Non-transient sizing for auto-fit. Actual's retained normal output is owned
    /// exclusively by begin/endActualPresentation and document history.
    @discardableResult
    func setPresentationOutputSize(_ size: CGSize) -> Bool {
        guard viewportEdit == nil, SketchDocument.validSize(size) else { return false }
        mutateDocument { document.renderSize = size == document.size ? nil : size }
        return true
    }

    @discardableResult
    func beginActualPresentation() -> Bool {
        guard actualNormalOutputSize == nil, viewportEdit == nil, !beginningViewportEdit, !isFinishingText,
              dragMode == .none, gestureState == nil, preview == nil, !drawingPencil,
              !editingUndoManager.isUndoing, !editingUndoManager.isRedoing,
              SketchDocument.validSize(canvasSize), SketchDocument.validSize(outputSize) else { return false }
        actualNormalOutputSize = outputSize
        reapplyActualPresentation()
        return true
    }

    func endActualPresentation() {
        guard let normal = actualNormalOutputSize else { return }
        if dragMode != .none { cancelOperation(nil) }
        actualNormalOutputSize = nil
        _ = setPresentationOutputSize(normal)
    }

    private func reapplyActualPresentation() {
        guard actualNormalOutputSize != nil else { return }
        _ = setPresentationOutputSize(fullResolutionOutputSize)
    }

    private func applyViewportState(_ value: EditorState) {
        applyingViewportState = true; settingPanBackground = true
        document = value.document
        settingPanBackground = false; applyingViewportState = false
        panBackground = value.panBackground
        selection = value.selection; cropRect = value.cropRect
    }
    private func restoreEditorState(_ value: EditorState) {
        let restored = undoState(value)
        if actualNormalOutputSize != nil { actualNormalOutputSize = restored.document.outputSize }
        applyViewportState(restored)
        reapplyActualPresentation()
    }
    @discardableResult
    func resizeImage(to size: CGSize) -> Bool {
        guard SketchDocument.validSize(size) else { return false }
        let pixels = integralSize(size)
        edit("Resize Image") { document.renderSize = pixels == document.size ? nil : pixels }
        return true
    }
    func setSnapToNormalSize() {
        endViewportEdit(cancelled: true)
        guard document.backgroundPNG != nil else { return }
        _ = resizeImage(to: document.size)
    }

    func newBlank(size: NSSize) {
        guard SketchDocument.validSize(size) else { return }
        endActualPresentation()
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
        endActualPresentation()
        edit("Set Background") {
            document.size = size; document.renderSize = nil; document.backgroundPNG = png; panBackground = nil
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
    /// Derived from content, so Undo naturally restores the next Wipe action. Field editing
    /// counts as artwork: the first press commits it and removes the drawing.
    var wipeStage: WipeStage {
        if textEditor != nil || !document.elements.isEmpty { return .wipe }
        return document.backgroundPNG != nil || document.backgroundColor != .white ? .clear : .blank
    }
    func wipe() {
        finishTextEditing()
        switch wipeStage {
        case .wipe:
            // wipeTA (decompiled.c:305279-305293) resets the rect to (0,0,1,1) unless an image remains.
            edit("Clear Annotations") {
                document.elements.removeAll(); selection.removeAll()
                if document.backgroundPNG == nil { resetViewport() }
            }
            onSound?("wipe_brushlayer")
        case .clear:
            edit("Wipe Snap") {
                document.backgroundPNG = nil; document.backgroundColor = .white; resetViewport()
            }
            onSound?("wipe_snap")
        case .blank:
            onSound?("wipe_already_blank")
        }
    }
    private func resetViewport() { cropRect = nil; panBackground = nil; document.renderSize = nil }
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
        endViewportEdit(cancelled: true)
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
    /// A color choice changes only color, preserving mixed stroke/font/effects.
    /// Pending typing and selected text colors stay in the existing text edit.
    func applyColorToSelection(_ color: NSColor) {
        let chosen = SketchColor(color)
        if let editor = textEditor {
            let caret = editor.selectedRange()
            for element in selectedTextElements {
                var style = PendingTextStyle(element); style.color = chosen
                pendingTextStyles[element.id] = style
            }
            mutateDocument {
                for index in document.elements.indices where selection.contains(document.elements[index].id) && document.elements[index].kind != .raster && document.elements[index].kind != .text {
                    document.elements[index].color = chosen
                }
            }
            updateCanvasSize(); editor.setSelectedRange(caret)
            onTextStyleContextChange?(); onChange?()
        } else {
            edit("Change Color") {
                for index in document.elements.indices where selection.contains(document.elements[index].id) && document.elements[index].kind != .raster {
                    document.elements[index].color = chosen
                }
            }
        }
    }
    /// Font/outline controls must not apply the current pen color or shape style.
    /// Pending typing commits first through edit(), retaining its own undo step.
    func applyTextStyleToSelection(includingShadow: Bool = false) {
        edit("Change Text Style") {
            for index in document.elements.indices where selection.contains(document.elements[index].id) &&
                document.elements[index].kind == .text {
                var element = document.elements[index]
                let size = fontSize.isFinite ? min(4096, max(18, fontSize)) : 24
                let typographyChanged = element.fontName != fontName || element.fontSize != size
                element.fontName = fontName
                element.fontSize = size
                element.outlined = outlined
                if includingShadow { element.shadowed = shadowed }
                // Recover natural text sizing while keeping its anchor/transform.
                if typographyChanged { element.rect.size = OriginalTextGeometry.size(for: element) }
                document.elements[index] = element
            }
        }
    }

    func restoreDefaultTextStyle() {
        fontName = "Helvetica-Bold"; outlined = true; shadowed = true
        convertSelectedTextFonts({ NSFont(name: "Helvetica-Bold", size: $0.pointSize) }, outline: true, shadow: true, name: "Default Skitch Style")
    }

    func applyTextEffectsToSelection(outline: Bool? = nil, shadow: Bool? = nil) {
        convertSelectedTextFonts(nil, outline: outline, shadow: shadow)
    }

    var selectedTextElements: [SketchElement] {
        document.elements.filter { $0.kind == .text && selection.contains($0.id) }.map(elementIncludingPendingText)
    }
    /// Convert each original font independently. A mixed effect is nil and keeps
    /// each annotation's value. Validate every result before touching pending work.
    @discardableResult
    func convertSelectedTextFonts(_ convert: ((NSFont) -> NSFont?)?, outline: Bool? = nil,
                                  shadow: Bool? = nil, name: String = "Change Text Style") -> Bool {
        let selected = selectedTextElements
        var styles: [UUID: PendingTextStyle] = [:]
        for element in selected {
            var style = PendingTextStyle(element)
            if let convert {
                let old = NSFont(name: element.fontName, size: element.fontSize) ?? .boldSystemFont(ofSize: element.fontSize)
                guard let font = convert(old), font.pointSize.isFinite, font.pointSize > 0, font.pointSize <= 4096,
                      font.pointSize >= 18 || font.pointSize == element.fontSize else { return false }
                style.fontName = font.fontName; style.fontSize = font.pointSize
            }
            if let outline { style.outlined = outline }
            if let shadow { style.shadowed = shadow }
            if style != PendingTextStyle(element) { styles[element.id] = style }
        }
        guard !styles.isEmpty else { return true }
        if let editor = textEditor {
            let caret = editor.selectedRange()
            pendingTextStyles.merge(styles) { _, new in new }
            updateCanvasSize()
            editor.setSelectedRange(caret)
            onTextStyleContextChange?(); onChange?()
        } else {
            edit(name) {
                for index in document.elements.indices {
                    guard let style = styles[document.elements[index].id] else { continue }
                    let old = document.elements[index]
                    style.apply(to: &document.elements[index])
                    if old.fontName != style.fontName || old.fontSize != style.fontSize {
                        document.elements[index].rect.size = OriginalTextGeometry.size(for: document.elements[index])
                    }
                }
            }
        }
        return true
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
        endViewportEdit(cancelled: true)
        let oldSize = canvasSize
        let matrix = clockwise ? SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: oldSize.height, ty: 0) :
            SketchTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: oldSize.width)
        transformDocument(matrix, size: NSSize(width: oldSize.height, height: oldSize.width), name: "Rotate")
    }
    func flip(horizontal: Bool) {
        endViewportEdit(cancelled: true)
        let matrix = horizontal ? SketchTransform(a: -1, d: 1, tx: canvasSize.width) :
            SketchTransform(a: 1, d: -1, ty: canvasSize.height)
        transformDocument(matrix, size: canvasSize, name: "Flip")
    }
    private func transformDocument(_ matrix: SketchTransform, size: NSSize, name: String) {
        var source = panBackground
        let background: Data?
        if let retained = source {
            let sourceRect = CGRect(origin: retained.offset, size: retained.sourceSize)
            let transformedRect = sourceRect.applying(matrix.cg).standardized
            guard SketchDocument.validSize(transformedRect.size),
                  abs(transformedRect.minX) <= 1_000_000, abs(transformedRect.minY) <= 1_000_000,
                  let image = NSImage(data: retained.sourcePNG),
                  let png = SketchRenderer.bitmap(size: transformedRect.size, draw: {
                    NSGraphicsContext.current?.cgContext.translateBy(x: -transformedRect.minX, y: -transformedRect.minY)
                    NSGraphicsContext.current?.cgContext.concatenate(matrix.cg)
                    SketchRenderer.drawImage(image, in: sourceRect)
                  })?.representation(using: .png, properties: [:]),
                  let rotated = NSImage(data: png),
                  let visible = SketchRenderer.bitmap(size: size, draw: {
                    SketchRenderer.drawImage(rotated, in: transformedRect)
                  })?.representation(using: .png, properties: [:]) else { return }
            source = PanBackground(sourcePNG: png, sourceSize: transformedRect.size, offset: transformedRect.origin)
            background = visible
        } else { background = transformedBackground(matrix, size: size) }
        if document.backgroundPNG != nil && background == nil { return }
        let output = undoState(state).document.renderSize
        edit(name) {
            settingPanBackground = true
            document.backgroundPNG = background; document.size = size
            settingPanBackground = false; panBackground = source
            if let output, name == "Rotate" { document.renderSize = CGSize(width: output.height, height: output.width) }
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
    /// Border cropping changes the visible rectangle, retaining hidden pixels and
    /// every editable object. The original ActionCropResize never deletes graphics.
    @discardableResult
    func reframe(to rect: CGRect, outputSize requestedOutput: CGSize? = nil, name: String = "Crop") -> Bool {
        guard viewportEdit == nil, let reframed = reframedState(from: undoState(state), to: rect, outputSize: requestedOutput) else { return false }
        if rect == document.canvasRect && (requestedOutput == nil || requestedOutput == outputSize) { cropRect = nil; return true }
        edit(name) {
            var committed = reframed
            // edit commits typing first; translate the resulting text as well.
            committed.document.elements = document.elements
            committed.selection = selection
            for index in committed.document.elements.indices {
                committed.document.elements[index].translate(x: -rect.minX, y: -rect.minY)
            }
            applyViewportState(committed)
        }
        return true
    }
    private func reframedState(from before: EditorState, to rect: CGRect,
                               outputSize requestedOutput: CGSize?) -> EditorState? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              abs(rect.origin.x) <= 1_000_000, abs(rect.origin.y) <= 1_000_000,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        let viewport = rect
        guard SketchDocument.validSize(viewport.size) else { return nil }
        let scale = CGSize(width: before.document.outputSize.width / before.document.size.width,
                           height: before.document.outputSize.height / before.document.size.height)
        let output = requestedOutput ?? (viewport == before.document.canvasRect ? before.document.outputSize :
            integralSize(CGSize(width: viewport.width * scale.width, height: viewport.height * scale.height)))
        guard SketchDocument.validSize(output) else { return nil }
        var result = before
        result.cropRect = nil
        if viewport == before.document.canvasRect {
            if output != before.document.outputSize {
                result.document.renderSize = output == viewport.size ? nil : output
            }
            return result
        }
        var source = before.panBackground
        if source == nil, let png = before.document.backgroundPNG {
            source = PanBackground(sourcePNG: png, sourceSize: before.document.size, offset: .zero)
        }
        var visiblePNG: Data?
        if var moved = source {
            moved.offset.x -= viewport.minX; moved.offset.y -= viewport.minY
            guard abs(moved.offset.x) <= 1_000_000, abs(moved.offset.y) <= 1_000_000,
                  let image = NSImage(data: moved.sourcePNG),
                  let png = SketchRenderer.bitmap(size: viewport.size, draw: {
                    SketchRenderer.drawImage(image, in: CGRect(origin: moved.offset, size: moved.sourceSize))
                  })?.representation(using: .png, properties: [:]) else { return nil }
            visiblePNG = png; source = moved
        }
        result.document.size = viewport.size
        result.document.renderSize = output == viewport.size ? nil : output
        result.document.backgroundPNG = visiblePNG; result.panBackground = source
        for index in result.document.elements.indices {
            result.document.elements[index].translate(x: -viewport.minX, y: -viewport.minY)
        }
        return result
    }
    /// Canvas dimensions use border-crop semantics; image resizing is separate.
    func resizeCanvas(to size: NSSize) { _ = reframe(to: CGRect(origin: .zero, size: size), name: "Resize Canvas") }
    @discardableResult
    func cropCanvas(to size: NSSize, anchor: CGPoint, outputSize: CGSize? = nil) -> Bool {
        guard anchor.x.isFinite, anchor.y.isFinite, (0...1).contains(anchor.x), (0...1).contains(anchor.y) else { return false }
        return reframe(to: CGRect(x: (canvasSize.width - size.width) * anchor.x,
                                 y: (canvasSize.height - size.height) * anchor.y,
                                 width: size.width, height: size.height), outputSize: outputSize)
    }
    func cropSelection() {
        endViewportEdit(cancelled: true)
        guard let rect = cropRect ?? selectionBounds else { return }
        crop(to: rect)
    }
    func crop(to rect: CGRect) { _ = reframe(to: rect) }
    /// Original "Crop Snap at Current Edges" permanently trims only the photo.
    /// Hidden annotations stay editable and can reappear when borders expand.
    func trimSnapAtCurrentEdges() {
        endViewportEdit(cancelled: true)
        guard panBackground != nil, document.backgroundPNG != nil else { return }
        edit("Crop Snap at Current Edges") { panBackground = nil }
    }

    func renderedImage(originalSize: Bool = false) -> NSImage {
        let value = documentIncludingPendingText()
        let size = originalSize && value.backgroundPNG != nil ? value.size : value.outputSize
        return ImageExport.image(document: value, size: size) ?? NSImage(size: size)
    }
    /// Export is a pure render of pending text; no model, editor, selection or undo changes.
    func imageData(format: String, originalSize: Bool = false, jpegQuality: Double = 0.7) -> Data? {
        let value = documentIncludingPendingText()
        let size = originalSize && value.backgroundPNG != nil ? value.size : value.outputSize
        return ImageExport.encode(document: value, size: size, format: format, jpegQuality: jpegQuality)
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
        endViewportEdit(cancelled: true)
        finishTextEditing()
        endActualPresentation()
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
        let growth: CGFloat = (color.alpha == 1 ? 1 : 0.2) / minimumDisplayScale
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
        context?.scaleBy(x: displayScale.width, y: displayScale.height)
        if !framePreview { drawCheckerboard(in: document.canvasRect) }
        var visible = documentIncludingPendingText()
        if let id = editingTextID { visible.elements.removeAll { $0.id == id } }
        SketchRenderer.draw(visible, includeBackground: !framePreview, inFlippedView: true)
        if let preview { SketchRenderer.draw(preview, inFlippedView: true) }
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
        let tile: CGFloat = 12 / minimumDisplayScale
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
        if let bounds = selectedBounds(excluding: editingTextID) {
            let path = NSBezierPath(rect: viewRect(bounds).insetBy(dx: -2, dy: -2))
            path.lineWidth = 1.5; path.stroke()
            for point in handlePoints(for: bounds) {
                let rect = CGRect(x: point.x * displayScale.width - 5, y: point.y * displayScale.height - 5, width: 10, height: 10)
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
    /// Original setModifiers exempts Text from Control, not Fill.
    /// Tablet proximity retains its existing independent path.
    var effectiveTool: SketchTool { toolForModifiers(currentModifiers) }
    func toolForModifiers(_ flags: NSEvent.ModifierFlags) -> SketchTool {
        if flags.contains(.command) { return .select }
        if flags.contains(.control) && tool != .text { return .eraser }
        if tabletEraser && tool != .fill { return .eraser }
        return tool
    }
    var isTemporaryHand: Bool { spaceHeld || dragMode == .pan }
    override func flagsChanged(with event: NSEvent) {
        currentModifiers = event.modifierFlags
        if textEditor == nil { onHintModifiers?(event.modifierFlags) }
        if drawingArrow, let style = preview {
            preview = arrowPreview(style: style, modifiers: event.modifierFlags)
            needsDisplay = true
        }
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
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area); pointerTrackingArea = area
    }
    override func mouseMoved(with event: NSEvent) { lastMousePoint = documentPoint(event) }
    override func mouseEntered(with event: NSEvent) { onHintHover?(true) }
    override func mouseExited(with event: NSEvent) { onHintHover?(false) }
    override func resignFirstResponder() -> Bool {
        if dragMode != .none { cancelOperation(nil) }
        spaceHeld = false; currentModifiers = []
        onHintModifiers?([])
        return super.resignFirstResponder()
    }
    private func resetGesture() {
        preview = nil; marquee = nil; gestureState = nil; gestureDocument = nil
        gestureColor = nil; dragMode = .none; strokePoints = []; strokeSamples = []; drawingPencil = false; resizingHandle = nil
        copyOnDrag = false; copiesCreated = false
        drawingArrow = false; arrowEnd = .zero
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
        return CGPoint(x: point.x / displayScale.width, y: point.y / displayScale.height)
    }
    private func documentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / displayScale.width, y: rect.minY / displayScale.height, width: rect.width / displayScale.width, height: rect.height / displayScale.height)
    }
    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * displayScale.width, y: rect.minY * displayScale.height, width: rect.width * displayScale.width, height: rect.height * displayScale.height)
    }
    var selectionBounds: CGRect? {
        selectedBounds(excluding: nil)
    }
    private func selectedBounds(excluding editorID: UUID?) -> CGRect? {
        // The native editor's grip supplies its editing frame. The committed
        // annotation may be moving in a pending transaction, so its old bounds
        // must not leave a second resize box behind. Other selections keep theirs.
        let elements = document.elements.filter { selection.contains($0.id) && $0.id != editorID }
            .map { editorID == nil ? $0 : elementIncludingPendingText($0) }
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
        return handlePoints(for: bounds).firstIndex { hypot(($0.x - point.x) * displayScale.width, ($0.y - point.y) * displayScale.height) <= 8 }
    }
    private func hitElement(_ point: CGPoint) -> SketchElement? {
        let hitOrder = document.elements.filter { $0.kind != .text } + document.elements.filter { $0.kind == .text }
        return hitOrder.reversed().first { element in
            let local = point.applying(element.transform.cg.inverted())
            let tolerance = max(4 / minimumDisplayScale, element.strokeWidth / 2 + 2)
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
        endViewportEdit(cancelled: true)
        documentMutationDepth += 1
        defer { documentMutationDepth -= 1 }
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
            } else if kind == .arrow {
                drawingArrow = true; arrowEnd = point
                element = arrowPreview(style: element, modifiers: event.modifierFlags)
            } else { element.rect = CGRect(origin: point, size: .zero) }
            preview = element; selection.removeAll(); dragMode = .create
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        documentMutationDepth += 1
        defer { documentMutationDepth -= 1 }
        if dragMode != .pan { autoscroll(with: event) }
        var point = documentPoint(event)
        lastMousePoint = point
        currentModifiers = event.modifierFlags
        let dx = point.x - gestureStart.x, dy = point.y - gestureStart.y
        switch dragMode {
        case .create:
            guard var element = preview else { return }
            if drawingPencil {
                if strokeSamples.count < StrokeFitter.maximumSamples { strokeSamples.append(strokeSample(event, at: point)) }
                element = pencilPreview(style: element, modifiers: event.modifierFlags)
            } else if drawingArrow {
                arrowEnd = event.modifierFlags.contains(.shift) ? OriginalArrowGeometry.constrained(point, from: gestureStart) : point
                element = arrowPreview(style: element, modifiers: event.modifierFlags)
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
        documentMutationDepth += 1
        defer { documentMutationDepth -= 1 }
        // ToolBrush and ToolEraser do not add the zero-pressure release event.
        if drawingArrow, let style = preview {
            // Original mouseUp uses the last dragged endpoint, while reading the
            // current Option flag again. Release coordinates do not add a segment.
            preview = arrowPreview(style: style, modifiers: event.modifierFlags)
        } else if dragMode != .none && dragMode != .erase && !drawingPencil { mouseDragged(with: event) }
        switch dragMode {
        case .create:
            if let element = preview,
               !element.pathCommands.isEmpty || element.kind == .brush || element.bounds.width > 0.5 || element.bounds.height > 0.5 {
                document.elements.append(element); selection = [element.id]
                if let before = gestureState { recordUndo(before, name: drawingArrow ? "Draw Arrow" : "Draw \(element.kind.rawValue.capitalized)") }
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
    private func arrowPreview(style: SketchElement, modifiers: NSEvent.ModifierFlags) -> SketchElement {
        var result = style
        result.kind = .path; result.points = []; result.filled = true; result.strokeWidth = 0
        result.pathCommands = OriginalArrowGeometry.commands(from: gestureStart, to: arrowEnd,
            width: effectiveStrokeWidth,
            reversed: OriginalArrowGeometry.reversed(preference: arrowHeadPreference, option: modifiers.contains(.option)))
        result.rect = (try? SVGPathParser.makeCGPath(result.pathCommands).boundingBoxOfPath) ?? .zero
        return result
    }
    override func tabletProximity(with event: NSEvent) {
        tabletEraser = event.isEnteringProximity && event.pointingDeviceType == .eraser
        resetCursorRects(); needsDisplay = true
    }

    // AppKit may deliver Control-click as a secondary-button event; it is still a pen eraser gesture.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard !event.modifierFlags.contains(.control), let element = hitElement(documentPoint(event)), element.kind == .text else { return nil }
        finishTextEditing(); selection = [element.id]; needsDisplay = true
        let menu = NSMenu(title: "Text"); menu.font = .systemFont(ofSize: 20)
        let style = NSMenuItem(title: "Skitch Text Style…", action: #selector(requestTextStyle), keyEquivalent: "")
        style.target = self; menu.addItem(style)
        let defaults = NSMenuItem(title: "Default Skitch Style", action: #selector(defaultTextStyle), keyEquivalent: "")
        defaults.target = self; menu.addItem(defaults)
        return menu
    }
    @objc private func requestTextStyle() { onTextStyleRequested?() }
    @objc private func defaultTextStyle() { restoreDefaultTextStyle() }
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

    private func documentIncludingPendingText() -> SketchDocument {
        var snapshot = document
        snapshot.elements = document.elements.map(elementIncludingPendingText).filter {
            $0.id != editingTextID || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return snapshot
    }
    private func elementIncludingPendingText(_ source: SketchElement) -> SketchElement {
        var element = source
        pendingTextStyles[element.id]?.apply(to: &element)
        if element.id == editingTextID, let editor = textEditor {
            element.text = editor.string
            element.translate(x: textEditorOffset.x, y: textEditorOffset.y)
        }
        if element.kind == .text, element.text != source.text || element.fontName != source.fontName || element.fontSize != source.fontSize {
            element.rect.size = OriginalTextGeometry.size(for: element)
        }
        return element
    }
    private func beginTextEditing(_ id: UUID, before: EditorState? = nil) {
        guard let element = document.elements.first(where: { $0.id == id }) else { return }
        textBeforeEditing = before ?? state
        resetGesture()
        editingTextID = id
        textEditorOffset = .zero; pendingTextStyles.removeAll()
        let editor = SketchTextEditor(frame: viewRect(element.bounds))
        editor.isRichText = false; editor.isEditable = true; editor.isSelectable = true
        editor.allowsUndo = true; editor.isContinuousSpellCheckingEnabled = true
        editor.usesFontPanel = true
        editor.drawsBackground = false
        editor.font = NSFont(name: element.fontName, size: max(18, element.fontSize * displayScale.height)) ??
            NSFont.boldSystemFont(ofSize: max(18, element.fontSize * displayScale.height))
        editor.textColor = element.color.nsColor
        editor.textContainerInset = NSSize(width: 4, height: 2)
        editor.textContainer?.lineFragmentPadding = 2
        editor.textContainer?.containerSize = NSSize(width: CGFloat(Float.greatestFiniteMagnitude), height: CGFloat(Float.greatestFiniteMagnitude))
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = false
        editor.isHorizontallyResizable = true; editor.isVerticallyResizable = true
        editor.maxSize = NSSize(width: CGFloat(Float.greatestFiniteMagnitude), height: CGFloat(Float.greatestFiniteMagnitude))
        editor.string = element.text
        editor.applyAnnotationStyle(element, scale: displayScale.height)
        editor.delegate = self
        editor.setAccessibilityLabel("Annotation text")
        textEditor = editor; addSubview(editor)
        let grip = SketchTextGrip(frame: SketchTextGrip.attachedFrame(editor.frame))
        grip.color = element.color.nsColor
        grip.attach(to: editor)
        grip.setAccessibilityIdentifier("text-grip")
        grip.setAccessibilityLabel("Move annotation text")
        grip.onMove = { [weak self] delta in self?.movePendingText(by: delta) }
        textEditorGrip = grip
        addSubview(grip, positioned: .below, relativeTo: editor)
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        needsDisplay = true
        onTextStyleContextChange?()
    }
    private func movePendingText(by delta: CGSize) {
        guard !isFinishingText, let editor = textEditor, let id = editingTextID,
              let element = document.elements.first(where: { $0.id == id }),
              delta.width.isFinite, delta.height.isFinite,
              delta.width != 0 || delta.height != 0 else { return }
        let offset = CGPoint(x: textEditorOffset.x + delta.width / displayScale.width,
                             y: textEditorOffset.y + delta.height / displayScale.height)
        let translation = CGPoint(x: element.transform.tx + offset.x, y: element.transform.ty + offset.y)
        guard translation.x.isFinite, translation.y.isFinite,
              abs(translation.x) <= 1_000_000, abs(translation.y) <= 1_000_000 else { return }
        textEditorOffset = offset
        // Original grip only changes the attached editor's origin. Preserve its
        // live text-container height, including multiline growth while typing.
        editor.setFrameOrigin(CGPoint(x: element.bounds.minX * displayScale.width + offset.x * displayScale.width,
                                      y: element.bounds.minY * displayScale.height + offset.y * displayScale.height))
        needsDisplay = true
        onChange?()
    }
    func textDidChange(_ notification: Notification) {
        guard !isFinishingText, let editor = textEditor, notification.object as? NSTextView === editor else { return }
        if let id = editingTextID, let source = document.elements.first(where: { $0.id == id }) {
            editor.applyAnnotationStyle(elementIncludingPendingText(source), scale: displayScale.height)
        }
        needsDisplay = true
        onChange?()
    }
    func textDidEndEditing(_ notification: Notification) { finishTextEditing() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
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
        let pending = documentIncludingPendingText()
        textEditorOffset = .zero; pendingTextStyles.removeAll()
        if cancel, let before {
            restoreEditorState(before)
        } else {
            document = pending
            if !document.elements.contains(where: { $0.id == id }) { selection.remove(id) }
        }
        reapplyActualPresentation()
        let returnFocusToCanvas = window?.firstResponder === editor
        editor.delegate = nil
        textEditorGrip?.onMove = nil
        textEditorGrip?.removeFromSuperview(); textEditorGrip = nil
        textEditor = nil; editingTextID = nil; textBeforeEditing = nil
        editor.removeFromSuperview()
        if returnFocusToCanvas { window?.makeFirstResponder(self) }
        isFinishingText = false
        if !cancel, let before { recordUndo(before, name: "Edit Text") }
        if cancel && hadPendingChanges { onChange?() }
        needsDisplay = true
        onTextStyleContextChange?()
    }
    private func startTyping(with event: NSEvent) -> Bool {
        guard viewportEdit == nil, window?.firstResponder === self, textEditor == nil, dragMode == .none, !spaceHeld,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
              }) else { return false }
        var point = lastMousePoint
        if point == nil, let window {
            let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let pointer = CGPoint(x: viewPoint.x / displayScale.width, y: viewPoint.y / displayScale.height)
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
        mutateDocument { document.elements.append(element) }; selection = [element.id]
        beginTextEditing(element.id, before: before)
        // Forward the original event through native text input, including composed
        // characters, rather than assigning its string and bypassing typing undo.
        textEditor?.keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.command) && event.keyCode == 49 {
            spaceHeld = true; onHintModifiers?(event.modifierFlags); window?.invalidateCursorRects(for: self); return
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
        if event.keyCode == 49 { spaceHeld = false; onHintModifiers?(event.modifierFlags); window?.invalidateCursorRects(for: self); return }
        super.keyUp(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if viewportEdit != nil { endViewportEdit(cancelled: true); return }
        // Programmatic cancellation retains explicit abandonment semantics; the
        // native editor/keyboard Escape handlers above commit the text instead.
        if textEditor != nil { finishTextEditing(cancel: true); return }
        if let before = gestureState {
            restoreEditorState(before)
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
