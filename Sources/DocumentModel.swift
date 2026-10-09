import AppKit
import UniformTypeIdentifiers

/// Document coordinates are pixels with a top-left origin, independent of display zoom.
enum SketchTool: String, CaseIterable, Codable {
    case select, arrow, line, rectangle, ellipse, brush, text, fill, eraser, crop
}

/// Recovered _createArrow (0x1e02be) and ToolArrow::mouseDragged (0x1e0100).
/// Use the original Float32 geometry; saved pre-reconstruction arrow elements
/// keep their existing representation instead of being silently reshaped.
enum OriginalArrowGeometry {
    static let preferenceKey = "arrowHead"
    static func reversed(preference: Int, option: Bool) -> Bool { (preference == 1) != option }

    static func constrained(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        let dx = Float(end.x - start.x), dy = Float(end.y - start.y)
        if abs(dx) > 2 * abs(dy) { return CGPoint(x: end.x, y: start.y) }
        if abs(dy) > 2 * abs(dx) { return CGPoint(x: start.x, y: end.y) }
        let side = CGFloat(max(abs(dx), abs(dy)))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    static func commands(from start: CGPoint, to end: CGPoint, width: CGFloat, reversed: Bool) -> [SVGPathCommand] {
        typealias Point = SIMD2<Float>
        func point(_ p: CGPoint) -> Point { Point(Float(p.x), Float(p.y)) }
        func cg(_ p: Point) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }
        func length(_ p: Point) -> Float { sqrt(p.x * p.x + p.y * p.y) }
        func unit(_ p: Point) -> Point { let n = length(p); return n > 0 ? p / n : .zero }
        let tail = point(reversed ? end : start)
        var tip = point(reversed ? start : end)
        guard tail.x.isFinite, tail.y.isFinite, tip.x.isFinite, tip.y.isFinite, width.isFinite else { return [] }
        if abs(tip.x - tail.x) < 0.000001 && abs(tip.y - tail.y) < 0.000001 { tip += Point(repeating: 1) }
        if length(tip - tail) < 5 { tip = tail + unit(tip - tail) * 5 }
        let distance = length(tip - tail), axis = unit(tip - tail)
        let normal = Point(axis.y, -axis.x)
        let size = (Float(width) * 0.5 - 1.5) * 0.7 + 6
        let head = min(0.4 * distance, max(6, size * 2))
        let neckWidth = min(0.25 * head, size * 0.5)
        let tailWidth = min(neckWidth, 1)
        let neck = (tip * (distance - head) + tail * head) / distance
        let shoulderDistance = head * 1.1
        let shoulder = (tip * (distance - shoulderDistance) + tail * shoulderDistance) / distance
        let rightTail = tail + normal * tailWidth, leftTail = tail - normal * tailWidth
        let rightNeck = neck + normal * neckWidth, leftNeck = neck - normal * neckWidth
        let rightShoulder = shoulder + normal * (shoulderDistance * 0.5)
        let leftShoulder = shoulder - normal * (shoulderDistance * 0.5)
        let averageWidth = (neckWidth + tailWidth) * 0.5
        let rightControl1 = rightTail * 0.5 + (neck + normal * averageWidth) * 0.5
        let leftControl2 = leftTail * 0.5 + (neck - normal * averageWidth) * 0.5
        let middle = tail + axis * distance * 0.5
        let rightControl2 = (middle + normal * tailWidth) * 0.5 + rightNeck * 0.5
        let leftControl1 = (middle - normal * tailWidth) * 0.5 + leftNeck * 0.5
        let capLeft = leftTail + unit(leftTail - leftNeck) * tailWidth * 1.5
        let capRight = rightTail + unit(rightTail - rightNeck) * tailWidth * 1.5
        return [.move(to: cg(rightTail)),
                .cubic(control1: cg(rightControl1), control2: cg(rightControl2), to: cg(rightNeck)),
                .line(to: cg(rightShoulder)), .line(to: cg(tip)),
                .line(to: cg(leftShoulder)), .line(to: cg(leftNeck)),
                .cubic(control1: cg(leftControl1), control2: cg(leftControl2), to: cg(leftTail)),
                .cubic(control1: cg(capLeft), control2: cg(capRight), to: cg(rightTail)), .close]
    }
}

struct SketchColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? .black
        red = rgb.redComponent; green = rgb.greenComponent
        blue = rgb.blueComponent; alpha = rgb.alphaComponent
    }
    var nsColor: NSColor { NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha) }
    static let white = SketchColor(.white)
    static let clear = SketchColor(.clear)
}

/// Keeping the affine matrix editable preserves shapes/text during rotation and flipping.
struct SketchTransform: Codable, Equatable {
    var a: CGFloat = 1
    var b: CGFloat = 0
    var c: CGFloat = 0
    var d: CGFloat = 1
    var tx: CGFloat = 0
    var ty: CGFloat = 0
    static let identity = SketchTransform()
    var cg: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
    func applying(_ point: CGPoint) -> CGPoint { point.applying(cg) }
    /// Apply this matrix first, then the world-space matrix.
    func followed(by next: SketchTransform) -> SketchTransform {
        SketchTransform(a: next.a * a + next.c * b, b: next.b * a + next.d * b,
                        c: next.a * c + next.c * d, d: next.b * c + next.d * d,
                        tx: next.a * tx + next.c * ty + next.tx,
                        ty: next.b * tx + next.d * ty + next.ty)
    }
    static func translation(x: CGFloat, y: CGFloat) -> SketchTransform { SketchTransform(tx: x, ty: y) }
}

struct SketchElement: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case arrow, line, rectangle, ellipse, brush, text, raster, path }
    var id = UUID()
    var kind: Kind
    var points: [CGPoint] = []
    var rect: CGRect = .zero
    var color = SketchColor(.systemRed)
    var strokeWidth: CGFloat = 5
    var filled = false
    var shadowed = false
    var text = ""
    var fontSize: CGFloat = 24
    var fontName: String = "Helvetica-Bold"
    var outlined: Bool = true
    var pathCommands: [SVGPathCommand] = []
    var imagePNG: Data?
    var transform = SketchTransform.identity
    var groupID: UUID?

    var localBounds: CGRect {
        switch kind {
        case .path: return (try? SVGPathParser.makeCGPath(pathCommands).boundingBoxOfPath) ?? .zero
        case .arrow, .line, .brush:
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { result, point in
                CGRect(x: min(result.minX, point.x), y: min(result.minY, point.y),
                       width: max(result.maxX, point.x) - min(result.minX, point.x),
                       height: max(result.maxY, point.y) - min(result.minY, point.y))
            }
        default: return rect.standardized
        }
    }
    var bounds: CGRect { localBounds.applying(transform.cg).standardized }
    var paintBounds: CGRect {
        let scale = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
        let padding = (kind == .arrow ? max(14, strokeWidth * 4) : max(2, strokeWidth)) * scale
        return bounds.insetBy(dx: -padding - (shadowed ? 10 : 0), dy: -padding - (shadowed ? 10 : 0))
    }
    mutating func translate(x: CGFloat, y: CGFloat) {
        transform = transform.followed(by: .translation(x: x, y: y))
    }
}

extension SketchElement {
    private enum CodingKeys: String, CodingKey {
        case id, kind, points, rect, color, strokeWidth, filled, shadowed, text, fontSize
        case fontName, outlined, pathCommands, imagePNG, transform, groupID
    }
    /// New version-1 fields have defaults so files saved before legacy path support remain readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? .zero
        color = try c.decodeIfPresent(SketchColor.self, forKey: .color) ?? SketchColor(.systemRed)
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 5
        filled = try c.decodeIfPresent(Bool.self, forKey: .filled) ?? false
        shadowed = try c.decodeIfPresent(Bool.self, forKey: .shadowed) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 24
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica-Bold"
        outlined = try c.decodeIfPresent(Bool.self, forKey: .outlined) ?? true
        pathCommands = try c.decodeIfPresent([SVGPathCommand].self, forKey: .pathCommands) ?? []
        imagePNG = try c.decodeIfPresent(Data.self, forKey: .imagePNG)
        transform = try c.decodeIfPresent(SketchTransform.self, forKey: .transform) ?? .identity
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
    }
}

enum SketchDocumentError: LocalizedError {
    case unsupportedFormat, unsupportedVersion, invalidDocument, invalidImage
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "This is not a supported OpenSnap document."
        case .unsupportedVersion: return "This OpenSnap document uses an unsupported format version."
        case .invalidDocument: return "The document contains invalid dimensions, colors, or drawing data."
        case .invalidImage: return "The image could not be decoded."
        }
    }
}

/// The native .opensnap document: versioned JSON with embedded PNGs.
struct SketchDocument: Codable, Equatable {
    /// Pictures and PDFs by their file type. Anything else, whatever its bytes look like, is not opened or dropped.
    static func isPictureFile(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return type.map { $0.conforms(to: .image) || $0.conforms(to: .pdf) } ?? false
    }
    static let formatIdentifier = "com.shoemoney.opensnap.document"
    static let fileExtension = "opensnap"
    static let maximumDimension: CGFloat = 16384
    static let maximumPixelCount: CGFloat = 32_000_000
    var format = Self.formatIdentifier
    var version = 1
    var size: CGSize = CGSize(width: 800, height: 600)
    var renderSize: CGSize?
    var backgroundColor = SketchColor.white
    var backgroundPNG: Data?
    var elements: [SketchElement] = []

    init(size: CGSize = CGSize(width: 800, height: 600)) { self.size = size }
    var outputSize: CGSize { renderSize ?? size }
    var canvasRect: CGRect { CGRect(origin: .zero, size: size) }
    var backgroundImage: NSImage? {
        get { backgroundPNG.flatMap(NSImage.init(data:)) }
        set { backgroundPNG = newValue.flatMap { SketchRenderer.png(image: $0) } }
    }
    static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1 &&
        size.width <= maximumDimension && size.height <= maximumDimension &&
        size.width.rounded(.up) * size.height.rounded(.up) <= maximumPixelCount
    }
    func validated() throws -> SketchDocument {
        guard format == Self.formatIdentifier else { throw SketchDocumentError.unsupportedFormat }
        guard version == 1 else { throw SketchDocumentError.unsupportedVersion }
        func validPoint(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite && abs(point.x) <= 1_000_000 && abs(point.y) <= 1_000_000
        }
        func validColor(_ color: SketchColor) -> Bool {
            [color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }
        guard Self.validSize(size), renderSize.map(Self.validSize) ?? true,
              validColor(backgroundColor), elements.count <= 100_000,
              Set(elements.map(\.id)).count == elements.count else { throw SketchDocumentError.invalidDocument }
        if let data = backgroundPNG, NSImage(data: data) == nil { throw SketchDocumentError.invalidImage }
        for element in elements {
            let t = element.transform
            guard element.points.count <= 1_000_000, element.points.allSatisfy(validPoint),
                  validPoint(element.rect.origin), element.rect.width.isFinite, element.rect.height.isFinite,
                  abs(element.rect.width) <= 1_000_000, abs(element.rect.height) <= 1_000_000,
                  element.strokeWidth.isFinite, (0...4096).contains(element.strokeWidth),
                  element.strokeWidth > 0 || (element.kind == .path && element.filled),
                  // Imported historical typography keeps its original size. New
                  // tool text and the editor enforce the 18-point minimum.
                  element.fontSize.isFinite, element.fontSize > 0, element.fontSize <= 4096, validColor(element.color),
                  [t.a, t.b, t.c, t.d, t.tx, t.ty].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                  abs(t.a * t.d - t.b * t.c) > 0.000000001 else { throw SketchDocumentError.invalidDocument }
            if [.arrow, .line, .brush].contains(element.kind), element.points.isEmpty {
                throw SketchDocumentError.invalidDocument
            }
            if element.kind == .raster {
                guard let data = element.imagePNG, NSImage(data: data) != nil,
                      element.rect.width > 0, element.rect.height > 0 else { throw SketchDocumentError.invalidImage }
            }
            if element.kind == .path {
                guard !element.pathCommands.isEmpty, element.pathCommands.count <= 1_000_000 else {
                    throw SketchDocumentError.invalidDocument
                }
                for command in element.pathCommands {
                    let points: [CGPoint]
                    switch command {
                    case .move(let p), .line(let p): points = [p]
                    case .cubic(let a, let b, let p): points = [a, b, p]
                    case .quadratic(let a, let p): points = [a, p]
                    case .close: points = []
                    case .arc: throw SketchDocumentError.invalidDocument // Parser retains arcs; renderer does not support them yet.
                    }
                    guard points.allSatisfy(validPoint) else { throw SketchDocumentError.invalidDocument }
                }
                _ = try SVGPathParser.makeCGPath(element.pathCommands)
            }
        }
        return self
    }
    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> SketchDocument {
        try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

/// ShadowLayoutManager outlineSize (0x1a934) and drawGlyphs (0x1b537).
/// Original i386 constants and arithmetic are Float32, including the strict
/// brightness threshold. Alpha applies to the completed text/effect group.
enum OriginalTextEffects {
    static func outlineColor(_ color: SketchColor) -> NSColor {
        let calibrated = color.nsColor.usingColorSpace(.genericRGB) ?? color.nsColor
        let brightness = Float(calibrated.blueComponent) * Float(0.114)
            + Float(calibrated.greenComponent) * Float(0.587)
            + Float(calibrated.redComponent) * Float(0.299)
        return brightness < 0.5 ? .white : .black
    }
    static func outlinePercentage(fontSize: CGFloat) -> CGFloat {
        let size = Float(fontSize)
        var percentage = max(Float(20), Float(-2) * size + Float(60))
        if percentage * size / 100 > 8 { percentage = 800 / size }
        return CGFloat(percentage)
    }
    static func shadow(scale: CGFloat = 1) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -scale)
        return shadow
    }
}

extension NSShadow {
    /// Installs this shadow so a negative `shadowOffset.height` falls down the page (the original's
    /// drawImage passes (dx, -dy)) on every surface. CoreGraphics reads the offset in the context's
    /// base space and `NSShadow.set()` does not compensate. A flipped offscreen export keeps an
    /// unflipped base (y runs against page y), but AppKit hands a view's draw(_:) a base that is
    /// already flipped, so the same offset cast the shadow upward on screen. `inFlippedView`
    /// is true only while drawing inside a flipped NSView's draw(_:); an unflipped view keeps the
    /// ordinary base, where `set()` already falls down and this flag would cast it up.
    func cast(in context: CGContext, inFlippedView: Bool) {
        context.setShadow(offset: CGSize(width: shadowOffset.width,
                                         height: inFlippedView ? -shadowOffset.height : shadowOffset.height),
                          blur: shadowBlurRadius, color: (shadowColor as? NSColor)?.cgColor)
    }
}

/// OriginalTextFieldEditor updateFrameSize (0x1c1e6): natural string width
/// plus four points and two outline margins; glyph height plus eight points.
/// Explicit line breaks determine rows, independently of a historical box width.
enum OriginalTextGeometry {
    static func size(text: String, font: NSFont) -> CGSize {
        let storage = NSTextStorage(string: text, attributes: [.font: font,
            .paragraphStyle: SketchRenderer.textParagraphStyle])
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: CGFloat(Float.greatestFiniteMagnitude),
                                                              height: CGFloat(Float.greatestFiniteMagnitude)))
        container.lineFragmentPadding = 2
        container.widthTracksTextView = false; container.heightTracksTextView = false
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let range = manager.glyphRange(for: container)
        let glyphs = manager.boundingRect(forGlyphRange: range, in: container)
        // TextKit exposes the trailing empty row separately from the glyph range.
        let height = max(glyphs.maxY, manager.extraLineFragmentUsedRect.maxY)
        let margin = CGFloat(Float(font.pointSize) * Float(OriginalTextEffects.outlinePercentage(fontSize: font.pointSize)) / 100)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 4 + 2 * margin
        return CGSize(width: max(1, width), height: max(1, height + 8))
    }
    static func size(for element: SketchElement) -> CGSize {
        size(text: element.text, font: NSFont(name: element.fontName, size: element.fontSize)
             ?? .boldSystemFont(ofSize: element.fontSize))
    }
}

/// Shared by screen drawing and exports. Selection handles and editor chrome are never exported.
enum SketchRenderer {
    static func bitmap(size: CGSize, draw: () -> Void) -> NSBitmapImageRep? {
        guard SketchDocument.validSize(size),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(size.width)), pixelsHigh: Int(ceil(size.height)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    static func bitmap(document: SketchDocument, includeBackground: Bool = true) -> NSBitmapImageRep? {
        bitmap(size: document.size) { draw(document, includeBackground: includeBackground) }
    }
    static func png(image: NSImage) -> Data? {
        guard SketchDocument.validSize(image.size) else { return nil }
        return bitmap(size: image.size) { drawImage(image, in: CGRect(origin: .zero, size: image.size)) }?
            .representation(using: .png, properties: [:])
    }
    static func drawImage(_ image: NSImage, in rect: CGRect) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
    static func draw(_ document: SketchDocument, includeBackground: Bool = true, inFlippedView: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: document.canvasRect).addClip()
        if includeBackground {
            document.backgroundColor.nsColor.setFill()
            document.canvasRect.fill()
            if let image = document.backgroundImage { drawImage(image, in: document.canvasRect) }
        }
        // Original text always floats above the drawing shapes.
        for element in document.elements where element.kind != .text { draw(element, inFlippedView: inFlippedView) }
        for element in document.elements where element.kind == .text { draw(element, inFlippedView: inFlippedView) }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func path(for element: SketchElement) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = element.strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch element.kind {
        case .rectangle: path.appendRect(element.rect.standardized)
        case .ellipse: path.appendOval(in: element.rect.standardized)
        case .arrow, .line, .brush:
            if let first = element.points.first {
                path.move(to: first)
                for point in element.points.dropFirst() { path.line(to: point) }
            }
        default: break
        }
        return path
    }
    static func draw(_ element: SketchElement, inFlippedView: Bool = false) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        cg.concatenate(element.transform.cg)
        if element.shadowed && element.kind != .text {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = NSSize(width: 2, height: -3)
            shadow.cast(in: cg, inFlippedView: inFlippedView)
        }
        element.color.nsColor.set()
        switch element.kind {
        case .path:
            if let path = try? SVGPathParser.makeCGPath(element.pathCommands) {
                cg.setFillColor(element.color.nsColor.cgColor)
                cg.setStrokeColor(element.color.nsColor.cgColor)
                cg.setLineWidth(element.strokeWidth); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.addPath(path); cg.drawPath(using: element.filled ? .fill : .stroke)
            }
        case .raster:
            if let data = element.imagePNG, let image = NSImage(data: data) { drawImage(image, in: element.rect) }
        case .text:
            cg.setLineJoin(.round)
            cg.setAlpha(element.color.alpha)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            cg.setAlpha(1)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: element.fontName, size: element.fontSize) ?? NSFont.boldSystemFont(ofSize: element.fontSize),
                .foregroundColor: element.color.nsColor.withAlphaComponent(1),
                .paragraphStyle: textParagraphStyle
            ]
            // The recovered layout manager paints a positive-width outline,
            // then the colored fill. A combined negative-width stroke obscures
            // glyph interiors at the original thick outline sizes.
            if element.shadowed { OriginalTextEffects.shadow().cast(in: cg, inFlippedView: inFlippedView) }
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            if element.outlined {
                attributes[.strokeColor] = OriginalTextEffects.outlineColor(element.color)
                attributes[.strokeWidth] = OriginalTextEffects.outlinePercentage(fontSize: element.fontSize)
                (element.text as NSString).draw(in: element.rect, withAttributes: attributes)
                attributes.removeValue(forKey: .strokeColor)
                attributes.removeValue(forKey: .strokeWidth)
            }
            (element.text as NSString).draw(in: element.rect, withAttributes: attributes)
            cg.endTransparencyLayer()
            cg.endTransparencyLayer()
        case .brush where element.points.count == 1:
            if let point = element.points.first {
                NSBezierPath(ovalIn: CGRect(x: point.x - element.strokeWidth / 2,
                    y: point.y - element.strokeWidth / 2, width: element.strokeWidth, height: element.strokeWidth)).fill()
            }
        default:
            let path = path(for: element)
            if element.filled && [.rectangle, .ellipse].contains(element.kind) { path.fill() }
            path.stroke()
            if element.kind == .arrow, let end = element.points.last, element.points.count >= 2 {
                let start = element.points[element.points.count - 2]
                let angle = atan2(end.y - start.y, end.x - start.x)
                let length = max(14, element.strokeWidth * 4)
                let halfWidth = max(6, element.strokeWidth * 1.8)
                let head = NSBezierPath()
                head.move(to: end)
                head.line(to: CGPoint(x: end.x - length * cos(angle) + halfWidth * sin(angle),
                                     y: end.y - length * sin(angle) - halfWidth * cos(angle)))
                head.line(to: CGPoint(x: end.x - length * cos(angle) - halfWidth * sin(angle),
                                     y: end.y - length * sin(angle) + halfWidth * cos(angle)))
                head.close(); head.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static var textParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return style
    }
}
