#if CAPTURE_TESTS
import AppKit
import Darwin
import Foundation
import CoreFoundation

// xcrun swiftc -swift-version 6 -D CAPTURE_TESTS -target arm64-apple-macosx13.0
// Sources/Capture.swift tests/CaptureTests.swift -o /tmp/skitch-capture-tests
// The same test executable acts as a controllable, local fake capture helper.
// Pure checks use no screen/camera permissions, network or NSApplication.
// --termination-probe runs a separate headless NSApplication with no windows.
private final class CaptureRecord: @unchecked Sendable {
    var results: [Result<NSImage, Error>] = []
    var acknowledgements: [Result<Void, Error>] = []
    var events: [String] = []
    var allMain = true
    func received(_ result: Result<NSImage, Error>) {
        allMain = allMain && Thread.isMainThread
        results.append(result); events.append("capture")
    }
    func acknowledged(_ result: Result<Void, Error>) {
        allMain = allMain && Thread.isMainThread
        acknowledgements.append(result); events.append("ack")
    }
}

private actor FakeCameraSession: CaptureSessionStopping {
    private var stopping = false
    private var stopped = false
    private var calls = 0
    func stop() async {
        stopping = true; calls += 1
        try? await Task.sleep(nanoseconds: 200_000_000)
        stopped = true
    }
    func state() -> (Bool, Bool, Int) { (stopping, stopped, calls) }
}

private final class CaptureTerminationJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let started = Date()
    private var events: [[String: Any]] = []
    private var terminated = false
    init(_ url: URL) { self.url = url }
    func record(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        events.append(["event": event, "seconds": Date().timeIntervalSince(started),
                       "main": Thread.isMainThread,
                       "mode": Thread.isMainThread ? RunLoop.current.currentMode?.rawValue ?? "none" : "worker"])
        do { try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
        catch { fputs("termination journal: \(error.localizedDescription)\n", stderr) }
    }
    func didTerminate() { lock.lock(); terminated = true; lock.unlock() }
    var isTerminated: Bool { lock.lock(); defer { lock.unlock() }; return terminated }
}

@MainActor
private final class CaptureTerminationProbe: NSObject, NSApplicationDelegate {
    let scenario: String
    let rig: CaptureTests.Rig
    let journal: CaptureTerminationJournal
    private var deciding = false
    private var acknowledgementCount = 0
    private var captureCallbacks = 0
    private var valid = true
    private var readiness: Timer?

    init(scenario: String, rig: CaptureTests.Rig, journal: CaptureTerminationJournal) {
        self.scenario = scenario; self.rig = rig; self.journal = journal
        super.init()
    }

    static func run(scenario: String, evidence: URL) {
        do {
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            CaptureTests.root = evidence.appendingPathComponent("resources", isDirectory: true)
            try FileManager.default.createDirectory(at: CaptureTests.root, withIntermediateDirectories: false)
            try CaptureTests.writeFixture()
            let rig = try CaptureTests.make("stubborn", timeout: 30, killDelay: 0.15)
            let journal = CaptureTerminationJournal(evidence.appendingPathComponent("events.json"))
            let delegate = CaptureTerminationProbe(scenario: scenario, rig: rig, journal: journal)
            let app = NSApplication.shared
            _ = app.setActivationPolicy(.prohibited) // No windows, Dock, menu or focus activation.
            app.delegate = delegate
            let marker = rig.marker, resources = CaptureTests.root
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                guard !journal.isTerminated else { return }
                journal.record("watchdog-timeout")
                // The watchdog can only kill this probe's own fake helper.
                if let data = try? Data(contentsOf: marker),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pid = object["pid"] as? NSNumber { _ = kill(pid.int32Value, SIGKILL) }
                try? FileManager.default.removeItem(at: resources)
                _exit(70)
            }
            delegate.prepare()
            withExtendedLifetime(delegate) { app.run() }
            // A successful NSApplication termination exits before returning here.
            journal.record("application-run-returned-unexpectedly")
            exit(71)
        } catch { fputs("termination probe: \(error.localizedDescription)\n", stderr); exit(72) }
    }

    private func prepare() {
        journal.record("headless-app-ready")
        switch scenario {
        case "busy-result", "busy-void":
            rig.coordinator.capture(mode: "fullscreen", completion: captured)
            readiness = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, FileManager.default.fileExists(atPath: self.rig.marker.path) else { return }
                    self.readiness?.invalidate(); self.readiness = nil
                    self.journal.record("fake-helper-ready")
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            }
        case "delayed-result":
            rig.coordinator.capture(mode: "fullscreen", delay: 30, completion: captured)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        case "session-result":
            rig.coordinator.testCaptureSession(FakeCameraSession(), completion: captured)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        default:
            // Match production smoke: terminate from a main-dispatch callback.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NSApp.terminate(nil) }
        }
    }

    private func captured(_ result: Result<NSImage, Error>) {
        captureCallbacks += 1
        valid = valid && Thread.isMainThread && CaptureTests.cancellation(result)
        journal.record("capture-cancel-callback")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        journal.record("termination-enter")
        deciding = true
        switch scenario {
        case "task-control":
            Task { @MainActor in self.acknowledged(.success(())) }
        case "dispatch-control":
            DispatchQueue.main.async { self.acknowledged(.success(())) }
        case "runloop-control":
            let modes = [RunLoop.Mode.default.rawValue, RunLoop.Mode.modalPanel.rawValue,
                         RunLoop.Mode.eventTracking.rawValue, RunLoop.Mode.common.rawValue] as CFArray
            CFRunLoopPerformBlock(CFRunLoopGetMain(), modes) {
                MainActor.assumeIsolated { self.acknowledged(.success(())) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        case "idle-void", "busy-void":
            rig.coordinator.shutdown { self.acknowledged(self.rig.coordinator.lastShutdownError.map { .failure($0) } ?? .success(())) }
        case "offthread-result":
            let coordinator = rig.coordinator
            DispatchQueue.global(qos: .utility).async {
                coordinator.shutdown { result in MainActor.assumeIsolated { self.acknowledged(result) } }
            }
        default:
            if scenario == "queued-result" { rig.coordinator.capture(mode: "fullscreen", completion: captured) }
            rig.coordinator.shutdown(completion: acknowledged)
        }
        deciding = false
        journal.record(acknowledgementCount == 1 ? "returned-terminate-now" : "returned-terminate-later")
        return acknowledgementCount == 1 ? .terminateNow : .terminateLater
    }

    private func acknowledged(_ result: Result<Void, Error>) {
        acknowledgementCount += 1
        valid = valid && Thread.isMainThread && CaptureTests.succeeded(result)
        if ["busy-result", "busy-void"].contains(scenario) {
            valid = valid && (try? CaptureTests.processExited(rig)) == true
            journal.record("helper-exit-verified")
        }
        valid = valid && CaptureTests.directories(rig).isEmpty
        journal.record("shutdown-ack")
        if !deciding { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let captured = ["busy-result", "busy-void", "delayed-result", "session-result", "queued-result"].contains(scenario)
        valid = valid && acknowledgementCount == 1 && captureCallbacks == (captured ? 1 : 0)
        journal.record(valid ? "will-terminate-pass" : "will-terminate-fail")
        journal.didTerminate()
        try? FileManager.default.removeItem(at: CaptureTests.root)
        if !valid { _exit(73) }
    }
}

@main
@MainActor
private enum CaptureTests {
    static var checks = 0
    static var coordinators: [CaptureCoordinator] = []
    static var root = FileManager.default.temporaryDirectory
        .appendingPathComponent("skitch-capture-tests-" + UUID().uuidString, isDirectory: true)
    static var fixture: URL { root.appendingPathComponent("retina.png") }

    struct Rig {
        let coordinator: CaptureCoordinator
        let directory: URL
        let temporary: URL
        let marker: URL
        var release: URL { marker.appendingPathExtension("release") }
    }

    static func main() async {
        if CommandLine.arguments.dropFirst().first == "--capture-test-helper" {
            fakeHelper(); return
        }
        if CommandLine.arguments.dropFirst().first == "--termination-probe" {
            guard CommandLine.arguments.count == 4 else { exit(64) }
            CaptureTerminationProbe.run(scenario: CommandLine.arguments[2],
                                        evidence: URL(fileURLWithPath: CommandLine.arguments[3]))
            return
        }
        var failure: Error?
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            try writeFixture()
            try await queuedCancellation()
            try await queuedShutdown()
            try await delayedCancellation()
            try await runningCancellation()
            try await lateExitShutdown()
            try await repeatedFrame()
            try await frameSnapshotAndValidation()
            try await failuresAndTimeout()
            try await cleanupFailure()
            try await shutdownAdmission()
            try await shutdownVoidAPI()
            try await serializedSessionStop()
            try await reentrantQueuedShutdown()
            for coordinator in coordinators {
                let record = CaptureRecord()
                coordinator.shutdown(completion: record.acknowledged)
                try await wait { record.acknowledgements.count == 1 }
                try expect(record.allMain, "final shutdown callback must be main")
            }
            try expect(NSApp == nil, "pure tests must never construct NSApplication")
            print("PASS CaptureTests (\(checks) checks; local fake helper, no desktop capture or permissions)")
        } catch { failure = error }
        if let failure {
            // Stop accepted helpers before leaving a failing test process.
            for coordinator in coordinators {
                let record = CaptureRecord()
                coordinator.shutdown(completion: record.acknowledged)
                try? await wait { record.acknowledgements.count == 1 }
            }
            fputs("FAIL CaptureTests: \(failure.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "CaptureTests", code: checks,
                                    userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func wait(seconds: Double = 8, _ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate() {
            if Date() > end { throw NSError(domain: "CaptureTests", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "Timed out awaiting fake helper/callback."]) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func writeFixture() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        memset(rep.bitmapData!, 255, rep.bytesPerRow * rep.pixelsHigh)
        rep.size = NSSize(width: 160, height: 90)
        try rep.representation(using: .png, properties: [:])!.write(to: fixture)
    }

    static func make(_ behavior: String = "instant", timeout: Double = 10,
                     killDelay: Double = 0.15, missingExecutable: Bool = false) throws -> Rig {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let temporary = directory.appendingPathComponent("captures", isDirectory: true)
        let marker = directory.appendingPathComponent("helper.json")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let helper = missingExecutable ? directory.appendingPathComponent("missing-helper")
            : URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let coordinator = CaptureCoordinator(testHelper: helper,
            arguments: ["--capture-test-helper", behavior, marker.path, fixture.path],
            temporaryRoot: temporary, timeout: timeout, killDelay: killDelay)
        coordinators.append(coordinator)
        return Rig(coordinator: coordinator, directory: directory, temporary: temporary, marker: marker)
    }

    static func directories(_ rig: Rig) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: rig.temporary, includingPropertiesForKeys: nil)) ?? []
    }

    static func launch(_ rig: Rig) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: rig.marker)) as! [String: Any]
    }

    static func processExited(_ rig: Rig) throws -> Bool {
        let pid = (try launch(rig)["pid"] as! NSNumber).int32Value
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    static func cancellation(_ result: Result<NSImage, Error>?) -> Bool {
        guard case .failure(let error) = result else { return false }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }

    static func errorCode(_ result: Result<NSImage, Error>?) -> Int? {
        if case .failure(let error) = result { return (error as NSError).code }
        return nil
    }

    static func succeeded(_ result: Result<Void, Error>?) -> Bool {
        if case .success = result { return true }
        return false
    }

    static func start(_ rig: Rig, mode: String = "fullscreen", delay: Double = 0) -> CaptureRecord {
        let record = CaptureRecord()
        rig.coordinator.capture(mode: mode, delay: delay, completion: record.received)
        return record
    }

    static func stopped(_ rig: Rig, _ record: CaptureRecord, shutdown: Bool = false) async throws {
        if shutdown { rig.coordinator.shutdown(completion: record.acknowledged) }
        else { rig.coordinator.cancelCapture(completion: record.acknowledged) }
        try await wait { record.acknowledgements.count == 1 }
        try expect(succeeded(record.acknowledgements.first), "clean stop must acknowledge success")
        try expect(record.results.count == 1 && cancellation(record.results.first), "capture must cancel exactly once")
        try expect(record.events == ["capture", "ack"], "capture callback must precede teardown acknowledgement")
        try expect(record.allMain, "callbacks must run on main")
        try expect(directories(rig).isEmpty, "stop acknowledgement must follow temp directory removal")
    }

    static func queuedCancellation() async throws {
        let rig = try make()
        let record = start(rig)
        try await stopped(rig, record)
        try expect(!FileManager.default.fileExists(atPath: rig.marker.path), "queued cancellation must never launch")
        try await pause(0.05)
        try expect(record.results.count == 1, "invalidated queued request must not call back again")
        let resumed = start(rig)
        try await wait { resumed.results.count == 1 }
        try expect(errorCode(resumed.results.first) == nil, "cancelled coordinator must remain reusable")
        try expect(directories(rig).isEmpty, "normal capture callback must follow cleanup too")
    }

    static func queuedShutdown() async throws {
        let rig = try make()
        let screen = start(rig)
        let web = CaptureRecord(), camera = CaptureRecord()
        rig.coordinator.captureURL(URL(string: "https://example.invalid/")!, completion: web.received)
        rig.coordinator.captureCamera(completion: camera.received)
        let ack = CaptureRecord()
        rig.coordinator.cancelCapture(completion: ack.acknowledged)
        rig.coordinator.shutdown { result in
            ack.acknowledged(result)
            if screen.results.count != 1 || web.results.count != 1 || camera.results.count != 1 { ack.allMain = false }
        }
        try await wait { ack.acknowledgements.count == 2 }
        try expect([screen, web, camera].allSatisfy { cancellation($0.results.first) && $0.results.count == 1 },
                   "shutdown must drain all queued screen/web/camera requests without creating resources")
        try expect(ack.allMain, "every accepted callback must precede shutdown acknowledgement")
        try expect(ack.acknowledgements.allSatisfy { succeeded($0) }, "concurrent stops must both acknowledge")
        try expect(directories(rig).isEmpty && !FileManager.default.fileExists(atPath: rig.marker.path), "queued shutdown cannot create files/helpers")
        try expect(NSApp == nil, "queued camera/web stop cannot open native UI or request permission")
    }

    static func delayedCancellation() async throws {
        let rig = try make()
        let record = start(rig, delay: 0.25)
        try await wait { directories(rig).count == 1 }
        try await stopped(rig, record)
        try await pause(0.35)
        try expect(!FileManager.default.fileExists(atPath: rig.marker.path), "cancelled delay must never launch later")
        try expect(record.results.count == 1, "cancelled timers must not deliver late callbacks")
    }

    static func runningCancellation() async throws {
        for behavior in ["hold", "stubborn"] {
            let rig = try make(behavior)
            let record = start(rig)
            try await wait { FileManager.default.fileExists(atPath: rig.marker.path) }
            let busy = start(rig)
            try await wait { busy.results.count == 1 }
            try expect(errorCode(busy.results.first) == 1, "a second capture must report busy")
            try await stopped(rig, record)
            try expect(try processExited(rig), "acknowledgement must follow actual helper exit/reaping")
            try await pause(0.2)
            try expect(record.results.count == 1, "helper exit cannot complete a cancelled operation again")
        }
    }

    static func lateExitShutdown() async throws {
        let rig = try make("late", killDelay: 1)
        let record = start(rig)
        try await wait { FileManager.default.fileExists(atPath: rig.marker.path) }
        rig.coordinator.shutdown(completion: record.acknowledged)
        try Data().write(to: rig.release)
        try await wait { record.acknowledgements.count == 1 }
        try expect(cancellation(record.results.first), "a late successful image must not escape shutdown")
        try expect(record.events == ["capture", "ack"], "shutdown callback order must remain deterministic")
        try expect(try processExited(rig), "natural late exit must be reaped before shutdown acknowledges")
        try expect(directories(rig).isEmpty, "late helper output must be removed before acknowledgement")
        try expect(rig.coordinator.lastCaptureMetadata == nil, "cancelled capture must not publish success metadata")
        try await pause(0.1)
        try expect(record.results.count == 1 && record.acknowledgements.count == 1, "late success and kill timer must not double-complete")
    }

    static func repeatedFrame() async throws {
        let rig = try make()
        let frame = NSRect(x: -50, y: 20, width: 160, height: 90)
        rig.coordinator.frameRect = frame
        var destinations: [String] = []
        for _ in 0..<3 {
            let record = start(rig, mode: "frame")
            try await wait { record.results.count == 1 }
            guard case .success(let image) = record.results[0] else { throw NSError(domain: "CaptureTests", code: -2) }
            let args = try launch(rig)["arguments"] as! [String]
            let index = args.firstIndex(of: "-R")!
            try expect(args[index + 1] == "-50,20,160,90", "frame must pass the same exact region on every repeat")
            try expect(!args.contains("-i") && !args.contains("-s"), "frame must never alias the crosshair picker")
            try expect(image.size == frame.size, "Retina capture must retain frame dimensions in points")
            try expect(rig.coordinator.frameRect == frame, "capture must not overwrite reusable frameRect")
            let metadata = rig.coordinator.lastCaptureMetadata
            try expect(metadata?.logicalSize == frame.size && metadata?.pixelSize == NSSize(width: 320, height: 180),
                       "sizing metadata must separate logical screen points from encoded pixels")
            try expect(metadata?.requestedFrameRect == frame && metadata?.capturedFrameRect == frame && metadata?.source == "frame",
                       "metadata must expose the requested and actual region before callback")
            try expect(directories(rig).isEmpty, "successful frame callback must follow cleanup")
            destinations.append(args.last!)
        }
        try expect(Set(destinations).count == 3, "each repeat must have a unique image path")
    }

    static func frameSnapshotAndValidation() async throws {
        let rig = try make()
        let supplied = NSRect(x: -50.25, y: 20.5, width: 160, height: 90)
        rig.coordinator.frameRect = supplied
        let record = start(rig, mode: "frame", delay: 0.15)
        try await wait { directories(rig).count == 1 }
        rig.coordinator.frameRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        try await wait { record.results.count == 1 }
        try expect(rig.coordinator.lastCaptureMetadata?.requestedFrameRect == supplied, "a delayed capture must snapshot its frame once")
        try expect(rig.coordinator.lastCaptureMetadata?.capturedFrameRect == supplied.integral, "fractional rectangle rounding must be explicit")
        try expect(rig.coordinator.frameRect?.size == NSSize(width: 10, height: 10), "finish must not overwrite a newer parent frame")
        for invalid in [NSRect.zero, NSRect(x: 0, y: 0, width: -1, height: 10),
                        NSRect(x: 0, y: 0, width: 10, height: -1),
                        NSRect(x: Double.nan, y: 0, width: 10, height: 10),
                        NSRect(x: 1e20, y: 0, width: 10, height: 10),
                        NSRect(x: 9000, y: 9000, width: 10, height: 10)] {
            rig.coordinator.frameRect = invalid
            let invalidRecord = start(rig, mode: "frame")
            try await wait { invalidRecord.results.count == 1 }
            try expect(errorCode(invalidRecord.results.first) == 9, "invalid/unattached frame must fail without launch")
            try expect(directories(rig).isEmpty, "frame validation must not leak files")
        }
    }

    static func failuresAndTimeout() async throws {
        for (behavior, expected) in [("invalid", 8), ("failure", 7), ("escape", NSUserCancelledError)] {
            let rig = try make(behavior)
            let record = start(rig, mode: behavior == "escape" ? "crosshair" : "fullscreen")
            try await wait { record.results.count == 1 }
            try expect(errorCode(record.results.first) == expected, "helper failures and picker cancellation must remain distinct")
            if behavior == "failure", case .failure(let error) = record.results[0] {
                try expect(error.localizedDescription.contains("fake helper diagnostic"), "report actual helper diagnostics")
            }
            try expect(directories(rig).isEmpty, "failed helpers must clean their temporary files")
        }
        let missing = try make(missingExecutable: true)
        let missingRecord = start(missing)
        try await wait { missingRecord.results.count == 1 }
        if case .failure(let error) = missingRecord.results[0] {
            try expect((error as NSError).domain != "SkitchRedux.Capture", "launch failure must preserve the actual Foundation error")
        } else { try expect(false, "missing helper must fail") }
        try expect(directories(missing).isEmpty, "launch failure must clean its directory")
        let timed = try make("stubborn", timeout: 0.8)
        let timedRecord = start(timed)
        try await wait { FileManager.default.fileExists(atPath: timed.marker.path) }
        try await wait { timedRecord.results.count == 1 }
        try expect(errorCode(timedRecord.results.first) == 2, "timeout must remain a real error rather than user cancellation")
        try expect(try processExited(timed), "timeout callback must follow actual helper exit")
        try expect(directories(timed).isEmpty, "timeout must remove all helper files")
        try await pause(0.2)
        try expect(timedRecord.results.count == 1, "timeout must not complete again on late process exit")
        let invalid = try make()
        for (mode, delay, code) in [("unknown", 0.0, 3), ("frame", -1.0, 4), ("fullscreen", Double.nan, 4), ("fullscreen", 3601.0, 4)] {
            let record = start(invalid, mode: mode, delay: delay)
            try await wait { record.results.count == 1 }
            try expect(errorCode(record.results.first) == code, "invalid screen inputs must report actual validation errors")
        }
        let urlRecord = CaptureRecord()
        invalid.coordinator.captureURL(URL(string: "file:///tmp/not-a-webpage")!, completion: urlRecord.received)
        try await wait { urlRecord.results.count == 1 }
        try expect(errorCode(urlRecord.results.first) == 11, "invalid webpage must fail before constructing WebKit")
    }

    static func cleanupFailure() async throws {
        let rig = try make("denied")
        let record = start(rig)
        try await wait { FileManager.default.fileExists(atPath: rig.marker.path) }
        // The fake helper denies traversal of its own temporary directory, so
        // cleanup errors are tested without native permissions or capture APIs.
        rig.coordinator.shutdown(completion: record.acknowledged)
        try await wait { record.acknowledgements.count == 1 }
        let imageURL = URL(fileURLWithPath: try launch(rig)["image"] as! String)
        let directory = imageURL.deletingLastPathComponent()
        _ = chmod(directory.path, 0o700)
        defer { try? FileManager.default.removeItem(at: directory) }
        try expect(try processExited(rig), "failed cleanup must still wait for helper exit")
        if case .failure(let error) = record.acknowledgements[0] {
            try expect((error as NSError).domain == NSCocoaErrorDomain || (error as NSError).domain == NSPOSIXErrorDomain,
                       "shutdown acknowledgement must expose the actual filesystem cleanup error")
        } else { try expect(false, "cleanup failure must not produce a fake successful acknowledgement") }
        try expect(record.results.count == 1 && !cancellation(record.results.first), "cleanup failure must not be hidden as benign cancellation")
        try expect(record.allMain, "cleanup failure callbacks must be main")
        try expect(rig.coordinator.lastShutdownError != nil, "void-compatible shutdown error property must preserve actual cleanup failure")
        var voidAcknowledged = false
        rig.coordinator.shutdown { voidAcknowledged = true }
        try expect(voidAcknowledged && rig.coordinator.lastShutdownError != nil, "idempotent void acknowledgement cannot erase an unresolved teardown error")
        let repeated = CaptureRecord()
        rig.coordinator.shutdown(completion: repeated.acknowledged)
        try await wait { repeated.acknowledgements.count == 1 }
        try expect(!succeeded(repeated.acknowledgements.first), "idempotent result acknowledgement cannot invent cleanup success")
    }

    static func shutdownAdmission() async throws {
        let rig = try make()
        let ack = CaptureRecord()
        // Exercise the nonisolated shutdown API from outside the main actor.
        await Task.detached { rig.coordinator.shutdown(completion: ack.acknowledged) }.value
        try await wait { ack.acknowledgements.count == 1 }
        let screen = start(rig), web = CaptureRecord(), camera = CaptureRecord()
        rig.coordinator.captureURL(URL(string: "https://example.invalid/")!, completion: web.received)
        rig.coordinator.captureCamera(completion: camera.received)
        try await wait { screen.results.count == 1 && web.results.count == 1 && camera.results.count == 1 }
        try expect([screen, web, camera].allSatisfy { errorCode($0.results.first) == 40 && $0.allMain },
                   "shutdown must permanently reject every capture kind on main")
        rig.coordinator.shutdown(completion: ack.acknowledged)
        rig.coordinator.cancelCapture(completion: ack.acknowledged)
        try await wait { ack.acknowledgements.count == 3 }
        try expect(ack.acknowledgements.allSatisfy { succeeded($0) } && ack.allMain, "shutdown and subsequent cancellation must be idempotent")
        try expect(directories(rig).isEmpty && !FileManager.default.fileExists(atPath: rig.marker.path), "rejected post-shutdown calls cannot create resources")
    }

    static func shutdownVoidAPI() async throws {
        for queued in [false, true] {
            let rig = try make()
            let record = queued ? start(rig) : CaptureRecord()
            var acknowledged = false
            rig.coordinator.shutdown {
                acknowledged = true
                record.acknowledged(.success(()))
            }
            try expect(acknowledged, "idle or queued-only void shutdown must acknowledge synchronously")
            try expect(record.allMain && succeeded(record.acknowledgements.first), "void shutdown callback must be main")
            if queued { try expect(cancellation(record.results.first), "queued operation must complete before synchronous shutdown ack") }
            try await pause(0.05)
            try expect(!FileManager.default.fileExists(atPath: rig.marker.path), "queued task must not run after synchronous closure")
            try expect(rig.coordinator.lastShutdownError == nil, "clean void shutdown must retain no error")
            var resultAcknowledged = false
            rig.coordinator.shutdown { (result: Result<Void, Error>) in
                resultAcknowledged = succeeded(result) && Thread.isMainThread
            }
            try expect(resultAcknowledged, "idle Result shutdown must also acknowledge synchronously on main")
        }
        let busy = try make("stubborn", killDelay: 0.4)
        let record = start(busy)
        try await wait { FileManager.default.fileExists(atPath: busy.marker.path) }
        var acknowledged = false
        busy.coordinator.shutdown {
            acknowledged = true
            record.acknowledged(.success(()))
        }
        try expect(!acknowledged, "running helper void shutdown must require terminateLater")
        try await pause(0.04)
        try expect(!acknowledged, "main actor must keep servicing work while awaiting stuck helper exit")
        try await wait { acknowledged }
        try expect(try processExited(busy), "void shutdown must acknowledge only after actual helper exit")
        try expect(record.events == ["capture", "ack"] && cancellation(record.results.first), "busy void shutdown must drain capture before ack")
        try expect(directories(busy).isEmpty, "busy void shutdown must remove helper files")
    }

    static func serializedSessionStop() async throws {
        let rig = try make()
        let resource = FakeCameraSession()
        let record = CaptureRecord()
        rig.coordinator.testCaptureSession(resource, completion: record.received)
        try await pause(0.02)
        rig.coordinator.cancelCapture(completion: record.acknowledged)
        var shutdownAcknowledged = false
        rig.coordinator.shutdown {
            shutdownAcknowledged = true
            record.acknowledged(.success(()))
        }
        try await pause(0.04)
        let pending = await resource.state()
        try expect(pending.0 && !pending.1 && !shutdownAcknowledged, "shutdown must await serialized session stop without blocking main")
        let rejected = start(rig)
        try await wait { rejected.results.count == 1 }
        try expect(errorCode(rejected.results.first) == 40, "session teardown shutdown must immediately close capture admission")
        try await wait { record.acknowledgements.count == 2 }
        let ended = await resource.state()
        try expect(ended.1 && ended.2 == 1, "concurrent cancel/shutdown must await exactly one session cleanup")
        try expect(cancellation(record.results.first) && record.results.count == 1, "session cancellation must finish exactly once")
        try expect(record.events == ["capture", "ack", "ack"] && record.allMain, "session cleanup must precede every main callback acknowledgement")
        try expect(directories(rig).isEmpty && !FileManager.default.fileExists(atPath: rig.marker.path), "fake session teardown cannot invoke any capture helper")
    }

    static func reentrantQueuedShutdown() async throws {
        let rig = try make()
        var delivered = 0
        var shutdownAck = false
        var safe = true
        let outer = CaptureRecord()
        for _ in 0..<4 {
            rig.coordinator.capture(mode: "fullscreen") { result in
                safe = safe && cancellation(result) && Thread.isMainThread
                delivered += 1
                if delivered == 1 {
                    rig.coordinator.shutdown {
                        shutdownAck = true
                        safe = safe && delivered == 4
                    }
                }
            }
        }
        rig.coordinator.cancelCapture(completion: outer.acknowledged)
        try await wait { outer.acknowledgements.count == 1 && shutdownAck }
        try expect(safe && delivered == 4, "reentrant shutdown must wait for the entire accepted callback drain")
        try expect(!FileManager.default.fileExists(atPath: rig.marker.path), "reentrant queued callbacks cannot launch a helper")
    }

    static func fakeHelper() {
        let arguments = CommandLine.arguments
        guard arguments.count > 5 else { exit(70) }
        let behavior = arguments[2]
        let marker = URL(fileURLWithPath: arguments[3])
        let fixture = URL(fileURLWithPath: arguments[4])
        let image = URL(fileURLWithPath: arguments.last!)
        if ["stubborn", "late", "denied"].contains(behavior) { signal(SIGTERM, SIG_IGN) }
        do {
            if behavior == "denied" {
                guard chmod(image.deletingLastPathComponent().path, 0) == 0 else { exit(74) }
            }
            let state: [String: Any] = ["pid": Int(getpid()), "arguments": Array(arguments.dropFirst(5)), "image": image.path]
            try JSONSerialization.data(withJSONObject: state).write(to: marker, options: .atomic)
            if ["hold", "stubborn", "late", "denied"].contains(behavior) {
                while !FileManager.default.fileExists(atPath: marker.appendingPathExtension("release").path) { usleep(10_000) }
            }
            if behavior == "escape" { exit(1) }
            if behavior == "failure" { fputs("fake helper diagnostic\n", stderr); exit(42) }
            if behavior == "invalid" { try Data("not an image".utf8).write(to: image) }
            else { try FileManager.default.copyItem(at: fixture, to: image) }
        } catch { fputs("fake helper: \(error.localizedDescription)\n", stderr); exit(75) }
    }
}
#endif
