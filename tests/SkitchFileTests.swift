// Compile non-App sources with -D SKITCH_FILE_TESTS. No original app or network.
#if SKITCH_FILE_TESTS
import AppKit
import Foundation

@main
enum SkitchFileTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func rejects(_ data: Data, _ description: String) throws {
        do { _ = try SkitchFile.decode(data) }
        catch { return }
        throw Failure(description: "Accepted \(description)")
    }
    static func fixtureURL() -> URL {
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), index + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("original/Skitch.app/Contents/Resources/firstlaunch.skitch")
    }
    static func png() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let pixels = bitmap.bitmapData else {
            throw Failure(description: "PNG fixture allocation")
        }
        for y in 0..<2 { for x in 0..<2 {
            let offset = y * bitmap.bytesPerRow + x * 4
            pixels[offset] = x == 0 ? 255 : 0; pixels[offset + 1] = x == 1 ? 255 : 0
            pixels[offset + 2] = y == 1 ? 255 : 0; pixels[offset + 3] = y == 1 ? 128 : 255
        } }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "PNG fixture encoding") }
        return data
    }
    static func complex() throws -> SketchDocument {
        var document = SketchDocument(size: CGSize(width: 240, height: 160))
        document.backgroundColor = SketchColor(NSColor(deviceRed: 0.123456789, green: 0.456789123, blue: 0.789123456, alpha: 0.83))
        document.backgroundPNG = try png()
        let group = UUID(), other = UUID()
        for (index, kind) in [SketchElement.Kind.arrow, .line, .rectangle, .ellipse, .brush, .path, .raster, .text].enumerated() {
            var element = SketchElement(kind: kind)
            element.points = [CGPoint(x: 10.123456789, y: 20), CGPoint(x: 60, y: 80), CGPoint(x: 90, y: 65)]
            element.rect = CGRect(x: 20.123456789, y: 30, width: 110, height: 90)
            element.color = SketchColor(NSColor(deviceRed: 0.734567891, green: 0.234567891, blue: 0.334567891, alpha: 0.432198765))
            element.strokeWidth = 3.123456789; element.filled = [.rectangle, .ellipse, .path].contains(kind)
            element.shadowed = index % 2 == 0; element.groupID = index % 2 == 0 ? group : other
            element.text = "<&>\"' 日本語 café\n\nlast\n"; element.fontName = "Helvetica-BoldOblique"; element.fontSize = 18.123456789
            element.pathCommands = [.move(to: CGPoint(x: 10.123456789, y: 20)),
                .cubic(control1: CGPoint(x: 20, y: 2), control2: CGPoint(x: 55, y: 5), to: CGPoint(x: 90, y: 45)),
                .quadratic(control: CGPoint(x: 88, y: 100), to: CGPoint(x: 10, y: 60)), .close]
            element.transform = SketchTransform(a: 0.866025403784, b: 0.5, c: -0.5, d: 0.866025403784, tx: 50.123456789, ty: 8)
            if kind == .raster { element.imagePNG = try png() }
            document.elements.append(element)
        }
        return try document.validated()
    }
    static func native(_ child: String, extra: String = "") -> Data {
        Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- Skitch 1.0 -->\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"240\" height=\"160\" " + extra + ">" + child + "</svg>").utf8)
    }
    static func mutatedState(_ file: Data, _ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        let attributes = try LegacySkitch.decode(file).attributes
        guard let encoded = attributes["redux:state"], let bytes = Data(base64Encoded: encoded),
              var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw Failure(description: "Missing state for mutation")
        }
        try mutate(&object)
        let replacement = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
        return Data(String(decoding: file, as: UTF8.self).replacingOccurrences(of: encoded, with: replacement).utf8)
    }
    static func main() {
        _ = NSApplication.shared
        let cases: [(String, () throws -> Void)] = [
            ("Original fixture remains editable after save and reopen", {
                let original = try LegacySkitch.read(fixtureURL()), imported = try SkitchFile.read(fixtureURL())
                try expect(imported.document.elements.filter { $0.kind == .path }.count == 3 && imported.document.elements.last?.text == "Snap\nyour\nscreen", "Fixture editability")
                let saved = try imported.encoded(), reopened = try SkitchFile.decode(saved)
                try expect(reopened.document == imported.document && reopened.metadata == imported.metadata, "Exact imported model/state round-trip")
                let visible = try LegacySkitch.decode(imported.encoded(includeSupplementalState: false))
                for (actual, expected) in zip(visible.paths, original.paths) {
                    try expect(actual.commands == expected.commands && actual.color == expected.color && actual.hasShadow == expected.hasShadow, "Original fixture curve/paint changed")
                }
                try expect(visible.paths.count == original.paths.count && visible.texts[0].anchor == original.texts[0].anchor && visible.texts[0].content == original.texts[0].content && visible.texts[0].lines.first?.position == original.texts[0].lines.first?.position, "Original anchor/first baseline/content lost")
                try expect(imported.metadata.elements.values.compactMap(\.originalText).first?.lines == original.texts[0].lines, "Original line metadata lost")
                try expect(visible.attributes["skitchBrushColor"] == original.attributes["skitchBrushColor"] && visible.attributes["skitchBrushSize"] == original.attributes["skitchBrushSize"], "Recovered brush metadata lost")
            }),
            ("Every model field, ID, group, raster byte and transform round-trips exactly", {
                let document = try complex(), file = SkitchFile(document: document)
                let reopened = try SkitchFile.decode(file.encoded())
                try expect(reopened.document == document, "Complex native document differs")
                try expect(reopened.document.encoded() == document.encoded(), "Full Codable field bytes changed")
                try expect(reopened.originalCompatibilityWarnings.count == 2, "Original engine limitations must be explicit")
            }),
            ("Supplement-free SVG retains editable vector/text/raster content", {
                let document = try complex(), file = SkitchFile(document: document)
                let bytes = try file.encoded(includeSupplementalState: false), original = try LegacySkitch.decode(bytes)
                try expect(!original.paths.isEmpty && original.images.count == 2 && original.texts.count == 1, "SVG contains only supplemental content or flattened vectors")
                try expect(original.images[0].pngData == document.backgroundPNG && original.images[1].pngData == document.elements[6].imagePNG, "Raster payload changed")
                try expect(original.texts[0].content.replacingOccurrences(of: "\n", with: "") == document.elements[7].text.replacingOccurrences(of: "\n", with: "") && original.texts[0].fontName == document.elements[7].fontName, "Visible editable text characters/font missing")
                for path in original.paths { try expect(path.commands.allSatisfy { switch $0 { case .move, .cubic, .close: return true; default: return false } }, "Original grammar violation") }
                let reopened = try SkitchFile.decode(bytes)
                try expect(reopened.document.elements.contains { $0.kind == .path } && reopened.document.elements.contains { $0.kind == .raster } && reopened.document.elements.contains { $0.kind == .text }, "Independent import lost editable object classes")
            }),
            ("Declaration, exact marker and complete recovered root schema", {
                let bytes = try SkitchFile(document: SketchDocument()).encoded(), text = String(decoding: bytes, as: UTF8.self)
                try expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- Skitch 1.0 -->\n<svg "), "Original declaration/comment/root order")
                let attributes = try LegacySkitch.decode(bytes).attributes
                for key in ["xmlns", "xmlns:xlink", "xmlns:ev", "version", "baseProfile", "width", "height", "overflow", "skitchDocumentType", "skitchVisibleWidth", "skitchVisibleHeight", "skitchCustomColor", "skitchCustomColorAlpha", "skitchBrushColor", "skitchBrushColorAlpha", "skitchBrushSize", "skitchTool", "skitchSourceURL", "skitchExternalAppDocumentPath"] {
                    try expect(attributes[key] != nil, "Missing original root key \(key)")
                }
            }),
            ("Unknown original attributes stay with objects across reorder and edits", {
                let xml = native("<rect x=\"0\" y=\"0\" width=\"240\" height=\"160\" fill=\"rgb(255,255,255)\" futureBackdrop=\"retained\"/><path d=\"M10 10 C20 0 40 0 50 10 z\" fill=\"rgb(255,0,0)\" skitchGroup=\"77\" futurePath=\"A&amp;B\"/><g skitchTextX=\"90\" skitchTextY=\"40\" font-family=\"Helvetica-Bold\" font-size=\"24\" skitchGroup=\"77\" futureText=\"text-meta\"><text x=\"85\" y=\"60\" futureLine=\"line-meta\">Caption</text></g>", extra: "futureRoot=\"root-meta\" skitchSourceURL=\"local fixture\"")
                var file = try SkitchFile.decode(xml)
                file.document.elements.reverse()
                let pathIndex = file.document.elements.firstIndex { $0.kind == .path }!
                file.document.elements[pathIndex].color.alpha = 0.25
                let visible = try LegacySkitch.decode(file.encoded(includeSupplementalState: false))
                try expect(visible.attributes["futureRoot"] == "root-meta" && visible.backgroundAttributes["futureBackdrop"] == "retained", "Root/backdrop metadata dropped")
                try expect(visible.paths[0].attributes["futurePath"] == "A&B" && visible.paths[0].color.alpha == 0.25 && visible.paths[0].group == 77, "Path/group metadata shifted or edits overwritten")
                try expect(visible.texts[0].attributes["futureText"] == "text-meta" && visible.texts[0].lines[0].attributes["futureLine"] == "line-meta" && visible.texts[0].anchor == CGPoint(x: 90, y: 40), "Text/line/anchor metadata lost")
                try expect(SkitchFile.decode(file.encoded()).document == file.document, "Reordered model lost")
            }),
            ("Partial backdrop remains a placed raster with original PNG bytes", {
                let image = try png(), uri = image.base64EncodedString()
                let bytes = native("<image x=\"12\" y=\"23\" width=\"50\" height=\"70\" xlink:href=\"data:image/png;base64,\(uri)\"/>")
                let file = try SkitchFile.decode(bytes)
                try expect(file.document.backgroundPNG == nil && file.document.elements.count == 1 && file.document.elements[0].kind == .raster, "Partial backdrop was stretched/flattened")
                try expect(file.document.elements[0].rect == CGRect(x: 12, y: 23, width: 50, height: 70) && file.document.elements[0].imagePNG == image, "Image placement/bytes changed")
            }),
            ("SVG matrices and interleaved raster/path order are independently editable", {
                let image = try png().base64EncodedString()
                let bytes = native("<path d=\"M10 10 C20 0 40 0 50 10 z\" fill=\"rgb(255,0,0)\" transform=\"matrix(0 1 -1 0 100 20)\"/><image x=\"12\" y=\"23\" width=\"50\" height=\"70\" transform=\"matrix(1 0.2 0 1 5 6)\" xlink:href=\"data:image/png;base64,\(image)\"/>")
                let file = try SkitchFile.decode(bytes), elements = file.document.elements
                try expect(elements.map(\.kind) == [.path, .raster] && elements[0].transform == SketchTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 20) && elements[1].transform.b == 0.2, "Matrix/order lost")
                try expect(SkitchFile.decode(file.encoded()).document == file.document, "Matrix round-trip")
            }),
            ("Exact high-precision model alpha survives RGB quantization in visible SVG", {
                let file = SkitchFile(document: try complex()), visible = try LegacySkitch.decode(file.encoded(includeSupplementalState: false))
                try expect(abs(visible.paths[0].color.alpha - file.document.elements[0].color.alpha) < 0.000001, "Original-facing opacity missing")
                try expect(SkitchFile.decode(file.encoded()).document.backgroundColor == file.document.backgroundColor, "Supplement lost exact native color precision")
            }),
            ("Atomic .skitch and legacy .skitchredux save/reopen", {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let file = SkitchFile(document: try complex())
                for ext in ["skitch", "skitchredux"] {
                    let url = directory.appendingPathComponent("editable." + ext)
                    try file.write(to: url)
                    try expect(SkitchFile.read(url).document == file.document, "Disk save/reopen \(ext)")
                    let first = try Data(contentsOf: url).first
                    try expect(first == (ext == "skitch" ? 60 : 123), "Incorrect on-disk format for \(ext)")
                }
            }),
            ("Full Canvas pan source survives native and old-extension disk reopen", {
                let source = try png(), sourceSize = CGSize(width: 2, height: 2), offset = CGPoint(x: -1, y: 20)
                var document = SketchDocument(size: CGSize(width: 240, height: 160))
                guard let image = NSImage(data: source), let viewport = SketchRenderer.bitmap(size: document.size, draw: {
                    SketchRenderer.drawImage(image, in: CGRect(origin: offset, size: sourceSize))
                })?.representation(using: .png, properties: [:]) else { throw Failure(description: "Pan viewport fixture") }
                document.backgroundPNG = viewport
                var object = try JSONSerialization.jsonObject(with: document.encoded()) as! [String: Any]
                let encoder = JSONEncoder()
                object["canvasPanBackground"] = ["sourcePNG": source.base64EncodedString(),
                    "sourceSize": try JSONSerialization.jsonObject(with: encoder.encode(sourceSize)),
                    "offset": try JSONSerialization.jsonObject(with: encoder.encode(offset))]
                let raw = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                try expect(CanvasView.validatedDocumentData(raw) == document, "Canvas fixture fails authoritative validation")
                let file = SkitchFile(document: document, canvasData: raw), saved = try file.encoded()
                let reopened = try SkitchFile.decode(saved)
                try expect(reopened.canvasData == raw && reopened.document == document, "Native envelope drops hidden pan pixels")
                let visible = try LegacySkitch.decode(file.encoded(includeSupplementalState: false))
                try expect(visible.images.count == 1 && visible.images[0].pngData == source && visible.images[0].rect == CGRect(origin: offset, size: sourceSize), "SVG backdrop fails to retain full source/offset")
                let canvas = CanvasView(frame: .zero)
                try canvas.loadDocument(data: reopened.canvasData)
                let reencoded = try JSONSerialization.jsonObject(with: canvas.snapshotDocumentData()) as! [String: Any]
                let recovered = reencoded["canvasPanBackground"] as? [String: Any]
                try expect(recovered?["sourcePNG"] as? String == source.base64EncodedString(), "Canvas load loses pan source")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                for ext in ["skitch", "skitchredux"] {
                    let url = directory.appendingPathComponent("pan." + ext); try file.write(to: url)
                    let loaded = try SkitchFile.read(url)
                    try expect(loaded.canvasData == raw, "\(ext) save drops raw CanvasFile pan state")
                }
            }),
            ("Canvas snapshots must match the document and fully validate pan state", {
                let document = try complex()
                var different = document; different.backgroundColor.alpha = 0.2
                let stale = SkitchFile(document: document, canvasData: try different.encoded())
                var rejected = false
                do { _ = try stale.encoded() } catch { rejected = true }
                try expect(rejected, "Mismatched raw document accepted")
                var object = try JSONSerialization.jsonObject(with: document.encoded()) as! [String: Any]
                object["canvasPanBackground"] = ["sourcePNG": "broken", "sourceSize": [2, 2], "offset": [0, 0]]
                let invalid = try JSONSerialization.data(withJSONObject: object)
                let file = SkitchFile(document: document, canvasData: invalid)
                rejected = false
                do { _ = try file.canvasData } catch { rejected = true }
                try expect(rejected, "Canvas getter returns unvalidated pan state")
                rejected = false
                do { _ = try file.encoded() } catch { rejected = true }
                try expect(rejected, "Native save accepts invalid pan state")
                try rejects(invalid, "invalid full .skitchredux CanvasFile")
            }),
            ("Equivalent XML formatting is accepted without stale-state errors", {
                let file = SkitchFile(document: try complex()), bytes = try file.encoded()
                let formatted = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\n", with: "\n    ")
                try expect(SkitchFile.decode(Data(formatted.utf8)).document == file.document, "Whitespace-only XML formatting failed")
            }),
            ("Visible SVG edits cannot be silently overridden by hidden state", {
                let bytes = try SkitchFile(document: try complex()).encoded()
                let changed = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "skitchBrushSize=\"6.75\"", with: "skitchBrushSize=\"6\"")
                try expect(changed != String(decoding: bytes, as: UTF8.self), "Mutation did not alter SVG")
                try rejects(Data(changed.utf8), "conflicting visible SVG")
            }),
            ("Early Redux implicit defaults migrate without weakening SVG consistency", {
                let defaults = ["skitchCustomColor": "rgb(0,0,0)", "skitchCustomColorAlpha": "1",
                                "skitchBrushColor": "rgb(252,12,89)", "skitchBrushColorAlpha": "1", "skitchBrushSize": "5"]
                var metadata = LegacyBridge.Metadata(); metadata.root = defaults
                let document = try complex()
                let explicit = try SkitchFile(document: document, metadata: metadata).encoded()
                let early = try mutatedState(explicit) { envelope in
                    var metadata = envelope["metadata"] as! [String: Any]
                    metadata["root"] = [String: String](); envelope["metadata"] = metadata
                }
                let reopened = try SkitchFile.decode(early)
                try expect(reopened.document == document && reopened.metadata.root == defaults,
                           "Known early defaults must restore explicitly with exact editable artwork")
                let saved = try reopened.encoded(), again = try SkitchFile.decode(saved)
                try expect(again.document == document && again.metadata == reopened.metadata,
                           "Migrated defaults survive save/reopen instead of adopting changed export constants")
                try rejects(mutatedState(early) { envelope in
                    var document = envelope["document"] as! [String: Any]
                    var elements = document["elements"] as! [[String: Any]]
                    elements[0]["strokeWidth"] = 19
                    document["elements"] = elements; envelope["document"] = document
                }, "conflicting hidden artwork in an early file")
                let visibleEdit = String(decoding: early, as: UTF8.self).replacingOccurrences(of: "skitchBrushSize=\"5\"", with: "skitchBrushSize=\"6\"")
                try rejects(Data(visibleEdit.utf8), "conflicting early visible defaults")
            }),
            ("Hidden model edits cannot bypass visible SVG consistency", {
                let bytes = try SkitchFile(document: try complex()).encoded()
                let changed = try mutatedState(bytes) { envelope in
                    var document = envelope["document"] as! [String: Any]
                    var elements = document["elements"] as! [[String: Any]]
                    elements[0]["strokeWidth"] = 19
                    document["elements"] = elements; envelope["document"] = document
                }
                try rejects(changed, "conflicting hidden model")
            }),
            ("Unknown supplemental version and corrupt base64 are rejected", {
                let bytes = try SkitchFile(document: SketchDocument()).encoded()
                try rejects(mutatedState(bytes) { $0["version"] = 99 }, "unknown supplemental version")
                let encoded = try LegacySkitch.decode(bytes).attributes["redux:state"]!
                try rejects(Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: encoded, with: "!").utf8), "corrupt state base64")
            }),
            ("Malformed XML, marker, dimensions and DTD are rejected", {
                for bytes in [Data("<svg>".utf8), native("", extra: "height=\"3\""),
                    Data(String(decoding: native(""), as: UTF8.self).replacingOccurrences(of: "Skitch 1.0", with: "Skitch 2.0").utf8),
                    Data(String(decoding: native(""), as: UTF8.self).replacingOccurrences(of: "width=\"240\"", with: "width=\"nan\"").utf8),
                    Data("<?xml version=\"1.0\"?><!DOCTYPE svg [<!ENTITY hidden \"x\">]><!-- Skitch 1.0 --><svg width=\"2\" height=\"2\"/>".utf8)] {
                    try rejects(bytes, "malformed original document")
                }
            }),
            ("Unsupported paint, event handlers, groups and image links are rejected", {
                for child in ["<script>1</script>", "<g><path d=\"M0 0z\"/></g>",
                    "<image width=\"2\" height=\"2\" xlink:href=\"https://invalid.example/image.png\"/>",
                    "<path d=\"M0 0L10 10\" stroke=\"red\"/>", "<path d=\"M0 0z\" style=\"display:none\"/>",
                    "<path d=\"M0 0z\" onclick=\"1\"/>", "<path d=\"M0 0z\" fill-rule=\"evenodd\"/>",
                    "<path d=\"\"/>"] { try rejects(native(child), "unsupported paint/content") }
            }),
            ("Invalid matrices and corrupt images are rejected without approximation", {
                for matrix in ["rotate(90)", "matrix(1 0 0 0 0 0)", "matrix(1 0 0 1 nan 0)", "matrix(1,,0,0,1,0,0)", "matrix(1 0 0 1 0)"] {
                    try rejects(native("<path d=\"M0 0 C1 1 2 2 3 3z\" transform=\"\(matrix)\"/>"), "invalid matrix")
                }
                let signature = Data([137, 80, 78, 71, 13, 10, 26, 10]).base64EncodedString()
                try rejects(native("<image width=\"2\" height=\"2\" xlink:href=\"data:image/png;base64,\(signature)\"/>"), "corrupt PNG")
            }),
            ("Invalid native documents and duplicate IDs fail before save", {
                var document = try complex(); document.size.width = .nan
                var rejected = false
                do { _ = try SkitchFile(document: document).encoded() } catch { rejected = true }
                try expect(rejected, "Invalid size accepted")
                document = try complex(); document.elements[1].id = document.elements[0].id
                rejected = false
                do { _ = try SkitchFile(document: document).encoded() } catch { rejected = true }
                try expect(rejected, "Duplicate IDs accepted")
            }),
            ("Saves are deterministic and leave the editing document unchanged", {
                let file = SkitchFile(document: try complex()), before = try file.document.encoded()
                try expect(file.encoded() == file.encoded() && file.document.encoded() == before, "Save mutates or changes group ordering")
            })
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("SkitchFileTests: \(cases.count - failures)/\(cases.count) passed; \(failures) failed")
        if failures != 0 { exit(1) }
    }
}
#endif
