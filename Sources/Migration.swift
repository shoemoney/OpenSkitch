import AppKit
import CryptoKit
import Security

/// One-time, copy-never-move migration of the previous app's data (folder "SkitchRedux", defaults domain
/// "com.shoemoney.skitch-redux", Keychain service "SkitchRedux.CustomPublishing") into OpenSnap's own stores.
///
/// Rules: nothing in the old stores is ever modified, moved or deleted; the new folder is assembled in a
/// staging folder and moved into place; the marker file is written last, and only when no whole store failed, so an interrupted or
/// partly failed run simply runs again (stores already installed are remembered and never copied twice); one failing
/// document never aborts the rest and is final. Every location and store is injectable for tests.
/// This file, together with LegacyReader.swift, is the only code that knows the retired document formats.
protocol MigrationKeychain {
    func accounts(service: String) throws -> [String]
    func password(service: String, account: String) throws -> Data?
    /// Returns false when the item already exists (it is left untouched).
    func add(_ password: Data, service: String, account: String) throws -> Bool
}

protocol MigrationDefaults {
    /// Everything the old domain holds.
    func oldValues() -> [String: Any]
    func hasNewValue(forKey key: String) -> Bool
    func setNewValue(_ value: Any, forKey key: String)
}

struct MigrationReport {
    var historyEntries = 0
    var historyConverted = 0
    var historyPictureOnly = 0
    var historyOmitted = 0
    var historyLooseUnindexed = 0
    var previewsCopied = 0
    var destinations = 0
    var defaultDestinationName: String?
    var publishingFilesCopied: [String] = []
    var defaultsCopied: [String] = []
    var defaultsRenamed: [String: String] = [:]
    var defaultsKeptExisting: [String] = []
    var defaultsObsolete: [String] = []
    var keychainCopied = 0
    var keychainAlreadyPresent = 0
    var keychainFailed = 0
    var failures: [String] = []
    /// A whole store (History, Publishing, the Keychain listing, the placement) failed: the next launch must retry.
    var storeFailed = false
    var notes: [String] = []

    var hasProblems: Bool { !failures.isEmpty || keychainFailed > 0 }

    private var renamedSummary: String {
        if defaultsRenamed.isEmpty { return "" }
        let pairs = defaultsRenamed.sorted { $0.key < $1.key }.map { "\($0.key) -> \($0.value)" }
        return ", of which renamed: " + pairs.joined(separator: ", ")
    }

    var text: String {
        var lines: [String] = ["OpenSnap migration report", ""]
        lines.append("History entries found: \(historyEntries)")
        lines.append("  converted to .opensnap: \(historyConverted)")
        lines.append("  kept as picture only (document could not be converted): \(historyPictureOnly)")
        lines.append("  omitted (document and preview both unusable): \(historyOmitted)")
        lines.append("  previews copied: \(previewsCopied)")
        lines.append("  files in the old History folder not in its index (not migrated): \(historyLooseUnindexed)")
        let defaultName: String = defaultDestinationName.map { " (default: \($0))" } ?? ""
        lines.append("Upload destinations copied: \(destinations)" + defaultName)
        lines.append("  files: " + (publishingFilesCopied.isEmpty ? "none" : publishingFilesCopied.joined(separator: ", ")))
        lines.append("Preferences copied: \(defaultsCopied.count)" + renamedSummary)
        lines.append("  already set in OpenSnap, kept: " + (defaultsKeptExisting.isEmpty ? "none" : defaultsKeptExisting.sorted().joined(separator: ", ")))
        lines.append("  obsolete, not copied: " + (defaultsObsolete.isEmpty ? "none" : defaultsObsolete.sorted().joined(separator: ", ")))
        lines.append("Keychain items: \(keychainCopied) copied, \(keychainAlreadyPresent) already present, \(keychainFailed) failed")
        if !notes.isEmpty { lines.append(""); lines.append("Notes"); lines += notes.map { "  - " + $0 } }
        lines.append(""); lines.append(failures.isEmpty ? "No failures." : "Failures")
        lines += failures.map { "  - " + $0 }
        lines.append(""); lines.append("The previous app's folder, preferences and Keychain items were not changed.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line for the status bar when something needs attention.
    var notice: String? {
        guard hasProblems else { return nil }
        return "Copied your data to OpenSnap, but \(failures.count + keychainFailed) item(s) need attention; see migration-report.txt in the OpenSnap folder."
    }
}

enum OpenSnapMigration {
    static let markerName = ".migrated-from-skitchredux"
    static let storeMarkerPrefix = ".migrated-store-"
    static let stagingPrefix = ".OpenSnap-migrating-"
    static let reportName = "migration-report.txt"
    static let oldFolderName = "SkitchRedux"
    static let newFolderName = "OpenSnap"
    static let oldDefaultsDomain = "com.shoemoney.skitch-redux"
    static let oldKeychainService = "SkitchRedux.CustomPublishing"
    static let newKeychainService = "OpenSnap.Publishing"
    /// Keys nothing reads any more (the retired appearance switch and the retired sounds preference).
    static let obsoleteDefaultsKeys: Set<String> = ["appearanceStyle", "disableSounds"]
    /// Keys whose names carried the old product name.
    static let renamedDefaultsKeys: [String: String] = [
        "skitchInSnap": "opensnapInSnap",
        "SkitchRedux.GlobalHotkeys.v1": "OpenSnap.GlobalHotkeys.v1",
        "SkitchRedux.HistoryDragFormat": "OpenSnap.HistoryDragFormat",
    ]
    /// Keys that live inside each row of the resize presets array (the array key itself is unchanged).
    static let resizePresetsKey = "SKPresetResizes"
    static let renamedResizeRowKeys: [String: String] = ["SkitchReduxResizePresetID": "OpenSnapResizePresetID"]
    /// Stored values that named the retired document format.
    static let renamedDefaultsValues: [String: [String: String]] = [
        "ExportFormat": ["skitch": "opensnap", "skitchredux": "opensnap"],
        "OpenSnap.HistoryDragFormat": ["skitch": "opensnap", "skitchredux": "opensnap"],
    ]

    /// Notice for the editor's status line after a launch that migrated with problems.
    nonisolated(unsafe) static var launchNotice: String?

    // MARK: Launch

    /// Called first thing in main(). Isolated runs (tests, harnesses) set OPENSNAP_APP_SUPPORT and never migrate.
    static func runAtLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard (environment["OPENSNAP_APP_SUPPORT"] ?? "").isEmpty else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let domain = Bundle.main.bundleIdentifier ?? "com.shoemoney.opensnap"
        let report = migrateIfNeeded(oldSupport: base.appendingPathComponent(oldFolderName, isDirectory: true),
                                     newSupport: base.appendingPathComponent(newFolderName, isDirectory: true),
                                     defaults: SystemMigrationDefaults(newDomain: domain), keychain: SystemMigrationKeychain())
        launchNotice = report?.notice
    }

    // MARK: Migration

    /// Returns nil when there is nothing to do (no old folder, or already migrated).
    @discardableResult
    static func migrateIfNeeded(oldSupport: URL, newSupport: URL, defaults: MigrationDefaults, keychain: MigrationKeychain,
                                now: Date = Date()) -> MigrationReport? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: oldSupport.path, isDirectory: &isDirectory), isDirectory.boolValue,
              !fm.fileExists(atPath: newSupport.appendingPathComponent(markerName).path) else { return nil }
        var report = MigrationReport()
        let parent = newSupport.deletingLastPathComponent()
        removeLeftoverStaging(in: parent)
        let stage = parent.appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        } catch {
            report.failures.append("Could not prepare the new folder (\(error.localizedDescription)); nothing was migrated and the next launch will try again.")
            return report
        }
        defer { try? fm.removeItem(at: stage) }

        // A store an earlier run already installed is never copied again.
        func alreadyInstalled(_ name: String) -> Bool { fm.fileExists(atPath: newSupport.appendingPathComponent(storeMarkerPrefix + name).path) }
        if alreadyInstalled("Publishing") { report.notes.append("Upload destinations were already copied by an earlier run; left as they are.") } else {
            migratePublishing(from: oldSupport.appendingPathComponent("Publishing", isDirectory: true),
                              to: stage.appendingPathComponent("Publishing", isDirectory: true), report: &report)
        }
        if alreadyInstalled("History") { report.notes.append("History was already copied by an earlier run; left as it is.") } else {
            migrateHistory(from: oldSupport.appendingPathComponent("History", isDirectory: true),
                           to: stage.appendingPathComponent("History", isDirectory: true), report: &report)
        }
        do {
            try fm.createDirectory(at: newSupport, withIntermediateDirectories: true)
            for name in ["Publishing", "History"] {
                let staged = stage.appendingPathComponent(name, isDirectory: true), target = newSupport.appendingPathComponent(name, isDirectory: true)
                guard fm.fileExists(atPath: staged.path) else { continue }
                if fm.fileExists(atPath: target.path) {
                    report.storeFailed = true
                    report.failures.append("\(name) already exists in the OpenSnap folder, so the previous app's \(name) was not copied (nothing was merged or overwritten); the next launch will try again.")
                    continue
                }
                try fm.moveItem(at: staged, to: target)
                try Data().write(to: newSupport.appendingPathComponent(storeMarkerPrefix + name), options: .atomic)
            }
        } catch {
            report.storeFailed = true
            report.failures.append("Could not place the migrated folders (\(error.localizedDescription)); the next launch will try again.")
            return report
        }
        migrateDefaults(defaults, report: &report)
        migrateKeychain(keychain, report: &report)

        do {
            try Data(report.text.utf8).write(to: newSupport.appendingPathComponent(reportName), options: .atomic)
            // A whole store that failed leaves no marker: the next launch retries it (documents already copied are not repeated).
            guard !report.storeFailed else { return report }
            let marker: [String: Any] = ["migratedAt": ISO8601DateFormatter().string(from: now), "from": oldSupport.path, "version": 1]
            try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys, .prettyPrinted])
                .write(to: newSupport.appendingPathComponent(markerName), options: .atomic)
        } catch {
            report.failures.append("Could not write the migration marker (\(error.localizedDescription)); the next launch will repeat the copy safely.")
        }
        return report
    }

    /// Staging folders from interrupted runs, recognised only by OpenSnap's own exact naming, directly inside Application Support.
    private static func removeLeftoverStaging(in parent: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names where name.hasPrefix(stagingPrefix) && UUID(uuidString: String(name.dropFirst(stagingPrefix.count))) != nil {
            let url = parent.appendingPathComponent(name, isDirectory: true)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Publishing

    private static func migratePublishing(from old: URL, to new: URL, report: inout MigrationReport) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path) else { report.notes.append("The previous app had no upload destinations."); return }
        do {
            try fm.createDirectory(at: new, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in ["destinations.json", "destination.json"] {
                let source = old.appendingPathComponent(name)
                guard fm.fileExists(atPath: source.path) else { continue }
                var data = try Data(contentsOf: source)
                // Any Keychain service named inside the files now points at the new service.
                if var text = String(data: data, encoding: .utf8), text.contains(oldKeychainService) {
                    text = text.replacingOccurrences(of: oldKeychainService, with: newKeychainService)
                    data = Data(text.utf8)
                }
                let target = new.appendingPathComponent(name)
                try data.write(to: target, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                report.publishingFilesCopied.append(name)
                if name == "destinations.json" { describeDestinations(data, report: &report) }
            }
        } catch {
            report.storeFailed = true
            try? fm.removeItem(at: new)
            report.failures.append("Upload destinations could not be copied (\(error.localizedDescription)); they are still in the previous app's folder and the next launch will try again.")
        }
    }

    private static func describeDestinations(_ data: Data, report: inout MigrationReport) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["destinations"] as? [[String: Any]] else {
            report.failures.append("destinations.json was copied but could not be read back as a destination list.")
            return
        }
        report.destinations = list.count
        let defaultID = root["defaultID"] as? String
        report.defaultDestinationName = list.first { ($0["id"] as? String) == defaultID }?["name"] as? String
    }

    // MARK: History

    private static func safeLeaf(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    private static func renamed(_ oldName: String, extension newExtension: String? = nil) -> String {
        let url = URL(fileURLWithPath: oldName)
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix("redux-") { stem = "snap-" + stem.dropFirst("redux-".count) }
        return stem + "." + (newExtension ?? url.pathExtension)
    }

    private static func migrateHistory(from old: URL, to new: URL, report: inout MigrationReport) {
        let fm = FileManager.default
        let indexURL = old.appendingPathComponent("index.json")
        guard fm.fileExists(atPath: indexURL.path) else { report.notes.append("The previous app had no History."); return }
        guard let indexData = try? Data(contentsOf: indexURL),
              var root = (try? JSONSerialization.jsonObject(with: indexData)) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else {
            report.storeFailed = true
            report.failures.append("The previous History index could not be read; no History was migrated and the old files were left alone.")
            return
        }
        do { try fm.createDirectory(at: new, withIntermediateDirectories: true) } catch {
            report.storeFailed = true
            report.failures.append("History could not be prepared (\(error.localizedDescription)); the next launch will try again.")
            return
        }
        report.historyEntries = entries.count
        var kept: [[String: Any]] = [], nameMap: [String: String] = [:], used = Set<String>()
        func unique(_ name: String) -> String {
            var candidate = name, counter = 2
            while !used.insert(candidate).inserted {
                let url = URL(fileURLWithPath: name)
                candidate = url.deletingPathExtension().lastPathComponent + "-\(counter)." + url.pathExtension; counter += 1
            }
            return candidate
        }
        var referenced = Set<String>()
        for original in entries {
            var entry = original
            let label = "\((entry["name"] as? String) ?? "Untitled") (\((entry["id"] as? String) ?? "no id"))"
            guard let nativeName = entry["nativeFile"] as? String, safeLeaf(nativeName) else {
                report.historyOmitted += 1; report.failures.append("\(label): the entry names an unsafe file; omitted.")
                continue
            }
            referenced.insert(nativeName)
            let previewName = (entry["previewFile"] as? String).flatMap { safeLeaf($0) ? $0 : nil }
            if let previewName { referenced.insert(previewName) }
            let previewData = previewName.flatMap { try? Data(contentsOf: old.appendingPathComponent($0)) }

            var converted: Data?, failure: String?
            do {
                let attributes = try fm.attributesOfItem(atPath: old.appendingPathComponent(nativeName).path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= LegacySkitch.maximumFileBytes else { throw LegacySkitchError.limitExceeded }
                let content = try LegacyDocumentReader.read(Data(contentsOf: old.appendingPathComponent(nativeName)))
                if let note = content.note { report.notes.append("\(label): \(note)") }
                converted = try OpenSnapFile(document: content.document, drawingDefaults: content.drawingDefaults, canvasData: content.canvasData).encoded()
            } catch { failure = error.localizedDescription }
            if converted == nil {
                if let previewData, let picture = pictureOnlyDocument(previewData) {
                    converted = picture
                    report.historyPictureOnly += 1
                    report.failures.append("\(label): \(failure ?? "unreadable document"); kept as a picture-only drawing from its preview.")
                } else {
                    report.historyOmitted += 1
                    report.failures.append("\(label): \(failure ?? "unreadable document") and no usable preview; omitted (the original is still in the previous app's folder).")
                    continue
                }
            } else { report.historyConverted += 1 }

            let newNative = unique(renamed(nativeName, extension: OpenSnapFile.fileExtension))
            do { try converted!.write(to: new.appendingPathComponent(newNative), options: .atomic) } catch {
                report.failures.append("\(label): could not write the converted document (\(error.localizedDescription)); omitted.")
                if failure == nil { report.historyConverted -= 1 } else { report.historyPictureOnly -= 1 }
                report.historyOmitted += 1
                continue
            }
            nameMap[nativeName] = newNative
            entry["nativeFile"] = newNative
            entry["digest"] = SHA256.hash(data: converted!).map { String(format: "%02x", $0) }.joined()
            if let previewName, let previewData {
                let newPreview = unique(renamed(previewName))
                do { try previewData.write(to: new.appendingPathComponent(newPreview), options: .atomic); entry["previewFile"] = newPreview; report.previewsCopied += 1 }
                catch { entry.removeValue(forKey: "previewFile"); report.failures.append("\(label): preview could not be copied (\(error.localizedDescription)).") }
            } else {
                if previewName != nil { report.failures.append("\(label): its preview file is missing.") }
                entry.removeValue(forKey: "previewFile")
            }
            kept.append(entry)
        }
        if let loose = try? fm.contentsOfDirectory(atPath: old.path) {
            let ignored = Set((root["ignoredLooseFiles"] as? [String]) ?? [])
            report.historyLooseUnindexed = loose.filter { name in
                !referenced.contains(name) && name != "index.json" && !ignored.contains(name) && !name.hasPrefix(".")
                    && ["skitch", "skitchredux"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
            }.count
        }
        root["entries"] = kept
        root["ignoredLooseFiles"] = ((root["ignoredLooseFiles"] as? [String]) ?? []).compactMap { nameMap[$0] }
        do {
            try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: new.appendingPathComponent("index.json"), options: .atomic)
        } catch {
            report.storeFailed = true
            report.failures.append("The migrated History index could not be written (\(error.localizedDescription)); no History was migrated and the next launch will try again.")
            try? fm.removeItem(at: new)
            return
        }
        // The new History must open with the app's own store before it is allowed into place.
        do {
            try verifyHistory(at: new, expectingEntries: kept.count)
        } catch {
            report.storeFailed = true
            report.failures.append("The migrated History did not pass verification (\(error.localizedDescription)); it was not installed and the next launch will try again. Nothing in the old folder was changed.")
            try? fm.removeItem(at: new)
        }
    }

    /// Opens the staged History with the app's own store and reads every drawing. The entry count must match what
    /// was written: the store imports stray valid documents it finds, which would silently add entries.
    static func verifyHistory(at directory: URL, expectingEntries expected: Int) throws {
        let store = try HistoryStore(directory: directory)
        for entry in store.entries { _ = try store.read(entry.id) }
        if store.entries.count != expected { throw HistoryStore.Failure.corruptIndex }
    }

    /// An editable drawing holding only the old preview picture, for documents that cannot be converted.
    private static func pictureOnlyDocument(_ preview: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: preview) else { return nil }
        var document = SketchDocument(size: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        guard SketchDocument.validSize(document.size) else { return nil }
        document.backgroundPNG = bitmap.representation(using: .png, properties: [:])
        return try? OpenSnapFile(document: document).encoded()
    }

    // MARK: Preferences and Keychain

    static func migrateDefaults(_ defaults: MigrationDefaults, report: inout MigrationReport) {
        for (oldKey, value) in defaults.oldValues().sorted(by: { $0.key < $1.key }) {
            if obsoleteDefaultsKeys.contains(oldKey) { report.defaultsObsolete.append(oldKey); continue }
            let key = renamedDefaultsKeys[oldKey] ?? oldKey
            if defaults.hasNewValue(forKey: key) { report.defaultsKeptExisting.append(key); continue }
            var stored = value
            if key == resizePresetsKey, let rows = value as? [Any] {
                stored = rows.map { row -> Any in
                    guard var dictionary = row as? [String: Any] else { return row }
                    for (oldName, newName) in renamedResizeRowKeys {
                        if let id = dictionary.removeValue(forKey: oldName), dictionary[newName] == nil { dictionary[newName] = id }
                    }
                    return dictionary
                }
            }
            if let text = value as? String, let replacement = renamedDefaultsValues[key]?[text] { stored = replacement }
            defaults.setNewValue(stored, forKey: key)
            report.defaultsCopied.append(key)
            if key != oldKey { report.defaultsRenamed[oldKey] = key }
        }
    }

    private static func migrateKeychain(_ keychain: MigrationKeychain, report: inout MigrationReport) {
        let accounts: [String]
        do { accounts = try keychain.accounts(service: oldKeychainService) } catch {
            report.keychainFailed += 1; report.storeFailed = true; report.failures.append("The previous Keychain items could not be listed (\(error.localizedDescription)).")
            return
        }
        for account in accounts {
            do {
                guard let secret = try keychain.password(service: oldKeychainService, account: account) else { continue }
                if try keychain.add(secret, service: newKeychainService, account: account) { report.keychainCopied += 1 } else { report.keychainAlreadyPresent += 1 }
            } catch {
                report.keychainFailed += 1; report.failures.append("Keychain item \(account) could not be copied (\(error.localizedDescription)).")
            }
        }
    }
}

// MARK: - Real stores

struct SystemMigrationDefaults: MigrationDefaults {
    let newDomain: String
    var oldDomain = OpenSnapMigration.oldDefaultsDomain
    var defaults = UserDefaults.standard
    func oldValues() -> [String: Any] { defaults.persistentDomain(forName: oldDomain) ?? [:] }
    func hasNewValue(forKey key: String) -> Bool { defaults.persistentDomain(forName: newDomain)?[key] != nil }
    func setNewValue(_ value: Any, forKey key: String) { defaults.set(value, forKey: key) }
}

struct SystemMigrationKeychain: MigrationKeychain {
    private func status(_ code: OSStatus) -> NSError { NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
    func accounts(service: String) throws -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return [] }
        guard code == errSecSuccess else { throw status(code) }
        return ((result as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
    }
    func password(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess else { throw status(code) }
        return result as? Data
    }
    func add(_ password: Data, service: String, account: String) throws -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
                                    kSecValueData as String: password, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let code = SecItemAdd(query as CFDictionary, nil)
        if code == errSecDuplicateItem { return false }
        guard code == errSecSuccess else { throw status(code) }
        return true
    }
}
