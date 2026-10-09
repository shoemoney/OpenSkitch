import AppKit
import CryptoKit
#if canImport(FoundationXML)
import FoundationXML
#endif

enum LegacySkitchError: Error, LocalizedError {
    case invalidXML(String), invalidDocument(String), invalidPath(String)
    case unsupported(String), limitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidXML(let reason): return "Invalid original Skitch XML: \(reason)"
        case .invalidDocument(let reason): return "Invalid original Skitch document: \(reason)"
        case .invalidPath(let reason): return "Invalid SVG path: \(reason)"
        case .unsupported(let reason): return "Unsupported original Skitch content: \(reason)"
        case .limitExceeded: return "The original Skitch file exceeds the import limits."
        }
    }
}


struct LegacySkitchColor: Codable, Equatable {
    var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    static let white = Self(red: 1, green: 1, blue: 1, alpha: 1)
}
struct LegacySkitchPath: Codable, Equatable {
    var commands: [SVGPathCommand]
    var originalD: String
    var color: LegacySkitchColor
    var group: Int
    var hasShadow: Bool
    var attributes: [String: String]
    var transform = LegacySkitchTransform.identity
}
struct LegacySkitchTextLine: Codable, Equatable {
    var content: String
    var position: CGPoint?
    var attributes: [String: String] = [:]
}
struct LegacySkitchText: Codable, Equatable {
    var anchor: CGPoint
    var content: String
    var lines: [LegacySkitchTextLine]
    var fontName: String
    var fontSize: CGFloat
    var color: LegacySkitchColor
    var group: Int
    var hasOutline: Bool
    var hasShadow: Bool
    var attributes: [String: String]
    var transform = LegacySkitchTransform.identity
    var frame: CGRect?
}
struct LegacySkitchImage: Codable, Equatable {
    var rect: CGRect
    var pngData: Data
    /// Includes skShadowRadius/Scales/Offset/Color/Opacity for later model adoption.
    var attributes: [String: String]
    var transform = LegacySkitchTransform.identity
}
struct LegacySkitchTransform: Codable, Equatable {
    var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1, tx: CGFloat = 0, ty: CGFloat = 0
    static let identity = Self()
    var cg: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
    static func parse(_ value: String?) throws -> Self {
        guard let value else { return .identity }
        let expression = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.hasPrefix("matrix("), expression.hasSuffix(")") else {
            throw LegacySkitchError.unsupported("Only a finite nonsingular SVG matrix is supported")
        }
        let numeric = "[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
        let pattern = "^matrix\\(\\s*" + Array(repeating: numeric, count: 6).joined(separator: "(?:\\s*,\\s*|\\s+)") + "\\s*\\)$"
        guard expression.range(of: pattern, options: .regularExpression) != nil else { throw LegacySkitchError.invalidDocument("Malformed SVG matrix") }
        let parts = expression.dropFirst(7).dropLast().split(whereSeparator: { $0.isWhitespace || $0 == "," })
        let values = parts.compactMap { Double($0) }
        guard values.count == 6, parts.count == 6,
              values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              abs(values[0] * values[3] - values[1] * values[2]) > 1e-9 else {
            throw LegacySkitchError.invalidDocument("Invalid SVG matrix")
        }
        return Self(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }
}
enum LegacySkitchPaint: Codable, Equatable { case path(Int), image(Int) }
struct LegacySkitchDocument: Codable, Equatable {
    /// SVG pixel coordinates; importing need not undo the original logical crop transform.
    var size: CGSize
    var visibleSize: CGSize
    var backgroundColor = LegacySkitchColor.white
    var background: LegacySkitchImage?
    var paths: [LegacySkitchPath] = []
    var texts: [LegacySkitchText] = []
    /// Brush/tool/type/source metadata, including unknown attributes, are retained.
    var attributes: [String: String]
    var backgroundAttributes: [String: String] = [:]
    var images: [LegacySkitchImage] = []
    var paintOrder: [LegacySkitchPaint] = []
}

/// Strict SVG-native import. No dependency on Canvas or DocumentModel.
/// Source: Document::{serialize,deSerialize} at 0x001c27a0/0x001c3770;
/// Text at 0x001c51b4/0x001c56e6; Image at 0x001ce8e0/0x001cec3c.
enum LegacySkitch {
    static let maximumFileBytes = 64 * 1024 * 1024
    static let maximumElements = 100_000

    static func read(_ url: URL) throws -> LegacySkitchDocument {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumFileBytes else {
            throw LegacySkitchError.limitExceeded
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func decode(_ data: Data, requireSignature: Bool = true) throws -> LegacySkitchDocument {
        guard data.count <= maximumFileBytes else { throw LegacySkitchError.limitExceeded }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw LegacySkitchError.invalidXML("Expected UTF-8")
        }
        if requireSignature && !xml.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?xml ") {
            throw LegacySkitchError.invalidDocument("Missing XML declaration before native marker")
        }
        guard !xml.localizedCaseInsensitiveContains("<!DOCTYPE") &&
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw LegacySkitchError.unsupported("DTD/entity declarations")
        }
        let reader = Reader(requireSignature: requireSignature)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let succeeded = parser.parse()
        if let error = reader.error { throw error }
        guard succeeded else { throw LegacySkitchError.invalidXML(parser.parserError?.localizedDescription ?? "Parse failed") }
        guard let document = reader.document else { throw LegacySkitchError.invalidDocument("No svg root") }
        return document
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let requireSignature: Bool
        var error: Error?
        var document: LegacySkitchDocument?
        var stack: [String] = []
        var signature = false
        var topLevelComments = 0
        var count = 0
        var groupAttributes: [String: String]?
        var textLines: [LegacySkitchTextLine] = []
        var lineAttributes: [String: String]?
        var lineContent = ""
        var commandCount = 0
        var clipID: String?
        var clips: [String: CGRect] = [:]
        var knownShadows = Set<String>()
        var activeShadow: String?

        init(requireSignature: Bool) { self.requireSignature = requireSignature }

        func fail(_ parser: XMLParser, _ error: Error) { self.error = error; parser.abortParsing() }

        func number(_ attributes: [String: String], _ key: String, default fallback: CGFloat? = nil) throws -> CGFloat {
            if let text = attributes[key], let value = Double(text), value.isFinite { return CGFloat(value) }
            if attributes[key] == nil, let fallback = fallback { return fallback }
            throw LegacySkitchError.invalidDocument("Missing/invalid \(key)")
        }
        func group(_ attributes: [String: String]) throws -> Int {
            guard let text = attributes["skitchGroup"] else { return 0 }
            guard let value = Int(text) else { throw LegacySkitchError.invalidDocument("Invalid skitchGroup") }
            return value
        }
        func flag(_ attributes: [String: String], _ key: String, default fallback: Bool) throws -> Bool {
            guard attributes[key] != nil else { return fallback }
            return try number(attributes, key) != 0
        }
        func color(_ attributes: [String: String], default fallback: LegacySkitchColor) throws -> LegacySkitchColor {
            guard let fill = attributes["fill"] else { return fallback }
            guard fill.hasPrefix("rgb("), fill.hasSuffix(")") else { throw LegacySkitchError.unsupported("Color \(fill)") }
            let parts = fill.dropFirst(4).dropLast().split(separator: ",", omittingEmptySubsequences: false)
            let rgb = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let alpha = try number(attributes, "opacity", default: 1)
            guard rgb.count == 3, rgb.allSatisfy({ $0.isFinite && (0...255).contains($0) }),
                  (0...1).contains(alpha) else { throw LegacySkitchError.invalidDocument("Invalid RGB/opacity") }
            return LegacySkitchColor(red: CGFloat(rgb[0] / 255), green: CGFloat(rgb[1] / 255),
                                     blue: CGFloat(rgb[2] / 255), alpha: alpha)
        }

        func parser(_ parser: XMLParser, foundComment comment: String) {
            if stack.isEmpty && document == nil {
                if topLevelComments == 0 && comment == " Skitch 1.0 " { signature = true }
                topLevelComments += 1
            }
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes a: [String: String]) {
            guard error == nil else { return }
            do {
                guard stack.count < 8 else { throw LegacySkitchError.limitExceeded }
                guard !a.keys.contains(where: { $0.lowercased().hasPrefix("on") }) else {
                    throw LegacySkitchError.unsupported("SVG event handlers")
                }
                let transform = try LegacySkitchTransform.parse(a["transform"])
                if elementName != "g" && elementName != "text" && a["stroke"] != nil {
                    throw LegacySkitchError.unsupported("SVG stroke paint; native paths must be filled outlines")
                }
                if elementName == "text" && a.keys.contains(where: { ["fill", "opacity", "font-family", "font-size", "style", "stroke"].contains($0) }) {
                    throw LegacySkitchError.unsupported("Per-line text paint overrides")
                }
                if let filter = a["filter"], !["url(#skitch-redux-shadow)", "url(#skitch-redux-text-shadow)"].contains(filter) { throw LegacySkitchError.unsupported("Unknown SVG filter") }
                if a["transform"] != nil && !["path", "g", "image"].contains(elementName) {
                    throw LegacySkitchError.unsupported("Transform on \(elementName)")
                }
                if let clip = a["clip-path"], !(elementName == "g" && clip.range(of: "^url\\(#skitch-redux-text-[A-Fa-f0-9-]+\\)$", options: .regularExpression) != nil) {
                    throw LegacySkitchError.unsupported("Unknown SVG clipping")
                }
                for key in ["mask", "stroke-dasharray", "fill-rule", "fill-opacity"] where a[key] != nil {
                    throw LegacySkitchError.unsupported("SVG \(key); unsupported paint semantics")
                }
                if let style = a["style"] {
                    let allowed = ["font-family", "font-weight", "font-style", "filter"]
                    for part in style.split(separator: ";", omittingEmptySubsequences: true) {
                        let pair = part.split(separator: ":", maxSplits: 1)
                        guard pair.count == 2 else { throw LegacySkitchError.invalidDocument("Invalid SVG style") }
                        let key = pair[0].trimmingCharacters(in: .whitespaces)
                        let value = pair[1].trimmingCharacters(in: .whitespaces)
                        // Root background style is a recovered legacy exception.
                        guard allowed.contains(key) || (elementName == "svg" && key == "background-color") else {
                            throw LegacySkitchError.unsupported("SVG style \(key)")
                        }
                        if key == "filter" && !["url(#skitch-redux-shadow)", "url(#skitch-redux-text-shadow)"].contains(value) {
                            throw LegacySkitchError.unsupported("Unknown SVG filter")
                        }
                    }
                }
                stack.append(elementName)
                count += 1
                guard count <= LegacySkitch.maximumElements else { throw LegacySkitchError.limitExceeded }
                if stack.count == 1 {
                    guard elementName == "svg", document == nil else { throw LegacySkitchError.invalidDocument("Expected svg root") }
                    guard a["xmlns"] == nil || a["xmlns"] == "http://www.w3.org/2000/svg" else { throw LegacySkitchError.invalidDocument("Invalid SVG namespace") }
                    guard signature || !requireSignature else { throw LegacySkitchError.invalidDocument("Missing Skitch 1.0 marker") }
                    let w = try number(a, "width"), h = try number(a, "height")
                    let vw = try number(a, "skitchVisibleWidth", default: 1), vh = try number(a, "skitchVisibleHeight", default: 1)
                    guard w > 0, h > 0, vw > 0, vh > 0 else { throw LegacySkitchError.invalidDocument("Dimensions must be positive") }
                    document = LegacySkitchDocument(size: CGSize(width: w, height: h),
                        visibleSize: CGSize(width: vw, height: vh), attributes: a)
                    if let style = a["style"], let begin = style.range(of: "rgb("),
                       let end = style[begin.lowerBound...].firstIndex(of: ")") {
                        document?.backgroundColor = try color(["fill": String(style[begin.lowerBound...end])], default: .white)
                    }
                } else if stack.count == 2 {
                    switch elementName {
                    case "defs": break
                    case "rect":
                        guard document?.backgroundAttributes.isEmpty == true else { throw LegacySkitchError.unsupported("Multiple background rectangles") }
                        let x = try number(a, "x", default: 0), y = try number(a, "y", default: 0)
                        let w = try number(a, "width", default: document!.size.width), h = try number(a, "height", default: document!.size.height)
                        guard x == 0, y == 0, w == document!.size.width, h == document!.size.height else { throw LegacySkitchError.unsupported("Background rectangle geometry") }
                        let previousColor = document?.backgroundColor ?? .white
                        let parsedColor = try color(a, default: previousColor)
                        document?.backgroundColor = parsedColor
                        document?.backgroundAttributes = a
                    case "path":
                        guard let d = a["d"] else { throw LegacySkitchError.invalidDocument("Path missing d") }
                        let commands = try SVGPathParser.parse(d, maximumCommands: 1_000_000 - commandCount)
                        guard !commands.isEmpty else { throw LegacySkitchError.invalidPath("Empty path") }
                        commandCount += commands.count
                        let fill = try color(a, default: LegacySkitchColor(red: 0, green: 0, blue: 0, alpha: 1))
                        let index = document!.paths.count
                        document?.paintOrder.append(.path(index))
                        document?.paths.append(LegacySkitchPath(commands: commands, originalD: d, color: fill,
                            group: try group(a), hasShadow: try flag(a, "skitchHasShadow", default: false), attributes: a, transform: transform))
                    case "g": groupAttributes = a; textLines = []
                    case "image":
                        _ = try group(a)
                        for key in ["skShadowRadius", "skShadowOpacity", "skShadowScales"] where a[key] != nil { _ = try number(a, key) }
                        let prefix = "data:image/png;base64,"
                        guard let href = a["xlink:href"], href.hasPrefix(prefix) else {
                            throw LegacySkitchError.invalidDocument("Expected embedded base64 PNG")
                        }
                        let encoded = href.dropFirst(prefix.count).filter { !$0.isWhitespace }
                        guard let png = Data(base64Encoded: String(encoded)),
                              png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                            throw LegacySkitchError.invalidDocument("Expected embedded base64 PNG")
                        }
                        let w = try number(a, "width"), h = try number(a, "height")
                        guard w > 0, h > 0 else { throw LegacySkitchError.invalidDocument("Invalid image dimensions") }
                        let rect = CGRect(x: try number(a, "x", default: 0), y: try number(a, "y", default: 0), width: w, height: h)
                        guard try number(a, "opacity", default: 1) == 1 else { throw LegacySkitchError.unsupported("Image opacity; use PNG alpha") }
                        let image = LegacySkitchImage(rect: rect, pngData: png, attributes: a, transform: transform)
                        let index = document!.images.count
                        document?.paintOrder.append(.image(index))
                        document?.images.append(image)
                        if document?.background == nil { document?.background = image }
                    default: throw LegacySkitchError.unsupported("Root child \(elementName)")
                    }
                } else if stack[1] == "defs" {
                    // Display-only SVG shadows carry no editable geometry. The
                    // native Skitch shadow flags retain their drawing semantics.
                    guard (stack.count == 3 && ["filter", "clipPath"].contains(elementName)) || (stack.count == 4 && ((stack[2] == "filter" && elementName == "feDropShadow") || (stack[2] == "clipPath" && elementName == "rect"))) else {
                        throw LegacySkitchError.unsupported("SVG definition \(elementName)")
                    }
                    if elementName == "filter" {
                        guard let id = a["id"], ["skitch-redux-shadow", "skitch-redux-text-shadow"].contains(id), knownShadows.insert(id).inserted else { throw LegacySkitchError.unsupported("Unknown/duplicate SVG filter") }
                        activeShadow = id
                    } else if elementName == "feDropShadow" {
                        let text = activeShadow == "skitch-redux-text-shadow"
                        guard try number(a, "dx") == (text ? 0 : 2), try number(a, "dy") == (text ? 1 : 3), try number(a, "stdDeviation") == (text ? 3 : 4),
                              try number(a, "flood-opacity") == (text ? 0.8 : 0.38), a["flood-color"] == "black" else {
                            throw LegacySkitchError.unsupported("SVG shadow metrics")
                        }
                    } else if elementName == "clipPath" {
                        guard let id = a["id"], id.hasPrefix("skitch-redux-text-"), clips[id] == nil, a["clipPathUnits"] == "userSpaceOnUse" else {
                            throw LegacySkitchError.unsupported("Unknown/duplicate SVG text clip")
                        }
                        clipID = id
                    } else if elementName == "rect", let id = clipID {
                        let w = try number(a, "width"), h = try number(a, "height")
                        guard w >= 0, h >= 0, clips[id] == nil else { throw LegacySkitchError.invalidDocument("Invalid SVG text clip") }
                        clips[id] = CGRect(x: try number(a, "x"), y: try number(a, "y"), width: w, height: h)
                    }
                } else if stack.count == 3, stack[1] == "g", elementName == "text" {
                    lineAttributes = a; lineContent = ""
                } else { throw LegacySkitchError.unsupported("Nested \(elementName)") }
            } catch { fail(parser, error) }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if stack.count == 3 && stack.last == "text" { lineContent += string }
            else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail(parser, LegacySkitchError.invalidDocument("Unexpected XML text")) }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if stack.count == 3 && stack.last == "text", let value = String(data: CDATABlock, encoding: .utf8) { lineContent += value }
            else if !CDATABlock.isEmpty { fail(parser, LegacySkitchError.invalidDocument("Unexpected CDATA")) }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard error == nil else { return }
            do {
                if stack.count == 3, elementName == "text", let a = lineAttributes {
                    var position: CGPoint?
                    if a["x"] != nil && a["y"] != nil { position = CGPoint(x: try number(a, "x"), y: try number(a, "y")) }
                    guard (a["x"] == nil) == (a["y"] == nil), a["transform"] == nil else { throw LegacySkitchError.unsupported("Text line position/transform") }
                    textLines.append(LegacySkitchTextLine(content: lineContent, position: position, attributes: a))
                    lineAttributes = nil
                } else if stack.count == 2, elementName == "g", let a = groupAttributes {
                    let anchor = CGPoint(x: try number(a, "skitchTextX"), y: try number(a, "skitchTextY"))
                    let fontSize = try number(a, a["skitchFontSize"] == nil ? "font-size" : "skitchFontSize", default: 12)
                    guard fontSize > 0 else { throw LegacySkitchError.invalidDocument("Invalid font size") }
                    var frame: CGRect?
                    if let clip = a["clip-path"] {
                        let id = String(clip.dropFirst(5).dropLast())
                        guard let rect = clips[id] else { throw LegacySkitchError.invalidDocument("Missing text clip definition") }
                        frame = rect
                    }
                    document?.texts.append(LegacySkitchText(anchor: anchor,
                        content: textLines.map(\.content).joined(separator: "\n"), lines: textLines,
                        fontName: a["font-family"] ?? "Helvetica Bold", fontSize: fontSize,
                        color: try color(a, default: LegacySkitchColor(red: 0, green: 0, blue: 0, alpha: 1)),
                        group: try group(a), hasOutline: try flag(a, "skitchHasOutline", default: true),
                        hasShadow: try flag(a, "skitchHasShadow", default: true), attributes: a,
                        transform: try LegacySkitchTransform.parse(a["transform"]), frame: frame))
                    groupAttributes = nil
                }
                if elementName == "clipPath" { clipID = nil }
                _ = stack.popLast()
            } catch { fail(parser, error) }
        }
    }
}

// MARK: - Converting a legacy document (reachable only from Migration)

enum LegacyBridge {
    /// Everything the original SVG carried besides the drawing itself.
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


/// The editing content of one legacy document, ready to be written as .opensnap.
struct LegacyDocumentContent {
    var document: SketchDocument
    var canvasData: Data
    var drawingDefaults: DrawingDefaults
    /// Set when the stored editing state could not be trusted and the visible drawing was converted instead.
    var note: String?
}

/// The one door into the legacy formats. Only the one-time data migration calls this: Open, drag and
/// drop, Recent and History never read a legacy document.
enum LegacyDocumentReader {
    static let legacyFormatIdentifier = "com.skitch-redux.editable-document"
    static let supplementalNamespace = "urn:skitch-redux:editable-document:1"

    static func read(_ data: Data) throws -> LegacyDocumentContent {
        guard data.count <= LegacySkitch.maximumFileBytes else { throw LegacySkitchError.limitExceeded }
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 {
            let canvas = try canvasBytes(data)
            return LegacyDocumentContent(document: try CanvasView.validatedDocumentData(canvas), canvasData: canvas, drawingDefaults: .init())
        }
        let original = try LegacySkitch.decode(data)
        guard let encoded = original.attributes["redux:state"] else {
            guard original.attributes["xmlns:redux"] == nil else { throw LegacySkitchError.invalidDocument("Missing editing state") }
            return try convertVisible(original, note: nil)
        }
        guard original.attributes["xmlns:redux"] == supplementalNamespace, let bytes = Data(base64Encoded: encoded),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes),
              envelope.format == supplementalNamespace, envelope.version == 1 else {
            throw LegacySkitchError.invalidDocument("Unreadable editing state")
        }
        guard (try? fingerprint(data)) == envelope.svgFingerprint else {
            return try convertVisible(original, note: "the drawing was edited outside the app after it was saved; converted from the visible drawing")
        }
        var document = envelope.document
        guard document.format == legacyFormatIdentifier else { throw SketchDocumentError.unsupportedFormat }
        document.format = SketchDocument.formatIdentifier
        document = try document.validated()
        let canvas: Data
        if let raw = envelope.rawCanvasData {
            canvas = try canvasBytes(raw)
            guard try CanvasView.validatedDocumentData(canvas) == document else {
                throw LegacySkitchError.invalidDocument("Canvas snapshot disagrees with the editing document")
            }
        } else { canvas = try document.encoded() }
        return LegacyDocumentContent(document: document, canvasData: canvas, drawingDefaults: defaults(envelope.metadata.root))
    }

    private static func convertVisible(_ original: LegacySkitchDocument, note: String?) throws -> LegacyDocumentContent {
        let converted = try LegacyBridge.convertWithMetadata(original)
        return LegacyDocumentContent(document: converted.document, canvasData: try converted.document.encoded(),
                                     drawingDefaults: defaults(converted.metadata.root), note: note)
    }

    /// Canvas JSON with the retired format identifier replaced byte for byte, so every number and pixel stays exact.
    private static func canvasBytes(_ data: Data) throws -> Data {
        let old = Data("\"format\":\"\(legacyFormatIdentifier)\"".utf8)
        let new = Data("\"format\":\"\(SketchDocument.formatIdentifier)\"".utf8)
        guard let range = data.range(of: old) else { throw SketchDocumentError.unsupportedFormat }
        var result = data; result.replaceSubrange(range, with: new)
        _ = try CanvasView.validatedDocumentData(result)
        return result
    }

    private static func defaults(_ root: [String: String]) -> DrawingDefaults {
        let names = ["skitchBrushColor": "brushColor", "skitchBrushColorAlpha": "brushColorAlpha", "skitchBrushSize": "brushSize",
                     "skitchCustomColor": "customColor", "skitchCustomColorAlpha": "customColorAlpha"]
        var values: [String: String] = [:]
        for (old, new) in names { if let value = root[old] { values[new] = value } }
        return DrawingDefaults(values: values)
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var document: SketchDocument
        var metadata: LegacyBridge.Metadata
        var rawCanvasData: Data?
        var svgFingerprint: String
    }

    /// Attribute order, indentation, CDATA and XML entity spelling do not matter; every painted node does.
    private static func fingerprint(_ data: Data) throws -> String {
        let reader = FingerprintReader(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), let root = reader.root else { throw LegacySkitchError.invalidXML("Cannot fingerprint SVG") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(root)).map { String(format: "%02x", $0) }.joined()
    }
    private final class FingerprintNode: Encodable {
        var name: String
        var attributes: [String: String]
        var children: [FingerprintNode] = []
        var text = ""
        init(_ name: String, _ attributes: [String: String]) {
            self.name = name; self.attributes = attributes
            if name == "svg" { self.attributes.removeValue(forKey: "redux:state"); self.attributes.removeValue(forKey: "xmlns:redux") }
        }
    }
    private final class FingerprintReader: NSObject, XMLParserDelegate {
        var root: FingerprintNode?
        var stack: [FingerprintNode] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            let node = FingerprintNode(name, attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if stack.last?.name == "text" { stack.last?.text += string } }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { if stack.last?.name == "text" { stack.last?.text += String(decoding: data, as: UTF8.self) } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    }
}
