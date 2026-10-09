import AppKit

enum SVGExport {
    struct TextLine { var content: String; var position: CGPoint }
    static func textBaseline(font: NSFont) -> CGFloat {
        let storage = NSTextStorage(string: "M", attributes: [.font: font, .paragraphStyle: SketchRenderer.textParagraphStyle])
        let layout = NSLayoutManager(), container = NSTextContainer(size: CGSize(width: 100_000, height: 100_000))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return layout.location(forGlyphAt: 0).y
    }
    static func textLines(_ element: SketchElement) -> [TextLine] {
        let font = NSFont(name: element.fontName, size: element.fontSize) ?? .boldSystemFont(ofSize: element.fontSize)
        let storage = NSTextStorage(string: element.text, attributes: [.font: font, .paragraphStyle: SketchRenderer.textParagraphStyle])
        let layout = NSLayoutManager(), container = NSTextContainer(size: CGSize(width: max(1, element.rect.width), height: 100_000_000))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var lines: [TextLine] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            var content = (element.text as NSString).substring(with: range)
            if content.hasSuffix("\n") { content.removeLast() }
            if content.hasSuffix("\r") { content.removeLast() }
            let position = layout.location(forGlyphAt: glyphs.location)
            lines.append(TextLine(content: content, position: CGPoint(x: element.rect.minX + rect.minX + position.x, y: element.rect.minY + rect.minY + position.y)))
        }
        if layout.extraLineFragmentTextContainer != nil || element.text.isEmpty {
            lines.append(TextLine(content: "", position: CGPoint(x: element.rect.minX, y: element.rect.minY + layout.extraLineFragmentRect.minY + textBaseline(font: font))))
        }
        return lines
    }
    /// Ordinary, portable SVG of the visible drawing: vector paint, selectable text and embedded images.
    static func encode(_ document: SketchDocument, outputSize: CGSize? = nil) throws -> Data {
        _ = try document.validated()
        func number(_ value: CGFloat) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value)) }
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;") }
        func color(_ c: SketchColor) -> String { "rgb(\(Int((c.red*255).rounded())),\(Int((c.green*255).rounded())),\(Int((c.blue*255).rounded())))" }
        func shadowStyle(_ element: SketchElement) -> String {
            guard element.shadowed else { return "" }
            return element.kind == .text ? "filter:url(#opensnap-text-shadow);" : "filter:url(#opensnap-shadow);"
        }
        func pathString(_ path: CGPath) -> String {
            var parts: [String] = []
            var current = CGPoint.zero, origin = CGPoint.zero
            func point(_ value: CGPoint) -> String { number(value.x)+" "+number(value.y) }
            func between(_ a: CGPoint, _ b: CGPoint, _ fraction: CGFloat) -> CGPoint {
                CGPoint(x: a.x+(b.x-a.x)*fraction, y: a.y+(b.y-a.y)*fraction)
            }
            path.applyWithBlock { entry in
                let e = entry.pointee
                switch e.type {
                case .moveToPoint:
                    current = e.points[0]; origin = current; parts.append("M"+point(current))
                case .addLineToPoint:
                    let end = e.points[0]
                    parts.append("C"+point(between(current,end,1/3))+" "+point(between(current,end,2/3))+" "+point(end)); current = end
                case .addQuadCurveToPoint:
                    let control = e.points[0], end = e.points[1]
                    parts.append("C"+point(between(current,control,2/3))+" "+point(between(end,control,2/3))+" "+point(end)); current = end
                case .addCurveToPoint:
                    parts.append("C"+point(e.points[0])+" "+point(e.points[1])+" "+point(e.points[2])); current = e.points[2]
                case .closeSubpath:
                    parts.append("z"); current = origin
                @unknown default: break
                }
            }
            return parts.joined(separator:" ")
        }
        func cgPath(_ bezier: NSBezierPath) throws -> CGPath {
            let path = CGMutablePath()
            var points = [NSPoint](repeating:.zero,count:3)
            for index in 0..<bezier.elementCount {
                let kind = points.withUnsafeMutableBufferPointer { bezier.element(at:index,associatedPoints:$0.baseAddress!) }
                switch kind {
                case .moveTo: path.move(to:points[0])
                case .lineTo: path.addLine(to:points[0])
                case .curveTo: path.addCurve(to:points[2],control1:points[0],control2:points[1])
                case .closePath: path.closeSubpath()
                default:
                    if #available(macOS 14, *), kind == .quadraticCurveTo { path.addQuadCurve(to:points[1],control:points[0]) }
                    else { throw SVGPathError.unsupported("Unknown native path element") }
                }
            }
            return path
        }
        func attributes(_ values: [String: String]) -> String {
            values.keys.sorted().map { "\($0)=\"\(escape(values[$0]!))\"" }.joined(separator: " ")
        }
        func groupAttribute(_ id: UUID?) -> [String: String] { id.map { ["data-group": $0.uuidString] } ?? [:] }
        let width = number(ceil(document.size.width)), height = number(ceil(document.size.height))
        let output = outputSize ?? document.size
        guard SketchDocument.validSize(output) else { throw SketchDocumentError.invalidDocument }
        var viewport = ["xmlns": "http://www.w3.org/2000/svg", "xmlns:xlink": "http://www.w3.org/1999/xlink", "version": "1.1",
                        "width": number(ceil(output.width)), "height": number(ceil(output.height))]
        if outputSize != nil {
            viewport["viewBox"] = "0 0 \(number(document.size.width)) \(number(document.size.height))"
            viewport["preserveAspectRatio"] = "none"
        }
        var xml = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<svg " + attributes(viewport) + ">",
            "<rect " + attributes(["x": "0", "y": "0", "width": width, "height": height, "fill": color(document.backgroundColor), "opacity": number(document.backgroundColor.alpha)]) + "/>" ]
        if document.elements.contains(where: { $0.shadowed && $0.kind != .text }) {
            // A canvas-sized user-space region avoids clipping shadows on thin strokes.
            xml.append("<defs><filter id=\"opensnap-shadow\" filterUnits=\"userSpaceOnUse\" x=\"-\(width)\" y=\"-\(height)\" width=\"\(number(ceil(document.size.width)*3))\" height=\"\(number(ceil(document.size.height)*3))\" color-interpolation-filters=\"sRGB\"><feDropShadow dx=\"2\" dy=\"3\" stdDeviation=\"4\" flood-color=\"black\" flood-opacity=\"0.38\"/></filter></defs>")
        }
        if document.elements.contains(where: { $0.kind == .text && $0.shadowed }) {
            xml.append("<defs><filter id=\"opensnap-text-shadow\" filterUnits=\"userSpaceOnUse\" x=\"-\(width)\" y=\"-\(height)\" width=\"\(number(ceil(document.size.width)*3))\" height=\"\(number(ceil(document.size.height)*3))\" color-interpolation-filters=\"sRGB\"><feDropShadow dx=\"0\" dy=\"1\" stdDeviation=\"3\" flood-color=\"black\" flood-opacity=\"0.8\"/></filter></defs>")
        }
        for element in document.elements where element.kind == .text {
            xml.append("<defs><clipPath id=\"opensnap-text-\(element.id.uuidString)\" clipPathUnits=\"userSpaceOnUse\"><rect x=\"\(number(element.rect.minX))\" y=\"\(number(element.rect.minY))\" width=\"\(number(max(0, element.rect.width)))\" height=\"\(number(max(0, element.rect.height)))\"/></clipPath></defs>")
        }
        if let data = document.backgroundPNG {
            let rect = document.canvasRect
            xml.append("<image " + attributes(["x": number(rect.minX), "y": number(rect.minY), "width": number(rect.width), "height": number(rect.height), "xlink:href": "data:image/png;base64," + data.base64EncodedString()]) + "/>")
        }
        for element in document.elements where element.kind != .text {
            let t=element.transform
            let matrix="matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))"
            if element.kind == .raster, let png = element.imagePNG {
                let a = groupAttribute(element.groupID).merging(["x": number(element.rect.minX), "y": number(element.rect.minY), "width": number(element.rect.width), "height": number(element.rect.height),
                    "transform": matrix, "style": shadowStyle(element), "xlink:href": "data:image/png;base64," + png.base64EncodedString()]) { _, new in new }
                xml.append("<image " + attributes(a) + "/>")
                continue
            }
            var paths: [CGPath] = []
            let base = element.kind == .path ? try SVGPathParser.makeCGPath(element.pathCommands) : try cgPath(SketchRenderer.path(for:element))
            let isDot = element.kind == .brush && element.points.count == 1
            if !isDot {
                if element.filled && [.path, .rectangle, .ellipse].contains(element.kind) { paths.append(base) }
                if element.strokeWidth > 0 && !(element.kind == .path && element.filled) { paths.append(base.copy(strokingWithWidth:element.strokeWidth,lineCap:.round,lineJoin:.round,miterLimit:10)) }
            }
            if element.kind == .brush, element.points.count == 1, let point=element.points.first { paths.append(CGPath(ellipseIn:CGRect(x:point.x-element.strokeWidth/2,y:point.y-element.strokeWidth/2,width:element.strokeWidth,height:element.strokeWidth),transform:nil)) }
            if element.kind == .arrow, element.points.count>=2,let end=element.points.last {
                let start=element.points[element.points.count-2], angle=atan2(end.y-start.y,end.x-start.x)
                let length=max(14,element.strokeWidth*4),halfWidth=max(6,element.strokeWidth*1.8)
                let head=CGMutablePath();head.move(to:end)
                head.addLine(to:CGPoint(x:end.x-length*cos(angle)+halfWidth*sin(angle),y:end.y-length*sin(angle)-halfWidth*cos(angle)))
                head.addLine(to:CGPoint(x:end.x-length*cos(angle)-halfWidth*sin(angle),y:end.y-length*sin(angle)+halfWidth*cos(angle)));head.closeSubpath();paths.append(head)
            }
            var transform=t.cg
            for path in paths {
                let transformed=path.copy(using:&transform) ?? path
                xml.append("<path " + attributes(groupAttribute(element.groupID).merging(["d": pathString(transformed), "fill": color(element.color), "opacity": number(element.color.alpha), "style": shadowStyle(element)]) { _, new in new }) + "/>")
            }
        }
        for element in document.elements where element.kind == .text {
            let t=element.transform, font=NSFont(name:element.fontName,size:element.fontSize) ?? .boldSystemFont(ofSize:element.fontSize)
            let traits = font.fontDescriptor.symbolicTraits
            let style = "font-family:'\(font.familyName ?? font.fontName)';font-weight:\(traits.contains(.bold) ? 700:400);font-style:\(traits.contains(.italic) ? "italic":"normal");" + shadowStyle(element)
            var a = groupAttribute(element.groupID).merging(["style": style, "font-family": element.fontName, "font-size": number(element.fontSize), "fill": color(element.color), "opacity": number(element.color.alpha)]) { _, new in new }
            a["clip-path"] = "url(#opensnap-text-\(element.id.uuidString))"
            if !t.cg.isIdentity { a["transform"] = "matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))" }
            if element.outlined {
                let stroke = OriginalTextEffects.outlineColor(element.color) == NSColor.white ? "white" : "black"
                let percentage = OriginalTextEffects.outlinePercentage(fontSize: element.fontSize)
                a.merge(["stroke": stroke, "stroke-width": number(element.fontSize * percentage / 100), "paint-order": "stroke fill", "stroke-linejoin": "round"]) { _, new in new }
            }
            xml.append("<g " + attributes(a) + ">")
            for line in textLines(element) {
                xml.append("<text " + attributes(["x": number(line.position.x), "y": number(line.position.y)]) + ">" + escape(line.content) + "</text>")
            }
            xml.append("</g>")
        }
        xml.append("</svg>")
        return Data(xml.joined(separator:"\n").utf8)
    }
}
