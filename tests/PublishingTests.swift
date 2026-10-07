import Foundation

// Standalone, pure checks: compile this file with Sources/Publishing.swift, then run --test.
// xcrun swiftc -swift-version 5 -framework AppKit -framework Security Sources/Publishing.swift tests/PublishingTests.swift -o /tmp/skitch-publishing-tests
// /tmp/skitch-publishing-tests --test
// No network, Keychain, saved settings, Process, or clipboard access in these checks.
@main
enum PublishingTests {
    static func main() throws {
        if CommandLine.arguments.contains("--live-sftp") { try liveSFTP(); return }
        guard CommandLine.arguments.contains("--test") else {
            print("Run with --test for pure publishing self-checks.")
            return
        }
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw PublishingFailure("SELF-CHECK FAILED: " + message) }
            checks += 1
        }
        func rejects(_ message: String, _ body: () throws -> Void) throws {
            do { try body() } catch { checks += 1; return }
            throw PublishingFailure("SELF-CHECK FAILED: accepted " + message)
        }
        let capabilities = try PublishingCapabilities(versionOutput: "curl 8.7.1 test\nProtocols: ftp ftps http https sftp\nFeatures: SSL\n")
        var settings = PublishingSettings()
        settings.endpoint = "https://example.com/dav/root/"
        settings.remoteFolder = "/screen shots/日本語/"
        settings.publicBaseURL = "https://cdn.example.com/images/"
        settings.username = "test-user"
        let filename = "a #?%;\" café.png"
        let plan = try PublishingPlan(settings: settings, fileName: filename, capabilities: capabilities)
        try expect(plan.remoteURL.absoluteString == "https://example.com/dav/root/screen%20shots/%E6%97%A5%E6%9C%AC%E8%AA%9E/a%20%23%3F%25%3B%22%20caf%C3%A9.png", "escaped destination")
        try expect(plan.publicURL?.absoluteString == "https://cdn.example.com/images/a%20%23%3F%25%3B%22%20caf%C3%A9.png", "public base maps to remote folder, no duplicate folder")
        try expect(PublishingPlan.escapePathComponent("%2F") == "%252F", "literal percent is not a path separator")
        try expect(PublishingPlan.escapePathComponent("-._~AZaz09") == "-._~AZaz09", "unreserved characters")
        try expect(PublishingPlan.escapePathComponent("{a}[1];type=a.png") == "%7Ba%7D%5B1%5D%3Btype%3Da.png", "curl globs and FTP type suffix are escaped")
        for filename in ["", ".", "..", "../x.png", "a/b.png", "a\\b.png", "a\n.png", "a\0.png"] {
            try rejects("unsafe filename") { _ = try PublishingPlan(settings: settings, fileName: filename, capabilities: capabilities) }
        }
        for endpoint in ["", "example.com", "file:///tmp", "ftp://example.com", "https://u:p@example.com", "https://u@example.com", "https://example.com?token=x", "https://example.com/#x", "https://example.com/a/../b", "https://example.com/%2e%2e/b", "https://example.com/a%2fb", "https://example.com/a%5cb", "https://example.com/%00", "https://example.com:0", "https://example.com:65536"] {
            var invalid = settings; invalid.endpoint = endpoint
            try rejects("unsafe endpoint") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for folder in ["../images", "a/./b", "a\\b", "a\r\nb"] {
            var invalid = settings; invalid.remoteFolder = folder
            try rejects("unsafe folder") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for publicURL in ["ftp://example.com", "https://user:pass@example.com", "https://example.com?secret=x"] {
            var invalid = settings; invalid.publicBaseURL = publicURL
            try rejects("unsafe public URL") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        var percent = settings; percent.endpoint = "https://example.com/a%20b/%25folder"
        try expect(try PublishingPlan(settings: percent, fileName: "x.png", capabilities: capabilities).remoteURL.absoluteString.hasPrefix("https://example.com/a%20b/%25folder/"), "endpoint is encoded once")
        let password = "p@ss\"\\word\nheader = injected\tend\r"
        let config = String(decoding: try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/a b"), username: settings.username, password: password), as: UTF8.self)
        try expect(config.contains("user = \"test-user:p@ss\\\"\\\\word\\nheader = injected\\tend\\r\"\n"), "credential config quoting")
        try expect(config.components(separatedBy: "\n").filter { $0.hasPrefix("user = ") }.count == 1, "single credential config line")
        try expect(!config.contains("\nheader = injected"), "no option injection")
        try expect(config.contains("max-time = 120\n") && config.contains("connect-timeout = 15\n") && config.contains("retry = 0\n"), "bounded upload without automatic retries")
        try expect(!config.contains("location") && !config.contains("insecure") && !config.contains("verbose"), "no insecure TLS or redirects or tracing")
        try rejects("null credential") { _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "u", password: "p\0") }
        try rejects("colon username") { _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "u:p", password: "p") }
        try rejects("password without username") { _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "", password: "p") }
        try rejects("unsupported credential control") { _ = try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "u", password: "p\u{1B}") }
        let anonymous = String(decoding: try plan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "", password: ""), as: UTF8.self)
        try expect(!anonymous.contains("user = "), "anonymous configuration contains no credentials")
        let clean = PublishingPlan.sanitized("test-user \(password) \(PublishingPlan.escapePathComponent(password)) https://test-user:secret@example.com/a?token=something\nAuthorization: Basic \(Data((settings.username + ":" + password).utf8).base64EncodedString())", username: settings.username, password: password)
        try expect(!clean.contains(settings.username) && !clean.contains("p@ss") && !clean.contains("something") && !clean.contains("secret"), "stderr secret redaction")
        let clipped = PublishingPlan.sanitized(String(repeating: "x", count: 1495) + "long-secret", username: "u", password: "long-secret")
        try expect(!clipped.contains("long-"), "redact before truncation")
        let encodedSecret = PublishingPlan.sanitized("user TEST-USER password p%40ss%3Aword token=unknown-secret", username: "test-user", password: "p@ss:word")
        try expect(!encodedSecret.lowercased().contains("test-user") && !encodedSecret.contains("p%40ss") && !encodedSecret.contains("unknown-secret"), "case-insensitive encoded credentials and token field redaction")
        try expect(!String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("password"), "settings JSON has no password field")
        func response(_ code: Int, url: String? = nil, size: String = "12") -> String {
            String(format: "%03d", code) + "\n" + (url ?? plan.remoteURL.absoluteString) + "\n" + size + "\n"
        }
        for code in [200, 201, 204] {
            let result = try plan.verifiedResult(stdout: response(code), exitCode: 0, stderr: "", byteCount: 12, username: settings.username, password: password)
            try expect(result == plan.publicURL, "verified HTTP public result")
        }
        for code in [0, 202, 206, 207, 301, 302, 401, 403, 404, 500] {
            try rejects("unconfirmed HTTP status") { _ = try plan.verifiedResult(stdout: response(code), exitCode: 0, stderr: "", byteCount: 12, username: "", password: "") }
        }
        for output in ["", "201\n", "201\n\n12\n", response(201, url: "https://other.example/x"), response(201, size: "11"), response(201, size: "nan"), response(201) + "extra"] {
            try rejects("missing or mismatching response") { _ = try plan.verifiedResult(stdout: output, exitCode: 0, stderr: "", byteCount: 12, username: "", password: "") }
        }
        try rejects("curl failure despite plausible stdout") { _ = try plan.verifiedResult(stdout: response(201), exitCode: 22, stderr: password, byteCount: 12, username: "", password: password) }
        var uploadOnly = settings; uploadOnly.publicBaseURL = ""
        let statusPlan = try PublishingPlan(settings: uploadOnly, fileName: "x.png", capabilities: capabilities)
        let location = try statusPlan.verifiedResult(stdout: "201\n\(statusPlan.remoteURL.absoluteString)\n12\n", exitCode: 0, stderr: "", byteCount: 12, username: "", password: "")
        try expect(statusPlan.publicURL == nil && location == statusPlan.remoteURL, "upload-only returns real remote location")
        let noSFTP = try PublishingCapabilities(versionOutput: "curl 8 test\nProtocols: ftp ftps http https\nFeatures: SSL\n")
        var sftp = uploadOnly; sftp.transport = .sftp; sftp.endpoint = "sftp://example.com/absolute/root"
        sftp.username = ""
        try rejects("missing system sftp executable") { _ = try PublishingPlan(settings: sftp, fileName: "x.png", capabilities: noSFTP) }
        let sftpPlan = try PublishingPlan(settings: sftp, fileName: "x.png", capabilities: noSFTP, sftpAvailable: true)
        let keyed = sftpPlan.keyedSFTP!
        let image = Data("synthetic image bytes".utf8)
        try expect(try keyed.verifiedResult(exitCode: 0, stderr: "", expected: image, downloaded: image, publicURL: nil) == sftpPlan.remoteURL, "SFTP verified by exact downloaded bytes")
        try rejects("SFTP curl path") { _ = try sftpPlan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "", password: "") }
        try rejects("SFTP curl success claim") { _ = try sftpPlan.verifiedResult(stdout: "000\n\(sftpPlan.remoteURL.absoluteString)\n12\n", exitCode: 0, stderr: "", byteCount: 12, username: "", password: "") }
        try rejects("SFTP missing verification") { _ = try keyed.verifiedResult(exitCode: 0, stderr: "", expected: image, downloaded: nil, publicURL: nil) }
        try rejects("SFTP wrong same-size bytes") { _ = try keyed.verifiedResult(exitCode: 0, stderr: "", expected: Data([1, 2]), downloaded: Data([2, 1]), publicURL: nil) }
        try rejects("SFTP failed command despite matching bytes") { _ = try keyed.verifiedResult(exitCode: 1, stderr: "", expected: image, downloaded: image, publicURL: nil) }
        for option in ["StrictHostKeyChecking=yes", "BatchMode=yes", "PasswordAuthentication=no", "KbdInteractiveAuthentication=no", "ControlPath=none", "ForwardAgent=no"] {
            try expect(keyed.arguments.contains(option), "strict keyed SSH argument")
        }
        try expect(!keyed.arguments.contains("-F") && !keyed.arguments.contains("-i") && !keyed.arguments.contains(where: { $0.contains("User=") }), "SSH alias configuration remains authoritative")
        let batch = String(decoding: try keyed.batch(upload: URL(fileURLWithPath: "/tmp/image"), verification: URL(fileURLWithPath: "/tmp/verified")), as: UTF8.self)
        try expect(batch == "@put \"/tmp/image\" \"/absolute/root/screen shots/日本語/x.png\"\n@chmod 0600 \"/absolute/root/screen shots/日本語/x.png\"\n@get \"/absolute/root/screen shots/日本語/x.png\" \"/tmp/verified\"\n@bye\n", "private batch contains exact put, owner-only mode and verification get with quoted spaces")
        try expect(!batch.contains("0644"), "private upload never grants public read")
        for path in ["a\"b", "a'b", "a\nb", "a\rb", "a\\b", "a*b", "a?b", "a[b]", "a{b}"] {
            try rejects("SFTP batch injection or wildcard") { _ = try PublishingSFTPPlan.batchQuote(path) }
        }
        let bootstrap = Data(#"{"transport":"sftp","sshAlias":"shoemoney.com","sftpRemoteRoot":"/var/www/shoemoney.com/shared/imgs","publicBaseURL":"https://shoemoney.com/imgs/"}"#.utf8)
        var aliasSettings = try JSONDecoder().decode(PublishingSettings.self, from: bootstrap)
        let aliasPlan = try PublishingPlan(settings: aliasSettings, fileName: "screen shot.png", capabilities: nil, sftpAvailable: true)
        try expect(aliasPlan.keyedSFTP?.target == "shoemoney.com" && aliasPlan.keyedSFTP?.port == nil, "secret-free bootstrap uses SSH alias and configured port")
        try expect(aliasPlan.keyedSFTP?.remotePath == "/var/www/shoemoney.com/shared/imgs/screen shot.png", "exact persistent shared destination")
        try expect(aliasPlan.publicURL?.absoluteString == "https://shoemoney.com/imgs/screen%20shot.png", "correct public file URL")
        let publicBatch = String(decoding: try aliasPlan.keyedSFTP!.batch(upload: URL(fileURLWithPath: "/tmp/image"), verification: URL(fileURLWithPath: "/tmp/verified"), publicURL: aliasPlan.publicURL), as: UTF8.self)
        try expect(publicBatch == "@put \"/tmp/image\" \"/var/www/shoemoney.com/shared/imgs/screen shot.png\"\n@chmod 0644 \"/var/www/shoemoney.com/shared/imgs/screen shot.png\"\n@get \"/var/www/shoemoney.com/shared/imgs/screen shot.png\" \"/tmp/verified\"\n@bye\n", "public batch makes only the quoted uploaded file web-readable before verification")
        try expect(!publicBatch.contains("0600") && !publicBatch.contains("-chmod") && !publicBatch.contains("chmod -R"), "public chmod is mandatory, targeted and nonrecursive")
        let check = try PublishingPublicCheck(url: aliasPlan.publicURL!)
        let publicConfig = String(decoding: try check.curlConfig(download: URL(fileURLWithPath: "/tmp/public-image"), byteCount: image.count), as: UTF8.self)
        try expect(publicConfig.contains("max-time = 30\n") && publicConfig.contains("connect-timeout = 10\n") && publicConfig.contains("max-redirs = 0\n"), "public GET is bounded and rejects redirects")
        try expect(publicConfig.contains("request = \"GET\"") && publicConfig.contains("max-filesize = \(image.count)\n"), "public verification fetches bounded actual bytes")
        for forbidden in ["user =", "netrc", "cookie", "Authorization", "location", "proxy", "insecure"] {
            try expect(!publicConfig.contains(forbidden), "public verification sends no credentials or redirects")
        }
        let publicResponse = "200\n\(check.url.absoluteString)\n\(image.count)\n"
        try expect(try check.verifiedResult(stdout: publicResponse, exitCode: 0, stderr: "", expected: image, downloaded: image) == check.url, "public success requires matching HTTP URL and image bytes")
        for status in ["201", "204", "206", "301", "302", "307", "401", "403", "404", "500"] {
            try rejects("public URL inaccessible or redirected") { _ = try check.verifiedResult(stdout: "\(status)\n\(check.url.absoluteString)\n\(image.count)\n", exitCode: 0, stderr: "", expected: image, downloaded: image) }
        }
        for output in ["", "200\n\n\(image.count)\n", "200\nhttps://other.example/image.png\n\(image.count)\n", "200\n\(check.url.absoluteString)\nnan\n", publicResponse + "extra"] {
            try rejects("missing or mismatching public response") { _ = try check.verifiedResult(stdout: output, exitCode: 0, stderr: "", expected: image, downloaded: image) }
        }
        try rejects("public success without body") { _ = try check.verifiedResult(stdout: publicResponse, exitCode: 0, stderr: "", expected: image, downloaded: nil) }
        try rejects("public body differs despite same size") { _ = try check.verifiedResult(stdout: "200\n\(check.url.absoluteString)\n2\n", exitCode: 0, stderr: "", expected: Data([1,2]), downloaded: Data([2,1])) }
        try rejects("failed public fetch despite plausible body") { _ = try check.verifiedResult(stdout: publicResponse, exitCode: 22, stderr: "HTTP 403", expected: image, downloaded: image) }
        try expect(try aliasPlan.keyedSFTP!.verifiedResult(exitCode: 0, stderr: "", expected: image, downloaded: image, publicURL: aliasPlan.publicURL) == aliasPlan.publicURL, "SFTP returns exact configured public filename after verification")
        aliasSettings.sftpPort = 2222; aliasSettings.username = "shoemoney"
        let overrides = try PublishingPlan(settings: aliasSettings, fileName: "x.png", capabilities: nil, sftpAvailable: true)
        try expect(overrides.keyedSFTP!.arguments.contains("2222") && overrides.keyedSFTP!.arguments.contains("User=shoemoney"), "optional port and username overrides")
        for alias in ["-oProxyCommand=evil", "user@host", "host:22", "host/path", "host\nput", "host\"quote", "host name"] {
            var invalid = aliasSettings; invalid.sshAlias = alias
            try rejects("SSH alias injection") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: nil, sftpAvailable: true) }
        }
        for root in ["relative/root", "/root/../imgs", "/root/\"imgs", "/root/imgs\nbye"] {
            var invalid = aliasSettings; invalid.sftpRemoteRoot = root
            try rejects("SFTP remote root injection") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: nil, sftpAvailable: true) }
        }
        for port in [0, 65536] {
            var invalid = aliasSettings; invalid.sftpPort = port
            try rejects("SFTP port range") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: nil, sftpAvailable: true) }
        }
        let oldSettings = Data(#"{"endpoint":"https://example.com","transport":"webDAV","username":"","remoteFolder":"","publicBaseURL":"","credentialID":"00000000-0000-0000-0000-000000000001"}"#.utf8)
        try expect(try JSONDecoder().decode(PublishingSettings.self, from: oldSettings).sshAlias == "", "older destinations decode without new SFTP fields")
        for (transport, endpoint) in [(PublishingProtocol.ftp, "ftp://example.com"), (.ftps, "ftp://example.com"), (.ftps, "ftps://example.com")] {
            var ftp = uploadOnly; ftp.transport = transport; ftp.endpoint = endpoint
            let ftpPlan = try PublishingPlan(settings: ftp, fileName: "x.png", capabilities: capabilities)
            let ftpConfig = String(decoding: try ftpPlan.curlConfig(file: URL(fileURLWithPath: "/tmp/image"), username: "u", password: "p"), as: UTF8.self)
            try expect(ftpConfig.contains("ssl-reqd") == (transport == .ftps), "FTPS mandates TLS")
            try expect(ftpConfig.contains("ftp-skip-pasv-ip"), "FTP data connection stays on endpoint host")
            try expect(try ftpPlan.verifiedResult(stdout: "226\n\(ftpPlan.remoteURL.absoluteString)\n12\n", exitCode: 0, stderr: "", byteCount: 12, username: "", password: "") == ftpPlan.remoteURL, "FTP verified result")
            try rejects("FTP incomplete status") { _ = try ftpPlan.verifiedResult(stdout: "150\n\(ftpPlan.remoteURL.absoluteString)\n12\n", exitCode: 0, stderr: "", byteCount: 12, username: "", password: "") }
        }
        let noTLS = try PublishingCapabilities(versionOutput: "curl 8 test\nProtocols: ftp ftps http https\nFeatures: IPv6\n")
        try rejects("FTPS without TLS") { try noTLS.validate(.ftps, scheme: "ftp") }
        try rejects("missing tool protocol report") { _ = try PublishingCapabilities(versionOutput: "not curl") }
        print("Publishing self-checks passed: \(checks). No uploads were executed.")
    }

    // Explicit integration path only. Parent/user supplies the destination; --test never reaches it.
    // --live-sftp --ssh-alias shoemoney.com --remote-root /var/www/shoemoney.com/shared/imgs --public-base-url https://shoemoney.com/imgs/
    static func liveSFTP() throws {
        func value(_ flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[index + 1]
        }
        guard let alias = value("--ssh-alias"), let root = value("--remote-root"), let publicBase = value("--public-base-url") else {
            throw PublishingFailure("--live-sftp requires --ssh-alias, --remote-root, and --public-base-url. It uploads a synthetic PNG and verifies exact bytes.")
        }
        var settings = PublishingSettings(); settings.transport = .sftp
        settings.sshAlias = alias; settings.sftpRemoteRoot = root; settings.publicBaseURL = publicBase
        if let port = value("--port") {
            guard let number = Int(port) else { throw PublishingFailure("--port must be numeric.") }
            settings.sftpPort = number
        }
        let name = "skitch-redux-backend-test-" + UUID().uuidString.lowercased() + ".png"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1cAAAAASUVORK5CYII=")!
        let plan = try PublishingPlan(settings: settings, fileName: name, capabilities: nil, sftpAvailable: PublishingTransfer.sftpAvailable)
        let worker = PublishingWorkController()
        var uploadResult: Result<URL, Error>?
        worker.start(work: { context in try PublishingTransfer.upload(data: png, plan: plan, cancellation: context) }) { uploadResult = $0 }
        while uploadResult == nil { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        let url = try uploadResult!.get()
        guard url == plan.publicURL else { throw PublishingFailure("The backend did not return the exact public image URL.") }
        print("SFTP and public HTTP 200 verified exact PNG bytes. Public URL: " + url.absoluteString)
    }
}
