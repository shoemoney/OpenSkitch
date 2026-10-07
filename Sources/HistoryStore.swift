import AppKit
import CryptoKit

/// History owns copies, never the user's exported originals. Each index commit
/// points at complete immutable revisions, so a failed update leaves the prior
/// drawing readable. The JSON index contains no publishing credentials.
final class HistoryStore {
    enum Action: String, Codable { case archived, exported, shared
        var title: String { switch self { case .archived: return "Saved"; case .exported: return "Exported/Dragged"; case .shared: return "Shared" } }
    }
    struct Snapshot {
        let native: Data
        let preview: Data?
        let size: CGSize
        let text: String
        let isEmpty: Bool
        init(canvasData: Data, metadata: LegacyBridge.Metadata, preview: Data?) throws {
            let document = try CanvasView.validatedDocumentData(canvasData)
            native = try SkitchFile(document: document, metadata: metadata, canvasData: canvasData).encoded()
            self.preview = preview; size = document.size
            isEmpty = document.elements.isEmpty && document.backgroundPNG == nil &&
                (document.backgroundColor == .white || document.backgroundColor.alpha == 0)
            text = document.elements.filter { $0.kind == .text }.map(\.text).joined(separator: "\n")
        }
    }
    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var date: Date
        var updated: Date
        var size: CGSize
        var text: String
        var action: Action
        var destination: String?
        var remoteURL: URL?
        var remoteBinding: [String: String]?
        var nativeFile: String
        var previewFile: String?
        var digest: String?
        var imported = false
        var legacySource: String?
        var legacyRemotePath: String?
        var legacyAccountID: String?
    }
    private struct Index: Codable {
        var version = 1
        var entries: [Entry] = []
        var ignoredLooseFiles: Set<String> = []
        var ignoredLegacySources: Set<String>?
    }
    enum Failure: LocalizedError {
        case corruptIndex, missing, unsafePath, unsupportedVersion
        var errorDescription: String? {
            switch self {
            case .corruptIndex: return "The History index could not be read safely. Your archived drawings were preserved."
            case .missing: return "This History drawing is missing or has changed outside Skitch."
            case .unsafePath: return "History refused a file path outside its own archive."
            case .unsupportedVersion: return "This History was written by a newer version of Skitch Redux."
            }
        }
    }
    let directory: URL
    private var index: Index
    private var readability: [String: (modified: Date?, bytes: Int?, valid: Bool)] = [:]
    /// Injectable atomic index writer for failure recovery tests.
    var writeIndex: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    var entries: [Entry] { Array(index.entries.reversed()) }
    init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("index.json")
        if (try? indexURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw Failure.unsafePath }
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do { index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL)) }
            catch { throw Failure.corruptIndex }
            guard index.version == 1 else { throw Failure.unsupportedVersion }
            guard Set(index.entries.map(\.id)).count == index.entries.count else { throw Failure.corruptIndex }
            guard Set(index.entries.map(\.nativeFile)).count == index.entries.count else { throw Failure.corruptIndex }
            for entry in index.entries {
                guard Self.safeLeaf(entry.nativeFile), entry.previewFile.map(Self.safeLeaf) ?? true,
                      ["skitch", "skitchredux"].contains(URL(fileURLWithPath: entry.nativeFile).pathExtension.lowercased()),
                      entry.previewFile.map({ ["png", "jpg", "jpeg"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) ?? true,
                      SketchDocument.validSize(entry.size), entry.date.timeIntervalSince1970.isFinite,
                      entry.updated.timeIntervalSince1970.isFinite else { throw Failure.corruptIndex }
            }
        } else { index = Index() }
        try migrateLooseFiles()
    }
    private static func safeLeaf(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
    private func ownedURL(_ name: String) throws -> URL {
        guard Self.safeLeaf(name) else { throw Failure.unsafePath }
        let url = directory.appendingPathComponent(name)
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        // Existing symlink files cannot redirect archive reads/writes/deletion.
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path == root.path else { throw Failure.unsafePath }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw Failure.unsafePath }
        return url
    }
    private func commit(_ next: Index) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = try ownedURL("index.json")
        try writeIndex(encoder.encode(next), url)
        index = next
    }
    private func migrateLooseFiles() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])
        let known = Set(index.entries.map(\.nativeFile)).union(index.ignoredLooseFiles)
        var next = index
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard ["skitch", "skitchredux"].contains(url.pathExtension.lowercased()), !known.contains(url.lastPathComponent),
                  !url.lastPathComponent.hasPrefix("redux-"), (try? ownedURL(url.lastPathComponent)) != nil,
                  let file = try? SkitchFile.read(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let prefix = url.lastPathComponent.split(separator: "-").first.flatMap { TimeInterval($0) }
            let date = prefix.map(Date.init(timeIntervalSince1970:)) ?? values?.creationDate ?? values?.contentModificationDate ?? Date()
            let preview = url.deletingPathExtension().appendingPathExtension("png").lastPathComponent
            next.entries.append(Entry(id: UUID(), name: url.deletingPathExtension().lastPathComponent, date: date, updated: date,
                size: file.document.size, text: file.document.elements.filter { $0.kind == .text }.map(\.text).joined(separator: "\n"),
                action: .archived, nativeFile: url.lastPathComponent,
                previewFile: FileManager.default.fileExists(atPath: directory.appendingPathComponent(preview).path) ? preview : nil,
                imported: true))
        }
        if next.entries != index.entries { try commit(next) }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    struct ImportReport { var imported = 0; var skipped = 0 }
    /// Copy only .skitch drawings from the explicitly supplied legacy archive
    /// directory. Stored legacy paths never grant access to arbitrary files.
    /// Original index, pictures, and previews remain untouched.
    func importLegacy(indexData: Data, archiveDirectory: URL) throws -> ImportReport {
        let records = try LegacyHistoryImporter.decode(indexData)
        let root = archiveDirectory.resolvingSymlinksInPath().standardizedFileURL
        var report = ImportReport()
        let existing = Set(index.entries.compactMap(\.legacySource)).union(index.ignoredLegacySources ?? [])
        var seen = existing
        for record in records {
            let name = URL(fileURLWithPath: record.localPath).lastPathComponent
            guard Self.safeLeaf(name), URL(fileURLWithPath: name).pathExtension.lowercased() == "skitch" else { report.skipped += 1; continue }
            let source = root.appendingPathComponent(name)
            let key = Self.hash(Data((root.path + "/" + name).utf8))
            guard seen.insert(key).inserted else { continue }
            guard source.resolvingSymlinksInPath().deletingLastPathComponent().path == root.path,
                  (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let file = try? SkitchFile.read(source) else { report.skipped += 1; continue }
            let raw = try file.canvasData
            let view = CanvasView(frame: .zero); try view.loadDocument(data: raw)
            let snapshot = try Snapshot(canvasData: raw, metadata: file.metadata, preview: view.imageData(format: "png"))
            let action: Action = record.local ? (record.saved ? .archived : .exported) : .shared
            let url = record.remoteURL.flatMap(URL.init(string:))
            let date = record.date ?? (try? source.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let entry = Entry(id: UUID(), name: source.deletingPathExtension().lastPathComponent, date: date, updated: date,
                size: snapshot.size, text: record.text.isEmpty ? snapshot.text : record.text, action: action,
                destination: record.remoteURL ?? record.remotePath, remoteURL: action == .shared ? url : nil,
                nativeFile: "", digest: Self.hash(snapshot.native), legacySource: key,
                legacyRemotePath: record.remotePath, legacyAccountID: record.accountID)
            try writeRevision(snapshot, entry: entry, inserting: true); report.imported += 1
        }
        return report
    }
    @discardableResult
    func archive(_ snapshot: Snapshot, name: String, action: Action, destination: String? = nil,
                 remoteURL: URL? = nil, remoteBinding: [String: String]? = nil, date: Date = Date()) throws -> UUID {
        let id = UUID()
        let entry = Entry(id: id, name: name, date: date, updated: date, size: snapshot.size, text: snapshot.text,
                          action: action, destination: destination, remoteURL: remoteURL, remoteBinding: remoteBinding,
                          nativeFile: "", digest: Self.hash(snapshot.native))
        try writeRevision(snapshot, entry: entry, inserting: true)
        return id
    }
    func follow(_ id: UUID, snapshot: Snapshot, name: String, date: Date = Date()) throws {
        guard var entry = index.entries.first(where: { $0.id == id }) else { return }
        _ = try read(id)
        let digest = Self.hash(snapshot.native)
        guard entry.digest != digest || entry.name != name else { return }
        entry.name = name; entry.size = snapshot.size; entry.text = snapshot.text; entry.updated = date; entry.digest = digest
        try writeRevision(snapshot, entry: entry, inserting: false)
    }
    private func writeRevision(_ snapshot: Snapshot, entry original: Entry, inserting: Bool) throws {
        // Validate before touching any existing index or files.
        _ = try SkitchFile.decode(snapshot.native)
        var entry = original
        let stem = "redux-\(entry.id.uuidString)-\(UUID().uuidString)"
        entry.nativeFile = stem + ".skitch"; entry.previewFile = snapshot.preview == nil ? nil : stem + ".png"
        let nativeURL = try ownedURL(entry.nativeFile)
        let previewURL = try entry.previewFile.map(ownedURL)
        let old = index.entries.first { $0.id == entry.id }
        do {
            try snapshot.native.write(to: nativeURL, options: .atomic)
            if let previewURL, let data = snapshot.preview { try data.write(to: previewURL, options: .atomic) }
            var next = index
            if inserting { next.entries.append(entry) }
            else if let position = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[position] = entry }
            if let old, old.imported { next.ignoredLooseFiles.insert(old.nativeFile) }
            entry.imported = false
            if let position = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[position].imported = false }
            try commit(next)
        } catch {
            try? FileManager.default.removeItem(at: nativeURL)
            if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
            throw error
        }
        // Imported originals remain intact. Only a successful commit permits
        // collecting our own superseded revisions.
        if let old, !old.imported { try? cleanupFiles(old) }
    }
    func entry(_ id: UUID) -> Entry? { index.entries.first { $0.id == id } }
    func read(_ id: UUID) throws -> SkitchFile {
        guard let entry = entry(id) else { throw Failure.missing }
        let data: Data
        do { data = try Data(contentsOf: ownedURL(entry.nativeFile)) } catch { throw Failure.missing }
        if let digest = entry.digest, Self.hash(data) != digest { throw Failure.missing }
        return try SkitchFile.decode(data)
    }
    func missing(_ id: UUID) -> Bool {
        guard let entry = entry(id), let url = try? ownedURL(entry.nativeFile),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              FileManager.default.fileExists(atPath: url.path) else { return true }
        if let check = readability[entry.nativeFile], check.modified == values.contentModificationDate, check.bytes == values.fileSize { return !check.valid }
        let valid = (try? read(id)) != nil
        readability[entry.nativeFile] = (values.contentModificationDate, values.fileSize, valid)
        return !valid
    }
    func previewURL(_ entry: Entry) -> URL? { entry.previewFile.flatMap { try? ownedURL($0) } }
    func clearRemote(_ id: UUID) throws {
        var next = index
        if let position = next.entries.firstIndex(where: { $0.id == id }) {
            next.entries[position].remoteURL = nil; next.entries[position].remoteBinding = nil
            try commit(next)
        }
    }
    /// Remove is list-only; deleting archive files is a separate explicit action.
    func remove(_ ids: Set<UUID>, deleteFiles: Bool) throws {
        let removed = index.entries.filter { ids.contains($0.id) }
        var next = index; next.entries.removeAll { ids.contains($0.id) }
        next.ignoredLooseFiles.formUnion(removed.map(\.nativeFile))
        next.ignoredLegacySources = (next.ignoredLegacySources ?? []).union(removed.compactMap(\.legacySource))
        try commit(next)
        if deleteFiles { for entry in removed { try cleanupFiles(entry) } }
    }
    /// Original "From Computer" removal is recoverable in the system Trash.
    /// Stage each move and roll it back if another move or the index commit
    /// fails. The index never claims removal when a file could not be trashed.
    func trash(_ ids: Set<UUID>, move: (URL) throws -> URL = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw Failure.missing }; return result as URL
    }) throws {
        let removed = index.entries.filter { ids.contains($0.id) }
        let retainedPreviews = Set(index.entries.filter { !ids.contains($0.id) }.compactMap(\.previewFile))
        var moved: [(original: URL, trashed: URL)] = []
        var visited: Set<String> = []
        do {
            for entry in removed {
                for name in [entry.nativeFile, entry.previewFile].compactMap({ $0 }) {
                    guard !retainedPreviews.contains(name), visited.insert(name).inserted else { continue }
                    let original = try ownedURL(name)
                    if FileManager.default.fileExists(atPath: original.path) { moved.append((original, try move(original))) }
                }
            }
            var next = index; next.entries.removeAll { ids.contains($0.id) }
            next.ignoredLooseFiles.formUnion(removed.map(\.nativeFile))
            next.ignoredLegacySources = (next.ignoredLegacySources ?? []).union(removed.compactMap(\.legacySource))
            try commit(next)
        } catch {
            var unrecovered: [String] = []
            for item in moved.reversed() {
                do { try FileManager.default.moveItem(at: item.trashed, to: item.original) }
                catch { unrecovered.append(item.trashed.path) }
            }
            if !unrecovered.isEmpty {
                throw NSError(domain: "SkitchHistory", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "History removal failed and some files could not be restored. The index was kept. Recover these copies from Trash: " + unrecovered.joined(separator: ", ")])
            }
            throw error
        }
    }
    private func cleanupFiles(_ entry: Entry) throws {
        for name in [entry.nativeFile, entry.previewFile].compactMap({ $0 }) {
            guard !index.entries.contains(where: { $0.nativeFile == name || $0.previewFile == name }) else { continue }
            let url = try ownedURL(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
