import AppKit
import UniformTypeIdentifiers

/// Frame preview clears only the canvas hole; application controls keep an
/// opaque backdrop so their adaptive label colors remain readable.
final class FrameChromeView: NSView {
    weak var canvasScrollView: NSScrollView?
    var usesRecoveredBezel = false
    private lazy var bezelImages: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        for name in ["TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right"] {
            if let url = Bundle.main.url(forResource: "docWin_" + name, withExtension: "png"), let image = NSImage(contentsOf: url) { images[name] = image }
        }
        return images
    }()
    var showsCanvasHole = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let chrome = NSBezierPath(rect: bounds)
        if showsCanvasHole, let scroll = canvasScrollView {
            let hole = scroll.convert(scroll.bounds, to: self).intersection(bounds)
            NSGraphicsContext.current?.cgContext.clear(hole)
            chrome.appendRect(hole)
            chrome.windingRule = .evenOdd
        }
        NSColor.windowBackgroundColor.setFill(); chrome.fill()
        if usesRecoveredBezel {
            NSGraphicsContext.saveGraphicsState()
            chrome.addClip()
            NSGradient(starting: NSColor(white: 0.91, alpha: 1), ending: NSColor(white: 0.78, alpha: 1))?.draw(in: bounds, angle: -90)
            let opening = canvasScrollView.map { $0.convert($0.bounds, to: self) } ?? bounds.insetBy(dx: 37, dy: 33)
            let left = max(0, opening.minX), right = max(0, bounds.maxX-opening.maxX)
            let top = max(0, bounds.maxY-opening.maxY), bottom = max(0, opening.minY)
            let pieces: [(String, NSRect)] = [
                ("TopLeft", NSRect(x: 0, y: opening.maxY, width: left, height: top)),
                ("TopRight", NSRect(x: opening.maxX, y: opening.maxY, width: right, height: top)),
                ("BottomLeft", NSRect(x: 0, y: 0, width: left, height: bottom)),
                ("BottomRight", NSRect(x: opening.maxX, y: 0, width: right, height: bottom)),
                ("Top", NSRect(x: opening.minX, y: opening.maxY, width: opening.width, height: top)),
                ("Bottom", NSRect(x: opening.minX, y: 0, width: opening.width, height: bottom)),
                ("Left", NSRect(x: 0, y: opening.minY, width: left, height: opening.height)),
                ("Right", NSRect(x: opening.maxX, y: opening.minY, width: right, height: opening.height))
            ]
            for (name, rect) in pieces { bezelImages[name]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func layout() { super.layout(); if showsCanvasHole || usesRecoveredBezel { needsDisplay = true } }
}

final class DragExportView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    struct Payload { let data: Data; let name: String; var format: String = "png"; let delivered: (URL) -> Void }
    var prepare: (() -> Payload?)?
    var overview: NSImage? { didSet { needsDisplay = true } }
    var onBegin: ((UUID) -> Void)?
    var onLeaveControl: ((UUID) -> Void)?
    var onEnd: ((UUID, Bool) -> Void)?
    var onDeliveryFailure: ((UUID) -> Void)?
    private struct Export {
        let id: UUID
        let provider: NSFilePromiseProvider
        let payload: Payload
        let controlRect: NSRect
    }
    private var payloads: [ObjectIdentifier: Export] = [:]
    private var sessions: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var activeProvider: ObjectIdentifier?
    /// Modern lets the glass surface behind the view be the plate.
    var drawsBackground = true { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        if drawsBackground { NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill() }
        if let overview { overview.draw(in: bounds.insetBy(dx: 4, dy: 4), from: .zero, operation: .sourceOver, fraction: 0.2) }
        let title = "Drag Me"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.labelColor]
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
    override func mouseDragged(with event: NSEvent) {
        guard activeProvider == nil, let window, let payload = prepare?() else { return }
        let provider = NSFilePromiseProvider(fileType: (UTType(filenameExtension: payload.format) ?? .data).identifier, delegate: self)
        guard beginExport(provider: provider, payload: payload, controlRect: window.convertToScreen(convert(bounds, to: nil))) else { return }
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { [overview] rect in
            overview?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
        item.setDraggingFrame(NSRect(x: bounds.midX - 64, y: bounds.midY - 64, width: 128, height: 128), contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        sessions[ObjectIdentifier(session)] = ObjectIdentifier(provider)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard sessions[ObjectIdentifier(session)] == activeProvider else { return }
        moveExport(to: screenPoint)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let provider = sessions.removeValue(forKey: ObjectIdentifier(session)) { endExport(provider: provider, succeeded: !operation.isEmpty) }
    }
    @discardableResult
    func beginExport(provider: NSFilePromiseProvider, payload: Payload, controlRect: NSRect) -> Bool {
        guard activeProvider == nil else { return false }
        let key = ObjectIdentifier(provider), export = Export(id: UUID(), provider: provider, payload: payload, controlRect: controlRect)
        payloads[key] = export; activeProvider = key
        activeExport = export
        onBegin?(export.id)
        return true
    }
    private var activeExport: Export?
    func moveExport(to screenPoint: NSPoint) {
        guard let export = activeExport, !export.controlRect.contains(screenPoint) else { return }
        onLeaveControl?(export.id)
    }
    func endExport(provider: ObjectIdentifier, succeeded: Bool) {
        guard activeProvider == provider, let export = activeExport else { return }
        activeProvider = nil; activeExport = nil
        if !succeeded { payloads.removeValue(forKey: provider) }
        onEnd?(export.id, succeeded)
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { (payloads[ObjectIdentifier(filePromiseProvider)]?.payload.name ?? "Skitch") + "." + (payloads[ObjectIdentifier(filePromiseProvider)]?.payload.format ?? "png") }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let export = payloads.removeValue(forKey: ObjectIdentifier(filePromiseProvider))
        do {
            guard let export else { throw NSError(domain: "SkitchRedux", code: 1, userInfo: [NSLocalizedDescriptionKey: "The dragged image is no longer available."]) }
            try export.payload.data.write(to: url, options: .atomic)
            export.payload.delivered(url); completionHandler(nil)
        } catch {
            if let export { onDeliveryFailure?(export.id) }
            completionHandler(error)
        }
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
}

final class DragThumbnailView: NSView {
    var image: NSImage?
    var clickToExpand = false { didSet { needsDisplay = true } }
    var restore: (() -> Void)?
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { restore?() }
    override func accessibilityPerformPress() -> Bool {
        guard let restore else { return false }
        restore(); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        if clickToExpand {
            NSColor.white.withAlphaComponent(0.1).setFill(); bounds.fill()
            let name = hovering ? "Skitch_ShowSkitch_mouseover" : "Skitch_ShowSkitch"
            if let overlay = NSImage(named: name) {
                overlay.draw(in: NSRect(x: (bounds.width-overlay.size.width)/2, y: (bounds.height-overlay.size.height)/2, width: overlay.size.width, height: overlay.size.height), from: .zero, operation: .sourceOver, fraction: 1)
            }
        } else if hovering, let overlay = NSImage(named: "Skitch_Cancel_DragMe") {
            overlay.draw(in: NSRect(x: (bounds.width-overlay.size.width)/2, y: (bounds.height-overlay.size.height)/2, width: overlay.size.width, height: overlay.size.height), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSFontChanging, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var window: NSWindow!
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let capture = CaptureCoordinator()
    let publishing = PublishingCoordinator()
    let historyRemoteDeletion = HistoryRemoteDeletionCoordinator()
    let hotkeys = GlobalHotkeyManager()
    var generalPreferences: OriginalGeneralPreferences { OriginalGeneralPreferences(defaults: .standard) }
    var preferencesWindow: NSWindow?
    var preferencesForm: GeneralPreferencesForm?
    var soundEffects = OriginalSoundEffects()
    var helpBevel: OriginalHelpBevel?
    private var hintEventMonitor: Any?
    let photoBrowser = PhotoBrowserCoordinator()
    let nameField = NSTextField(string: "Untitled")
    let status = NSTextField(labelWithString: "")
    let colorWell = NSColorWell()
    let widthControl = BezelSizeSlider(frame: .zero)
    let sizeLabel = NSTextField(labelWithString: "Size · 6.75")
    let paletteButton = BezelHoverButton(title: "Color…", target: nil, action: nil)
    var colorPopover: NSPopover?
    var colorControlHovered = false, colorPaletteHovered = false, colorOpenedByHover = false
    private var colorHoverDismissal: DispatchWorkItem?
    var presetColorButtons: [BezelColorButton] = []
    var sizeUndoGrouping = false
    var customDrawingColor = NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 1)
    let zoomControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let dragFormatControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let dragOriginalControl = NSButton(checkboxWithTitle: "Export at original size", target: nil, action: nil)
    let dragSizeLabel = NSTextField(labelWithString: "")
    var dragExportView: DragExportView?
    var dragPreviewTimer: Timer?
    var activeDragID: UUID?
    var dragThumbnailID: UUID?
    var dragThumbnailWindow: NSPanel?
    var windowZoom: WindowZoomAnimation?
    var windowZoomID: UUID?
    var visibilityZoomOrigin: CGRect?
    var animatesWindowZoom: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var actualButton: NSButton?
    var resizeButton: NSButton?
    let navigator = CanvasNavigator(frame: NSRect(x: 0, y: 0, width: 180, height: 170))
    var navigatorWindow: NSPanel?
    let canvasBorder = CanvasBorderView(frame: .zero)
    struct ActualViewState {
        let generation: UUID
        let outputSize: CGSize
        let zoom: CGFloat
        let windowFrame: CGRect
        let scrollOrigin: CGPoint
        var savedWhileActive = false
    }
    var actualView: ActualViewState?
    var isActualSize: Bool { actualView != nil }
    struct WindowGesture {
        let generation: UUID
        let outputSize: CGSize
        let sourceSize: CGSize
        let zoom: CGFloat
        let windowFrame: CGRect
        let handle: CanvasBorderHandle
    }
    var windowGesture: WindowGesture?
    var adjustingWindowFrame = false
    var navigatorTimer: Timer?
    var fontPanel: NSFontPanel?
    var textStyleForm: TextStyleForm?
    var fontPanelRefreshTimer: Timer?
    var fontPanelRecordedTypography = false
    var fontPanelOpeningLayoutApplied = false
    var fontPanelVisibleFrameOverride: (() -> NSRect?)?
    var applyingFontChange = false
    var activeResizeSession: ResizePanelSession?
    var toolButtons: [SketchTool: NSButton] = [:]
    var modernChrome: NSView?
    /// Launches a fresh instance; only `OpenSkitchMain` installs one, so tests and tools never spawn an app.
    var relaunchRequest: ((URL) -> Void)?
    var pendingRelaunch: URL?
    var currentURL: URL?
    var documentGeneration = UUID()
    var legacyMetadata = LegacyBridge.Metadata()
    var dirty = false
    var restoring = false
    var discardedForTermination = false
    var terminationStarted = false
    var decidingTermination = false
    var shutdownPending: Set<String> = []
    var shutdownError: Error?
    var timer: Timer?
    var statusItem: NSStatusItem?
    var historyBrowser: HistoryBrowser?
    var historyWindow: NSWindow? { historyBrowser?.window }
    var historyStore: HistoryStore?
    struct ShareSnapshot { let snapshot: HistoryStore.Snapshot; let name: String; let generation: UUID }
    var sharePicker: NSSharingServicePicker?
    var pickerSnapshot: ShareSnapshot?
    var sharingSnapshots: [ObjectIdentifier: ShareSnapshot] = [:]
    var currentArchiveID: UUID?
    var historyFollowTimer: Timer?
    var snapButton: NSButton!
    var cameraButton: NSButton!
    var cancelFrameButton: NSButton!
    /// Located by its action on first use, so the window builder needs no extra reference.
    weak var wipeRailButton: NSButton?
    var frameMode = false
    var frameKeepsAnnotations = false
    var frameCaptureInProgress = false
    var frameTimedSnap = false
    var activeFrameScreenSize: NSSize?
    var frameWindowWasOpaque = true
    var frameWindowHadShadow = true
    var frameWindowAlpha: CGFloat = 1
    var frameWindowLevel = NSWindow.Level.normal
    var frameWindowBackground: NSColor?
    var frameScrollDrewBackground = true
    var frameTitlebarBackdrop: FrameChromeView?
    let support: URL = {
        if let isolated = ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] { return URL(fileURLWithPath: isolated, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SkitchRedux", isDirectory: true)
    }()

    var firstLaunchDocumentURL: URL? = Bundle.main.url(forResource: "firstlaunch", withExtension: "skitch")
    var firstLaunchMarker: URL { support.appendingPathComponent("FirstLaunchDone") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus(); buildWindow()
        installMenuPresence()
        applyPresencePolicy()
        installHintMonitoring()
        NSColorPanel.shared.showsAlpha = true
        canvas.onChange = { [weak self] in self?.changed() }
        canvas.onSound = { [weak self] name in self?.playOriginalSound(name) }
        capture.onSound = { [weak self] name in self?.playOriginalSound(name) }
        canvas.onTextStyleRequested = { [weak self] in self?.chooseFont() }
        canvas.onTextStyleContextChange = { [weak self] in self?.syncFontPanelSelection(); self?.updateWipeButton() }
        canvas.onViewportEditCancelled = { [weak self] in
            self?.endWindowGesture(cancelled: true)
            self?.activeResizeSession?.cancel()
        }
        canvas.onHistoryRestored = { [weak self] previous in self?.finishHistoryResize(previousOutput: previous) }
        canvas.onOpenDocument = { [weak self] url in self?.openURL(url) }
        canvas.onToolChange = { [weak self] tool in
            guard let self else { return }
            self.updateToolButtons(tool)
            self.updateStatus()
        }
        canvas.onColorChange = { [weak self] color in self?.colorWell.color = color; self?.rememberDrawingDefaults(); self?.syncDrawingControls() }
        try? FileManager.default.createDirectory(at: support.appendingPathComponent("History"), withIntermediateDirectories: true)
        let nativeRecovery = support.appendingPathComponent("Recovery.skitch")
        let recovery = FileManager.default.fileExists(atPath: nativeRecovery.path) ? nativeRecovery : support.appendingPathComponent("Recovery.skitchredux")
        let recoveryData = try? Data(contentsOf: recovery)
        if let data = recoveryData {
            do { let restored = try SkitchFile.decode(data); restoring = true; try canvas.loadDocument(data: restored.canvasData); legacyMetadata = restored.metadata; restoreDrawingDefaults(); restoring = false; dirty = true; window.isDocumentEdited = true; nameField.stringValue = "Recovered drawing" }
            catch { restoring = false; status.stringValue = "Previous session could not be restored." }
        }
        let fixturePath = ProcessInfo.processInfo.environment["SKITCH_FIXTURE"]
        if let fixture = fixturePath { openURL(URL(fileURLWithPath: fixture)) }
        else if recoveryData == nil, !FileManager.default.fileExists(atPath: firstLaunchMarker.path) {
            // Original launch path (decompiled.c:7880-7893): the bundled firstlaunch.skitch loads once, unsaved.
            if let welcome = firstLaunchDocumentURL {
                openURL(welcome)
                if currentURL != nil || nameField.stringValue != "Welcome" { currentURL = nil; nameField.stringValue = "Welcome" }
                dirty = false; window.isDocumentEdited = false
            }
            try? Data().write(to: firstLaunchMarker, options: .atomic)
        }
        updateStatus(); updateWipeButton()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.saveRecovery() } }
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); NSApp.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded(); updateViewportChrome()
        do {
            try hotkeys.install(globalScreen: { [weak self] in self?.captureCrosshair(manualOption: false) }, globalWindow: { [weak self] in self?.windowSnap() }, globalFullscreen: { [weak self] in self?.captureFullscreen(manualOption: false) }, globalFrame: { [weak self] in self?.enterFrame(keepingAnnotations: false, manualFlags: []) }, globalCamera: { [weak self] in self?.cameraSnap() }, globalUpload: { [weak self] in self?.snapAndUpload() }, globalShow: { [weak self] in self?.makeVisible() })
        } catch { status.stringValue = "Global shortcuts unavailable: " + error.localizedDescription }
        writeLayoutEvidence()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.runSmokeTest() }
        }
        if CommandLine.arguments.contains("--relaunch-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.runRelaunchSmoke() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationStarted { return shutdownPending.isEmpty ? .terminateNow : .terminateLater }
        widthControl.endTracking(); closeDrawingColors()
        if windowZoom != nil { makeVisible() }
        saveRecovery()
        guard allowDiscard(discardingForTermination: true) else { pendingRelaunch = nil; return .terminateCancel }
        terminationStarted = true; decidingTermination = true
        shutdownPending = ["capture", "publishing", "photos", "history-deletion"]; shutdownError = nil
        historyRemoteDeletion.shutdown { [weak self] result in self?.acknowledgeShutdown("history-deletion", result: result) }
        photoBrowser.shutdown { [weak self] in self?.acknowledgeShutdown("photos", result: .success(())) }
        capture.shutdown { [weak self] (result: Result<Void, Error>) in self?.acknowledgeShutdown("capture", result: result) }
        publishing.shutdown { [weak self] (result: Result<Void, Error>) in self?.acknowledgeShutdown("publishing", result: result) }
        decidingTermination = false
        if shutdownPending.isEmpty { return finishShutdownDecision() ? .terminateNow : .terminateCancel }
        status.stringValue = "Finishing capture and publishing cleanup…"
        return .terminateLater
    }
    func acknowledgeShutdown(_ operation: String, result: Result<Void, Error>) {
        guard shutdownPending.remove(operation) != nil else { return }
        if case .failure(let error) = result, shutdownError == nil { shutdownError = error }
        guard shutdownPending.isEmpty, !decidingTermination else { return }
        let approved = finishShutdownDecision()
        NSApp.reply(toApplicationShouldTerminate: approved)
    }
    func finishShutdownDecision() -> Bool {
        guard let failure = shutdownError else { return true }
        terminationStarted = false; pendingRelaunch = nil
        if discardedForTermination { dirty = true; window.isDocumentEdited = true }
        discardedForTermination = false; saveRecovery(); updateStatus()
        // Reply to AppKit before presenting an error about incomplete cleanup.
        DispatchQueue.main.async { [weak self] in self?.error(failure) }
        return false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === preferencesWindow { closePreferences(); return false }
        guard sender === window else { return true }
        vanish()
        return false
    }
    func installMenuPresence() {
        guard statusItem == nil else { return }
        guard UserDefaults.standard.integer(forKey: "statusMenu") != 2 else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(named: "menu")
            button.alternateImage = NSImage(named: "menu-sel")
            button.toolTip = "Click to show/hide Skitch"
            button.setAccessibilityLabel("Show or hide OpenSkitch")
            button.target = self; button.action = #selector(showHide)
        }
    }
    func applyPresencePolicy() {
        let presence = generalPreferences.state.statusMenu
        // Modern AppKit changes Dock presence without rewriting the signed app
        // bundle or restarting with pending drawings, unlike original Skitch.
        NSApp.setActivationPolicy(presence == 1 ? .accessory : .regular)
        if presence == 2, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        } else if presence != 2 { installMenuPresence() }
    }
    func playOriginalSound(_ name: String) { soundEffects.play(name, enabled: generalPreferences.state.playSounds) }
    func trackHint(_ view: NSView, owner: String, message: @escaping () -> String?) {
        let tracking = HintTrackingView(); tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.setAccessibilityElement(false)
        tracking.onHover = { [weak self] entered in
            guard let self, !self.terminationStarted else { return }
            if entered { self.helpBevel?.hover(owner: owner, message: message()) }
            else { self.helpBevel?.exit(owner: owner) }
        }
        view.addSubview(tracking)
        NSLayoutConstraint.activate([tracking.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tracking.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tracking.topAnchor.constraint(equalTo: view.topAnchor), tracking.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    func hintModifiers(_ flags: NSEvent.ModifierFlags) {
        guard !terminationStarted, window.attachedSheet == nil,
              !(window.firstResponder is NSTextView) else { return }
        let message = canvas.isTemporaryHand ? "" : OriginalHintMessages.getHelpForModifiers(tool: canvas.toolForModifiers(flags), modifiers: flags)
        helpBevel?.modifiers(message: message)
    }
    func installHintMonitoring() {
        hintEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, NSApp.keyWindow === self.window { self.hintModifiers(event.modifierFlags) }
            }
            return event
        }
    }
    func applicationWillResignActive(_ notification: Notification) { helpBevel?.clear() }
    func applicationDidHide(_ notification: Notification) { helpBevel?.clear() }
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { helpBevel?.clear() }
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { helpBevel?.clear() }
    }
    @objc func showHide() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { quit(); return }
        guard UserDefaults.standard.integer(forKey: "statusMenu") != 2 else { return }
        toggleVisible()
    }
    @objc func vanish() {
        guard window.isVisible else { return }
        toggleVisible()
    }
    @objc func toggleVisible() {
        guard !terminationStarted, !frameCaptureInProgress, window.attachedSheet == nil else { return }
        widthControl.endTracking(); closeDrawingColors(); helpBevel?.clear()
        if windowZoom != nil { makeVisible(); return }
        if dragThumbnailWindow != nil {
            let panel = dragThumbnailWindow!, source = panel.frame
            let image = snapshot(window: panel)
            removeDragThumbnail()
            if UserDefaults.standard.integer(forKey: "statusMenu") == 2 {
                visibilityZoomOrigin = nil; window.orderFront(nil); window.miniaturize(nil)
            } else {
                let target = zoomDestinationRect(); visibilityZoomOrigin = target.isEmpty ? nil : target
                if let image { _ = startWindowZoom(image: image, source: source, destination: target, direction: .shrink, frames: 25,
                                                  completion: { [weak self] in self?.writeLayoutEvidence() }) }
            }
            writeLayoutEvidence(); return
        }
        if !window.isVisible || window.isMiniaturized || !NSApp.isActive {
            makeVisible()
        } else {
            saveRecovery()
            timer?.fireDate = .distantFuture
            fontPanel?.orderOut(nil); navigatorWindow?.orderOut(nil)
            if UserDefaults.standard.integer(forKey: "statusMenu") == 2 { visibilityZoomOrigin = nil; window.miniaturize(nil) }
            else {
                let target = zoomDestinationRect(); visibilityZoomOrigin = target.isEmpty ? nil : target
                if animatesWindowZoom, let image = snapshot(window: window) {
                    _ = startWindowZoom(image: image, source: window.frame, destination: target, direction: .shrink, frames: 15,
                                        completion: { [weak self] in self?.writeLayoutEvidence() })
                }
                window.orderOut(nil)
            }
            writeLayoutEvidence()
        }
    }
    @objc func makeVisible() {
        guard !terminationStarted else { return }
        if animatesWindowZoom && windowZoom == nil && dragThumbnailWindow == nil && !window.isVisible && !window.isMiniaturized,
           UserDefaults.standard.integer(forKey: "statusMenu") != 2, let previous = visibilityZoomOrigin,
           let image = snapshot(window: window) {
            let current = zoomDestinationRect(), source = current.isEmpty ? previous : current
            visibilityZoomOrigin = nil
            NSApp.activate(ignoringOtherApps: true); timer?.fireDate = Date(timeIntervalSinceNow: 15)
            if startWindowZoom(image: image, source: source, destination: window.frame, direction: .restore, frames: 15,
                               completion: { [weak self] in self?.showEditorImmediately() }) { writeLayoutEvidence(); return }
        }
        showEditorImmediately()
    }
    func showEditorImmediately() {
        guard !terminationStarted else { return }
        visibilityZoomOrigin = nil
        removeDragThumbnail()
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        timer?.fireDate = Date(timeIntervalSinceNow: 15)
        updateViewportChrome(); writeLayoutEvidence()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !window.isVisible && window.attachedSheet == nil { makeVisible() }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if discardedForTermination { removeRecovery() }
        else { saveRecovery(finalizingTermination: true) }
        timer?.invalidate(); historyFollowTimer?.invalidate(); dragPreviewTimer?.invalidate(); navigatorTimer?.invalidate(); closeFontPanel(); try? hotkeys.unregister()
        preferencesWindow?.orderOut(nil); soundEffects.stop()
        helpBevel?.shutdown()
        if let hintEventMonitor { NSEvent.removeMonitor(hintEventMonitor); self.hintEventMonitor = nil }
        removeDragThumbnail(); activeDragID = nil; visibilityZoomOrigin = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        if let url = pendingRelaunch { pendingRelaunch = nil; relaunchRequest?(url) }
    }
    static func dragThumbnailRect(windowFrame: NSRect, controlRect: NSRect) -> NSRect {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return .zero }
        let scale = 128 / max(windowFrame.width, windowFrame.height)
        let width = max(90, windowFrame.width * scale), height = max(90, windowFrame.height * scale)
        return NSRect(x: controlRect.midX-width/2, y: controlRect.midY-height/2, width: width, height: height).integral
    }
    func zoomDestinationRect() -> CGRect { statusItem?.button?.window?.frame ?? .zero }
    func snapshot(window: NSWindow) -> NSImage? {
        guard let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = NSImage(size: content.bounds.size); image.addRepresentation(bitmap)
        return image
    }
    func iconifyDrag(_ id: UUID) {
        guard activeDragID == id, dragThumbnailWindow == nil, !terminationStarted,
              window.isVisible, window.attachedSheet == nil, let drag = dragExportView,
              let image = snapshot(window: window) else { return }
        let rect = Self.dragThumbnailRect(windowFrame: window.frame, controlRect: window.convertToScreen(drag.convert(drag.bounds, to: nil)))
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = true; panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        let view = DragThumbnailView(frame: NSRect(origin: .zero, size: rect.size)); view.image = image
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Restore Skitch editor")
        view.restore = { [weak self] in self?.restoreDragThumbnail(id) }
        panel.contentView = view; dragThumbnailWindow = panel; dragThumbnailID = id
        saveRecovery(); timer?.fireDate = .distantFuture
        fontPanel?.orderOut(nil); navigatorWindow?.orderOut(nil)
        if !startWindowZoom(image: image, source: window.frame, destination: rect, direction: .shrink, completion: { [weak self, weak panel] in
            guard self?.dragThumbnailID == id else { return }
            panel?.orderFrontRegardless(); self?.writeLayoutEvidence()
        }) { panel.orderFrontRegardless() }
        window.orderOut(nil); writeLayoutEvidence()
    }
    func endDrag(_ id: UUID, succeeded: Bool) {
        guard activeDragID == id, !terminationStarted else { return }
        activeDragID = nil
        if !succeeded { restoreDragThumbnail(id) }
        else if dragThumbnailID == id {
            (dragThumbnailWindow?.contentView as? DragThumbnailView)?.clickToExpand = true
            writeLayoutEvidence()
        }
    }
    func restoreDragThumbnail(_ id: UUID) {
        guard dragThumbnailID == id, dragThumbnailWindow != nil, !terminationStarted else { return }
        let image = (dragThumbnailWindow?.contentView as? DragThumbnailView)?.image
        let source = dragThumbnailWindow!.frame
        removeDragThumbnail()
        NSApp.activate(ignoringOtherApps: true)
        guard let image, startWindowZoom(image: image, source: source, destination: window.frame, direction: .restore,
                                        completion: { [weak self] in self?.makeVisible() }) else { makeVisible(); return }
        writeLayoutEvidence()
    }
    func removeDragThumbnail() {
        cancelWindowZoom()
        (dragThumbnailWindow?.contentView as? DragThumbnailView)?.restore = nil
        dragThumbnailWindow?.orderOut(nil); dragThumbnailWindow?.close()
        dragThumbnailWindow = nil; dragThumbnailID = nil
    }
    func replaceDragPresentation() {
        closeDrawingColors()
        activeDragID = nil
        if dragThumbnailWindow != nil || windowZoom != nil || visibilityZoomOrigin != nil { showEditorImmediately() }
    }
    @discardableResult
    func startWindowZoom(image: NSImage, source: CGRect, destination: CGRect, direction: WindowZoomDirection, frames: Int? = nil, completion: @escaping () -> Void) -> Bool {
        guard animatesWindowZoom, !terminationStarted else { return false }
        cancelWindowZoom()
        let token = UUID()
        guard let animation = WindowZoomAnimation(image: image, source: source, destination: destination, direction: direction, frames: frames, completion: { [weak self] in
            guard let self, self.windowZoomID == token, !self.terminationStarted else { return }
            self.windowZoom = nil; self.windowZoomID = nil; completion()
        }) else { return false }
        windowZoom = animation; windowZoomID = token; animation.start(); return true
    }
    func cancelWindowZoom() {
        let previous = windowZoom
        windowZoom = nil; windowZoomID = nil; previous?.cancel()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { openURL(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func label(_ text: String) -> NSTextField { let f = NSTextField(labelWithString: text); f.font = .systemFont(ofSize: 18); return f }
    func button(_ title: String, _ action: Selector) -> NSButton { let b = OriginalActionButton(title: title, target: self, action: action); b.font = .systemFont(ofSize: 18); return b }
    func stack(_ views: [NSView], horizontal: Bool = false) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = horizontal ? .horizontal : .vertical; s.spacing = 12; s.alignment = horizontal ? .centerY : .leading; return s
    }
    func recoveredImage(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    func copiedMainMenuItem(_ action: Selector, title: String? = nil) -> NSMenuItem? {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == action { return item }
                if let submenu = item.submenu, let found = find(submenu) { return found }
            }
            return nil
        }
        guard let main = NSApp.mainMenu, let item = find(main)?.copy() as? NSMenuItem else { return nil }
        if let title { item.title = title }
        return item
    }
    func copiedMainMenu(_ title: String) -> NSMenu? {
        guard let original = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == title })?.submenu,
              let copied = original.copy() as? NSMenu else { return nil }
        copied.font = .systemFont(ofSize: 20)
        return copied
    }
    func bezelToolbox() -> NSPopUpButton {
        let control = NSPopUpButton(frame: .zero, pullsDown: true)
        control.font = .systemFont(ofSize: 20)
        let choices = NSMenu(title: "Toolbox"); choices.font = .systemFont(ofSize: 20)
        choices.addItem(withTitle: "Toolbox", action: nil, keyEquivalent: "")
        let groups: [[(String, Selector)]] = [
            [("About OpenSkitch", #selector(about)), ("Preferences…", #selector(showPreferences)), ("Quit OpenSkitch", #selector(quit))],
            [("New", #selector(newFile)), ("Open...", #selector(openFile)), ("Browse Photos", #selector(showPhotos)),
             ("Save to History", #selector(saveHistory)), ("Export...", #selector(exportFile)), ("Save As...", #selector(saveAs)), ("Print...", #selector(printImage))],
            [("Cut", #selector(cut)), ("Copy", #selector(copyArtwork)), ("Paste", #selector(paste)),
             ("Delete", #selector(deleteSelection)), ("Select All", #selector(selectAll)), ("Duplicate", #selector(duplicate)), ("Show Fonts", #selector(chooseFont))],
            [("Crosshair Snapshot", #selector(screenSnap)), ("Fullscreen Snapshot", #selector(fullscreenSnap)), ("Frame Snapshot", #selector(frameSnap)),
             ("Cam Snapshot...", #selector(cameraSnap)), ("Re-snap (Keep Pen)", #selector(resnap))],
            [("Set Snap to Normal Size", #selector(normalSize)), ("Flip", #selector(flipH)), ("Rotate 90° Clockwise", #selector(rotateCW)),
             ("Background Color to Transparent", #selector(transparent)), ("Crop Snap at Current View", #selector(trimSnap)), ("Wipe Snap Only", #selector(wipeSnap))]
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { choices.addItem(.separator()) }
            for (title, action) in group {
                if let item = copiedMainMenuItem(action, title: title) { choices.addItem(item) }
            }
        }
        choices.addItem(.separator())
        // Existing additions remain reachable without placing the original
        // common commands behind another menu level.
        let more = NSMenu(title: "More Commands"); more.font = .systemFont(ofSize: 20)
        for title in ["File", "Image", "Drawing", "Text", "Capture"] {
            guard let copied = copiedMainMenu(title) else { continue }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = copied; more.addItem(item)
        }
        for (title, action) in [("Sharing Settings…", #selector(sharingSettings)), ("Capture Shortcuts…", #selector(shortcutSettings))] {
            if let item = copiedMainMenuItem(action, title: title) { more.addItem(item) }
        }
        let extra = NSMenuItem(title: "More Commands", action: nil, keyEquivalent: ""); extra.submenu = more; choices.addItem(extra)
        for (title, action) in [("Filled Shapes", #selector(toggleBezelFill(_:))), ("Shadow", #selector(toggleBezelShadow(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; choices.addItem(item)
        }
        control.menu = choices; control.setAccessibilityLabel("Toolbox")
        control.toolTip = "Common drawing and capture commands; additional actions are in More Commands"
        return control
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenSkitch"; window.delegate = self; window.minSize = NSSize(width: 900, height: 640)
        if #available(macOS 26, *), Appearance.isModern { buildModernWindowContent(); return }
        window.contentView = FrameChromeView(frame: window.contentView?.bounds ?? .zero)
        guard let content = window.contentView else { return }
        content.appearance = NSAppearance(named: .aqua)
        (content as? FrameChromeView)?.usesRecoveredBezel = true
        let toolbox = bezelToolbox()
        let photos = button("Photos", #selector(showPhotos))
        let companyLogo = NSImageView(); companyLogo.image = recoveredImage("OpenSkitch")
        companyLogo.imageScaling = .scaleProportionallyUpOrDown
        companyLogo.setAccessibilityLabel("ShoeMoney logo")
        companyLogo.widthAnchor.constraint(equalToConstant: 32).isActive = true
        companyLogo.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let companyName = label("OpenSkitch"); companyName.font = .systemFont(ofSize: 20, weight: .semibold)
        companyName.setContentCompressionResistancePriority(.required, for: .horizontal)
        let title = stack([companyLogo, companyName], horizontal: true); title.spacing = 8
        title.identifier = NSUserInterfaceItemIdentifier("OpenSkitchBrand")
        let hide = button("Hide", #selector(vanish)); hide.image = recoveredImage("Hide"); hide.imagePosition = .imageLeading
        let save = button("Save", #selector(saveHistory)); save.image = recoveredImage("SaveToHistoryArrow"); save.imagePosition = .imageTrailing
        let leadingCommands = stack([hide, toolbox, photos], horizontal: true); leadingCommands.spacing = 8
        let trailingCommands = stack([save, button("History", #selector(showHistory))], horizontal: true)
        trailingCommands.spacing = 8
        let top = NSView(); top.identifier = NSUserInterfaceItemIdentifier("OpenSkitchHeader")
        for group in [leadingCommands, title, trailingCommands] {
            group.translatesAutoresizingMaskIntoConstraints = false; top.addSubview(group)
        }
        NSLayoutConstraint.activate([
            leadingCommands.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            trailingCommands.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            title.centerXAnchor.constraint(equalTo: top.centerXAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: leadingCommands.trailingAnchor, constant: 12),
            trailingCommands.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            leadingCommands.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            title.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            trailingCommands.centerYAnchor.constraint(equalTo: top.centerYAnchor)
        ])
        snapButton = button("Snap", #selector(snapButtonPressed))
        (snapButton as? OriginalActionButton)?.alternateTarget = self
        (snapButton as? OriginalActionButton)?.alternateAction = #selector(fullscreenSnap)
        snapButton.toolTip = "Drag an area or click a window; right-click or Control-click for Fullscreen"
        snapButton.image = recoveredImage("SnapCrosshair"); snapButton.imagePosition = .imageLeading
        cameraButton = button("Cam", #selector(cameraSnap)); cameraButton.image = recoveredImage("SnapISight"); cameraButton.imagePosition = .imageLeading
        cancelFrameButton = button("Cancel", #selector(cancelFrame)); cancelFrameButton.isHidden = true
        cancelFrameButton.image = recoveredImage("SnapCancel"); cancelFrameButton.imagePosition = .imageLeading
        var sidebarViews: [NSView] = [label("Tools")]
        let originalToolOrder: [SketchTool] = [.select, .brush, .line, .ellipse, .rectangle, .fill, .eraser, .text, .arrow]
        for tool in originalToolOrder + [.crop] {
            let b = ToolButton(title: tool == .crop ? "Crop" : "", target: self, action: #selector(chooseTool(_:)))
            b.isBordered = false; b.font = .systemFont(ofSize: 18)
            b.identifier = NSUserInterfaceItemIdentifier(tool.rawValue); b.setButtonType(.toggle)
            let assets: [String: String] = ["select":"Cursor", "arrow":"Arrow", "line":"Line", "rectangle":"Rect", "ellipse":"Circle", "brush":"Brush", "text":"Text", "fill":"Fill", "eraser":"Eraser"]
            if let asset = assets[tool.rawValue], let image = recoveredImage("ToolOff"+asset) {
                b.image = image; b.alternateImage = recoveredImage("ToolOn"+asset); b.imagePosition = .imageOnly; b.imageScaling = .scaleNone
            }
            b.setAccessibilityLabel(tool.rawValue.capitalized); b.toolTip = tool.rawValue.capitalized + " tool"
            b.widthAnchor.constraint(equalToConstant: 54).isActive = true; b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            sidebarViews.append(b); toolButtons[tool] = b
            trackHint(b, owner: "tool-" + tool.rawValue) { OriginalHintMessages.hover(tool: tool) }
        }
        let sidebar = stack(sidebarViews); sidebar.spacing = 4; sidebar.alignment = .centerX
        let sidebarRail = NSView(); sidebarRail.addSubview(sidebar)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: sidebarRail.leadingAnchor), sidebar.topAnchor.constraint(equalTo: sidebarRail.topAnchor), sidebar.widthAnchor.constraint(equalToConstant: 58)])
        colorWell.color = OriginalDrawingControls.presets[0].color; colorWell.target = self; colorWell.action = #selector(changeColor(_:))
        paletteButton.font = .systemFont(ofSize: 18); paletteButton.target = self; paletteButton.action = #selector(showDrawingColors(_:))
        paletteButton.imagePosition = .imageLeading; paletteButton.setAccessibilityLabel("Drawing colors")
        paletteButton.toolTip = "Hover for original preset colors; hold Shift to change the canvas background"
        paletteButton.onHover = { [weak self] inside in self?.drawingColorHover(inside, palette: false) }
        sizeLabel.font = .systemFont(ofSize: 18)
        widthControl.target = self; widthControl.action = #selector(changeWidth(_:))
        widthControl.widthAnchor.constraint(equalToConstant: 40).isActive = true; widthControl.heightAnchor.constraint(equalToConstant: 82).isActive = true
        widthControl.onBegin = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return false }
            self.canvas.editingUndoManager.beginUndoGrouping(); self.sizeUndoGrouping = true; return true
        }
        widthControl.onEnd = { [weak self] in self?.endDrawingSizeGesture() }
        let actual = button("Actual Size", #selector(toggleActualSize)); actualButton = actual
        actual.setButtonType(.toggle); actual.image = recoveredImage("ActualSizeToggleOff"); actual.alternateImage = recoveredImage("ActualSizeToggleOn")
        actual.imagePosition = .imageLeading
        let numericResize = button("Resize…", #selector(resize)); resizeButton = numericResize
        numericResize.image = recoveredImage("Resize"); numericResize.imagePosition = .imageLeading
        let sizing = stack([actual, numericResize]); sizing.spacing = 4; sizing.alignment = .centerX
        for control in [actual, numericResize] {
            control.widthAnchor.constraint(equalToConstant: 142).isActive = true
            control.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        dragOriginalControl.title = "Original size"; dragOriginalControl.font = .systemFont(ofSize: 18)
        dragOriginalControl.target = self; dragOriginalControl.action = #selector(changeDragOptions(_:))
        dragOriginalControl.state = (UserDefaults.standard.object(forKey: "DragOriginalSize") as? Bool ?? true) ? .on : .off
        dragOriginalControl.setAccessibilityLabel("Drag out at original size")
        let wipeButton = button("Wipe", #selector(wipe))
        trackHint(wipeButton, owner: "wipe") { OriginalHintMessages.hover(actionTag: 50) }
        trackHint(widthControl, owner: "drawing-size") { OriginalHintMessages.hover(actionTag: 20) }
        let font = button("Font", #selector(chooseFont)); font.image = recoveredImage("Font"); font.imagePosition = .imageLeading
        let capture = stack([snapButton, cancelFrameButton, cameraButton]); capture.spacing = 4; capture.alignment = .centerX
        for control in [snapButton!, cancelFrameButton!, cameraButton!] {
            control.widthAnchor.constraint(equalToConstant: 132).isActive = true
            control.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        let undoWipe = stack([button("Undo", #selector(undo)), wipeButton]); undoWipe.spacing = 4; undoWipe.alignment = .centerX
        for control in undoWipe.arrangedSubviews {
            control.widthAnchor.constraint(equalToConstant: 132).isActive = true
            control.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        let railSpace = NSView()
        let right = stack([capture, paletteButton, font, sizeLabel, widthControl, dragOriginalControl, railSpace, undoWipe])
        right.spacing = 4; right.alignment = .centerX
        for control in right.arrangedSubviews where control is NSButton || control is NSPopUpButton {
            control.widthAnchor.constraint(equalToConstant: 132).isActive = true; control.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        let rightRail = NSView(); rightRail.addSubview(right)
        right.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([right.leadingAnchor.constraint(equalTo: rightRail.leadingAnchor), right.topAnchor.constraint(equalTo: rightRail.topAnchor), right.widthAnchor.constraint(equalToConstant: 138)])
        right.bottomAnchor.constraint(equalTo: rightRail.bottomAnchor).isActive = true
        let scroll = NSScrollView(); scroll.documentView = canvas; scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.backgroundColor = .windowBackgroundColor
        (content as? FrameChromeView)?.canvasScrollView = scroll
        nameField.font = .systemFont(ofSize: 20); nameField.placeholderString = "Image name"; nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        zoomControl.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"]); for (index,item) in zoomControl.itemArray.enumerated() { item.representedObject = [0.25,0.5,0.75,1,1.5,2][index] }; zoomControl.selectItem(withTitle: "100%"); zoomControl.font = .systemFont(ofSize: 18); zoomControl.target = self; zoomControl.action = #selector(changeZoom(_:)); zoomControl.setAccessibilityLabel("Canvas zoom")
        zoomControl.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let drag = DragExportView(); dragExportView = drag; drag.widthAnchor.constraint(equalToConstant: 115).isActive = true; drag.heightAnchor.constraint(equalToConstant: 50).isActive = true
        configureDragExport(drag)
        let webpost = button("Webpost…", #selector(share(_:))); webpost.font = .systemFont(ofSize: 20); webpost.setAccessibilityLabel("Share drawing")
        dragFormatControl.addItems(withTitles: ["PNG", "JPEG 100%", "JPEG 80%", "JPEG 60%", "JPEG 30%", "JPEG 10%", "TIFF", "GIF", "BMP", "PDF", "SVG", "Skitch"])
        dragFormatControl.font = .systemFont(ofSize: 20); dragFormatControl.widthAnchor.constraint(equalToConstant: 176).isActive = true
        dragFormatControl.setAccessibilityLabel("Drag Me format")
        for item in dragFormatControl.itemArray { item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 20)]) }
        dragFormatControl.target = self; dragFormatControl.action = #selector(changeDragOptions(_:))
        let choice = UserDefaults.standard.integer(forKey: "DragFormatChoice")
        dragFormatControl.selectItem(at: (0..<dragFormatControl.numberOfItems).contains(choice) ? choice : 0)
        let bottom = stack([nameField, dragFormatControl, drag, webpost], horizontal: true); bottom.spacing = 8
        dragSizeLabel.font = .systemFont(ofSize: 18); dragSizeLabel.lineBreakMode = .byTruncatingTail
        status.font = .systemFont(ofSize: 18); status.lineBreakMode = .byTruncatingTail
        let options = stack([zoomControl, dragSizeLabel, status], horizontal: true); options.spacing = 12
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for v in [top, sidebarRail, rightRail, scroll, sizing, bottom, options] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 8), top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), top.heightAnchor.constraint(equalToConstant: 36),
            sidebarRail.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6), sidebarRail.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8), sidebarRail.widthAnchor.constraint(equalToConstant: 62), sidebarRail.bottomAnchor.constraint(equalTo: sizing.topAnchor, constant: -8),
            rightRail.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6), rightRail.topAnchor.constraint(equalTo: sidebarRail.topAnchor), rightRail.widthAnchor.constraint(equalToConstant: 142), rightRail.bottomAnchor.constraint(equalTo: sidebarRail.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidebarRail.trailingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: rightRail.leadingAnchor, constant: -8), scroll.topAnchor.constraint(equalTo: sidebarRail.topAnchor), scroll.bottomAnchor.constraint(equalTo: sidebarRail.bottomAnchor),
            sizing.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), sizing.bottomAnchor.constraint(equalTo: options.topAnchor, constant: -4), sizing.heightAnchor.constraint(equalToConstant: 72), sizing.widthAnchor.constraint(equalToConstant: 142),
            bottom.leadingAnchor.constraint(equalTo: sizing.trailingAnchor, constant: 12), bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), bottom.centerYAnchor.constraint(equalTo: sizing.centerYAnchor), bottom.heightAnchor.constraint(equalToConstant: 50),
            options.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), options.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), options.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8), options.heightAnchor.constraint(equalToConstant: 30)
        ])
        content.addSubview(canvasBorder)
        wireEditorChrome(scroll: scroll)
        setTool(.arrow)
    }
    func configureDragExport(_ drag: DragExportView) {
        drag.prepare = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return nil }
            self.canvas.commitPendingTextEditing()
            self.updateDragPreview()
            guard let data = try? self.exportData(format: self.dragFormat, originalSize: self.dragAtOriginalSize, jpegQuality: self.dragQuality), let snapshot = try? self.historySnapshot() else { return nil }
            let name = self.safeName(), generation = self.documentGeneration
            return DragExportView.Payload(data: data, name: name, format: self.dragFormat, delivered: { [weak self] url in
                guard let self, !self.terminationStarted else { return }
                self.archive(snapshot, name: name, action: .exported, destination: url.path, generation: generation)
            })
        }
        drag.onBegin = { [weak self] id in self?.activeDragID = id }
        drag.onLeaveControl = { [weak self] id in self?.iconifyDrag(id) }
        drag.onEnd = { [weak self] id, succeeded in self?.endDrag(id, succeeded: succeeded) }
        drag.onDeliveryFailure = { [weak self] id in
            guard let self, !self.terminationStarted else { return }
            if self.activeDragID == id { self.activeDragID = nil }
            self.restoreDragThumbnail(id)
        }
        drag.setAccessibilityElement(true); drag.setAccessibilityLabel("Drag Me"); drag.toolTip = "Drag the drawing into Finder or another application"
        trackHint(drag, owner: "drag-me") { OriginalHintMessages.hover(actionTag: 40) }
    }
    func wireEditorChrome(scroll: NSScrollView) {
        canvasBorder.onBegin = { [weak self] handle, flags in self?.beginWindowGesture(handle, flags: flags) ?? false }
        canvasBorder.onDrag = { [weak self] delta, flags in self?.previewBorderGesture(delta: delta, flags: flags) }
        canvasBorder.onEnd = { [weak self] cancelled in self?.endWindowGesture(cancelled: cancelled) }
        navigator.onNavigate = { [weak self] origin in
            guard let self, self.isActualSize, let scroll = self.canvas.enclosingScrollView else { return }
            scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
            self.updateViewportChrome()
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(canvasViewportChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        canvas.strokeColor = colorWell.color; canvas.strokeWidth = CGFloat(OriginalDrawingControls.initialSize)
        canvas.fontSize = OriginalDrawingControls.readableFontSize(OriginalDrawingControls.initialSize)
        syncDrawingControls()
        canvas.strokeSmoothing = generalPreferences.state.drawingPrecision
        canvas.arrowHeadPreference = UserDefaults.standard.integer(forKey: OriginalArrowGeometry.preferenceKey)
        helpBevel = OriginalHelpBevel(host: window)
        helpBevel?.enabled = generalPreferences.state.showKeyboardTips
        canvas.onHintModifiers = { [weak self] flags in self?.hintModifiers(flags) }
        canvas.onHintHover = { [weak self] entered in
            guard let self else { return }
            if entered { self.helpBevel?.hover(owner: "canvas", message: OriginalHintMessages.hover(tool: self.canvas.tool)) }
            else { self.helpBevel?.exit(owner: "canvas") }
        }
    }
    func menu(_ title: String, items: [(String, Selector?, String)]) -> NSMenu {
        let m = NSMenu(title: title); m.font = .systemFont(ofSize: 20)
        for (name, action, key) in items { if name == "-" { m.addItem(.separator()); continue }; let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self; m.addItem(item) }; return m
    }
    func buildMenus() {
        let bar = NSMenu()
        let appMenu = menu("OpenSkitch", items: [("About OpenSkitch", #selector(about), ""), ("Preferences…", #selector(showPreferences), ","), ("Sharing Settings…", #selector(sharingSettings), ""), ("Capture Shortcuts…", #selector(shortcutSettings), ""), ("-", nil, ""), ("Quit OpenSkitch", #selector(quit), "q")])
        appMenu.insertItem(NSMenuItem(title: "Hide OpenSkitch", action: #selector(toggleVisible), keyEquivalent: "h"), at: appMenu.numberOfItems - 1)
        appMenu.item(at: appMenu.numberOfItems - 2)?.target = self
        let quitIndex = appMenu.numberOfItems - 1
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        for (offset, item) in [hideOthers, showAll, NSMenuItem.separator()].enumerated() {
            item.target = nil; appMenu.insertItem(item, at: quitIndex + offset)
        }
        let file = menu("File", items: [("New Blank", #selector(newFile), "n"), ("Open…", #selector(openFile), "o"), ("Photos…", #selector(showPhotos), ""), ("Save Editable Document", #selector(saveFile), "s"), ("Save As…", #selector(saveAs), "S"), ("Save to History", #selector(saveHistory), ""), ("History", #selector(showHistory), ""), ("Export…", #selector(exportFile), "e"), ("Publish Image…", #selector(publishImage), ""), ("Print…", #selector(printImage), "p")])
        let close = NSMenuItem(title: "Close", action: #selector(closeCurrentWindow), keyEquivalent: "w")
        close.target = self; file.insertItem(close, at: 3)
        let setup = NSMenuItem(title: "Page Setup…", action: #selector(pageSetup), keyEquivalent: "P")
        setup.target = self; file.insertItem(setup, at: file.numberOfItems - 1)
        let edit = menu("Edit", items: [("Undo", #selector(undo), "z"), ("Redo", #selector(redo), "Z"), ("-", nil, ""), ("Cut", #selector(cut), "x"), ("Copy", #selector(copyArtwork), "c"), ("Copy Image", #selector(copyImage), ""), ("Paste", #selector(paste), "v"), ("Delete", #selector(deleteSelection), ""), ("Select All", #selector(selectAll), "a"), ("Duplicate", #selector(duplicate), "d"), ("Wipe", #selector(wipe), ""), ("Wipe Snap Only", #selector(wipeSnap), ""), ("Clear Annotations", #selector(clear), "")])
        let image = menu("Image", items: [("Actual Size", #selector(toggleActualSize), ""), ("Resize…", #selector(resize), ""), ("Crop Selection", #selector(crop), ""), ("Crop Snap at Current Edges", #selector(trimSnap), ""), ("Set Snap to Normal Size", #selector(normalSize), ""), ("Rotate Clockwise", #selector(rotateCW), ""), ("Rotate Counterclockwise", #selector(rotateCCW), ""), ("Flip Horizontal", #selector(flipH), ""), ("Flip Vertical", #selector(flipV), ""), ("Transparent Background", #selector(transparent), ""), ("White Background", #selector(white), ""), ("Flatten", #selector(flatten), ""), ("Bring to Front", #selector(front), ""), ("Send to Back", #selector(back), ""), ("Group", #selector(group), ""), ("Ungroup", #selector(ungroup), "")])
        let text = menu("Text", items: [("Font…", #selector(chooseFont), ""), ("Default Skitch Style", #selector(defaultTextStyle), ""), ("Toggle Text Outline", #selector(toggleOutline), ""), ("Toggle Text Shadow", #selector(toggleTextShadow), "")])
        let spelling = NSMenu(title: "Spelling"); spelling.font = .systemFont(ofSize: 20)
        for (title, action, key) in [("Spelling…", "showGuessPanel:", ":"), ("Check Spelling", "checkSpelling:", ";"), ("Check Spelling as You Type", "toggleContinuousSpellChecking:", "")] {
            // Original MainMenu.nib connects these directly to the text responder.
            // Keep the target nil so sheet fields and annotation editors both work.
            spelling.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let spellingItem = NSMenuItem(title: "Spelling", action: nil, keyEquivalent: ""); spellingItem.submenu = spelling; text.addItem(spellingItem)
        let snap = menu("Capture", items: [("Crosshair Snapshot", #selector(screenSnap), "1"), ("Fullscreen Snapshot", #selector(fullscreenSnap), "2"), ("Window Snapshot", #selector(windowSnap), "3"), ("Frame Snapshot", #selector(frameSnap), "4"), ("Re-snap (Keep Pen)", #selector(resnap), ""), ("Cancel Frame", #selector(cancelFrame), ""), ("Timed Snapshot…", #selector(timedSnap), ""), ("Cancel Snapshot", #selector(cancelSnapshot), ""), ("Camera Snapshot…", #selector(cameraSnap), ""), ("Snap from Link…", #selector(webSnap), "")])
        let drawing = menu("Drawing", items: [])
        let smoothing = menu("Pencil Smoothing", items: [])
        for mode in [StrokeSmoothing.precise, .medium, .loose] {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(changeSmoothing(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self; smoothing.addItem(item)
        }
        let smoothingItem = NSMenuItem(title: "Pencil Smoothing", action: nil, keyEquivalent: "")
        smoothingItem.submenu = smoothing; drawing.addItem(smoothingItem)
        let arrowHead = menu("Arrow Head", items: [])
        for (title, tag) in [("At Start", 1), ("At End", 2)] {
            let item = NSMenuItem(title: title, action: #selector(changeArrowHead(_:)), keyEquivalent: "")
            item.tag = tag; item.target = self; arrowHead.addItem(item)
        }
        let arrowHeadItem = NSMenuItem(title: "Arrow Head", action: nil, keyEquivalent: "")
        arrowHeadItem.submenu = arrowHead; drawing.addItem(arrowHeadItem)
        let windows = menu("Window", items: [("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")])
        for item in windows.items { item.target = nil }
        let minimize = NSMenuItem(title: "Minimize", action: #selector(vanish), keyEquivalent: "m")
        minimize.target = self; windows.insertItem(minimize, at: 0)
        for m in [appMenu, file, edit, image, drawing, text, snap, windows] { let i = NSMenuItem(); i.submenu = m; bar.addItem(i) }
        if #available(macOS 26, *), Appearance.isModern { MenuSymbols.apply(to: bar) }
        NSApp.mainMenu = bar; NSApp.windowsMenu = windows
    }
    @objc func changeSmoothing(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = StrokeSmoothing(rawValue: raw) else { return }
        canvas.strokeSmoothing = mode; generalPreferences.setPrecision(mode)
        preferencesForm?.synchronize(generalPreferences.state)
    }
    @objc func changeArrowHead(_ sender: NSMenuItem) {
        guard sender.tag == 1 || sender.tag == 2 else { return }
        canvas.arrowHeadPreference = sender.tag
        UserDefaults.standard.set(sender.tag, forKey: OriginalArrowGeometry.preferenceKey)
        preferencesForm?.synchronize(generalPreferences.state)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(cancelSnapshot) { return !terminationStarted && capture.isCapturing }
        if menuItem.action == #selector(showPreferences) { return !terminationStarted && !frameCaptureInProgress && window?.attachedSheet == nil }
        if menuItem.action == #selector(changeArrowHead(_:)) {
            menuItem.state = ((canvas.arrowHeadPreference == 1) == (menuItem.tag == 1)) ? .on : .off
            return !terminationStarted && !frameCaptureInProgress
        }
        if menuItem.action == #selector(toggleBezelFill(_:)) { menuItem.state = canvas.filled ? .on : .off; return !terminationStarted && !frameCaptureInProgress }
        if menuItem.action == #selector(toggleBezelShadow(_:)) { menuItem.state = canvas.shadowed ? .on : .off; return !terminationStarted && !frameCaptureInProgress }
        if menuItem.action == #selector(chooseFont) {
            menuItem.title = fontPanel?.isVisible == true ? "Hide Fonts" : "Show Fonts"
            return !terminationStarted
        }
        if menuItem.action == #selector(toggleActualSize) { menuItem.state = isActualSize ? .on : .off; return canToggleActualSize }
        if menuItem.action == #selector(resize) { return !isActualSize && !frameMode }
        if menuItem.action == #selector(changeSmoothing(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == canvas.strokeSmoothing.rawValue ? .on : .off
        }
        if menuItem.action == #selector(undo) { return activeUndoManager.canUndo }
        if menuItem.action == #selector(redo) { return activeUndoManager.canRedo }
        return true
    }
    func updateToolButtons(_ tool: SketchTool) {
        for (choice, button) in toolButtons {
            let selected = choice == tool
            button.state = selected ? .on : .off
            button.bezelColor = selected ? .controlAccentColor : nil
            button.toolTip = choice.rawValue.capitalized + (selected ? " tool (selected)" : " tool")
            if choice == .arrow { button.toolTip! += "; Option reverses direction, Shift constrains the angle" }
            button.needsDisplay = true
        }
    }
    func setTool(_ tool: SketchTool) { canvas.tool = tool; updateToolButtons(tool); window?.makeFirstResponder(canvas); updateStatus() }
    @objc func chooseTool(_ sender: NSButton) { if let s = sender.identifier?.rawValue, let t = SketchTool(rawValue: s) { setTool(t) } }
    @objc func changeColor(_ sender: Any) {
        // NSColorPanel can route its standard changeColor: before a custom
        // target is installed. It uses calibrated components, unlike pen state.
        if let panel = sender as? NSColorPanel { changeCustomColor(panel) }
        else if let well = sender as? NSColorWell { applyChosenColor(well.color, modifiers: NSApp.currentEvent?.modifierFlags ?? []) }
    }
    func applyChosenColor(_ color: NSColor, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            canvas.setBackgroundColor(color); colorWell.color = canvas.strokeColor
        } else {
            canvas.strokeColor = color; canvas.applyColorToSelection(color)
        }
        rememberDrawingDefaults(); syncDrawingControls()
        writeLayoutEvidence()
    }
    @objc func changeWidth(_ sender: NSControl) {
        let size = OriginalDrawingControls.size(sender.doubleValue, continuous: true)
        canvas.strokeWidth = CGFloat(size); canvas.fontSize = OriginalDrawingControls.readableFontSize(size, displayFontScale: canvas.outputSize.height / canvas.canvasSize.height)
        _ = canvas.convertSelectedTextFonts({ NSFont(name: $0.fontName, size: self.canvas.fontSize) }, name: "Change Text Size")
        rememberDrawingDefaults(); syncDrawingControls(); updateStatus(); writeLayoutEvidence()
    }
    func endDrawingSizeGesture() {
        guard sizeUndoGrouping else { return }
        sizeUndoGrouping = false; canvas.editingUndoManager.endUndoGrouping(); writeLayoutEvidence()
    }
    func syncDrawingControls() {
        colorWell.color = canvas.strokeColor
        widthControl.doubleValue = Double(canvas.strokeWidth)
        sizeLabel.stringValue = "Size · " + String(format: "%.3g", widthControl.doubleValue)
        let indicatorColor = canvas.strokeColor
        paletteButton.image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            indicatorColor.setFill(); rect.insetBy(dx: 1, dy: 1).fill()
            NSColor.darkGray.setStroke(); NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke(); return true
        }
        let chosen = SketchColor(canvas.strokeColor)
        for button in presetColorButtons {
            let preset = OriginalDrawingControls.presets.first { $0.tag == button.tag }
            button.state = preset.map { SketchColor($0.color) == chosen } == true ? .on : .off
        }
        paletteButton.setAccessibilityValue(String(format: "Red %.3g, green %.3g, blue %.3g, alpha %.3g", chosen.red, chosen.green, chosen.blue, chosen.alpha))
    }
    @objc func showDrawingColors(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress, window.attachedSheet == nil else { return }
        if let colorPopover, colorPopover.isShown {
            // Keep click/keyboard access stable when entering Color first
            // opened it by hover. An explicit activation pins the palette.
            if colorOpenedByHover {
                colorOpenedByHover = false; colorHoverDismissal?.cancel(); colorHoverDismissal = nil
            } else { closeDrawingColors() }
            writeLayoutEvidence(); return
        }
        presentDrawingColors(hover: false)
    }
    func drawingColorHover(_ inside: Bool, palette: Bool) {
        if palette { colorPaletteHovered = inside } else { colorControlHovered = inside }
        colorHoverDismissal?.cancel(); colorHoverDismissal = nil
        if inside {
            if !palette && colorPopover?.isShown != true { presentDrawingColors(hover: true) }
        } else if colorOpenedByHover && !colorControlHovered && !colorPaletteHovered {
            // The modern popover has an arrow gap absent from the old panel.
            // Briefly bridge that gap so crossing into the swatches cannot close it.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.colorOpenedByHover, !self.colorControlHovered, !self.colorPaletteHovered else { return }
                self.closeDrawingColors()
            }
            colorHoverDismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now()+0.12, execute: work)
        }
    }
    func closeDrawingColors() {
        colorHoverDismissal?.cancel(); colorHoverDismissal = nil
        colorOpenedByHover = false; colorControlHovered = false; colorPaletteHovered = false
        (colorPopover?.contentViewController?.view as? BezelHoverPaletteView)?.onHover = nil
        colorPopover?.performClose(nil)
    }
    func presentDrawingColors(hover: Bool) {
        guard !terminationStarted, !frameCaptureInProgress, window.isVisible,
              window.attachedSheet == nil, colorPopover?.isShown != true else { return }
        colorOpenedByHover = hover
        let view = BezelHoverPaletteView(frame: NSRect(x: 0, y: 0, width: 246, height: 140))
        view.onHover = { [weak self] inside in self?.drawingColorHover(inside, palette: true) }
        if modernChrome == nil { view.appearance = NSAppearance(named: .aqua) }
        let title = label("Drawing colors"); title.frame = NSRect(x: 12, y: 108, width: 222, height: 25); view.addSubview(title)
        presetColorButtons.removeAll()
        for (index, preset) in OriginalDrawingControls.presets.enumerated() {
            let button = BezelColorButton(frame: NSRect(x: CGFloat(12+(index%5)*44), y: CGFloat(68-(index/5)*34), width: 42, height: 32))
            button.title = ""; button.isBordered = false; button.font = .systemFont(ofSize: 18)
            button.drawingColor = preset.swatchColor; button.tag = preset.tag
            button.target = self; button.action = #selector(choosePresetColor(_:))
            button.setAccessibilityLabel(preset.name); button.toolTip = preset.name + "; Shift changes the background"
            trackHint(button, owner: "color-" + String(preset.tag)) { OriginalHintMessages.hover(actionTag: preset.tag) }
            presetColorButtons.append(button); view.addSubview(button)
        }
        let custom = button("Custom color…", #selector(chooseCustomColor(_:))); custom.font = .systemFont(ofSize: 20)
        custom.frame = NSRect(x: 12, y: 2, width: 222, height: 30); custom.tag = 110; view.addSubview(custom)
        let controller = NSViewController(); controller.view = view
        let popover = NSPopover(); popover.behavior = .transient; popover.contentViewController = controller
        if modernChrome == nil { popover.appearance = NSAppearance(named: .aqua) }
        colorPopover = popover; syncDrawingControls()
        popover.show(relativeTo: paletteButton.bounds, of: paletteButton, preferredEdge: .minX)
        writeLayoutEvidence()
    }
    @objc func choosePresetColor(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress,
              let preset = OriginalDrawingControls.presets.first(where: { $0.tag == sender.tag }) else { return }
        applyChosenColor(preset.color, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
        closeDrawingColors()
    }
    @objc func chooseCustomColor(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        closeDrawingColors()
        guard let chosen = OriginalDrawingControls.drawingColor(from: customDrawingColor) else { return }
        applyChosenColor(chosen, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
        let panel = NSColorPanel.shared; panel.showsAlpha = true; panel.isContinuous = true
        panel.setTarget(self); panel.setAction(#selector(changeCustomColor(_:)))
        panel.color = customDrawingColor; panel.orderFront(sender)
    }
    @objc func changeCustomColor(_ sender: NSColorPanel) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        guard let chosen = OriginalDrawingControls.drawingColor(from: sender.color) else { return }
        customDrawingColor = sender.color
        applyChosenColor(chosen, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
    }
    func rememberDrawingDefaults() {
        let color = SketchColor(canvas.strokeColor)
        let custom = OriginalDrawingControls.drawingColor(from: customDrawingColor) ?? OriginalDrawingControls.presets[0].color
        legacyMetadata.root["skitchBrushColor"] = OriginalDrawingControls.legacyRGB(canvas.strokeColor)
        legacyMetadata.root["skitchBrushColorAlpha"] = String(Double(color.alpha))
        legacyMetadata.root["skitchBrushSize"] = String(Double(canvas.strokeWidth))
        legacyMetadata.root["skitchCustomColor"] = OriginalDrawingControls.legacyRGB(custom)
        legacyMetadata.root["skitchCustomColorAlpha"] = String(Double(SketchColor(custom).alpha))
    }
    func restoreDrawingDefaults() {
        closeDrawingColors()
        if let color = OriginalDrawingControls.legacyColor(legacyMetadata.root["skitchBrushColor"], alpha: legacyMetadata.root["skitchBrushColorAlpha"]) {
            canvas.strokeColor = color
        }
        if let custom = OriginalDrawingControls.legacyColor(legacyMetadata.root["skitchCustomColor"], alpha: legacyMetadata.root["skitchCustomColorAlpha"]) {
            let rgba = SketchColor(custom)
            customDrawingColor = NSColor(calibratedRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        }
        if let size = Double(legacyMetadata.root["skitchBrushSize"] ?? ""), size.isFinite {
            canvas.strokeWidth = CGFloat(OriginalDrawingControls.size(size, continuous: true))
            canvas.fontSize = OriginalDrawingControls.readableFontSize(Double(canvas.strokeWidth), displayFontScale: canvas.outputSize.height / canvas.canvasSize.height)
        }
        syncDrawingControls()
    }
    @objc func toggleBezelFill(_ sender: NSMenuItem) { canvas.filled.toggle(); canvas.applyStyleToSelection() }
    @objc func toggleBezelShadow(_ sender: NSMenuItem) { canvas.shadowed.toggle(); canvas.applyStyleToSelection() }
    @objc func changeZoom(_ sender: NSPopUpButton) {
        guard !isActualSize, let scale = sender.selectedItem?.representedObject as? Double else { return }
        canvas.setZoom(CGFloat(scale)); updateStatus()
    }
    func fitCanvasToWindow() {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let scroll = canvas.enclosingScrollView else { return }
        let viewport = scroll.contentView.bounds.size, size = canvas.outputSize
        let scale = min(1, max(0.05, min((viewport.width-20)/size.width, (viewport.height-20)/size.height)))
        setCanvasDisplayZoom(scale, label: "Fit")
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    func setCanvasDisplayZoom(_ scale: CGFloat, label: String) {
        canvas.setZoom(scale)
        for item in zoomControl.itemArray where item.tag == 999 { zoomControl.menu?.removeItem(item) }
        let item = NSMenuItem(title: "\(label) · \(Int((canvas.zoom*100).rounded()))%", action: nil, keyEquivalent: "")
        item.tag = 999; item.representedObject = Double(canvas.zoom); zoomControl.menu?.insertItem(item, at: 0); zoomControl.select(item)
    }
    func changed() {
        if isActualSize { _ = canvas.setPresentationOutputSize(canvas.fullResolutionOutputSize); scheduleNavigatorImage() }
        if !restoring { dirty = true }
        window?.isDocumentEdited = dirty; updateStatus(); updateWipeButton()
        historyFollowTimer?.invalidate()
        if currentArchiveID != nil {
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in Task { @MainActor in self?.followHistory() } }
            historyFollowTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    /// Original updateWipeButton: Blank (disabled) / Clear / Wipe, derived from the canvas.
    func updateWipeButton() {
        if wipeRailButton == nil { wipeRailButton = findWipeButton(in: window?.contentView) }
        guard let button = wipeRailButton else { return }
        let stage = canvas.wipeStage
        if button.title != stage.title { button.title = stage.title }
        if button.isEnabled != stage.isEnabled { button.isEnabled = stage.isEnabled }
    }
    private func findWipeButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.action == #selector(wipe) { return button }
        for sub in view.subviews { if let found = findWipeButton(in: sub) { return found } }
        return nil
    }
    func updateStatus() { status.stringValue = "\(canvas.tool.rawValue.capitalized) · \(dirty ? "Unsaved changes" : "Saved")"; updateViewportChrome(); scheduleDragPreview() }
    var dragFormat: String {
        let formats = ["png", "jpeg", "jpeg", "jpeg", "jpeg", "jpeg", "tiff", "gif", "bmp", "pdf", "svg", "skitch"]
        return formats.indices.contains(dragFormatControl.indexOfSelectedItem) ? formats[dragFormatControl.indexOfSelectedItem] : "png"
    }
    var dragQuality: Double {
        let values = [1.0, 1.0, 0.8, 0.6, 0.3, 0.1]
        return values.indices.contains(dragFormatControl.indexOfSelectedItem) ? values[dragFormatControl.indexOfSelectedItem] : 0.6
    }
    @objc func changeDragOptions(_ sender: Any?) {
        UserDefaults.standard.set(dragFormatControl.indexOfSelectedItem, forKey: "DragFormatChoice")
        UserDefaults.standard.set(dragOriginalControl.state == .on, forKey: "DragOriginalSize")
        scheduleDragPreview()
    }
    func scheduleDragPreview() {
        guard dragExportView != nil else { return }
        dragPreviewTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDragPreview() }
        }
        dragPreviewTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func updateDragPreview() {
        dragPreviewTimer?.invalidate(); dragPreviewTimer = nil
        let original = dragAtOriginalSize
        let size = original && canvas.document.backgroundPNG != nil ? canvas.canvasSize : canvas.outputSize
        if let data = try? exportData(format: dragFormat, originalSize: original, jpegQuality: dragQuality) {
            dragSizeLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) · " + ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        } else { dragSizeLabel.stringValue = "Preview unavailable" }
        if let raw = try? canvas.snapshotDocumentData(), let document = try? CanvasView.validatedDocumentData(raw) {
            let scale = min(1, 128 / max(document.size.width, document.size.height))
            dragExportView?.overview = ImageExport.image(document: document, size: CGSize(width: max(1, ceil(document.size.width * scale)), height: max(1, ceil(document.size.height * scale))))
        }
        feedCanvasBleed()
    }
    func safeName() -> String { let s = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return (s.isEmpty ? "Skitch" : s).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
    func applyFrameWindowValues() {
        window.hasShadow = false
        window.alphaValue = CGFloat(Float32(bitPattern: 0x3f4ccccd))
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    }
    /// The screen-saver Frame level would bury alerts and panels (they open at modal level),
    /// so modals shown during Frame run with the stored pre-Frame window values.
    func withFrameWindowValuesSuspended<T>(_ body: () -> T) -> T {
        guard frameMode else { return body() }
        window.hasShadow = frameWindowHadShadow; window.alphaValue = frameWindowAlpha; window.level = frameWindowLevel
        defer { if frameMode { applyFrameWindowValues() } }
        return body()
    }
    func error(_ error: Error) { let a = NSAlert(error: error); _ = withFrameWindowValuesSuspended { a.runModal() } }
    func allowDiscard(discardingForTermination: Bool = false) -> Bool {
        if discardedForTermination { return true }
        guard dirty || canvas.hasPendingTextChanges else { return true }
        let a = NSAlert(); a.messageText = "Save your drawing?"; a.informativeText = "This document has changes that have not been saved."; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Discard")
        let result = withFrameWindowValuesSuspended { a.runModal() }
        if result == .alertFirstButtonReturn { return save() }
        if result == .alertThirdButtonReturn {
            if discardingForTermination { discardedForTermination = true; dirty = false }
            return true
        }
        return false
    }
    @objc func newFile() {
        guard !terminationStarted, allowDiscard() else { return }
        do {
            // The original loads the replacement and registers one transaction (loadFromFileTA, decompiled.c:314172-314243).
            let scratch = CanvasView(frame: .zero); scratch.newBlank(size: NSSize(width: 1000, height: 700))
            try restoreHistoryEditorState(HistoryEditorState(data: try scratch.snapshotDocumentData(), metadata: .init(), name: "Untitled",
                url: nil, archiveID: nil, dirty: false), actionName: "New", resetDrawingDefaults: false)
            replaceDragPresentation()
        } catch { self.error(error) }
    }
    @objc func openFile() { let p = NSOpenPanel(); p.allowedContentTypes = [.image, .pdf, .data]; p.allowsMultipleSelection = false; if withFrameWindowValuesSuspended({ p.runModal() }) == .OK, let u = p.url { openURL(u) } }
    func openURL(_ url: URL) {
        guard !terminationStarted else { return }
        guard allowDiscard() else { return }
        do {
            let state: HistoryEditorState, native = ["skitchredux", "skitch"].contains(url.pathExtension.lowercased())
            if native {
                let file = try SkitchFile.read(url)
                // Bundled samples stay intact; ordinary drawings save in place.
                state = HistoryEditorState(data: try file.canvasData, metadata: file.metadata, name: url.deletingPathExtension().lastPathComponent,
                    url: url.path.contains(".app/Contents/Resources/") ? nil : url, archiveID: nil, dirty: false)
            } else {
                guard let image = NSImage(contentsOf: url) else { throw NSError(domain: "SkitchRedux", code: 3, userInfo: [NSLocalizedDescriptionKey: "The file could not be read as an image."]) }; var proposed = CGRect(origin: .zero, size: image.size)
                guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                    throw NSError(domain: "SkitchRedux", code: 5, userInfo: [NSLocalizedDescriptionKey: "This image is too large or cannot be decoded safely."])
                }
                let scratch = CanvasView(frame: .zero)
                scratch.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); scratch.setBackground(image)
                state = HistoryEditorState(data: try scratch.snapshotDocumentData(), metadata: .init(), name: url.deletingPathExtension().lastPathComponent,
                    url: nil, archiveID: nil, dirty: false)
            }
            try restoreHistoryEditorState(state, actionName: "Open", resetDrawingDefaults: native, rasterViewport: !native)
            replaceDragPresentation()
        } catch { self.error(error) }
    }
    func save(forceChoose: Bool = false) -> Bool {
        if let session = activeResizeSession {
            do { guard try session.apply() else { return false } }
            catch { self.error(error); return false }
        }
        endWindowGesture()
        var url = forceChoose ? nil : currentURL
        if url == nil { let p = NSSavePanel(); p.nameFieldStringValue = safeName()+".skitch"; p.allowedContentTypes = [UTType(filenameExtension: "skitch") ?? .data, UTType(filenameExtension: "skitchredux") ?? .data]; if p.runModal() != .OK { return false }; url = p.url }
        do {
            guard let url else { return false }
            let snapshot = try canvas.snapshotDocumentData(); let document = try CanvasView.validatedDocumentData(snapshot)
            try SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot).write(to: url)
            canvas.commitPendingTextEditing(); currentURL = url; dirty = false; window.isDocumentEdited = false; updateStatus()
            status.stringValue = "Saved " + url.lastPathComponent
            if isActualSize { actualView?.savedWhileActive = true }
            archive(try HistoryStore.Snapshot(canvasData: snapshot, metadata: legacyMetadata, preview: canvas.imageData(format: "png")), name: safeName(), action: .exported, destination: url.path, generation: documentGeneration)
            return true
        } catch { self.error(error); return false }
    }
    @objc func saveFile() { _ = save() }
    @objc func saveAs() { _ = save(forceChoose: true) }
    func saveRecovery(finalizingTermination: Bool = false) {
        // Queued timer work must not interpret the temporary Discard dirty flag
        // as permission to delete recovery before backend cleanup succeeds.
        guard !terminationStarted || finalizingTermination else { return }
        guard activeResizeSession?.lastPreview == nil else { return }
        followHistory()
        let url = support.appendingPathComponent("Recovery.skitch")
        guard dirty || canvas.hasPendingTextChanges else { removeRecovery(); return }
        guard let snapshot = try? canvas.snapshotDocumentData(), let document = try? CanvasView.validatedDocumentData(snapshot), let data = try? SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot).encoded() else { return }
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.removeItem(at: support.appendingPathComponent("Recovery.skitchredux"))
        } catch { return }
    }
    func removeRecovery() {
        for name in ["Recovery.skitch", "Recovery.skitchredux"] { try? FileManager.default.removeItem(at: support.appendingPathComponent(name)) }
    }
    func archiveStore() throws -> HistoryStore {
        if let historyStore { return historyStore }
        let store = try HistoryStore(directory: support.appendingPathComponent("History"))
        historyStore = store
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let legacyIndex = home.appendingPathComponent("Library/Application Support/Skitch/history")
        if ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] == nil,
           FileManager.default.fileExists(atPath: legacyIndex.path) {
            do {
                guard (try legacyIndex.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw HistoryStore.Failure.unsafePath }
                _ = try store.importLegacy(indexData: Data(contentsOf: legacyIndex), archiveDirectory: home.appendingPathComponent("Pictures/Skitch"))
            } catch { status.stringValue = "Old Skitch History could not be imported; originals were kept: " + error.localizedDescription }
        }
        return store
    }
    func historySnapshot() throws -> HistoryStore.Snapshot {
        let raw = try canvas.snapshotDocumentData()
        let document = try CanvasView.validatedDocumentData(raw)
        let preview = ImageExport.encode(document: document, size: document.outputSize, format: "png")
        return try HistoryStore.Snapshot(canvasData: raw, metadata: legacyMetadata, preview: preview)
    }
    @discardableResult
    func archive(_ snapshot: HistoryStore.Snapshot, name: String, action: HistoryStore.Action,
                 destination: String? = nil, remoteURL: URL? = nil, remoteBinding: [String: String]? = nil, generation: UUID) -> Bool {
        guard !snapshot.isEmpty else { return false }
        do {
            let store = try archiveStore()
            let id = try store.archive(snapshot, name: name, action: action, destination: destination, remoteURL: remoteURL, remoteBinding: remoteBinding)
            if documentGeneration == generation {
                followHistory(); currentArchiveID = id
                // An asynchronous export may have completed after more edits.
                // Keep its successful-output snapshot, then follow the live copy.
                followHistory()
            }
            refreshHistory()
            return true
        } catch { status.stringValue = "History could not be updated: " + error.localizedDescription; return false }
    }
    func followHistory() {
        guard activeResizeSession?.lastPreview == nil else { return }
        historyFollowTimer?.invalidate(); historyFollowTimer = nil
        guard let id = currentArchiveID else { return }
        do { try archiveStore().follow(id, snapshot: historySnapshot(), name: safeName()); refreshHistory() }
        catch { status.stringValue = "History update failed; the previous archive was preserved: " + error.localizedDescription }
    }
    @objc func saveHistory() {
        do {
            if archive(try historySnapshot(), name: safeName(), action: .archived, generation: documentGeneration) { status.stringValue = "Saved to History" }
        } catch { self.error(error) }
    }
    func refreshHistory() {
        guard let browser = historyBrowser, let store = historyStore else { return }
        browser.update(items: store.entries.map { entry in
            HistoryBrowser.Item(id: entry.id, name: entry.name, date: entry.date, size: entry.size,
                action: entry.action.title, text: entry.text, destination: entry.destination,
                link: entry.remoteURL, previewURL: store.previewURL(entry), missing: store.missing(entry.id))
        })
    }
    @objc func showHistory() {
        do {
            _ = try archiveStore(); followHistory()
            if historyBrowser == nil {
                let browser = HistoryBrowser()
                browser.onOpen = { [weak self] ids in if let id = ids.first { self?.openHistory(id) } }
                browser.onCopy = { [weak self] ids in self?.copyHistory(ids) }
                browser.onCopyLink = { [weak self] ids in self?.copyHistoryLink(ids) }
                browser.onOpenLink = { [weak self] ids in
                    guard let self, let id = ids.first, let url = self.historyStore?.entry(id)?.remoteURL,
                          ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
                    NSWorkspace.shared.open(url)
                }
                browser.onRemove = { [weak self] ids in self?.removeHistory(ids, deleteFiles: false) }
                browser.onDeleteFiles = { [weak self] ids in self?.removeHistory(ids, deleteFiles: true) }
                browser.onDeleteRemote = { [weak self] ids in self?.deleteHistoryRemote(ids) }
                browser.onExport = { [weak self] id, format in
                    guard let self else { throw HistoryStore.Failure.missing }
                    return try self.historyExport(id, format: format)
                }
                browser.onError = { [weak self] in self?.error($0) }
                historyBrowser = browser
            }
            refreshHistory(); historyBrowser?.showWindow(nil); historyBrowser?.window?.makeKeyAndOrderFront(nil)
        } catch { self.error(error) }
    }
    struct HistoryEditorState {
        let data: Data; let metadata: LegacyBridge.Metadata; let name: String
        let url: URL?; let archiveID: UUID?; let dirty: Bool
    }
    func historyEditorState() throws -> HistoryEditorState {
        HistoryEditorState(data: try canvas.snapshotDocumentData(), metadata: legacyMetadata, name: nameField.stringValue,
                           url: currentURL, archiveID: currentArchiveID, dirty: dirty)
    }
    /// The whole document identity participates in the same Undo operation as
    /// the artwork, so reopening History cannot redirect a later Save.
    func restoreHistoryEditorState(_ state: HistoryEditorState, actionName: String = "Open History",
                                   resetDrawingDefaults: Bool = true, rasterViewport: Bool = false) throws {
        _ = try CanvasView.validatedDocumentData(state.data)
        canvas.commitPendingTextEditing()
        activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize()
        let inverse = try historyEditorState()
        followHistory(); leaveFrame()
        restoring = true
        defer { restoring = false }
        try canvas.loadDocument(data: state.data, clearingUndo: false)
        legacyMetadata = state.metadata; if resetDrawingDefaults { restoreDrawingDefaults() }; nameField.stringValue = state.name; currentURL = state.url
        currentArchiveID = state.archiveID; dirty = state.dirty; documentGeneration = UUID()
        let manager = canvas.editingUndoManager
        let grouping = !manager.isUndoing && !manager.isRedoing
        if grouping { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { app in
            do { try app.restoreHistoryEditorState(inverse, actionName: actionName, resetDrawingDefaults: resetDrawingDefaults) } catch { app.error(error) }
        }
        manager.setActionName(actionName)
        if grouping { manager.endUndoGrouping() }
        if rasterViewport { adoptRasterViewport() } else { fitCanvasToWindow() }
        window.isDocumentEdited = dirty; updateStatus(); refreshHistory()
    }
    func openHistory(_ id: UUID) {
        guard !terminationStarted else { return }
        do {
            let store = try archiveStore(), file = try store.read(id)
            guard let entry = store.entry(id) else { throw HistoryStore.Failure.missing }
            try restoreHistoryEditorState(HistoryEditorState(data: file.canvasData, metadata: file.metadata,
                name: entry.name, url: nil, archiveID: id, dirty: true))
            historyBrowser?.window?.orderOut(nil)
            replaceDragPresentation(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
        } catch { self.error(error); refreshHistory() }
    }
    func historyExport(_ id: UUID, format: String) throws -> Data {
        let file = try archiveStore().read(id)
        if format == "skitch" { return try file.encoded() }
        if format == "svg" { return try file.encoded(includeSupplementalState: false) }
        let view = CanvasView(frame: .zero); try view.loadDocument(data: file.canvasData)
        guard let data = view.imageData(format: format) else { throw HistoryStore.Failure.missing }
        return data
    }
    func copyHistory(_ ids: [UUID]) {
        do {
            guard let id = ids.first else { return }
            let file = try archiveStore().read(id), native = try file.encoded()
            let view = CanvasView(frame: .zero); try view.loadDocument(data: file.canvasData)
            guard let png = view.imageData(format: "png") else { throw HistoryStore.Failure.missing }
            let board = NSPasteboard.general; board.clearContents()
            board.setData(png, forType: .png)
            board.setData(native, forType: NSPasteboard.PasteboardType("com.shoemoney.skitch-redux.native"))
            if let tiff = view.renderedImage().tiffRepresentation { board.setData(tiff, forType: .tiff) }
        } catch { self.error(error) }
    }
    func copyHistoryLink(_ ids: [UUID]) {
        guard let id = ids.first, let entry = historyStore?.entry(id), entry.action == .shared,
              let url = entry.remoteURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    func removeHistory(_ ids: [UUID], deleteFiles: Bool) {
        guard !ids.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = deleteFiles ? "Move archived drawings to Trash?" : "Hide drawings from History?"
        alert.informativeText = deleteFiles ? "The selected History copies and previews will move to Trash. Exported originals and web posts are kept." : "The selected drawings will leave the History list. Their archive files and web posts are kept."
        alert.addButton(withTitle: deleteFiles ? "Move to Trash" : "Hide"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if deleteFiles { try archiveStore().trash(Set(ids)) } else { try archiveStore().remove(Set(ids), deleteFiles: false) }
            if let id = currentArchiveID, ids.contains(id) { currentArchiveID = nil }
            refreshHistory()
        } catch { self.error(error) }
    }
    func deleteHistoryRemote(_ ids: [UUID]) {
        guard !terminationStarted, let id = ids.first, ids.count == 1,
              let entry = historyStore?.entry(id), let url = entry.remoteURL, let binding = entry.remoteBinding else {
            status.stringValue = "This item has no verified publication destination for deletion."; return
        }
        let alert = NSAlert(); alert.messageText = "Delete this web post?"
        alert.informativeText = "This removes the published image at " + url.absoluteString + ". Its editable History copy will be kept."
        alert.addButton(withTitle: "Delete from Web"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        status.stringValue = "Deleting web post…"
        historyRemoteDeletion.deleteRemote(url: url, binding: binding, presenting: window) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    do { try self.archiveStore().clearRemote(id); self.refreshHistory(); self.status.stringValue = "Web post deleted; History copy kept" }
                    catch { self.error(error) }
                case .failure(let error): if !self.terminationStarted { self.error(error) }
                }
            }
        }
    }
    @objc func showPhotos() {
        photoBrowser.show(relativeTo: window) { [weak self] url in self?.openURL(url) }
    }
    func exportData(format: String, originalSize: Bool, jpegQuality: Double) throws -> Data {
        if ["svg", "skitch"].contains(format.lowercased()) {
            var snapshot = try canvas.snapshotDocumentData(), document = try CanvasView.validatedDocumentData(snapshot)
            if format.lowercased() == "skitch", originalSize, document.backgroundPNG != nil {
                var raw = try JSONSerialization.jsonObject(with: snapshot) as! [String: Any]
                raw.removeValue(forKey: "renderSize")
                snapshot = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
                document = try CanvasView.validatedDocumentData(snapshot)
            }
            let file = SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot)
            if format.lowercased() == "skitch" { return try file.encoded() }
            return try file.exportedSVG(size: originalSize && document.backgroundPNG != nil ? document.size : document.outputSize)
        }
        guard let encoded = canvas.imageData(format: format, originalSize: originalSize, jpegQuality: jpegQuality) else {
            throw NSError(domain: "SkitchRedux", code: 4, userInfo: [NSLocalizedDescriptionKey: "That export format could not be encoded."])
        }
        return encoded
    }
    @objc func exportFile() {
        let panel = NSSavePanel()
        panel.title = "Export"; panel.nameFieldLabel = "Export As:"; panel.prompt = "Export"
        let options = ExportAccessory(format: UserDefaults.standard.string(forKey: "ExportFormat") ?? "png",
            originalSize: UserDefaults.standard.bool(forKey: "ExportOriginalSize"),
            jpegQuality: UserDefaults.standard.object(forKey: "ExportQuality") as? Double ?? 0.7)
        panel.accessoryView = options.view; panel.allowsOtherFileTypes = false
        let refresh = { [weak self, weak panel, weak options] in
            guard let self, let panel, let options else { return }
            // Commit the filename editor before replacing its extension; otherwise
            // AppKit can restore the editor's old text when the format popup closes.
            if let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor {
                panel.makeFirstResponder(nil)
            }
            panel.allowedContentTypes = [UTType(filenameExtension: options.format) ?? .data]
            let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = (stem.isEmpty ? self.safeName() : stem) + "." + options.format
            let size = options.originalSize && self.canvas.document.backgroundPNG != nil ? self.canvas.canvasSize : self.canvas.outputSize
            let data = try? self.exportData(format: options.format, originalSize: options.originalSize, jpegQuality: options.jpegQuality)
            options.updateByteCount(data?.count, size: size)
        }
        options.onChange = refresh
        panel.nameFieldStringValue = safeName() + "." + options.format
        refresh()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try exportData(format: options.format, originalSize: options.originalSize, jpegQuality: options.jpegQuality)
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(options.format, forKey: "ExportFormat")
            UserDefaults.standard.set(options.originalSize, forKey: "ExportOriginalSize")
            UserDefaults.standard.set(options.jpegQuality, forKey: "ExportQuality")
            status.stringValue = "Exported " + url.lastPathComponent
            archive(try historySnapshot(), name: safeName(), action: .exported, destination: url.path, generation: documentGeneration)
        } catch { self.error(error) }
    }
    @objc func pageSetup() {
        let settings = NSPrintInfo.shared.copy() as! NSPrintInfo
        if NSPageLayout().runModal(with: settings) == NSApplication.ModalResponse.OK.rawValue { NSPrintInfo.shared = settings }
        writeLayoutEvidence()
    }
    @objc func printImage() { let view = NSImageView(frame: NSRect(origin: .zero,size: canvas.outputSize)); view.image = canvas.renderedImage(); view.imageScaling = .scaleProportionallyUpOrDown; let p = NSPrintInfo.shared.copy() as! NSPrintInfo; p.horizontalPagination = .fit; p.verticalPagination = .fit; NSPrintOperation(view: view, printInfo: p).run() }
    @objc func share(_ sender: NSButton) {
        guard let snapshot = try? historySnapshot() else { return }
        pickerSnapshot = ShareSnapshot(snapshot: snapshot, name: safeName(), generation: documentGeneration)
        let picker = NSSharingServicePicker(items: [canvas.renderedImage()]); picker.delegate = self; sharePicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        if let snapshot = pickerSnapshot { sharingSnapshots[ObjectIdentifier(sharingService)] = snapshot }
        return self
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { pickerSnapshot = nil }; sharePicker = nil
    }
    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        guard let value = sharingSnapshots.removeValue(forKey: ObjectIdentifier(service)) else { return }
        pickerSnapshot = nil
        archive(value.snapshot, name: value.name, action: .shared, destination: service.title, generation: value.generation)
    }
    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        sharingSnapshots.removeValue(forKey: ObjectIdentifier(service)); pickerSnapshot = nil
        if !terminationStarted { self.error(error) }
    }
    @objc func showPreferences() {
        guard !terminationStarted, !frameCaptureInProgress, window?.attachedSheet == nil,
              preferencesWindow?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        if preferencesWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 570),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Preferences"; panel.isReleasedWhenClosed = false
            panel.contentMinSize = NSSize(width: 650, height: 500); panel.delegate = self
            let form = GeneralPreferencesForm(state: generalPreferences.state)
            form.onChange = { [weak self] in self?.applyGeneralPreferences($0) }
            form.onDone = { [weak self] in self?.closePreferences() }
            form.onRelaunch = { [weak self] in self?.relaunch() }
            form.onShortcuts = { [weak self] in
                guard let self, !self.terminationStarted else { return }
                self.hotkeys.showSettings(attachedTo: self.preferencesWindow)
            }
            form.onSharing = { [weak self] in
                guard let self, !self.terminationStarted, let panel = self.preferencesWindow else { return }
                self.publishing.showSettings(relativeTo: panel)
            }
            panel.contentView = form
            preferencesForm = form; preferencesWindow = panel; panel.center()
        }
        preferencesForm?.synchronize(generalPreferences.state)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    func applyGeneralPreferences(_ state: GeneralPreferencesState) {
        guard !terminationStarted else { return }
        let previous = generalPreferences.state
        generalPreferences.apply(state)
        let saved = generalPreferences.state
        canvas.strokeSmoothing = saved.drawingPrecision
        canvas.arrowHeadPreference = UserDefaults.standard.integer(forKey: OriginalArrowGeometry.preferenceKey)
        preferencesForm?.synchronize(saved)
        if saved.statusMenu != previous.statusMenu { applyPresencePolicy() }
        if !saved.playSounds { soundEffects.stop() }
        helpBevel?.enabled = saved.showKeyboardTips
    }
    /// Quits through the normal Save/Discard decision; the fresh instance starts only once this one has released its global shortcuts.
    func relaunch() {
        guard !terminationStarted, allowDiscard(discardingForTermination: true) else { return }
        saveRecovery()
        pendingRelaunch = Bundle.main.bundleURL
        NSApp.terminate(nil)
    }
    func closePreferences() {
        guard let panel = preferencesWindow, panel.attachedSheet == nil else { return }
        panel.orderOut(nil)
        if !terminationStarted, window.isVisible { window.makeKeyAndOrderFront(nil) }
    }
    @objc func closeCurrentWindow() {
        closeWindow(NSApp.keyWindow)
    }
    func closeWindow(_ keyWindow: NSWindow?) {
        if let keyWindow, keyWindow === preferencesWindow { closePreferences() }
        else if let keyWindow, keyWindow !== window { keyWindow.performClose(nil) }
        else { toggleVisible() }
    }
    @objc func shortcutSettings() { hotkeys.showSettings(attachedTo: window) }
    @objc func sharingSettings() { publishing.showSettings(relativeTo: window) }
    @objc func publishImage() {
        guard let data = canvas.imageData(format: "png"), let snapshot = try? historySnapshot() else { return }
        let name = safeName(), generation = documentGeneration
        let fileName = name+"-"+UUID().uuidString.lowercased()+".png"
        let binding = try? historyRemoteDeletion.captureBinding(fileName: fileName)
        status.stringValue = "Publishing image…"
        publishing.publish(data: data, fileName: fileName, presenting: window) { [weak self] result in
            // Publishing guarantees delivery on main, including nested AppKit
            // termination loops. Archive success before its shutdown barrier can
            // acknowledge completion; an extra Task could run after app exit.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.receivePublishing(result)
                if case .success(let url) = result {
                    let currentBinding = try? self.historyRemoteDeletion.captureBinding(for: url)
                    let retainedBinding = binding == currentBinding ? binding : nil
                    self.archive(snapshot, name: name, action: .shared, destination: url.absoluteString, remoteURL: url, remoteBinding: retainedBinding, generation: generation)
                }
            }
        }
    }
    func receivePublishing(_ result: Result<URL, Error>) {
        guard !terminationStarted else { return }
        switch result {
        case .success(let url):
            status.stringValue = ["http", "https"].contains(url.scheme ?? "") ? "Published image" : "Uploaded image to destination"
        case .failure(let error):
            updateStatus()
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSUserCancelledError { self.error(error) }
        }
    }
    /// Snap & Upload hotkey: a crosshair capture whose installed result is published.
    /// A cancelled, failed or declined capture never reaches publishImage().
    func snapAndUpload() {
        startCapture("crosshair", afterInstalling: { [weak self] in self?.publishImage() })
    }
    func startCapture(_ mode: String, delay: Double = 0, manualOption: Bool = false, afterInstalling: (() -> Void)? = nil) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        helpBevel?.clear()
        leaveFrame()
        let generation = documentGeneration
        let includeApp = generalPreferences.includeApp(mode: mode, manualOption: manualOption)
        capture.capture(mode: mode, delay: delay, includeApp: includeApp) { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation, afterInstalling: afterInstalling)
        }
    }
    func receiveCapture(_ result: Result<NSImage,Error>, discardAlreadyApproved: Bool = false, expectedGeneration: UUID? = nil, fitOutput: Bool = true, afterInstalling: (() -> Void)? = nil) {
        guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
        switch result { case .success(let image):
            var proposed = CGRect(origin: .zero, size: image.size)
            guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                self.error(NSError(domain: "SkitchRedux", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
                return
            }
            // Captures may finish after editing resumes. Recheck pending changes
            // here so timed, camera and web captures cannot silently replace them.
            guard discardAlreadyApproved || allowDiscard() else { return }
            guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
            preferencesWindow?.orderOut(nil)
            followHistory(); currentArchiveID = nil; activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize(); canvas.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); canvas.setBackground(image); documentGeneration = UUID(); legacyMetadata = .init(); canvas.editingUndoManager.removeAllActions(); currentURL = nil; if fitOutput { adoptRasterViewport() } else { fitCanvasToWindow() }; nameField.stringValue = "Screenshot"; dirty = true; replaceDragPresentation(); window.makeKeyAndOrderFront(nil); updateStatus()
            playOriginalSound("snap")
            afterInstalling?()
        case .failure(let error): if (error as NSError).code != NSUserCancelledError { self.error(error) } }
    }
    @objc func screenSnap() {
        captureCrosshair(manualOption: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }
    @objc func snapButtonPressed() {
        if frameMode {
            frameTimedSnap = frameTimedSnap || NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            performFrameSnap(delay: frameTimedSnap ? OriginalCaptureTiming.originalDelay : 0)
        }
        else { screenSnap() }
    }
    @objc func cancelSnapshot() {
        capture.cancelCapture { [weak self] result in
            guard let self, !self.terminationStarted else { return }
            self.updateStatus()
            if case .failure(let error) = result { self.error(error) }
        }
    }
    func captureCrosshair(manualOption: Bool) {
        startCapture("crosshair", manualOption: manualOption)
    }
    @objc func fullscreenSnap() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        captureFullscreen(manualOption: flags.contains(.option), delay: OriginalCaptureTiming.manualDelay(flags: flags))
    }
    func captureFullscreen(manualOption: Bool, delay: Double = 0) { startCapture("fullscreen", delay: delay, manualOption: manualOption) }
    @objc func windowSnap() { startCapture("window") }
    @objc func frameSnap() {
        enterFrame(keepingAnnotations: false)
    }
    @objc func resnap() {
        enterFrame(keepingAnnotations: true)
    }
    func enterFrame(keepingAnnotations: Bool, manualFlags: NSEvent.ModifierFlags? = nil) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize()
        canvas.commitPendingTextEditing()
        if !frameMode {
            frameWindowWasOpaque = window.isOpaque
            frameWindowHadShadow = window.hasShadow
            frameWindowAlpha = window.alphaValue
            frameWindowLevel = window.level
            frameWindowBackground = window.backgroundColor
            frameScrollDrewBackground = canvas.enclosingScrollView?.drawsBackground ?? true
        }
        frameTimedSnap = frameTimedSnap || (manualFlags ?? NSApp.currentEvent?.modifierFlags ?? []).contains(.shift)
        frameMode = true; frameKeepsAnnotations = keepingAnnotations
        window.isOpaque = false; window.backgroundColor = .clear
        // Recovered -[PlatformController(snap) setSnapMode:] (decompiled.c:20481): shadow off, screen-saver level, alpha 0x3f4ccccd (0.8f).
        applyFrameWindowValues()
        window.titlebarAppearsTransparent = false
        // A clear window also clears AppKit's titlebar on recent macOS. Keep
        // its adaptive white title readable without filling the canvas hole.
        if frameTitlebarBackdrop == nil,
           let titlebar = window.standardWindowButton(.closeButton)?.superview,
           titlebar.bounds.height > 0, titlebar.bounds.height <= 100 {
            let backdrop = FrameChromeView(frame: titlebar.bounds)
            backdrop.autoresizingMask = [.width, .height]
            titlebar.addSubview(backdrop, positioned: .below, relativeTo: nil)
            frameTitlebarBackdrop = backdrop
        }
        (window.contentView as? FrameChromeView)?.showsCanvasHole = true
        canvas.enclosingScrollView?.drawsBackground = false
        canvas.framePreview = true
        snapButton.cancelOperation(nil)
        snapButton.title = "Snap Frame"
        if modernChrome == nil { snapButton.image = recoveredImage("SnapSnap"); snapButton.imageScaling = .scaleProportionallyDown }
        (snapButton as? OriginalActionButton)?.alternateAction = nil
        snapButton.toolTip = "Capture the area inside the frame; hold Shift for a six-second timer"
        cameraButton.isHidden = true; cancelFrameButton.isHidden = false
        setModernFrameMode(true)
        status.stringValue = keepingAnnotations ? "Frame preview · Snap Frame replaces the picture and keeps your drawing" : "Frame preview · Position the window, then choose Snap Frame"
    }
    @objc func cancelFrame() {
        guard !frameCaptureInProgress else { return }
        leaveFrame()
    }
    func leaveFrame() {
        guard frameMode else { return }
        frameMode = false; frameKeepsAnnotations = false; frameTimedSnap = false
        frameTitlebarBackdrop?.removeFromSuperview(); frameTitlebarBackdrop = nil
        canvas.framePreview = false
        (window.contentView as? FrameChromeView)?.showsCanvasHole = false
        window.isOpaque = frameWindowWasOpaque
        window.hasShadow = frameWindowHadShadow
        window.alphaValue = frameWindowAlpha
        window.level = frameWindowLevel
        window.backgroundColor = frameWindowBackground
        canvas.enclosingScrollView?.drawsBackground = frameScrollDrewBackground
        snapButton.title = "Snap"
        if modernChrome == nil { snapButton.image = recoveredImage("SnapCrosshair"); snapButton.imageScaling = .scaleNone }
        (snapButton as? OriginalActionButton)?.alternateAction = #selector(fullscreenSnap)
        snapButton.toolTip = "Drag an area or click a window; right-click or Control-click for Fullscreen"
        cameraButton.isHidden = false; cancelFrameButton.isHidden = true
        setModernFrameMode(false)
        updateStatus()
    }
    func performFrameSnap(delay: Double = 0) {
        guard !terminationStarted, frameMode, !frameCaptureInProgress else { return }
        if frameKeepsAnnotations, !canvasIsFullyVisible {
            status.stringValue = "Re-Snap needs the whole drawing visible. Reduce zoom or enlarge the window, then try again."
            return
        }
        let visible = canvas.convert(canvas.visibleRect, to: nil)
        let global = window.convertToScreen(visible)
        let top = NSScreen.screens.first?.frame.maxY ?? global.maxY
        capture.frameRect = NSRect(x: global.minX, y: top-global.maxY, width: global.width, height: global.height)
        activeFrameScreenSize = capture.frameRect?.integral.size
        let keepingAnnotations = frameKeepsAnnotations
        let generation = documentGeneration, size = canvas.canvasSize, visibleRect = canvas.visibleRect, zoom = canvas.zoom
        frameCaptureInProgress = true
        capture.capture(mode: "frame", delay: delay) { [weak self] result in
            guard let self else { return }
            self.frameCaptureInProgress = false
            guard self.documentGeneration == generation else { return }
            if keepingAnnotations, (self.canvas.canvasSize != size || self.canvas.visibleRect != visibleRect || self.canvas.zoom != zoom) {
                self.status.stringValue = "The drawing view changed during Re-Snap. Position the frame and try again."
                return
            }
            self.receiveFrameCapture(result, keepingAnnotations: keepingAnnotations, expectedGeneration: generation)
        }
    }
    var canvasIsFullyVisible: Bool {
        let visible = canvas.visibleRect, full = canvas.bounds
        // Allow only subpixel layout rounding, never a clipped document strip.
        return visible.minX <= full.minX + 0.01 && visible.minY <= full.minY + 0.01 &&
            visible.maxX >= full.maxX - 0.01 && visible.maxY >= full.maxY - 0.01
    }
    func receiveFrameCapture(_ result: Result<NSImage, Error>, keepingAnnotations: Bool, expectedGeneration: UUID? = nil) {
        frameCaptureInProgress = false
        guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
        switch result {
        case .success(let image):
            var proposed = CGRect(origin: .zero, size: image.size)
            guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                error(NSError(domain: "SkitchRedux", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
                return
            }
            if keepingAnnotations {
                guard canvas.replaceSnapPreservingAnnotations(image) else {
                    error(NSError(domain: "SkitchRedux", code: 6, userInfo: [NSLocalizedDescriptionKey: "The frame snapshot could not be decoded safely."]))
                    return
                }
                leaveFrame(); updateStatus()
            } else {
                guard allowDiscard() else { return }
                guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
                leaveFrame(); receiveCapture(.success(image), discardAlreadyApproved: true, expectedGeneration: expectedGeneration)
                if let frameSize = activeFrameScreenSize {
                    // Retina capture pixels must not enlarge the next frame.
                    let size = canvas.canvasSize
                    setCanvasDisplayZoom(min(frameSize.width/size.width, frameSize.height/size.height), label: "Frame")
                }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { self.error(error) }
            // A cancelled picker keeps the frame ready for another attempt.
        }
    }
    @objc func timedSnap() {
        let option = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        if let s = prompt("Timed Snapshot", text: "Delay in seconds", value: "6"), let d = Double(s), d >= 0, d <= 120 {
            startCapture("crosshair", delay: d, manualOption: option)
        }
    }
    @objc func cameraSnap() {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        let generation = documentGeneration
        capture.captureCamera { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation, fitOutput: false)
        }
    }
    @objc func webSnap() {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        guard let s = prompt("Snap from Link", text: "Web address", value: "https://"), let url = URL(string: s), ["https","http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let generation = documentGeneration
        capture.captureURL(url) { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation)
        }
    }
    func prompt(_ title: String, text: String, value: String) -> String? { let a = NSAlert(); a.messageText = title; a.informativeText = text; let field = NSTextField(string: value); field.font = .systemFont(ofSize: 20); field.frame = NSRect(x: 0,y: 0,width: 340,height: 32); a.accessoryView = field; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel"); return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil }
    @objc func chooseFont() {
        guard !terminationStarted else { return }
        if let panel = fontPanel, panel.isVisible { panel.orderOut(nil); fontPanelRefreshTimer?.invalidate(); return }
        let panel = NSFontManager.shared.fontPanel(true) ?? NSFontPanel.shared
        fontPanel = panel; panel.delegate = self; panel.isReleasedWhenClosed = false
        let form = textStyleForm ?? TextStyleForm(outlined: canvas.outlined, shadowed: canvas.shadowed)
        textStyleForm = form; panel.accessoryView = form
        form.onOutlineChange = { [weak self] value in
            guard let self, !self.terminationStarted else { return }
            self.canvas.outlined = value; self.canvas.applyTextEffectsToSelection(outline: value); self.syncFontPanelSelection()
        }
        form.onShadowChange = { [weak self] value in
            guard let self, !self.terminationStarted else { return }
            self.canvas.shadowed = value; self.canvas.applyTextEffectsToSelection(shadow: value); self.syncFontPanelSelection()
        }
        form.onDefaultRequested = { [weak self] in self?.defaultTextStyle() }
        let manager = NSFontManager.shared; manager.target = self; manager.action = #selector(changeFont(_:))
        syncFontPanelSelection()
        panel.orderFront(nil)
        // AppKit restores the shared panel's saved small frame when first shown.
        // Size the loaded panel, bounded to the usable display (the accessory scrolls
        // when constrained), then keep it centered on this screen.
        let content = NSRect(x: 0, y: 0, width: 940, height: 720)
        if let main = window, let usable = fontPanelVisibleFrameOverride?() ?? main.screen?.visibleFrame {
            panel.setFrame(TextStyleForm.fontPanelFrame(size: panel.frameRect(forContentRect: content).size,
                                                        visible: usable.insetBy(dx: 12, dy: 12), anchor: main.frame), display: true)
        } else { panel.setContentSize(content.size) }
        fontPanelOpeningLayoutApplied = TextStyleForm.prepareFontPanelLayout(panel)
        TextStyleForm.prepareFontPanel(panel)
        if window != nil { writeLayoutEvidence() }
        fontPanelRefreshTimer?.invalidate()
        fontPanelRecordedTypography = false
        fontPanelRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFontPanel() }
        }
    }
    func refreshFontPanel() {
        guard let panel = fontPanel, panel.isVisible else { fontPanelRefreshTimer?.invalidate(); return }
        // The modern shared panel creates its split views after Show. Retry the
        // opening layout until those native views are loaded, then never again for
        // this presentation: later refreshes must not fight a dragged divider.
        if !fontPanelOpeningLayoutApplied { fontPanelOpeningLayoutApplied = TextStyleForm.prepareFontPanelLayout(panel) }
        TextStyleForm.prepareFontPanel(panel)
        if window != nil, !fontPanelRecordedTypography {
            writeLayoutEvidence(); fontPanelRecordedTypography = true
        }
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { NSFontPanel.ModeMask(rawValue: 7) }
    func syncFontPanelSelection() {
        guard fontPanel != nil, !applyingFontChange else { return }
        let selected = canvas.selectedTextElements
        let first = selected.first
        let source = NSFont(name: first?.fontName ?? canvas.fontName, size: first?.fontSize ?? canvas.fontSize) ?? .boldSystemFont(ofSize: 24)
        // Original displayFontScale is output/logical height; editor zoom is a
        // view transform and must not change the point size in the Fonts panel.
        let scale = canvas.outputSize.height / canvas.canvasSize.height
        let displayed = NSFontManager.shared.convert(source, toSize: source.pointSize * scale)
        NSFontManager.shared.setSelectedFont(displayed, isMultiple: selected.count > 1)
        func uniform(_ values: [Bool], fallback: Bool) -> Bool? {
            guard let value = values.first else { return fallback }
            return values.allSatisfy { $0 == value } ? value : nil
        }
        textStyleForm?.setChoices(outlined: uniform(selected.map(\.outlined), fallback: canvas.outlined),
                                  shadowed: uniform(selected.map(\.shadowed), fallback: canvas.shadowed))
    }
    func changeFont(_ sender: NSFontManager?) {
        guard !terminationStarted, let panel = fontPanel, let form = textStyleForm else { return }
        let scale = canvas.outputSize.height / canvas.canvasSize.height
        let manager = NSFontManager.shared
        let convert: (NSFont) -> NSFont? = { source in
            let displayed = manager.convert(source, toSize: source.pointSize * scale)
            let changed = panel.convert(displayed)
            return manager.convert(changed, toSize: changed.pointSize / scale)
        }
        let first = canvas.selectedTextElements.first
        let source = NSFont(name: first?.fontName ?? canvas.fontName, size: first?.fontSize ?? canvas.fontSize) ?? .boldSystemFont(ofSize: 24)
        guard let future = convert(source), future.pointSize.isFinite, future.pointSize > 0, future.pointSize <= 4096,
              future.pointSize >= 18 || future.pointSize == source.pointSize else { return }
        applyingFontChange = true
        let valid = canvas.convertSelectedTextFonts(convert, outline: form.outlineChoice, shadow: form.shadowChoice)
        if valid {
            canvas.fontName = future.fontName; canvas.fontSize = future.pointSize
            if let value = form.outlineChoice { canvas.outlined = value }
            if let value = form.shadowChoice { canvas.shadowed = value }
        }
        applyingFontChange = false; syncFontPanelSelection(); fontPanelRecordedTypography = false
    }
    func closeFontPanel() {
        fontPanelRefreshTimer?.invalidate(); fontPanelRefreshTimer = nil
        fontPanel?.orderOut(nil); fontPanel?.delegate = nil; fontPanel?.accessoryView = nil
        if NSFontManager.shared.target === self { NSFontManager.shared.target = nil }
        fontPanel = nil; textStyleForm = nil; fontPanelOpeningLayoutApplied = false
    }
    @objc func defaultTextStyle() { guard !terminationStarted else { return }; canvas.restoreDefaultTextStyle(); syncFontPanelSelection() }
    @objc func toggleTextShadow() {
        let selected = canvas.selectedTextElements.first
        canvas.shadowed = !(selected?.shadowed ?? canvas.shadowed)
        canvas.applyTextEffectsToSelection(shadow: canvas.shadowed)
    }
    @objc func toggleOutline() {
        let selected = canvas.selectedTextElements.first
        canvas.outlined = !(selected?.outlined ?? canvas.outlined)
        canvas.applyTextEffectsToSelection(outline: canvas.outlined)
    }
    @objc func resize() {
        guard let session = makeResizeSession() else { return }
        ResizePanel(session: session).show(attachedTo: window)
    }
    @objc func normalSize() { canvas.setSnapToNormalSize(); updateStatus() }
    @objc func trimSnap() { canvas.trimSnapAtCurrentEdges(); updateStatus() }
    var activeTextEditor: NSTextView? {
        (window?.attachedSheet ?? NSApp.keyWindow ?? window)?.firstResponder as? NSTextView
    }
    var activeUndoManager: UndoManager { activeTextEditor?.undoManager ?? canvas.editingUndoManager }
    @objc func undo() {
        if let editor = activeTextEditor { editor.undoManager?.undo(); return }
        endWindowGesture(cancelled: true)
        canvas.undo()
    }
    @objc func redo() {
        if let editor = activeTextEditor { editor.undoManager?.redo(); return }
        endWindowGesture(cancelled: true)
        canvas.redo()
    }
    @objc func cut() { if let editor = activeTextEditor { editor.cut(nil) } else { canvas.copySelection(); canvas.deleteSelection() } }
    @objc func copyArtwork() { if let editor = activeTextEditor { editor.copy(nil) } else { canvas.copySelection() } }
    @objc func copyImage() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([canvas.renderedImage()]) }
    @objc func paste() { if let editor = activeTextEditor { editor.paste(nil) } else { canvas.paste() } }
    @objc func selectAll() { if let editor = activeTextEditor { editor.selectAll(nil) } else { canvas.selectAll() } }
    @objc func deleteSelection() { if let editor = activeTextEditor { editor.delete(nil) } else { canvas.deleteSelection() } }
    @objc func duplicate() { canvas.duplicateSelection() }; @objc func clear() { canvas.clearAnnotations() }; @objc func crop() { canvas.cropSelection() }
    @objc func wipe() { leaveFrame(); canvas.wipe() }
    @objc func wipeSnap() { leaveFrame(); canvas.wipeSnap() }
    @objc func rotateCW() { canvas.rotate(clockwise: true) }; @objc func rotateCCW() { canvas.rotate(clockwise: false) }
    @objc func flipH() { canvas.flip(horizontal: true) }; @objc func flipV() { canvas.flip(horizontal: false) }
    @objc func transparent() { canvas.setBackgroundColor(.clear) }; @objc func white() { canvas.setBackgroundColor(.white) }; @objc func flatten() { canvas.flatten() }
    @objc func front() { canvas.bringSelectionToFront() }; @objc func back() { canvas.sendSelectionToBack() }; @objc func group() { canvas.groupSelection() }; @objc func ungroup() { canvas.ungroupSelection() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "OpenSkitch", .credits: NSAttributedString(string: "Native 64-bit reconstruction for personal use. Feature parity with Skitch 1.0.12 is still in progress.")]) }
    func runSmokeTest() {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKITCH_EVIDENCE_DIR"] ?? NSTemporaryDirectory())
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let snapshot = try canvas.snapshotDocumentData()
            let expected = try CanvasView.validatedDocumentData(snapshot)
            try snapshot.write(to: dir.appendingPathComponent("smoke.skitchredux"))
            let nativeURL = dir.appendingPathComponent("smoke.skitch")
            try SkitchFile(document: expected, metadata: legacyMetadata, canvasData: snapshot).write(to: nativeURL)
            let reopened = try SkitchFile.read(nativeURL)
            guard reopened.document == expected, reopened.metadata == legacyMetadata else { throw NSError(domain: "Smoke", code: 2) }
            try canvas.loadDocument(data: reopened.canvasData)
            guard let png = canvas.imageData(format: "png"), !png.isEmpty else { throw NSError(domain: "Smoke", code: 1) }
            try png.write(to: dir.appendingPathComponent("smoke.png"))
            try JSONSerialization.data(withJSONObject: appearanceEvidence(), options: [.sortedKeys]).write(to: dir.appendingPathComponent("smoke-appearance.json"))
            try Data("native startup, original-format editable save/load, PNG export succeeded\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        } catch {
            try? Data("FAILED: \(error)\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        }
    }
    /// Clicks the real Preferences Relaunch button; tools/test-native-startup.py checks that a new process replaces this one.
    func runRelaunchSmoke() {
        showPreferences()
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            let tabbed = (view as? NSTabView)?.tabViewItems.compactMap(\.view) ?? []
            for child in view.subviews + tabbed { if let match = find(identifier, in: child) { return match } }
            return nil
        }
        dirty = false
        guard let form = preferencesForm, let relaunch = find("appearanceRelaunch", in: form) as? NSButton else {
            let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKITCH_EVIDENCE_DIR"] ?? NSTemporaryDirectory())
            try? Data("FAILED: Preferences has no Relaunch button\n".utf8).write(to: dir.appendingPathComponent("relaunch-smoke-result.txt"))
            NSApp.terminate(nil); return
        }
        relaunch.performClick(nil)
    }
    func writeLayoutEvidence() {
        let folder = ProcessInfo.processInfo.environment["SKITCH_EVIDENCE_DIR"] ?? support.path
        window.contentView?.layoutSubtreeIfNeeded()
        let rect = window.convertToScreen(canvas.convert(canvas.visibleRect, to: nil))
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        var evidence: [String: Any] = ["windowFrame": NSStringFromRect(window.frame), "canvasScreenRect": NSStringFromRect(rect), "canvasInputTopLeft": [rect.minX,top-rect.maxY], "screenFrame": NSStringFromRect(NSScreen.screens.first?.frame ?? .zero), "nativeBackingScale":window.backingScaleFactor, "nameFontSize":nameField.font?.pointSize ?? 0,"statusFontSize":status.font?.pointSize ?? 0]
        evidence["shell"] = ["visible": window.isVisible, "miniaturized": window.isMiniaturized,
                             "statusMenu": UserDefaults.standard.integer(forKey: "statusMenu"), "menuIconInstalled": statusItem != nil]
        evidence["dragThumbnail"] = ["present": dragThumbnailWindow != nil,
                                     "frame": NSStringFromRect(dragThumbnailWindow?.frame ?? .zero),
                                     "clickToExpand": (dragThumbnailWindow?.contentView as? DragThumbnailView)?.clickToExpand ?? false,
                                     "dragging": activeDragID != nil]
        evidence["windowZoom"] = ["active": windowZoom != nil, "frame": windowZoom?.lastRenderedFrame ?? 0,
                                  "frames": windowZoom?.frameCount ?? 0,
                                  "restoring": windowZoom?.direction == .restore]
        evidence["visibilityZoomOrigin"] = NSStringFromRect(visibilityZoomOrigin ?? .zero)
        evidence["appearance"] = ["style": Appearance.current.rawValue, "modernChrome": modernChrome != nil]
        evidence["toolButtons"] = SketchTool.allCases.compactMap { tool -> [String: Any]? in
            guard let button = toolButtons[tool] else { return nil }
            return ["tool": tool.rawValue, "fontSize": button.font?.pointSize ?? 0,
                    "frame": NSStringFromRect(button.frame), "selected": button.state == .on]
        }
        if let content = window.contentView {
            var controls: [[String: Any]] = []
            func inspect(_ view: NSView) {
                guard view !== canvas else { return }
                if let control = view as? NSControl, control is NSButton || control is NSTextField || control is BezelSizeSlider {
                    let rect = control.convert(control.bounds, to: content)
                    var clipped = rect.intersection(content.bounds)
                    var ancestor = control.superview
                    while let parent = ancestor {
                        if parent is NSClipView { clipped = clipped.intersection(parent.convert(parent.bounds, to: content)) }
                        ancestor = parent.superview
                    }
                    controls.append(["label": control.accessibilityLabel() ?? (control as? NSButton)?.title ?? (control as? NSTextField)?.stringValue ?? "",
                                     "fontSize": control.font?.pointSize ?? 0, "frame": NSStringFromRect(rect),
                                     "visibleFrame": NSStringFromRect(clipped), "hidden": control.isHiddenOrHasHiddenAncestor,
                                     "parentIsButton": control.superview is NSButton])
                }
                for child in view.subviews { inspect(child) }
            }
            inspect(content)
            evidence["bezelControls"] = controls
            let chosen = SketchColor(canvas.strokeColor), custom = SketchColor(OriginalDrawingControls.drawingColor(from: customDrawingColor) ?? .black)
            evidence["drawingControls"] = ["size": widthControl.doubleValue, "fontSize": canvas.fontSize,
                                           "colorRGBA": [chosen.red,chosen.green,chosen.blue,chosen.alpha],
                                           "customRGBA": [custom.red,custom.green,custom.blue,custom.alpha],
                                           "popoverShown": colorPopover?.isShown ?? false, "sizeUndoGrouping": sizeUndoGrouping,
                                           "hoverOpened": colorOpenedByHover, "controlHovered": colorControlHovered, "paletteHovered": colorPaletteHovered]
            evidence["bezelLayout"] = ["contentSize": NSStringFromSize(content.bounds.size), "minimumWindowSize": NSStringFromSize(window.minSize),
                                       "recoveredArtwork": (content as? FrameChromeView)?.usesRecoveredBezel ?? false]
            if let header = (modernChrome ?? content).subviews.first(where: { $0.identifier?.rawValue == "OpenSkitchHeader" }),
               let brand = header.subviews.first(where: { $0.identifier?.rawValue == "OpenSkitchBrand" }) {
                let frame = brand.convert(brand.bounds, to: content)
                evidence["bezelHeader"] = ["brandFrame": NSStringFromRect(frame), "windowCenterX": content.bounds.midX,
                                           "brandCenterOffset": frame.midX - content.bounds.midX,
                                           "commandFrames": header.subviews.filter { $0 !== brand }.map { NSStringFromRect($0.convert($0.bounds, to: content)) }]
            }
        }
        let printInfo = NSPrintInfo.shared
        evidence["printInfo"] = ["paperSize": NSStringFromSize(printInfo.paperSize),
                                "orientation": printInfo.orientation == .portrait ? "portrait" : "landscape",
                                "margins": [printInfo.leftMargin, printInfo.rightMargin, printInfo.topMargin, printInfo.bottomMargin]]
        if let panel = fontPanel {
            evidence["fontPanel"] = ["frame": NSStringFromRect(panel.frame), "visible": panel.isVisible, "windowNumber": panel.windowNumber,
                                     "key": panel.isKeyWindow, "modeMask": validModesForFontPanel(panel).rawValue,
                                     "typography": TextStyleForm.fontPanelTypographyEvidence(panel),
                                     "layout": TextStyleForm.fontPanelLayoutEvidence(panel)]
        }
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: .prettyPrinted) { try? data.write(to: URL(fileURLWithPath:folder).appendingPathComponent("layout.json"), options:.atomic) }
    }
}

/// Starts the fresh instance for Relaunch. The caller is quitting, and a process that exits before LaunchServices
/// accepts the request can take it along, so this returns only once the request is acknowledged or `timeout` passes.
enum RelaunchLauncher {
    typealias Completion = @Sendable (NSRunningApplication?, Error?) -> Void
    typealias Opener = (URL, NSWorkspace.OpenConfiguration, @escaping Completion) -> Void
    private final class Acknowledgement: @unchecked Sendable {
        let signal = DispatchSemaphore(value: 0)
        var error: Error?
    }
    static let launchServices: Opener = { url, configuration, completion in
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
    }
    /// Only where the new instance keeps its data and evidence survives a relaunch. SKITCH_APPEARANCE would override the
    /// choice just made in Preferences, which is the whole reason to relaunch, and SKITCH_FIXTURE would reopen the fixture
    /// over the recovered drawing.
    static let inheritedKeys: Set<String> = ["SKITCH_APP_SUPPORT", "SKITCH_EVIDENCE_DIR"]
    static func inheritedEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { inheritedKeys.contains($0.key) }
    }
    @MainActor
    @discardableResult
    static func launch(_ url: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                       timeout: TimeInterval = 5, open: Opener = launchServices) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = inheritedEnvironment(environment)
        let acknowledgement = Acknowledgement()
        open(url, configuration) { _, error in acknowledgement.error = error; acknowledgement.signal.signal() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        // Waiting in short slices while draining the main run loop also covers a completion delivered on the main queue.
        while acknowledgement.signal.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
            guard Date() < deadline else { return false }
            RunLoop.current.run(mode: .default, before: Date())
        }
        return acknowledgement.error == nil
    }
}

@main
@MainActor
enum OpenSkitchMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        delegate.relaunchRequest = { url in
            if !RelaunchLauncher.launch(url) { NSLog("OpenSkitch could not start the relaunched instance at %@", url.path) }
        }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
