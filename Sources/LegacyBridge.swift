import AppKit

enum LegacyBridge {
    static func convert(_ original: LegacySkitchDocument) throws -> SketchDocument {
        func color(_ c: LegacySkitchColor) -> SketchColor { SketchColor(NSColor(deviceRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)) }
        var document = SketchDocument(size: original.size)
        document.backgroundColor = color(original.backgroundColor)
        if let background = original.background {
            guard let image = NSImage(data: background.pngData) else { throw SketchDocumentError.invalidImage }
            guard let bitmap = SketchRenderer.bitmap(size: original.size, draw: { SketchRenderer.drawImage(image, in: background.rect) }), let png = bitmap.representation(using: .png, properties: [:]) else { throw SketchDocumentError.invalidImage }
            document.backgroundPNG = png
        }
        var groups: [Int: UUID] = [:]
        func groupID(_ id: Int) -> UUID? {
            guard id != 0 else { return nil }
            if let uuid = groups[id] { return uuid }
            let uuid = UUID(); groups[id] = uuid; return uuid
        }
        for path in original.paths {
            _ = try SVGPathParser.makeCGPath(path.commands)
            var element = SketchElement(kind: .path)
            element.pathCommands = path.commands; element.color = color(path.color)
            element.filled = true; element.strokeWidth = 0; element.shadowed = path.hasShadow
            element.groupID = groupID(path.group); document.elements.append(element)
        }
        for text in original.texts {
            var element = SketchElement(kind: .text)
            element.text = text.content; element.fontName = text.fontName; element.fontSize = text.fontSize
            element.color = color(text.color); element.outlined = text.hasOutline; element.shadowed = text.hasShadow
            let font = NSFont(name: text.fontName, size: text.fontSize) ?? .boldSystemFont(ofSize: text.fontSize)
            let position = text.lines.first?.position.map { CGPoint(x: $0.x, y: $0.y-font.ascender) } ?? text.anchor
            let textSize = (text.content as NSString).boundingRect(with: NSSize(width: max(1,original.size.width-position.x+100),height: 100_000), options: [.usesLineFragmentOrigin,.usesFontLeading], attributes: [.font:font])
            element.rect = CGRect(origin: position, size: CGSize(width: max(40,ceil(textSize.width)+16),height: max(text.fontSize*1.5,ceil(textSize.height)+8)))
            element.groupID = groupID(text.group); document.elements.append(element)
        }
        return try document.validated()
    }
}
