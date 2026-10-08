import Foundation
import Security

// Several saved upload destinations, exactly one of them the default. Secrets live in the Keychain
// (or, for AWS profiles, in the user's own credentials file); the JSON here never contains one.

struct PublishingDestination: Codable, Equatable {
    var id: String
    var name: String
    var settings: PublishingSettings

    init(id: String = UUID().uuidString, name: String, settings: PublishingSettings) {
        self.id = id; self.name = name; self.settings = settings
    }
}

struct PublishingDestinationList: Codable, Equatable {
    var version = 2
    var defaultID: String?
    var destinations: [PublishingDestination] = []

    /// A stale defaultID falls back to the first entry so uploads never lose their target.
    var defaultDestination: PublishingDestination? {
        destinations.first { $0.id == defaultID } ?? destinations.first
    }
}

extension PublishingSettings {
    /// Whether this destination keeps a secret in the Keychain under credentialID.
    var storesSecretInKeychain: Bool {
        switch transport {
        case .sftp: return false
        case .s3: return (s3?.credentialsProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    /// Enough detail to attempt an upload.
    var isUsable: Bool {
        func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch transport {
        case .sftp: return !(blank(sshAlias) && blank(endpoint))
        case .s3: return !blank(s3?.bucket ?? "") && !blank(s3?.region ?? "")
        default: return !blank(endpoint)
        }
    }

    /// Menu title used for a migrated or unnamed destination.
    var suggestedName: String {
        switch transport {
        case .sftp:
            let alias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? endpoint
            return "SFTP · " + (alias.isEmpty ? host : alias)
        case .s3: return "S3 · " + (s3?.bucket ?? "")
        default:
            let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? endpoint
            return transport.title + " · " + host
        }
    }
}

protocol PublishingSecretStore {
    func read(_ id: String, allowMissing: Bool) throws -> String
    func add(_ value: String, id: String) throws
    func remove(_ id: String)
}

struct PublishingKeychain: PublishingSecretStore {
    private static let service = "SkitchRedux.CustomPublishing"
    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
         kSecAttrAccount as String: id, kSecAttrSynchronizable as String: false]
    }
    func read(_ id: String, allowMissing: Bool = false) throws -> String {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound, allowMissing { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw PublishingFailure("The publishing password could not be read from macOS Keychain (\(status)).")
        }
        return value
    }
    func add(_ value: String, id: String) throws {
        var q = query(id)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PublishingFailure("The publishing password could not be saved to macOS Keychain (\(status)).")
        }
    }
    func remove(_ id: String) { SecItemDelete(query(id) as CFDictionary) }
}

/// Tests (and anything that must never touch the login Keychain) use this.
final class PublishingMemorySecrets: PublishingSecretStore {
    private let lock = NSLock()
    private(set) var items: [String: String] = [:]
    func read(_ id: String, allowMissing: Bool) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if let value = items[id] { return value }
        if allowMissing { return "" }
        throw PublishingFailure("The publishing password could not be read from macOS Keychain (-25300).")
    }
    func add(_ value: String, id: String) throws { lock.lock(); items[id] = value; lock.unlock() }
    func remove(_ id: String) { lock.lock(); items.removeValue(forKey: id); lock.unlock() }
}

final class PublishingDestinationStore {
    let directory: URL
    let secrets: PublishingSecretStore
    private let lock = NSLock()

    init(directory: URL, secrets: PublishingSecretStore) {
        self.directory = directory; self.secrets = secrets
    }

    /// The folder for a support directory: <support>/Publishing.
    static func directory(support: URL) -> URL { support.appendingPathComponent("Publishing", isDirectory: true) }

    /// The store the app uses. With SKITCH_APP_SUPPORT set (tests, harnesses, eye-dump) it lives inside
    /// that isolated folder and secrets stay in memory, so nothing can reach the real folder or Keychain.
    /// Without it, the real Application Support folder and the login Keychain.
    static func forEnvironment(_ environment: [String: String]) -> PublishingDestinationStore {
        if let isolated = environment["SKITCH_APP_SUPPORT"], !isolated.isEmpty {
            return PublishingDestinationStore(directory: directory(support: URL(fileURLWithPath: isolated, isDirectory: true)),
                                              secrets: PublishingMemorySecrets())
        }
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkitchRedux", isDirectory: true)
        return PublishingDestinationStore(directory: directory(support: real), secrets: PublishingKeychain())
    }

    static let system = forEnvironment(ProcessInfo.processInfo.environment)

    var file: URL { directory.appendingPathComponent("destinations.json") }
    /// The pre-multi-destination single file. It is copied, never moved or modified: a downgrade must still find it.
    var legacyFile: URL { directory.appendingPathComponent("destination.json") }
    var backupFile: URL { directory.appendingPathComponent("destination.json.pre-destinations.bak") }

    func load() throws -> PublishingDestinationList {
        lock.lock(); defer { lock.unlock() }
        return try loadLocked()
    }
    func defaultDestination() throws -> PublishingDestination? { try load().defaultDestination }

    func setDefault(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var list = try loadLocked()
        guard list.destinations.contains(where: { $0.id == id }) else { throw PublishingFailure("That destination no longer exists.") }
        list.defaultID = id
        try write(list)
    }

    /// Adds or replaces by id. A secret-bearing destination gets a fresh Keychain item; the old one is
    /// deleted only after the new list is committed, so a failed save never loses the working secret.
    func save(_ destination: PublishingDestination, password: String) throws {
        lock.lock(); defer { lock.unlock() }
        var list = try loadLocked()
        var next = destination
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.name.isEmpty, next.name.count <= 80, !PublishingPlan.hasControls(next.name) else {
            throw PublishingFailure("Give the destination a name of up to 80 characters.")
        }
        guard !list.destinations.contains(where: { $0.id != next.id && $0.name.caseInsensitiveCompare(next.name) == .orderedSame }) else {
            throw PublishingFailure("A destination named “\(next.name)” already exists.")
        }
        let index = list.destinations.firstIndex { $0.id == next.id }
        let previous = index.map { list.destinations[$0].settings }
        next.settings.credentialID = UUID().uuidString
        if next.settings.storesSecretInKeychain { try secrets.add(password, id: next.settings.credentialID) }
        if let index { list.destinations[index] = next } else { list.destinations.append(next) }
        if list.defaultID == nil || !list.destinations.contains(where: { $0.id == list.defaultID }) { list.defaultID = next.id }
        do { try write(list) } catch {
            if next.settings.storesSecretInKeychain { secrets.remove(next.settings.credentialID) }
            throw error
        }
        if let previous, previous.storesSecretInKeychain, previous.credentialID != legacyCredentialID() {
            secrets.remove(previous.credentialID)
        }
    }

    func remove(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var list = try loadLocked()
        guard let index = list.destinations.firstIndex(where: { $0.id == id }) else { return }
        let removed = list.destinations.remove(at: index)
        if list.defaultID == id || !list.destinations.contains(where: { $0.id == list.defaultID }) { list.defaultID = list.destinations.first?.id }
        try write(list)
        if removed.settings.storesSecretInKeychain, removed.settings.credentialID != legacyCredentialID() {
            secrets.remove(removed.settings.credentialID)
        }
    }

    /// The Keychain item the untouched legacy destination.json still points at. An older build would read
    /// it after a downgrade, so it is never deleted here.
    private func legacyCredentialID() -> String? {
        guard let data = try? Data(contentsOf: legacyFile), data.count <= 65536,
              let legacy = try? JSONDecoder().decode(PublishingSettings.self, from: data) else { return nil }
        return legacy.credentialID
    }

    private func loadLocked() throws -> PublishingDestinationList {
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            do {
                let list = try JSONDecoder().decode(PublishingDestinationList.self, from: Data(contentsOf: file))
                guard list.destinations.allSatisfy({ UUID(uuidString: $0.settings.credentialID) != nil }) else {
                    throw PublishingFailure("Invalid credential identifier.")
                }
                return list
            } catch { throw PublishingFailure("Publishing destinations could not be read. The saved file has been preserved.") }
        }
        guard fm.fileExists(atPath: legacyFile.path) else { return PublishingDestinationList() }
        // Transparent migration: the one old destination becomes the only entry and the default.
        // Its credentialID is kept, so the Keychain item (and SFTP config) are untouched; destinations.json
        // existing marks the store as migrated.
        let legacy: PublishingSettings
        do {
            let data = try Data(contentsOf: legacyFile)
            guard data.count <= 65536 else { throw PublishingFailure("too large") }
            legacy = try JSONDecoder().decode(PublishingSettings.self, from: data)
            guard UUID(uuidString: legacy.credentialID) != nil else { throw PublishingFailure("bad id") }
        } catch { throw PublishingFailure("Publishing settings could not be read. The existing destination has been preserved.") }
        let entry = PublishingDestination(name: legacy.suggestedName, settings: legacy)
        let list = PublishingDestinationList(defaultID: entry.id, destinations: [entry])
        var backup = backupFile
        if fm.fileExists(atPath: backup.path) { backup = directory.appendingPathComponent("destination.json.pre-destinations.\(UUID().uuidString).bak") }
        do {
            try fm.copyItem(at: legacyFile, to: backup)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        } catch { throw PublishingFailure("The existing destination could not be backed up, so it was not migrated.") }
        try write(list)
        return list
    }

    private func write(_ list: PublishingDestinationList) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(list).write(to: file, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw PublishingFailure("Publishing destinations could not be saved to Application Support.") }
    }
}

enum PublishingS3Credentials {
    /// Profile destinations read the shared credentials file; others use the access key ID in
    /// settings plus the secret in the secret store. Nothing is read until an upload or Test needs it.
    static func resolve(settings: PublishingSettings, secrets: PublishingSecretStore, credentialsFile: URL) throws -> S3Credentials {
        let profile = (settings.s3?.credentialsProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { return try AWSSharedCredentials.load(profile: profile, from: credentialsFile) }
        let secret = try secrets.read(settings.credentialID, allowMissing: false)
        return S3Credentials(accessKeyID: settings.username, secretAccessKey: secret, sessionToken: "")
    }
}
