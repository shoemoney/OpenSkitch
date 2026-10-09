import Foundation

/// Small per-document preferences saved with the drawing so reopening it restores the pen.
struct DrawingDefaults: Codable, Equatable {
    var values: [String: String] = [:]
    init(values: [String: String] = [:]) { self.values = values }
}

enum OpenSnapFileError: Error, LocalizedError {
    case tooLarge, invalid(String)
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This OpenSnap document is larger than the supported limit."
        case .invalid(let reason): return "This is not a valid OpenSnap document: \(reason)"
        }
    }
}

/// The native editable .opensnap document: the canvas JSON (versioned SketchDocument with embedded PNGs,
/// plus the hidden pan source when the image was panned) and the pen defaults, in one JSON object.
/// Nothing else is accepted: no other document type is opened, saved or dropped.
struct OpenSnapFile {
    static let fileExtension = SketchDocument.fileExtension
    static let typeIdentifier = "com.shoemoney.opensnap.document"
    static let maximumFileBytes = 64 * 1024 * 1024
    var document: SketchDocument
    var drawingDefaults: DrawingDefaults
    var rawCanvasData: Data?

    init(document: SketchDocument, drawingDefaults: DrawingDefaults = .init(), canvasData: Data? = nil) {
        self.document = document; self.drawingDefaults = drawingDefaults; self.rawCanvasData = canvasData
    }

    /// Exact canvas JSON bytes, including recoverable pixels outside the viewport.
    var canvasData: Data {
        get throws {
            if let rawCanvasData {
                guard try CanvasView.validatedDocumentData(rawCanvasData) == document else {
                    throw OpenSnapFileError.invalid("canvas snapshot disagrees with the editing document")
                }
                return rawCanvasData
            }
            return try document.encoded()
        }
    }

    static func read(_ url: URL) throws -> Self {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard size?.intValue ?? 0 <= maximumFileBytes else { throw OpenSnapFileError.tooLarge }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    private struct Defaults: Decodable { var drawingDefaults: DrawingDefaults? }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileBytes else { throw OpenSnapFileError.tooLarge }
        guard data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 else { throw SketchDocumentError.unsupportedFormat }
        let document = try CanvasView.validatedDocumentData(data)
        let defaults = (try? JSONDecoder().decode(Defaults.self, from: data))?.drawingDefaults ?? .init()
        return Self(document: document, drawingDefaults: defaults, canvasData: try stripDefaults(from: data))
    }

    /// Canvas bytes without the defaults entry, so re-saving never duplicates it. Files this app wrote carry the
    /// entry as the last member, which is removed byte for byte; anything else is re-serialized.
    private static func stripDefaults(from data: Data) throws -> Data {
        guard (try? JSONDecoder().decode(Defaults.self, from: data))?.drawingDefaults != nil else { return data }
        let key = Data(",\"drawingDefaults\":".utf8)
        var end = data.count
        while end > 0, [9, 10, 13, 32].contains(data[end - 1]) { end -= 1 }
        if let range = data.range(of: key, options: .backwards), end > 0, data[end - 1] == 125 {
            let candidate = data[data.startIndex..<range.lowerBound] + Data([125])
            if (try? JSONDecoder().decode(Defaults.self, from: candidate))?.drawingDefaults == nil,
               (try? CanvasView.validatedDocumentData(Data(candidate))) != nil { return Data(candidate) }
        }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SketchDocumentError.invalidDocument }
        object.removeValue(forKey: "drawingDefaults")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func encoded() throws -> Data {
        _ = try document.validated()
        guard Set(document.elements.map(\.id)).count == document.elements.count else { throw OpenSnapFileError.invalid("duplicate element IDs") }
        var canvas = try canvasData
        if !drawingDefaults.values.isEmpty {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let defaults = try encoder.encode(drawingDefaults)
            while let last = canvas.last, [9, 10, 13, 32].contains(last) { canvas.removeLast() }
            guard canvas.last == 125 else { throw SketchDocumentError.invalidDocument }
            canvas.removeLast()
            canvas.append(Data(",\"drawingDefaults\":".utf8)); canvas.append(defaults); canvas.append(125)
        }
        guard canvas.count <= Self.maximumFileBytes else { throw OpenSnapFileError.tooLarge }
        return canvas
    }

    /// Atomic local save.
    func write(to url: URL) throws { try encoded().write(to: url, options: .atomic) }
}
