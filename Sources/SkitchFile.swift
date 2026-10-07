import Foundation
import CryptoKit
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Transferable SVG-native .skitch plus optional exact Redux editing state.
/// The SVG remains visible/editable without the supplement. The original i386
/// engine reads cubic outlines, text metadata and the first backdrop, but cannot
/// retain Redux tool kinds/UUIDs, arbitrary text matrices or multiple images.
struct SkitchFile {
    static let fileExtension = "skitch"
    static let supplementalNamespace = "urn:skitch-redux:editable-document:1"
    var document: SketchDocument
    var metadata: LegacyBridge.Metadata
    var rawCanvasData: Data?

    init(document: SketchDocument, metadata: LegacyBridge.Metadata = .init(), canvasData: Data? = nil) {
        self.document = document; self.metadata = metadata; self.rawCanvasData = canvasData
    }

    /// Exact CanvasFile bytes, including recoverable pixels outside the viewport.
    var canvasData: Data {
        get throws {
            if let rawCanvasData { _ = try validatedBackdrop(); return rawCanvasData }
            return try document.encoded()
        }
    }

    /// Retain this value while editing; replace .document from Canvas before saving.
    static func read(_ url: URL) throws -> Self {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard size?.intValue ?? 0 <= LegacySkitch.maximumFileBytes else { throw LegacySkitchError.limitExceeded }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Also accepts existing .skitchredux JSON. Malformed supplements and conflicting
    /// SVG/state are errors, never a reason to silently prefer hidden model data.
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= LegacySkitch.maximumFileBytes else { throw LegacySkitchError.limitExceeded }
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 {
            return Self(document: try CanvasView.validatedDocumentData(data), canvasData: data)
        }
        let original = try LegacySkitch.decode(data)
        guard let encoded = original.attributes["redux:state"] else {
            guard original.attributes["xmlns:redux"] == nil else { throw LegacySkitchError.invalidDocument("Missing Redux state") }
            let converted = try LegacyBridge.convertWithMetadata(original)
            return Self(document: converted.document, metadata: converted.metadata)
        }
        guard original.attributes["xmlns:redux"] == supplementalNamespace,
              let bytes = Data(base64Encoded: encoded) else { throw LegacySkitchError.invalidDocument("Invalid Redux state encoding/namespace") }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: bytes) }
        catch { throw LegacySkitchError.invalidDocument("Malformed Redux editing state") }
        guard envelope.format == supplementalNamespace, envelope.version == 1 else {
            throw SketchDocumentError.unsupportedVersion
        }
        let document = try envelope.document.validated()
        let actual = try fingerprint(data)
        guard actual == envelope.svgFingerprint else {
            throw LegacySkitchError.invalidDocument("Visible SVG changed independently of Redux state; remove both Redux attributes to import the SVG edits")
        }
        let file = Self(document: document, metadata: envelope.metadata, canvasData: envelope.rawCanvasData)
        let regenerated = try SVGExport.encode(document, preserving: envelope.metadata, backdrop: file.validatedBackdrop())
        guard try fingerprint(regenerated) == actual else {
            throw LegacySkitchError.invalidDocument("Redux state disagrees with the visible SVG")
        }
        return file
    }

    func encoded(includeSupplementalState: Bool = true) throws -> Data {
        _ = try document.validated()
        guard Set(document.elements.map(\.id)).count == document.elements.count else {
            throw LegacySkitchError.invalidDocument("Duplicate element IDs")
        }
        let svg = try SVGExport.encode(document, preserving: metadata, backdrop: validatedBackdrop())
        // Validate the real, supplemental-free SVG before appending editing state.
        _ = try LegacySkitch.decode(svg)
        if !includeSupplementalState { return svg }
        let envelope = Envelope(format: Self.supplementalNamespace, version: 1,
            document: document, metadata: metadata, rawCanvasData: rawCanvasData, svgFingerprint: try Self.fingerprint(svg))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let state = try encoder.encode(envelope).base64EncodedString()
        let text = String(decoding: svg, as: UTF8.self).replacingOccurrences(of: "<svg ",
            with: "<svg xmlns:redux=\"\(Self.supplementalNamespace)\" redux:state=\"\(state)\" ")
        let data = Data(text.utf8)
        guard data.count <= LegacySkitch.maximumFileBytes else { throw LegacySkitchError.limitExceeded }
        return data
    }

    /// Atomic local save. The explicit old extension retains JSON compatibility.
    func write(to url: URL) throws {
        let data = url.pathExtension.lowercased() == SketchDocument.fileExtension ? try canvasData : try encoded()
        try data.write(to: url, options: .atomic)
    }

    /// These are limitations of the recovered original engine, not save failures.
    var originalCompatibilityWarnings: [String] {
        var warnings: [String] = []
        if document.elements.filter({ $0.kind == .raster }).count + (document.backgroundPNG == nil ? 0 : 1) > 1 {
            warnings.append("Original Skitch reads only the first image as its backdrop; separate raster layers remain editable in Redux and visible in ordinary SVG.")
        }
        if document.elements.contains(where: { $0.kind == .text && $0.transform != .identity }) {
            warnings.append("Original Skitch ignores SVG text matrices; Redux and ordinary SVG retain them.")
        }
        return warnings
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var document: SketchDocument
        var metadata: LegacyBridge.Metadata
        var rawCanvasData: Data?
        var svgFingerprint: String
    }

    private struct CanvasExtra: Decodable {
        var canvasPanBackground: PanSource?
    }
    private struct PanSource: Decodable {
        var sourcePNG: Data
        var sourceSize: CGSize
        var offset: CGPoint
    }
    private func validatedBackdrop() throws -> SVGExport.Backdrop? {
        guard let rawCanvasData else { return nil }
        guard rawCanvasData.count <= LegacySkitch.maximumFileBytes,
              try CanvasView.validatedDocumentData(rawCanvasData) == document else {
            throw LegacySkitchError.invalidDocument("Canvas snapshot disagrees with the editing document")
        }
        let extra = try JSONDecoder().decode(CanvasExtra.self, from: rawCanvasData)
        guard let source = extra.canvasPanBackground else { return nil }
        return SVGExport.Backdrop(pngData: source.sourcePNG, rect: CGRect(origin: source.offset, size: source.sourceSize))
    }

    /// Attribute order, indentation, CDATA and XML entity spelling do not matter.
    /// Every painted node/attribute/text value does. This is consistency checking,
    /// not authentication or proof of original-runtime interoperability.
    private static func fingerprint(_ data: Data) throws -> String {
        let reader = FingerprintReader(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), let root = reader.root else { throw LegacySkitchError.invalidXML("Cannot fingerprint SVG") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(root)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private final class FingerprintNode: Encodable {
        var name: String
        var attributes: [String: String]
        var children: [FingerprintNode] = []
        var text = ""
        init(_ name: String, _ attributes: [String: String]) {
            self.name = name; self.attributes = attributes
            if name == "svg" { self.attributes.removeValue(forKey: "redux:state"); self.attributes.removeValue(forKey: "xmlns:redux") }
        }
    }
    private final class FingerprintReader: NSObject, XMLParserDelegate {
        var root: FingerprintNode?
        var stack: [FingerprintNode] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            let node = FingerprintNode(name, attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if stack.last?.name == "text" { stack.last?.text += string } }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { if stack.last?.name == "text" { stack.last?.text += String(decoding: data, as: UTF8.self) } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    }
}
