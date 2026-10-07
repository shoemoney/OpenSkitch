import AppKit
import Security
import Darwin

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

private enum PublishingProcess {
    struct Output { let stdout: String; let stderr: String; let code: Int32 }
    static func run(executable: String, arguments: [String], input: Data? = nil,
                    timeout: TimeInterval, allowSSHAgent: Bool = false) throws -> Output {
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
        let ended = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in ended.signal() }
        do { try task.run() } catch { throw PublishingFailure("System publishing tool could not be launched.") }
        // Foundation gives a launched task its own process group on macOS. Check before using it:
        // terminating SFTP must also stop its SSH child, rather than leave an upload running.
        let ownGroup = getpgid(task.processIdentifier) == task.processIdentifier
        if allowSSHAgent && !ownGroup {
            task.terminate(); try? stdin.fileHandleForWriting.close()
            throw PublishingFailure("SFTP could not be isolated for bounded process termination.")
        }
        let drained = DispatchGroup()
        for capture in [stdout, stderr] {
            drained.enter()
            DispatchQueue.global(qos: .utility).async { capture.drain(); drained.leave() }
        }
        // Input may contain credentials. It is never written to disk or passed as an argument.
        DispatchQueue.global(qos: .utility).async {
            if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
            try? stdin.fileHandleForWriting.close()
        }
        let timedOut = ended.wait(timeout: .now() + timeout) == .timedOut
        if timedOut, task.isRunning {
            if ownGroup { kill(-task.processIdentifier, SIGTERM) } else { task.terminate() }
            if ended.wait(timeout: .now() + 2) == .timedOut, task.isRunning {
                kill(ownGroup ? -task.processIdentifier : task.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 2)
            }
        }
        guard !task.isRunning else { throw PublishingFailure("The publishing tool could not be stopped after the upload deadline.") }
        task.waitUntilExit()
        guard drained.wait(timeout: .now() + 2) == .success else {
            if ownGroup { kill(-task.processIdentifier, SIGKILL) }
            throw PublishingFailure("Publishing output could not be read completely; upload success could not be verified.")
        }
        guard !timedOut else { throw PublishingFailure("The upload timed out. Its remote state is unknown; verify the destination before retrying.") }
        return Output(stdout: stdout.text, stderr: stderr.text, code: task.terminationStatus)
    }
}

private enum PublishingCurl {
    static func capabilities() throws -> PublishingCapabilities {
        let output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--version"], timeout: 5)
        guard output.code == 0 else { throw PublishingFailure("System curl capabilities could not be inspected.") }
        return try PublishingCapabilities(versionOutput: output.stdout)
    }
    static func upload(data: Data, plan: PublishingPlan, username: String, password: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SkitchPublish-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { throw PublishingFailure("A private temporary upload folder could not be created.") }
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("image")
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw PublishingFailure("The image could not be prepared for upload.") }
        let config = try plan.curlConfig(file: file, username: username, password: password)
        // --disable MUST come first: no ~/.curlrc, .netrc, redirects or verbose tracing.
        let output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--config", "-"], input: config, timeout: 125)
        return try plan.verifiedResult(stdout: output.stdout, exitCode: output.code, stderr: output.stderr,
                                       byteCount: data.count, username: username, password: password)
    }
}

private enum PublishingSFTP {
    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/sftp") && FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh")
    }
    static func upload(data: Data, plan: PublishingPlan) throws -> URL {
        guard available, let sftp = plan.keyedSFTP else { throw PublishingFailure("The keyed SFTP backend is unavailable.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SkitchSFTP-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { throw PublishingFailure("A private SFTP verification folder could not be created.") }
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("image"), verification = directory.appendingPathComponent("verified-image")
        do {
            try data.write(to: source, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        } catch { throw PublishingFailure("The image could not be prepared for SFTP.") }
        let batch = try sftp.batch(upload: source, verification: verification, publicURL: plan.publicURL)
        let output = try PublishingProcess.run(executable: "/usr/bin/sftp", arguments: sftp.arguments,
                                              input: batch, timeout: 125, allowSSHAgent: true)
        let downloaded = try? Data(contentsOf: verification, options: .mappedIfSafe)
        return try sftp.verifiedResult(exitCode: output.code, stderr: output.stderr, expected: data,
                                      downloaded: downloaded, publicURL: plan.publicURL)
    }
}

// Module-internal entry point for the explicitly requested --live-sftp integration check.
// Production calls this only after the coordinator's Publish button is clicked.
enum PublishingTransfer {
    static var sftpAvailable: Bool { PublishingSFTP.available }
    static func upload(data: Data, plan: PublishingPlan, username: String = "", password: String = "") throws -> URL {
        guard !data.isEmpty else { throw PublishingFailure("There is no image data to upload.") }
        let uploaded: URL
        if plan.transport == .sftp { uploaded = try PublishingSFTP.upload(data: data, plan: plan) }
        else { uploaded = try PublishingCurl.upload(data: data, plan: plan, username: username, password: password) }
        guard let publicURL = plan.publicURL else { return uploaded }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SkitchPublicCheck-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { throw PublishingFailure("The file uploaded, but a private public-URL verification folder could not be created. No link was copied.") }
        defer { try? FileManager.default.removeItem(at: directory) }
        let download = directory.appendingPathComponent("public-image")
        let check = try PublishingPublicCheck(url: publicURL)
        let config = try check.curlConfig(download: download, byteCount: data.count)
        let output: PublishingProcess.Output
        do {
            output = try PublishingProcess.run(executable: "/usr/bin/curl", arguments: ["--disable", "--config", "-"], input: config, timeout: 35)
        } catch { throw PublishingFailure("The file uploaded, but public URL verification failed or timed out. No link was copied.") }
        let downloaded = try? Data(contentsOf: download, options: .mappedIfSafe)
        return try check.verifiedResult(stdout: output.stdout, exitCode: output.code, stderr: output.stderr,
                                       expected: data, downloaded: downloaded, username: username, password: password)
    }
}

public final class PublishingCoordinator: NSObject {
    private var settingsPanel: NSPanel?
    private var publishPanel: NSPanel?
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
    private var pendingUpload: (() -> Void)?
    private var pendingCompletion: ((Result<URL, Error>) -> Void)?

    public override init() { super.init() }

    public static var settingsFileURL: URL { PublishingStorage.file }

    /// Installs a secret-free keyed-SFTP default only if the user has no destination yet.
    /// No SSH connection, folder creation, upload, or Keychain access occurs here.
    @discardableResult
    public func setDefaultSFTPDestination(sshAlias: String, remoteRoot: String, publicBaseURL: String,
                                          port: Int? = nil) throws -> Bool {
        guard !PublishingStorage.exists else { return false }
        var settings = PublishingSettings()
        settings.transport = .sftp; settings.sshAlias = sshAlias; settings.sftpRemoteRoot = remoteRoot
        settings.publicBaseURL = publicBaseURL; settings.sftpPort = port
        _ = try PublishingPlan(settings: settings, fileName: "validation.png", capabilities: nil, sftpAvailable: PublishingSFTP.available)
        try PublishingStorage.save(settings, password: "")
        return true
    }

    /// Settings never start a network request. Passwords are saved only in macOS Keychain.
    public func showSettings(relativeTo window: NSWindow) {
        if !Thread.isMainThread { DispatchQueue.main.async { self.showSettings(relativeTo: window) }; return }
        guard publishPanel == nil else { return }
        if let panel = settingsPanel { panel.makeKeyAndOrderFront(nil); return }
        guard window.attachedSheet == nil else { return }
        do {
            savedSettings = try PublishingStorage.load()
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
            window.beginSheet(panel) { [self] _ in _ = self }
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try PublishingCurl.capabilities() }
                DispatchQueue.main.async {
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
            }
        } catch { presentMessage(error.localizedDescription, relativeTo: window) }
    }

    /// Presents a Publish confirmation. Only that button starts the upload.
    /// Success returns the configured public URL, or the verified remote URL for status only.
    /// Only a configured public URL is copied. Completion always runs on the main thread.
    /// Callers must not copy the completion URL unconditionally; this coordinator owns clipboard policy.
    public func publish(data: Data, fileName: String, presenting window: NSWindow,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.publish(data: data, fileName: fileName, presenting: window, completion: completion) }; return
        }
        guard publishPanel == nil, settingsPanel == nil, window.attachedSheet == nil else {
            completion(.failure(PublishingFailure("Close the current sheet before publishing."))); return
        }
        do {
            guard !data.isEmpty else { throw PublishingFailure("There is no image data to upload.") }
            let settings = try PublishingStorage.load()
            let capabilities = settings.transport == .sftp ? nil : try PublishingCurl.capabilities()
            let plan = try PublishingPlan(settings: settings, fileName: fileName, capabilities: capabilities, sftpAvailable: PublishingSFTP.available)
            let panel = makePanel(title: "Publish Image", width: 700, height: 350)
            let form = verticalStack()
            let description = label("Upload \(fileName) to:\n\(plan.remoteURL.absoluteString)\n\n" +
                (plan.publicURL != nil ? "After a verified upload, the configured public link will be copied." : "Upload only. The remote file location will be returned; the clipboard will stay unchanged."))
            description.maximumNumberOfLines = 9; description.preferredMaxLayoutWidth = 640
            description.lineBreakMode = .byTruncatingMiddle
            form.addArrangedSubview(description)
            let cancel = button("Cancel", #selector(cancelPublish)), publish = button("Publish", #selector(confirmPublish))
            form.addArrangedSubview(buttonRow([cancel, publish])); install(form, in: panel)
            publishPanel = panel; pendingCompletion = completion
            // Hold self until the sheet completes so a temporary coordinator is safe to use.
            window.beginSheet(panel) { [self] _ in _ = self }
            pendingUpload = { [self] in
                pendingUpload = nil; cancel.isEnabled = false; publish.isEnabled = false
                description.stringValue = "Uploading \(fileName)…\nUpload and public-link verification have a three-minute deadline."
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result<URL, Error> {
                        if settings.transport == .sftp { return try PublishingTransfer.upload(data: data, plan: plan) }
                        let password = try PublishingKeychain.read(settings.credentialID)
                        return try PublishingTransfer.upload(data: data, plan: plan, username: settings.username, password: password)
                    }
                    DispatchQueue.main.async {
                        if case .success(let url) = result, plan.publicURL != nil {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                        self.finishPublish(result)
                    }
                }
            }
        } catch { completion(.failure(error)) }
    }

    @objc private func confirmPublish() { pendingUpload?() }
    @objc private func protocolChanged() {
        guard let field = protocolField, field.indexOfSelectedItem >= 0 else { return }
        let sftp = PublishingProtocol.allCases[field.indexOfSelectedItem] == .sftp
        passwordField?.isEnabled = !sftp
        aliasField?.isEnabled = sftp; remoteRootField?.isEnabled = sftp; portField?.isEnabled = sftp
    }
    @objc private func cancelPublish() {
        guard pendingUpload != nil else { return }
        finishPublish(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                                       userInfo: [NSLocalizedDescriptionKey: "Publishing was cancelled."])))
    }
    private func finishPublish(_ result: Result<URL, Error>) {
        let completion = pendingCompletion
        pendingCompletion = nil; pendingUpload = nil
        if let panel = publishPanel { panel.sheetParent?.endSheet(panel); panel.orderOut(nil) }
        publishPanel = nil; completion?(result)
    }
    @objc private func cancelSettings() {
        if let panel = settingsPanel { panel.sheetParent?.endSheet(panel); panel.orderOut(nil) }
        settingsPanel = nil; passwordField?.stringValue = ""
        endpointField = nil; protocolField = nil; usernameField = nil; passwordField = nil
        folderField = nil; publicField = nil; settingsStatus = nil
        aliasField = nil; remoteRootField = nil; portField = nil
    }
    @objc private func saveSettings() {
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
            let capabilities = settings.transport == .sftp ? nil : try PublishingCurl.capabilities()
            let plan = try PublishingPlan(settings: settings, fileName: "validation.png", capabilities: capabilities, sftpAvailable: PublishingSFTP.available)
            if settings.transport != .sftp {
                _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/validation"), username: settings.username, password: secret.stringValue)
            }
            try PublishingStorage.save(settings, password: settings.transport == .sftp ? "" : secret.stringValue)
            cancelSettings()
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
        install(form, in: panel); settingsPanel = panel; window.beginSheet(panel) { [self] _ in _ = self }
    }
}
