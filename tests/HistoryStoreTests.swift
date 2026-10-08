// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D HISTORY_STORE_TESTS \
//   Sources/{LegacySkitch,LegacyBridge,DocumentModel,VectorGeometry,StrokeFitting,ImageExport,Canvas,SVGExport,SkitchFile,LegacyHistoryImporter,HistoryStore}.swift \
//   tests/HistoryStoreTests.swift -o /tmp/skitch-history-store-tests
// /tmp/skitch-history-store-tests
#if HISTORY_STORE_TESTS
import AppKit

@main
enum HistoryStoreTests {
    struct Failure: Error { let message: String }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; count += 1
    }
    static func rejects(_ block: () throws -> Void, _ message: String) throws {
        do { try block() } catch { count += 1; return }; throw Failure(message: message)
    }
    @MainActor static func snapshot(_ title: String = "café revised") throws -> HistoryStore.Snapshot {
        let view = CanvasView(frame: .zero); view.newBlank(size: CGSize(width: 160, height: 100))
        var text = SketchElement(kind: .text); text.text = title; text.rect = CGRect(x: 10, y: 10, width: 130, height: 50)
        view.document.elements.append(text)
        var metadata = LegacyBridge.Metadata(); metadata.root["skitchCustom"] = "preserved"
        return try HistoryStore.Snapshot(canvasData: view.snapshotDocumentData(), metadata: metadata, preview: view.imageData(format: "png"))
    }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SkitchHistoryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("History"), store = try HistoryStore(directory: directory)
        let first = try snapshot(), date = Date(timeIntervalSince1970: 1_791_000_000)
        let emptyView = CanvasView(frame: .zero)
        try expect(try HistoryStore.Snapshot(canvasData: emptyView.snapshotDocumentData(), metadata: .init(), preview: nil).isEmpty, "Default blank is empty")
        emptyView.setBackgroundColor(.blue)
        try expect(try !HistoryStore.Snapshot(canvasData: emptyView.snapshotDocumentData(), metadata: .init(), preview: nil).isEmpty, "Solid-color drawing is meaningful artwork")
        let link = URL(string: "https://example.invalid/imgs/proof.png")!
        let id = try store.archive(first, name: "Proof", action: .shared, destination: "SFTP", remoteURL: link, remoteBinding: ["destination": "fixture"], date: date)
        try expect(store.entries.count == 1, "Archive creates one item")
        try expect(try store.read(id).metadata.root["skitchCustom"] == "preserved", "Unknown original metadata survives archive")
        try expect(try store.read(id).document.elements.first?.text == "café revised", "Editable text survives archive")
        try expect(store.entries.first?.text == "café revised", "Search text comes from actual drawing")
        try expect(store.entries.first?.action.title == "Shared", "Original action category is retained")
        let native = directory.appendingPathComponent(store.entries[0].nativeFile)
        let revised = try snapshot("latest edit")
        try store.follow(id, snapshot: revised, name: "Renamed", date: date.addingTimeInterval(60))
        try expect(store.entries.count == 1 && store.entries.first?.id == id, "Follow updates one identity without duplicates")
        try expect(store.entries[0].date == date && store.entries[0].updated == date.addingTimeInterval(60), "Follow keeps action date and records update separately")
        try expect(store.entries[0].remoteURL == link && store.entries[0].remoteBinding == ["destination": "fixture"], "Follow preserves publishing destination")
        try expect(!FileManager.default.fileExists(atPath: native.path), "Successful follow collects only superseded owned revision")
        try expect(try store.read(id).document.elements.first?.text == "latest edit", "Latest revision is editable")
        let stable = store.entries[0], stableBytes = try Data(contentsOf: directory.appendingPathComponent(stable.nativeFile))
        let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        store.writeIndex = { _, _ in throw Failure(message: "Disk full") }
        try rejects({ try store.follow(id, snapshot: first, name: "Lost") }, "Failed follow must fail")
        try expect(store.entries[0] == stable, "Failed follow preserves in-memory record")
        try expect(try Data(contentsOf: directory.appendingPathComponent(stable.nativeFile)) == stableBytes, "Failed follow preserves committed drawing bytes")
        try expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(beforeFiles), "Failed follow cleans only its uncommitted files")
        try rejects({ _ = try store.archive(first, name: "Failed", action: .archived) }, "Failed archive must fail")
        try expect(try HistoryStore(directory: directory).entries == [stable], "Failed writes survive fresh process reload")
        store.writeIndex = { try $0.write(to: $1, options: .atomic) }
        try store.follow(id, snapshot: revised, name: "Renamed")
        try expect(store.entries[0] == stable, "Unchanged follow preserves revision and update date")
        let exportID = try store.archive(first, name: "Export", action: .exported, destination: "/user/original.png", date: date.addingTimeInterval(100))
        try expect(store.entries[0].id == exportID && store.entries[0].action.title == "Exported/Dragged", "Newest action first and original exported category")
        let exportFile = directory.appendingPathComponent(store.entries[0].nativeFile)
        try store.remove([exportID], deleteFiles: false)
        try expect(FileManager.default.fileExists(atPath: exportFile.path), "Remove is list-only")
        try expect(try HistoryStore(directory: directory).entries.count == 1, "Removed copies are not reimported")
        try store.clearRemote(id)
        try expect(store.entry(id)?.remoteURL == nil && store.entry(id)?.remoteBinding == nil, "Remote deletion metadata can be cleared without deleting local archive")
        let currentFile = directory.appendingPathComponent(store.entry(id)!.nativeFile)
        try Data("tampered".utf8).write(to: currentFile, options: .atomic)
        try expect(store.missing(id), "Tampered snapshots are flagged, not silently opened")
        try rejects({ try store.follow(id, snapshot: first, name: "Overwrite") }, "Follow cannot overwrite a missing or externally changed archive")
        try expect(try Data(contentsOf: currentFile) == Data("tampered".utf8), "Externally modified file is preserved")
        try store.remove([id], deleteFiles: true)
        try expect(!FileManager.default.fileExists(atPath: currentFile.path), "Explicit Delete Files deletes local copy")
        let legacyDir = root.appendingPathComponent("Loose"), legacyURL = legacyDir.appendingPathComponent("1791000000-old-proof.skitch")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try first.native.write(to: legacyURL)
        let legacyStore = try HistoryStore(directory: legacyDir)
        try expect(legacyStore.entries.count == 1 && legacyStore.entries[0].imported, "Loose native archive migrates without moving original")
        try expect(legacyStore.entries[0].date == date, "Old epoch name is retained as action date")
        try expect(try HistoryStore(directory: legacyDir).entries.count == 1, "Migration is idempotent")
        let legacyID = legacyStore.entries[0].id
        try legacyStore.follow(legacyID, snapshot: revised, name: "Updated import")
        try expect(FileManager.default.fileExists(atPath: legacyURL.path), "Following migrated archive preserves original imported file")
        try expect(try HistoryStore(directory: legacyDir).entries.count == 1, "Preserved original does not get duplicated on reload")
        let trashDirectory = root.appendingPathComponent("FakeTrash")
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let trashMove: (URL) throws -> URL = { url in
            let target = trashDirectory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target); return target
        }
        let revision = legacyStore.entries[0], revisionURL = legacyDir.appendingPathComponent(revision.nativeFile)
        legacyStore.writeIndex = { _, _ in throw Failure(message: "Disk full after Trash moves") }
        try rejects({ try legacyStore.trash([legacyID], move: trashMove) }, "Trash commit failure must report failure")
        try expect(legacyStore.entry(legacyID) == revision && FileManager.default.fileExists(atPath: revisionURL.path), "Failed Trash commit restores file and index")
        try expect(try FileManager.default.contentsOfDirectory(atPath: trashDirectory.path).isEmpty, "Failed Trash transaction leaves no staged items")
        legacyStore.writeIndex = { try $0.write(to: $1, options: .atomic) }
        try rejects({ try legacyStore.trash([legacyID], move: { _ in throw Failure(message: "Trash unavailable") }) }, "Trash move failure must report failure")
        try expect(legacyStore.entry(legacyID) == revision, "Trash move failure retains entry")
        try legacyStore.trash([legacyID], move: trashMove)
        try expect(legacyStore.entry(legacyID) == nil && !FileManager.default.fileExists(atPath: revisionURL.path), "Successful Trash transaction removes only owned revision")
        try expect(FileManager.default.fileExists(atPath: legacyURL.path), "Trashing follow revision does not destroy original legacy source")
        let outside = root.appendingPathComponent("outside.skitch"); try first.native.write(to: outside)
        let symlink = legacyDir.appendingPathComponent("escape.skitch")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        try expect(try HistoryStore(directory: legacyDir).entries.isEmpty, "Symlink escape is never imported")
        let indexURL = directory.appendingPathComponent("index.json"), before = try Data(contentsOf: indexURL)
        try Data("corrupt index".utf8).write(to: indexURL, options: .atomic)
        try rejects({ _ = try HistoryStore(directory: directory) }, "Corrupt index fails closed")
        try expect(try Data(contentsOf: indexURL) == Data("corrupt index".utf8), "Corrupt index is not replaced")
        try before.write(to: indexURL, options: .atomic)
        var object = try JSONSerialization.jsonObject(with: before) as! [String: Any]
        object["version"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: indexURL)
        try rejects({ _ = try HistoryStore(directory: directory) }, "Newer version fails closed")
        let oldPictures = root.appendingPathComponent("OldPictures"), importedDirectory = root.appendingPathComponent("Imported")
        try FileManager.default.createDirectory(at: oldPictures, withIntermediateDirectories: true)
        let oldPicture = oldPictures.appendingPathComponent("original.skitch"); try first.native.write(to: oldPicture)
        let imported = try HistoryStore(directory: importedDirectory)
        let uid: (Int) -> [String: Int] = { ["CF$UID": $0] }
        let objects: [Any] = ["$null", ["$class": uid(4), "NS.objects": [uid(2)]],
            ["$class": uid(5), "mInfo": uid(3)],
            ["$class": uid(6), "NS.keys": ["localPath", "local", "saved", "remoteURL", "textContent", "accountID"],
             "NS.objects": ["/untrusted/outside/original.skitch", false, false, "https://example.invalid/imgs/original.png", "Original indexed words", "old-account"]],
            ["$classname": "NSArray", "$classes": ["NSArray", "NSObject"]],
            ["$classname": "HistoryObject", "$classes": ["HistoryObject", "NSObject"]],
            ["$classname": "NSDictionary", "$classes": ["NSDictionary", "NSObject"]]]
        let plist: [String: Any] = ["$archiver": "NSKeyedArchiver", "$version": 100000, "$top": ["root": uid(1)], "$objects": objects]
        let legacyData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let report = try imported.importLegacy(indexData: legacyData, archiveDirectory: oldPictures)
        try expect(report.imported == 1 && report.skipped == 0, "Synthetic keyed archive imports one native copy")
        let importedEntry = imported.entries[0]
        try expect(importedEntry.action == .shared && importedEntry.remoteURL?.absoluteString == "https://example.invalid/imgs/original.png" && importedEntry.remoteBinding == nil,
                   "Legacy shared URL preserved without granting unproven remote-deletion binding")
        try expect(importedEntry.text == "Original indexed words" && importedEntry.legacyAccountID == "old-account", "Legacy search snapshot and account identifier retained")
        try expect(try imported.read(importedEntry.id).nativeCanvasDataMatches(first), "Legacy copied drawing retains editable raw state and metadata")
        try expect(try Data(contentsOf: oldPicture) == first.native, "Original legacy picture remains untouched")
        try expect(try imported.importLegacy(indexData: legacyData, archiveDirectory: oldPictures).imported == 0, "Legacy import is idempotent")
        try imported.remove([importedEntry.id], deleteFiles: false)
        try expect(try HistoryStore(directory: importedDirectory).importLegacy(indexData: legacyData, archiveDirectory: oldPictures).imported == 0, "Hidden imported record is not resurrected")
        let failingImport = try HistoryStore(directory: root.appendingPathComponent("FailedImport"))
        failingImport.writeIndex = { _, _ in throw Failure(message: "Import index unavailable") }
        try rejects({ _ = try failingImport.importLegacy(indexData: legacyData, archiveDirectory: oldPictures) }, "Failed import commit reports failure")
        try expect(failingImport.entries.isEmpty && FileManager.default.fileExists(atPath: oldPicture.path), "Failed import leaves source and index intact")
        let sharedDir = root.appendingPathComponent("SharedPreview")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        try first.native.write(to: sharedDir.appendingPathComponent("same.skitch"))
        try first.native.write(to: sharedDir.appendingPathComponent("same.skitchredux"))
        try first.preview!.write(to: sharedDir.appendingPathComponent("same.png"))
        let sharedStore = try HistoryStore(directory: sharedDir)
        let left = sharedStore.entries.first { $0.nativeFile == "same.skitch" }!, right = sharedStore.entries.first { $0.nativeFile == "same.skitchredux" }!
        try sharedStore.trash([left.id], move: trashMove)
        try expect(FileManager.default.fileExists(atPath: sharedDir.appendingPathComponent("same.png").path) && !sharedStore.missing(right.id), "Trashing one migrated entry preserves another entry's shared preview and drawing")
        let recoveryStore = try HistoryStore(directory: root.appendingPathComponent("RollbackWarning"))
        let recoverID = try recoveryStore.archive(first, name: "recover", action: .archived)
        let recoverFile = recoveryStore.directory.appendingPathComponent(recoveryStore.entry(recoverID)!.nativeFile)
        recoveryStore.writeIndex = { _, _ in
            try FileManager.default.createDirectory(at: recoverFile, withIntermediateDirectories: false)
            throw Failure(message: "Index failed and original path was claimed")
        }
        do { try recoveryStore.trash([recoverID], move: trashMove); throw Failure(message: "Expected rollback warning") }
        catch {
            try expect(error.localizedDescription.contains("Recover these copies from Trash:") && error.localizedDescription.contains(trashDirectory.path), "Partial Trash rollback reports exact recovery location")
        }
        try expect(FileManager.default.fileExists(atPath: trashDirectory.appendingPathComponent(recoverFile.lastPathComponent).path), "Unrestorable copy remains recoverable in Trash")
        print("History store tests: \(count) passed")
    }
}
private extension SkitchFile {
    func nativeCanvasDataMatches(_ snapshot: HistoryStore.Snapshot) throws -> Bool {
        let expected = try SkitchFile.decode(snapshot.native)
        return try canvasData == expected.canvasData && metadata == expected.metadata
    }
}
#endif
