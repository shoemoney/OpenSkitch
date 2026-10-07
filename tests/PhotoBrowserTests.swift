// Pure local-file fixtures only: no windows, Photos picker, permissions, user
// library scans, desktop input or general clipboard. Run the resulting executable.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit 
//   -framework PhotosUI -framework ImageIO Sources/PhotoBrowser.swift 
//   tests/PhotoBrowserTests.swift -o /tmp/skitch-photo-browser-tests
import AppKit
import CoreFoundation
import ImageIO
import UniformTypeIdentifiers

// Background test observations are lock-protected; no UI or Photos API involved.
private final class PhotoBrowserWorkerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var copiedURL: URL?
    private var rejected = false
    private var failure: String?
    private var acknowledgements = 0
    private var cleanedAtAcknowledgement = false
    func copied(_ url: URL) { lock.lock(); copiedURL = url; lock.unlock() }
    func finished(rejected: Bool, failure: String? = nil) {
        lock.lock(); self.rejected = rejected; self.failure = failure; lock.unlock()
    }
    func acknowledge() {
        lock.lock(); defer { lock.unlock() }
        acknowledgements += 1
        cleanedAtAcknowledgement = copiedURL.map {
            !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path)
        } ?? true
    }
    var snapshot: (url: URL?, rejected: Bool, failure: String?, acknowledgements: Int, cleaned: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (copiedURL, rejected, failure, acknowledgements, cleanedAtAcknowledgement)
    }
}

@MainActor
private final class PhotoBrowserModalAcknowledgementProbe {
    private(set) var finished = false
    private(set) var acknowledged = 0
    private(set) var modalDelivery = false
    private(set) var failure: String?
    let worker = PhotoBrowserWorkerProbe()
    func run(copySource: URL) {
        DispatchQueue.main.async {
            let work = PhotoBrowserImportWork(), done = DispatchSemaphore(value: 0)
            let admission = work.admitCopy()!
            let mode = CFRunLoopMode(rawValue: RunLoop.Mode.modalPanel.rawValue as CFString)
            let completion = PhotoBrowserShutdownCompletion {
                self.acknowledged += 1
                self.modalDelivery = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) == mode
                self.worker.acknowledge()
            }
            work.beginShutdown()
            if work.notifyWhenDrained({ completion.schedule() }) {
                self.failure = "Acknowledged an admitted copy synchronously"
            }
            let worker = self.worker
            DispatchQueue.global().async {
                defer { done.signal() }
                do {
                    let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: copySource)
                    worker.copied(lease.url)
                    let outcome = work.finishCopy(admission, result: .success(lease))
                    worker.finished(rejected: outcome == nil)
                } catch {
                    _ = work.finishCopy(admission, result: .failure(error))
                    worker.finished(rejected: true, failure: error.localizedDescription)
                }
            }
            // Real CF modal loop nested inside an executing main-queue callback,
            // as during deferred termination; no NSApplication/window/input.
            let deadline = Date().addingTimeInterval(2)
            while self.acknowledged == 0 && Date() < deadline {
                CFRunLoopRunInMode(mode, 0.01, false)
            }
            if done.wait(timeout: .now() + 2) != .success { self.failure = "Copy worker did not return" }
            self.finished = true
        }
    }
}

@main
@MainActor
enum PhotoBrowserTests {
    struct Failure: Error { let message: String }
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(message: message) }
    }
    static func fixture(_ url: URL, width: Int = 640, height: Int = 360, orientation: Int = 1) throws {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(message: "Cannot create local fixture")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: width,height: height))
        guard let image = context.makeImage() else { throw Failure(message: "Cannot render fixture") }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try expect(CGImageDestinationFinalize(destination), "Fixture encoding failed")
    }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoBrowserTests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("photo2.PNG"), second = folder.appendingPathComponent("Photo10.png")
        try fixture(first); try fixture(second, width: 100, height: 80)
        let invalid = folder.appendingPathComponent("broken.jpg"), unsupported = folder.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: invalid); try Data(contentsOf: first).write(to: unsupported)
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try fixture(nested.appendingPathComponent("private.png"))
        let link = folder.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let cases: [(String, () throws -> Void)] = [
            ("selected folder only, supported decoded images and no recursion/symlinks", {
                let entries = try PhotoBrowserCatalog.entries(in: folder)
                try expect(entries.map(\.url) == [first, second], "Unexpected file types, nested images, links, or ordering")
            }),
            ("natural stable sort and standardized URL deduplication", {
                let equivalent = folder.appendingPathComponent("nested/../photo2.PNG")
                let entries = PhotoBrowserCatalog.entries(from: [second, first, equivalent, first])
                try expect(entries.map(\.name) == ["photo2.PNG", "Photo10.png"], "Sort/deduplication changed")
            }),
            ("actual decoded metadata retains full-resolution dimensions", {
                let entry = PhotoBrowserCatalog.metadata(for: first)
                try expect(entry?.pixelWidth == 640 && entry?.pixelHeight == 360, "Native photo dimensions lost")
                try expect(entry?.typeIdentifier == UTType.png.identifier && entry?.orientation == 1, "Decoder type/orientation changed")
            }),
            ("corrupt image and unsupported extension rejected", {
                try expect(PhotoBrowserCatalog.metadata(for: invalid) == nil, "Corrupt image accepted")
                try expect(PhotoBrowserCatalog.metadata(for: unsupported) == nil, "Non-image file extension accepted")
                try expect(PhotoBrowserCatalog.metadata(for: URL(string: "https://example.com/photo.png")!) == nil, "Remote URL accessed")
            }),
            ("bounded thumbnail retains original file for import", {
                let bytes = try Data(contentsOf: first), entry = PhotoBrowserCatalog.metadata(for: first)!
                let thumbnail = PhotoBrowserCatalog.thumbnail(for: entry, maximumPixelSize: 160)
                try expect(thumbnail?.width == 160 && thumbnail?.height == 90, "Thumbnail dimensions wrong")
                try expect(entry.pixelWidth == 640 && entry.url == first, "Thumbnail substituted for original")
                try expect(try Data(contentsOf: first) == bytes, "Thumbnail modified original")
                try expect(PhotoBrowserCatalog.thumbnail(for: entry, maximumPixelSize: 0) == nil, "Invalid thumbnail bound accepted")
            }),
            ("orientation-aware thumbnail and displayed metadata", {
                let rotated = folder.appendingPathComponent("rotated.png")
                try fixture(rotated, orientation: 6)
                let entry = PhotoBrowserCatalog.metadata(for: rotated)!
                let thumbnail = PhotoBrowserCatalog.thumbnail(for: entry, maximumPixelSize: 160)
                try expect(entry.orientation == 6 && entry.displayWidth == 360 && entry.displayHeight == 640, "Rotated display metadata wrong")
                try expect(thumbnail?.width == 90 && thumbnail?.height == 160, "Orientation was not applied to thumbnail")
            }),
            ("provider copy exists through callback and is removed afterward", {
                let providerFile = folder.appendingPathComponent("provider-representation.tmp")
                let bytes = try Data(contentsOf: first); try bytes.write(to: providerFile)
                let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: providerFile), copy = lease.url
                try expect(copy.pathExtension == "png" && copy != providerFile, "Provider copy does not use decoded image type")
                try FileManager.default.removeItem(at: providerFile)
                var called = false
                lease.deliver { url in
                    called = true
                    // Assert outside the nonthrowing callback as well.
                    called = called && (try? Data(contentsOf: url)) == bytes && PhotoBrowserCatalog.metadata(for: url)?.pixelWidth == 640
                }
                try expect(called, "File unavailable while synchronous App callback decoded it")
                try expect(!FileManager.default.fileExists(atPath: copy.path) && !FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path), "Provider copy leaked after callback")
                lease.cleanup() // Cleanup is idempotent.
            }),
            ("invalid provider image rejected without a callback", {
                var rejected = false
                do { _ = try PhotoBrowserTemporaryImport.copyRepresentation(from: invalid) } catch { rejected = true }
                try expect(rejected, "Unsupported provider representation accepted")
            }),
            ("cancelled folder scan produces no stale results", {
                try expect(PhotoBrowserCatalog.entries(from: [first, second], isCancelled: { true }).isEmpty, "Cancelled results delivered")
            }),
            ("shutdown blocks late import and cleans its temporary lease", {
                let session = PhotoBrowserSession()
                var callbacks = 0
                let id = session.begin { _ in callbacks += 1 }!
                let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                session.shutdown(); session.shutdown()
                session.complete(id, opening: lease.url, lease: lease)
                try expect(callbacks == 0 && !session.accepts(id), "Shutdown allowed a late onOpen")
                try expect(session.begin { _ in callbacks += 1 } == nil, "Shutdown coordinator reopened")
                try expect(!FileManager.default.fileExists(atPath: lease.url.deletingLastPathComponent().path), "Stale Photos lease leaked after shutdown")
            }),
            ("stale success and failure cannot replace the current session", {
                let session = PhotoBrowserSession()
                var oldCallbacks = 0, newCallbacks = 0, decoded = false
                let oldID = session.begin { _ in oldCallbacks += 1 }!
                let currentID = session.begin { url in
                    newCallbacks += 1
                    decoded = PhotoBrowserCatalog.metadata(for: url)?.pixelWidth == 640
                }!
                let staleLease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                session.complete(oldID, opening: staleLease.url, lease: staleLease)
                session.complete(oldID, opening: nil, lease: nil) // Late provider failure/cancellation.
                try expect(session.accepts(currentID) && oldCallbacks == 0 && newCallbacks == 0, "Stale result changed the current session")
                try expect(!FileManager.default.fileExists(atPath: staleLease.url.path), "Stale successful copy leaked")
                let currentLease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                session.complete(currentID, opening: currentLease.url, lease: currentLease)
                session.complete(currentID, opening: first, lease: nil)
                try expect(newCallbacks == 1 && decoded && !session.accepts(currentID), "Current callback lost, repeated, or missing its original photo")
                try expect(!FileManager.default.fileExists(atPath: currentLease.url.path), "Delivered copy leaked")
            }),
            ("shutdown reentered during cleanup suppresses the queued callback", {
                let session = PhotoBrowserSession()
                var callbacks = 0
                let id = session.begin { _ in callbacks += 1 }!
                let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                session.complete(id, opening: lease.url, lease: lease) { session.shutdown() }
                try expect(callbacks == 0 && !FileManager.default.fileExists(atPath: lease.url.path), "Cleanup reentrancy delivered after shutdown or leaked a file")
            }),
            ("cancelled close remains reusable and work cancellation is idempotent", {
                let session = PhotoBrowserSession()
                var callbacks = 0
                let id = session.begin { _ in callbacks += 1 }!
                session.complete(id, opening: nil, lease: nil)
                try expect(callbacks == 0 && session.begin { _ in callbacks += 1 } != nil, "Normal Close incorrectly shut down the coordinator")
                let work = PhotoBrowserCancellation()
                try expect(!work.isCancelled, "New work starts cancelled")
                work.cancel(); work.cancel()
                try expect(work.isCancelled && PhotoBrowserCatalog.entries(from: [first], isCancelled: { work.isCancelled }).isEmpty, "Cancelled work produced catalog results")
            }),
            ("idle copy shutdown acknowledges synchronously and rejects admission", {
                let work = PhotoBrowserImportWork()
                work.beginShutdown(); work.beginShutdown()
                try expect(work.notifyWhenDrained { fatalError("Idle acknowledgement must remain synchronous") }, "Idle shutdown incorrectly queued acknowledgement")
                try expect(work.admitCopy() == nil, "Late provider callback admitted a new copy")
            }),
            ("shutdown drains an unclaimed queued copy before acknowledgement", {
                let work = PhotoBrowserImportWork(), session = PhotoBrowserSession()
                var callbacks = 0
                let sessionID = session.begin { _ in callbacks += 1 }!
                let admission = work.admitCopy()!
                let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                guard case .copied(let id) = work.finishCopy(admission, result: .success(lease)) else {
                    throw Failure(message: "Open copy was not queued")
                }
                session.shutdown(); work.beginShutdown()
                try expect(work.notifyWhenDrained { fatalError("Drained copy should acknowledge synchronously") }, "Unclaimed copy held acknowledgement")
                if let claimed = work.claim(id) { session.complete(sessionID, opening: claimed.url, lease: claimed) }
                try expect(callbacks == 0 && work.claim(id) == nil, "Queued copy delivered after shutdown")
                try expect(!FileManager.default.fileExists(atPath: lease.url.deletingLastPathComponent().path), "Acknowledged while queued temporary directory existed")
                work.release(id) // A stale queued main task may discard again.
            }),
            ("shutdown waits for an admitted worker and cleans before acknowledgement", {
                let work = PhotoBrowserImportWork(), probe = PhotoBrowserWorkerProbe()
                let admitted = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
                let acknowledged = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    defer { finished.signal() }
                    guard let id = work.admitCopy() else {
                        probe.finished(rejected: true, failure: "Worker rejected before shutdown")
                        admitted.signal(); return
                    }
                    admitted.signal()
                    guard resume.wait(timeout: .now() + 5) == .success else {
                        let error = PhotoBrowserFailure("Timed out waiting for race fixture")
                        _ = work.finishCopy(id, result: .failure(error))
                        probe.finished(rejected: true, failure: error.message); return
                    }
                    do {
                        let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                        probe.copied(lease.url)
                        let outcome = work.finishCopy(id, result: .success(lease))
                        probe.finished(rejected: outcome == nil)
                    } catch {
                        _ = work.finishCopy(id, result: .failure(error))
                        probe.finished(rejected: true, failure: error.localizedDescription)
                    }
                }
                defer { resume.signal() }
                try expect(admitted.wait(timeout: .now() + 5) == .success, "Worker was not admitted")
                work.beginShutdown()
                try expect(!work.notifyWhenDrained { probe.acknowledge(); acknowledged.signal() }, "Acknowledged before admitted copy completed")
                try expect(acknowledged.wait(timeout: .now()) == .timedOut, "Premature shutdown acknowledgement")
                try expect(work.admitCopy() == nil, "Shutdown allowed another copy worker")
                resume.signal()
                try expect(acknowledged.wait(timeout: .now() + 5) == .success, "Shutdown did not drain its worker")
                try expect(finished.wait(timeout: .now() + 5) == .success, "Copy worker did not return")
                let proof = probe.snapshot
                try expect(proof.url != nil && proof.rejected && proof.failure == nil, "Admitted fixture did not exercise a rejected successful copy")
                try expect(proof.acknowledgements == 1 && proof.cleaned, "Acknowledgement preceded cleanup or ran more than once")
            }),
            ("claimed delivery cleanup must finish before shutdown acknowledges", {
                let work = PhotoBrowserImportWork(), probe = PhotoBrowserWorkerProbe()
                let id = work.admitCopy()!
                let lease = try PhotoBrowserTemporaryImport.copyRepresentation(from: first)
                _ = work.finishCopy(id, result: .success(lease))
                try expect(work.claim(id) === lease && work.claim(id) == nil, "Lease ownership was not exclusive")
                probe.copied(lease.url)
                work.beginShutdown()
                try expect(!work.notifyWhenDrained { probe.acknowledge() }, "Shutdown acknowledged before claimed delivery returned")
                try expect(FileManager.default.fileExists(atPath: lease.url.path), "Shutdown removed a file still owned by synchronous delivery")
                work.release(id); work.release(id)
                let proof = probe.snapshot
                try expect(proof.acknowledgements == 1 && proof.cleaned, "Claim cleanup did not precede exactly one acknowledgement")
            }),
            ("failed admitted copy drains shutdown without late delivery", {
                let work = PhotoBrowserImportWork(), probe = PhotoBrowserWorkerProbe()
                let id = work.admitCopy()!
                work.beginShutdown()
                try expect(!work.notifyWhenDrained { probe.acknowledge() }, "Active failed worker was ignored")
                let result: Result<PhotoBrowserTemporaryImport, Error> = Result {
                    try PhotoBrowserTemporaryImport.copyRepresentation(from: invalid)
                }
                guard case .failure = result else { throw Failure(message: "Invalid fixture unexpectedly copied") }
                try expect(work.finishCopy(id, result: result) == nil, "Failed worker produced a late UI outcome")
                try expect(probe.snapshot.acknowledgements == 1 && work.admitCopy() == nil, "Failure did not drain terminal shutdown")
            }),
            ("busy acknowledgement runs once in a nested modal loop after cleanup", {
                let probe = PhotoBrowserModalAcknowledgementProbe()
                probe.run(copySource: first)
                let deadline = Date().addingTimeInterval(5)
                while !probe.finished && Date() < deadline {
                    CFRunLoopRunInMode(.defaultMode, 0.01, false)
                }
                CFRunLoopRunInMode(.defaultMode, 0.01, false)
                let proof = probe.worker.snapshot
                try expect(probe.finished && probe.failure == nil, "Modal acknowledgement probe did not finish: \(probe.failure ?? "timeout")")
                try expect(probe.acknowledged == 1 && probe.modalDelivery, "Acknowledgement was duplicate or stalled until default mode")
                try expect(proof.url != nil && proof.rejected && proof.failure == nil && proof.acknowledgements == 1 && proof.cleaned, "Modal acknowledgement preceded successful copy cleanup")
            })
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("PhotoBrowserTests: \(cases.count-failures)/\(cases.count) passed; no UI/library permissions exercised")
        if failures != 0 { exit(1) }
    }
}
