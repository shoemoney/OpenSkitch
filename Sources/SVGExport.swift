import AppKit

enum SVGExport {
    struct Backdrop { var pngData: Data; var rect: CGRect }
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
    static func encode(_ document: SketchDocument, preserving metadata: LegacyBridge.Metadata = .init(), backdrop: Backdrop? = nil) throws -> Data {
        _ = try document.validated()
        func number(_ value: CGFloat) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value)) }
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;") }
        func color(_ c: SketchColor) -> String { "rgb(\(Int((c.red*255).rounded())),\(Int((c.green*255).rounded())),\(Int((c.blue*255).rounded())))" }
        func shadowStyle(_ element: SketchElement) -> String { element.shadowed ? "filter:url(#skitch-redux-shadow);" : "" }
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
                    else { throw LegacySkitchError.unsupported("Unknown native path element") }
                }
            }
            return path
        }
        func attributes(_ original: [String: String] = [:], _ current: [String: String]) -> String {
            var merged = original
            // Transform/style are regenerated from editable data. Never preserve stale paint.
            for key in ["transform", "style", "filter", "stroke", "stroke-width", "paint-order", "redux:state", "xmlns:redux"] { merged.removeValue(forKey: key) }
            merged.merge(current) { _, new in new }
            return merged.keys.sorted().map { "\($0)=\"\(escape(merged[$0]!))\"" }.joined(separator: " ")
        }
        let width = number(ceil(document.size.width)), height = number(ceil(document.size.height))
        var root = metadata.root
        let defaults = ["xmlns:ev": "http://www.w3.org/2001/xml-events", "baseProfile": "full", "overflow": "hidden",
            "skitchDocumentType": document.backgroundPNG != nil || document.elements.contains(where: { $0.kind == .raster }) ? "2" : "3",
            "skitchVisibleWidth": number(document.size.width), "skitchVisibleHeight": number(document.size.height),
            "skitchCustomColor": "rgb(0,0,0)", "skitchCustomColorAlpha": "1", "skitchBrushColor": "rgb(252,12,89)",
            "skitchBrushColorAlpha": "1", "skitchBrushSize": "5", "skitchTool": "1", "skitchSourceURL": "", "skitchExternalAppDocumentPath": ""]
        for (key, value) in defaults where root[key] == nil { root[key] = value }
        if metadata.originalSize != document.size { root["skitchVisibleWidth"] = number(document.size.width); root["skitchVisibleHeight"] = number(document.size.height) }
        var xml = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<!-- Skitch 1.0 -->",
            "<svg " + attributes(root, ["xmlns": "http://www.w3.org/2000/svg", "xmlns:xlink": "http://www.w3.org/1999/xlink", "version": "1.1", "width": width, "height": height]) + ">",
            "<rect " + attributes(metadata.background, ["x": "0", "y": "0", "width": width, "height": height, "fill": color(document.backgroundColor), "opacity": number(document.backgroundColor.alpha)]) + "/>" ]
        if document.elements.contains(where: { $0.shadowed }) {
            // A canvas-sized user-space region avoids clipping shadows on thin strokes.
            xml.append("<defs><filter id=\"skitch-redux-shadow\" filterUnits=\"userSpaceOnUse\" x=\"-\(width)\" y=\"-\(height)\" width=\"\(number(ceil(document.size.width)*3))\" height=\"\(number(ceil(document.size.height)*3))\" color-interpolation-filters=\"sRGB\"><feDropShadow dx=\"2\" dy=\"3\" stdDeviation=\"4\" flood-color=\"black\" flood-opacity=\"0.38\"/></filter></defs>")
        }
        for element in document.elements where element.kind == .text {
            xml.append("<defs><clipPath id=\"skitch-redux-text-\(element.id.uuidString)\" clipPathUnits=\"userSpaceOnUse\"><rect x=\"\(number(element.rect.minX))\" y=\"\(number(element.rect.minY))\" width=\"\(number(max(0, element.rect.width)))\" height=\"\(number(max(0, element.rect.height)))\"/></clipPath></defs>")
        }
        if let data = backdrop?.pngData ?? document.backgroundPNG {
            let rect = backdrop?.rect ?? document.canvasRect
            xml.append("<image " + attributes(metadata.backgroundImage, ["x": number(rect.minX), "y": number(rect.minY), "width": number(rect.width), "height": number(rect.height), "xlink:href": "data:image/png;base64," + data.base64EncodedString()]) + "/>")
        }
        var groupIDs: [UUID: Int] = [:]
        var used = Set(metadata.groups.values)
        func group(_ id: UUID?) -> Int {
            guard let id else { return 0 }
            if let value = groupIDs[id] { return value }
            if let original = metadata.groups[id.uuidString], original != 0 { groupIDs[id] = original; return original }
            var value = 1
            while used.contains(value) { value += 1 }
            used.insert(value); groupIDs[id] = value; return value
        }
        for element in document.elements where element.kind != .text {
            let t=element.transform
            let matrix="matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))"
            if element.kind == .raster, let png = element.imagePNG {
                var preserved = metadata.elements[element.id.uuidString]?.attributes ?? [:]
                for key in ["skShadowRadius", "skShadowScales", "skShadowOffset", "skShadowColor", "skShadowOpacity"] { preserved.removeValue(forKey: key) }
                var a = ["x": number(element.rect.minX), "y": number(element.rect.minY), "width": number(element.rect.width), "height": number(element.rect.height),
                    "transform": matrix, "skitchGroup": "\(group(element.groupID))", "style": shadowStyle(element), "xlink:href": "data:image/png;base64," + png.base64EncodedString()]
                if element.shadowed { a.merge(["skShadowRadius": "4", "skShadowScales": "1", "skShadowOffset": "2.000 3.000", "skShadowColor": "rgb(0,0,0)", "skShadowOpacity": "0.38"]) { _, new in new } }
                xml.append("<image " + attributes(preserved, a) + "/>")
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
                xml.append("<path " + attributes(metadata.elements[element.id.uuidString]?.attributes ?? [:], ["d": pathString(transformed), "fill": color(element.color), "opacity": number(element.color.alpha), "skitchHasShadow": element.shadowed ? "1" : "0", "skitchGroup": "\(group(element.groupID))", "style": shadowStyle(element)]) + "/>")
            }
        }
        for element in document.elements where element.kind == .text {
            let t=element.transform, font=NSFont(name:element.fontName,size:element.fontSize) ?? .boldSystemFont(ofSize:element.fontSize)
            let traits = font.fontDescriptor.symbolicTraits
            let style = "font-family:'\(font.familyName ?? font.fontName)';font-weight:\(traits.contains(.bold) ? 700:400);font-style:\(traits.contains(.italic) ? "italic":"normal");" + shadowStyle(element)
            let record = metadata.elements[element.id.uuidString]
            // Retain original anchor versus frame distinction and per-line positions
            // until geometry/content/typography changes. Color/group edits are independent.
            let unchanged = record.map { $0.importedElement.rect == element.rect && $0.importedElement.text == element.text && $0.importedElement.fontName == element.fontName && $0.importedElement.fontSize == element.fontSize && $0.importedElement.transform == element.transform } ?? false
            let original = unchanged ? record?.originalText : nil
            let anchor = original?.anchor ?? element.rect.origin
            var a = ["style": style, "font-family": element.fontName, "font-size": number(element.fontSize), "fill": color(element.color), "opacity": number(element.color.alpha),
                "skitchTextX": number(anchor.x), "skitchTextY": number(anchor.y), "skitchFontSize": number(element.fontSize), "skitchHasOutline": element.outlined ? "1" : "0", "skitchHasShadow": element.shadowed ? "1" : "0", "skitchGroup": "\(group(element.groupID))"]
            a["clip-path"] = "url(#skitch-redux-text-\(element.id.uuidString))"
            if !t.cg.isIdentity { a["transform"] = "matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))" }
            if element.outlined { a.merge(["stroke": "white", "stroke-width": number(element.fontSize*0.03), "paint-order": "stroke fill"]) { _, new in new } }
            xml.append("<g " + attributes(record?.attributes ?? [:], a) + ">")
            for (index, line) in textLines(element).enumerated() {
                let preservedLine = original.flatMap { index < $0.lines.count ? $0.lines[index] : nil }
                xml.append("<text " + attributes(preservedLine?.attributes ?? [:], ["x": number(line.position.x), "y": number(line.position.y)]) + ">" + escape(line.content) + "</text>")
            }
            xml.append("</g>")
        }
        xml.append("</svg>")
        return Data(xml.joined(separator:"\n").utf8)
    }
}
