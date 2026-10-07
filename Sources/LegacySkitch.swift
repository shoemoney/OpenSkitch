import Foundation
import CoreGraphics
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Absolute, editable SVG geometry. Curves are retained, never reduced to sample points.
/// Arc parameters remain exact for a future renderer; original Skitch emits M/C/z only.
enum SVGPathCommand: Codable, Equatable {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case cubic(control1: CGPoint, control2: CGPoint, to: CGPoint)
    case quadratic(control: CGPoint, to: CGPoint)
    case arc(radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat,
             largeArc: Bool, sweep: Bool, to: CGPoint)
    case close

    var isFinite: Bool {
        func finite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }
        switch self {
        case .move(let p), .line(let p): return finite(p)
        case .cubic(let c1, let c2, let p): return finite(c1) && finite(c2) && finite(p)
        case .quadratic(let c, let p): return finite(c) && finite(p)
        case .arc(let rx, let ry, let angle, _, _, let p):
            return rx.isFinite && ry.isFinite && rx >= 0 && ry >= 0 && angle.isFinite && finite(p)
        case .close: return true
        }
    }
}

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

/// Handles SVG M/L/H/V/C/S/Q/T/A/Z, repetitions, relative coordinates and exponents.
/// Smooth commands are normalized to explicit controls; elliptical arcs stay as arcs.
enum SVGPathParser {
    static func parse(_ value: String, maximumCommands: Int = 1_000_000) throws -> [SVGPathCommand] {
        var scanner = Scanner(bytes: Array(value.utf8))
        var result: [SVGPathCommand] = []
        var point = CGPoint.zero, start = CGPoint.zero
        var cubicControl: CGPoint?, quadraticControl: CGPoint?
        var command: UInt8?

        func reflected(_ control: CGPoint?, around origin: CGPoint) -> CGPoint {
            guard let control = control else { return origin }
            return CGPoint(x: 2 * origin.x - control.x, y: 2 * origin.y - control.y)
        }

        while !scanner.atEnd {
            if let next = scanner.takeCommand() { command = next }
            guard let cmd = command else { throw LegacySkitchError.invalidPath("Missing command") }
            let absolute = cmd >= 65 && cmd <= 90
            let upper = absolute ? cmd : cmd - 32
            if result.isEmpty && upper != 77 { throw LegacySkitchError.invalidPath("Must start with M") }
            guard result.count < maximumCommands else { throw LegacySkitchError.limitExceeded }
            if upper == 90 {
                result.append(.close); point = start
                cubicControl = nil; quadraticControl = nil; command = nil
                continue
            }
            let origin = absolute ? CGPoint.zero : point
            func pair() throws -> CGPoint {
                let x = try scanner.number(), y = try scanner.number()
                let value = CGPoint(x: x + origin.x, y: y + origin.y)
                guard value.x.isFinite && value.y.isFinite else {
                    throw LegacySkitchError.invalidPath("Non-finite coordinate")
                }
                return value
            }
            switch upper {
            case 77:
                point = try pair(); start = point; result.append(.move(to: point))
                command = absolute ? 76 : 108
                cubicControl = nil; quadraticControl = nil
            case 76:
                point = try pair(); result.append(.line(to: point))
                cubicControl = nil; quadraticControl = nil
            case 72:
                point.x = try scanner.number() + origin.x; result.append(.line(to: point))
                cubicControl = nil; quadraticControl = nil
            case 86:
                point.y = try scanner.number() + origin.y; result.append(.line(to: point))
                cubicControl = nil; quadraticControl = nil
            case 67:
                let c1 = try pair(), c2 = try pair(), end = try pair()
                result.append(.cubic(control1: c1, control2: c2, to: end))
                point = end; cubicControl = c2; quadraticControl = nil
            case 83:
                let c1 = reflected(cubicControl, around: point)
                let c2 = try pair(), end = try pair()
                result.append(.cubic(control1: c1, control2: c2, to: end))
                point = end; cubicControl = c2; quadraticControl = nil
            case 81:
                let control = try pair(), end = try pair()
                result.append(.quadratic(control: control, to: end))
                point = end; quadraticControl = control; cubicControl = nil
            case 84:
                let control = reflected(quadraticControl, around: point), end = try pair()
                result.append(.quadratic(control: control, to: end))
                point = end; quadraticControl = control; cubicControl = nil
            case 65:
                let rx = try scanner.number(), ry = try scanner.number(), rotation = try scanner.number()
                guard rx >= 0 && ry >= 0 else { throw LegacySkitchError.invalidPath("Negative arc radius") }
                let large = try scanner.flag(), sweep = try scanner.flag(), end = try pair()
                result.append(.arc(radiusX: rx, radiusY: ry, rotation: rotation,
                                   largeArc: large, sweep: sweep, to: end))
                point = end; cubicControl = nil; quadraticControl = nil
            default:
                throw LegacySkitchError.invalidPath("Unknown command \(UnicodeScalar(cmd))")
            }
            guard point.x.isFinite && point.y.isFinite && result.last?.isFinite == true else {
                throw LegacySkitchError.invalidPath("Non-finite coordinate")
            }
        }
        return result
    }

    /// Original M/C/z documents render without approximation. Quadratics use exact
    /// degree elevation. A generic SVG arc is preserved by parse(), but requires a
    /// dedicated ellipse renderer rather than silently flattening it here.
    static func makeCGPath(_ commands: [SVGPathCommand]) throws -> CGPath {
        let path = CGMutablePath()
        for command in commands {
            guard command.isFinite else { throw LegacySkitchError.invalidPath("Non-finite coordinate") }
            switch command {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .cubic(let c1, let c2, let p): path.addCurve(to: p, control1: c1, control2: c2)
            case .quadratic(let control, let p): path.addQuadCurve(to: p, control: control)
            case .close: path.closeSubpath()
            case .arc: throw LegacySkitchError.unsupported("SVG arc rendering; parameters are retained")
            }
        }
        return path
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var allowsComma = false
        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }
        var atEnd: Bool { mutating get { whitespace(); return index == bytes.count } }
        mutating func takeCommand() -> UInt8? {
            whitespace()
            guard index < bytes.count else { return nil }
            let b = bytes[index]
            guard (65...90).contains(b) || (97...122).contains(b) else { return nil }
            index += 1; allowsComma = false; return b
        }
        mutating func separator() throws {
            whitespace()
            if index < bytes.count && bytes[index] == 44 {
                // Commas separate numeric arguments, never follow a command/another comma.
                guard allowsComma else {
                    throw LegacySkitchError.invalidPath("Unexpected comma")
                }
                index += 1; allowsComma = false; whitespace()
            }
        }
        mutating func flag() throws -> Bool {
            try separator()
            guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else {
                throw LegacySkitchError.invalidPath("Arc flag must be 0 or 1")
            }
            let flag = bytes[index] == 49; index += 1; allowsComma = true; return flag
        }
        mutating func number() throws -> CGFloat {
            try separator()
            let start = index
            if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
            var digits = 0
            while index < bytes.count && (48...57).contains(bytes[index]) { index += 1; digits += 1 }
            if index < bytes.count && bytes[index] == 46 {
                index += 1
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1; digits += 1 }
            }
            guard digits > 0 else { throw LegacySkitchError.invalidPath("Expected number at byte \(start)") }
            if index < bytes.count && (bytes[index] == 69 || bytes[index] == 101) {
                index += 1
                if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
                let exponent = index
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                guard index > exponent else { throw LegacySkitchError.invalidPath("Missing exponent") }
            }
            guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)), value.isFinite else {
                throw LegacySkitchError.invalidPath("Non-finite number")
            }
            allowsComma = true
            return CGFloat(value)
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
