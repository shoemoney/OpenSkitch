import AppKit

enum SVGExport {
    static func encode(_ document: SketchDocument) throws -> Data {
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
        var xml = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<!-- Skitch 1.0 -->", "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" width=\"\(number(document.size.width))\" height=\"\(number(document.size.height))\" skitchVisibleWidth=\"\(number(document.size.width))\" skitchVisibleHeight=\"\(number(document.size.height))\" skitchDocumentType=\"3\">", "<rect x=\"0\" y=\"0\" width=\"\(number(document.size.width))\" height=\"\(number(document.size.height))\" fill=\"\(color(document.backgroundColor))\" opacity=\"\(number(document.backgroundColor.alpha))\"/>"]
        if document.elements.contains(where: { $0.shadowed }) {
            xml.append("<defs><filter id=\"skitch-redux-shadow\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\" color-interpolation-filters=\"sRGB\"><feDropShadow dx=\"2\" dy=\"3\" stdDeviation=\"4\" flood-color=\"black\" flood-opacity=\"0.38\"/></filter></defs>")
        }
        if let data = document.backgroundPNG { xml.append("<image x=\"0\" y=\"0\" width=\"\(number(document.size.width))\" height=\"\(number(document.size.height))\" xlink:href=\"data:image/png;base64,\(data.base64EncodedString())\"/>") }
        var groupIDs: [UUID:Int] = [:]
        func group(_ id:UUID?) -> Int { guard let id else { return 0 }; if let value = groupIDs[id] { return value }; let value=groupIDs.count+1;groupIDs[id]=value;return value }
        for element in document.elements where element.kind != .text {
            let t=element.transform
            let matrix="matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))"
            if element.kind == .raster, let png = element.imagePNG {
                xml.append("<image x=\"\(number(element.rect.minX))\" y=\"\(number(element.rect.minY))\" width=\"\(number(element.rect.width))\" height=\"\(number(element.rect.height))\" transform=\"\(matrix)\" skitchGroup=\"\(group(element.groupID))\" style=\"\(shadowStyle(element))\" xlink:href=\"data:image/png;base64,\(png.base64EncodedString())\"/>")
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
                xml.append("<path d=\"\(pathString(transformed))\" fill=\"\(color(element.color))\" opacity=\"\(number(element.color.alpha))\" skitchHasShadow=\"\(element.shadowed ? 1:0)\" skitchGroup=\"\(group(element.groupID))\" style=\"\(shadowStyle(element))\"/>")
            }
        }
        for element in document.elements where element.kind == .text {
            let t=element.transform, font=NSFont(name:element.fontName,size:element.fontSize) ?? .boldSystemFont(ofSize:element.fontSize)
            let transformAttribute = t.cg.isIdentity ? "" : " transform=\"matrix(\(number(t.a)) \(number(t.b)) \(number(t.c)) \(number(t.d)) \(number(t.tx)) \(number(t.ty)))\""
            let traits = font.fontDescriptor.symbolicTraits
            let style = "font-family:'\(font.familyName ?? font.fontName)';font-weight:\(traits.contains(.bold) ? 700:400);font-style:\(traits.contains(.italic) ? "italic":"normal");" + shadowStyle(element)
            let outline = element.outlined ? " stroke=\"white\" stroke-width=\"\(number(element.fontSize*0.03))\" paint-order=\"stroke fill\"" : ""
            xml.append("<g\(transformAttribute) style=\"\(escape(style))\"\(outline) font-family=\"\(escape(element.fontName))\" font-size=\"\(number(element.fontSize))\" fill=\"\(color(element.color))\" opacity=\"\(number(element.color.alpha))\" skitchTextX=\"\(number(element.rect.minX))\" skitchTextY=\"\(number(element.rect.minY))\" skitchFontSize=\"\(number(element.fontSize))\" skitchHasOutline=\"\(element.outlined ? 1:0)\" skitchHasShadow=\"\(element.shadowed ? 1:0)\" skitchGroup=\"\(group(element.groupID))\">")
            for (index,line) in element.text.components(separatedBy:"\n").enumerated() { xml.append("<text x=\"\(number(element.rect.minX))\" y=\"\(number(element.rect.minY+font.ascender+CGFloat(index)*element.fontSize*1.2))\">\(escape(line))</text>") }
            xml.append("</g>")
        }
        xml.append("</svg>")
        return Data(xml.joined(separator:"\n").utf8)
    }
}
