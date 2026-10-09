// No Canvas, windows or desktop input is required. From the repository root:
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D IMAGE_EXPORT_TESTS \
//   Sources/{SVGPath,DocumentModel,VectorGeometry,ImageExport}.swift \
//   tests/ImageExportTests.swift -o /tmp/opensnap-image-export-tests
// /tmp/opensnap-image-export-tests
#if IMAGE_EXPORT_TESTS
import AppKit
import ImageIO
import Darwin

@main
enum ImageExportTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
    }
    static func required<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(description: message) }; return value
    }
    static func bytes(_ document: SketchDocument, _ size: CGSize, _ format: String,
                      quality: Double = 0.7) throws -> Data {
        try required(ImageExport.encode(document: document, size: size, format: format,
                                        jpegQuality: quality), "Cannot encode \(format)")
    }
    static func decoded(_ data: Data) throws -> CGImage {
        let source = try required(CGImageSourceCreateWithData(data as CFData, nil), "Cannot read image")
        return try required(CGImageSourceCreateImageAtIndex(source, 0, nil), "Cannot decode image pixels")
    }
    static func color(_ image: CGImage, _ x: Int, _ y: Int) throws -> NSColor {
        try required(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                     "Cannot sample image")
    }
    static func fixture() -> SketchDocument {
        var document = SketchDocument(size: CGSize(width: 80, height: 60))
        document.backgroundColor = .clear
        document.renderSize = CGSize(width: 33, height: 27)
        var shape = SketchElement(kind: .rectangle)
        shape.rect = CGRect(x: 4, y: 5, width: 14, height: 12)
        shape.transform = .translation(x: 10, y: 5)
        shape.color = SketchColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        shape.strokeWidth = 2; shape.filled = true; shape.groupID = UUID()
        var path = SketchElement(kind: .path)
        path.pathCommands = [.move(to: CGPoint(x: 60, y: 40)), .line(to: CGPoint(x: 75, y: 40)),
                             .line(to: CGPoint(x: 75, y: 55)), .close]
        path.filled = true; path.strokeWidth = 0; path.color = SketchColor(.blue)
        document.elements = [shape, path]
        return document
    }
    static func assertScaledInk(_ image: CGImage) throws {
        // The asymmetric landmarks distinguish scaling from clipping or changing the canvas.
        let red = try color(image, image.width / 4, image.height / 4)
        let blue = try color(image, image.width * 9 / 10, image.height * 3 / 4)
        try expect(red.redComponent > 0.9 && red.blueComponent < 0.1, "Translated shape not scaled in full")
        try expect(blue.blueComponent > 0.9 && blue.redComponent < 0.1, "Far-edge vector clipped or misplaced")
    }
    static func gradient() throws -> SketchDocument {
        let width = 256, height = 192
        let bitmap = try required(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Gradient allocation")
        let pixels = try required(bitmap.bitmapData, "Gradient storage")
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bitmap.bytesPerRow + x * 4
                let ripple = Int(24 * sin(Double(x * 7 + y * 11)))
                pixels[offset] = UInt8(clamping: x + ripple)
                pixels[offset + 1] = UInt8(clamping: y * 255 / (height - 1) - ripple)
                pixels[offset + 2] = UInt8(clamping: (x + y) * 255 / (width + height - 2) + ripple)
                pixels[offset + 3] = 255
            }
        }
        var document = SketchDocument(size: CGSize(width: width, height: height))
        document.backgroundPNG = try required(bitmap.representation(using: .png, properties: [:]), "Gradient PNG")
        return document
    }
    static func pdfDocument(_ data: Data) throws -> CGPDFDocument {
        let provider = try required(CGDataProvider(data: data as CFData), "PDF provider")
        return try required(CGPDFDocument(provider), "Cannot decode PDF")
    }
    static func rasterizedPDF(_ page: CGPDFPage, size: CGSize) throws -> CGImage {
        let context = try required(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), "PDF raster context")
        context.drawPDFPage(page)
        return try required(context.makeImage(), "PDF raster image")
    }
    static func expectInvalidDocument(_ document: SketchDocument) throws {
        var rejected = false
        do { _ = try document.validated() } catch { rejected = true }
        try expect(rejected, "Invalid document passed validation")
        try expect(ImageExport.image(document: document, size: CGSize(width: 20, height: 20)) == nil,
                   "Invalid document produced an image")
        for format in ["png", "jpeg", "tiff", "gif", "bmp", "pdf"] {
            try expect(ImageExport.encode(document: document, size: CGSize(width: 20, height: 20),
                                          format: format) == nil, "Invalid document exported as \(format)")
        }
    }
    static func main() {
        let cases: [(String, () throws -> Void)] = [
            ("All raster formats decode with explicit output dimensions and scaled geometry", {
                let document = fixture(), size = CGSize(width: 160, height: 90)
                for format in ["png", "jpeg", "tiff", "gif", "bmp"] {
                    let image = try decoded(bytes(document, size, format))
                    try expect(image.width == 160 && image.height == 90, "\(format) actual dimensions")
                    try assertScaledInk(image)
                }
            }),
            ("Fractional output dimensions round upward within pixel limits", {
                for format in ["png", "jpeg", "tiff", "gif", "bmp"] {
                    let image = try decoded(bytes(fixture(), CGSize(width: 41.25, height: 31.75), format))
                    try expect(image.width == 42 && image.height == 32, "\(format) fractional pixel dimensions")
                }
            }),
            ("Export and original-size temporary rendering preserve every model field", {
                let document = fixture(), before = try document.encoded()
                for size in [document.outputSize, document.size, CGSize(width: 160, height: 90)] {
                    for format in ["png", "jpeg", "tiff", "gif", "bmp", "pdf"] {
                        _ = try bytes(document, size, format)
                    }
                    let image = try required(ImageExport.image(document: document, size: size), "Output NSImage")
                    try expect(image.size == size, "NSImage logical size ignored explicit size")
                    let bitmap = try required(image.representations.first as? NSBitmapImageRep, "NSImage bitmap")
                    try expect(bitmap.pixelsWide == Int(ceil(size.width)) && bitmap.pixelsHigh == Int(ceil(size.height)),
                               "NSImage pixel size changed")
                    try assertScaledInk(required(bitmap.cgImage, "NSImage pixels"))
                }
                try expect(try document.encoded() == before,
                           "Source geometry, transforms, groups, or output preference mutated")
            }),
            ("PNG and TIFF retain fractional alpha; GIF retains transparent pixels", {
                var document = SketchDocument(size: CGSize(width: 32, height: 24))
                document.backgroundColor = SketchColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0.25))
                for format in ["png", "tiff"] {
                    let pixel = try color(decoded(bytes(document, document.size, format)), 15, 10)
                    try expect(abs(pixel.alphaComponent - 0.25) < 0.02 && pixel.redComponent > 0.9,
                               "\(format) alpha or unpremultiplied color lost")
                }
                document.backgroundColor = .clear
                for format in ["png", "tiff", "gif"] {
                    let pixel = try color(decoded(bytes(document, document.size, format)), 15, 10)
                    try expect(pixel.alphaComponent < 0.02, "\(format) transparent pixel became opaque")
                }
            }),
            ("JPEG and BMP composite transparent and translucent pixels over white", {
                var document = SketchDocument(size: CGSize(width: 32, height: 24))
                for alpha: CGFloat in [0, 0.25] {
                    document.backgroundColor = SketchColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: alpha))
                    for format in ["jpeg", "bmp"] {
                        let pixel = try color(decoded(bytes(document, document.size, format)), 15, 10)
                        // Decode the independently calculated opaque reference through
                        // the same format to account for embedded color profiles.
                        var reference = SketchDocument(size: document.size)
                        reference.backgroundColor = SketchColor(NSColor(deviceRed: 1, green: 1 - alpha,
                                                                       blue: 1 - alpha, alpha: 1))
                        let expected = try color(decoded(bytes(reference, reference.size, format)), 15, 10)
                        try expect(pixel.alphaComponent > 0.99 && pixel.redComponent > 0.97 &&
                                   abs(pixel.greenComponent - expected.greenComponent) < 0.025 &&
                                   abs(pixel.blueComponent - expected.blueComponent) < 0.025,
                                   "\(format) white composition is incorrect at alpha \(alpha): \(pixel); expected \(expected)")
                    }
                }
            }),
            ("PNG keeps alpha: a transparent canvas with a drawn shape and a translucent snapshot stays transparent where empty", {
                var document = SketchDocument(size: CGSize(width: 40, height: 30))
                document.backgroundColor = .clear
                var shape = SketchElement(kind: .rectangle)
                shape.rect = CGRect(x: 10, y: 10, width: 20, height: 10); shape.filled = true
                shape.color = SketchColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
                document.elements = [shape]
                let rep = try required(NSBitmapImageRep(data: bytes(document, document.size, "png")), "PNG decodes")
                try expect(rep.hasAlpha && rep.colorAt(x: 1, y: 1)!.alphaComponent < 0.01 && rep.colorAt(x: 20, y: 15)!.alphaComponent > 0.99, "PNG flattened transparency")
                // A captured window: opaque body, fully transparent corner, translucent shadow edge.
                let snap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                for y in 0..<30 { for x in 0..<40 { snap.setColor(x < 4 ? .clear : NSColor(deviceRed: 0, green: 1, blue: 0, alpha: x < 8 ? 0.5 : 1), atX: x, y: y) } }
                var windowDoc = SketchDocument(size: CGSize(width: 40, height: 30))
                windowDoc.backgroundColor = .clear
                windowDoc.backgroundPNG = snap.representation(using: .png, properties: [:])
                let out = try required(NSBitmapImageRep(data: bytes(windowDoc, windowDoc.size, "png")), "window PNG decodes")
                let corner = out.colorAt(x: 1, y: 15)!.alphaComponent, edge = out.colorAt(x: 6, y: 15)!.alphaComponent, body = out.colorAt(x: 30, y: 15)!.alphaComponent
                try expect(corner < 0.02 && abs(edge - 0.5) < 0.05 && body > 0.99, "Snapshot alpha not preserved: \(corner) \(edge) \(body)")
            }),
            ("The footer toggle maps stored rows to PNG/JPG and JPG is always 0.75", {
                try expect(FormatToggle.titles == ["PNG", "JPG"] && FormatToggle.jpgQuality == 0.75, "Toggle constants")
                try expect(FormatToggle.segment(forStoredChoice: 0) == 0 && (1...5).allSatisfy { FormatToggle.segment(forStoredChoice: $0) == 1 }
                           && [6, 7, 11, -1, 40].allSatisfy { FormatToggle.segment(forStoredChoice: $0) == 0 }, "Stored row mapping")
                try expect(FormatToggle.storedChoice(forSegment: 1, current: 0) == 2 && FormatToggle.storedChoice(forSegment: 1, current: 4) == 4
                           && FormatToggle.storedChoice(forSegment: 0, current: 4) == 0, "Stored row writing")
                let jpg = FormatToggle.payload(forSegment: 1), png = FormatToggle.payload(forSegment: 0)
                try expect(jpg.format == "jpeg" && jpg.quality == 0.75 && png.format == "png", "Payload parameters")
            }),
            ("JPEG quality controls detailed-gradient bytes and defaults to 0.7", {
                let document = try gradient()
                let low = try bytes(document, document.size, "jpeg", quality: 0.1)
                let high = try bytes(document, document.size, "jpeg", quality: 1)
                try expect(low != high && high.count > low.count * 2, "JPEG quality did not materially change encoded bytes")
                let defaultData = try required(ImageExport.encode(document: document, size: document.size, format: "jpeg"),
                                               "Default JPEG")
                try expect(try defaultData == bytes(document, document.size, "jpeg", quality: 0.7), "Default quality is not 0.7")
                _ = try bytes(document, document.size, "jpeg", quality: 0.6) // DragMe supplies its own default.
                let source = try decoded(high)
                try expect(source.width == 256 && source.height == 192, "Gradient image dimensions")
            }),
            ("Format case, extension and MIME/UTType aliases normalize", {
                let groups = [["png", " PNG ", ".PnG", "image/png", "public.png"],
                              ["jpeg", "JPG", ".jPe", "image/jpeg", "public.jpeg"],
                              ["tiff", "TiF", "image/tiff", "public.tiff"],
                              ["gif", ".GIF", "image/gif", "com.compuserve.gif"],
                              ["bmp", ".BMP", "image/bmp", "image/x-ms-bmp", "com.microsoft.bmp"],
                              ["pdf", ".PDF", "application/pdf", "com.adobe.pdf"]]
                for group in groups {
                    for alias in group { _ = try bytes(fixture(), CGSize(width: 40, height: 30), alias) }
                }
                for unknown in ["", "svg", "webp", "pnggarbage"] {
                    try expect(ImageExport.encode(document: fixture(), size: CGSize(width: 40, height: 30),
                                                  format: unknown) == nil, "Unknown format accepted")
                }
            }),
            ("PDF has exact fractional page bounds and scaled vector artwork", {
                let size = CGSize(width: 160, height: 90)
                let document = try pdfDocument(bytes(fixture(), size, "pdf"))
                let page = try required(document.page(at: 1), "PDF page")
                try expect(document.numberOfPages == 1 && page.getBoxRect(.mediaBox) == CGRect(origin: .zero, size: size),
                           "PDF output page bounds")
                try assertScaledInk(rasterizedPDF(page, size: size))
                let fractional = CGSize(width: 41.25, height: 31.75)
                let smallPDF = try pdfDocument(bytes(fixture(), fractional, "pdf"))
                let smallPage = try required(smallPDF.page(at: 1), "Fractional PDF page")
                try expect(smallPage.getBoxRect(.mediaBox).size == fractional, "PDF page was rounded to pixels")
                let table = try required(CGPDFOperatorTableCreate(), "PDF operator table")
                for operation in ["m", "l", "c", "re"] {
                    CGPDFOperatorTableSetCallback(table, operation) { _, info in
                        info?.assumingMemoryBound(to: Int.self).pointee += 1
                    }
                }
                var paths = 0
                let stream = CGPDFContentStreamCreateWithPage(page)
                let scanned = withUnsafeMutablePointer(to: &paths) { pointer -> Bool in
                    let scanner = CGPDFScannerCreate(stream, table, pointer)
                    return CGPDFScannerScan(scanner)
                }
                try expect(scanned && paths >= 4, "PDF artwork was flattened instead of retaining vector paths")
            }),
            ("Invalid and oversized output sizes fail before rendering in all formats", {
                let invalid = [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: 0.5, height: 10),
                               CGSize(width: CGFloat.nan, height: 10), CGSize(width: 10, height: CGFloat.infinity),
                               CGSize(width: 16385, height: 1), CGSize(width: 6000, height: 6000),
                               CGSize(width: 8000.1, height: 4000)]
                for size in invalid {
                    try expect(ImageExport.image(document: fixture(), size: size) == nil, "Invalid size produced image")
                    for format in ["png", "jpeg", "tiff", "gif", "bmp", "pdf"] {
                        try expect(ImageExport.encode(document: fixture(), size: size, format: format) == nil,
                                   "\(format) accepted invalid output size")
                    }
                }
            }),
            ("Nonfinite and out-of-range JPEG quality is rejected for every encoding", {
                let invalid: [Double] = [.nan, .infinity, -.infinity, -1, 0, 0.099, 1.001]
                for quality in invalid {
                    for format in ["png", "jpeg", "tiff", "gif", "bmp", "pdf"] {
                        try expect(ImageExport.encode(document: fixture(), size: CGSize(width: 40, height: 30),
                                                      format: format, jpegQuality: quality) == nil,
                                   "\(format) accepted invalid quality \(quality)")
                    }
                }
            }),
            ("Unsafe document geometry, data and render preferences are rejected", {
                var document = fixture(); document.size.width = .nan
                try expectInvalidDocument(document)
                document = fixture(); document.elements[0].transform.tx = .infinity
                try expectInvalidDocument(document)
                document = fixture(); document.elements[1].pathCommands = [.move(to: CGPoint(x: CGFloat.nan, y: 0))]
                try expectInvalidDocument(document)
                document = fixture(); document.backgroundPNG = Data([0, 1, 2])
                try expectInvalidDocument(document)
                document = fixture(); document.version = 2
                try expectInvalidDocument(document)
                document = fixture(); document.renderSize = CGSize(width: 10, height: CGFloat.nan)
                try expectInvalidDocument(document)
            }),
            ("renderSize round-trips while old JSON falls back to canvas size", {
                let document = fixture(), encoded = try document.encoded()
                let restored = try SketchDocument.decode(encoded)
                try expect(restored == document && restored.outputSize == document.renderSize,
                           "renderSize preference not serialized")
                var object = try required(JSONSerialization.jsonObject(with: encoded) as? [String: Any], "JSON object")
                object.removeValue(forKey: "renderSize")
                let old = try SketchDocument.decode(JSONSerialization.data(withJSONObject: object))
                try expect(old.renderSize == nil && old.outputSize == old.size && old.elements == document.elements,
                           "Old JSON did not decode with absent renderSize")
                object["renderSize"] = NSNull()
                let null = try SketchDocument.decode(JSONSerialization.data(withJSONObject: object))
                try expect(null.renderSize == nil && null.outputSize == null.size, "Null optional renderSize failed")
            }),
            ("Invalid serialized renderSize is rejected without changing schema version", {
                let original = fixture()
                let data = try original.encoded()
                var object = try required(JSONSerialization.jsonObject(with: data) as? [String: Any], "JSON object")
                for size in [[0, 10], [-1, 10], [16385, 1], [6000, 6000]] {
                    object["renderSize"] = size
                    var rejected = false
                    do { _ = try SketchDocument.decode(JSONSerialization.data(withJSONObject: object)) } catch { rejected = true }
                    try expect(rejected, "Invalid serialized renderSize accepted")
                }
                try expect(original.version == 1, "Optional preference changed document version")
            }),
            ("Current graphics state survives raster and PDF export", {
                let bitmap = try required(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Context bitmap")
                let context = try required(NSGraphicsContext(bitmapImageRep: bitmap), "Caller context")
                NSGraphicsContext.saveGraphicsState()
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current = context
                context.cgContext.translateBy(x: 3, y: 4)
                let transform = context.cgContext.ctm
                for format in ["png", "jpeg", "tiff", "gif", "bmp", "pdf"] {
                    _ = try bytes(fixture(), CGSize(width: 40, height: 30), format)
                    try expect(NSGraphicsContext.current === context && context.cgContext.ctm == transform,
                               "\(format) leaked graphics context or transform")
                }
            })
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("ImageExportTests: \(cases.count - failures)/\(cases.count) passed; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
#endif
