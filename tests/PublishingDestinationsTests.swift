import Foundation

// Standalone pure checks for multi-destination storage and S3 transport. No network, no Keychain,
// no real ~/.aws and no real Application Support: every path is a fresh temp folder, secrets are in memory.
// xcrun swiftc -swift-version 5 Sources/Publishing.swift Sources/PublishingS3.swift Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift tests/PublishingDestinationsTests.swift -o /tmp/skitch-destinations-tests
// /tmp/skitch-destinations-tests --test
// Explicit integration path (never run by --test):
// /tmp/skitch-destinations-tests --live-s3 "AWS cdn"
@main
enum PublishingDestinationsTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw PublishingFailure("SELF-CHECK FAILED: " + message) }
        checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw PublishingFailure("SELF-CHECK FAILED: accepted " + message)
    }
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skitch-destinations-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func main() throws {
        if CommandLine.arguments.contains("--live-s3") { try liveS3(); return }
        guard CommandLine.arguments.contains("--test") else { print("Run with --test for pure destination and S3 self-checks."); return }
        try s3Plan()
        try s3Responses()
        try credentialsFile()
        try migration()
        try storeOperations()
        print("Destination and S3 self-checks passed: \(checks). No uploads were executed.")
    }

    static let capabilities = try! PublishingCapabilities(versionOutput: "curl 8.7.1 test\nProtocols: ftp ftps http https sftp\nFeatures: SSL\n")

    static func awsCDN() -> PublishingSettings {
        var settings = PublishingSettings()
        settings.transport = .s3; settings.remoteFolder = "pics"; settings.publicBaseURL = "https://cdn.shoemoney.com/pics/"
        var options = S3Options(); options.region = "us-east-1"; options.bucket = "cdn.shoemoney.com"; options.credentialsProfile = "default"
        settings.s3 = options
        return settings
    }

    // MARK: S3 request generation

    static func s3Plan() throws {
        let plan = try PublishingPlan(settings: awsCDN(), fileName: "My Shot #1 café-0a1b.png", capabilities: capabilities)
        try expect(PublishingS3Plan.safeFileName("My Shot #1 café.png") == "My-Shot-1-caf-.png", "unsafe characters become single hyphens")
        try expect(PublishingS3Plan.safeFileName("..hidden") == "hidden" && PublishingS3Plan.safeFileName("") == "image.png", "leading dots stripped, empty falls back")
        try expect(plan.remoteURL.absoluteString == "https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png",
                   "AWS URL is path-style even for a bucket name containing dots (\(plan.remoteURL))")
        try expect(plan.publicURL?.absoluteString == "https://cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png", "public URL is base + the same safe name")
        try expect(plan.s3?.signingProvider == "aws:amz:us-east-1:s3", "sigv4 provider string")
        let file = URL(fileURLWithPath: "/tmp/image"), response = URL(fileURLWithPath: "/tmp/response")
        let secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        let text = String(decoding: try plan.curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, sessionToken: "FwoGZXIvYXdzEXAMPLE", responseFile: response), as: UTF8.self)
        try expect(text.contains("aws-sigv4 = \"aws:amz:us-east-1:s3\"\n"), "config carries the sigv4 provider")
        try expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("user = ") } == ["user = \"AKIAIOSFODNN7EXAMPLE:\(secret)\""], "key pair appears once, in the stdin config")
        try expect(text.contains("header = \"x-amz-security-token: FwoGZXIvYXdzEXAMPLE\"\n"), "session token is a header")
        try expect(text.contains("header = \"Content-Type: image/png\"\n") && text.contains("upload-file = \"/tmp/image\"\n"), "PUT of the file with its content type")
        try expect(!text.lowercased().contains("x-amz-acl"), "no ACL header by default")
        try expect(text.contains("url = \"https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png\"\n"), "config url is the path-style object URL")
        try expect(!text.contains("insecure") && !text.contains("location") && !text.contains("\nfail\n"), "no insecure TLS, redirects or --fail (the body is needed for diagnostics)")
        try expect(PublishingS3Operations.curlArguments == ["--disable", "--config", "-"], "argv never carries a secret")
        let bare = String(decoding: try plan.curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, responseFile: response), as: UTF8.self)
        try expect(!bare.contains("x-amz-security-token"), "no token header without a session token")
        var acl = awsCDN(); acl.s3?.publicReadACL = true
        let aclText = String(decoding: try PublishingPlan(settings: acl, fileName: "a.png", capabilities: capabilities).curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, responseFile: response), as: UTF8.self)
        try expect(aclText.contains("x-amz-acl: public-read"), "the public-read ACL header exists only when opted in")

        var r2 = awsCDN(); r2.endpoint = "https://acct123.r2.cloudflarestorage.com"; r2.s3?.region = "auto"; r2.s3?.bucket = "shots"; r2.remoteFolder = "a/b"
        let r2Plan = try PublishingPlan(settings: r2, fileName: "x.jpg", capabilities: capabilities)
        try expect(r2Plan.remoteURL.absoluteString == "https://acct123.r2.cloudflarestorage.com/shots/a/b/x.jpg", "custom endpoint is <endpoint>/<bucket>/<key>")
        try expect(r2Plan.s3?.contentType == "image/jpeg" && r2Plan.s3?.signingProvider == "aws:amz:auto:s3", "content type by extension, region in the provider")
        var minio = r2; minio.endpoint = "http://192.168.1.10:9000/base"
        try expect(try PublishingPlan(settings: minio, fileName: "x.png", capabilities: capabilities).remoteURL.absoluteString == "http://192.168.1.10:9000/base/shots/a/b/x.png", "http MinIO endpoint with a base path")

        var keyed = awsCDN(); keyed.s3?.credentialsProfile = ""; keyed.username = "AKIAIOSFODNN7EXAMPLE"
        _ = try PublishingPlan(settings: keyed, fileName: "x.png", capabilities: capabilities)
        keyed.username = ""
        try rejects("an empty access key ID without a profile") { _ = try PublishingPlan(settings: keyed, fileName: "x.png", capabilities: capabilities) }
        for bucket in ["", "ab", "Upper", "under_score", "a..b", "-start", "end-", "x/y", "a b"] {
            var invalid = awsCDN(); invalid.s3?.bucket = bucket
            try rejects("bucket \(bucket)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for region in ["", "U S", "us/east", "../x", "x"] {
            var invalid = awsCDN(); invalid.s3?.region = region
            try rejects("region \(region)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for folder in ["../x", "a/./b", "my pics", "a%2Fb", "a\nb"] {
            var invalid = awsCDN(); invalid.remoteFolder = folder
            try rejects("key prefix \(folder)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        var badProfile = awsCDN(); badProfile.s3?.credentialsProfile = "bad profile\n"
        try rejects("profile with whitespace") { _ = try PublishingPlan(settings: badProfile, fileName: "x.png", capabilities: capabilities) }
        try rejects("missing curl capabilities") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: nil) }
        let old = try PublishingCapabilities(versionOutput: "curl 7.74.0 test\nProtocols: http https\nFeatures: SSL\n")
        try rejects("curl older than 7.75") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: old) }
        let noHTTPS = try PublishingCapabilities(versionOutput: "curl 8.7.1 test\nProtocols: http\nFeatures: SSL\n")
        try rejects("curl without https") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: noHTTPS) }

        // Test button and live-check requests.
        let s3 = try unwrap(plan.s3)
        let check = String(decoding: try s3.checkConfig(credentials: S3Credentials(accessKeyID: "AK", secretAccessKey: "SK", sessionToken: ""), responseFile: response), as: UTF8.self)
        try expect(try s3.checkURL().absoluteString == "https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com?list-type=2&max-keys=0&prefix=pics%2F", "bucket check is a max-keys=0 listing under the prefix")
        try expect(check.contains("request = \"GET\"") && !check.contains("upload-file") && check.contains("aws-sigv4"), "the check is a signed GET, not an upload")
        let delete = String(decoding: try s3.deleteConfig(credentials: S3Credentials(accessKeyID: "AK", secretAccessKey: "SK", sessionToken: "T"), responseFile: response), as: UTF8.self)
        try expect(delete.contains("request = \"DELETE\"") && delete.contains("url = \"\(s3.objectURL.absoluteString)\"") && delete.contains("x-amz-security-token: T"), "signed DELETE of the exact object")
    }

    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw PublishingFailure("SELF-CHECK FAILED: unexpected nil") }
        return value
    }

    static func s3Responses() throws {
        let plan = try unwrap(PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: capabilities).s3)
        let url = plan.objectURL.absoluteString
        try plan.verifiedUpload(stdout: "200\n\(url)\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK")
        let denied = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message><RequestId>ABC</RequestId></Error>"
        do { try plan.verifiedUpload(stdout: "403\n\(url)\n5\n", exitCode: 0, stderr: "", body: denied, byteCount: 5, username: "AK", password: "SK"); throw PublishingFailure("SELF-CHECK FAILED: 403 accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("403") && error.message.contains("AccessDenied: Access Denied") && !error.message.contains("RequestId"), "status and S3 code/message shown, nothing else") }
        for status in ["201", "204", "301", "500"] {
            try rejects("status \(status)") { try plan.verifiedUpload(stdout: "\(status)\n\(url)\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        }
        try rejects("size mismatch") { try plan.verifiedUpload(stdout: "200\n\(url)\n4\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        try rejects("other effective URL") { try plan.verifiedUpload(stdout: "200\nhttps://evil.example/x\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        do { try plan.verifiedUpload(stdout: "", exitCode: 6, stderr: "could not resolve host SKSECRETVALUE for AKIDVALUE", body: "", byteCount: 5, username: "AKIDVALUE", password: "SKSECRETVALUE"); throw PublishingFailure("SELF-CHECK FAILED: curl failure accepted") }
        catch let error as PublishingFailure { try expect(!error.message.contains("SKSECRETVALUE") && !error.message.contains("AKIDVALUE") && error.message.contains("curl 6"), "curl failures redact the key pair") }

        try expect(PublishingS3Plan.interpretCheck(code: 200, body: "<ListBucketResult/>").ok, "200 passes the check")
        let limited = PublishingS3Plan.interpretCheck(code: 403, body: denied)
        try expect(limited.ok && limited.message.contains("PutObject"), "AccessDenied still proves the signature, with a caveat")
        let bad = PublishingS3Plan.interpretCheck(code: 403, body: "<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match.</Message><StringToSign>SECRET</StringToSign></Error>")
        try expect(!bad.ok && bad.message == "SignatureDoesNotMatch: The request signature we calculated does not match.", "bad credentials fail with the S3 code and message only")
        try expect(!PublishingS3Plan.interpretCheck(code: 404, body: "<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist</Message></Error>").ok, "missing bucket fails")
        try expect(PublishingS3Plan.interpretCheck(code: 500, body: "oops").message == "The server answered HTTP 500.", "non-XML failures fall back to the status")
    }

    // MARK: AWS shared credentials

    static func credentialsFile() throws {
        let text = """
        # top comment
        ; another comment

        [default]
        aws_access_key_id = AKIADEFAULT
          aws_secret_access_key=  default/secret+key
        region = us-west-2

        [ work ]
        AWS_ACCESS_KEY_ID = AKIAWORK
        aws_secret_access_key = work-secret
        aws_session_token = tok/en==
        # trailing comment

        [nosecret]
        aws_access_key_id = AKIAONLY
        """
        let standard = try AWSSharedCredentials.parse(text, profile: "default")
        try expect(standard == S3Credentials(accessKeyID: "AKIADEFAULT", secretAccessKey: "default/secret+key", sessionToken: ""), "default profile with odd whitespace")
        let work = try AWSSharedCredentials.parse(text, profile: "work")
        try expect(work == S3Credentials(accessKeyID: "AKIAWORK", secretAccessKey: "work-secret", sessionToken: "tok/en=="), "named profile with a session token and uppercase keys")
        do { _ = try AWSSharedCredentials.parse(text, profile: "missing"); throw PublishingFailure("SELF-CHECK FAILED: missing profile accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("“missing”") && error.message.contains("not found"), "missing profile error names it") }
        do { _ = try AWSSharedCredentials.parse(text, profile: "nosecret"); throw PublishingFailure("SELF-CHECK FAILED: partial profile accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("aws_secret_access_key") && !error.message.contains("AKIAONLY"), "a profile without a secret is rejected without echoing keys") }
        try expect(try AWSSharedCredentials.parse("[profile cli]\naws_access_key_id=A\naws_secret_access_key=B\n", profile: "cli").secretAccessKey == "B", "[profile name] headers are tolerated")

        let home = URL(fileURLWithPath: "/fake-home")
        try expect(AWSSharedCredentials.defaultFile(environment: [:], home: home).path == "/fake-home/.aws/credentials", "default location under the injected home")
        try expect(AWSSharedCredentials.defaultFile(environment: ["AWS_SHARED_CREDENTIALS_FILE": "/tmp/custom-creds"], home: home).path == "/tmp/custom-creds", "AWS_SHARED_CREDENTIALS_FILE is honoured when passed in")
        try expect(AWSSharedCredentials.defaultFile(environment: ["AWS_SHARED_CREDENTIALS_FILE": ""], home: home).path == "/fake-home/.aws/credentials", "an empty variable is ignored")

        let directory = try temporaryDirectory(), file = directory.appendingPathComponent("credentials")
        try text.write(to: file, atomically: true, encoding: .utf8)
        try expect(try AWSSharedCredentials.load(profile: "work", from: file).accessKeyID == "AKIAWORK", "loads from an injected file")
        try rejects("unreadable credentials file") { _ = try AWSSharedCredentials.load(profile: "default", from: directory.appendingPathComponent("nope")) }

        // resolve(): profile reads the file, Keychain source reads the secret store; neither touches ~/.aws.
        let secrets = PublishingMemorySecrets()
        var viaProfile = awsCDN(); viaProfile.s3?.credentialsProfile = "work"
        try expect(try PublishingS3Credentials.resolve(settings: viaProfile, secrets: secrets, credentialsFile: file).sessionToken == "tok/en==", "profile credentials via the injected path")
        var viaKeychain = awsCDN(); viaKeychain.s3?.credentialsProfile = ""; viaKeychain.username = "AKIAKEYCHAIN"
        try secrets.add("keychain-secret", id: viaKeychain.credentialID)
        let resolved = try PublishingS3Credentials.resolve(settings: viaKeychain, secrets: secrets, credentialsFile: directory.appendingPathComponent("never-read"))
        try expect(resolved == S3Credentials(accessKeyID: "AKIAKEYCHAIN", secretAccessKey: "keychain-secret", sessionToken: ""), "access key plus Keychain secret")
    }

    // MARK: Storage

    static func legacyJSON(_ settings: PublishingSettings) throws -> Data { try JSONEncoder().encode(settings) }

    static func migration() throws {
        // The owner's SFTP destination.
        let directory = try temporaryDirectory(), secrets = PublishingMemorySecrets()
        var sftp = PublishingSettings(); sftp.transport = .sftp; sftp.sshAlias = "shoemoney.com"
        sftp.sftpRemoteRoot = "/var/www/shoemoney.com/shared/imgs"; sftp.publicBaseURL = "https://shoemoney.com/imgs/"
        sftp.credentialID = "00000000-0000-0000-0000-0000000000AA"
        let original = try legacyJSON(sftp)
        try original.write(to: directory.appendingPathComponent("destination.json"))
        let store = PublishingDestinationStore(directory: directory, secrets: secrets)
        let list = try store.load()
        try expect(list.destinations.count == 1 && list.defaultDestination?.id == list.destinations[0].id && list.defaultID == list.destinations[0].id, "the old destination becomes the only entry and the default")
        try expect(list.destinations[0].settings == sftp && list.destinations[0].settings.credentialID == sftp.credentialID, "SFTP settings and credentialID survive unchanged")
        try expect(list.destinations[0].name == "SFTP · shoemoney.com", "migrated name is readable")
        try expect(try Data(contentsOf: store.backupFile) == original, "the old file is kept byte for byte as a backup")
        try expect(!FileManager.default.fileExists(atPath: store.legacyFile.path) && FileManager.default.fileExists(atPath: store.file.path), "the single file is retired once the list is written")
        try expect(try store.load() == list, "a second load is stable")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try expect(!String(decoding: try encoder.encode(list.destinations[0].settings), as: UTF8.self).contains("s3"), "non-S3 settings encode exactly as before, so history fingerprints still match")

        // A password destination keeps its Keychain item (same credentialID, same secret).
        let directory2 = try temporaryDirectory(), secrets2 = PublishingMemorySecrets()
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com/up"; dav.username = "me"
        dav.credentialID = "00000000-0000-0000-0000-0000000000BB"
        try secrets2.add("dav-password", id: dav.credentialID)
        try legacyJSON(dav).write(to: directory2.appendingPathComponent("destination.json"))
        let migrated = try PublishingDestinationStore(directory: directory2, secrets: secrets2).load()
        try expect(secrets2.items == [dav.credentialID: "dav-password"] && migrated.destinations[0].settings.credentialID == dav.credentialID, "the Keychain item is neither moved nor deleted")

        // An unreadable old file blocks migration and is left alone.
        let directory3 = try temporaryDirectory()
        let junk = Data("{ not json".utf8)
        try junk.write(to: directory3.appendingPathComponent("destination.json"))
        let broken = PublishingDestinationStore(directory: directory3, secrets: PublishingMemorySecrets())
        try rejects("a corrupt legacy file") { _ = try broken.load() }
        try expect(try Data(contentsOf: broken.legacyFile) == junk && !FileManager.default.fileExists(atPath: broken.file.path), "the corrupt file is preserved and nothing is written")

        // An existing backup is never overwritten.
        let directory4 = try temporaryDirectory()
        try Data("older backup".utf8).write(to: directory4.appendingPathComponent("destination.json.pre-destinations.bak"))
        try original.write(to: directory4.appendingPathComponent("destination.json"))
        _ = try PublishingDestinationStore(directory: directory4, secrets: PublishingMemorySecrets()).load()
        try expect(try Data(contentsOf: directory4.appendingPathComponent("destination.json.pre-destinations.bak")) == Data("older backup".utf8)
                   && (try FileManager.default.contentsOfDirectory(atPath: directory4.path)).filter { $0.hasSuffix(".bak") }.count == 2, "a second backup gets its own name")

        let empty = try PublishingDestinationStore(directory: try temporaryDirectory(), secrets: PublishingMemorySecrets()).load()
        try expect(empty.destinations.isEmpty && empty.defaultDestination == nil, "a fresh install has no destinations")
    }

    static func storeOperations() throws {
        let directory = try temporaryDirectory(), secrets = PublishingMemorySecrets()
        let store = PublishingDestinationStore(directory: directory, secrets: secrets)
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com"; dav.username = "me"
        let first = PublishingDestination(name: "Work DAV", settings: dav)
        try store.save(first, password: "pw1")
        try expect(try store.load().defaultID == first.id, "the first destination becomes the default")
        try expect(secrets.items.count == 1 && secrets.items.values.first == "pw1", "its password went to the secret store")
        let storedID = try unwrap(store.load().destinations.first?.settings.credentialID)
        var s3 = awsCDN(); s3.s3?.credentialsProfile = ""; s3.username = "AKIAEXAMPLE"
        let second = PublishingDestination(name: "AWS cdn", settings: s3)
        try store.save(second, password: "s3-secret")
        try expect(try store.load().destinations.map(\.name) == ["Work DAV", "AWS cdn"] && (try store.load().defaultID) == first.id, "adding keeps the default")
        try expect(secrets.items.count == 2, "a Keychain-source S3 destination stores its secret")
        try rejects("a duplicate name") { try store.save(PublishingDestination(name: "aws CDN", settings: dav), password: "") }
        try rejects("an empty name") { try store.save(PublishingDestination(name: "  ", settings: dav), password: "") }

        try store.setDefault(second.id)
        let reopened = PublishingDestinationStore(directory: directory, secrets: secrets)
        try expect(try reopened.defaultDestination()?.name == "AWS cdn", "the default survives a fresh store on the same folder")
        try rejects("an unknown default") { try store.setDefault("nope") }

        var edited = first; edited.settings.endpoint = "https://dav2.example.com"
        try store.save(edited, password: "pw2")
        try expect(secrets.items[storedID] == nil && secrets.items.count == 2 && secrets.items.values.contains("pw2"), "editing rotates the secret and drops the old item")
        try expect(try store.load().destinations.count == 2 && (try store.load().destinations[0].settings.endpoint) == "https://dav2.example.com", "editing replaces in place")

        var profile = awsCDN(); profile.s3?.credentialsProfile = "default"
        let third = PublishingDestination(name: "Profile", settings: profile)
        try store.save(third, password: "")
        try expect(secrets.items.count == 2, "an AWS-profile destination stores no secret")

        try store.remove(second.id)
        try expect(try store.load().destinations.map(\.name) == ["Work DAV", "Profile"] && (try store.load().defaultID) == (try store.load().destinations[0].id), "removing the default promotes the first remaining")
        try expect(secrets.items.count == 1, "removing deletes its secret")
        try store.remove(first.id); try store.remove(third.id)
        try expect(try store.load().destinations.isEmpty && secrets.items.isEmpty && (try store.load().defaultID) == nil, "removing everything leaves an empty list")
        try expect(!(try Data(contentsOf: store.file).isEmpty) && !String(decoding: try Data(contentsOf: store.file), as: UTF8.self).contains("s3-secret"), "the file never holds a secret")
    }

    // MARK: Live check

    /// --live-s3 "<destination name>": upload a tiny PNG, verify its public URL, print it, then DELETE the object.
    /// Reads the saved destination (and AWS profile or Keychain secret) exactly as the app would.
    static func liveS3() throws {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--live-s3"), flag + 1 < arguments.count else {
            throw PublishingFailure("--live-s3 requires a saved destination name, e.g. --live-s3 \"AWS cdn\".")
        }
        let wanted = arguments[flag + 1]
        let store = PublishingDestinationStore.system
        let list = try store.load()
        guard let destination = list.destinations.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            throw PublishingFailure("No saved destination is named “\(wanted)”. Saved: " + list.destinations.map(\.name).joined(separator: ", "))
        }
        guard destination.settings.transport == .s3 else { throw PublishingFailure("“\(wanted)” is not an S3 destination.") }
        let credentials = try PublishingS3Credentials.resolve(
            settings: destination.settings, secrets: store.secrets,
            credentialsFile: AWSSharedCredentials.defaultFile(environment: ProcessInfo.processInfo.environment, home: URL(fileURLWithPath: NSHomeDirectory())))
        let name = "openskitch-live-check-" + UUID().uuidString.lowercased() + ".png"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1cAAAAASUVORK5CYII=")!
        let worker = PublishingWorkController()
        func run<T>(_ body: @escaping (PublishingCancellation) throws -> T) throws -> T {
            var outcome: Result<T, Error>?
            worker.start(work: body) { outcome = $0 }
            while outcome == nil { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
            return try outcome!.get()
        }
        let capabilities = try run { try PublishingCurl.capabilities(cancellation: $0) }
        let plan = try PublishingPlan(settings: destination.settings, fileName: name, capabilities: capabilities)
        let s3 = try unwrap(plan.s3)
        print("Uploading " + s3.key + " to bucket " + s3.bucket + " (" + s3.region + ")…")
        var failure: Error?
        do {
            let url = try run {
                try PublishingTransfer.upload(data: png, plan: plan, username: credentials.accessKeyID, password: credentials.secretAccessKey,
                                              sessionToken: credentials.sessionToken, cancellation: $0)
            }
            print("Uploaded and verified exact bytes at the public URL: " + url.absoluteString)
        } catch { failure = error }
        // The object is removed whether or not verification passed, so a failed check leaves nothing behind.
        do {
            try run { try PublishingS3Operations.delete(plan: s3, credentials: credentials, cancellation: $0) }
            print("Deleted " + s3.key + " (signed DELETE accepted).")
        } catch {
            print("WARNING: could not delete " + s3.key + ": " + error.localizedDescription)
            if failure == nil { failure = error }
        }
        if let failure { throw failure }
        print("LIVE S3 CHECK PASSED")
    }
}
