// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D HISTORY_STORE_TESTS \
//   Sources/{SVGPath,DocumentModel,VectorGeometry,StrokeFitting,ImageExport,Canvas,OpenSnapFile,HistoryStore}.swift \
//   tests/HistoryStoreTests.swift -o /tmp/opensnap-history-store-tests
// /tmp/opensnap-history-store-tests
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
        var metadata = DrawingDefaults(); metadata.values["customColor"] = "preserved"
        return try HistoryStore.Snapshot(canvasData: view.snapshotDocumentData(), drawingDefaults: metadata, preview: view.imageData(format: "png"))
    }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("OpenSnapHistoryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("History"), store = try HistoryStore(directory: directory)
        let first = try snapshot(), date = Date(timeIntervalSince1970: 1_791_000_000)
        let emptyView = CanvasView(frame: .zero)
        try expect(try HistoryStore.Snapshot(canvasData: emptyView.snapshotDocumentData(), drawingDefaults: .init(), preview: nil).isEmpty, "Default blank is empty")
        emptyView.setBackgroundColor(.blue)
        try expect(try !HistoryStore.Snapshot(canvasData: emptyView.snapshotDocumentData(), drawingDefaults: .init(), preview: nil).isEmpty, "Solid-color drawing is meaningful artwork")
        let link = URL(string: "https://example.invalid/imgs/proof.png")!
        let id = try store.archive(first, name: "Proof", action: .shared, destination: "SFTP", remoteURL: link, remoteBinding: ["destination": "fixture"], date: date)
        try expect(store.entries.count == 1, "Archive creates one item")
        try expect(try store.read(id).drawingDefaults.values["customColor"] == "preserved", "Unknown original metadata survives archive")
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
        let legacyDir = root.appendingPathComponent("Loose"), legacyURL = legacyDir.appendingPathComponent("1791000000-old-proof.opensnap")
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
        let outside = root.appendingPathComponent("outside.opensnap"); try first.native.write(to: outside)
        let symlink = legacyDir.appendingPathComponent("escape.opensnap")
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
        let sharedDir = root.appendingPathComponent("SharedPreview")
        let sharedStore0 = try HistoryStore(directory: sharedDir)
        let leftID = try sharedStore0.archive(first, name: "left", action: .archived), rightID = try sharedStore0.archive(first, name: "right", action: .archived)
        // Two entries pointing at one preview picture: trashing one must keep the other's picture.
        let sharedIndexURL = sharedDir.appendingPathComponent("index.json")
        var sharedIndex = try JSONSerialization.jsonObject(with: Data(contentsOf: sharedIndexURL)) as! [String: Any]
        var sharedEntries = sharedIndex["entries"] as! [[String: Any]]
        let sharedPreview = sharedEntries[0]["previewFile"] as! String
        sharedEntries[1]["previewFile"] = sharedPreview
        sharedIndex["entries"] = sharedEntries
        try JSONSerialization.data(withJSONObject: sharedIndex).write(to: sharedIndexURL)
        let sharedStore = try HistoryStore(directory: sharedDir)
        try sharedStore.trash([leftID], move: trashMove)
        try expect(FileManager.default.fileExists(atPath: sharedDir.appendingPathComponent(sharedPreview).path) && !sharedStore.missing(rightID), "Trashing one entry preserves another entry's shared preview and drawing")
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
#endif
