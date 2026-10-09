import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The Modern footer's [PNG | JPG] toggle. The stored preference is the popup row index under
/// "DragFormatChoice" (0 = PNG, 1...5 = the JPEG quality rows, 6+ = other formats); the toggle maps it onto two segments.
enum FormatToggle {
    static let defaultsKey = "DragFormatChoice"
    static let titles = ["PNG", "JPG"]
    static let jpgQuality = 0.75
    static let jpgStoredChoice = 2
    static let toolTip = "Format for drag, export and upload"
    /// Anything that is not a stored JPEG row (absent, PNG, TIFF, ...) shows as PNG.
    static func segment(forStoredChoice choice: Int) -> Int { (1...5).contains(choice) ? 1 : 0 }
    /// Keeps a finer stored JPEG row when the segment is already JPG, so the shared preference is not needlessly rewritten.
    static func storedChoice(forSegment segment: Int, current: Int) -> Int {
        segment == 1 ? ((1...5).contains(current) ? current : jpgStoredChoice) : 0
    }
    static func payload(forSegment segment: Int) -> (format: String, quality: Double) {
        segment == 1 ? ("jpeg", jpgQuality) : ("png", 1.0)
    }
}

/// Output dimensions are independent of editable canvas and element geometry.
enum ImageExport {
    static func encode(document: SketchDocument, size: CGSize, format: String,
                       jpegQuality: Double = 0.7) -> Data? {
        guard jpegQuality.isFinite, (0.1...1).contains(jpegQuality),
              SketchDocument.validSize(size), (try? document.validated()) != nil else { return nil }
        let normalized = format.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let type: NSBitmapImageRep.FileType
        switch normalized {
        case "pdf", "application/pdf", "com.adobe.pdf":
            return pdf(document: document, size: size)
        case "png", "image/png", "public.png": type = .png
        case "jpeg", "jpg", "jpe", "image/jpeg", "public.jpeg": type = .jpeg
        case "tiff", "tif", "image/tiff", "public.tiff": type = .tiff
        case "gif", "image/gif", "com.compuserve.gif": type = .gif
        case "bmp", "image/bmp", "image/x-bmp", "image/x-ms-bmp", "com.microsoft.bmp": type = .bmp
        default: return nil
        }
        guard let bitmap = bitmap(document: document, size: size,
                                  opaque: type == .jpeg || type == .bmp) else { return nil }
        if type == .gif {
            guard let cgImage = bitmap.cgImage else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString,
                                                                     1, nil) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, nil)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg
            ? [.compressionFactor: jpegQuality] : [:]
        return bitmap.representation(using: type, properties: properties)
    }

    static func image(document: SketchDocument, size: CGSize) -> NSImage? {
        guard SketchDocument.validSize(size), (try? document.validated()) != nil,
              let bitmap = bitmap(document: document, size: size, opaque: false) else { return nil }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func bitmap(document: SketchDocument, size: CGSize, opaque: Bool) -> NSBitmapImageRep? {
        SketchRenderer.bitmap(size: size) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.scaleBy(x: size.width / document.size.width, y: size.height / document.size.height)
            SketchRenderer.draw(document)
            context.restoreGState()
            if opaque {
                // The renderer's background fill can replace prior pixels. Composite
                // white behind the completed artwork, including fractional edge pixels.
                context.setBlendMode(.destinationOver)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height)))
            }
        }
    }

    private static func pdf(document: SketchDocument, size: CGSize) -> Data? {
        let data = NSMutableData()
        var bounds = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { return nil }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: size.width / document.size.width, y: -size.height / document.size.height)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        SketchRenderer.draw(document)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
