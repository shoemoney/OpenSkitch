import AppKit
import Security
import Darwin
import CoreFoundation

// Reconstructs the original WebpostFTP/WebpostSFTP/WebpostWebDAV destinations.
// No Evernote account API, background publishing, or credential-bearing argv.
enum PublishingProtocol: String, Codable, CaseIterable {
    case webDAV, ftp, ftps, sftp

    var title: String {
        switch self {
        case .webDAV: return "WebDAV / HTTP PUT"
        case .ftp: return "FTP"
        case .ftps: return "FTPS (TLS required)"
        case .sftp: return "SFTP (SSH config / agent keys)"
        }
    }
    var schemes: Set<String> {
        switch self {
        case .webDAV: return ["http", "https"]
        case .ftp: return ["ftp"]
        case .ftps: return ["ftp", "ftps"] // Explicit TLS and implicit TLS, respectively.
        case .sftp: return ["sftp"]
        }
    }
}

struct PublishingSettings: Codable, Equatable {
    var endpoint = ""
    var transport: PublishingProtocol = .webDAV
    var username = ""
    var remoteFolder = ""
    // Maps directly to remoteFolder; only the filename is appended to this URL.
    var publicBaseURL = ""
    var credentialID = UUID().uuidString
    var sshAlias = ""
    var sftpRemoteRoot = ""
    var sftpPort: Int?

    init() {}
    private enum CodingKeys: String, CodingKey {
        case endpoint, transport, username, remoteFolder, publicBaseURL, credentialID
        case sshAlias, sftpRemoteRoot, sftpPort
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        transport = try c.decodeIfPresent(PublishingProtocol.self, forKey: .transport) ?? .webDAV
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        remoteFolder = try c.decodeIfPresent(String.self, forKey: .remoteFolder) ?? ""
        publicBaseURL = try c.decodeIfPresent(String.self, forKey: .publicBaseURL) ?? ""
        credentialID = try c.decodeIfPresent(String.self, forKey: .credentialID) ?? UUID().uuidString
        sshAlias = try c.decodeIfPresent(String.self, forKey: .sshAlias) ?? ""
        sftpRemoteRoot = try c.decodeIfPresent(String.self, forKey: .sftpRemoteRoot) ?? ""
        sftpPort = try c.decodeIfPresent(Int.self, forKey: .sftpPort)
    }
}

struct PublishingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct PublishingCapabilities {
    let protocols: Set<String>
    let hasTLS: Bool

    init(versionOutput: String) throws {
        let lines = versionOutput.components(separatedBy: .newlines)
        guard lines.first?.hasPrefix("curl ") == true,
              let line = lines.first(where: { $0.hasPrefix("Protocols: ") }) else {
            throw PublishingFailure("System curl did not report its supported protocols.")
        }
        protocols = Set(line.dropFirst("Protocols: ".count).split(separator: " ").map(String.init))
        hasTLS = lines.first(where: { $0.hasPrefix("Features: ") })?
            .split(separator: " ").contains("SSL") == true
    }

    func validate(_ transport: PublishingProtocol, scheme: String) throws {
        guard transport.schemes.contains(scheme), protocols.contains(scheme),
              transport != .ftps || hasTLS else {
            throw PublishingFailure("System /usr/bin/curl does not support this destination's protocol or required TLS.")
        }
    }
}

struct PublishingPlan {
    let remoteURL: URL
    let publicURL: URL?
    let transport: PublishingProtocol
    let keyedSFTP: PublishingSFTPPlan?

    init(settings: PublishingSettings, fileName: String, capabilities: PublishingCapabilities?, sftpAvailable: Bool = false) throws {
        try Self.validateUsername(settings.username)
        let folders = settings.remoteFolder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for folder in folders { try Self.validateComponent(folder) }
        try Self.validateComponent(fileName)
        if settings.transport == .sftp {
            guard sftpAvailable else { throw PublishingFailure("System /usr/bin/sftp and /usr/bin/ssh are required for keyed SFTP publishing.") }
            let sftp = try PublishingSFTPPlan(settings: settings, fileName: fileName)
            keyedSFTP = sftp; remoteURL = sftp.remoteURL
        } else {
            let base = try Self.baseURL(settings.endpoint, schemes: settings.transport.schemes)
            guard let capabilities else { throw PublishingFailure("System curl capabilities are unavailable.") }
            try capabilities.validate(settings.transport, scheme: base.scheme!.lowercased())
            remoteURL = try Self.appending(folders + [fileName], to: base)
            keyedSFTP = nil
        }
        if settings.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            publicURL = nil
        } else {
            let publicBase = try Self.baseURL(settings.publicBaseURL, schemes: ["http", "https"])
            publicURL = try Self.appending([fileName], to: publicBase)
        }
        transport = settings.transport
    }

    static func validateUsername(_ username: String) throws {
        guard !username.contains(":"), !hasControls(username), username.utf8.count <= 4096 else {
            throw PublishingFailure("Username cannot contain a colon or control characters and must be at most 4096 bytes.")
        }
    }

    static func hasControls(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func validateComponent(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"),
              !value.contains("\\"), !hasControls(value), value.utf8.count <= 4096 else {
            throw PublishingFailure("Filename and folder components must be nonempty, contain no separators or control characters, and cannot be . or ...")
        }
    }

    static func baseURL(_ text: String, schemes: Set<String>) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasControls(text), !text.contains("\\"), text.utf8.count <= 16384,
              var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), schemes.contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              let decodedPath = parts.percentEncodedPath.removingPercentEncoding,
              !hasControls(decodedPath), !decodedPath.contains("\\") else {
            throw PublishingFailure("Enter a complete endpoint URL with the matching scheme and host, without embedded credentials, query, or fragment.")
        }
        // Decode once, reject hidden separators/traversal, then canonicalize each component.
        guard !parts.percentEncodedPath.lowercased().contains("%2f") else {
            throw PublishingFailure("Endpoint paths cannot contain encoded separators.")
        }
        let path = decodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in path { try validateComponent(component) }
        parts.scheme = scheme
        parts.percentEncodedPath = path.isEmpty ? "" : "/" + path.map(escapePathComponent).joined(separator: "/")
        guard let url = parts.url else { throw PublishingFailure("The destination URL is invalid.") }
        return url
    }

    static func escapePathComponent(_ value: String) -> String {
        // ASCII unreserved only; percent signs, ?, #, ;, quotes and UTF-8 are encoded.
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                || [45, 46, 95, 126].contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    static func appending(_ components: [String], to base: URL) throws -> URL {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw PublishingFailure("The destination URL is invalid.")
        }
        parts.percentEncodedPath += "/" + components.map(escapePathComponent).joined(separator: "/")
        guard let url = parts.url else { throw PublishingFailure("The composed file URL is invalid.") }
        return url
    }

    static func configQuote(_ text: String) throws -> String {
        guard !text.contains("\0"), text.utf8.count <= 16384 else {
            throw PublishingFailure("A publishing field contains a null byte or is too long.")
        }
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{0B}", with: "\\v")
        guard !escaped.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else { throw PublishingFailure("Unsupported control character in a publishing field.") }
        return "\"" + escaped + "\""
    }

    func curlConfig(file: URL, username: String, password: String) throws -> Data {
        guard transport != .sftp else { throw PublishingFailure("Keyed SFTP must use /usr/bin/sftp, never curl.") }
        try Self.validateUsername(username)
        guard !username.isEmpty || password.isEmpty else {
            throw PublishingFailure("A password requires a username.")
        }
        var lines = ["silent", "show-error", "globoff", "path-as-is", "connect-timeout = 15",
                     "max-time = 120", "retry = 0", "output = \"/dev/null\"",
                     "proto = " + (try Self.configQuote("=" + remoteURL.scheme!)),
                     "url = " + (try Self.configQuote(remoteURL.absoluteString)),
                     "upload-file = " + (try Self.configQuote(file.path)),
                     // No response body, headers, credentials, redirects, or remote tokens in stdout.
                     "write-out = \"%{response_code}\\n%{url_effective}\\n%{size_upload}\\n\""]
        if !username.isEmpty { lines.append("user = " + (try Self.configQuote(username + ":" + password))) }
        if transport == .webDAV { lines += ["request = \"PUT\"", "fail", "header = \"Content-Type: application/octet-stream\""] }
        if transport == .ftps { lines.append("ssl-reqd") }
        if transport == .ftp || transport == .ftps { lines.append("ftp-skip-pasv-ip") }
        // Existing remote folders only: never create a directory, follow a redirect, or retry an upload.
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func sanitized(_ stderr: String, username: String, password: String) -> String {
        // Redact URL userinfo and query/fragment tokens even if returned by a server.
        var text = stderr
        for pattern in [#"(?i)([a-z][a-z0-9+.-]*://)[^\s/]*@"#,
                        #"(?i)[a-z0-9_.-]+@[^\s:]+"#,
                        #"(?i)([a-z][a-z0-9+.-]*://[^\s?#]+)[?#][^\s]*"#,
                        #"(?im)(authorization|proxy-authorization|password|token|secret)\s*[:=].*$"#] {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                text = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
            }
        }
        let secrets = [username, password].filter { !$0.isEmpty }.flatMap { value -> [String] in
            [value, escapePathComponent(value), value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value,
             (try? configQuote(value))?.dropFirst().dropLast().description ?? value,
             Data(value.utf8).base64EncodedString()]
        } + (!username.isEmpty ? [Data((username + ":" + password).utf8).base64EncodedString()] : [])
        // Use one pass so a later short secret cannot undo an earlier redaction.
        let alternatives = Set(secrets).sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        if !alternatives.isEmpty, let expression = try? NSRegularExpression(pattern: alternatives.joined(separator: "|"), options: .caseInsensitive) {
            text = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
        }
        text = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }.map(String.init).joined()
        // Truncate after redaction so no partial secret is left at the display boundary.
        return String(text.prefix(1500)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func verifiedResult(stdout: String, exitCode: Int32, stderr: String, byteCount: Int,
                        username: String, password: String) throws -> URL {
        guard exitCode == 0 else {
            let detail = Self.sanitized(stderr, username: username, password: password)
            throw PublishingFailure("Upload failed (curl \(exitCode))." + (detail.isEmpty ? "" : "\n" + detail))
        }
        let lines = stdout.components(separatedBy: "\n")
        guard lines.count == 4, lines.last == "", lines[0].count == 3,
              let code = Int(lines[0]), !lines[1].isEmpty,
              let effective = URL(string: lines[1]), effective == remoteURL,
              let uploaded = Double(lines[2]), uploaded.isFinite, uploaded == Double(byteCount) else {
            throw PublishingFailure("Curl did not return a complete, matching file URL and uploaded byte count. Upload success could not be verified.")
        }
        switch transport {
        case .webDAV:
            guard [200, 201, 204].contains(code) else {
                throw PublishingFailure("HTTP PUT returned status \(code); a completed upload was not confirmed.")
            }
        case .ftp, .ftps:
            guard [226, 250].contains(code) else {
                throw PublishingFailure("FTP returned status \(code); a completed upload was not confirmed.")
            }
        case .sftp:
            throw PublishingFailure("SFTP success requires a verified download through /usr/bin/sftp.")
        }
        return publicURL ?? effective
    }
}

struct PublishingSFTPPlan {
    let target: String
    let port: Int?
    let username: String
    let remotePath: String
    let remoteURL: URL

    init(settings: PublishingSettings, fileName: String) throws {
        let alias = settings.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.endpoint.isEmpty ? nil : try PublishingPlan.baseURL(settings.endpoint, schemes: ["sftp"])
        if !alias.isEmpty {
            guard alias.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"#, options: .regularExpression) != nil else {
                throw PublishingFailure("SSH alias must be a plain host alias from ~/.ssh/config, without quotes, spaces, user@, paths, or options.")
            }
            target = alias
        } else {
            guard let endpoint, let host = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.host else {
                throw PublishingFailure("Enter an SSH host alias or a complete sftp:// endpoint.")
            }
            guard host.range(of: #"^[A-Za-z0-9.\[\]:_-]+$"#, options: .regularExpression) != nil,
                  !host.hasPrefix("-") else { throw PublishingFailure("The SFTP hostname is invalid.") }
            target = host.contains(":") && !host.hasPrefix("[") ? "[" + host + "]" : host
        }
        port = settings.sftpPort ?? endpoint.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.port }
        guard port == nil || (1...65535).contains(port!) else { throw PublishingFailure("SFTP port must be between 1 and 65535.") }
        username = settings.username
        guard username.isEmpty || username.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_.-]*\$?$"#, options: .regularExpression) != nil else {
            throw PublishingFailure("SFTP username must be a plain SSH login name; leave it empty to use the alias configuration.")
        }
        let root = settings.sftpRemoteRoot.isEmpty ? (endpoint?.path ?? "") : settings.sftpRemoteRoot
        guard root.hasPrefix("/") else { throw PublishingFailure("Set an absolute SFTP remote root, or include the directory in the endpoint URL.") }
        let components = root.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            + settings.remoteFolder.split(separator: "/", omittingEmptySubsequences: true).map(String.init) + [fileName]
        for component in components { try PublishingPlan.validateComponent(component) }
        remotePath = "/" + components.joined(separator: "/")
        _ = try Self.batchQuote(remotePath)
        var parts = URLComponents(); parts.scheme = "sftp"; parts.host = target; parts.port = port
        parts.percentEncodedPath = "/" + components.map(PublishingPlan.escapePathComponent).joined(separator: "/")
        guard let url = parts.url else { throw PublishingFailure("The remote SFTP file location is invalid.") }
        remoteURL = url
    }

    var arguments: [String] {
        var args = ["-q", "-b", "-", "-S", "/usr/bin/ssh"]
        for option in ["BatchMode=yes", "StrictHostKeyChecking=yes", "NoHostAuthenticationForLocalhost=no",
                       "UpdateHostKeys=no", "PasswordAuthentication=no", "KbdInteractiveAuthentication=no",
                       "PreferredAuthentications=publickey", "ConnectTimeout=15", "ConnectionAttempts=1",
                       "ServerAliveInterval=15", "ServerAliveCountMax=2", "ForwardAgent=no",
                       "ClearAllForwardings=yes", "PermitLocalCommand=no", "ControlMaster=no", "ControlPath=none",
                       "ForkAfterAuthentication=no", "RequestTTY=no"] {
            args += ["-o", option]
        }
        if let port { args += ["-P", String(port)] }
        if !username.isEmpty { args += ["-o", "User=" + username] }
        // No -F override: OpenSSH reads ~/.ssh/config, including IdentityFile and HostName.
        return args + [target]
    }

    static func batchQuote(_ path: String) throws -> String {
        // Quotes protect spaces. Reject quote/control injection and all glob metacharacters rather
        // than permit a get command to expand into a different remote filename.
        guard !path.isEmpty, path.utf8.count <= 32768, !PublishingPlan.hasControls(path),
              !path.contains("\\"), !path.contains("\""), !path.contains("'"),
              !path.contains(where: { "*?[]{}".contains($0) }) else {
            throw PublishingFailure("SFTP paths cannot contain quotes, backslashes, control characters, or wildcard characters.")
        }
        return "\"" + path + "\""
    }

    func batch(upload: URL, verification: URL, publicURL: URL? = nil) throws -> Data {
        let source = try Self.batchQuote(upload.path), destination = try Self.batchQuote(remotePath)
        let downloaded = try Self.batchQuote(verification.path)
        // @ suppresses command echo, but deliberately does NOT suppress command failure.
        // Round-trip verification uses a fresh private local file and checks the exact bytes.
        // Only this uploaded file is changed. Public publication needs nginx-readable bytes;
        // a private upload explicitly remains owner-only, including when overwriting an old file.
        let mode = publicURL == nil ? "0600" : "0644"
        return Data(("@put " + source + " " + destination + "\n@chmod " + mode + " " + destination +
                     "\n@get " + destination + " " + downloaded + "\n@bye\n").utf8)
    }

    func verifiedResult(exitCode: Int32, stderr: String, expected: Data, downloaded: Data?, publicURL: URL?) throws -> URL {
        guard exitCode == 0 else {
            let detail = PublishingPlan.sanitized(stderr, username: username, password: "")
            throw PublishingFailure("SFTP upload or verification failed (\(exitCode))." + (detail.isEmpty ? "" : "\n" + detail))
        }
        guard let downloaded, downloaded == expected else {
            throw PublishingFailure("The SFTP upload could not be verified byte for byte. No public link was copied.")
        }
        return publicURL ?? remoteURL
    }
}

struct PublishingPublicCheck {
    let url: URL
    init(url: URL) throws {
        self.url = try PublishingPlan.baseURL(url.absoluteString, schemes: ["http", "https"])
    }
    func curlConfig(download: URL, byteCount: Int) throws -> Data {
        guard byteCount > 0 else { throw PublishingFailure("There are no published bytes to verify.") }
        let lines = ["silent", "show-error", "fail", "globoff", "path-as-is", "request = \"GET\"",
                     "connect-timeout = 10", "max-time = 30", "retry = 0", "max-redirs = 0",
                     "max-filesize = " + String(byteCount),
                     "proto = " + (try PublishingPlan.configQuote("=" + url.scheme!)),
                     "url = " + (try PublishingPlan.configQuote(url.absoluteString)),
                     "output = " + (try PublishingPlan.configQuote(download.path)),
                     "header = \"Cache-Control: no-cache\"", "header = \"Accept-Encoding: identity\"",
                     "write-out = \"%{response_code}\\n%{url_effective}\\n%{size_download}\\n\""]
        // No user, netrc, cookies, credential headers, proxy, retries or redirect following.
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
    func verifiedResult(stdout: String, exitCode: Int32, stderr: String, expected: Data,
                        downloaded: Data?, username: String = "", password: String = "") throws -> URL {
        guard exitCode == 0 else {
            let detail = PublishingPlan.sanitized(stderr, username: username, password: password)
            throw PublishingFailure("The file uploaded, but its public URL could not be verified (curl \(exitCode)). No link was copied." +
                                    (detail.isEmpty ? "" : "\n" + detail))
        }
        let lines = stdout.components(separatedBy: "\n")
        guard lines.count == 4, lines.last == "", lines[0] == "200",
              !lines[1].isEmpty, URL(string: lines[1]) == url,
              let size = Double(lines[2]), size.isFinite, size == Double(expected.count),
              !expected.isEmpty, let downloaded, downloaded == expected else {
            throw PublishingFailure("The file uploaded, but the public URL did not serve HTTP 200 with the exact image bytes at the configured URL. No link was copied.")
        }
        return url
    }
}

private enum PublishingKeychain {
    private static let service = "SkitchRedux.CustomPublishing"
    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id, kSecAttrSynchronizable as String: false]
    }
    static func read(_ id: String, allowMissing: Bool = false) throws -> String {
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
    static func add(_ value: String, id: String) throws {
        var q = query(id)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PublishingFailure("The publishing password could not be saved to macOS Keychain (\(status)).")
        }
    }
    static func remove(_ id: String) { SecItemDelete(query(id) as CFDictionary) }
}

private enum PublishingStorage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkitchRedux/Publishing", isDirectory: true)
    }
    static var file: URL { directory.appendingPathComponent("destination.json") }
    static var exists: Bool { FileManager.default.fileExists(atPath: file.path) }
    static func load() throws -> PublishingSettings {
        guard exists else { return PublishingSettings() }
        do {
            let settings = try JSONDecoder().decode(PublishingSettings.self, from: Data(contentsOf: file))
            guard UUID(uuidString: settings.credentialID) != nil else { throw PublishingFailure("Invalid credential identifier.") }
            return settings
        } catch { throw PublishingFailure("Publishing settings could not be read. The existing destination has been preserved.") }
    }
    static func save(_ settings: PublishingSettings, password: String) throws {
        let hadPrevious = exists
        let old = try load()
        var next = settings
        next.credentialID = UUID().uuidString
        if next.transport != .sftp { try PublishingKeychain.add(password, id: next.credentialID) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Only delete the new secret if the destination was not committed.
            if next.transport != .sftp, (try? load().credentialID) != next.credentialID { PublishingKeychain.remove(next.credentialID) }
            throw PublishingFailure("Publishing settings could not be saved to Application Support.")
        }
        if hadPrevious, old.transport != .sftp { PublishingKeychain.remove(old.credentialID) }
    }
}

private final class PublishingPipeCapture {
    let pipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var truncated = false
    func drain() {
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            lock.lock()
            if buffer.count + chunk.count <= 65536 { buffer.append(chunk) }
            else { truncated = true; buffer.removeAll() }
            lock.unlock()
        }
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        // Never display a captured prefix cut through a secret.
        return truncated ? "" : String(decoding: buffer, as: UTF8.self)
    }
}

func publishingCancellationError() -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "Publishing was cancelled."])
}

// One context per queued operation. Cancellation is cheap; all waits and file cleanup run on workers.
final class PublishingCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [ObjectIdentifier: PublishingProcessHandle] = [:]
    private var directories: Set<URL> = []
    private let removeDirectory: (URL) throws -> Void

    init(removeDirectory: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.removeDirectory = removeDirectory
    }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func check() throws { if isCancelled { throw publishingCancellationError() } }
    func cancel() {
        lock.lock(); cancelled = true; let handles = Array(processes.values); lock.unlock()
        handles.forEach { $0.requestStop() }
    }
    fileprivate func register(_ handle: PublishingProcessHandle) {
        lock.lock(); processes[ObjectIdentifier(handle)] = handle; let stop = cancelled; lock.unlock()
        if stop { handle.requestStop() }
    }
    fileprivate func unregister(_ handle: PublishingProcessHandle) {
        lock.lock(); processes.removeValue(forKey: ObjectIdentifier(handle)); lock.unlock()
    }
    func makeTemporaryDirectory(prefix: String) throws -> URL {
        try check()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        lock.lock(); directories.insert(url); lock.unlock()
        // A cancellation racing directory creation is still registered for cleanup.
        try check()
        return url
    }
    func cleanup() throws {
        precondition(!Thread.isMainThread, "Publishing cleanup must run off the main thread")
        lock.lock(); let handles = Array(processes.values); lock.unlock()
        for handle in handles { try handle.settle(stopping: true); unregister(handle) }
        lock.lock(); let owned = Array(directories); lock.unlock()
        for url in owned {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try removeDirectory(url) }
            } catch { throw PublishingFailure("Publishing temporary files could not be removed; shutdown is not complete.") }
            lock.lock(); directories.remove(url); lock.unlock()
        }
    }
}

// AppKit's nested quit loop can run inside a main-dispatch block, which prevents that queue
// from draining recursively. One run-loop block (not a polling timer) delivers in ordinary,
// modal/tracking, and the currently active mode; registering multiple modes still runs it once.
enum PublishingMainDelivery {
    static func enqueue(_ body: @escaping () -> Void) {
        let runLoop = CFRunLoopGetMain()!
        var modes: [CFString] = [CFRunLoopMode.commonModes.rawValue, CFRunLoopMode.defaultMode.rawValue,
                                RunLoop.Mode.modalPanel.rawValue as CFString, RunLoop.Mode.eventTracking.rawValue as CFString]
        if let current = CFRunLoopCopyCurrentMode(runLoop) { modes.append(current.rawValue) }
        CFRunLoopPerformBlock(runLoop, modes as CFArray, body)
        CFRunLoopWakeUp(runLoop)
    }
}

// Shared main-thread delivery gate: cancellation also invalidates results already queued for delivery.
final class PublishingWorkController {
    private let queue: DispatchQueue
    private let makeContext: () -> PublishingCancellation
    private var active: [UUID: PublishingCancellation] = [:]
    private var waiters: [(Result<Void, Error>) -> Void] = []
    private var failedCleanup: [UUID: (PublishingCancellation, Error)] = [:]
    private(set) var isShutdown = false
    private var isCancelling = false
    var acceptsWork: Bool { !isShutdown && !isCancelling }

    init(queue: DispatchQueue = .global(qos: .userInitiated),
         makeContext: @escaping () -> PublishingCancellation = { PublishingCancellation() }) {
        self.queue = queue; self.makeContext = makeContext
    }
    @discardableResult
    func start<Value>(work: @escaping (PublishingCancellation) throws -> Value,
                      completion: @escaping (Result<Value, Error>) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        guard acceptsWork else {
            PublishingMainDelivery.enqueue { completion(.failure(publishingCancellationError())) }
            return false
        }
        let id = UUID(), context = makeContext()
        active[id] = context // Register before dispatch so shutdown sees queued work too.
        queue.async {
            var result = Result { try context.check(); return try work(context) }
            var cleanupError: Error?
            do { try context.cleanup() } catch { cleanupError = error; result = .failure(error) }
            let delivered = result, failedCleanup = cleanupError
            PublishingMainDelivery.enqueue {
                self.active.removeValue(forKey: id)
                if let error = failedCleanup { self.failedCleanup[id] = (context, error) }
                if context.isCancelled, failedCleanup == nil { completion(.failure(publishingCancellationError())) }
                else { completion(delivered) }
                self.notifyIfIdle()
            }
        }
        return true
    }
    func stop(shutdown: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        if shutdown { isShutdown = true }
        isCancelling = true; waiters.append(completion)
        // Retain failed resources and retry them on a later shutdown/cancel request. Never report
        // success merely because the operation that owned them already returned an error.
        let retry = failedCleanup; failedCleanup.removeAll()
        for (id, entry) in retry {
            let context = entry.0; active[id] = context
            queue.async {
                let result = Result { try context.cleanup() }
                PublishingMainDelivery.enqueue {
                    self.active.removeValue(forKey: id)
                    if case .failure(let error) = result { self.failedCleanup[id] = (context, error) }
                    self.notifyIfIdle()
                }
            }
        }
        active.values.forEach { $0.cancel() }
        notifyIfIdle()
    }
    private func notifyIfIdle() {
        guard active.isEmpty, !waiters.isEmpty else { return }
        let callbacks = waiters; waiters.removeAll(); isCancelling = !failedCleanup.isEmpty
        let result: Result<Void, Error> = failedCleanup.values.first.map { .failure($0.1) } ?? .success(())
        callbacks.forEach { $0(result) }
    }
}

private final class PublishingProcessHandle {
    let task: Process
    let io = DispatchGroup()
    private let lock = NSLock()
    private let group: pid_t?
    private var closed = false
    init(task: Process) {
        self.task = task
        let pid = task.processIdentifier
        let groupID = getpgid(pid)
        // The parent can exit before registration while a child still holds its process group.
        group = groupID == pid || (groupID == -1 && kill(-pid, 0) == 0) ? pid : nil
    }
    var ownsGroup: Bool { group != nil }
    private func groupAlive() -> Bool {
        guard let group else { return task.isRunning }
        return kill(-group, 0) == 0 || errno == EPERM
    }
    func requestStop() { signal(SIGTERM) }
    private func signal(_ value: Int32) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        if let group { kill(-group, value) }
        else if task.isRunning { kill(task.processIdentifier, value) }
    }
    func settle(stopping: Bool) throws {
        precondition(!Thread.isMainThread)
        if stopping { requestStop() }
        let grace = Date().addingTimeInterval(1)
        // A helper retaining a pipe is still an active process, even if its parent already exited.
        while task.isRunning || groupAlive() || io.wait(timeout: .now()) == .timedOut {
            if Date() >= grace { signal(SIGKILL); break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning || groupAlive() || io.wait(timeout: .now()) == .timedOut {
            guard Date() < deadline else {
                throw PublishingFailure("A publishing process or helper did not exit; shutdown is not complete.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        task.waitUntilExit()
        lock.lock(); closed = true; lock.unlock()
    }
}

enum PublishingProcess {
    struct Output { let stdout: String; let stderr: String; let code: Int32 }
    static func run(executable: String, arguments: [String], input: Data? = nil,
                    timeout: TimeInterval, allowSSHAgent: Bool = false,
                    cancellation: PublishingCancellation = PublishingCancellation()) throws -> Output {
        precondition(!Thread.isMainThread, "Publishing processes must run off the main thread")
        try cancellation.check()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        // Ignore inherited proxy/auth/config variables. System trust and SSH known_hosts remain enabled.
        task.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        if allowSSHAgent {
            if let socket = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                task.environment?["SSH_AUTH_SOCK"] = socket
            }
            task.environment?["SSH_ASKPASS_REQUIRE"] = "never"
        }
        let stdin = Pipe(), stdout = PublishingPipeCapture(), stderr = PublishingPipeCapture()
        task.standardInput = stdin; task.standardOutput = stdout.pipe; task.standardError = stderr.pipe
        do { try task.run() } catch { throw PublishingFailure("System publishing tool could not be launched.") }
        // Foundation gives a launched task its own process group on macOS. Check before using it:
        // terminating SFTP must also stop its SSH child, rather than leave an upload running.
        let handle = PublishingProcessHandle(task: task)
        cancellation.register(handle)
        for capture in [stdout, stderr] {
            handle.io.enter()
            DispatchQueue.global(qos: .utility).async { capture.drain(); handle.io.leave() }
        }
        // Input may contain credentials. It is never written to disk or passed as an argument.
        handle.io.enter()
        DispatchQueue.global(qos: .utility).async {
            if !cancellation.isCancelled, let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
            try? stdin.fileHandleForWriting.close()
            handle.io.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && !cancellation.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let timedOut = task.isRunning && Date() >= deadline
        let unisolatedSSH = allowSSHAgent && !handle.ownsGroup
        try handle.settle(stopping: cancellation.isCancelled || timedOut || unisolatedSSH)
        cancellation.unregister(handle)
        try cancellation.check()
        guard !unisolatedSSH else { throw PublishingFailure("SFTP could not be isolated for bounded process termination.") }
        guard !timedOut else { throw PublishingFailure("The upload timed out. Its remote state is unknown; verify the destination before retrying.") }
        return Output(stdout: stdout.text, stderr: stderr.text, code: task.terminationStatus)
    }
}

private enum PublishingCurl {
    static func capabilities(cancellation: PublishingCancellation = PublishingCancellation()) throws -> PublishingCapabilities {
        let output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--version"], timeout: 5, cancellation: cancellation)
        guard output.code == 0 else { throw PublishingFailure("System curl capabilities could not be inspected.") }
        return try PublishingCapabilities(versionOutput: output.stdout)
    }
    static func upload(data: Data, plan: PublishingPlan, username: String, password: String, cancellation: PublishingCancellation) throws -> URL {
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchPublish-") }
        catch { throw PublishingFailure("A private temporary upload folder could not be created.") }
        let file = directory.appendingPathComponent("image")
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw PublishingFailure("The image could not be prepared for upload.") }
        let config = try plan.curlConfig(file: file, username: username, password: password)
        // --disable MUST come first: no ~/.curlrc, .netrc, redirects or verbose tracing.
        let output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--config", "-"], input: config, timeout: 125, cancellation: cancellation)
        return try plan.verifiedResult(stdout: output.stdout, exitCode: output.code, stderr: output.stderr,
                                       byteCount: data.count, username: username, password: password)
    }
}

private enum PublishingSFTP {
    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/sftp") && FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh")
    }
    static func upload(data: Data, plan: PublishingPlan, cancellation: PublishingCancellation) throws -> URL {
        guard available, let sftp = plan.keyedSFTP else { throw PublishingFailure("The keyed SFTP backend is unavailable.") }
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchSFTP-") }
        catch { throw PublishingFailure("A private SFTP verification folder could not be created.") }
        let source = directory.appendingPathComponent("image"), verification = directory.appendingPathComponent("verified-image")
        do {
            try data.write(to: source, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        } catch { throw PublishingFailure("The image could not be prepared for SFTP.") }
        let batch = try sftp.batch(upload: source, verification: verification, publicURL: plan.publicURL)
        let output = try PublishingProcess.run(executable: "/usr/bin/sftp", arguments: sftp.arguments,
                                              input: batch, timeout: 125, allowSSHAgent: true, cancellation: cancellation)
        let downloaded = try? Data(contentsOf: verification, options: .mappedIfSafe)
        return try sftp.verifiedResult(exitCode: output.code, stderr: output.stderr, expected: data,
                                      downloaded: downloaded, publicURL: plan.publicURL)
    }
}

// Module-internal entry point for the explicitly requested --live-sftp integration check.
// Production calls this only after the coordinator's Publish button is clicked.
enum PublishingTransfer {
    static var sftpAvailable: Bool { PublishingSFTP.available }
    static func upload(data: Data, plan: PublishingPlan, username: String = "", password: String = "",
                       cancellation: PublishingCancellation = PublishingCancellation()) throws -> URL {
        precondition(!Thread.isMainThread)
        let result = Result { try performUpload(data: data, plan: plan, username: username, password: password, cancellation: cancellation) }
        try cancellation.cleanup()
        try cancellation.check()
        return try result.get()
    }
    private static func performUpload(data: Data, plan: PublishingPlan, username: String, password: String,
                                      cancellation: PublishingCancellation) throws -> URL {
        try cancellation.check()
        guard !data.isEmpty else { throw PublishingFailure("There is no image data to upload.") }
        let uploaded: URL
        if plan.transport == .sftp { uploaded = try PublishingSFTP.upload(data: data, plan: plan, cancellation: cancellation) }
        else { uploaded = try PublishingCurl.upload(data: data, plan: plan, username: username, password: password, cancellation: cancellation) }
        try cancellation.check()
        guard let publicURL = plan.publicURL else { return uploaded }
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchPublicCheck-") }
        catch { throw PublishingFailure("The file uploaded, but a private public-URL verification folder could not be created. No link was copied.") }
        let download = directory.appendingPathComponent("public-image")
        let check = try PublishingPublicCheck(url: publicURL)
        let config = try check.curlConfig(download: download, byteCount: data.count)
        let output: PublishingProcess.Output
        do {
            output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--config", "-"], input: config, timeout: 35, cancellation: cancellation)
        } catch { throw PublishingFailure("The file uploaded, but public URL verification failed or timed out. No link was copied.") }
        let downloaded = try? Data(contentsOf: download, options: .mappedIfSafe)
        return try check.verifiedResult(stdout: output.stdout, exitCode: output.code, stderr: output.stderr,
                                       expected: data, downloaded: downloaded, username: username, password: password)
    }
}

public final class PublishingCoordinator: NSObject {
    private let workController: PublishingWorkController
    var clipboardWriter: (URL) -> Void
    private var isShuttingDown = false
    private var isCancellationPending = false
    private var isPreparingPublish = false
    private var transferActive = false
    private var endingSheets: Set<ObjectIdentifier> = []
    private var quiescenceResult: Result<Void, Error>?
    private var quiescenceCallbacks: [(Result<Void, Error>) -> Void] = []
    private var successfulQuiescenceCallbacks: [() -> Void] = []
    private var settingsPanel: NSPanel?
    private var endpointField: NSTextField?
    private var protocolField: NSPopUpButton?
    private var usernameField: NSTextField?
    private var passwordField: NSSecureTextField?
    private var folderField: NSTextField?
    private var publicField: NSTextField?
    private var aliasField: NSTextField?
    private var remoteRootField: NSTextField?
    private var portField: NSTextField?
    private var settingsStatus: NSTextField?
    private var savedSettings = PublishingSettings()
    private var pendingCompletion: ((Result<URL, Error>) -> Void)?
    /// True when the last successful transfer wrote its verified public URL to the clipboard.
    private(set) var lastTransferCopiedLink = false
    // Seams for tests: destination lookup and the network transfer itself.
    var settingsLoader: () throws -> PublishingSettings = { try PublishingStorage.load() }
    var uploader: (Data, PublishingSettings, PublishingPlan, PublishingCancellation) throws -> URL = PublishingCoordinator.realUploader

    public override init() {
        workController = PublishingWorkController()
        clipboardWriter = { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
        super.init()
    }
    // Dependency injection exercises the production completion/clipboard gate without UI or uploads.
    init(workController: PublishingWorkController, clipboardWriter: @escaping (URL) -> Void) {
        self.workController = workController; self.clipboardWriter = clipboardWriter
        super.init()
    }

    /// Permanently rejects new publishing. On main, an idle publisher acknowledges synchronously;
    /// otherwise completion runs on main after worker exit, cleanup, and sheet dismissal.
    /// This acknowledgement is successful cleanup only; use the result overload to report failures.
    public func shutdown(completion: @escaping () -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.shutdown(completion: completion) }; return }
        successfulQuiescenceCallbacks.append(completion)
        shutdown { (_: Result<Void, Error>) in }
    }
    public func cancelPublishing(completion: @escaping () -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.cancelPublishing(completion: completion) }; return }
        successfulQuiescenceCallbacks.append(completion)
        cancelPublishing { (_: Result<Void, Error>) in }
    }
    /// Permanently rejects new publishing. Completion is on main, after worker exit,
    /// helper/pipe exit, owned temporary-file cleanup, and sheet dismissal. On failure, do not quit.
    public func shutdown(completion: @escaping (Result<Void, Error>) -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.shutdown(completion: completion) }; return }
        isShuttingDown = true
        cancelSettings()
        requestCancellation(shutdown: true, completion: completion)
    }
    /// Cancels queued/running publishing and waits for the same cleanup. New publishing becomes
    /// available after successful cancellation; shutdown remains permanent.
    public func cancelPublishing(completion: @escaping (Result<Void, Error>) -> Void) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.cancelPublishing(completion: completion) }; return }
        requestCancellation(shutdown: false, completion: completion)
    }
    private func requestCancellation(shutdown: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        isCancellationPending = true; quiescenceResult = nil; quiescenceCallbacks.append(completion)
        workController.stop(shutdown: shutdown) { result in
            self.quiescenceResult = result; self.flushQuiescenceCallbacks()
        }
    }
    private func flushQuiescenceCallbacks() {
        guard let result = quiescenceResult, endingSheets.isEmpty else { return }
        quiescenceResult = nil
        let callbacks = quiescenceCallbacks; quiescenceCallbacks.removeAll()
        // A cleanup failure continues to block new work until the parent resolves it.
        var successfulCallbacks: [() -> Void] = []
        if case .success = result {
            isCancellationPending = false
            successfulCallbacks = successfulQuiescenceCallbacks
            successfulQuiescenceCallbacks.removeAll()
        }
        callbacks.forEach { $0(result) }
        // Keep void acknowledgements pending across a failed cleanup; a successful retry delivers
        // every invocation once. A failure must never tell the parent it is safe to terminate.
        successfulCallbacks.forEach { $0() }
    }
    private func beginSheet(_ panel: NSPanel, relativeTo window: NSWindow) {
        window.beginSheet(panel) { [self] _ in
            panel.orderOut(nil)
            endingSheets.remove(ObjectIdentifier(panel))
            flushQuiescenceCallbacks()
        }
    }
    private func dismissSheet(_ panel: NSPanel) {
        if let parent = panel.sheetParent {
            endingSheets.insert(ObjectIdentifier(panel))
            parent.endSheet(panel)
        } else { panel.orderOut(nil) }
    }

    public static var settingsFileURL: URL { PublishingStorage.file }

    /// Settings never start a network request. Passwords are saved only in macOS Keychain.
    public func showSettings(relativeTo window: NSWindow) {
        if !Thread.isMainThread { PublishingMainDelivery.enqueue { self.showSettings(relativeTo: window) }; return }
        guard !isShuttingDown, !isCancellationPending, !isPreparingPublish, workController.acceptsWork else { return }
        if let panel = settingsPanel { panel.makeKeyAndOrderFront(nil); return }
        guard window.attachedSheet == nil else { return }
        do {
            savedSettings = try settingsLoader()
            let password = savedSettings.transport == .sftp ? "" : try PublishingKeychain.read(savedSettings.credentialID, allowMissing: !PublishingStorage.exists)
            let panel = makePanel(title: "Custom Publishing Settings", width: 800, height: 800)
            let form = verticalStack()
            form.spacing = 14
            let endpoint = field(savedSettings.endpoint, placeholder: "https://example.com/uploads")
            let transport = NSPopUpButton(frame: .zero, pullsDown: false)
            transport.font = .systemFont(ofSize: 18)
            transport.menu?.font = .systemFont(ofSize: 18)
            transport.menu?.autoenablesItems = false
            transport.addItems(withTitles: PublishingProtocol.allCases.map(\.title))
            transport.selectItem(at: PublishingProtocol.allCases.firstIndex(of: savedSettings.transport) ?? 0)
            transport.target = self; transport.action = #selector(protocolChanged)
            let username = field(savedSettings.username, placeholder: "Username (optional for anonymous destinations)")
            let secret = NSSecureTextField(string: password); secret.font = .systemFont(ofSize: 20)
            secret.placeholderString = "Password stored in macOS Keychain"
            let folder = field(savedSettings.remoteFolder, placeholder: "screenshots (relative to endpoint)")
            let publicURL = field(savedSettings.publicBaseURL, placeholder: "https://example.com/screenshots (optional)")
            let alias = field(savedSettings.sshAlias, placeholder: "shoemoney.com (from ~/.ssh/config)")
            let remoteRoot = field(savedSettings.sftpRemoteRoot, placeholder: "/var/www/shoemoney.com/shared/imgs")
            let port = field(savedSettings.sftpPort.map(String.init) ?? "", placeholder: "Use SSH configuration (optional)")
            for (title, control) in [("Endpoint URL", endpoint as NSView), ("Protocol", transport),
                                     ("Username", username), ("Password", secret),
                                     ("Remote folder", folder), ("Public base URL", publicURL),
                                     ("SSH host alias", alias), ("SFTP remote root", remoteRoot), ("SFTP port", port)] {
                let row = NSStackView(views: [label(title), control]); row.orientation = .horizontal
                row.alignment = .centerY; row.spacing = 16
                row.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 165).isActive = true
                control.widthAnchor.constraint(greaterThanOrEqualToConstant: 450).isActive = true
                control.setAccessibilityLabel(title)
                form.addArrangedSubview(row)
            }
            let help = label("SFTP uses keys from SSH configuration or your agent, with strict known-host checks. Leave username and port empty to use the alias settings; no password is used. FTPS: ftp:// is explicit TLS, ftps:// is implicit TLS. Folders must exist. Public base URL maps to the upload folder; only the filename is appended.")
            help.maximumNumberOfLines = 0; help.preferredMaxLayoutWidth = 720
            form.addArrangedSubview(help)
            let status = label("Checking publishing tools…"); status.maximumNumberOfLines = 0; status.preferredMaxLayoutWidth = 720
            form.addArrangedSubview(status)
            form.addArrangedSubview(buttonRow([button("Cancel", #selector(cancelSettings)), button("Save", #selector(saveSettings))]))
            install(form, in: panel)
            endpointField = endpoint; protocolField = transport; usernameField = username; passwordField = secret
            folderField = folder; publicField = publicURL; settingsStatus = status; settingsPanel = panel
            aliasField = alias; remoteRootField = remoteRoot; portField = port; protocolChanged()
            beginSheet(panel, relativeTo: window)
            workController.start(work: { try PublishingCurl.capabilities(cancellation: $0) }) { result in
                    guard self.settingsPanel === panel else { return }
                    switch result {
                    case .success(let capabilities):
                        let missing = PublishingProtocol.allCases.filter { transport in
                            if transport == .sftp { return !PublishingSFTP.available }
                            return !transport.schemes.contains(where: { scheme in (try? capabilities.validate(transport, scheme: scheme)) != nil })
                        }
                        status.stringValue = missing.isEmpty ? "SFTP uses /usr/bin/sftp; other protocols use system curl." : "Unavailable: " + missing.map(\.title).joined(separator: ", ") + "."
                        for (index, transport) in PublishingProtocol.allCases.enumerated() {
                            self.protocolField?.item(at: index)?.isEnabled = !missing.contains(transport)
                        }
                    case .failure: status.stringValue = PublishingSFTP.available ? "Keyed SFTP is available; system curl is unavailable for other protocols." : "Publishing tools are unavailable."
                    }
            }
        } catch { presentMessage(error.localizedDescription, relativeTo: window) }
    }

    /// True while a plan is being prepared or a transfer is running; a second upload is not queued.
    var isBusy: Bool { isPreparingPublish || transferActive }
    /// Menu title of the saved destination, or nil when none is configured.
    var destinationTitle: String? {
        guard isConfigured, let settings = try? settingsLoader() else { return nil }
        let alias = settings.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? settings.endpoint
        return (settings.transport == .sftp ? "SFTP" : settings.transport.title) + " · " + (alias.isEmpty || settings.transport != .sftp ? host : alias)
    }
    /// Whether a destination is saved with enough detail to attempt an upload.
    var isConfigured: Bool {
        guard let settings = try? settingsLoader() else { return false }
        func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return settings.transport == .sftp ? !(blank(settings.sshAlias) && blank(settings.endpoint)) : !blank(settings.endpoint)
    }

    /// Uploads straight away with no confirmation and no sheet; the caller shows progress.
    /// Success returns the configured public URL, or the verified remote URL for status only.
    /// Only a configured public URL is copied (see `lastTransferCopiedLink`). Completion always runs on the main thread.
    /// Callers must not copy the completion URL unconditionally; this coordinator owns clipboard policy.
    public func publish(data: Data, fileName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        if !Thread.isMainThread {
            PublishingMainDelivery.enqueue { self.publish(data: data, fileName: fileName, completion: completion) }; return
        }
        guard !isShuttingDown, !isCancellationPending, workController.acceptsWork else {
            completion(.failure(publishingCancellationError())); return
        }
        guard !isPreparingPublish, !transferActive else {
            completion(.failure(PublishingFailure("An upload is already running."))); return
        }
        guard settingsPanel == nil else {
            completion(.failure(PublishingFailure("Close the sharing settings before publishing."))); return
        }
        do {
            guard !data.isEmpty else { throw PublishingFailure("There is no image data to upload.") }
            let settings = try settingsLoader()
            isPreparingPublish = true
            workController.start(work: { context in
                let capabilities = settings.transport == .sftp ? nil : try PublishingCurl.capabilities(cancellation: context)
                return try PublishingPlan(settings: settings, fileName: fileName, capabilities: capabilities, sftpAvailable: PublishingSFTP.available)
            }) { result in
                self.isPreparingPublish = false
                switch result {
                case .success(let plan):
                    let upload = self.uploader
                    self.beginTransfer(copiesPublicURL: plan.publicURL != nil, work: { context in
                        try context.check()
                        return try upload(data, settings, plan, context)
                    }, completion: completion)
                case .failure(let error): completion(.failure(error))
                }
            }
        } catch { completion(.failure(error)) }
    }

    static let realUploader: (Data, PublishingSettings, PublishingPlan, PublishingCancellation) throws -> URL = { data, settings, plan, context in
        if settings.transport == .sftp { return try PublishingTransfer.upload(data: data, plan: plan, cancellation: context) }
        let password = try PublishingKeychain.read(settings.credentialID)
        return try PublishingTransfer.upload(data: data, plan: plan, username: settings.username, password: password, cancellation: context)
    }

    func beginTransfer(copiesPublicURL: Bool, work: @escaping (PublishingCancellation) throws -> URL,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !isShuttingDown, !isCancellationPending, !transferActive, workController.acceptsWork else {
            completion(.failure(publishingCancellationError())); return
        }
        pendingCompletion = completion; transferActive = true; lastTransferCopiedLink = false
        workController.start(work: work) { result in
            self.transferActive = false
            if case .success(let url) = result, copiesPublicURL, !self.isShuttingDown, !self.isCancellationPending {
                self.clipboardWriter(url); self.lastTransferCopiedLink = true
            }
            self.finishPublish(result)
        }
    }

    @objc private func protocolChanged() {
        guard let field = protocolField, field.indexOfSelectedItem >= 0 else { return }
        let sftp = PublishingProtocol.allCases[field.indexOfSelectedItem] == .sftp
        passwordField?.isEnabled = !sftp
        aliasField?.isEnabled = sftp; remoteRootField?.isEnabled = sftp; portField?.isEnabled = sftp
    }
    private func finishPublish(_ result: Result<URL, Error>) {
        let completion = pendingCompletion
        pendingCompletion = nil; completion?(result)
    }
    @objc private func cancelSettings() {
        if let panel = settingsPanel { dismissSheet(panel) }
        settingsPanel = nil; passwordField?.stringValue = ""
        endpointField = nil; protocolField = nil; usernameField = nil; passwordField = nil
        folderField = nil; publicField = nil; settingsStatus = nil
        aliasField = nil; remoteRootField = nil; portField = nil
    }
    @objc private func saveSettings() {
        guard !isShuttingDown, !isCancellationPending else { return }
        guard let transport = protocolField, let secret = passwordField else { return }
        do {
            var settings = savedSettings
            settings.endpoint = endpointField?.stringValue ?? ""
            settings.transport = PublishingProtocol.allCases[transport.indexOfSelectedItem]
            settings.username = usernameField?.stringValue ?? ""
            settings.remoteFolder = folderField?.stringValue ?? ""
            settings.publicBaseURL = publicField?.stringValue ?? ""
            settings.sshAlias = aliasField?.stringValue ?? ""
            settings.sftpRemoteRoot = remoteRootField?.stringValue ?? ""
            let portText = (portField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if portText.isEmpty { settings.sftpPort = nil }
            else {
                guard let port = Int(portText) else { throw PublishingFailure("SFTP port must be a number, or empty to use SSH configuration.") }
                settings.sftpPort = port
            }
            let saved = settings, password = settings.transport == .sftp ? "" : secret.stringValue, panel = settingsPanel
            workController.start(work: { context in
                let capabilities = saved.transport == .sftp ? nil : try PublishingCurl.capabilities(cancellation: context)
                let plan = try PublishingPlan(settings: saved, fileName: "validation.png", capabilities: capabilities, sftpAvailable: PublishingSFTP.available)
                if saved.transport != .sftp { _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/validation"), username: saved.username, password: password) }
                try context.check(); try PublishingStorage.save(saved, password: password)
            }) { result in
                guard self.settingsPanel === panel else { return }
                switch result {
                case .success: self.cancelSettings()
                case .failure(let error): self.settingsStatus?.stringValue = error.localizedDescription
                }
            }
        } catch { settingsStatus?.stringValue = error.localizedDescription }
    }

    private func makePanel(title: String, width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; return panel
    }
    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: 18)
        field.textColor = .labelColor; return field
    }
    private func field(_ text: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: text); field.font = .systemFont(ofSize: 20)
        field.placeholderString = placeholder; return field
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.font = .systemFont(ofSize: 18)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true; return button
    }
    private func buttonRow(_ buttons: [NSButton]) -> NSStackView {
        let stack = NSStackView(views: buttons); stack.orientation = .horizontal; stack.spacing = 16; return stack
    }
    private func verticalStack() -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20; return stack
    }
    private func install(_ form: NSStackView, in panel: NSPanel) {
        guard let content = panel.contentView else { return }
        form.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(form)
        NSLayoutConstraint.activate([form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                                     form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                                     form.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                                     form.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)])
    }
    private func presentMessage(_ message: String, relativeTo window: NSWindow) {
        guard window.attachedSheet == nil else { return }
        let panel = makePanel(title: "Publishing Settings", width: 700, height: 300)
        let form = verticalStack(); let text = label(message); text.preferredMaxLayoutWidth = 640
        form.addArrangedSubview(text); form.addArrangedSubview(button("Close", #selector(cancelSettings)))
        install(form, in: panel); settingsPanel = panel; beginSheet(panel, relativeTo: window)
    }
}
