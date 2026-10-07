import AppKit
import AVFoundation
import CoreGraphics
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

private final class ScreenshotProcess: @unchecked Sendable {
    let process = Process()
    // Accessed only by the main actor; distinguishes a cancelled delay from exit.
    var launched = false
    let directory: URL
    let imageURL: URL
    let diagnosticURL: URL
    let diagnosticHandle: FileHandle

    init() throws {
        directory = FileManager.default.temporaryDirectory
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
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cleanup() {
        try? diagnosticHandle.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        // A stuck system picker must not keep the app hidden or leak a child.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

/// One capture at a time. Cancellation is NSCocoaErrorDomain/NSUserCancelledError
/// (3072), so callers can suppress an error alert without suppressing real errors.
/// Screen modes: crosshair = rectangle; fullscreen = main display; window =
/// system window picker; frame = the supplied repeatable screen rectangle.
/// The original Skitch see-through frame preview belongs to the parent UI and
/// is not implemented here.
@MainActor
final class CaptureCoordinator: NSObject, WKNavigationDelegate, NSWindowDelegate {
    /// Global screen coordinates with a top-left origin (main display baseline),
    /// matching screencapture -R. Negative origins support secondary displays.
    /// The parent supplies its canvas rectangle; a missing frame is an error.
    var frameRect: NSRect? = nil

    /// False hides the app before screen capture. True deliberately includes it
    /// if it lies inside the captured area. Camera preview remains visible.
    var showAppDuringCapture: Bool = false

    private var operationID: UUID?
    private var completion: CaptureCompletion?
    private var lifetime: CaptureCoordinator?
    private var timeout: Task<Void, Never>?
    private var delayedCapture: Task<Void, Never>?
    private var screenshot: ScreenshotProcess?
    private var hidApplication = false
    private var wasActive = false
    private weak var previousKeyWindow: NSWindow?

    // A real, ordered off-screen window keeps WebKit attached and rendering.
    private var webView: WKWebView?
    private var webWindow: NSWindow?
    private var snapshotStarted = false

    private var camera: CameraCaptureSession?
    private var cameraPanel: NSPanel?
    private weak var cameraParent: NSWindow?
    private var cameraPreview: CameraPreviewView?
    private var cameraStatus: NSTextField?
    private var cameraCaptureButton: NSButton?
    private var takingPhoto = false

    nonisolated override init() { super.init() }

    nonisolated func capture(mode: String, delay: Double = 0,
                             completion: @escaping (Result<NSImage, Error>) -> Void) {
        let callback = CaptureCompletion(completion)
        Task { @MainActor in
            self.startScreenCapture(mode: mode, delay: delay, callback: callback)
        }
    }

    nonisolated func captureURL(_ url: URL,
                                completion: @escaping (Result<NSImage, Error>) -> Void) {
        let callback = CaptureCompletion(completion)
        Task { @MainActor in self.startURLCapture(url, callback: callback) }
    }

    nonisolated func captureCamera(completion: @escaping (Result<NSImage, Error>) -> Void) {
        let callback = CaptureCompletion(completion)
        Task { @MainActor in self.startCameraCapture(callback: callback) }
    }

    private func begin(_ callback: CaptureCompletion) -> UUID? {
        guard operationID == nil else {
            callback.callback(.failure(captureFailure(1, "Another capture is already in progress.")))
            return nil
        }
        let id = UUID()
        operationID = id
        completion = callback
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
        timeout?.cancel()
        timeout = nil
        delayedCapture?.cancel()
        delayedCapture = nil
        let callback = completion
        completion = nil

        if let request = screenshot {
            if request.launched { request.stop() }
            else {
                request.process.terminationHandler = nil
                request.cleanup()
            }
        }
        screenshot = nil // A launched process owns cleanup in its termination handler.
        if hidApplication {
            NSApplication.shared.unhide(nil)
            if wasActive {
                NSApplication.shared.activate(ignoringOtherApps: true)
                previousKeyWindow?.makeKeyAndOrderFront(nil)
            }
        }
        hidApplication = false
        previousKeyWindow = nil
        wasActive = false

        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        webWindow?.close()
        webWindow = nil
        snapshotStarted = false

        cameraPreview?.previewLayer?.session = nil
        cameraPreview = nil
        camera?.stop()
        camera = nil
        if let panel = cameraPanel {
            panel.delegate = nil
            if let parent = panel.sheetParent { parent.endSheet(panel, returnCode: .cancel) }
            panel.orderOut(nil)
            panel.close()
        }
        cameraPanel = nil
        cameraParent = nil
        cameraStatus = nil
        cameraCaptureButton = nil
        takingPhoto = false
        lifetime = nil
        callback?.callback(result)
    }

    private func startScreenCapture(mode: String, delay: Double, callback: CaptureCompletion) {
        guard let id = begin(callback) else { return }
        let mode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["crosshair", "fullscreen", "window", "frame"].contains(mode) else {
            finish(.failure(captureFailure(3, "Unknown capture mode: \(mode).")), id: id)
            return
        }
        guard delay.isFinite, delay >= 0, delay <= 3_600 else {
            finish(.failure(captureFailure(4, "Capture delay must be between 0 and 3600 seconds.")), id: id)
            return
        }
        guard !NSScreen.screens.isEmpty else {
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
        }
        // Preflight prevents permission denial being confused with picker Esc.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            finish(.failure(captureFailure(6, "Screen Recording access is not granted. Enable this app in System Settings > Privacy & Security > Screen Recording, then reopen it if macOS requests that.")), id: id)
            return
        }
        do {
            let request = try ScreenshotProcess()
            screenshot = request
            let process = request.process
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            var arguments = ["-x", "-t", "png"]
            switch mode {
            case "fullscreen": arguments += ["-m"]
            case "window": arguments += ["-i", "-w"]
            case "frame": arguments += ["-R", rectangleArgument!]
            default: arguments += ["-i", "-s"]
            }
            // Each argument is separate; no shell and no clipboard/default-file flags.
            process.arguments = arguments + [request.imageURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            // A file, rather than an undrained pipe, cannot deadlock on stderr.
            process.standardError = request.diagnosticHandle
            let interactive = mode == "crosshair" || mode == "window"
            process.terminationHandler = { [weak self, request] child in
                child.terminationHandler = nil
                defer { request.cleanup() }
                let result = Result<Data, Error> {
                    // A diagnostic read failure is a real error, not an empty
                    // stderr stream that could accidentally look like Esc.
                    let diagnostic = String(decoding: try Data(contentsOf: request.diagnosticURL), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasFile = FileManager.default.fileExists(atPath: request.imageURL.path)
                    if child.terminationReason == .exit, child.terminationStatus == 0, hasFile {
                        return try Data(contentsOf: request.imageURL)
                    }
                    if interactive, child.terminationReason == .exit,
                       child.terminationStatus == 1, !hasFile, diagnostic.isEmpty {
                        // The system picker exits 1 without a file/diagnostic on Esc.
                        // Never classify signals or diagnostic errors as cancellation.
                        throw captureCancellation()
                    }
                    let detail = diagnostic.isEmpty
                        ? "No image file was produced. If Control was held, the system picker may have sent the image to the clipboard."
                        : diagnostic
                    throw captureFailure(7, "Screen capture exited with status \(child.terminationStatus) (\(child.terminationReason == .exit ? "exit" : "signal")). \(detail)")
                }
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id else { return }
                    self.finish(self.decode(result), id: id)
                }
            }
            let app = NSApplication.shared
            hidApplication = !showAppDuringCapture && !app.isHidden
            wasActive = app.isActive
            previousKeyWindow = app.keyWindow
            if hidApplication { app.hide(nil) }
            armTimeout(delay + 120, id: id, message: "Screen capture timed out.")
            delayedCapture = Task { [weak self, request] in
                // Give WindowServer time to remove this app before the shot.
                do { try await Task.sleep(nanoseconds: UInt64((delay + 0.3) * 1_000_000_000)) }
                catch { return }
                guard let self, self.operationID == id else { return }
                do {
                    try request.process.run()
                    request.launched = true
                }
                catch {
                    request.process.terminationHandler = nil
                    request.cleanup()
                    self.finish(.failure(error), id: id)
                }
            }
        } catch {
            finish(.failure(error), id: id)
        }
    }

    private func screenRectangleArgument(_ rect: NSRect) -> String? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return nil }
        let integral = rect.integral
        guard let x = Int32(exactly: integral.minX), let y = Int32(exactly: integral.minY),
              let width = Int32(exactly: integral.width), let height = Int32(exactly: integral.height),
              width > 0, height > 0 else { return nil }
        let baseline = NSScreen.screens.first?.frame.maxY ?? 0
        let intersectsDisplay = NSScreen.screens.contains { screen in
            let display = NSRect(x: screen.frame.minX, y: baseline - screen.frame.maxY,
                                 width: screen.frame.width, height: screen.frame.height)
            return !integral.intersection(display).isEmpty
        }
        guard intersectsDisplay else { return nil }
        return "\(x),\(y),\(width),\(height)"
    }

    private func decode(_ result: Result<Data, Error>) -> Result<NSImage, Error> {
        result.flatMap { data in
            guard let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0 else {
                return .failure(captureFailure(8, "Capture returned missing or undecodable image data."))
            }
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

    private func startCameraCapture(callback: CaptureCompletion) {
        guard let id = begin(callback) else { return }
        // Calling the permission API without this key terminates the host process.
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish(.failure(captureFailure(20, "Camera capture requires NSCameraUsageDescription in this app's Info.plist.")), id: id)
            return
        }
        showCameraSheet()
        armTimeout(60, id: id, message: "Camera permission was not resolved within 60 seconds.")
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureCamera(id: id)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id else { return }
                    if granted { self.configureCamera(id: id) }
                    else { self.cameraPermissionDenied(id: id) }
                }
            }
        case .denied, .restricted: cameraPermissionDenied(id: id)
        @unknown default:
            finish(.failure(captureFailure(21, "macOS reported an unknown camera authorization status.")), id: id)
        }
    }

    private func cameraPermissionDenied(id: UUID) {
        finish(.failure(captureFailure(22, "Camera access is denied or restricted. Check System Settings > Privacy & Security > Camera and the app's camera entitlement.")), id: id)
    }

    private func configureCamera(id: UUID) {
        guard operationID == id else { return }
        cameraStatus?.stringValue = "Starting camera…"
        armTimeout(30, id: id, message: "The camera did not start within 30 seconds.")
        let session = CameraCaptureSession(onReady: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id, let camera = self.camera else { return }
                self.cameraPreview?.attach(camera.session)
                self.cameraCaptureButton?.isEnabled = true
                self.cameraStatus?.stringValue = "Ready. Capture a photo or cancel."
                self.armTimeout(300, id: id, message: "Camera capture timed out while waiting for a photo.")
            }
        }, onResult: { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id else { return }
                self.finish(self.decode(result), id: id)
            }
        })
        camera = session // Retain before any asynchronous configuration can fail.
        session.start()
    }

    private func showCameraSheet() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 550),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Camera Capture"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = NSView()
        panel.contentView = content
        let heading = NSTextField(labelWithString: "Camera Capture")
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        let status = NSTextField(wrappingLabelWithString: "Waiting for camera permission…")
        status.font = .systemFont(ofSize: 20)
        let preview = CameraPreviewView()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelCamera(_:)))
        cancel.font = .systemFont(ofSize: 20)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let capture = NSButton(title: "Capture Photo", target: self, action: #selector(takeCameraPhoto(_:)))
        capture.font = .systemFont(ofSize: 20)
        capture.bezelStyle = .rounded
        capture.keyEquivalent = "\r"
        capture.isEnabled = false
        for view in [heading, status, preview, cancel, capture] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            status.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            preview.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 16),
            preview.bottomAnchor.constraint(equalTo: capture.topAnchor, constant: -20),
            capture.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            capture.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            capture.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            cancel.trailingAnchor.constraint(equalTo: capture.leadingAnchor, constant: -16),
            cancel.centerYAnchor.constraint(equalTo: capture.centerYAnchor),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        cameraPanel = panel
        cameraStatus = status
        cameraPreview = preview
        cameraCaptureButton = capture
        let app = NSApplication.shared
        if let parent = app.keyWindow ?? app.mainWindow, parent.attachedSheet == nil {
            cameraParent = parent
            parent.beginSheet(panel) { [weak self] _ in
                guard let self, self.cameraPanel === panel, let id = self.operationID else { return }
                self.finish(.failure(captureCancellation()), id: id)
            }
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
        app.activate(ignoringOtherApps: true)
    }

    @objc private func takeCameraPhoto(_ sender: NSButton) {
        guard let id = operationID, let camera, !takingPhoto else { return }
        takingPhoto = true
        cameraCaptureButton?.isEnabled = false
        cameraStatus?.stringValue = "Capturing photo…"
        armTimeout(20, id: id, message: "The camera did not deliver a photo within 20 seconds.")
        camera.takePhoto()
    }

    @objc private func cancelCamera(_ sender: Any?) {
        guard cameraPanel != nil, let id = operationID else { return }
        finish(.failure(captureCancellation()), id: id)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === cameraPanel { cancelCamera(nil); return false }
        return true
    }
}

@MainActor
private final class CameraPreviewView: NSView {
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityLabel("Live camera preview")
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func attach(_ session: AVCaptureSession) {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect // Same framing as the resulting photo.
        layer?.addSublayer(preview)
        previewLayer = preview
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

// AVFoundation configuration, start/stop, capture state and delegate results are
// serialized here, never on AppKit's main thread. All coordinator callbacks hop
// to the main actor. Queued cleanup retains this object until the hardware stops.
private final class CameraCaptureSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "SkitchRedux.Camera", qos: .userInitiated)
    private let onReady: @Sendable () -> Void
    private let onResult: @Sendable (Result<Data, Error>) -> Void
    private var observers: [NSObjectProtocol] = []
    private var finished = false
    private var cleanedUp = false
    private var photoRequested = false
    private var photoID: Int64?
    private var photoResult: Result<Data, Error>?

    init(onReady: @escaping @Sendable () -> Void,
         onResult: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.onReady = onReady
        self.onResult = onResult
        super.init()
    }

    func start() {
        queue.async { [self] in
            guard !finished else { return }
            do {
                guard let device = AVCaptureDevice.default(for: .video) else {
                    throw captureFailure(23, "No camera is connected or available.")
                }
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                do {
                    if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
                    guard session.canAddInput(input) else {
                        throw captureFailure(24, "The camera input cannot be added to the capture session.")
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        throw captureFailure(25, "This camera does not support native still-photo capture.")
                    }
                    session.addOutput(output)
                    session.commitConfiguration()
                } catch {
                    session.commitConfiguration()
                    throw error
                }
                observeFailures()
                session.startRunning()
                guard session.isRunning else {
                    // Per the SDK, startup failure arrives as a runtime-error
                    // notification. Let the queued observer report its actual
                    // NSError; the coordinator deadline guards a missing event.
                    return
                }
                onReady()
            } catch { deliver(.failure(error)) }
        }
    }

    private func observeFailures() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError,
                                            object: session, queue: nil) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                ?? captureFailure(27, "The camera capture session reported a runtime error.")
            self?.queue.async { [weak self] in self?.deliver(.failure(error)) }
        })
        observers.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted,
                                            object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.deliver(.failure(captureFailure(28, "The camera session was interrupted by macOS or another application.")))
            }
        })
    }

    func takePhoto() {
        queue.async { [self] in
            guard !finished, !photoRequested else { return }
            guard session.isRunning, let connection = output.connection(with: .video),
                  connection.isEnabled, connection.isActive else {
                deliver(.failure(captureFailure(29, "The camera has no active video connection.")))
                return
            }
            photoRequested = true
            let codecs = output.availablePhotoCodecTypes
            guard let codec = codecs.contains(.jpeg) ? AVVideoCodecType.jpeg : codecs.first else {
                deliver(.failure(captureFailure(32, "This camera has no supported encoded photo format.")))
                return
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            photoID = settings.uniqueID
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let result: Result<Data, Error>
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation(), !data.isEmpty { result = .success(data) }
        else { result = .failure(captureFailure(30, "The camera returned no decodable photo data.")) }
        let id = photo.resolvedSettings.uniqueID
        queue.async { [self] in
            guard !finished, photoID == id else { return }
            photoResult = result
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let id = resolvedSettings.uniqueID
        queue.async { [self] in
            guard !finished, photoID == id else { return }
            if let error { deliver(.failure(error)) }
            else { deliver(photoResult ?? .failure(captureFailure(31, "The camera finished capture without delivering a photo."))) }
        }
    }

    private func deliver(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        // Report the actual capture error immediately, even if hardware teardown
        // takes time. The serial queue retains us until cleanup has completed.
        onResult(result)
        cleanup()
    }

    func stop() {
        queue.async { [self] in
            finished = true
            cleanup()
        }
    }

    private func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        photoResult = nil
        photoID = nil
    }
}
