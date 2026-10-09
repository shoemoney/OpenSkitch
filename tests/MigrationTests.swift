// Executable regression tests for the one-time OpenSnap data migration. Everything runs against a temporary
// HOME, temporary support folders, in-memory defaults and an in-memory Keychain: the owner's real data is never
// read or written. Run via tools/test.py (which supplies CFFIXED_USER_HOME). Dry run against a copy of real data:
//   MigrationTests --migration-dry-run OLD_SUPPORT_COPY NEW_SUPPORT_DIR [DEFAULTS_PLIST_COPY]
#if MIGRATION_TESTS
import AppKit
import CryptoKit
import Foundation

/// The same deterministic document that built tests/fixtures/legacy-sample.* (our own content, no original files).
enum LegacySample {
    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    static func backgroundPNG() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pixels = bitmap.bitmapData!
        for y in 0..<3 { for x in 0..<4 {
            let o = y * bitmap.bytesPerRow + x * 4
            pixels[o] = UInt8(40 + x * 60); pixels[o + 1] = UInt8(30 + y * 80); pixels[o + 2] = 200; pixels[o + 3] = x == 3 ? 100 : 255
        } }
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func document() -> SketchDocument {
        var document = SketchDocument(size: CGSize(width: 320, height: 200))
        document.backgroundPNG = backgroundPNG()
        func make(_ n: Int, _ kind: SketchElement.Kind, _ build: (inout SketchElement) -> Void) {
            var element = SketchElement(kind: kind); element.id = uuid(n); build(&element); document.elements.append(element)
        }
        make(1, .rectangle) { $0.rect = CGRect(x: 20, y: 20, width: 120, height: 70); $0.color = SketchColor(NSColor(deviceRed: 0.9, green: 0.2, blue: 0.1, alpha: 1)); $0.strokeWidth = 4 }
        make(2, .ellipse) { $0.rect = CGRect(x: 160, y: 30, width: 90, height: 60); $0.color = SketchColor(NSColor(deviceRed: 0.1, green: 0.5, blue: 0.9, alpha: 0.75)); $0.filled = true; $0.shadowed = true }
        make(3, .arrow) { $0.points = [CGPoint(x: 30, y: 150), CGPoint(x: 200, y: 120)]; $0.color = SketchColor(NSColor(deviceRed: 0.99, green: 0.05, blue: 0.35, alpha: 1)); $0.strokeWidth = 6 }
        make(4, .brush) { $0.points = [CGPoint(x: 220, y: 140), CGPoint(x: 232, y: 150), CGPoint(x: 246, y: 142), CGPoint(x: 260, y: 158), CGPoint(x: 280, y: 146)]; $0.color = SketchColor(NSColor(deviceRed: 0.1, green: 0.7, blue: 0.2, alpha: 1)); $0.strokeWidth = 8 }
        make(5, .text) { $0.text = "Hello OpenSnap"; $0.rect = CGRect(x: 24, y: 100, width: 200, height: 40); $0.fontName = "Helvetica-Bold"; $0.fontSize = 24; $0.outlined = true; $0.shadowed = true; $0.color = SketchColor(NSColor(deviceRed: 1, green: 1, blue: 0.2, alpha: 1)) }
        make(6, .text) { $0.text = "Second font: café ✓"; $0.rect = CGRect(x: 150, y: 165, width: 160, height: 28); $0.fontName = "Georgia"; $0.fontSize = 18; $0.outlined = false; $0.color = SketchColor(NSColor(deviceRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)) }
        return document
    }
    static let expectedDefaults = DrawingDefaults(values: ["brushColor": "rgb(252,12,89)", "brushColorAlpha": "1", "brushSize": "6",
                                                          "customColor": "rgb(0,255,255)", "customColorAlpha": "1"])
}

/// Fails a case when a preferences or Keychain call arrives after the "migration complete" marker already exists:
/// the marker must be the very last thing written (a crash after an early marker would skip the rest forever).
enum MarkerWatch {
    nonisolated(unsafe) static var url: URL?
    nonisolated(unsafe) static var violations = 0
    static func check() { if let url, FileManager.default.fileExists(atPath: url.path) { violations += 1 } }
}

final class FakeDefaults: MigrationDefaults {
    var old: [String: Any]
    var new: [String: Any]
    var writes = 0
    init(old: [String: Any], new: [String: Any] = [:]) { self.old = old; self.new = new }
    func oldValues() -> [String: Any] { MarkerWatch.check(); return old }
    func hasNewValue(forKey key: String) -> Bool { MarkerWatch.check(); return new[key] != nil }
    func setNewValue(_ value: Any, forKey key: String) { MarkerWatch.check(); new[key] = value; writes += 1 }
}

final class FakeKeychain: MigrationKeychain {
    var items: [String: [String: Data]] = [:]
    var failingAccounts: Set<String> = []
    var adds = 0
    var listingFails = false
    func accounts(service: String) throws -> [String] {
        MarkerWatch.check()
        if listingFails { throw NSError(domain: "FakeKeychain", code: -25308) }
        return (items[service] ?? [:]).keys.sorted()
    }
    func password(service: String, account: String) throws -> Data? {
        MarkerWatch.check()
        if failingAccounts.contains(account) { throw NSError(domain: "FakeKeychain", code: -25293) }
        return items[service]?[account]
    }
    func add(_ password: Data, service: String, account: String) throws -> Bool {
        MarkerWatch.check()
        if items[service]?[account] != nil { return false }
        items[service, default: [:]][account] = password; adds += 1; return true
    }
}

@main
enum MigrationTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static let oldService = OpenSnapMigration.oldKeychainService
    static let newService = OpenSnapMigration.newKeychainService

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// Relative path -> SHA-256 of every file below a folder (and every directory as "dir").
    static func snapshot(_ folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return result }
        for case let url as URL in walker {
            let relative = String(url.path.dropFirst(folder.path.count))
            result[relative] = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true ? "dir" : sha(try Data(contentsOf: url))
        }
        return result
    }
    static func fixture(_ name: String) throws -> Data {
        for base in ["tests/fixtures", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures").path] {
            let url = URL(fileURLWithPath: base).appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) { return data }
        }
        throw Failure(description: "Missing fixture \(name)")
    }
    static func previewPNG(width: Int, height: Int, shade: UInt8) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<height { for x in 0..<width {
            let o = y * bitmap.bytesPerRow + x * 4
            bitmap.bitmapData![o] = shade; bitmap.bitmapData![o + 1] = UInt8(x * 7 % 256); bitmap.bitmapData![o + 2] = UInt8(y * 5 % 256); bitmap.bitmapData![o + 3] = 255
        } }
        return bitmap.representation(using: .png, properties: [:])!
    }

    struct World {
        let root: URL, oldSupport: URL, newSupport: URL
        var oldHistory: URL { oldSupport.appendingPathComponent("History") }
        var newHistory: URL { newSupport.appendingPathComponent("History") }
        var newPublishing: URL { newSupport.appendingPathComponent("Publishing") }
    }
    static let ids = (1...6).map { String(format: "0000000%d-AAAA-4000-8000-00000000000%d", $0, $0) }

    /// An old SkitchRedux folder built from the committed fixtures: 5 History entries (one with a corrupt document),
    /// two destinations with a default, the legacy single destination file, and files the migration must ignore.
    static func makeWorld(extraCorruptWithoutPreview: Bool = false, customize: ((URL, inout [[String: Any]]) throws -> Void)? = nil) throws -> World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-migration-tests-" + UUID().uuidString)
        let oldSupport = root.appendingPathComponent("Application Support/SkitchRedux", isDirectory: true)
        let newSupport = root.appendingPathComponent("Application Support/OpenSnap", isDirectory: true)
        let history = oldSupport.appendingPathComponent("History", isDirectory: true), publishing = oldSupport.appendingPathComponent("Publishing", isDirectory: true)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: publishing, withIntermediateDirectories: true)
        var entries: [[String: Any]] = []
        func add(_ n: Int, name: String, text: String, native: String, document: Data, preview: Data?, previewName: String? = nil, action: String = "archived") throws {
            try document.write(to: history.appendingPathComponent(native))
            var entry: [String: Any] = ["id": ids[n], "name": name, "date": 813053688.5 + Double(n), "updated": 813053700.25 + Double(n), "size": [320, 200],
                "text": text, "action": action, "nativeFile": native, "digest": sha(document), "imported": false]
            if let preview, let previewName {
                try preview.write(to: history.appendingPathComponent(previewName)); entry["previewFile"] = previewName
            } else if let previewName { entry["previewFile"] = previewName }
            entries.append(entry)
        }
        try add(0, name: "Redux sample", text: "Hello OpenSnap", native: "redux-\(ids[0])-AAAAAAAA-0000-4000-8000-000000000001.skitch",
                document: try fixture("legacy-sample.skitch"), preview: previewPNG(width: 40, height: 25, shade: 10), previewName: "redux-\(ids[0])-AAAAAAAA-0000-4000-8000-000000000001.png", action: "exported")
        try add(1, name: "Editable JSON sample", text: "Second font", native: "redux-\(ids[1])-AAAAAAAA-0000-4000-8000-000000000002.skitchredux",
                document: try fixture("legacy-sample.skitchredux"), preview: previewPNG(width: 41, height: 26, shade: 20), previewName: "redux-\(ids[1])-AAAAAAAA-0000-4000-8000-000000000002.png")
        try add(2, name: "Plain imported", text: "Hello OpenSnap", native: "1791000000-plain.skitch",
                document: try fixture("legacy-sample-plain.skitch"), preview: previewPNG(width: 42, height: 27, shade: 30), previewName: "1791000000-plain.png", action: "shared")
        try add(3, name: "Corrupt with preview", text: "words that survive", native: "redux-\(ids[3])-AAAAAAAA-0000-4000-8000-000000000004.skitch",
                document: Data("<?xml version=\"1.0\"?><svg this is not a drawing".utf8), preview: previewPNG(width: 43, height: 28, shade: 40), previewName: "redux-\(ids[3])-AAAAAAAA-0000-4000-8000-000000000004.png")
        try add(4, name: "Valid, preview missing", text: "no preview", native: "redux-\(ids[4])-AAAAAAAA-0000-4000-8000-000000000005.skitch",
                document: try fixture("legacy-sample.skitch"), preview: nil, previewName: "redux-\(ids[4])-AAAAAAAA-0000-4000-8000-000000000005.png")
        if extraCorruptWithoutPreview {
            try add(5, name: "Corrupt, no preview", text: "lost", native: "redux-\(ids[5])-AAAAAAAA-0000-4000-8000-000000000006.skitch",
                    document: Data("garbage".utf8), preview: nil, previewName: nil)
        }
        try customize?(history, &entries)
        let index: [String: Any] = ["version": 1, "entries": entries, "ignoredLooseFiles": ["hidden-by-user.skitch"]]
        try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys]).write(to: history.appendingPathComponent("index.json"))
        try fixture("legacy-sample.skitch").write(to: history.appendingPathComponent("stray.skitch"))
        try fixture("legacy-sample.skitch").write(to: history.appendingPathComponent("hidden-by-user.skitch"))
        let destinations = """
        {"defaultID":"D2222222-2222-4222-8222-222222222222","version":2,"destinations":[
         {"id":"D1111111-1111-4111-8111-111111111111","name":"SFTP test","settings":{"credentialID":"C1111111-1111-4111-8111-111111111111","endpoint":"sftp://example.invalid/imgs","transport":"sftp","note":"\(oldService)","other":"\(oldService)/\(oldService)"}},
         {"id":"D2222222-2222-4222-8222-222222222222","name":"S3 test","settings":{"credentialID":"C2222222-2222-4222-8222-222222222222","endpoint":"","transport":"s3"}}]}
        """
        try Data(destinations.utf8).write(to: publishing.appendingPathComponent("destinations.json"))
        try Data("{\"credentialID\":\"C1111111-1111-4111-8111-111111111111\",\"transport\":\"sftp\",\"endpoint\":\"sftp://example.invalid/imgs\"}".utf8)
            .write(to: publishing.appendingPathComponent("destination.json"))
        try Data("{\"old\":true}".utf8).write(to: publishing.appendingPathComponent("destination.json.pre-destinations.bak"))
        try Data("recovery".utf8).write(to: oldSupport.appendingPathComponent("Recovery.skitch"))
        try Data("{}".utf8).write(to: oldSupport.appendingPathComponent("layout.json"))
        MarkerWatch.url = newSupport.appendingPathComponent(OpenSnapMigration.markerName)
        return World(root: root, oldSupport: oldSupport, newSupport: newSupport)
    }
    static func entry(_ id: String, name: String, native: String, document: Data) -> [String: Any] {
        ["id": id, "name": name, "date": 813053688.5, "updated": 813053700.25, "size": [320, 200], "text": "", "action": "archived",
         "nativeFile": native, "digest": sha(document), "imported": false]
    }
    static func makeDefaults() -> FakeDefaults {
        FakeDefaults(old: ["arrowHead": 2, "PencilSmoothing": "medium", "disableSounds": false, "appearanceStyle": "classic",
                           "skitchInSnap": true, "SkitchRedux.GlobalHotkeys.v1": Data([1, 2, 3]), "ExportFormat": "skitch",
                           "SkitchRedux.HistoryDragFormat": "skitch", "fittingPrecision": 1,
                           "NSWindow Frame NSColorPanel": "0 284 266 366 0 0 2056 1290 ", "SKPresetResizes": [["SKPresetResizeNameKey": "Ad", "SkitchReduxResizePresetID": "preset-9"], ["SKPresetResizeNameKey": "Banner"]]],
                     new: ["arrowHead": 5])
    }
    static func makeKeychain() -> FakeKeychain {
        let keychain = FakeKeychain()
        keychain.items[oldService] = ["C1111111-1111-4111-8111-111111111111": Data("secret-one".utf8), "C2222222-2222-4222-8222-222222222222": Data("secret-two".utf8)]
        keychain.items[newService] = ["C2222222-2222-4222-8222-222222222222": Data("already-here".utf8)]
        return keychain
    }
    /// The account's real home from the user database, which CFFIXED_USER_HOME does not redirect.
    static func realHomeDirectory() -> String { getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? "/nonexistent" }
    static func realHomeLibrary() -> String { realHomeDirectory() + "/Library/" }

    @MainActor static func main() {
        _ = NSApplication.shared
        if let flag = CommandLine.arguments.firstIndex(of: "--migration-dry-run") { dryRun(Array(CommandLine.arguments[(flag + 1)...])) }
        // Everything below uses fakes and temp folders, but a redirected HOME is the second line of defence.
        let realHome = realHomeDirectory()
        guard NSHomeDirectory() != realHome else {
            print("FAIL refusing to run: HOME is the real home \(realHome) (run through tools/test.py, which sets CFFIXED_USER_HOME)"); exit(2)
        }
        let cases: [(String, () throws -> Void)] = [
            ("Full migration: History converted to .opensnap with editable content equal to the source", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())
                guard let report else { throw Failure(description: "Migration did not run") }
                try expect(report.historyEntries == 5 && report.historyConverted == 4 && report.historyPictureOnly == 1 && report.historyOmitted == 0, "History counts: \(report.text)")
                let store = try HistoryStore(directory: world.newHistory)
                try expect(store.entries.count == 5, "New History has 5 entries, found \(store.entries.count)")
                for entry in store.entries {
                    try expect(URL(fileURLWithPath: entry.nativeFile).pathExtension == "opensnap", "\(entry.nativeFile) is not .opensnap")
                    let bytes = try Data(contentsOf: world.newHistory.appendingPathComponent(entry.nativeFile))
                    try expect(entry.digest == sha(bytes), "Digest is recomputed for \(entry.nativeFile)")
                    try expect(!entry.nativeFile.hasSuffix(".skitch") && !entry.nativeFile.hasSuffix(".skitchredux"), "Legacy extension survived")
                }
                let byName = Dictionary(uniqueKeysWithValues: store.entries.map { ($0.name, $0) })
                let expected = LegacySample.document()
                let redux = try store.read(byName["Redux sample"]!.id)
                try expect(redux.document == expected, "Redux .skitch: editable content differs from the source document")
                try expect(redux.drawingDefaults == LegacySample.expectedDefaults, "Redux .skitch: pen defaults differ: \(redux.drawingDefaults)")
                let json = try store.read(byName["Editable JSON sample"]!.id)
                try expect(json.document == expected, ".skitchredux: editable content differs from the source document")
                                for converted in [redux.document, json.document] {
                    try expect(converted.elements.count == 6 && converted.elements.map(\.kind) == expected.elements.map(\.kind), "Element count/types")
                    try expect(converted.elements.filter { $0.kind == .text }.map(\.fontName) == ["Helvetica-Bold", "Georgia"], "Two fonts survive")
                    try expect(converted.elements.filter { $0.kind == .text }.map(\.text) == ["Hello OpenSnap", "Second font: café ✓"], "Text survives")
                    try expect(converted.elements.map(\.color) == expected.elements.map(\.color), "Colours survive")
                    try expect(converted.backgroundPNG == expected.backgroundPNG, "Background pixels survive")
                }
                let plain = try store.read(byName["Plain imported"]!.id).document
                try expect(plain.elements.filter { $0.kind == .text }.count == 2 && plain.elements.filter { $0.kind == .path }.count >= 4 && plain.elements.allSatisfy { [.path, .text].contains($0.kind) }, "Plain legacy drawing: vector paths and 2 texts, got \(plain.elements.map(\.kind))")
                try expect(plain.elements.filter { $0.kind == .text }.map(\.text) == ["Hello OpenSnap", "Second font: café ✓"], "Plain drawing text")
                try expect(plain.backgroundPNG == expected.backgroundPNG, "Plain drawing background pixels")
                try expect(byName["Plain imported"]!.action == .shared && byName["Redux sample"]!.action == .exported, "Actions preserved")
                try expect(byName["Redux sample"]!.text == "Hello OpenSnap" && byName["Redux sample"]!.updated == Date(timeIntervalSinceReferenceDate: 813053700.25 + 0), "Entry text and dates preserved")
            }),
            ("A corrupt document is reported and kept as an image-only drawing from its preview", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(report.failures.contains { $0.contains("Corrupt with preview") && $0.contains("picture-only") }, "Failure recorded: \(report.failures)")
                let store = try HistoryStore(directory: world.newHistory)
                let entry = store.entries.first { $0.name == "Corrupt with preview" }!
                let file = try store.read(entry.id)
                try expect(file.document.elements.isEmpty && file.document.size == CGSize(width: 43, height: 28), "Image-only document has the preview's size and no elements")
                let preview = try Data(contentsOf: world.oldHistory.appendingPathComponent("redux-\(ids[3])-AAAAAAAA-0000-4000-8000-000000000004.png"))
                try expect(file.document.backgroundPNG != nil && NSBitmapImageRep(data: preview)?.pixelsWide == 43, "Background is the preview picture")
                try expect(entry.text == "words that survive", "Search text kept")
                try expect(try Data(contentsOf: world.newHistory.appendingPathComponent(entry.previewFile!)) == preview, "Preview copied byte for byte")
                let missing = store.entries.first { $0.name == "Valid, preview missing" }!
                try expect(missing.previewFile == nil && (try store.read(missing.id)).document == LegacySample.document(), "Entry with a missing preview keeps its converted document")
                try expect(report.failures.contains { $0.contains("preview file is missing") }, "Missing preview reported")
            }),
            ("A document and preview that are both unusable is omitted, reported, and does not abort the rest", {
                let world = try makeWorld(extraCorruptWithoutPreview: true); defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(report.historyEntries == 6 && report.historyOmitted == 1 && report.historyConverted == 4 && report.historyPictureOnly == 1, "Counts: \(report.text)")
                try expect(report.failures.contains { $0.contains("Corrupt, no preview") && $0.contains("omitted") }, "Omission reported")
                try expect(try HistoryStore(directory: world.newHistory).entries.count == 5, "The five usable entries migrated")
            }),
            ("Destinations, the default, the legacy file and the service name", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                let data = try Data(contentsOf: world.newPublishing.appendingPathComponent("destinations.json"))
                let list = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let destinations = list["destinations"] as! [[String: Any]]
                try expect(destinations.count == 2 && list["defaultID"] as? String == "D2222222-2222-4222-8222-222222222222", "Two destinations and the same defaultID")
                try expect(destinations.map { $0["name"] as! String } == ["SFTP test", "S3 test"], "Destination names")
                try expect(report.destinations == 2 && report.defaultDestinationName == "S3 test", "Report names the default")
                let text = String(decoding: data, as: UTF8.self)
                try expect(!text.contains(oldService) && text.contains(newService), "Keychain service reference rewritten")
                try expect(text.components(separatedBy: newService).count - 1 == 3, "Every occurrence rewritten, not just the first")
                let legacy = try Data(contentsOf: world.newPublishing.appendingPathComponent("destination.json"))
                try expect(legacy == (try Data(contentsOf: world.oldSupport.appendingPathComponent("Publishing/destination.json"))), "Legacy destination.json copied")
                try expect(!FileManager.default.fileExists(atPath: world.newPublishing.appendingPathComponent("destination.json.pre-destinations.bak").path), "Old backup file is not carried over")
                let attributes = try FileManager.default.attributesOfItem(atPath: world.newPublishing.appendingPathComponent("destinations.json").path)
                try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Destination file is private")
            }),
            ("Preferences are copied minus obsolete keys, renamed where needed, never overwriting", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let defaults = makeDefaults()
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: makeKeychain())!
                try expect(defaults.new["arrowHead"] as? Int == 5, "A key already set in OpenSnap is not overwritten")
                try expect(report.defaultsKeptExisting == ["arrowHead"], "Report lists the kept key")
                try expect(defaults.new["disableSounds"] == nil && defaults.new["appearanceStyle"] == nil, "Obsolete keys are not copied")
                try expect(Set(report.defaultsObsolete) == ["disableSounds", "appearanceStyle"], "Obsolete keys are listed")
                try expect(defaults.new["opensnapInSnap"] as? Bool == true && defaults.new["skitchInSnap"] == nil, "Renamed capture preference")
                try expect(defaults.new["OpenSnap.GlobalHotkeys.v1"] as? Data == Data([1, 2, 3]) && defaults.new["SkitchRedux.GlobalHotkeys.v1"] == nil, "Renamed hotkeys")
                let rows = defaults.new["SKPresetResizes"] as? [[String: Any]] ?? []
                try expect(rows.count == 2 && rows[0]["OpenSnapResizePresetID"] as? String == "preset-9" && rows[0]["SkitchReduxResizePresetID"] == nil
                           && rows[0]["SKPresetResizeNameKey"] as? String == "Ad" && rows[1]["OpenSnapResizePresetID"] == nil, "Resize preset id renamed inside each row: \(rows)")
                try expect(defaults.new["OpenSnapResizePresetID"] == nil, "No top-level resize preset id invented")
                try expect(defaults.new["ExportFormat"] as? String == "opensnap" && defaults.new["OpenSnap.HistoryDragFormat"] as? String == "opensnap", "Stored format values follow the new extension")
                try expect(defaults.new["PencilSmoothing"] as? String == "medium" && defaults.new["fittingPrecision"] as? Int == 1 && defaults.new["NSWindow Frame NSColorPanel"] != nil && defaults.new["SKPresetResizes"] != nil, "Ordinary keys copied")
                try expect(!defaults.new.keys.contains { $0.lowercased().contains("skitch") }, "No key keeps the old product name")
                try expect(!rows.contains { $0.keys.contains { $0.lowercased().contains("skitch") } }, "No row key keeps the old product name")
                try expect(defaults.old.count == 11, "Old domain untouched")
            }),
            ("Keychain items are copied to the new service, existing ones kept, old ones never deleted", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let keychain = makeKeychain()
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: keychain)!
                try expect(keychain.items[newService]?["C1111111-1111-4111-8111-111111111111"] == Data("secret-one".utf8), "Item copied under the same account")
                try expect(keychain.items[newService]?["C2222222-2222-4222-8222-222222222222"] == Data("already-here".utf8), "Existing new item not overwritten")
                try expect(keychain.items[oldService]?.count == 2 && keychain.items[oldService]?["C1111111-1111-4111-8111-111111111111"] == Data("secret-one".utf8), "Old items untouched")
                try expect(report.keychainCopied == 1 && report.keychainAlreadyPresent == 1 && report.keychainFailed == 0, "Keychain counts")
                try expect(!report.text.contains("secret-one"), "Secrets never appear in the report")
            }),
            ("A failing Keychain item is reported and does not stop the others", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let keychain = makeKeychain(); keychain.items[newService] = [:]
                keychain.failingAccounts = ["C1111111-1111-4111-8111-111111111111"]
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: keychain)!
                try expect(report.keychainFailed == 1 && report.keychainCopied == 1 && report.hasProblems && report.notice != nil, "Failure counted, other item copied")
                try expect(FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "Marker still written")
            }),
            ("Marker and human-readable report are written; the old folder is byte-for-byte unchanged", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let before = try snapshot(world.oldSupport)
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(".migrated-from-skitchredux").path), "Marker")
                let text = try String(contentsOf: world.newSupport.appendingPathComponent("migration-report.txt"), encoding: .utf8)
                try expect(text == report.text && text.contains("History entries found: 5") && text.contains("Corrupt with preview") && text.contains("obsolete, not copied"), "Report content")
                try expect(try snapshot(world.oldSupport) == before, "SHA-256 of every old file, and the file list, are unchanged")
                try expect(!FileManager.default.fileExists(atPath: world.oldSupport.appendingPathComponent(".migrated-from-skitchredux").path), "No marker in the old folder")
                try expect(!(try FileManager.default.contentsOfDirectory(atPath: world.newSupport.deletingLastPathComponent().path)).contains { $0.hasPrefix(".OpenSnap-migrating-") }, "Staging folder removed")
                try expect(!FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent("Recovery.skitch").path) && !FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent("layout.json").path), "Recovery and evidence files are not carried over")
                try expect(report.historyLooseUnindexed == 1, "Unindexed legacy file counted, ignored one not")
            }),
            ("Second launch does nothing at all", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let defaults = makeDefaults(), keychain = makeKeychain()
                _ = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain)
                let newBefore = try snapshot(world.newSupport), oldBefore = try snapshot(world.oldSupport)
                let writes = defaults.writes, adds = keychain.adds
                try expect(OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain) == nil, "Second run returns nil")
                try expect(try snapshot(world.newSupport) == newBefore && (try snapshot(world.oldSupport)) == oldBefore, "No file changed")
                try expect(defaults.writes == writes && keychain.adds == adds, "No preference or Keychain write")
            }),
            ("An interrupted run (no marker) repeats safely without duplicating or overwriting", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let defaults = makeDefaults(), keychain = makeKeychain()
                _ = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain)
                let historyBefore = try snapshot(world.newHistory)
                try FileManager.default.removeItem(at: world.newSupport.appendingPathComponent(".migrated-from-skitchredux"))
                let writes = defaults.writes, adds = keychain.adds
                let again = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain)!
                try expect(try snapshot(world.newHistory) == historyBefore, "History not rewritten or merged")
                try expect(again.notes.contains { $0.contains("already copied") } && !again.hasProblems, "Notes explain the stores an earlier run installed: \(again.text)")
                try expect(defaults.writes == writes && keychain.adds == adds, "No extra preference or Keychain writes")
                try expect(FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(".migrated-from-skitchredux").path), "Marker rewritten")
            }),
            ("No previous app folder means no migration and no new folder", {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-migration-tests-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: root) }
                let newSupport = root.appendingPathComponent("OpenSnap")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try expect(OpenSnapMigration.migrateIfNeeded(oldSupport: root.appendingPathComponent("SkitchRedux"), newSupport: newSupport, defaults: makeDefaults(), keychain: makeKeychain()) == nil, "Nothing to do")
                try expect(!FileManager.default.fileExists(atPath: newSupport.path), "New folder not created")
            }),
            ("An unreadable History index is reported without touching anything", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                try Data("not json".utf8).write(to: world.oldHistory.appendingPathComponent("index.json"))
                let before = try snapshot(world.oldSupport)
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(report.failures.contains { $0.contains("History index could not be read") } && !FileManager.default.fileExists(atPath: world.newHistory.path), "Reported, not migrated")
                try expect(report.hasProblems && report.notice?.hasPrefix("Copied your data") == true, "Notice shown, worded as a copy")
                try expect(!FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "A failed store leaves no marker")
                try expect(FileManager.default.fileExists(atPath: world.newPublishing.path), "Publishing still migrated")
                try expect(try snapshot(world.oldSupport) == before, "Old folder unchanged")
            }),
            ("A store-level failure leaves no marker and a later launch completes it without duplicates", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let goodIndex = try Data(contentsOf: world.oldHistory.appendingPathComponent("index.json"))
                try Data("not json".utf8).write(to: world.oldHistory.appendingPathComponent("index.json"))
                let defaults = makeDefaults(), keychain = makeKeychain()
                let first = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain)!
                try expect(first.storeFailed && first.hasProblems, "First run reports the failed store")
                try expect(!FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "No marker after a failed store")
                try expect(FileManager.default.fileExists(atPath: world.newPublishing.path), "The healthy store was installed")
                let publishingBefore = try snapshot(world.newPublishing), adds = keychain.adds
                try goodIndex.write(to: world.oldHistory.appendingPathComponent("index.json"))
                guard let second = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain) else {
                    throw Failure(description: "A launch after a failed store must try again")
                }
                try expect(try HistoryStore(directory: world.newHistory).entries.count == 5, "History completed on the later launch")
                try expect(try snapshot(world.newPublishing) == publishingBefore && keychain.adds == adds, "Publishing and Keychain not duplicated")
                try expect(!second.hasProblems || second.failures.allSatisfy { $0.contains("picture-only") || $0.contains("preview file is missing") }, "No store-level failure on the second run: \(second.failures)")
                try expect(!second.storeFailed, "Second run complete")
                try expect(FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "Marker written once everything is in place")
                try expect(OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: defaults, keychain: keychain) == nil, "Third launch does nothing")
            }),
            ("A destination folder that already exists is a problem, nothing is merged, and no marker is written", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                try FileManager.default.createDirectory(at: world.newHistory, withIntermediateDirectories: true)
                try Data("mine".utf8).write(to: world.newHistory.appendingPathComponent("keep.txt"))
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(report.failures.contains { $0.contains("History already exists") } && report.hasProblems && report.notice != nil, "Surfaced as a problem: \(report.failures)")
                let existing = try snapshot(world.newHistory)
                try expect(existing.count == 1 && existing.values.first == sha(Data("mine".utf8)) && existing.keys.first?.hasSuffix("keep.txt") == true, "The existing folder is untouched, nothing merged: \(existing)")
                try expect(!FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "No marker")
                try expect(FileManager.default.fileExists(atPath: world.newPublishing.path), "The other store was still installed")
            }),
            ("A Keychain that cannot be listed leaves no marker", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let keychain = makeKeychain(); keychain.listingFails = true
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: keychain)!
                try expect(report.storeFailed && !FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "Retry on the next launch")
            }),
            ("Two History entries whose converted names collide both survive under different names", {
                let document = try fixture("legacy-sample.skitch")
                let a = UUID().uuidString, b = UUID().uuidString
                let world = try makeWorld { history, entries in
                    try document.write(to: history.appendingPathComponent("same.skitch"))
                    try document.write(to: history.appendingPathComponent("same.skitchredux"))
                    entries.append(entry(a, name: "Collide A", native: "same.skitch", document: document))
                    entries.append(entry(b, name: "Collide B", native: "same.skitchredux", document: document))
                }
                defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(!report.storeFailed, "History installed: \(report.failures)")
                let store = try HistoryStore(directory: world.newHistory)
                let pair = store.entries.filter { $0.name.hasPrefix("Collide") }
                try expect(pair.count == 2 && Set(pair.map(\.nativeFile)).count == 2, "Distinct file names: \(pair.map(\.nativeFile))")
                for entry in pair { _ = try store.read(entry.id) }
            }),
            ("An index with an entry the History store refuses is caught by verification and not installed", {
                let document = try fixture("legacy-sample.skitch")
                let world = try makeWorld { history, entries in
                    try document.write(to: history.appendingPathComponent("badsize.skitch"))
                    var bad = entry(UUID().uuidString, name: "Bad size", native: "badsize.skitch", document: document)
                    bad["size"] = [0, 0]
                    entries.append(bad)
                }
                defer { try? FileManager.default.removeItem(at: world.root) }
                let report = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())!
                try expect(report.storeFailed && report.failures.contains { $0.contains("did not pass verification") }, "Verification failure reported: \(report.failures)")
                try expect(!FileManager.default.fileExists(atPath: world.newHistory.path) && !FileManager.default.fileExists(atPath: world.newSupport.appendingPathComponent(OpenSnapMigration.markerName).path), "Nothing half-installed, no marker")
            }),
            ("Verification fails when the History holds a different number of entries than was written", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                _ = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())
                try OpenSnapMigration.verifyHistory(at: world.newHistory, expectingEntries: 5)
                var wrongCount = false
                do { try OpenSnapMigration.verifyHistory(at: world.newHistory, expectingEntries: 4) } catch { wrongCount = true }
                try expect(wrongCount, "A count that differs from what was written is refused")
                // A stray, valid document the store would import as an extra entry.
                let kept = try FileManager.default.contentsOfDirectory(atPath: world.newHistory.path).first { $0.hasSuffix(".opensnap") }!
                try FileManager.default.copyItem(at: world.newHistory.appendingPathComponent(kept), to: world.newHistory.appendingPathComponent("stray.opensnap"))
                var strayRefused = false
                do { try OpenSnapMigration.verifyHistory(at: world.newHistory, expectingEntries: 5) } catch { strayRefused = true }
                try expect(strayRefused, "An extra imported entry is refused")
            }),
            ("Staging folders left by an interrupted run are removed, and only OpenSnap's own", {
                let world = try makeWorld(); defer { try? FileManager.default.removeItem(at: world.root) }
                let parent = world.newSupport.deletingLastPathComponent()
                let leftover = parent.appendingPathComponent(OpenSnapMigration.stagingPrefix + UUID().uuidString), foreign = parent.appendingPathComponent(OpenSnapMigration.stagingPrefix + "not-a-uuid"), other = parent.appendingPathComponent("SomethingElse")
                for url in [leftover, foreign, other] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
                _ = OpenSnapMigration.migrateIfNeeded(oldSupport: world.oldSupport, newSupport: world.newSupport, defaults: makeDefaults(), keychain: makeKeychain())
                try expect(!FileManager.default.fileExists(atPath: leftover.path), "Own leftover staging removed")
                try expect(FileManager.default.fileExists(atPath: foreign.path) && FileManager.default.fileExists(atPath: other.path), "Anything else is left alone")
            }),
            ("The native reader refuses every retired format", {
                for name in ["legacy-sample.skitch", "legacy-sample.skitchredux", "legacy-sample-plain.skitch"] {
                    var rejected = false
                    do { _ = try OpenSnapFile.decode(try fixture(name)) } catch { rejected = true }
                    try expect(rejected, "\(name) was accepted by the native reader")
                }
            }),
            ("The legacy reader is reachable only from Migration", {
                let allowed: Set<String> = ["Migration.swift", "LegacyReader.swift"]
                let folder = FileManager.default.fileExists(atPath: "Sources") ? "Sources" : URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
                var checked = 0
                for name in try FileManager.default.contentsOfDirectory(atPath: folder).sorted() where name.hasSuffix(".swift") && !allowed.contains(name) {
                    let text = try String(contentsOfFile: folder + "/" + name, encoding: .utf8)
                    checked += 1
                    for symbol in ["LegacyDocumentReader", "LegacySkitch", "LegacyBridge", "LegacyDocumentContent"] {
                        try expect(!text.contains(symbol), "\(name) refers to \(symbol): only Migration may reach the legacy reader")
                    }
                }
                try expect(checked > 10, "Scanned the sources")
            }),
            ("Info.plist declares .opensnap as the only document type", {
                let plistPath = FileManager.default.fileExists(atPath: "Info.plist") ? "Info.plist" : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist").path
                let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: plistPath)), format: nil) as! [String: Any]
                try expect(plist["CFBundleIdentifier"] as? String == "com.shoemoney.opensnap" && plist["CFBundleExecutable"] as? String == "OpenSnap", "Identity")
                let types = (plist["CFBundleDocumentTypes"] as! [[String: Any]]).flatMap { $0["LSItemContentTypes"] as! [String] }
                try expect(Set(types) == ["com.shoemoney.opensnap.document", "public.image", "com.adobe.pdf"], "Document types: \(types)")
                let exported = plist["UTExportedTypeDeclarations"] as! [[String: Any]]
                try expect(exported.count == 1 && exported[0]["UTTypeIdentifier"] as? String == "com.shoemoney.opensnap.document", "One exported UTI")
                try expect(Set(exported[0]["UTTypeConformsTo"] as! [String]) == ["public.data", "public.content"], "UTI conforms to public.data and public.content")
                let tags = (exported[0]["UTTypeTagSpecification"] as! [String: Any])["public.filename-extension"] as! [String]
                try expect(tags == ["opensnap"], "Extension tag")
                try expect(plist["UTImportedTypeDeclarations"] == nil, "No imported legacy type")
            }),
        ]
        var failures = 0
        for (name, test) in cases {
            MarkerWatch.url = nil; MarkerWatch.violations = 0
            do {
                try test()
                if MarkerWatch.violations > 0 { throw Failure(description: "preferences or Keychain were touched after the marker was written (\(MarkerWatch.violations) calls)") }
                print("PASS \(name)")
            } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("MigrationTests: \(cases.count - failures)/\(cases.count) passed; \(failures) failed")
        if failures != 0 { exit(1) }
    }

    /// Test-only entry: run the migration code against COPIES of real data and print what it did. Never the app.
    @MainActor static func dryRun(_ arguments: [String]) -> Never {
        guard arguments.count >= 2 else { print("usage: --migration-dry-run OLD_SUPPORT_COPY NEW_SUPPORT_DIR [DEFAULTS_PLIST_COPY]"); exit(2) }
        let old = URL(fileURLWithPath: arguments[0]).standardizedFileURL, new = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        for url in [old, new] where url.path.hasPrefix(realHomeLibrary()) {
            print("FAIL refusing to touch \(url.path): inside the real ~/Library"); exit(2)
        }
        do {
            var oldValues: [String: Any] = [:]
            if arguments.count >= 3 {
                oldValues = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: arguments[2])), format: nil) as? [String: Any] ?? [:]
            }
            let keychain = FakeKeychain()
            if let data = try? Data(contentsOf: old.appendingPathComponent("Publishing/destinations.json")),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = root["destinations"] as? [[String: Any]] {
                for destination in list {
                    if let settings = destination["settings"] as? [String: Any], let account = settings["credentialID"] as? String {
                        keychain.items[oldService, default: [:]][account] = Data("dry-run-placeholder".utf8)
                    }
                }
            }
            let defaults = FakeDefaults(old: oldValues)
            let before = try snapshot(old)
            guard let report = OpenSnapMigration.migrateIfNeeded(oldSupport: old, newSupport: new, defaults: defaults, keychain: keychain) else {
                print("Nothing to migrate (no old folder or marker present)"); exit(0)
            }
            print(report.text)
            let store = try HistoryStore(directory: new.appendingPathComponent("History"))
            var editable = 0, pictureOnly = 0
            for entry in store.entries {
                let file = try store.read(entry.id)
                if file.document.elements.isEmpty && file.document.backgroundPNG != nil { pictureOnly += 1 } else { editable += 1 }
            }
            let list = try JSONSerialization.jsonObject(with: Data(contentsOf: new.appendingPathComponent("Publishing/destinations.json"))) as! [String: Any]
            print("DRY-RUN VERIFIED: \(store.entries.count) History entries open in the new store (\(editable) editable, \(pictureOnly) picture-only); all .opensnap: \(store.entries.allSatisfy { $0.nativeFile.hasSuffix(".opensnap") })")
            print("DRY-RUN VERIFIED: destinations \((list["destinations"] as! [Any]).count), default \(report.defaultDestinationName ?? "none")")
            print("DRY-RUN VERIFIED: copied preference keys \(defaults.new.count) of \(oldValues.count); Keychain (placeholders) copied \(report.keychainCopied)")
            let rowsOut = defaults.new["SKPresetResizes"] as? [[String: Any]] ?? [], rowsIn = oldValues["SKPresetResizes"] as? [[String: Any]] ?? []
            print("DRY-RUN VERIFIED: resize preset rows \(rowsOut.count) of \(rowsIn.count); row ids renamed: \(rowsOut.filter { $0["OpenSnapResizePresetID"] != nil }.count) (old-named ids in input: \(rowsIn.filter { $0["SkitchReduxResizePresetID"] != nil }.count), old-named ids left in output: \(rowsOut.filter { $0["SkitchReduxResizePresetID"] != nil }.count))")
            print("DRY-RUN VERIFIED: old copy unchanged: \(try snapshot(old) == before)")
            let unchanged = try snapshot(old) == before
            exit(report.hasProblems || !unchanged ? 1 : 0)
        } catch { print("FAIL dry run: \(error)"); exit(1) }
    }
}
#endif
