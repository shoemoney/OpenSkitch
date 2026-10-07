// Executable regression tests; no app windows, capture, network, or credentials.
// From the repository root, compile all Sources/*.swift except App.swift with:
// xcrun swiftc -D SVG_EXPORT_TESTS -swift-version 5 -target arm64-apple-macosx13.0 \
//   Sources/{LegacySkitch,LegacyBridge,DocumentModel,Canvas,SVGExport,Capture,Publishing}.swift \
//   tests/SVGExportTests.swift -o /tmp/skitch-svg-tests
// /tmp/skitch-svg-tests [--fixture /absolute/path/firstlaunch.skitch]
// Repeat compilation with x86_64-apple-macosx13.0 to check the other architecture.
// Known exporter regressions deliberately fail; they are not treated as expected passes.

#if SVG_EXPORT_TESTS
import AppKit
import Foundation
import CoreGraphics
import WebKit
import Darwin
#if canImport(FoundationXML)
import FoundationXML
#endif

fileprivate final class SVGTestNode {
    let name: String
    let attributes: [String: String]
    var children: [SVGTestNode] = []
    var text = ""
    init(_ name: String, _ attributes: [String: String]) {
        self.name = name; self.attributes = attributes
    }
    func named(_ name: String) -> [SVGTestNode] { children.filter { $0.name == name } }
}

/// Independent XML tree reader: never uses LegacySkitch to validate generic SVG.
fileprivate final class SVGTestXML: NSObject, XMLParserDelegate {
    var root: SVGTestNode?
    var stack: [SVGTestNode] = []
    var comments: [String] = []
    static func read(_ data: Data) throws -> SVGTestXML {
        let tree = SVGTestXML(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = tree
        guard parser.parse(), tree.root?.name == "svg", tree.stack.isEmpty else {
            throw SVGExportTests.Failure("Export is not well-formed SVG XML: \(parser.parserError?.localizedDescription ?? "missing root")")
        }
        return tree
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        let node = SVGTestNode(name, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { stack.last?.text += String(decoding: data, as: UTF8.self) }
    func parser(_ parser: XMLParser, foundComment comment: String) { comments.append(comment) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
}

@main
fileprivate enum SVGExportTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message) }
    }
    static func approximately(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.000002) -> Bool {
        abs(actual - expected) <= tolerance
    }
    static func number(_ node: SVGTestNode, _ key: String) throws -> CGFloat {
        guard let text = node.attributes[key], let value = Double(text), value.isFinite else {
            throw Failure("Missing/non-finite \(node.name).\(key)")
        }
        return CGFloat(value)
    }
    static func fillAlpha(_ node: SVGTestNode) throws -> CGFloat {
        // Both forms are legal SVG. If both occur, their opacities multiply.
        let opacity = try node.attributes["opacity"] == nil ? 1 : number(node, "opacity")
        let fillOpacity = try node.attributes["fill-opacity"] == nil ? 1 : number(node, "fill-opacity")
        return opacity * fillOpacity
    }
    static func exported(_ elements: [SketchElement] = [], background: SketchColor = .white,
                         png: Data? = nil) throws -> (Data, SVGTestNode) {
        var document = SketchDocument(size: CGSize(width: 240, height: 160))
        document.backgroundColor = background; document.backgroundPNG = png; document.elements = elements
        let bytes = try SVGExport.encode(document)
        return (bytes, try SVGTestXML.read(bytes).root!)
    }
    static func nativePath(group: UUID? = nil) -> SketchElement {
        var path = SketchElement(kind: .path)
        path.pathCommands = [.move(to: CGPoint(x: 10, y: 20)),
            .cubic(control1: CGPoint(x: 12, y: 4), control2: CGPoint(x: 44, y: 6), to: CGPoint(x: 50, y: 20)),
            .line(to: CGPoint(x: 10, y: 20)), .close]
        path.filled = true; path.strokeWidth = 0; path.groupID = group
        path.color = SketchColor(NSColor(deviceRed: 1, green: 0.25, blue: 0, alpha: 1))
        return path
    }
    static func text(_ content: String = "Editable\ntext", group: UUID? = nil) -> SketchElement {
        var element = SketchElement(kind: .text)
        element.text = content; element.rect = CGRect(x: 25, y: 30, width: 180, height: 80)
        element.fontName = "Helvetica-Bold"; element.fontSize = 24
        element.groupID = group; element.outlined = false; element.shadowed = false
        element.color = SketchColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        return element
    }
    static func commands(_ path: SVGTestNode) throws -> [SVGPathCommand] {
        guard let d = path.attributes["d"] else { throw Failure("Path lacks d") }
        return try SVGPathParser.parse(d)
    }
    static func paintPaths(_ root: SVGTestNode) throws -> [CGPath] {
        try root.named("path").map { try SVGPathParser.makeCGPath(commands($0)) }
    }
    static func point(_ actual: CGPoint, equals expected: CGPoint) -> Bool {
        approximately(actual.x, expected.x) && approximately(actual.y, expected.y)
    }
    static func compareCommands(_ actual: [SVGPathCommand], _ expected: [SVGPathCommand]) throws {
        // Compare exact polynomial controls, allowing the original M/C/z grammar.
        // Degree elevation is lossless; flattening or merely matching bounds is not.
        let actual = cubicCommands(actual), expected = cubicCommands(expected)
        try expect(actual.count == expected.count, "Path command count changed: \(actual.count) versus \(expected.count)")
        for (a, b) in zip(actual, expected) {
            let equivalent: Bool
            switch (a, b) {
            case (.move(let p), .move(let q)), (.line(let p), .line(let q)): equivalent = point(p, equals: q)
            case (.cubic(let a1, let a2, let p), .cubic(let b1, let b2, let q)):
                equivalent = point(a1, equals: b1) && point(a2, equals: b2) && point(p, equals: q)
            case (.quadratic(let c, let p), .quadratic(let d, let q)): equivalent = point(c, equals: d) && point(p, equals: q)
            case (.close, .close): equivalent = true
            default: equivalent = false
            }
            try expect(equivalent, "Curve/control point changed: \(a) versus \(b)")
        }
    }
    static func cubicCommands(_ commands: [SVGPathCommand]) -> [SVGPathCommand] {
        var current = CGPoint.zero, start = CGPoint.zero
        func between(_ a: CGPoint, _ b: CGPoint, _ fraction: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }
        return commands.map { command in
            switch command {
            case .move(let end): current = end; start = end; return command
            case .line(let end):
                let elevated = SVGPathCommand.cubic(control1: between(current, end, 1 / 3),
                    control2: between(current, end, 2 / 3), to: end)
                current = end; return elevated
            case .quadratic(let control, let end):
                let elevated = SVGPathCommand.cubic(control1: between(current, control, 2 / 3),
                    control2: between(end, control, 2 / 3), to: end)
                current = end; return elevated
            case .cubic(_, _, let end): current = end; return command
            case .arc(_, _, _, _, _, let end): current = end; return command
            case .close: current = start; return command
            }
        }
    }
    /// WebKit decodes ordinary SVG into canvas pixels, independently of SketchRenderer.
    /// No window, HTTP server, file access, or remote resources are used.
    static func renderedDifference(_ first: Data, _ second: Data) throws -> (changed: Int, ink: Int, maskMismatch: Int) {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), configuration: configuration)
        let html = """
        <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; script-src 'unsafe-inline'">
        <canvas id="pixels" width="240" height="160"></canvas><script>
        (async function () {
          try {
            const canvas = document.getElementById('pixels'), ctx = canvas.getContext('2d');
            async function pixels(base64) {
              const image = new Image();
              await new Promise((resolve, reject) => {
                image.onload = resolve; image.onerror = () => reject(new Error('SVG image decode failed'));
                image.src = 'data:image/svg+xml;base64,' + base64;
              });
              ctx.clearRect(0, 0, 240, 160); ctx.drawImage(image, 0, 0);
              return ctx.getImageData(0, 0, 240, 160).data;
            }
            const a = await pixels('\(first.base64EncodedString())'), b = await pixels('\(second.base64EncodedString())');
            let changed = 0, ink = 0, maskMismatch = 0;
            for (let i = 0; i < a.length; i += 4) {
              if (a[i] !== b[i] || a[i+1] !== b[i+1] || a[i+2] !== b[i+2] || a[i+3] !== b[i+3]) changed++;
              if (a[i+3] > 0 && (a[i] < 240 || a[i+1] < 240 || a[i+2] < 240)) ink++;
              const inkA = a[i+3] > 0 && Math.min(a[i], a[i+1], a[i+2]) < 220;
              const inkB = b[i+3] > 0 && Math.min(b[i], b[i+1], b[i+2]) < 220;
              if (inkA !== inkB) maskMismatch++;
            }
            window.svgTestResult = { changed, ink, maskMismatch };
          } catch (error) { window.svgTestResult = { error: String(error) }; }
        })();
        </script>
        """
        view.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(15)
        var result: [String: Any]?, pending = false
        while Date() < deadline && result == nil {
            if !pending {
                pending = true
                view.evaluateJavaScript("window.svgTestResult || null") { value, _ in
                    result = value as? [String: Any]; pending = false
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        view.stopLoading()
        guard let result else { throw Failure("Offscreen WebKit SVG rendering timed out; visual appearance unverified") }
        if let error = result["error"] { throw Failure("Offscreen WebKit SVG render: \(error)") }
        guard let changed = result["changed"] as? NSNumber, let ink = result["ink"] as? NSNumber, let mismatch = result["maskMismatch"] as? NSNumber else {
            throw Failure("WebKit returned no pixel measurements")
        }
        return (changed.intValue, ink.intValue, mismatch.intValue)
    }
    static func matrix(_ node: SVGTestNode) throws -> CGAffineTransform {
        guard let raw = node.attributes["transform"], raw.hasPrefix("matrix("), raw.hasSuffix(")") else {
            throw Failure("Missing SVG matrix")
        }
        let values = raw.dropFirst(7).dropLast().split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) }
        try expect(values.count == 6 && values.allSatisfy(\.isFinite), "Invalid SVG matrix")
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }
    static func png() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw Failure("Cannot build image fixture") }
        bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        bitmap.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), atX: 1, y: 0)
        bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: 0, y: 1)
        bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: 1, y: 1)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure("Cannot encode image fixture") }
        return data
    }
    static func embeddedPNG(_ image: SVGTestNode) throws -> Data {
        let prefix = "data:image/png;base64,"
        guard let href = image.attributes["xlink:href"], href.hasPrefix(prefix),
              let data = Data(base64Encoded: String(href.dropFirst(prefix.count))) else { throw Failure("Invalid PNG data URI") }
        try expect(NSImage(data: data) != nil, "Exported PNG is undecodable")
        return data
    }
    static var fixtureURL: URL {
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), index + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        // Resolve relative to this test source, not the caller's working directory.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("original/Skitch.app/Contents/Resources/firstlaunch.skitch")
    }
    static func originalFixture() throws -> (LegacySkitchDocument, SketchDocument, Data, SVGTestNode) {
        let original = try LegacySkitch.read(fixtureURL)
        let modern = try LegacyBridge.convert(original)
        let bytes = try SVGExport.encode(modern)
        return (original, modern, bytes, try SVGTestXML.read(bytes).root!)
    }

    static func main() {
        var passed = 0, failures: [String] = []
        let cases: [(String, () throws -> Void)] = [
            ("XML declaration, native marker, namespaces and document dimensions", {
                let (data, root) = try exported()
                try expect(String(decoding: data, as: UTF8.self).hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), "Missing UTF-8 declaration")
                try expect(try SVGTestXML.read(data).comments == [" Skitch 1.0 "], "Missing exact original marker")
                try expect(root.attributes["xmlns"] == "http://www.w3.org/2000/svg" && root.attributes["xmlns:xlink"] == "http://www.w3.org/1999/xlink", "SVG namespaces")
                try expect(try number(root, "width") == 240 && number(root, "height") == 160, "Canvas dimensions changed")
                try expect(root.children.count == 1 && root.children[0].name == "rect", "Empty document background")
            }),
            ("Cubic geometry retains controls, closure and editable vectors", {
                let element = nativePath(), (_, root) = try exported([element])
                try expect(root.named("path").count == 1 && root.named("image").isEmpty, "Vector was flattened or duplicated")
                try compareCommands(commands(root.named("path")[0]), element.pathCommands)
            }),
            ("Quadratic degree elevation preserves exact cubic control points", {
                var element = nativePath()
                element.pathCommands = [.move(to: CGPoint(x: 1, y: 2)), .quadratic(control: CGPoint(x: 40, y: 3), to: CGPoint(x: 80, y: 20)), .close]
                let (_, root) = try exported([element])
                try compareCommands(commands(root.named("path")[0]), element.pathCommands)
            }),
            ("Shape/line/arrow/brush exports contain vector paint instead of images", {
                for kind in [SketchElement.Kind.rectangle, .ellipse, .line, .arrow, .brush] {
                    var element = SketchElement(kind: kind)
                    element.rect = CGRect(x: 20, y: 30, width: 80, height: 40)
                    element.points = [CGPoint(x: 20, y: 80), CGPoint(x: 180, y: 80)]
                    element.strokeWidth = 10
                    let (_, root) = try exported([element]), paths = try paintPaths(root)
                    try expect(!paths.isEmpty && root.named("image").isEmpty, "\(kind) became raster or disappeared")
                    try expect(paths.allSatisfy { !$0.isEmpty }, "\(kind) exported empty paint")
                    if kind == .arrow { try expect(paths.contains { $0.contains(CGPoint(x: 155, y: 90)) }, "Arrowhead geometry missing") }
                }
            }),
            ("Single-point brush produces only nonempty dot paint", {
                var element = SketchElement(kind: .brush); element.points = [CGPoint(x: 70, y: 80)]; element.strokeWidth = 10
                let (_, root) = try exported([element]), paths = try paintPaths(root)
                try expect(paths.count == 1 && paths.allSatisfy { !$0.isEmpty }, "Dot export includes an empty stroked path")
                try expect(paths[0].contains(CGPoint(x: 70, y: 80)) && !paths[0].contains(CGPoint(x: 76, y: 80)), "Dot dimensions")
            }),
            ("Filled native path matches renderer fill-only behavior", {
                var element = nativePath(); element.strokeWidth = 12
                let (_, root) = try exported([element])
                try expect(root.named("path").count == 1, "Exporter adds a stroke around a filled native path; renderer uses fill only")
                try compareCommands(commands(root.named("path")[0]), element.pathCommands)
            }),
            ("XML text and font attributes escape all five special characters", {
                let content = "<&>\"' &amp; café 日本語 🖊\n\nlast\n"
                var element = text(content); element.fontName = "Font <&>\"'"
                element.rect.size = CGSize(width: 600, height: 200)
                let (data, root) = try exported([element]), groups = root.named("g")
                try expect(groups.count == 1 && groups[0].attributes["font-family"] == element.fontName, "Font attribute escaping")
                try expect(groups[0].named("text").map(\.text) == content.components(separatedBy: "\n"), "Text escaping/double escaping/blank lines")
                let xml = String(decoding: data, as: UTF8.self)
                for escaped in ["&lt;", "&gt;", "&quot;", "&apos;", "&amp;"] { try expect(xml.contains(escaped), "Missing \(escaped)") }
            }),
            ("Editable text metadata and explicit line positions retained", {
                var element = text(); element.outlined = true; element.shadowed = true; element.fontSize = 32
                let (_, root) = try exported([element]), node = root.named("g")[0], lines = node.named("text")
                try expect(node.attributes["font-family"] == element.fontName, "Font family changed")
                try expect(try number(node, "skitchFontSize") == 32 && number(node, "skitchTextX") == 25 && number(node, "skitchTextY") == 30, "Editor typography/anchor lost")
                try expect(node.attributes["skitchHasOutline"] == "1" && node.attributes["skitchHasShadow"] == "1", "Text flags lost")
                let font = NSFont(name: element.fontName, size: element.fontSize)!
                let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
                try expect(lines.count == 2 && approximately(try number(lines[1], "y") - number(lines[0], "y"), lineHeight), "SVG spacing differs from native AppKit text layout")
            }),
            ("Text is emitted after every vector despite mixed input order", {
                let (_, root) = try exported([text(), nativePath(), text("second")])
                try expect(root.children.filter { $0.name != "defs" }.map(\.name) == ["rect", "path", "g", "g"], "Text no longer floats above drawing")
            }),
            ("Rotated cubic controls are baked exactly once", {
                var element = nativePath(); element.transform = SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 30)
                let (_, root) = try exported([element]), node = root.named("path")[0]
                try expect(node.attributes["transform"] == nil, "Baked vector transform duplicated")
                try compareCommands(commands(node), [.move(to: CGPoint(x: 80, y: 40)),
                    .cubic(control1: CGPoint(x: 96, y: 42), control2: CGPoint(x: 94, y: 74), to: CGPoint(x: 80, y: 80)),
                    .line(to: CGPoint(x: 80, y: 40)), .close])
            }),
            ("Rotated stroked line retains width and world bounds", {
                var line = SketchElement(kind: .line); line.points = [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20)]
                line.strokeWidth = 4; line.transform = SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 30)
                let (_, root) = try exported([line]), bounds = try paintPaths(root)[0].boundingBoxOfPath
                try expect(approximately(bounds.minX, 78) && approximately(bounds.maxX, 82) && approximately(bounds.minY, 38) && approximately(bounds.maxY, 82), "Stroke transformed before width expansion or rotation applied twice")
            }),
            ("Group identity shared by transformed vectors and text", {
                let id = UUID(), other = UUID()
                var first = nativePath(group: id), second = nativePath(group: id), caption = text(group: id)
                let matrix = SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 30)
                first.transform = matrix; second.transform = matrix; caption.transform = matrix
                let (_, root) = try exported([first, second, caption, nativePath(group: other), nativePath()])
                let paths = root.named("path"), shared = paths[0].attributes["skitchGroup"]
                try expect(shared != "0" && shared != nil && paths[1].attributes["skitchGroup"] == shared && root.named("g")[0].attributes["skitchGroup"] == shared, "Group identity broke across classes")
                try expect(paths[2].attributes["skitchGroup"] != shared && paths[3].attributes["skitchGroup"] == "0", "Distinct/ungrouped identities changed")
                let t = try self.matrix(root.named("g")[0])
                try expect(point(CGPoint(x: 25, y: 30).applying(t), equals: CGPoint(x: 70, y: 55)), "Text group transform changed")
            }),
            ("Background and rotated raster retain exact embedded image bytes", {
                let image = try png(); var raster = SketchElement(kind: .raster)
                raster.imagePNG = image; raster.rect = CGRect(x: 10, y: 20, width: 30, height: 40)
                raster.transform = SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 30)
                let (_, root) = try exported([raster], png: image), nodes = root.named("image")
                try expect(nodes.count == 2 && root.children[1].name == "image", "Background/raster count or layering changed")
                try expect(try embeddedPNG(nodes[0]) == image && embeddedPNG(nodes[1]) == image, "PNG was re-encoded or corrupted")
                try expect(try number(nodes[0], "width") == 240 && number(nodes[0], "height") == 160, "Background dimensions")
                try expect(try number(nodes[1], "x") == 10 && number(nodes[1], "y") == 20 && number(nodes[1], "width") == 30 && number(nodes[1], "height") == 40, "Raster geometry lost")
                try expect(point(CGPoint(x: 10, y: 20).applying(matrix(nodes[1])), equals: CGPoint(x: 80, y: 40)), "Raster rotation changed")
            }),
            ("Raster retains its group alongside vector siblings", {
                let id = UUID(); var raster = SketchElement(kind: .raster)
                raster.rect = CGRect(x: 1, y: 2, width: 20, height: 30); raster.imagePNG = try png(); raster.groupID = id
                let (_, root) = try exported([nativePath(group: id), raster])
                try expect(root.named("image")[0].attributes["skitchGroup"] == root.named("path")[0].attributes["skitchGroup"], "Raster skitchGroup is missing")
            }),
            ("SVG alpha is explicit for both paint and background", {
                var path = nativePath(); path.color.alpha = 0.25
                let (_, root) = try exported([path], background: SketchColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0.5)))
                try expect(try fillAlpha(root.named("path")[0]) == 0.25 && fillAlpha(root.named("rect")[0]) == 0.5, "SVG alpha missing")
            }),
            ("Native Skitch alpha survives export and import", {
                var path = nativePath(); path.color.alpha = 0.25
                let (bytes, _) = try exported([path], background: SketchColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0.5)))
                let imported = try LegacySkitch.decode(bytes)
                try expect(imported.backgroundColor.alpha == 0.5 && imported.paths[0].color.alpha == 0.25,
                    "Original reader uses opacity; exporter writes only fill-opacity, so alpha becomes 1")
            }),
            ("Filled path with fractional alpha is not painted twice", {
                var element = nativePath(); element.strokeWidth = 12; element.color.alpha = 0.5
                let (_, root) = try exported([element])
                try expect(root.named("path").count == 1, "Overlapping extra stroke changes 0.5-alpha path edges to 0.75 alpha")
            }),
            ("Shadow is a visible SVG effect, not only private metadata", {
                var path = nativePath(); path.shadowed = true
                let (_, root) = try exported([path]), node = root.named("path")[0]
                try expect(node.attributes["skitchHasShadow"] == "1", "Shadow flag lost")
                try expect(node.attributes["filter"] != nil || node.attributes["style"]?.contains("filter") == true,
                    "SVG has no shadow filter/effect; generic viewers ignore skitchHasShadow")
            }),
            ("Text outline is a visible SVG effect", {
                var element = text(); element.outlined = true
                let (_, root) = try exported([element]), group = root.named("g")[0]
                let nodes = [group] + group.named("text")
                try expect(nodes.contains { $0.attributes["stroke"] != nil || $0.attributes["style"]?.contains("stroke") == true || $0.attributes["filter"] != nil },
                    "SVG contains no stroke/filter for outlined text; private flag alone has no visual effect")
            }),
            ("Portable SVG font family and weight retain the bold face", {
                let (_, root) = try exported([text()]), node = root.named("g")[0]
                let style = node.attributes["style"] ?? ""
                let family = node.attributes["font-family"] == "Helvetica" || style.contains("font-family:'Helvetica'") || style.contains("font-family:Helvetica;")
                let weight = ["700", "bold"].contains(node.attributes["font-weight"] ?? "") || style.contains("font-weight:700") || style.contains("font-weight:bold")
                try expect(family && weight, "PostScript Helvetica-Bold must have standard CSS family Helvetica and bold weight")
            }),
            ("WebKit SVG renderer paints vectors and detects changed colors", {
                var red = nativePath(); red.shadowed = false
                var blue = red; blue.color = SketchColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
                let result = try renderedDifference(exported([red]).0, exported([blue]).0)
                print("WEBKIT color control: \(result.changed) changed pixels; \(result.ink) vector ink pixels")
                try expect(result.ink > 100 && result.changed > 100, "Independent SVG renderer produced blank/unchanged pixels")
            }),
            ("WebKit SVG pixels include the exported shadow", {
                var plain = nativePath(); plain.shadowed = false
                // Keep the object away from canvas edges to avoid clipping the shadow.
                plain.transform = SketchTransform(a: 1, b: 0, c: 0, d: 1, tx: 60, ty: 50)
                var shadowed = plain; shadowed.shadowed = true
                let baseline = try exported([plain]).0
                // Positive control uses standard SVG filter primitives, not CSS filters.
                let definitions = "<defs><filter id=\"svg-test-shadow\" x=\"-100%\" y=\"-100%\" width=\"300%\" height=\"300%\"><feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"4\" result=\"blur\"/><feOffset in=\"blur\" dx=\"2\" dy=\"3\" result=\"offset\"/><feFlood flood-color=\"black\" flood-opacity=\"0.38\" result=\"color\"/><feComposite in=\"color\" in2=\"offset\" operator=\"in\" result=\"shadow\"/><feMerge><feMergeNode in=\"shadow\"/><feMergeNode in=\"SourceGraphic\"/></feMerge></filter></defs>"
                let controlSVG = String(decoding: baseline, as: UTF8.self).replacingOccurrences(of: "<path ", with: definitions + "<path filter=\"url(#svg-test-shadow)\" ")
                let control = try renderedDifference(baseline, Data(controlSVG.utf8))
                try expect(control.changed > 32, "Independent renderer cannot paint the standard SVG shadow control")
                let result = try renderedDifference(baseline, exported([shadowed]).0)
                print("WEBKIT shadow: \(result.changed) changed pixels; standard filter control: \(control.changed)")
                try expect(result.ink > 100 && result.changed > 32, "Exported shadow changes \(result.changed) pixels; SVG filter control changes \(control.changed). CSS drop-shadow is ineffective in WebKit's SVG image renderer")
            }),
            ("WebKit SVG pixels include the exported white text outline", {
                var plain = text("Outline"); plain.fontSize = 40
                var outlined = plain; outlined.outlined = true
                let background = SketchColor(NSColor(deviceRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
                let result = try renderedDifference(exported([plain], background: background).0, exported([outlined], background: background).0)
                print("WEBKIT text outline: \(result.changed) changed pixels")
                try expect(result.ink > 100 && result.changed > 32, "Text outline metadata/attributes have no ordinary SVG pixel effect")
            }),
            ("WebKit SVG text placement and wrapping match native rendered ink", {
                var element = text("Native text wraps across lines with spacing.")
                element.rect = CGRect(x: 20, y: 20, width: 175, height: 130)
                element.fontSize = 24; element.color = SketchColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1))
                var document = SketchDocument(size: CGSize(width: 240, height: 160)); document.elements = [element]
                guard let png = SketchRenderer.bitmap(document: document)?.representation(using: .png, properties: [:]) else { throw Failure("Native text bitmap failed") }
                let imageSVG = Data(("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"240\" height=\"160\"><image width=\"240\" height=\"160\" xlink:href=\"data:image/png;base64," + png.base64EncodedString() + "\"/></svg>").utf8)
                let result = try renderedDifference(imageSVG, SVGExport.encode(document))
                print("WEBKIT native/SVG wrapped text ink: \(result.ink); mismatched ink pixels: \(result.maskMismatch)")
                // Rasterizers differ at antialiased edges; a baseline/line-wrap shift
                // moves most glyph ink and exceeds this meaningful silhouette bound.
                try expect(result.ink > 500 && result.maskMismatch < max(50, result.ink / 5), "SVG text placement/wrapping differs substantially from native rendering")
            }),
            ("Original fixture export retains every vector and text line", {
                let (original, _, bytes, root) = try originalFixture()
                try expect(root.named("path").count == original.paths.count && root.named("g").count == original.texts.count && root.named("image").isEmpty, "Fixture was flattened or lost objects")
                try expect(try number(root, "width") == original.size.width && number(root, "height") == original.size.height, "Fixture dimensions changed")
                for (path, expected) in zip(root.named("path"), original.paths) { try compareCommands(commands(path), expected.commands) }
                try expect(root.named("g")[0].named("text").map(\.text) == ["Snap", "your", "screen"], "Fixture text changed")
                try expect(try SVGTestXML.read(bytes).comments == [" Skitch 1.0 "], "Fixture export marker changed")
            }),
            ("Original fixture export is readable by native document importer", {
                let (original, _, bytes, _) = try originalFixture()
                let imported: LegacySkitchDocument
                do { imported = try LegacySkitch.decode(bytes) }
                catch { throw Failure("Exported original fixture is rejected by LegacySkitch: \(error.localizedDescription)") }
                try expect(imported.paths.count == original.paths.count && imported.texts.map(\.content) == original.texts.map(\.content), "Native fixture round-trip loses content")
            }),
            ("Native Skitch path grammar uses M/C/z, including new stroked shapes", {
                var line = SketchElement(kind: .line); line.points = [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20)]; line.strokeWidth = 5
                let (_, root) = try exported([line])
                for path in root.named("path") {
                    let parsed = try commands(path)
                    try expect(parsed.allSatisfy {
                        switch $0 { case .move, .cubic, .close: return true; default: return false }
                    }, "Export emits L/Q commands that recovered original SubPathSegment::deSerialize does not accept (0x001c8400)")
                }
            }),
            ("Invalid model data is rejected before writing XML", {
                var invalid = SketchDocument(); invalid.size.width = .nan
                var rejected = false
                do { _ = try SVGExport.encode(invalid) } catch { rejected = true }
                try expect(rejected, "Invalid dimensions exported")
                invalid = SketchDocument(); var path = nativePath(); path.pathCommands = [.move(to: CGPoint(x: CGFloat.infinity, y: 0))]; invalid.elements = [path]
                rejected = false
                do { _ = try SVGExport.encode(invalid) } catch { rejected = true }
                try expect(rejected, "Nonfinite coordinates exported")
            }),
            ("Repeated export is deterministic and does not mutate document", {
                let group = UUID(); var document = SketchDocument(); document.elements = [nativePath(group: group), text(group: group)]
                let before = try document.encoded(), first = try SVGExport.encode(document), second = try SVGExport.encode(document)
                try expect(first == second && document.encoded() == before, "Export changes state or assigns unstable groups")
            })
        ]
        for (name, test) in cases {
            do { try test(); passed += 1; print("PASS \(name)") }
            catch { let message = "\(name): \(error)"; failures.append(message); print("FAIL \(message)") }
        }
        print("SVGExportTests: \(passed)/\(cases.count) passed; \(failures.count) failed")
        if !failures.isEmpty { exit(1) }
    }
}
#endif
