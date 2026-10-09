// Executable regression tests for the native .opensnap document; no app launch, no network. Run via tools/test.py.
#if OPENSNAP_FILE_TESTS
import AppKit
import Foundation

@main
enum OpenSnapFileTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func rejects(_ data: Data, _ description: String) throws {
        do { _ = try OpenSnapFile.decode(data) } catch { return }
        throw Failure(description: "Accepted \(description)")
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
    @MainActor static func main() {
        _ = NSApplication.shared
        let defaults = DrawingDefaults(values: ["brushColor": "rgb(1,2,3)", "brushSize": "6.5"])
        let cases: [(String, () throws -> Void)] = [
            ("The format has its own identifier and extension", {
                try expect(SketchDocument.fileExtension == "opensnap" && OpenSnapFile.fileExtension == "opensnap", "Extension")
                try expect(SketchDocument.formatIdentifier == "com.shoemoney.opensnap.document" && OpenSnapFile.typeIdentifier == SketchDocument.formatIdentifier, "Identifier")
            }),
            ("Every model field, ID, group, raster byte and transform round-trips exactly", {
                let document = try complex(), file = OpenSnapFile(document: document, drawingDefaults: defaults)
                let reopened = try OpenSnapFile.decode(file.encoded())
                try expect(reopened.document == document, "Complex native document differs")
                try expect(reopened.document.encoded() == document.encoded(), "Full Codable field bytes changed")
                try expect(reopened.drawingDefaults == defaults, "Drawing defaults differ")
            }),
            ("Re-saving a reopened file is byte-stable and never duplicates the defaults entry", {
                let first = try OpenSnapFile(document: try complex(), drawingDefaults: defaults).encoded()
                let second = try OpenSnapFile.decode(first).encoded()
                try expect(first == second, "Second save differs from the first")
                try expect(String(decoding: second, as: UTF8.self).components(separatedBy: "\"drawingDefaults\"").count == 2, "Defaults entry duplicated")
            }),
            ("Canvas data with hidden pan pixels is preserved exactly", {
                let view = CanvasView(frame: .zero); view.newBlank(size: CGSize(width: 100, height: 80))
                let raw = try view.snapshotDocumentData(), document = try CanvasView.validatedDocumentData(raw)
                let file = OpenSnapFile(document: document, drawingDefaults: defaults, canvasData: raw)
                let reopened = try OpenSnapFile.decode(file.encoded())
                try expect(try reopened.canvasData == raw, "Canvas bytes changed")
            }),
            ("A file without defaults still opens", {
                let bytes = try OpenSnapFile(document: try complex()).encoded()
                try expect(!String(decoding: bytes, as: UTF8.self).contains("drawingDefaults"), "Empty defaults were written")
                try expect(try OpenSnapFile.decode(bytes).drawingDefaults == DrawingDefaults(), "Defaults not empty")
            }),
            ("Retired formats are rejected, never read", {
                try rejects(Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"></svg>".utf8), "an SVG drawing")
                try rejects(Data(), "empty data"); try rejects(Data("not a drawing".utf8), "text")
            }),
            ("Unsupported versions and corrupt payloads are rejected", {
                var document = try complex(); document.version = 2
                let encoder = JSONEncoder()
                try rejects(try encoder.encode(document), "an unsupported version")
                var tampered = try OpenSnapFile(document: try complex()).encoded()
                tampered.replaceSubrange(0..<1, with: Data("[".utf8))
                try rejects(tampered, "a corrupt object")
            }),
            ("Invalid native documents and duplicate IDs fail before save", {
                var document = try complex(); document.size.width = .nan
                var rejected = false
                do { _ = try OpenSnapFile(document: document).encoded() } catch { rejected = true }
                try expect(rejected, "Invalid size accepted")
                document = try complex(); document.elements[1].id = document.elements[0].id
                rejected = false
                do { _ = try OpenSnapFile(document: document).encoded() } catch { rejected = true }
                try expect(rejected, "Duplicate IDs accepted")
            }),
            ("Saves are deterministic and leave the editing document unchanged", {
                let file = OpenSnapFile(document: try complex(), drawingDefaults: defaults), before = try file.document.encoded()
                try expect(file.encoded() == file.encoded() && file.document.encoded() == before, "Save mutates or changes ordering")
            }),
            ("Files on disk round-trip through write and read, and oversize files are refused", {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-file-tests-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let url = folder.appendingPathComponent("drawing.opensnap"), document = try complex()
                try OpenSnapFile(document: document, drawingDefaults: defaults).write(to: url)
                let reopened = try OpenSnapFile.read(url)
                try expect(reopened.document == document && reopened.drawingDefaults == defaults, "Disk round trip")
                let huge = folder.appendingPathComponent("huge.opensnap")
                FileManager.default.createFile(atPath: huge.path, contents: nil)
                let handle = try FileHandle(forWritingTo: huge); try handle.truncate(atOffset: UInt64(OpenSnapFile.maximumFileBytes) + 1); try handle.close()
                var rejected = false
                do { _ = try OpenSnapFile.read(huge) } catch { rejected = true }
                try expect(rejected, "Oversize file accepted")
            }),
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("OpenSnapFileTests: \(cases.count - failures)/\(cases.count) passed; \(failures) failed")
        if failures != 0 { exit(1) }
    }
}
#endif
