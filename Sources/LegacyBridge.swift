import AppKit

enum LegacyBridge {
    /// Kept by SkitchFile alongside Canvas's document. Unknown original attributes
    /// are attached to stable element IDs, not fragile indices after editing.
    struct Metadata: Codable, Equatable {
        var root: [String: String] = [:]
        var background: [String: String] = [:]
        var backgroundImage: [String: String] = [:]
        var elements: [String: Record] = [:]
        var groups: [String: Int] = [:]
        var originalSize: CGSize?
    }
    struct Record: Codable, Equatable {
        var attributes: [String: String]
        var importedElement: SketchElement
        var originalText: LegacySkitchText?
    }
    static func convert(_ original: LegacySkitchDocument) throws -> SketchDocument {
        try convertWithMetadata(original).document
    }
    static func convertWithMetadata(_ original: LegacySkitchDocument) throws -> (document: SketchDocument, metadata: Metadata) {
        func color(_ c: LegacySkitchColor) -> SketchColor { SketchColor(NSColor(deviceRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)) }
        func transform(_ t: LegacySkitchTransform) -> SketchTransform { SketchTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty) }
        var document = SketchDocument(size: original.size)
        document.backgroundColor = color(original.backgroundColor)
        var metadata = Metadata(root: original.attributes, background: original.backgroundAttributes, originalSize: original.size)
        metadata.root.removeValue(forKey: "redux:state")
        metadata.root.removeValue(forKey: "xmlns:redux")
        var groups: [Int: UUID] = [:]
        func groupID(_ id: Int) -> UUID? {
            guard id != 0 else { return nil }
            if let uuid = groups[id] { return uuid }
            let uuid = UUID(); groups[id] = uuid; metadata.groups[uuid.uuidString] = id; return uuid
        }
        func append(_ element: SketchElement, attributes: [String: String], text: LegacySkitchText? = nil) {
            document.elements.append(element)
            metadata.elements[element.id.uuidString] = Record(attributes: attributes, importedElement: element, originalText: text)
        }
        let images = original.images.isEmpty ? original.background.map { [$0] } ?? [] : original.images
        let order = original.paintOrder.isEmpty ? images.indices.map { LegacySkitchPaint.image($0) } + original.paths.indices.map { .path($0) } : original.paintOrder
        for (position, paint) in order.enumerated() {
            switch paint {
            case .image(let index):
                let image = images[index]
                guard let decoded = NSImage(data: image.pngData), SketchDocument.validSize(decoded.size) else { throw SketchDocumentError.invalidImage }
                let shadowed = (Double(image.attributes["skShadowRadius"] ?? "0") ?? 0) > 0 || image.attributes["skitchHasShadow"] == "1"
                if position == 0 && image.rect == document.canvasRect && image.transform == .identity && !shadowed && image.attributes["skitchGroup"] == nil {
                    document.backgroundPNG = image.pngData
                    metadata.backgroundImage = image.attributes
                } else {
                    var element = SketchElement(kind: .raster)
                    element.imagePNG = image.pngData; element.rect = image.rect; element.transform = transform(image.transform)
                    element.groupID = groupID(Int(image.attributes["skitchGroup"] ?? "0") ?? 0); element.shadowed = shadowed
                    append(element, attributes: image.attributes)
                }
            case .path(let index):
                let path = original.paths[index]
                _ = try SVGPathParser.makeCGPath(path.commands)
                var element = SketchElement(kind: .path)
                element.pathCommands = path.commands; element.color = color(path.color)
                element.filled = true; element.strokeWidth = 0; element.shadowed = path.hasShadow
                element.transform = transform(path.transform)
                element.groupID = groupID(path.group); append(element, attributes: path.attributes)
            }
        }
        for text in original.texts {
            var element = SketchElement(kind: .text)
            element.text = text.content; element.fontName = text.fontName; element.fontSize = text.fontSize
            element.color = color(text.color); element.outlined = text.hasOutline; element.shadowed = text.hasShadow
            let font = NSFont(name: text.fontName, size: text.fontSize) ?? .boldSystemFont(ofSize: text.fontSize)
            let sample = NSTextStorage(string: "M", attributes: [.font: font, .paragraphStyle: SketchRenderer.textParagraphStyle])
            let layout = NSLayoutManager(), container = NSTextContainer(size: CGSize(width: 100_000, height: 100_000))
            container.lineFragmentPadding = 0; sample.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
            let baseline = layout.location(forGlyphAt: 0).y
            let position = text.lines.first?.position.map { CGPoint(x: $0.x, y: $0.y-baseline) } ?? text.anchor
            let textSize = (text.content as NSString).boundingRect(with: NSSize(width: max(1,original.size.width-position.x+100),height: 100_000), options: [.usesLineFragmentOrigin,.usesFontLeading], attributes: [.font:font])
            element.rect = CGRect(origin: position, size: CGSize(width: max(40,ceil(textSize.width)+16),height: max(text.fontSize*1.5,ceil(textSize.height)+8)))
            if let frame = text.frame { element.rect = frame }
            element.transform = transform(text.transform)
            element.groupID = groupID(text.group); append(element, attributes: text.attributes, text: text)
        }
        return (try document.validated(), metadata)
    }
}
