import AppKit
import Security
import CryptoKit
import Darwin

/// Capture locally; persist with the URL only after PublishingCoordinator reports success.
/// These digests contain no password, key, username, or endpoint. They do not attest upload success.
struct HistoryRemoteDestinationBinding: Equatable {
    let version: Int
    let destinationFingerprint: String
    let sshFingerprint: String?
    let publicURL: String
    var dictionary: [String: String] {
        var result = ["version": String(version), "destinationSHA256": destinationFingerprint, "publicURL": publicURL]
        if let sshFingerprint { result["sshConfigSHA256"] = sshFingerprint }
        return result
    }
    init(destinationFingerprint: String, sshFingerprint: String?, publicURL: String) {
        version = 1; self.destinationFingerprint = destinationFingerprint
        self.sshFingerprint = sshFingerprint; self.publicURL = publicURL
    }
    init(dictionary: [String: String]) throws {
        let allowed: Set<String> = ["version", "destinationSHA256", "sshConfigSHA256", "publicURL"]
        guard Set(dictionary.keys).isSubset(of: allowed), dictionary["version"] == "1",
              let digest = dictionary["destinationSHA256"], digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let url = dictionary["publicURL"], !url.isEmpty,
              dictionary["sshConfigSHA256"] == nil || dictionary["sshConfigSHA256"]!.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw PublishingFailure("This history item has no valid remote-deletion binding.")
        }
        self.init(destinationFingerprint: digest, sshFingerprint: dictionary["sshConfigSHA256"], publicURL: url)
    }
}

private func historyDeletionDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

struct HistoryRemoteDeletionPlan {
    let publishing: PublishingPlan
    let fileName: String
    let settings: PublishingSettings

    static func fingerprint(_ settings: PublishingSettings) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return historyDeletionDigest(try encoder.encode(settings))
    }

    init(url: URL, binding: HistoryRemoteDestinationBinding, settings: PublishingSettings,
         capabilities: PublishingCapabilities?, sftpAvailable: Bool) throws {
        guard binding.version == 1, binding.publicURL == url.absoluteString,
              binding.destinationFingerprint == (try Self.fingerprint(settings)) else {
            throw PublishingFailure("The publishing destination changed or this history item has no valid destination binding. Remote deletion was refused.")
        }
        guard settings.transport == .sftp || settings.transport == .webDAV else {
            throw PublishingFailure("Remote history deletion supports keyed SFTP and WebDAV only. This destination is unsupported.")
        }
        let base = try PublishingPlan.baseURL(settings.publicBaseURL, schemes: ["http", "https"])
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let baseParts = URLComponents(url: base, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.scheme == baseParts.scheme, parts.host == baseParts.host, parts.port == baseParts.port,
              parts.percentEncodedPath.hasPrefix(baseParts.percentEncodedPath + "/") else {
            throw PublishingFailure("The history URL is not in the current configured public destination.")
        }
        let leaf = String(parts.percentEncodedPath.dropFirst(baseParts.percentEncodedPath.count + 1))
        guard !leaf.isEmpty, !leaf.contains("/"), let decoded = leaf.removingPercentEncoding,
              !decoded.contains("%") else {
            throw PublishingFailure("Remote deletion requires one unambiguous filename directly inside the public destination.")
        }
        try PublishingPlan.validateComponent(decoded)
        let plan = try PublishingPlan(settings: settings, fileName: decoded, capabilities: capabilities, sftpAvailable: sftpAvailable)
        guard plan.publicURL?.absoluteString == url.absoluteString else {
            throw PublishingFailure("The history URL does not exactly match the configured published filename.")
        }
        // Never let an HTTP server interpret a twice-encoded path or traversal differently.
        for candidate in [base, plan.remoteURL] {
            guard let path = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding,
                  !path.contains("%") else {
                throw PublishingFailure("Ambiguous destination paths are not eligible for remote deletion.")
            }
        }
        publishing = plan; fileName = decoded; self.settings = settings
    }

    func webDAVConfig(username: String, password: String) throws -> Data {
        guard publishing.transport == .webDAV else { throw PublishingFailure("This is not a WebDAV deletion.") }
        try PublishingPlan.validateUsername(username)
        guard !username.isEmpty || password.isEmpty else { throw PublishingFailure("A password requires a username.") }
        var lines = ["silent", "show-error", "globoff", "path-as-is", "request = \"DELETE\"", "fail",
                     "connect-timeout = 10", "max-time = 25", "retry = 0", "max-redirs = 0",
                     "output = \"/dev/null\"", "proto = " + (try PublishingPlan.configQuote("=" + publishing.remoteURL.scheme!)),
                     "url = " + (try PublishingPlan.configQuote(publishing.remoteURL.absoluteString)),
                     "write-out = \"%{response_code}\\n%{url_effective}\\n\""]
        if !username.isEmpty { lines.append("user = " + (try PublishingPlan.configQuote(username + ":" + password))) }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    func verifyWebDAV(_ output: PublishingProcess.Output, username: String, password: String) throws {
        guard output.code == 0 else {
            let detail = PublishingPlan.sanitized(output.stderr, username: username, password: password)
            throw PublishingFailure("Remote deletion failed (curl \(output.code))." + (detail.isEmpty ? "" : "\n" + detail))
        }
        let lines = output.stdout.components(separatedBy: "\n")
        guard lines.count == 3, lines.last == "", ["200", "204"].contains(lines[0]),
              lines[1] == publishing.remoteURL.absoluteString else {
            throw PublishingFailure("WebDAV did not confirm a completed deletion at the exact configured file URL. Its remote state is unknown.")
        }
    }
}

// Resolve the user's alias locally with ssh -G, then pin the supported connection settings.
// Deletion uses -F /dev/null, so changing an alias after validation cannot retarget the command.
// Key contents are never read. Advanced proxies/canonicalization are refused, rather than guessed.
struct HistoryDeletionSSHConfiguration {
    let fingerprint: String
    let pinnedOptions: [String]

    init(output: String) throws {
        guard !output.isEmpty, output.utf8.count <= 65536 else { throw PublishingFailure("SSH configuration could not be bound safely.") }
        var values: [String: [String]] = [:]
        for line in output.split(separator: "\n") {
            guard let split = line.firstIndex(of: " ") else { throw PublishingFailure("SSH configuration response was incomplete.") }
            let key = String(line[..<split]), value = String(line[line.index(after: split)...])
            guard key.range(of: "^[a-z0-9]+$", options: .regularExpression) != nil,
                  !value.isEmpty, !PublishingPlan.hasControls(value) else { throw PublishingFailure("SSH configuration response was unsafe.") }
            values[key, default: []].append(value)
        }
        func scalar(_ key: String) throws -> String? {
            guard let list = values[key] else { return nil }
            guard list.count == 1 else { throw PublishingFailure("SSH configuration contains ambiguous connection settings.") }
            return list[0]
        }
        for key in ["proxycommand", "proxyjump"] {
            if let value = try scalar(key), value != "none" {
                throw PublishingFailure("Remote deletion cannot safely freeze SSH proxy connections. This SSH alias is unsupported.")
            }
        }
        if let value = try scalar("canonicalizehostname"), !["false", "no"].contains(value) {
            throw PublishingFailure("Remote deletion cannot safely freeze SSH hostname canonicalization.")
        }
        guard let host = try scalar("hostname"), host.range(of: "^[A-Za-z0-9.\\[\\]:_-]+$", options: .regularExpression) != nil, !host.hasPrefix("-"),
              let user = try scalar("user"), user.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*\\$?$", options: .regularExpression) != nil,
              let portText = try scalar("port"), let port = Int(portText), (1...65535).contains(port) else {
            throw PublishingFailure("SSH did not provide a safe host, login, and port for remote deletion.")
        }
        var options = ["HostName=" + host, "User=" + user, "Port=" + String(port)]
        func safePath(_ value: String) throws -> String {
            guard value == "none" || value == "SSH_AUTH_SOCK" || value.hasPrefix("/") || value.hasPrefix("~/"),
                  !value.contains("%"), !value.contains("\\"), !value.contains("\""), !value.contains("'"),
                  !PublishingPlan.hasControls(value), value.utf8.count <= 4096 else {
                throw PublishingFailure("SSH paths cannot be frozen safely for remote deletion.")
            }
            return try PublishingPlan.configQuote(value)
        }
        let identities = values["identityfile"] ?? []
        guard !identities.isEmpty, identities.count <= 32 else { throw PublishingFailure("SSH identity configuration is unavailable or too large.") }
        for identity in identities { options.append("IdentityFile=" + (try safePath(identity))) }
        if let certificates = values["certificatefile"] {
            guard certificates.count <= 32 else { throw PublishingFailure("SSH certificate configuration is too large.") }
            for certificate in certificates { options.append("CertificateFile=" + (try safePath(certificate))) }
        }
        if let only = try scalar("identitiesonly") {
            guard ["yes", "no", "true", "false"].contains(only) else { throw PublishingFailure("SSH identity policy is invalid.") }
            options.append("IdentitiesOnly=" + only)
        }
        if let agent = try scalar("identityagent") { options.append("IdentityAgent=" + (try safePath(agent))) }
        if let alias = try scalar("hostkeyalias") {
            guard alias.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else { throw PublishingFailure("SSH host-key alias is unsafe.") }
            options.append("HostKeyAlias=" + alias)
        }
        for key in ["userknownhostsfile", "globalknownhostsfile"] {
            guard let value = try scalar(key) else { throw PublishingFailure("SSH known-host configuration is unavailable.") }
            let paths = value.split(separator: " ").map(String.init)
            guard !paths.isEmpty, paths.count <= 32 else { throw PublishingFailure("SSH known-host configuration is too large.") }
            options.append(key + "=" + (try paths.map(safePath)).joined(separator: " "))
        }
        pinnedOptions = options
        fingerprint = historyDeletionDigest(Data(output.utf8))
    }

    static func inspectionArguments(_ plan: PublishingSFTPPlan) -> [String] {
        var args = ["-G"], index = 0
        let original = plan.arguments
        while index < original.count - 1 {
            if original[index] == "-o" { args += ["-o", original[index + 1]]; index += 2 }
            else if original[index] == "-P" { args += ["-p", original[index + 1]]; index += 2 }
            else if original[index] == "-b" || original[index] == "-S" { index += 2 }
            else { index += 1 }
        }
        return args + [plan.target]
    }

    func deletionArguments(_ plan: PublishingSFTPPlan) -> [String] {
        var args = ["-F", "/dev/null", "-q", "-b", "-", "-S", "/usr/bin/ssh"]
        let original = plan.arguments
        var index = 0
        while index < original.count - 1 {
            if original[index] == "-o" {
                let option = original[index + 1]
                if !option.hasPrefix("User=") { args += ["-o", option] }
                index += 2
            } else if ["-P", "-b", "-S"].contains(original[index]) { index += 2 }
            else { index += 1 }
        }
        for option in pinnedOptions { args += ["-o", option] }
        return args + [plan.target]
    }
}

struct HistoryRemoteDeletionCommand {
    let executable: String
    let arguments: [String]
    let input: Data
    let timeout: TimeInterval
    let allowsSSHAgent: Bool
}

// Snapshot only SSH configuration files, never IdentityFile/CertificateFile contents. Standard
// Includes are expanded locally and bounded. Dynamic Match/environment-dependent configs cannot
// safely bind a previous publication, so capture refuses them and the parent disables Delete Web.
enum HistoryDeletionSSHConfigSnapshot {
    static func fingerprint(userDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh"),
                            systemDirectory: URL = URL(fileURLWithPath: "/etc/ssh")) throws -> String {
        var material = Data(), fileCount = 0, totalBytes = 0, stack: Set<String> = []
        let roots = [userDirectory, systemDirectory].map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        func tokens(_ line: String) throws -> [String] {
            var result: [String] = [], token = "", quote: Character?
            for char in line {
                if char == "\\" { throw PublishingFailure("SSH configuration escaping cannot be bound safely.") }
                if let q = quote {
                    if char == q { quote = nil } else { token.append(char) }
                } else if char == "\"" || char == "'" { quote = char }
                else if char == "#" { break }
                else if char == " " || char == "\t" || char == "=" {
                    if !token.isEmpty { result.append(token); token = "" }
                } else { token.append(char) }
            }
            guard quote == nil else { throw PublishingFailure("SSH configuration has unterminated quotes.") }
            if !token.isEmpty { result.append(token) }
            return result
        }
        func visit(_ url: URL, relativeTo includeRoot: URL) throws {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let path = resolved.path, name = resolved.lastPathComponent.lowercased()
            guard roots.contains(where: { path.hasPrefix($0 + "/") }),
                  !name.hasPrefix("id_"), !["pem", "key", "pub"].contains(resolved.pathExtension.lowercased()),
                  fileCount < 128, !stack.contains(path) else {
                throw PublishingFailure("SSH includes are outside the supported configuration tree, cyclic, or may reference keys. Remote deletion cannot be bound.")
            }
            fileCount += 1
            material.append(Data(path.utf8)); material.append(0)
            guard FileManager.default.fileExists(atPath: path) else { material.append(Data("missing\0".utf8)); return }
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= 65536 else {
                throw PublishingFailure("SSH configuration is not a bounded regular file.")
            }
            let data = try Data(contentsOf: resolved); totalBytes += data.count
            guard data.count <= 65536, totalBytes <= 1048576, let text = String(data: data, encoding: .utf8),
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && !["\n", "\r", "\t"].contains($0) }),
                  !text.contains("${") else { throw PublishingFailure("SSH configuration is too large or environment-dependent.") }
            material.append(data); material.append(0); stack.insert(path); defer { stack.remove(path) }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let directive = trimmed.prefix { !$0.isWhitespace && $0 != "=" }.lowercased()
                guard directive != "match" else { throw PublishingFailure("Dynamic SSH Match rules cannot be bound to a history publication safely.") }
                guard directive == "include" else { continue }
                let parts = try tokens(trimmed)
                guard parts.count > 1 else { throw PublishingFailure("SSH Include has no path.") }
                for pattern in parts.dropFirst() {
                    guard !pattern.contains("%"), !pattern.contains("$"), !PublishingPlan.hasControls(pattern) else { throw PublishingFailure("Dynamic SSH includes cannot be bound safely.") }
                    let absolute: String
                    if pattern.hasPrefix("~/") { absolute = String(userDirectory.deletingLastPathComponent().path) + String(pattern.dropFirst()) }
                    else if pattern.hasPrefix("/") { absolute = pattern }
                    else { absolute = includeRoot.appendingPathComponent(pattern).path }
                    let boundedPattern = URL(fileURLWithPath: absolute).resolvingSymlinksInPath().standardizedFileURL.path
                    guard roots.contains(where: { boundedPattern.hasPrefix($0 + "/") }) else {
                        throw PublishingFailure("SSH Include is outside the supported configuration tree.")
                    }
                    material.append(Data(("include:" + absolute + "\0").utf8))
                    var matches = glob_t()
                    let code = glob(absolute, GLOB_NOSORT, nil, &matches)
                    defer { globfree(&matches) }
                    guard code == 0 || code == GLOB_NOMATCH, matches.gl_pathc <= 128 else { throw PublishingFailure("SSH includes could not be expanded within safe bounds.") }
                    var paths: [String] = []
                    for index in 0..<Int(matches.gl_pathc) {
                        if let value = matches.gl_pathv?[index] { paths.append(String(cString: value)) }
                    }
                    for match in paths.sorted() { try visit(URL(fileURLWithPath: match), relativeTo: includeRoot) }
                }
            }
        }
        try visit(userDirectory.appendingPathComponent("config"), relativeTo: userDirectory)
        try visit(systemDirectory.appendingPathComponent("ssh_config"), relativeTo: systemDirectory)
        return historyDeletionDigest(material)
    }
}

protocol HistoryRemoteDeletionAdapter {
    func loadSettings() throws -> PublishingSettings
    func sshSourceFingerprint() throws -> String
    func capabilities(cancellation: PublishingCancellation) throws -> PublishingCapabilities
    func inspectSSH(_ plan: PublishingSFTPPlan, cancellation: PublishingCancellation) throws -> HistoryDeletionSSHConfiguration
    func password(credentialID: String) throws -> String
    func execute(_ command: HistoryRemoteDeletionCommand, cancellation: PublishingCancellation) throws -> PublishingProcess.Output
}

private struct HistorySystemRemoteDeletionAdapter: HistoryRemoteDeletionAdapter {
    func sshSourceFingerprint() throws -> String { try HistoryDeletionSSHConfigSnapshot.fingerprint() }
    /// Remote deletion is bound to the default destination's settings; a different default refuses deletion.
    func loadSettings() throws -> PublishingSettings {
        guard let settings = try? PublishingDestinationStore.system.defaultDestination()?.settings else {
            throw PublishingFailure("Current publishing settings are unavailable. Remote deletion was refused.")
        }
        return settings
    }
    func capabilities(cancellation: PublishingCancellation) throws -> PublishingCapabilities {
        let output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--version"], timeout: 5, cancellation: cancellation)
        guard output.code == 0 else { throw PublishingFailure("System curl is unavailable.") }
        return try PublishingCapabilities(versionOutput: output.stdout)
    }
    func inspectSSH(_ plan: PublishingSFTPPlan, cancellation: PublishingCancellation) throws -> HistoryDeletionSSHConfiguration {
        let output = try PublishingProcess.run(executable: "/usr/bin/ssh", arguments: HistoryDeletionSSHConfiguration.inspectionArguments(plan),
                                              timeout: 5, cancellation: cancellation)
        guard output.code == 0 else { throw PublishingFailure("The SSH alias could not be resolved safely for remote deletion.") }
        return try HistoryDeletionSSHConfiguration(output: output.stdout)
    }
    func password(credentialID: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "SkitchRedux.CustomPublishing", kSecAttrAccount as String: credentialID,
                                    kSecAttrSynchronizable as String: false, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw PublishingFailure("The current publishing password is unavailable in Keychain. Remote deletion was refused.")
        }
        return password
    }
    func execute(_ command: HistoryRemoteDeletionCommand, cancellation: PublishingCancellation) throws -> PublishingProcess.Output {
        try PublishingProcess.run(executable: command.executable, arguments: command.arguments, input: command.input,
                                  timeout: command.timeout, allowSSHAgent: command.allowsSSHAgent, cancellation: cancellation)
    }
}

public final class HistoryRemoteDeletionCoordinator: NSObject {
    private let adapter: HistoryRemoteDeletionAdapter
    private let work: PublishingWorkController
    private let destinationBinding: [String: String]?
    private var busy = false

    public init(destinationBinding: [String: String]? = nil) {
        adapter = HistorySystemRemoteDeletionAdapter(); work = PublishingWorkController()
        self.destinationBinding = destinationBinding; super.init()
    }
    init(adapter: HistoryRemoteDeletionAdapter, work: PublishingWorkController = PublishingWorkController(),
         destinationBinding: [String: String]? = nil) {
        self.adapter = adapter; self.work = work; self.destinationBinding = destinationBinding; super.init()
    }

    /// Capture the intended public URL before publishing, then compare captureBinding(for:) after
    /// success. This is a configuration snapshot, not proof of immutable config or server identity.
    public func captureBinding(fileName: String) throws -> [String: String] {
        let settings = try adapter.loadSettings()
        let mappingOnly = try PublishingCapabilities(versionOutput: "curl mapping-validator\nProtocols: http https\nFeatures: SSL\n")
        let plan = try PublishingPlan(settings: settings, fileName: fileName, capabilities: mappingOnly,
                                      sftpAvailable: PublishingTransfer.sftpAvailable)
        guard let url = plan.publicURL else { throw PublishingFailure("A configured public URL is required for remote-deletion binding.") }
        let binding = try captureBinding(for: url)
        guard binding["destinationSHA256"] == (try HistoryRemoteDeletionPlan.fingerprint(settings)) else {
            throw PublishingFailure("Publishing configuration changed while capturing the filename binding.")
        }
        return binding
    }

    /// Synchronous, bounded local config reads only: no process, network, Keychain or key reads.
    /// Capture the intended URL before publication when possible and compare with capture after
    /// success; a URL alone cannot establish which destination was used during an earlier upload.
    /// A post-success capture binds the mapping at capture time, not unobserved earlier settings.
    public func captureBinding(for url: URL) throws -> [String: String] {
        let settings = try adapter.loadSettings()
        let ssh = settings.transport == .sftp ? try adapter.sshSourceFingerprint() : nil
        let binding = HistoryRemoteDestinationBinding(destinationFingerprint: try HistoryRemoteDeletionPlan.fingerprint(settings),
                                                     sshFingerprint: ssh, publicURL: url.absoluteString)
        // Capture validates mapping without asserting any installed curl capability. Actual deletion
        // inspects the system tool's protocols before executing a mutation.
        let mappingOnly = try PublishingCapabilities(versionOutput: "curl mapping-validator\nProtocols: http https\nFeatures: SSL\n")
        _ = try HistoryRemoteDeletionPlan(url: url, binding: binding, settings: settings,
                                         capabilities: mappingOnly, sftpAvailable: PublishingTransfer.sftpAvailable)
        guard settings == (try adapter.loadSettings()) else {
            throw PublishingFailure("Publishing configuration changed while capturing the binding. Remote deletion is unavailable.")
        }
        if settings.transport == .sftp, ssh != (try adapter.sshSourceFingerprint()) {
            throw PublishingFailure("SSH configuration changed while capturing the binding. Remote deletion is unavailable.")
        }
        return binding.dictionary
    }

    /// Caller supplies the user-click confirmation. This method opens no UI and deletes one bound
    /// remote file only; it never deletes local history, folders, or a URL-only legacy record.
    public func deleteRemote(url: URL, presenting: NSWindow, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let binding = destinationBinding else {
            PublishingMainDelivery.enqueue { completion(.failure(PublishingFailure("This history item has no publication-time destination binding. Remote deletion was refused."))) }
            return
        }
        deleteRemote(url: url, binding: binding, presenting: presenting, completion: completion)
    }
    public func deleteRemote(url: URL, binding: [String: String], presenting: NSWindow,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        deleteBoundRemote(url: url, binding: binding, completion: completion)
    }
    // Same implementation used by the native public API; tests need no NSWindow or desktop UI.
    func deleteBoundRemote(url: URL, binding: [String: String],
                           completion: @escaping (Result<Void, Error>) -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.deleteBoundRemote(url: url, binding: binding, completion: completion) }; return }
        guard !busy, work.acceptsWork else { completion(.failure(publishingCancellationError())); return }
        busy = true
        work.start(work: { context in
            let binding = try HistoryRemoteDestinationBinding(dictionary: binding)
            let settings = try self.adapter.loadSettings()
            guard binding.destinationFingerprint == (try HistoryRemoteDeletionPlan.fingerprint(settings)) else {
                throw PublishingFailure("The publishing destination changed. Remote deletion was refused.")
            }
            let capabilities = settings.transport == .sftp ? nil : try self.adapter.capabilities(cancellation: context)
            let plan = try HistoryRemoteDeletionPlan(url: url, binding: binding, settings: settings, capabilities: capabilities, sftpAvailable: PublishingTransfer.sftpAvailable)
            let command: HistoryRemoteDeletionCommand
            var password = ""
            if let sftp = plan.publishing.keyedSFTP {
                guard binding.sshFingerprint == (try self.adapter.sshSourceFingerprint()) else { throw PublishingFailure("The SSH destination configuration changed. Remote deletion was refused.") }
                let ssh = try self.adapter.inspectSSH(sftp, cancellation: context)
                let quoted = try PublishingSFTPPlan.batchQuote(sftp.remotePath)
                command = HistoryRemoteDeletionCommand(executable: "/usr/bin/sftp", arguments: ssh.deletionArguments(sftp),
                                                      // pwd supplies an observable completion after rm. Without it,
                                                      // an early EOF/failed stdin write could otherwise look like exit 0.
                                                      input: Data(("@rm " + quoted + "\n@pwd\n@bye\n").utf8), timeout: 30, allowsSSHAgent: true)
            } else {
                guard binding.sshFingerprint == nil else { throw PublishingFailure("This binding is not a WebDAV destination.") }
                if !settings.username.isEmpty { password = try self.adapter.password(credentialID: settings.credentialID) }
                command = HistoryRemoteDeletionCommand(executable: "/usr/bin/curl", arguments: ["--disable", "--config", "-"],
                                                      input: try plan.webDAVConfig(username: settings.username, password: password), timeout: 30, allowsSSHAgent: false)
            }
            // Credentials and alias resolution can take time. Recheck config at the mutation boundary.
            try context.check()
            guard settings == (try self.adapter.loadSettings()) else { throw PublishingFailure("Publishing settings changed before remote deletion. Nothing was deleted.") }
            if settings.transport == .sftp {
                guard binding.sshFingerprint == (try self.adapter.sshSourceFingerprint()) else { throw PublishingFailure("SSH configuration changed before remote deletion. Nothing was deleted.") }
            }
            let output: PublishingProcess.Output
            do { output = try self.adapter.execute(command, cancellation: context) }
            catch { try context.check(); throw PublishingFailure("Remote deletion could not be completed within its bounded process lifetime. Its remote state is unknown.") }
            try context.check()
            if plan.publishing.transport == .sftp {
                guard output.code == 0,
                      output.stdout.components(separatedBy: "\n").contains(where: {
                          $0.hasPrefix("Remote working directory: /") && !PublishingPlan.hasControls($0)
                      }) else {
                    // Alias-derived usernames/key paths can appear in SSH stderr. Do not display it.
                    throw PublishingFailure("SFTP did not confirm removal of the file. Its remote state is unknown.")
                }
            } else { try plan.verifyWebDAV(output, username: settings.username, password: password) }
        }) { result in self.busy = false; completion(result) }
    }

    /// Uses the publisher's modal-safe delivery and process-group cancellation/cleanup.
    public func shutdown(completion: @escaping (Result<Void, Error>) -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.shutdown(completion: completion) }; return }
        work.stop(shutdown: true, completion: completion)
    }
}
