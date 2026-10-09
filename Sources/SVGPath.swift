import Foundation
import CoreGraphics
#if canImport(FoundationXML)
import FoundationXML
#endif


/// Absolute, editable SVG geometry. Curves are retained, never reduced to sample points.
/// Arc parameters remain exact for a future renderer; the original app emitted M/C/z only.
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


enum SVGPathError: Error, LocalizedError {
    case invalidPath(String), unsupported(String), limitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidPath(let reason): return "Invalid SVG path: \(reason)"
        case .unsupported(let reason): return "Unsupported SVG content: \(reason)"
        case .limitExceeded: return "The SVG path exceeds the supported limits."
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
            guard let cmd = command else { throw SVGPathError.invalidPath("Missing command") }
            let absolute = cmd >= 65 && cmd <= 90
            let upper = absolute ? cmd : cmd - 32
            if result.isEmpty && upper != 77 { throw SVGPathError.invalidPath("Must start with M") }
            guard result.count < maximumCommands else { throw SVGPathError.limitExceeded }
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
                    throw SVGPathError.invalidPath("Non-finite coordinate")
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
                guard rx >= 0 && ry >= 0 else { throw SVGPathError.invalidPath("Negative arc radius") }
                let large = try scanner.flag(), sweep = try scanner.flag(), end = try pair()
                result.append(.arc(radiusX: rx, radiusY: ry, rotation: rotation,
                                   largeArc: large, sweep: sweep, to: end))
                point = end; cubicControl = nil; quadraticControl = nil
            default:
                throw SVGPathError.invalidPath("Unknown command \(UnicodeScalar(cmd))")
            }
            guard point.x.isFinite && point.y.isFinite && result.last?.isFinite == true else {
                throw SVGPathError.invalidPath("Non-finite coordinate")
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
            guard command.isFinite else { throw SVGPathError.invalidPath("Non-finite coordinate") }
            switch command {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .cubic(let c1, let c2, let p): path.addCurve(to: p, control1: c1, control2: c2)
            case .quadratic(let control, let p): path.addQuadCurve(to: p, control: control)
            case .close: path.closeSubpath()
            case .arc: throw SVGPathError.unsupported("SVG arc rendering; parameters are retained")
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
                    throw SVGPathError.invalidPath("Unexpected comma")
                }
                index += 1; allowsComma = false; whitespace()
            }
        }
        mutating func flag() throws -> Bool {
            try separator()
            guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else {
                throw SVGPathError.invalidPath("Arc flag must be 0 or 1")
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
            guard digits > 0 else { throw SVGPathError.invalidPath("Expected number at byte \(start)") }
            if index < bytes.count && (bytes[index] == 69 || bytes[index] == 101) {
                index += 1
                if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
                let exponent = index
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                guard index > exponent else { throw SVGPathError.invalidPath("Missing exponent") }
            }
            guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)), value.isFinite else {
                throw SVGPathError.invalidPath("Non-finite number")
            }
            allowsComma = true
            return CGFloat(value)
        }
    }
}

