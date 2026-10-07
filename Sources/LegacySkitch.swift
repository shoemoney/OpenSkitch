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
}
struct LegacySkitchTextLine: Codable, Equatable {
    var content: String
    var position: CGPoint?
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
}
struct LegacySkitchImage: Codable, Equatable {
    var rect: CGRect
    var pngData: Data
    /// Includes skShadowRadius/Scales/Offset/Color/Opacity for later model adoption.
    var attributes: [String: String]
}
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
}

/// Read-only original-document import. No dependency on Canvas or DocumentModel.
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
        var count = 0
        var groupAttributes: [String: String]?
        var textLines: [LegacySkitchTextLine] = []
        var lineAttributes: [String: String]?
        var lineContent = ""
        var commandCount = 0

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
            if stack.isEmpty && document == nil && comment == " Skitch 1.0 " { signature = true }
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes a: [String: String]) {
            guard error == nil else { return }
            do {
                guard stack.count < 8 else { throw LegacySkitchError.limitExceeded }
                guard a["transform"] == nil else {
                    throw LegacySkitchError.unsupported("SVG transform attribute; geometry would require applying it")
                }
                stack.append(elementName)
                count += 1
                guard count <= LegacySkitch.maximumElements else { throw LegacySkitchError.limitExceeded }
                if stack.count == 1 {
                    guard elementName == "svg", document == nil else { throw LegacySkitchError.invalidDocument("Expected svg root") }
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
                        let previousColor = document?.backgroundColor ?? .white
                        let parsedColor = try color(a, default: previousColor)
                        document?.backgroundColor = parsedColor
                    case "path":
                        guard let d = a["d"] else { throw LegacySkitchError.invalidDocument("Path missing d") }
                        let commands = try SVGPathParser.parse(d, maximumCommands: 1_000_000 - commandCount)
                        commandCount += commands.count
                        let fill = try color(a, default: LegacySkitchColor(red: 0, green: 0, blue: 0, alpha: 1))
                        document?.paths.append(LegacySkitchPath(commands: commands, originalD: d, color: fill,
                            group: try group(a), hasShadow: try flag(a, "skitchHasShadow", default: false), attributes: a))
                    case "g": groupAttributes = a; textLines = []
                    case "image":
                        guard document?.background == nil else { throw LegacySkitchError.unsupported("Multiple background images") }
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
                        document?.background = LegacySkitchImage(rect: rect, pngData: png, attributes: a)
                    default: throw LegacySkitchError.unsupported("Root child \(elementName)")
                    }
                } else if stack[1] == "defs" {
                    // Display-only SVG shadows carry no editable geometry. The
                    // native Skitch shadow flags retain their drawing semantics.
                    guard (stack.count == 3 && elementName == "filter") || (stack.count == 4 && stack[2] == "filter" && elementName == "feDropShadow") else {
                        throw LegacySkitchError.unsupported("SVG definition \(elementName)")
                    }
                } else if stack.count == 3, stack[1] == "g", elementName == "text" {
                    lineAttributes = a; lineContent = ""
                } else { throw LegacySkitchError.unsupported("Nested \(elementName)") }
            } catch { fail(parser, error) }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if stack.count == 3 && stack.last == "text" { lineContent += string }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if stack.count == 3 && stack.last == "text", let value = String(data: CDATABlock, encoding: .utf8) { lineContent += value }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard error == nil else { return }
            do {
                if stack.count == 3, elementName == "text", let a = lineAttributes {
                    var position: CGPoint?
                    if a["x"] != nil && a["y"] != nil { position = CGPoint(x: try number(a, "x"), y: try number(a, "y")) }
                    textLines.append(LegacySkitchTextLine(content: lineContent, position: position))
                    lineAttributes = nil
                } else if stack.count == 2, elementName == "g", let a = groupAttributes {
                    let anchor = CGPoint(x: try number(a, "skitchTextX"), y: try number(a, "skitchTextY"))
                    let fontSize = try number(a, a["skitchFontSize"] == nil ? "font-size" : "skitchFontSize", default: 12)
                    guard fontSize > 0 else { throw LegacySkitchError.invalidDocument("Invalid font size") }
                    document?.texts.append(LegacySkitchText(anchor: anchor,
                        content: textLines.map(\.content).joined(separator: "\n"), lines: textLines,
                        fontName: a["font-family"] ?? "Helvetica Bold", fontSize: fontSize,
                        color: try color(a, default: LegacySkitchColor(red: 0, green: 0, blue: 0, alpha: 1)),
                        group: try group(a), hasOutline: try flag(a, "skitchHasOutline", default: true),
                        hasShadow: try flag(a, "skitchHasShadow", default: true), attributes: a))
                    groupAttributes = nil
                }
                _ = stack.popLast()
            } catch { fail(parser, error) }
        }
    }
}
