import AppKit
import CoreGraphics
import CoreFoundation
import Darwin
import WebKit

private func captureFailure(_ code: Int, _ message: String) -> NSError {
    NSError(domain: "SkitchRedux.Capture", code: code,
            userInfo: [NSLocalizedDescriptionKey: message])
}

private func captureCancellation() -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "Capture cancelled."])
}

// The public API accepts calls from any thread. The box only crosses into the
// main actor; the callback itself is always invoked there, exactly once.
private final class CaptureCompletion: @unchecked Sendable {
    let callback: (Result<NSImage, Error>) -> Void
    init(_ callback: @escaping (Result<NSImage, Error>) -> Void) {
        self.callback = callback
    }
}

private final class CaptureStopCompletion: @unchecked Sendable {
    let callback: (Result<Void, Error>) -> Void
    let isShutdown: Bool
    init(isShutdown: Bool = false, _ callback: @escaping (Result<Void, Error>) -> Void) {
        self.isShutdown = isShutdown
        self.callback = callback
    }
}

// terminateLater can run a nested modal loop inside an existing main-dispatch
// callback. Neither DispatchQueue.main nor MainActor Tasks can re-enter that
// queue. Run-loop delivery handles this case; the dispatch fallback also supports
// command-line async entry points that service dispatch without a CF run loop.
private final class CaptureMainJob: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@MainActor @Sendable () -> Void)?
    init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    func run() {
        precondition(Thread.isMainThread)
        lock.lock(); let callback = action; action = nil; lock.unlock()
        if let callback { MainActor.assumeIsolated { callback() } }
    }
}

private enum CaptureMainDelivery {
    static func perform(immediatelyOnMain: Bool = false,
                        _ action: @escaping @MainActor @Sendable () -> Void) {
        if immediatelyOnMain, Thread.isMainThread {
            MainActor.assumeIsolated { action() }
            return
        }
        let job = CaptureMainJob(action)
        let modes = [RunLoop.Mode.common.rawValue, RunLoop.Mode.default.rawValue,
                     RunLoop.Mode.modalPanel.rawValue, RunLoop.Mode.eventTracking.rawValue] as CFArray
        CFRunLoopPerformBlock(CFRunLoopGetMain(), modes) { job.run() }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        DispatchQueue.main.async { job.run() } // Once-only fallback, never the sole modal delivery path.
    }
}

private final class CaptureCleanupErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    func record(_ error: Error?) {
        guard let error else { return }
        lock.lock(); errors.append(error); lock.unlock()
    }
    var result: Error? {
        lock.lock(); defer { lock.unlock() }
        return captureCleanupError(errors)
    }
}

// Linearize ingress before hopping to the main actor. A stop drains even calls
// whose main-actor task has not started, and permanently closes shutdown ingress.
private final class CaptureIngress: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var stops = 0
    private var queued: [UUID: CaptureCompletion] = [:]
    private var cancelled: [CaptureCompletion] = []

    func enqueue(_ callback: CaptureCompletion) -> Result<UUID, Error> {
        lock.lock(); defer { lock.unlock() }
        if closed { return .failure(captureFailure(40, "The capture coordinator has shut down.")) }
        if stops > 0 { return .failure(captureCancellation()) }
        let id = UUID(); queued[id] = callback
        return .success(id)
    }

    func take(_ id: UUID) -> CaptureCompletion? {
        lock.lock(); defer { lock.unlock() }
        return queued.removeValue(forKey: id)
    }

    func stop(permanently: Bool) {
        lock.lock(); defer { lock.unlock() }
        closed = closed || permanently
        stops += 1
        cancelled.append(contentsOf: queued.values); queued.removeAll()
    }

    func drainCancelled() -> [CaptureCompletion] {
        lock.lock(); defer { lock.unlock() }
        let callbacks = cancelled; cancelled.removeAll()
        return callbacks
    }

    var isStopping: Bool {
        lock.lock(); defer { lock.unlock() }
        return stops > 0
    }

    func acknowledged() {
        lock.lock(); defer { lock.unlock() }
        stops -= 1
    }
}

/// Logical dimensions are points; pixelSize is the encoded raster resolution.
/// A frame's capturedFrameRect is its integral -R region. The original supplied
/// frameRect is retained unchanged, including fractional coordinates.
struct CaptureMetadata: Equatable, Sendable {
    let source: String
    let logicalSize: NSSize
    let pixelSize: NSSize
    let requestedFrameRect: NSRect?
    let capturedFrameRect: NSRect?
}

// Keep visibility ownership in the coordinator; tests replace only native UI.
@MainActor
protocol CaptureApplicationVisibility: Sendable {
    var isHidden: Bool { get }
    var isActive: Bool { get }
    func hide()
    func unhide()
    func activate()
    func keyWindowRestorer() -> (@MainActor () -> Void)?
}

@MainActor
protocol CaptureKeyWindow: AnyObject {
    var isVisible: Bool { get }
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: CaptureKeyWindow {}

@MainActor
func captureKeyWindowRestorer(_ window: (any CaptureKeyWindow)?) -> (@MainActor () -> Void)? {
    guard let window else { return nil }
    return { [weak window] in
        // finish calls this after native unhide/activation. A normal hidden
        // window is visible again then; an ordered-out/closed window stays out.
        guard let window, window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class NativeCaptureApplicationVisibility: CaptureApplicationVisibility {
    nonisolated init() {}
    var isHidden: Bool { NSApplication.shared.isHidden }
    var isActive: Bool { NSApplication.shared.isActive }
    func hide() { NSApplication.shared.hide(nil) }
    func unhide() { NSApplication.shared.unhide(nil) }
    func activate() { NSApplication.shared.activate(ignoringOtherApps: true) }
    func keyWindowRestorer() -> (@MainActor () -> Void)? {
        captureKeyWindowRestorer(NSApplication.shared.keyWindow)
    }
}

private struct CaptureEnvironment: Sendable {
    var executable = URL(fileURLWithPath: "/usr/sbin/screencapture")
    var arguments: [String] = []
    var temporaryRoot = FileManager.default.temporaryDirectory
    var testDisplays: [NSRect]? = nil
    var settleDelay = 0.3
    var screenTimeout = 120.0
    var killDelay = 2.0
}

private struct ScreenshotExit: @unchecked Sendable {
    let result: Result<Data, Error>
    let cleanupError: Error?
}

private final class ScreenshotProcess: @unchecked Sendable {
    let process = Process()
    // Accessed only by the main actor; distinguishes a cancelled delay from exit.
    var launched = false
    let directory: URL
    let imageURL: URL
    let diagnosticURL: URL
    let diagnosticHandle: FileHandle
    private let killDelay: Double
    private let lock = NSLock()
    private var exit: ScreenshotExit?
    private var waiters: [@Sendable (ScreenshotExit) -> Void] = []
    private var escalation: DispatchWorkItem?
    private var signalErrors: [Error] = []

    init(environment: CaptureEnvironment) throws {
        killDelay = environment.killDelay
        directory = environment.temporaryRoot
            .appendingPathComponent("skitch-capture-" + UUID().uuidString, isDirectory: true)
        imageURL = directory.appendingPathComponent("capture.png")
        diagnosticURL = directory.appendingPathComponent("diagnostics.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            guard FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw captureFailure(10, "Could not create the capture diagnostic file.")
            }
            diagnosticHandle = try FileHandle(forWritingTo: diagnosticURL)
        } catch {
            do { try FileManager.default.removeItem(at: directory) }
            catch let cleanupError { throw captureCleanupError([error, cleanupError])! }
            throw error
        }
    }

    private func cleanup() -> Error? {
        var errors: [Error] = []
        do { try diagnosticHandle.close() } catch { errors.append(error) }
        do { try FileManager.default.removeItem(at: directory) } catch { errors.append(error) }
        return captureCleanupError(errors)
    }

    func monitor(interactive: Bool) {
        DispatchQueue.global(qos: .utility).async { [self] in
            // Never wait for a helper on the AppKit thread. This also reaps it.
            process.waitUntilExit()
            let result = Result<Data, Error> {
                let diagnostic = String(decoding: try Data(contentsOf: diagnosticURL), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let hasFile = FileManager.default.fileExists(atPath: imageURL.path)
                if process.terminationReason == .exit, process.terminationStatus == 0, hasFile {
                    return try Data(contentsOf: imageURL)
                }
                if interactive, process.terminationReason == .exit,
                   process.terminationStatus == 1, !hasFile, diagnostic.isEmpty {
                    throw captureCancellation()
                }
                let detail = diagnostic.isEmpty
                    ? "No image file was produced. If Control was held, the system picker may have sent the image to the clipboard."
                    : diagnostic
                throw captureFailure(7, "Screen capture exited with status \(process.terminationStatus) (\(process.terminationReason == .exit ? "exit" : "signal")). \(detail)")
            }
            let cleanupError = cleanup()
            lock.lock()
            let outcome = ScreenshotExit(result: result,
                                         cleanupError: captureCleanupError(signalErrors + (cleanupError.map { [$0] } ?? [])))
            exit = outcome
            escalation?.cancel(); escalation = nil
            let callbacks = waiters; waiters.removeAll()
            lock.unlock()
            callbacks.forEach { $0(outcome) }
        }
    }

    private func observeExit(_ callback: @escaping @Sendable (ScreenshotExit) -> Void) {
        lock.lock()
        if let exit { lock.unlock(); callback(exit) }
        else { waiters.append(callback); lock.unlock() }
    }

    func exited() async -> ScreenshotExit {
        await withCheckedContinuation { continuation in
            observeExit { continuation.resume(returning: $0) }
        }
    }

    func teardown(completion: @escaping @Sendable (Error?) -> Void) {
        if launched {
            DispatchQueue.global(qos: .utility).async { [self] in
                stop()
                observeExit { completion($0.cleanupError) }
            }
        } else {
            DispatchQueue.global(qos: .utility).async { [self] in completion(cleanup()) }
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard exit == nil, escalation == nil, process.isRunning else { return }
        if kill(process.processIdentifier, SIGTERM) != 0, errno != ESRCH {
            signalErrors.append(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        let item = DispatchWorkItem { [self] in
            lock.lock(); defer { lock.unlock() }
            guard exit == nil, process.isRunning else { return }
            if kill(process.processIdentifier, SIGKILL) != 0, errno != ESRCH {
                // Preserve the actual signal error. Still wait
                // for real process exit; a timer is never a successful ack.
                signalErrors.append(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
            }
        }
        escalation = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killDelay, execute: item)
    }
}

private func captureCleanupError(_ errors: [Error]) -> Error? {
    guard let first = errors.first else { return nil }
    if errors.count == 1 { return first }
    return NSError(domain: "SkitchRedux.Capture", code: 41,
                   userInfo: [NSLocalizedDescriptionKey: errors.map { $0.localizedDescription }.joined(separator: "; "),
                              NSUnderlyingErrorKey: first, "CleanupErrors": errors])
}

/// One capture at a time. Cancellation is NSCocoaErrorDomain/NSUserCancelledError
/// (3072), so callers can suppress an error alert without suppressing real errors.
/// Screen modes: crosshair = rectangle; fullscreen = main display; window =
/// system window picker; frame = the supplied repeatable screen rectangle.
/// The original Skitch see-through frame preview belongs to the parent UI and
/// is not implemented here.
@MainActor
final class CaptureCoordinator: NSObject, WKNavigationDelegate {
    /// Global screen coordinates with a top-left origin (main display baseline),
    /// matching screencapture -R. Negative origins support secondary displays.
    /// The parent supplies its canvas rectangle; a missing frame is an error.
    var frameRect: NSRect? = nil

    /// Updated before a successful capture callback, and cleared when the next
    /// operation begins. Frame NSImage.size equals the actual -R region in points;
    /// Retina pixel dimensions remain available separately here.
    private(set) var lastCaptureMetadata: CaptureMetadata?
    /// The termination-friendly void overload preserves actual teardown failures
    /// here before acknowledgement. The Result overload returns the same error.
    private(set) var lastShutdownError: Error?

    private let ingress = CaptureIngress()
    private let environment: CaptureEnvironment
    private let applicationVisibility: (any CaptureApplicationVisibility)?
    private var cleaningUp = false
    private var finishingResult: Result<NSImage, Error>?
    private var stopWaiters: [CaptureStopCompletion] = []
    private var deliveringCallbacks = 0
    private var teardownError: Error?
    private var source = ""
    private var requestedFrame: NSRect?
    private var capturedFrame: NSRect?

    private var operationID: UUID?
    private var completion: CaptureCompletion?
    private var lifetime: CaptureCoordinator?
    private var timeout: Task<Void, Never>?
    private var delayedCapture: Task<Void, Never>?
    private var screenshot: ScreenshotProcess?
    private var selectionPicker: (any CaptureSelectionPicking)?
    private var countdown: (any CaptureCountdownPresenting)?
    private var captureFlash: (any CaptureFlashPresenting)?
    private let nativeSelection: Bool
    private let nativeCountdown: Bool
    private var nativeFlash = false
    var onSound: ((String) -> Void)?
    var isCapturing: Bool { operationID != nil || cleaningUp }
    private var hidApplication = false
    private var wasActive = false
    private var previousKeyWindowRestorer: (@MainActor () -> Void)?

    // A real, ordered off-screen window keeps WebKit attached and rendering.
    private var webView: WKWebView?
    private var webWindow: NSWindow?
    private var snapshotStarted = false

    nonisolated override init() {
        environment = CaptureEnvironment()
        nativeSelection = true; nativeCountdown = true
        nativeFlash = true
        applicationVisibility = NativeCaptureApplicationVisibility()
        super.init()
    }

    #if CAPTURE_TESTS
    // Test-only injection bypasses display/permission/AppKit activation entirely.
    // Production always uses the system helper and native permission preflight.
    nonisolated init(testHelper: URL, arguments: [String], temporaryRoot: URL,
                     displays: [NSRect] = [NSRect(x: -1000, y: -1000, width: 3000, height: 3000)],
                     settleDelay: Double = 0, timeout: Double = 2, killDelay: Double = 0.1,
                     applicationVisibility: (any CaptureApplicationVisibility)? = nil,
                     selectionPicker: (any CaptureSelectionPicking)? = nil,
                     countdown: (any CaptureCountdownPresenting)? = nil,
                     captureFlash: (any CaptureFlashPresenting)? = nil) {
        environment = CaptureEnvironment(executable: testHelper, arguments: arguments,
                                         temporaryRoot: temporaryRoot, testDisplays: displays,
                                         settleDelay: settleDelay,
                                         screenTimeout: timeout, killDelay: killDelay)
        self.applicationVisibility = applicationVisibility
        self.selectionPicker = selectionPicker; self.countdown = countdown
        self.captureFlash = captureFlash
        nativeSelection = selectionPicker != nil; nativeCountdown = countdown != nil
        super.init()
    }
    #endif

    /// Cancels accepted/queued work. Acknowledges on main only after helper exit,
    /// file removal. Captures may resume after this ack.
    /// The cancelled capture completes exactly once before ack; a real teardown
    /// failure is reported instead of being hidden as NSUserCancelledError.
    nonisolated func cancelCapture(completion: @escaping (Result<Void, Error>) -> Void) {
        requestStop(permanently: false, completion: completion)
    }

    /// Permanent, idempotent closure. Call before replying to terminateLater.
    /// Rejected requests subsequently receive a shutdown error on main. Accepted
    /// callbacks are drained before this ack; late native delegates are ignored.
    /// macOS-owned permission prompts/WebKit child processes cannot be killed by
    /// this API; our views/delegates are detached and the helper process is stopped.
    /// When called on the main thread, idle acknowledgement is synchronous.
    /// Busy acknowledgements service AppKit's modal termination run-loop mode.
    nonisolated func shutdown(completion: @escaping (Result<Void, Error>) -> Void) {
        requestStop(permanently: true, completion: completion)
    }

    /// Parent termination integration. Fully idle/queued-only shutdown acknowledges
    /// synchronously on main after invalidating and cancelling queued requests.
    /// Busy callers must return terminateLater and reply when this callback runs.
    func shutdown(completion: @escaping @MainActor () -> Void) {
        ingress.stop(permanently: true)
        performStop(CaptureStopCompletion(isShutdown: true) { _ in
            MainActor.assumeIsolated { completion() }
        })
    }

    private nonisolated func requestStop(permanently: Bool,
                                         completion: @escaping (Result<Void, Error>) -> Void) {
        ingress.stop(permanently: permanently)
        let acknowledgement = CaptureStopCompletion(isShutdown: permanently, completion)
        CaptureMainDelivery.perform(immediatelyOnMain: true) {
            self.performStop(acknowledgement)
        }
    }

    private func performStop(_ acknowledgement: CaptureStopCompletion) {
        stopWaiters.append(acknowledgement)
        let cancelled = ingress.drainCancelled()
        deliveringCallbacks += 1
        cancelled.forEach { $0.callback(.failure(captureCancellation())) }
        deliveringCallbacks -= 1
        if let id = operationID {
            finish(.failure(captureCancellation()), id: id)
        } else if cleaningUp {
            finishingResult = .failure(captureCancellation())
        } else {
            acknowledgeStops(.success(()))
        }
    }

    private nonisolated func submit(_ completion: @escaping (Result<NSImage, Error>) -> Void,
                                    start: @escaping @MainActor @Sendable (CaptureCompletion) -> Void) {
        let callback = CaptureCompletion(completion)
        switch ingress.enqueue(callback) {
        case .success(let id):
            // Run-loop delivery, not a MainActor Task: nested run loops still reach it.
            CaptureMainDelivery.perform {
                guard let callback = self.ingress.take(id) else { return }
                start(callback)
            }
        case .failure(let error):
            Task { @MainActor in callback.callback(.failure(error)) }
        }
    }

    /// Inclusion is fixed at submission, including while queued or delayed.
    /// False hides a visible app; true leaves its existing visibility unchanged.
    nonisolated func capture(mode: String, delay: Double = 0, includeApp: Bool = false,
                             completion: @escaping (Result<NSImage, Error>) -> Void) {
        submit(completion) { callback in
            self.startScreenCapture(mode: mode, delay: delay, includeApp: includeApp, callback: callback)
        }
    }

    nonisolated func captureURL(_ url: URL,
                                completion: @escaping (Result<NSImage, Error>) -> Void) {
        submit(completion) { callback in self.startURLCapture(url, callback: callback) }
    }

    private func begin(_ callback: CaptureCompletion) -> UUID? {
        guard operationID == nil, !cleaningUp else {
            callback.callback(.failure(captureFailure(1, "Another capture is already in progress.")))
            return nil
        }
        let id = UUID()
        operationID = id
        completion = callback
        lastCaptureMetadata = nil
        source = ""
        requestedFrame = nil
        capturedFrame = nil
        lifetime = self // Keep even a temporary coordinator alive until completion.
        return id
    }

    private func armTimeout(_ seconds: Double, id: UUID, message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard let self, self.operationID == id else { return }
            self.finish(.failure(captureFailure(2, message)), id: id)
        }
    }

    private func finish(_ result: Result<NSImage, Error>, id: UUID) {
        guard operationID == id else { return }
        // Invalidate before tearing down delegates, sheets or processes; those
        // can cause late callbacks and must never complete a newer request.
        operationID = nil
        cleaningUp = true
        finishingResult = result
        selectionPicker?.cancel()
        countdown?.cancel()
        timeout?.cancel()
        timeout = nil
        delayedCapture?.cancel()
        delayedCapture = nil
        let request = screenshot
        screenshot = nil
        if hidApplication {
            applicationVisibility?.unhide()
            if wasActive {
                applicationVisibility?.activate()
                previousKeyWindowRestorer?()
            }
        }
        hidApplication = false
        previousKeyWindowRestorer = nil
        wasActive = false

        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        webWindow?.close()
        webWindow = nil
        snapshotStarted = false

        guard request != nil else {
            completeCleanup(error: nil)
            return
        }
        // Start teardown directly on background queues. A MainActor Task here
        // would never even start when terminateLater is nested inside main dispatch.
        let group = DispatchGroup()
        let errors = CaptureCleanupErrors()
        if let request {
            group.enter()
            request.teardown { error in errors.record(error); group.leave() }
        }
        group.notify(queue: .global(qos: .utility)) { @Sendable in
            let error = errors.result
            CaptureMainDelivery.perform { self.completeCleanup(error: error) }
        }
    }

    private func completeCleanup(error: Error?) {
        guard cleaningUp, let result = finishingResult else { return }
        if let error {
            teardownError = captureCleanupError((teardownError.map { [$0] } ?? []) + [error])
        }
        var delivered: Result<NSImage, Error> = ingress.isStopping ? .failure(captureCancellation()) : result
        if let error {
            let prior: Error? = if case .failure(let failure) = result { failure } else { nil }
            delivered = .failure(captureCleanupError([error] + (prior.map { [$0] } ?? []))!)
        }
        if case .success(let image) = delivered {
            let representation = image.representations.max {
                Double($0.pixelsWide) * Double($0.pixelsHigh) < Double($1.pixelsWide) * Double($1.pixelsHigh)
            }
            lastCaptureMetadata = CaptureMetadata(source: source, logicalSize: image.size,
                                                  pixelSize: NSSize(width: representation?.pixelsWide ?? 0,
                                                                    height: representation?.pixelsHigh ?? 0),
                                                  requestedFrameRect: requestedFrame,
                                                  capturedFrameRect: capturedFrame)
        }
        let callback = completion
        completion = nil
        finishingResult = nil
        cleaningUp = false
        lifetime = nil
        deliveringCallbacks += 1
        if case .success = delivered, let plan = flashPlan() {
            if captureFlash == nil, nativeFlash { captureFlash = OriginalCaptureFlashController() }
            captureFlash?.play(frame: plan.frame, deflashDuration: plan.deflashDuration)
        }
        callback?.callback(delivered)
        deliveringCallbacks -= 1
        acknowledgeStops(error.map { .failure($0) } ?? .success(()))
    }

    private func flashPlan() -> OriginalCaptureFlashPlan? {
        let screens = environment.testDisplays ?? NSScreen.screens.map(\.frame)
        return OriginalCaptureFlashPlan.make(source: source, requested: requestedFrame,
                                             captured: capturedFrame, mainScreen: screens.first)
    }

    private func acknowledgeStops(_ result: Result<Void, Error>) {
        guard deliveringCallbacks == 0 else { return }
        // A stop can close ingress from another thread just before its actor task
        // is installed. Retain teardown failures so that task cannot acknowledge
        // fake success after cleanup has already finished (or on repeated shutdown).
        let delivered: Result<Void, Error>
        if case .failure = result { delivered = result }
        else { delivered = teardownError.map { .failure($0) } ?? result }
        let waiters = stopWaiters; stopWaiters.removeAll()
        // Open ingress before invoking acknowledgement, permitting the caller
        // to synchronously start its next capture from a cancellation callback.
        waiters.forEach { _ in ingress.acknowledged() }
        waiters.forEach {
            if $0.isShutdown {
                if case .failure(let error) = delivered { lastShutdownError = error }
                // Once permanently closed, an idempotent idle ack must not erase
                // a failure that the caller has not yet read.
            }
            $0.callback(delivered)
        }
    }

    private func startScreenCapture(mode: String, delay: Double, includeApp: Bool,
                                    callback: CaptureCompletion) {
        guard let id = begin(callback) else { return }
        let mode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        source = mode
        guard ["crosshair", "fullscreen", "window", "frame"].contains(mode) else {
            finish(.failure(captureFailure(3, "Unknown capture mode: \(mode).")), id: id)
            return
        }
        guard delay.isFinite, delay >= 0, delay <= 3_600 else {
            finish(.failure(captureFailure(4, "Capture delay must be between 0 and 3600 seconds.")), id: id)
            return
        }
        guard environment.testDisplays != nil || !NSScreen.screens.isEmpty else {
            finish(.failure(captureFailure(5, "There is no display available to capture.")), id: id)
            return
        }
        var rectangleArgument: String?
        if mode == "frame" {
            guard let rect = frameRect, let argument = screenRectangleArgument(rect) else {
                finish(.failure(captureFailure(9, "Frame capture needs a finite, nonempty frameRect in global top-left screen coordinates that intersects an attached display.")), id: id)
                return
            }
            rectangleArgument = argument
            requestedFrame = rect
            capturedFrame = rect.integral
        }
        // Preflight prevents permission denial being confused with picker Esc.
        guard environment.testDisplays != nil || CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            finish(.failure(captureFailure(6, "Screen Recording access is not granted. Enable this app in System Settings > Privacy & Security > Screen Recording, then reopen it if macOS requests that.")), id: id)
            return
        }
        // A native permission dialog may pump a nested run loop and allow a stop.
        guard operationID == id else { return }
        do {
            let request = try ScreenshotProcess(environment: environment)
            screenshot = request
            let process = request.process
            process.executableURL = environment.executable
            // Picker/timer teardown shares the same operation identity as the
            // subprocess. Native selection occurs before the timed countdown.
            if let app = applicationVisibility, !includeApp, !app.isHidden {
                hidApplication = true
                wasActive = app.isActive
                previousKeyWindowRestorer = app.keyWindowRestorer()
                app.hide()
            }
            armTimeout(delay + environment.screenTimeout, id: id, message: "Screen capture timed out.")
            if nativeSelection, mode == "crosshair" || mode == "window" {
                if selectionPicker == nil { selectionPicker = OriginalCapturePicker() }
                selectionPicker?.begin(windowOnly: mode == "window") { [weak self, request] result in
                    guard let self, self.operationID == id else { return }
                    switch result {
                    case .failure(let error): self.finish(.failure(error), id: id)
                    case .success(let selection):
                        guard let region = self.screenRectangleArgument(selection.rect) else {
                            self.finish(.failure(captureFailure(9, "The selected area is outside the attached displays.")), id: id)
                            return
                        }
                        self.requestedFrame = selection.rect
                        self.capturedFrame = selection.windowID == nil ? selection.rect.integral : nil
                        var args = ["-x", "-t", "png"]
                        if let window = selection.windowID { args += ["-l", String(window)] }
                        else { args += ["-R", region] }
                        let chosenDelay = OriginalCaptureTiming.selectedDelay(flags: selection.modifiers, explicitDelay: delay)
                        if chosenDelay > 0 { args += ["-C"] }
                        let top = NSScreen.screens.first?.frame.maxY ?? 0
                        let rect = NSRect(x: selection.rect.minX, y: top - selection.rect.maxY,
                                          width: selection.rect.width, height: selection.rect.height)
                        self.prepareScreenshot(request, arguments: args, delay: chosenDelay, rect: rect, interactive: false, id: id)
                    }
                }
            } else {
                var args = ["-x", "-t", "png"]
                switch mode {
                case "fullscreen": args += ["-m"]
                case "window": args += ["-i", "-w"]
                case "frame": args += ["-R", rectangleArgument!]
                default: args += ["-i"] // Crosshair also allows clicking a window.
                }
                if delay > 0, mode == "fullscreen" || mode == "frame" { args += ["-C"] }
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let rect: NSRect
                if let frame = requestedFrame { rect = NSRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height) }
                else { rect = NSScreen.screens.first?.frame ?? .zero }
                prepareScreenshot(request, arguments: args, delay: delay, rect: rect,
                                  interactive: mode == "crosshair" || mode == "window", id: id)
            }
        } catch {
            finish(.failure(error), id: id)
        }
    }

    private func prepareScreenshot(_ request: ScreenshotProcess, arguments: [String], delay: Double,
                                   rect: NSRect, interactive: Bool, id: UUID) {
        guard operationID == id else { return }
        request.process.arguments = environment.arguments + arguments + [request.imageURL.path]
        request.process.standardInput = FileHandle.nullDevice
        request.process.standardOutput = FileHandle.nullDevice
        request.process.standardError = request.diagnosticHandle
        armTimeout(delay + environment.screenTimeout, id: id, message: "Screen capture timed out.")
        let launch = { [weak self, request] in
            guard let self, self.operationID == id else { return }
            self.delayedCapture = Task { [weak self, request] in
                do { try await Task.sleep(nanoseconds: UInt64((self?.environment.settleDelay ?? 0) * 1_000_000_000)) }
                catch { return }
                guard let self, self.operationID == id else { return }
                do {
                    try request.process.run(); request.launched = true
                    request.monitor(interactive: interactive)
                    Task { @MainActor [weak self, request] in
                        let outcome = await request.exited()
                        guard let self, self.operationID == id else { return }
                        self.finish(self.decode(outcome.result, frame: self.capturedFrame), id: id)
                    }
                } catch { self.finish(.failure(error), id: id) }
            }
        }
        if delay > 0, nativeCountdown {
            if countdown == nil { countdown = OriginalCaptureCountdown() }
            countdown?.start(rect: rect, parent: nil, delay: delay, cue: { [weak self] in
                guard let self, self.operationID == id else { return }
                self.onSound?("pre-snap-countdown")
            }, completion: launch)
        } else if delay > 0 {
            delayedCapture = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
                guard let self, self.operationID == id else { return }
                launch()
            }
        } else { launch() }
    }

    private func screenRectangleArgument(_ rect: NSRect) -> String? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              rect.size.width > 0, rect.size.height > 0 else { return nil }
        let integral = rect.integral
        guard let x = Int32(exactly: integral.minX), let y = Int32(exactly: integral.minY),
              let width = Int32(exactly: integral.width), let height = Int32(exactly: integral.height),
              width > 0, height > 0 else { return nil }
        let displays: [NSRect]
        if let supplied = environment.testDisplays { displays = supplied }
        else {
            let baseline = NSScreen.screens.first?.frame.maxY ?? 0
            displays = NSScreen.screens.map { screen in
                NSRect(x: screen.frame.minX, y: baseline - screen.frame.maxY,
                       width: screen.frame.width, height: screen.frame.height)
            }
        }
        let intersectsDisplay = displays.contains { !integral.intersection($0).isEmpty }
        guard intersectsDisplay else { return nil }
        return "\(x),\(y),\(width),\(height)"
    }

    private func decode(_ result: Result<Data, Error>, frame: NSRect? = nil) -> Result<NSImage, Error> {
        result.flatMap { data in
            guard let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0 else {
                return .failure(captureFailure(8, "Capture returned missing or undecodable image data."))
            }
            // Encoded DPI/Retina resolution must not change a repeat frame's
            // logical dimensions or cause the parent's next frame to grow.
            if let frame { image.size = frame.size }
            return .success(image)
        }
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else { return false }
        return true
    }

    private func startURLCapture(_ url: URL, callback: CaptureCompletion) {
        guard let id = begin(callback) else { return }
        source = "web"
        guard isWebURL(url) else {
            finish(.failure(captureFailure(11, "Enter an absolute HTTP or HTTPS webpage URL with a host and without embedded credentials.")), id: id)
            return
        }
        armTimeout(30, id: id, message: "The webpage did not finish loading and rendering within 30 seconds.")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let size = NSSize(width: 1280, height: 900)
        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        view.navigationDelegate = self
        let left = NSScreen.screens.map { $0.frame.minX }.min() ?? 0
        let window = NSWindow(contentRect: NSRect(x: left - size.width - 100, y: 0,
                                                 width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.contentView = view
        webView = view
        webWindow = window
        window.orderBack(nil)
        // This captures a rendered 1280 x 900 viewport, not an unbounded page.
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView, let id = operationID else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            guard let url = navigationAction.request.url, isWebURL(url) else {
                decisionHandler(.cancel)
                finish(.failure(captureFailure(12, "The webpage tried to navigate to an unsupported URL.")), id: id)
                return
            }
            // Do not follow a script forever while the snapshot is being made.
            if snapshotStarted { decisionHandler(.cancel); return }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView, let id = operationID else {
            decisionHandler(.cancel)
            return
        }
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            decisionHandler(.cancel)
            var info: [String: Any] = [NSLocalizedDescriptionKey: "The webpage returned HTTP \(response.statusCode)."]
            if let url = response.url { info[NSURLErrorFailingURLErrorKey] = url }
            finish(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse,
                                    userInfo: info)), id: id)
            return
        }
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            finish(.failure(captureFailure(13, "WebKit cannot render this response as a webpage.")), id: id)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, let id = operationID, !snapshotStarted else { return }
        snapshotStarted = true
        // Font loading and a brief settling interval give WebKit time to paint.
        // Off-screen requestAnimationFrame can pause, so do not rely on it.
        // The overall deadline covers stalled fonts, JavaScript and snapshots.
        webView.callAsyncJavaScript("""
            if (document.fonts) await document.fonts.ready;
            await new Promise(resolve => setTimeout(resolve, 250));
            return true;
            """, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
            guard let self, let webView, webView === self.webView, self.operationID == id else { return }
            switch result {
            case .failure(let error): self.finish(.failure(error), id: id)
            case .success:
                let configuration = WKSnapshotConfiguration()
                configuration.rect = webView.bounds
                configuration.snapshotWidth = NSNumber(value: webView.bounds.width)
                configuration.afterScreenUpdates = true
                webView.takeSnapshot(with: configuration) { [weak self] image, error in
                    guard let self, self.operationID == id else { return }
                    if let error { self.finish(.failure(error), id: id) }
                    else if let image, image.isValid, image.size.width > 0, image.size.height > 0 {
                        self.finish(.success(image), id: id)
                    } else {
                        self.finish(.failure(captureFailure(14, "WebKit returned no rendered snapshot.")), id: id)
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, let id = operationID else { return }
        finish(.failure(error), id: id)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard webView === self.webView, let id = operationID else { return }
        finish(.failure(error), id: id)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, let id = operationID else { return }
        finish(.failure(captureFailure(15, "The webpage rendering process terminated.")), id: id)
    }
}
