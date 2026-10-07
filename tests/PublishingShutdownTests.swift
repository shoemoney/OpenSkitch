import AppKit
import CoreFoundation
import Darwin

// xcrun swiftc -swift-version 5 -framework AppKit -framework Security Sources/Publishing.swift tests/PublishingShutdownTests.swift -o /tmp/skitch-publishing-shutdown-tests
// /tmp/skitch-publishing-shutdown-tests --test
// Real local fake processes, no uploads, network, Keychain, clipboard access or preview windows.
private final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Value) { lock.lock(); self.value = value; lock.unlock() }
}

// A real NSApplication quit loop without a window, Dock icon, preview bundle, or input.
// Reply false exits the nested quit loop without terminating the standalone test executable.
private final class NativePublishingQuitProbe: NSObject, NSApplicationDelegate {
    let coordinator: PublishingCoordinator
    let root: URL
    let helperPID: pid_t
    var insideDispatch = false
    var returned = false
    var acknowledgements = 0
    var acknowledgedInsideQuit = false
    var acknowledgedOnMain = false
    var cleanedBeforeAck = false
    var timedOut = false
    var requests = 0
    init(coordinator: PublishingCoordinator, root: URL, helperPID: pid_t) {
        self.coordinator = coordinator; self.root = root; self.helperPID = helperPID
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requests += 1
        coordinator.shutdown { (result: Result<Void, Error>) in
            self.acknowledgements += 1
            self.acknowledgedOnMain = Thread.isMainThread
            self.acknowledgedInsideQuit = self.insideDispatch && !self.returned
            self.cleanedBeforeAck = PublishingShutdownTests.clean(result)
                && !FileManager.default.fileExists(atPath: self.root.path)
                && !PublishingShutdownTests.alive(self.helperPID)
            sender.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }
    func stopRun(_ app: NSApplication) {
        app.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, subtype: 0, data1: 0, data2: 0) {
            app.postEvent(event, atStart: true)
        }
    }
}

@main
enum PublishingShutdownTests {
    static var checks = 0
    static let resultURL = URL(string: "https://example.com/never-uploaded.png")!
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw PublishingFailure("SHUTDOWN SELF-CHECK FAILED: " + message) }
        checks += 1
    }
    static func pump(until condition: () -> Bool, seconds: TimeInterval = 8) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        try expect(condition(), "asynchronous work completed before deadline")
    }
    static func cancelled(_ result: Result<URL, Error>?) -> Bool {
        guard case .failure(let error)? = result else { return false }
        return (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError
    }
    static func clean(_ result: Result<Void, Error>?) -> Bool {
        guard case .success? = result else { return false }; return true
    }
    static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    static func main() throws {
        guard CommandLine.arguments.contains("--test") else { print("Use --test for fake-process shutdown checks."); return }
        try expect(Thread.isMainThread, "test drives the parent's main-thread integration contract")
        try idleAndRejectedWork()
        try queuedCancellation()
        try runningProcessAndHelper()
        try exitedParentAndHelper()
        try completingRaceAndRetry()
        try timeoutCleanup()
        try cleanupFailureAndRetry()
        try shutdownFromWorker()
        try nativeNestedQuit()
        print("Publishing shutdown checks passed: \(checks). No uploads or preview apps were run.")
    }

    static func idleAndRejectedWork() throws {
        var copies = 0, acknowledgements = 0, ran = false
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in copies += 1 })
        coordinator.shutdown { acknowledgements += 1 }
        try expect(acknowledgements == 1, "idle void shutdown acknowledges synchronously")
        coordinator.shutdown { acknowledgements += 1 }
        try expect(acknowledgements == 2, "each repeated shutdown invocation acknowledges once")
        var rejected: Result<URL, Error>?
        coordinator.beginTransfer(copiesPublicURL: true, work: { _ in ran = true; return resultURL }) { rejected = $0 }
        try expect(cancelled(rejected) && !ran && copies == 0, "shutdown rejects work without invoking transfer or clipboard")
    }

    static func queuedCancellation() throws {
        let queue = DispatchQueue(label: "publishing.shutdown.queued")
        queue.suspend(); var resumed = false
        defer { if !resumed { queue.resume() } }
        let ran = Locked(false)
        var result: Result<URL, Error>?, ack: Result<Void, Error>?, ackCount = 0, copies = 0
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(queue: queue), clipboardWriter: { _ in copies += 1 })
        coordinator.beginTransfer(copiesPublicURL: true, work: { _ in ran.set(true); return resultURL }) { result = $0 }
        let before = Date()
        coordinator.shutdown { (value: Result<Void, Error>) in ack = value; ackCount += 1 }
        try expect(Date().timeIntervalSince(before) < 0.1 && ack == nil, "queued shutdown returns without blocking or premature acknowledgement")
        queue.resume(); resumed = true
        try pump(until: { ack != nil })
        try expect(clean(ack) && ackCount == 1 && cancelled(result) && !ran.get() && copies == 0, "queued transfer never starts and shutdown completes once")
    }

    static func runningProcessAndHelper() throws {
        let directory = Locked<URL?>(nil)
        var result: Result<URL, Error>?, copies = 0, acks = 0
        var ack: Result<Void, Error>?, events: [String] = []
        var voidAcks = 0
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in copies += 1 })
        coordinator.beginTransfer(copiesPublicURL: true, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownFake-")
            directory.set(root)
            try Data("private fake screenshot".utf8).write(to: root.appendingPathComponent("image"))
            // Both shell and child ignore TERM, forcing the real group-stop escalation path.
            let script = "trap '' TERM; /bin/sleep 60 & child=$!; printf '%s\\n' \"$child\" > \"$1\"; wait"
            _ = try PublishingProcess.run(executable: "/bin/sh", arguments: ["-c", script, "fake-transfer", root.appendingPathComponent("child.pid").path], timeout: 60, cancellation: context)
            return resultURL
        }) { result = $0; events.append("transfer finished") }
        try pump(until: {
            guard let root = directory.get() else { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent("child.pid").path)
        })
        let root = directory.get()!
        let pid = pid_t(try String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        try expect(alive(pid), "fake SSH helper actually started")
        let before = Date()
        coordinator.shutdown { (value: Result<Void, Error>) in ack = value; acks += 1; events.append("shutdown acknowledged") }
        coordinator.shutdown { try! expect(Thread.isMainThread, "active void acknowledgement runs on main"); voidAcks += 1 }
        coordinator.shutdown { voidAcks += 1 }
        try expect(Date().timeIntervalSince(before) < 0.1 && ack == nil, "running shutdown never waits on main")
        try pump(until: { ack != nil })
        try expect(clean(ack) && acks == 1, "running shutdown acknowledges successful cleanup once")
        try expect(voidAcks == 2, "concurrent void shutdown invocations each acknowledge once")
        try expect(!alive(pid), "helper process exited before acknowledgement")
        try expect(!FileManager.default.fileExists(atPath: root.path), "private temp folder removed before acknowledgement")
        try expect(cancelled(result) && copies == 0, "cancelled running transfer cannot copy a public URL")
        try expect(events == ["transfer finished", "shutdown acknowledged"], "completion precedes shutdown acknowledgement")
    }

    static func exitedParentAndHelper() throws {
        let directory = Locked<URL?>(nil)
        var result: Result<URL, Error>?, acknowledged = false
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in })
        coordinator.beginTransfer(copiesPublicURL: false, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownOrphan-"); directory.set(root)
            // Parent exits immediately; its child keeps stdout open and ignores TERM.
            let script = "trap '' TERM; /bin/sleep 60 & printf '%s\\n' \"$!\" > \"$1\"; exit 0"
            _ = try PublishingProcess.run(executable: "/bin/sh", arguments: ["-c", script, "fake-transfer", root.appendingPathComponent("child.pid").path], timeout: 60, cancellation: context)
            return resultURL
        }) { result = $0 }
        try pump(until: {
            guard let root = directory.get() else { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent("child.pid").path)
        })
        let root = directory.get()!
        let pid = pid_t(try String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        try expect(alive(pid), "helper survives its already-exited parent")
        coordinator.shutdown { acknowledged = true }
        try pump(until: { acknowledged })
        try expect(!alive(pid) && !FileManager.default.fileExists(atPath: root.path) && cancelled(result), "shutdown waits for orphan helper and pipe exit before removing its files")
    }

    static func completingRaceAndRetry() throws {
        let queue = DispatchQueue(label: "publishing.shutdown.completing")
        let workerReturned = DispatchSemaphore(value: 0), directory = Locked<URL?>(nil)
        var result: Result<URL, Error>?, ack: Result<Void, Error>?, copies: [URL] = []
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(queue: queue), clipboardWriter: { copies.append($0) })
        coordinator.beginTransfer(copiesPublicURL: true, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownCompleted-")
            directory.set(root); try Data([1,2,3]).write(to: root.appendingPathComponent("image"))
            return resultURL
        }) { result = $0 }
        // This runs after the serial worker has enqueued its success onto main. Keep main unpumped
        // until cancellation marks that still-undelivered operation invalid.
        queue.async { workerReturned.signal() }
        try expect(workerReturned.wait(timeout: .now() + 2) == .success, "worker successfully completed before cancellation")
        try expect(result == nil && copies.isEmpty, "success is pending main-thread delivery")
        coordinator.cancelPublishing { (value: Result<Void, Error>) in ack = value }
        try pump(until: { ack != nil })
        try expect(clean(ack) && cancelled(result) && copies.isEmpty, "cancellation suppresses already-queued successful URL delivery")
        try expect(!FileManager.default.fileExists(atPath: directory.get()!.path), "completed race cleans owned temporary files")
        var success: Result<URL, Error>?
        coordinator.beginTransfer(copiesPublicURL: true, work: { _ in resultURL }) { success = $0 }
        try pump(until: { success != nil })
        try expect(copies == [resultURL], "positive control copies once and cancellation reopens publishing")
        var privateSuccess: Result<URL, Error>?
        coordinator.beginTransfer(copiesPublicURL: false, work: { _ in resultURL }) { privateSuccess = $0 }
        try pump(until: { privateSuccess != nil })
        try expect(copies == [resultURL], "private success still never copies")
    }

    static func timeoutCleanup() throws {
        let directory = Locked<URL?>(nil)
        var result: Result<URL, Error>?, copies = 0
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in copies += 1 })
        coordinator.beginTransfer(copiesPublicURL: true, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownTimeout-"); directory.set(root)
            _ = try PublishingProcess.run(executable: "/bin/sleep", arguments: ["60"], timeout: 0.05, cancellation: context)
            return resultURL
        }) { result = $0 }
        try pump(until: { result != nil })
        guard case .failure = result! else { throw PublishingFailure("Timeout was reported as success.") }
        try expect(copies == 0 && !FileManager.default.fileExists(atPath: directory.get()!.path), "timeout stops process and cleans its private folder")
        var acknowledged = false
        coordinator.shutdown { acknowledged = true }
        try expect(acknowledged, "failed transfer with completed cleanup permits idle shutdown")
    }

    static func cleanupFailureAndRetry() throws {
        let failRemoval = Locked(true), directory = Locked<URL?>(nil)
        let worker = PublishingWorkController(makeContext: {
            PublishingCancellation(removeDirectory: { url in
                if failRemoval.get() { throw PublishingFailure("Injected filesystem removal failure.") }
                try FileManager.default.removeItem(at: url)
            })
        })
        var result: Result<URL, Error>?, copies = 0
        let coordinator = PublishingCoordinator(workController: worker, clipboardWriter: { _ in copies += 1 })
        coordinator.beginTransfer(copiesPublicURL: true, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownRetry-"); directory.set(root)
            try Data([1]).write(to: root.appendingPathComponent("image")); return resultURL
        }) { result = $0 }
        try pump(until: { result != nil })
        var first: Result<Void, Error>?
        coordinator.shutdown { (value: Result<Void, Error>) in first = value }
        try pump(until: { first != nil })
        guard case .failure = first! else { throw PublishingFailure("Cleanup failure was acknowledged as safe to terminate.") }
        try expect(copies == 0 && FileManager.default.fileExists(atPath: directory.get()!.path), "cleanup failure preserves tracked resources and suppresses clipboard")
        var pendingAcks = 0, retryFinished = false
        coordinator.shutdown { pendingAcks += 1 }
        coordinator.shutdown { (_: Result<Void, Error>) in retryFinished = true }
        try pump(until: { retryFinished })
        try expect(pendingAcks == 0, "void acknowledgement remains pending after cleanup failure")
        failRemoval.set(false)
        var ackCount = 0
        coordinator.shutdown { ackCount += 1 }
        try pump(until: { ackCount > 0 })
        try expect(ackCount == 1 && !FileManager.default.fileExists(atPath: directory.get()!.path), "later shutdown retries cleanup and acknowledges exactly once")
        try expect(pendingAcks == 1, "successful cleanup retry also acknowledges the original void request exactly once")
    }

    static func shutdownFromWorker() throws {
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in })
        var acknowledgements = 0, callbackWasMain = false
        DispatchQueue.global().async {
            coordinator.shutdown { acknowledgements += 1; callbackWasMain = Thread.isMainThread }
        }
        try pump(until: { acknowledgements > 0 })
        try expect(callbackWasMain && acknowledgements == 1, "off-main shutdown marshals its single acknowledgement to main")
    }

    static func nativeNestedQuit() throws {
        let directory = Locked<URL?>(nil)
        var result: Result<URL, Error>?, copies = 0
        let coordinator = PublishingCoordinator(workController: PublishingWorkController(), clipboardWriter: { _ in copies += 1 })
        coordinator.beginTransfer(copiesPublicURL: true, work: { context in
            let root = try context.makeTemporaryDirectory(prefix: "SkitchShutdownNativeQuit-"); directory.set(root)
            try Data([1,2,3]).write(to: root.appendingPathComponent("image"))
            let script = "trap '' TERM; /bin/sleep 60 & printf '%s\\n' \"$!\" > \"$1\"; wait"
            _ = try PublishingProcess.run(executable: "/bin/sh", arguments: ["-c", script, "fake-transfer", root.appendingPathComponent("child.pid").path], timeout: 60, cancellation: context)
            return resultURL
        }) { result = $0 }
        try pump(until: {
            guard let root = directory.get() else { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent("child.pid").path)
        })
        let root = directory.get()!
        let pid = pid_t(try String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        try expect(alive(pid) && result == nil, "native quit starts with an actually busy transfer")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = NativePublishingQuitProbe(coordinator: coordinator, root: root, helperPID: pid)
        app.delegate = probe
        let watchdogDone = Locked(false)
        // Independent CF watchdog bounds even the old broken main-dispatch delivery. It needs no
        // keyboard event or click to escape terminateLater, and does not use production delivery.
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            guard !watchdogDone.get() else { return }
            let loop = CFRunLoopGetMain()!
            var modes: [CFString] = [CFRunLoopMode.commonModes.rawValue, CFRunLoopMode.defaultMode.rawValue, RunLoop.Mode.modalPanel.rawValue as CFString]
            if let current = CFRunLoopCopyCurrentMode(loop) { modes.append(current.rawValue) }
            CFRunLoopPerformBlock(loop, modes as CFArray) {
                guard !watchdogDone.get() else { return }
                probe.timedOut = true
                app.reply(toApplicationShouldTerminate: false)
                probe.stopRun(app)
            }
            CFRunLoopWakeUp(loop)
        }
        DispatchQueue.main.async {
            probe.insideDispatch = true
            app.terminate(nil) // AppKit's actual nested quit loop inside the occupied dispatch queue.
            probe.returned = true; probe.insideDispatch = false
            probe.stopRun(app)
        }
        app.run()
        watchdogDone.set(true); app.delegate = nil
        try expect(!probe.timedOut && probe.returned && probe.requests == 1, "native nested quit exits without input before its watchdog")
        try expect(probe.acknowledgedInsideQuit && probe.acknowledgedOnMain && probe.acknowledgements == 1, "busy acknowledgement reaches main inside terminateLater before main-dispatch returns")
        try expect(probe.cleanedBeforeAck && cancelled(result) && copies == 0, "native nested quit acknowledges helper exit and temp cleanup without a late clipboard write")
        var repeated = 0
        coordinator.shutdown { repeated += 1 }
        try expect(repeated == 1 && probe.acknowledgements == 1, "modal delivery runs each acknowledgement once despite multiple registered modes")
    }
}
