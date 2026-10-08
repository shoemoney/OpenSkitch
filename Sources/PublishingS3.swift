import Foundation

// S3-compatible destinations (AWS, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, Wasabi, MinIO).
// Uploads go through the system curl with --aws-sigv4. Keys are always sent path-style
// (bucket names containing dots break virtual-hosted TLS). Secrets travel only on curl's stdin config.

struct S3Options: Codable, Equatable {
    var region = "us-east-1"
    var bucket = ""
    /// Non-empty: read keys from this AWS shared-credentials profile. Empty: access key + secret in Keychain.
    var credentialsProfile = ""
    /// Off by default. Buckets with ACLs disabled (BucketOwnerEnforced) reject any x-amz-acl header.
    var publicReadACL = false

    init() {}
    private enum CodingKeys: String, CodingKey { case region, bucket, credentialsProfile, publicReadACL }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "us-east-1"
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        credentialsProfile = try c.decodeIfPresent(String.self, forKey: .credentialsProfile) ?? ""
        publicReadACL = try c.decodeIfPresent(Bool.self, forKey: .publicReadACL) ?? false
    }
}

struct S3Credentials: Equatable {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String
}

enum AWSSharedCredentials {
    /// AWS_SHARED_CREDENTIALS_FILE wins when the caller passes an environment that sets it.
    /// Production passes the process environment; tests pass a fake environment and home.
    static func defaultFile(environment: [String: String], home: URL) -> URL {
        if let custom = environment["AWS_SHARED_CREDENTIALS_FILE"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent(".aws/credentials")
    }

    static func load(profile: String, from file: URL) throws -> S3Credentials {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count <= 262_144,
              let text = String(data: data, encoding: .utf8) else {
            throw PublishingFailure("The AWS credentials file could not be read at \(file.path).")
        }
        return try parse(text, profile: profile, source: file.path)
    }

    static func parse(_ text: String, profile: String, source: String = "the credentials file") throws -> S3Credentials {
        let wanted = profile.trimmingCharacters(in: .whitespaces)
        var current: String?
        var found = false
        var values: [String: String] = [:]
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                var name = String(line[line.index(after: line.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
                if name.hasPrefix("profile ") { name = String(name.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
                current = name
                if name == wanted { found = true }
                continue
            }
            guard current == wanted, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        guard found else { throw PublishingFailure("Profile “\(wanted)” was not found in \(source).") }
        guard let key = values["aws_access_key_id"], !key.isEmpty,
              let secret = values["aws_secret_access_key"], !secret.isEmpty else {
            throw PublishingFailure("Profile “\(wanted)” needs aws_access_key_id and aws_secret_access_key.")
        }
        let token = values["aws_session_token"] ?? values["aws_security_token"] ?? ""
        guard ![key, secret, token].contains(where: PublishingPlan.hasControls), !key.contains(":") else {
            throw PublishingFailure("Profile “\(wanted)” contains an unusable credential value.")
        }
        return S3Credentials(accessKeyID: key, secretAccessKey: secret, sessionToken: token)
    }

    static func validateProfileName(_ name: String) throws {
        guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.@+=,-]{0,127}$"#, options: .regularExpression) != nil else {
            throw PublishingFailure("The AWS profile name may use letters, digits and . _ @ + = , - only.")
        }
    }
}

struct PublishingS3Plan {
    let region: String
    let bucket: String
    let keyComponents: [String]
    let objectURL: URL
    let bucketURL: URL
    let contentType: String
    let publicReadACL: Bool
    let usesProfile: Bool

    var key: String { keyComponents.joined(separator: "/") }
    var signingProvider: String { "aws:amz:\(region):s3" }

    init(settings: PublishingSettings, fileName: String) throws {
        let options = settings.s3 ?? S3Options()
        region = options.region.trimmingCharacters(in: .whitespacesAndNewlines)
        bucket = options.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard region.range(of: #"^[a-z0-9][a-z0-9-]{1,31}$"#, options: .regularExpression) != nil else {
            throw PublishingFailure("Enter an S3 region such as us-east-1 (Cloudflare R2 uses auto).")
        }
        guard bucket.range(of: #"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"#, options: .regularExpression) != nil,
              !bucket.contains(".."), !bucket.contains(".-"), !bucket.contains("-.") else {
            throw PublishingFailure("Enter a valid bucket name: 3 to 63 lowercase letters, digits, dots or hyphens.")
        }
        let profile = options.credentialsProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        usesProfile = !profile.isEmpty
        if usesProfile { try AWSSharedCredentials.validateProfileName(profile) }
        else {
            guard settings.username.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.@+=,-]{0,127}$"#, options: .regularExpression) != nil else {
                throw PublishingFailure("Enter the S3 access key ID, or choose an AWS credentials profile.")
            }
        }
        let prefix = settings.remoteFolder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in prefix {
            try PublishingPlan.validateComponent(component)
            guard component.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
                throw PublishingFailure("The key prefix may use letters, digits, dots, underscores and hyphens only.")
            }
        }
        try PublishingPlan.validateComponent(fileName)
        keyComponents = prefix + [fileName]
        let base: URL
        if settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = try PublishingPlan.baseURL("https://s3.\(region).amazonaws.com", schemes: ["https"])
        } else {
            base = try PublishingPlan.baseURL(settings.endpoint, schemes: ["https", "http"])
        }
        // Path-style only: <endpoint>/<bucket>/<key>.
        bucketURL = try PublishingPlan.appending([bucket], to: base)
        objectURL = try PublishingPlan.appending([bucket] + keyComponents, to: base)
        contentType = Self.contentType(for: fileName)
        publicReadACL = options.publicReadACL
    }

    /// Keys use only A-Z a-z 0-9 . _ - so SigV4 canonicalization can never disagree with the URL.
    static func safeFileName(_ name: String) -> String {
        var out = ""
        for scalar in name.unicodeScalars {
            let ascii = scalar.isASCII
            let ok = ascii && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-")
            out.append(ok ? Character(scalar) : "-")
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = String(out.drop(while: { $0 == "-" || $0 == "." }))
        out = String(out.prefix(200))
        return out.isEmpty ? "image.png" : out
    }

    static func contentType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// One signed request. The key pair appears only in this stdin config, never in argv.
    func signedConfig(method: String, url: URL, credentials: S3Credentials, uploadFile: URL?, responseFile: URL,
                      includeACL: Bool = false) throws -> Data {
        guard !credentials.accessKeyID.contains(":"), !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            throw PublishingFailure("The S3 access key and secret are required.")
        }
        var lines = ["silent", "show-error", "globoff", "path-as-is", "connect-timeout = 15",
                     "max-time = 120", "retry = 0",
                     "output = " + (try PublishingPlan.configQuote(responseFile.path)),
                     "proto = " + (try PublishingPlan.configQuote("=" + url.scheme!)),
                     "url = " + (try PublishingPlan.configQuote(url.absoluteString)),
                     "write-out = \"%{response_code}\\n%{url_effective}\\n%{size_upload}\\n\"",
                     "aws-sigv4 = " + (try PublishingPlan.configQuote(signingProvider)),
                     "user = " + (try PublishingPlan.configQuote(credentials.accessKeyID + ":" + credentials.secretAccessKey))]
        if let uploadFile {
            lines.append("upload-file = " + (try PublishingPlan.configQuote(uploadFile.path)))
            lines.append("header = " + (try PublishingPlan.configQuote("Content-Type: " + contentType)))
            lines.append("header = \"x-amz-content-sha256: UNSIGNED-PAYLOAD\"")
        } else {
            lines.append("request = " + (try PublishingPlan.configQuote(method)))
            lines.append("header = \"x-amz-content-sha256: \(Self.emptyPayloadHash)\"")
        }
        if !credentials.sessionToken.isEmpty {
            lines.append("header = " + (try PublishingPlan.configQuote("x-amz-security-token: " + credentials.sessionToken)))
        }
        if includeACL { lines.append("header = \"x-amz-acl: public-read\"") }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    func uploadConfig(file: URL, credentials: S3Credentials, responseFile: URL) throws -> Data {
        try signedConfig(method: "PUT", url: objectURL, credentials: credentials, uploadFile: file,
                         responseFile: responseFile, includeACL: publicReadACL)
    }
    func deleteConfig(credentials: S3Credentials, responseFile: URL) throws -> Data {
        try signedConfig(method: "DELETE", url: objectURL, credentials: credentials, uploadFile: nil, responseFile: responseFile)
    }
    /// ListObjectsV2 with max-keys=0 under the key prefix: signed, read-only, returns no objects and uploads nothing.
    func checkURL() throws -> URL {
        guard var parts = URLComponents(url: bucketURL, resolvingAgainstBaseURL: false) else {
            throw PublishingFailure("The bucket URL is invalid.")
        }
        var query = "list-type=2&max-keys=0"
        if keyComponents.count > 1 {
            query += "&prefix=" + PublishingPlan.escapePathComponent(keyComponents.dropLast().joined(separator: "/") + "/")
        }
        parts.percentEncodedQuery = query
        guard let url = parts.url else { throw PublishingFailure("The bucket check URL is invalid.") }
        return url
    }
    func checkConfig(credentials: S3Credentials, responseFile: URL) throws -> Data {
        try signedConfig(method: "GET", url: try checkURL(), credentials: credentials, uploadFile: nil, responseFile: responseFile)
    }

    /// S3 reports problems as XML; show only its Code and Message.
    static func errorSummary(_ body: String) -> String? {
        func element(_ name: String) -> String? {
            guard let open = body.range(of: "<\(name)>"), let close = body.range(of: "</\(name)>", range: open.upperBound..<body.endIndex) else { return nil }
            return String(body[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let code = element("Code") else { return nil }
        return element("Message").map { "\(code): \($0)" } ?? code
    }

    func verifiedUpload(stdout: String, exitCode: Int32, stderr: String, body: String, byteCount: Int,
                        username: String, password: String) throws {
        guard exitCode == 0 else {
            let detail = PublishingPlan.sanitized(stderr, username: username, password: password)
            throw PublishingFailure("Upload failed (curl \(exitCode))." + (detail.isEmpty ? "" : "\n" + detail))
        }
        let lines = stdout.components(separatedBy: "\n")
        guard lines.count == 4, lines.last == "", let code = Int(lines[0]) else {
            throw PublishingFailure("Curl did not return a complete S3 response. Upload success could not be verified.")
        }
        guard code == 200 else {
            let detail = Self.errorSummary(body).map { PublishingPlan.sanitized($0, username: username, password: password) }
            throw PublishingFailure("S3 returned status \(code); the upload was not confirmed." + (detail.map { "\n" + $0 } ?? ""))
        }
        guard let uploaded = Double(lines[2]), uploaded == Double(byteCount), URL(string: lines[1]) == objectURL else {
            throw PublishingFailure("S3 answered 200 but the uploaded byte count or file URL did not match. Upload success could not be verified.")
        }
    }

    struct CheckResult: Equatable { let ok: Bool; let message: String }

    /// Interprets the max-keys=0 listing. AccessDenied still proves the signature was accepted.
    static func interpretCheck(code: Int, body: String) -> CheckResult {
        if code == 200 { return CheckResult(ok: true, message: "OK: credentials and bucket verified. Nothing was uploaded.") }
        let summary = errorSummary(body)
        if code == 403, summary?.hasPrefix("AccessDenied") == true {
            return CheckResult(ok: true, message: "Credentials accepted, but they may not list this bucket. Uploads can still work if they allow PutObject.")
        }
        return CheckResult(ok: false, message: summary ?? "The server answered HTTP \(code).")
    }
}

enum PublishingS3Operations {
    /// The only argv curl ever receives: the key pair and session token ride in the stdin config.
    static let curlArguments = ["--disable", "--config", "-"]
    private static func runCurl(config: Data, timeout: TimeInterval, cancellation: PublishingCancellation) throws -> PublishingProcess.Output {
        try PublishingProcess.run(executable: "/usr/bin/curl", arguments: curlArguments,
                                  input: config, timeout: timeout, cancellation: cancellation)
    }
    private static func body(_ file: URL) -> String {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return "" }
        return String(decoding: data.prefix(8192), as: UTF8.self)
    }
    private static func statusCode(_ output: PublishingProcess.Output) -> Int? {
        output.stdout.components(separatedBy: "\n").first.flatMap { Int($0) }
    }

    static func upload(data: Data, plan: PublishingPlan, s3: PublishingS3Plan, credentials: S3Credentials,
                       cancellation: PublishingCancellation) throws {
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchS3-") }
        catch { throw PublishingFailure("A private temporary upload folder could not be created.") }
        let file = directory.appendingPathComponent("image"), response = directory.appendingPathComponent("response")
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw PublishingFailure("The image could not be prepared for upload.") }
        let config = try s3.uploadConfig(file: file, credentials: credentials, responseFile: response)
        let output = try runCurl(config: config, timeout: 125, cancellation: cancellation)
        try s3.verifiedUpload(stdout: output.stdout, exitCode: output.code, stderr: output.stderr, body: body(response),
                              byteCount: data.count, username: credentials.accessKeyID, password: credentials.secretAccessKey)
    }

    /// The Test button: a signed read-only listing. No object is written.
    static func check(plan: PublishingS3Plan, credentials: S3Credentials, cancellation: PublishingCancellation) throws -> PublishingS3Plan.CheckResult {
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchS3Check-") }
        catch { throw PublishingFailure("A private temporary folder could not be created.") }
        let response = directory.appendingPathComponent("response")
        let output = try runCurl(config: try plan.checkConfig(credentials: credentials, responseFile: response), timeout: 40, cancellation: cancellation)
        guard output.code == 0, let code = statusCode(output) else {
            let detail = PublishingPlan.sanitized(output.stderr, username: credentials.accessKeyID, password: credentials.secretAccessKey)
            throw PublishingFailure("The bucket could not be reached (curl \(output.code))." + (detail.isEmpty ? "" : "\n" + detail))
        }
        return PublishingS3Plan.interpretCheck(code: code, body: body(response))
    }

    /// Signed DELETE of the planned object; S3 answers 204 (200 from some compatible servers).
    static func delete(plan: PublishingS3Plan, credentials: S3Credentials, cancellation: PublishingCancellation) throws {
        let directory: URL
        do { directory = try cancellation.makeTemporaryDirectory(prefix: "SkitchS3Delete-") }
        catch { throw PublishingFailure("A private temporary folder could not be created.") }
        let response = directory.appendingPathComponent("response")
        let output = try runCurl(config: try plan.deleteConfig(credentials: credentials, responseFile: response), timeout: 40, cancellation: cancellation)
        guard output.code == 0, let code = statusCode(output), [200, 204].contains(code) else {
            let detail = PublishingS3Plan.errorSummary(body(response)) ?? PublishingPlan.sanitized(output.stderr, username: credentials.accessKeyID, password: credentials.secretAccessKey)
            throw PublishingFailure("The S3 object could not be deleted." + (detail.isEmpty ? "" : "\n" + detail))
        }
    }
}
