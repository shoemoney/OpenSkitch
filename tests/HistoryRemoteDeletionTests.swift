import Foundation
import Darwin

// Standalone, no UI/network/process/Keychain operations; every deletion adapter is fake.
// xcrun swiftc -swift-version 5 -framework AppKit -framework Security Sources/Publishing.swift Sources/HistoryRemoteDeletion.swift tests/HistoryRemoteDeletionTests.swift -o /tmp/skitch-history-deletion-tests
// /tmp/skitch-history-deletion-tests --test
private final class FakeHistoryDeletionAdapter: HistoryRemoteDeletionAdapter {
    private let lock = NSLock()
    private var config: PublishingSettings
    private var source = String(repeating: "a", count: 64)
    private var commands: [HistoryRemoteDeletionCommand] = []
    var response = PublishingProcess.Output(stdout: "Remote working directory: /home/publisher\n", stderr: "", code: 0)
    var passwordValue = "synthetic-password-8383"
    var inspectHook: (() -> Void)?
    var executeHook: ((PublishingCancellation) throws -> Void)?
    var loadHook: (() -> Void)?
    var toolAvailable = true
    var passwordReads = 0
    static let ssh = "hostname upload.example.test\nuser publisher\nport 22\nidentityfile ~/.ssh/test.pem\nidentitiesonly yes\nuserknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts2\nglobalknownhostsfile /etc/ssh/ssh_known_hosts /etc/ssh/ssh_known_hosts2\ncanonicalizehostname false\n"
    init(_ settings: PublishingSettings) { config = settings }
    func setSettings(_ value: PublishingSettings) { lock.lock(); config = value; lock.unlock() }
    func setSource(_ value: String) { lock.lock(); source = value; lock.unlock() }
    func capturedCommands() -> [HistoryRemoteDeletionCommand] { lock.lock(); defer { lock.unlock() }; return commands }
    func loadSettings() throws -> PublishingSettings { loadHook?(); lock.lock(); defer { lock.unlock() }; return config }
    func sshSourceFingerprint() throws -> String { lock.lock(); defer { lock.unlock() }; return source }
    func capabilities(cancellation: PublishingCancellation) throws -> PublishingCapabilities {
        guard toolAvailable else { throw PublishingFailure("Injected unsupported tool.") }
        return try PublishingCapabilities(versionOutput: "curl fake\nProtocols: http https\nFeatures: SSL\n")
    }
    func inspectSSH(_ plan: PublishingSFTPPlan, cancellation: PublishingCancellation) throws -> HistoryDeletionSSHConfiguration {
        inspectHook?(); return try HistoryDeletionSSHConfiguration(output: Self.ssh)
    }
    func password(credentialID: String) throws -> String { passwordReads += 1; return passwordValue }
    func execute(_ command: HistoryRemoteDeletionCommand, cancellation: PublishingCancellation) throws -> PublishingProcess.Output {
        lock.lock(); commands.append(command); lock.unlock()
        try executeHook?(cancellation); return response
    }
}

@main
enum HistoryRemoteDeletionTests {
    static var checks = 0
    static let url = URL(string: "https://example.test/imgs/proof%20image.png")!
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw PublishingFailure("HISTORY DELETION SELF-CHECK FAILED: " + message) }; checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw PublishingFailure("HISTORY DELETION SELF-CHECK FAILED: accepted " + message)
    }
    static func pump(until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        try expect(condition(), "fake work completed before deadline")
    }
    static func succeeded(_ result: Result<Void, Error>?) -> Bool { if case .success? = result { return true }; return false }
    static func sftpSettings() -> PublishingSettings {
        var settings = PublishingSettings(); settings.transport = .sftp
        settings.credentialID = "00000000-0000-0000-0000-000000000001"
        settings.sshAlias = "upload-alias"; settings.sftpRemoteRoot = "/srv/public images"
        settings.remoteFolder = "imgs"; settings.publicBaseURL = "https://example.test/imgs/"
        return settings
    }
    static func webSettings() -> PublishingSettings {
        var settings = sftpSettings(); settings.transport = .webDAV; settings.endpoint = "https://upload.example.test/storage"
        settings.username = "synthetic-user"; return settings
    }
    static func delete(_ coordinator: HistoryRemoteDeletionCoordinator, url: URL = url, binding: [String: String]) throws -> Result<Void, Error> {
        var result: Result<Void, Error>?
        coordinator.deleteBoundRemote(url: url, binding: binding) { result = $0 }
        try pump(until: { result != nil }); return result!
    }
    static func main() {
        do {
            guard CommandLine.arguments.contains("--test") else { print("Use --test for fake remote deletion checks."); return }
            try sftpMappingAndCommand()
            try urlRejections()
            try configDrift()
            try dictionaryAndSSHValidation()
            try webDAVResultsAndSecurity()
            try queuedAndBusyCancellation()
            try sshSourceSnapshot()
            print("History remote deletion checks passed: \(checks). Only fake adapters ran; no network, deletion tools, Keychain or UI.")
        } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    }
    static func sftpMappingAndCommand() throws {
        let adapter = FakeHistoryDeletionAdapter(sftpSettings())
        let coordinator = HistoryRemoteDeletionCoordinator(adapter: adapter)
        let binding = try coordinator.captureBinding(for: url)
        try expect(binding == (try coordinator.captureBinding(fileName: "proof image.png")), "before-publication filename binding exactly matches successful-URL binding")
        try expect(binding["publicURL"] == url.absoluteString && binding["version"] == "1", "binding stores only exact URL, version and hashes")
        try expect(binding.keys.sorted() == ["destinationSHA256", "publicURL", "sshConfigSHA256", "version"], "binding schema is secret-free")
        try expect(!binding.values.joined().contains("test.pem") && !binding.values.joined().contains("publisher"), "binding does not contain SSH credentials or key paths")
        try expect(succeeded(try delete(coordinator, binding: binding)), "fake SFTP confirms removal")
        let command = adapter.capturedCommands()[0]
        try expect(command.executable == "/usr/bin/sftp" && command.timeout == 30 && command.allowsSSHAgent, "SFTP uses bounded true sftp backend")
        try expect(String(decoding: command.input, as: UTF8.self) == "@rm \"/srv/public images/imgs/proof image.png\"\n@pwd\n@bye\n", "exact one-file SFTP rm with quoted full path and completion response")
        try expect(command.arguments.contains("StrictHostKeyChecking=yes") && command.arguments.contains("ControlPath=none"), "strict host checks and isolated helper settings preserved")
        try expect(command.arguments.starts(with: ["-F", "/dev/null"]) && command.arguments.contains("HostName=upload.example.test") && command.arguments.contains("User=publisher"), "effective host and user pinned independently of mutable alias config")
        try expect(!command.arguments.contains("-r") && !command.arguments.joined().contains("StrictHostKeyChecking=no") && adapter.passwordReads == 0, "no recursive deletion, host-check bypass or SFTP password lookup")
        adapter.response = PublishingProcess.Output(stdout: "", stderr: "denied", code: 1)
        try expect(!succeeded(try delete(coordinator, binding: binding)), "failed SFTP acknowledgement is not success")
        adapter.response = PublishingProcess.Output(stdout: "", stderr: "", code: 0)
        try expect(!succeeded(try delete(coordinator, binding: binding)), "exit zero without a processed-batch response is not success")
    }
    static func urlRejections() throws {
        let adapter = FakeHistoryDeletionAdapter(sftpSettings()), coordinator = HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(sftpSettings()))
        let invalid = ["https://evil.test/imgs/a.png", "http://example.test/imgs/a.png", "https://example.test:443/imgs/a.png",
                       "https://example.test/imgs-other/a.png", "https://example.test/imgs", "https://example.test/imgs/",
                       "https://example.test/imgs/a/b.png", "https://example.test/imgs//a.png", "https://example.test/imgs/../a.png",
                       "https://example.test/imgs/%2E%2E", "https://example.test/imgs/a%2Fb.png", "https://example.test/imgs/a%5Cb.png",
                       "https://example.test/imgs/%252E%252E", "https://example.test/imgs/a%250Ab.png", "https://example.test/imgs/a%00.png",
                       "https://example.test/imgs/a.png?token=synthetic", "https://example.test/imgs/a.png?", "https://example.test/imgs/a.png#",
                       "https://user:synthetic@example.test/imgs/a.png", "https://example.test/imgs/%61.png",
                       "https://example.test/imgs/%22.png", "https://example.test/imgs/%2A.png", "https://example.test/imgs/%27.png"]
        for text in invalid { try rejects("unsafe URL") { _ = try coordinator.captureBinding(for: URL(string: text)!) } }
        let liveFake = HistoryRemoteDeletionCoordinator(adapter: adapter)
        let binding = try liveFake.captureBinding(for: url)
        try expect(!succeeded(try delete(liveFake, url: URL(string: "https://example.test/imgs/other.png")!, binding: binding)), "a binding cannot authorize another filename")
        try expect(adapter.capturedCommands().isEmpty, "unrelated URL rejected before any deletion command")
        for text in ["https://example.test/imgs/caf%C3%A9.png", "https://example.test/imgs/-dash.png"] {
            _ = try liveFake.captureBinding(for: URL(string: text)!); checks += 1
        }
    }
    static func configDrift() throws {
        let original = sftpSettings()
        var mutations: [PublishingSettings] = []
        var changed = original; changed.sftpRemoteRoot = "/other"; mutations.append(changed)
        changed = original; changed.sshAlias = "other-host"; mutations.append(changed)
        changed = original; changed.sftpPort = 2222; mutations.append(changed)
        changed = original; changed.username = "other-user"; mutations.append(changed)
        changed = original; changed.remoteFolder = "other-folder"; mutations.append(changed)
        changed = original; changed.endpoint = "sftp://other.test/root"; mutations.append(changed)
        changed = original; changed.publicBaseURL = "https://example.test/other"; mutations.append(changed)
        changed = original; changed.credentialID = "00000000-0000-0000-0000-000000000002"; mutations.append(changed)
        changed = original; changed.transport = .webDAV; mutations.append(changed)
        for mutation in mutations {
            let adapter = FakeHistoryDeletionAdapter(original), coordinator = HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(original))
            let binding = try coordinator.captureBinding(for: url)
            adapter.setSettings(mutation)
            let changedCoordinator = HistoryRemoteDeletionCoordinator(adapter: adapter)
            try expect(!succeeded(try delete(changedCoordinator, binding: binding)) && adapter.capturedCommands().isEmpty, "config drift refuses deletion before mutation")
        }
        let adapter = FakeHistoryDeletionAdapter(original), coordinator = HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(original))
        let binding = try coordinator.captureBinding(for: url)
        adapter.setSource(String(repeating: "b", count: 64))
        try expect(!succeeded(try delete(HistoryRemoteDeletionCoordinator(adapter: adapter), binding: binding)) && adapter.capturedCommands().isEmpty, "SSH source drift refuses deletion")
        adapter.setSource(String(repeating: "a", count: 64))
        adapter.inspectHook = { adapter.setSource(String(repeating: "c", count: 64)) }
        try expect(!succeeded(try delete(HistoryRemoteDeletionCoordinator(adapter: adapter), binding: binding)) && adapter.capturedCommands().isEmpty, "SSH drift during resolution refuses mutation")
        adapter.setSource(String(repeating: "a", count: 64))
        adapter.inspectHook = { var config = original; config.sftpRemoteRoot = "/changed-during-inspection"; adapter.setSettings(config) }
        try expect(!succeeded(try delete(HistoryRemoteDeletionCoordinator(adapter: adapter), binding: binding)) && adapter.capturedCommands().isEmpty, "config rechecked at mutation boundary")
    }
    static func dictionaryAndSSHValidation() throws {
        let adapter = FakeHistoryDeletionAdapter(sftpSettings()), coordinator = HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(sftpSettings()))
        let good = try coordinator.captureBinding(for: url)
        var malformed: [[String: String]] = [[:]]
        var bad = good; bad["version"] = "2"; malformed.append(bad)
        bad = good; bad["destinationSHA256"] = "short"; malformed.append(bad)
        bad = good; bad["password"] = "must-never-be-stored"; malformed.append(bad)
        bad = good; bad["sshConfigSHA256"] = nil; malformed.append(bad)
        for binding in malformed { try expect(!succeeded(try delete(HistoryRemoteDeletionCoordinator(adapter: adapter), binding: binding)), "invalid or legacy binding rejected") }
        try expect(adapter.capturedCommands().isEmpty, "invalid bindings never reach a transfer adapter")
        for suffix in ["proxycommand shell-command\n", "proxyjump other-host\n", "canonicalizehostname yes\n", "hostname -option\n", "identityfile /path/%h.pem\n", "user injected user\n"] {
            try rejects("unsafe or advanced SSH configuration") { _ = try HistoryDeletionSSHConfiguration(output: FakeHistoryDeletionAdapter.ssh + suffix) }
        }
        var ftp = sftpSettings(); ftp.transport = .ftp; ftp.endpoint = "ftp://example.test/root"
        try rejects("unsupported FTP deletion") { _ = try HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(ftp)).captureBinding(for: url) }
        var local = webSettings(); local.endpoint = "file:///tmp"
        try rejects("unsupported local deletion") { _ = try HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(local)).captureBinding(for: url) }
    }
    static func webDAVResultsAndSecurity() throws {
        let settings = webSettings(), adapter = FakeHistoryDeletionAdapter(webSettings())
        let coordinator = HistoryRemoteDeletionCoordinator(adapter: adapter)
        let binding = try coordinator.captureBinding(for: url)
        try expect(binding["sshConfigSHA256"] == nil, "WebDAV binding has no SSH dependency")
        let target = "https://upload.example.test/storage/imgs/proof%20image.png"
        for status in ["200", "204", "202", "301", "302", "404", "500", ""] {
            adapter.response = PublishingProcess.Output(stdout: status + "\n" + target + "\n", stderr: "", code: 0)
            try expect(succeeded(try delete(coordinator, binding: binding)) == ["200", "204"].contains(status), "only completed WebDAV HTTP status accepted")
        }
        let command = adapter.capturedCommands()[0], config = String(decoding: command.input, as: UTF8.self)
        try expect(command.executable == "/usr/bin/curl" && command.arguments == ["--disable", "--config", "-"] && command.timeout == 30, "bounded curl config stdin backend")
        try expect(config.contains("request = \"DELETE\"") && config.contains("max-redirs = 0") && !config.contains("location"), "DELETE has no automatic redirects")
        try expect(!command.arguments.joined().contains(adapter.passwordValue) && config.contains(adapter.passwordValue), "credentials only in stdin config")
        try expect(!binding.values.joined().contains(settings.username) && !binding.values.joined().contains(adapter.passwordValue), "binding persists no credential data")
        adapter.response = PublishingProcess.Output(stdout: "204\nhttps://other.test/file\n", stderr: "", code: 0)
        try expect(!succeeded(try delete(coordinator, binding: binding)), "mismatched effective URL is never success")
        adapter.response = PublishingProcess.Output(stdout: "", stderr: settings.username + " " + adapter.passwordValue, code: 7)
        let failure = try delete(coordinator, binding: binding)
        guard case .failure(let error) = failure else { throw PublishingFailure("Expected fake failure.") }
        try expect(!error.localizedDescription.contains(settings.username) && !error.localizedDescription.contains(adapter.passwordValue), "stderr credentials sanitized")
        adapter.executeHook = { _ in throw PublishingFailure("synthetic-password-8383") }
        guard case .failure(let launchError) = try delete(coordinator, binding: binding) else { throw PublishingFailure("Expected fake execution failure.") }
        try expect(!launchError.localizedDescription.contains(adapter.passwordValue), "adapter errors cannot log credentials")
        adapter.executeHook = nil; adapter.toolAvailable = false
        let previousCount = adapter.capturedCommands().count
        try expect(!succeeded(try delete(coordinator, binding: binding)) && adapter.capturedCommands().count == previousCount, "unsupported system curl refused before deletion")
    }
    static func queuedAndBusyCancellation() throws {
        let queue = DispatchQueue(label: "history.deletion.fake.queued"), adapter = FakeHistoryDeletionAdapter(sftpSettings())
        let coordinator = HistoryRemoteDeletionCoordinator(adapter: adapter, work: PublishingWorkController(queue: queue))
        let binding = try coordinator.captureBinding(for: url)
        queue.suspend(); var resumed = false; defer { if !resumed { queue.resume() } }
        var result: Result<Void, Error>?, duplicate: Result<Void, Error>?, ack: Result<Void, Error>?
        coordinator.deleteBoundRemote(url: url, binding: binding) { result = $0 }
        coordinator.deleteBoundRemote(url: url, binding: binding) { duplicate = $0 }
        try expect(duplicate != nil && !succeeded(duplicate), "concurrent duplicate deletion rejected")
        coordinator.shutdown { ack = $0 }
        try expect(ack == nil, "queued shutdown does not acknowledge before work cleanup")
        queue.resume(); resumed = true
        try pump(until: { ack != nil })
        try expect(succeeded(ack) && !succeeded(result) && adapter.capturedCommands().isEmpty, "shutdown cancels queued deletion without executing it")
        var late: Result<Void, Error>?
        coordinator.deleteBoundRemote(url: url, binding: binding) { late = $0 }
        try expect(late != nil && !succeeded(late), "shutdown rejects late deletion")
        let running = FakeHistoryDeletionAdapter(sftpSettings()), liveFake = HistoryRemoteDeletionCoordinator(adapter: FakeHistoryDeletionAdapter(sftpSettings()))
        let liveBinding = try liveFake.captureBinding(for: url)
        let busyCoordinator = HistoryRemoteDeletionCoordinator(adapter: running)
        running.executeHook = { context in
            let deadline = Date().addingTimeInterval(2)
            while !context.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            try context.check()
        }
        var busyResult: Result<Void, Error>?, busyAck: Result<Void, Error>?
        busyCoordinator.deleteBoundRemote(url: url, binding: liveBinding) { busyResult = $0 }
        try pump(until: { !running.capturedCommands().isEmpty })
        busyCoordinator.shutdown { busyAck = $0 }
        try pump(until: { busyAck != nil })
        try expect(succeeded(busyAck) && !succeeded(busyResult), "running adapter cancellation acknowledged after fake exit")
    }
    static func sshSourceSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistorySSHConfigTest-" + UUID().uuidString)
        let user = root.appendingPathComponent("user"), system = root.appendingPathComponent("system")
        try FileManager.default.createDirectory(at: user.appendingPathComponent("config.d"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = user.appendingPathComponent("config"), include = user.appendingPathComponent("config.d/host.conf")
        try Data("Include config.d/*.conf\nHost upload-alias\n  HostName example.test\n  IdentityFile ~/.ssh/test.pem\n".utf8).write(to: config)
        try Data("Host upload-alias\n  User publisher\n".utf8).write(to: include)
        let first = try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system)
        try expect(first == (try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system)), "config source fingerprint stable")
        try Data("Host upload-alias\n  User other\n".utf8).write(to: include)
        try expect(first != (try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system)), "included SSH config changes invalidate binding")
        try Data("Match exec command\n".utf8).write(to: config)
        try rejects("dynamic SSH Match") { _ = try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system) }
        try Data("Include config\n".utf8).write(to: config)
        try rejects("cyclic SSH include") { _ = try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system) }
        try Data("Include test.pem\n".utf8).write(to: config)
        try Data("DO NOT READ A PRIVATE KEY".utf8).write(to: user.appendingPathComponent("test.pem"))
        try rejects("key-file include") { _ = try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system) }
        try Data("Include ../../outside.conf\n".utf8).write(to: config)
        try rejects("config include outside tree") { _ = try HistoryDeletionSSHConfigSnapshot.fingerprint(userDirectory: user, systemDirectory: system) }
    }
}
