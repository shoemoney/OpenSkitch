import AppKit
import UniformTypeIdentifiers

/// Frame preview clears only the canvas hole; application controls keep an
/// opaque backdrop so their adaptive label colors remain readable.
final class FrameChromeView: NSView {
    weak var canvasScrollView: NSScrollView?
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
    }
    override func layout() { super.layout(); if showsCanvasHole { needsDisplay = true } }
}

final class DragExportView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var export: (() -> Data?)?
    var fileName: (() -> String)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        let title = "Drag Me"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.labelColor]
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
    override func mouseDragged(with event: NSEvent) {
        guard export?() != nil else { return }
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "photo", accessibilityDescription: "Export image"))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { (fileName?() ?? "Skitch") + ".png" }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do { guard let data = export?() else { throw NSError(domain: "SkitchRedux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to render the image."]) }; try data.write(to: url, options: .atomic); completionHandler(nil) } catch { completionHandler(error) }
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let capture = CaptureCoordinator()
    let publishing = PublishingCoordinator()
    let hotkeys = GlobalHotkeyManager()
    let photoBrowser = PhotoBrowserCoordinator()
    let nameField = NSTextField(string: "Untitled")
    let status = NSTextField(labelWithString: "")
    let colorWell = NSColorWell()
    let widthControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let zoomControl = NSPopUpButton(frame: .zero, pullsDown: false)
    var toolButtons: [SketchTool: NSButton] = [:]
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
    var historyWindow: NSWindow?
    var snapButton: NSButton!
    var frameButton: NSButton!
    var cancelFrameButton: NSButton!
    var frameMode = false
    var frameKeepsAnnotations = false
    var frameCaptureInProgress = false
    var activeFrameScreenSize: NSSize?
    var frameWindowWasOpaque = true
    var frameWindowBackground: NSColor?
    var frameScrollDrewBackground = true
    var frameTitlebarBackdrop: FrameChromeView?
    let support: URL = {
        if let isolated = ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] { return URL(fileURLWithPath: isolated, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SkitchRedux", isDirectory: true)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus(); buildWindow()
        NSColorPanel.shared.showsAlpha = true
        canvas.onChange = { [weak self] in self?.changed() }
        canvas.onOpenDocument = { [weak self] url in self?.openURL(url) }
        canvas.onToolChange = { [weak self] tool in
            guard let self else { return }
            for (choice, button) in self.toolButtons { button.state = choice == tool ? .on : .off }
            self.updateStatus()
        }
        canvas.onColorChange = { [weak self] color in self?.colorWell.color = color }
        try? FileManager.default.createDirectory(at: support.appendingPathComponent("History"), withIntermediateDirectories: true)
        let nativeRecovery = support.appendingPathComponent("Recovery.skitch")
        let recovery = FileManager.default.fileExists(atPath: nativeRecovery.path) ? nativeRecovery : support.appendingPathComponent("Recovery.skitchredux")
        if let data = try? Data(contentsOf: recovery) {
            do { let restored = try SkitchFile.decode(data); restoring = true; try canvas.loadDocument(data: restored.canvasData); legacyMetadata = restored.metadata; restoring = false; dirty = true; window.isDocumentEdited = true; nameField.stringValue = "Recovered drawing" }
            catch { restoring = false; status.stringValue = "Previous session could not be restored." }
        }
        if let fixture = ProcessInfo.processInfo.environment["SKITCH_FIXTURE"] { openURL(URL(fileURLWithPath: fixture)) }
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.saveRecovery() } }
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); NSApp.activate(ignoringOtherApps: true)
        do {
            try hotkeys.install(globalScreen: { [weak self] in self?.screenSnap() }, globalWindow: { [weak self] in self?.windowSnap() }, globalFullscreen: { [weak self] in self?.fullscreenSnap() }, globalFrame: { [weak self] in self?.frameSnap() }, globalCamera: { [weak self] in self?.cameraSnap() })
        } catch { status.stringValue = "Global shortcuts unavailable: " + error.localizedDescription }
        writeLayoutEvidence()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.runSmokeTest() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationStarted { return shutdownPending.isEmpty ? .terminateNow : .terminateLater }
        saveRecovery()
        guard allowDiscard(discardingForTermination: true) else { return .terminateCancel }
        terminationStarted = true; decidingTermination = true
        shutdownPending = ["capture", "publishing", "photos"]; shutdownError = nil
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
        terminationStarted = false
        if discardedForTermination { dirty = true; window.isDocumentEdited = true }
        discardedForTermination = false; saveRecovery(); updateStatus()
        // Reply to AppKit before presenting an error about incomplete cleanup.
        DispatchQueue.main.async { [weak self] in self?.error(failure) }
        return false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        // The editor owns this single-document session. A History window must
        // not keep a discarded editor alive with termination-only state.
        NSApp.terminate(nil)
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if discardedForTermination { removeRecovery() }
        else { saveRecovery(finalizingTermination: true) }
        timer?.invalidate(); try? hotkeys.unregister()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { openURL(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func label(_ text: String) -> NSTextField { let f = NSTextField(labelWithString: text); f.font = .systemFont(ofSize: 18); return f }
    func button(_ title: String, _ action: Selector) -> NSButton { let b = NSButton(title: title, target: self, action: action); b.font = .systemFont(ofSize: 18); return b }
    func stack(_ views: [NSView], horizontal: Bool = false) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = horizontal ? .horizontal : .vertical; s.spacing = 12; s.alignment = horizontal ? .centerY : .leading; return s
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Skitch Redux"; window.delegate = self; window.minSize = NSSize(width: 1040, height: 740)
        window.contentView = FrameChromeView(frame: window.contentView?.bounds ?? .zero)
        guard let content = window.contentView else { return }
        snapButton = button("Screen Snap", #selector(screenSnap))
        frameButton = button("Frame", #selector(frameSnap))
        cancelFrameButton = button("Cancel Frame", #selector(cancelFrame)); cancelFrameButton.isHidden = true
        let top = stack([snapButton, frameButton, cancelFrameButton, button("Full Screen", #selector(fullscreenSnap)), button("Window", #selector(windowSnap)), button("Camera", #selector(cameraSnap)), button("Web Snap", #selector(webSnap)), button("Open…", #selector(openFile)), button("History", #selector(showHistory))], horizontal: true)
        top.distribution = .fillProportionally
        var sidebarViews: [NSView] = [label("Tools")]
        for tool in SketchTool.allCases {
            let b = button(tool.rawValue.capitalized, #selector(chooseTool(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(tool.rawValue); b.setButtonType(.toggle)
            let assets: [String: String] = ["select":"Cursor", "arrow":"Arrow", "line":"Line", "rectangle":"Rect", "ellipse":"Circle", "brush":"Brush", "text":"Text", "fill":"Fill", "eraser":"Eraser"]
            if let asset = assets[tool.rawValue], let url = Bundle.main.url(forResource: "ToolOff"+asset, withExtension: "png"), let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 30, height: 30); b.image = image; b.imagePosition = .imageLeading
            }
            b.alignment = .left; b.widthAnchor.constraint(equalToConstant: 172).isActive = true; b.heightAnchor.constraint(equalToConstant: 38).isActive = true
            sidebarViews.append(b); toolButtons[tool] = b
        }
        colorWell.color = .systemRed; colorWell.target = self; colorWell.action = #selector(changeColor(_:)); colorWell.heightAnchor.constraint(equalToConstant: 38).isActive = true; colorWell.widthAnchor.constraint(equalToConstant: 172).isActive = true
        widthControl.addItems(withTitles: ["Thin · 2", "Medium · 5", "Bold · 10", "Heavy · 20", "Wide · 40"]); widthControl.selectItem(at: 1); widthControl.font = .systemFont(ofSize: 18); widthControl.target = self; widthControl.action = #selector(changeWidth(_:))
        let fill = NSButton(checkboxWithTitle: "Filled shapes", target: self, action: #selector(toggleFill(_:))); fill.font = .systemFont(ofSize: 18)
        let shadow = NSButton(checkboxWithTitle: "Shadow", target: self, action: #selector(toggleShadow(_:))); shadow.font = .systemFont(ofSize: 18); shadow.state = canvas.shadowed ? .on : .off
        sidebarViews += [label("Color"), colorWell, label("Stroke"), widthControl, fill, shadow]
        let sidebar = stack(sidebarViews); sidebar.spacing = 5
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = sidebar; sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: sidebarScroll.contentView.leadingAnchor, constant: 4), sidebar.topAnchor.constraint(equalTo: sidebarScroll.contentView.topAnchor, constant: 4), sidebar.widthAnchor.constraint(equalToConstant: 182)])
        let scroll = NSScrollView(); scroll.documentView = canvas; scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.backgroundColor = .windowBackgroundColor
        (content as? FrameChromeView)?.canvasScrollView = scroll
        nameField.font = .systemFont(ofSize: 20); nameField.placeholderString = "Image name"; nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        zoomControl.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"]); for (index,item) in zoomControl.itemArray.enumerated() { item.representedObject = [0.25,0.5,0.75,1,1.5,2][index] }; zoomControl.selectItem(withTitle: "100%"); zoomControl.font = .systemFont(ofSize: 18); zoomControl.target = self; zoomControl.action = #selector(changeZoom(_:))
        let drag = DragExportView(); drag.widthAnchor.constraint(equalToConstant: 115).isActive = true; drag.heightAnchor.constraint(equalToConstant: 50).isActive = true
        drag.export = { [weak self] in self?.canvas.imageData(format: "png") }; drag.fileName = { [weak self] in self?.safeName() ?? "Skitch" }
        let bottom = stack([nameField, zoomControl, button("Resize…", #selector(resize)), button("Export…", #selector(exportFile)), button("Share…", #selector(share(_:))), drag], horizontal: true)
        status.font = .systemFont(ofSize: 18); status.lineBreakMode = .byTruncatingTail
        for v in [top, sidebarScroll, scroll, bottom, status] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 14), top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), top.heightAnchor.constraint(equalToConstant: 42),
            sidebarScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), sidebarScroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14), sidebarScroll.widthAnchor.constraint(equalToConstant: 196), sidebarScroll.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -12),
            scroll.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), scroll.topAnchor.constraint(equalTo: sidebarScroll.topAnchor), scroll.bottomAnchor.constraint(equalTo: sidebarScroll.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), bottom.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8), bottom.heightAnchor.constraint(equalToConstant: 52),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        canvas.strokeColor = colorWell.color; canvas.strokeWidth = 5
        canvas.strokeSmoothing = StrokeSmoothing(rawValue: UserDefaults.standard.string(forKey: "PencilSmoothing") ?? "medium") ?? .medium
        setTool(.arrow)
    }
    func menu(_ title: String, items: [(String, Selector?, String)]) -> NSMenu {
        let m = NSMenu(title: title); m.font = .systemFont(ofSize: 20)
        for (name, action, key) in items { if name == "-" { m.addItem(.separator()); continue }; let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self; m.addItem(item) }; return m
    }
    func buildMenus() {
        let bar = NSMenu()
        let appMenu = menu("Skitch Redux", items: [("About Skitch Redux", #selector(about), ""), ("Sharing Settings…", #selector(sharingSettings), ","), ("Capture Shortcuts…", #selector(shortcutSettings), ""), ("-", nil, ""), ("Quit Skitch Redux", #selector(quit), "q")])
        let file = menu("File", items: [("New Blank", #selector(newFile), "n"), ("Open…", #selector(openFile), "o"), ("Photos…", #selector(showPhotos), ""), ("Save Editable Document", #selector(saveFile), "s"), ("Save As…", #selector(saveAs), "S"), ("Save to History", #selector(saveHistory), ""), ("History", #selector(showHistory), ""), ("Export…", #selector(exportFile), "e"), ("Publish Image…", #selector(publishImage), ""), ("Print…", #selector(printImage), "p")])
        let edit = menu("Edit", items: [("Undo", #selector(undo), "z"), ("Redo", #selector(redo), "Z"), ("-", nil, ""), ("Cut", #selector(cut), "x"), ("Copy", #selector(copyArtwork), "c"), ("Copy Image", #selector(copyImage), ""), ("Paste", #selector(paste), "v"), ("Delete", #selector(deleteSelection), ""), ("Select All", #selector(selectAll), "a"), ("Duplicate", #selector(duplicate), "d"), ("Wipe", #selector(wipe), ""), ("Wipe Snap Only", #selector(wipeSnap), ""), ("Clear Annotations", #selector(clear), "")])
        let image = menu("Image", items: [("Resize…", #selector(resize), ""), ("Crop Selection", #selector(crop), ""), ("Rotate Clockwise", #selector(rotateCW), ""), ("Rotate Counterclockwise", #selector(rotateCCW), ""), ("Flip Horizontal", #selector(flipH), ""), ("Flip Vertical", #selector(flipV), ""), ("Transparent Background", #selector(transparent), ""), ("White Background", #selector(white), ""), ("Flatten", #selector(flatten), ""), ("Bring to Front", #selector(front), ""), ("Send to Back", #selector(back), ""), ("Group", #selector(group), ""), ("Ungroup", #selector(ungroup), "")])
        let text = menu("Text", items: [("Font…", #selector(chooseFont), ""), ("Toggle Text Outline", #selector(toggleOutline), "")])
        let snap = menu("Capture", items: [("Crosshair Snapshot", #selector(screenSnap), "1"), ("Fullscreen Snapshot", #selector(fullscreenSnap), "2"), ("Window Snapshot", #selector(windowSnap), "3"), ("Frame Snapshot", #selector(frameSnap), "4"), ("Re-snap (Keep Pen)", #selector(resnap), ""), ("Cancel Frame", #selector(cancelFrame), ""), ("Timed Snapshot…", #selector(timedSnap), ""), ("Camera Snapshot…", #selector(cameraSnap), ""), ("Snap from Link…", #selector(webSnap), "")])
        let drawing = menu("Drawing", items: [])
        let smoothing = menu("Pencil Smoothing", items: [])
        for mode in [StrokeSmoothing.precise, .medium, .loose] {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(changeSmoothing(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self; smoothing.addItem(item)
        }
        let smoothingItem = NSMenuItem(title: "Pencil Smoothing", action: nil, keyEquivalent: "")
        smoothingItem.submenu = smoothing; drawing.addItem(smoothingItem)
        for m in [appMenu, file, edit, image, drawing, text, snap] { let i = NSMenuItem(); i.submenu = m; bar.addItem(i) }; NSApp.mainMenu = bar
    }
    @objc func changeSmoothing(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = StrokeSmoothing(rawValue: raw) else { return }
        canvas.strokeSmoothing = mode; UserDefaults.standard.set(mode.rawValue, forKey: "PencilSmoothing")
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(changeSmoothing(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == canvas.strokeSmoothing.rawValue ? .on : .off
        }
        if menuItem.action == #selector(undo) { return activeUndoManager.canUndo }
        if menuItem.action == #selector(redo) { return activeUndoManager.canRedo }
        return true
    }
    func setTool(_ tool: SketchTool) { canvas.tool = tool; for (t,b) in toolButtons { b.state = t == tool ? .on : .off }; window?.makeFirstResponder(canvas); updateStatus() }
    @objc func chooseTool(_ sender: NSButton) { if let s = sender.identifier?.rawValue, let t = SketchTool(rawValue: s) { setTool(t) } }
    @objc func changeColor(_ sender: NSColorWell) { applyChosenColor(sender.color, modifiers: NSApp.currentEvent?.modifierFlags ?? []) }
    func applyChosenColor(_ color: NSColor, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            canvas.setBackgroundColor(color); colorWell.color = canvas.strokeColor
        } else {
            canvas.strokeColor = color; canvas.applyStyleToSelection()
        }
    }
    @objc func changeWidth(_ sender: NSPopUpButton) { let widths: [CGFloat] = [2,5,10,20,40]; canvas.strokeWidth = widths[sender.indexOfSelectedItem]; canvas.applyStyleToSelection() }
    @objc func toggleFill(_ sender: NSButton) { canvas.filled = sender.state == .on; canvas.applyStyleToSelection() }
    @objc func toggleShadow(_ sender: NSButton) { canvas.shadowed = sender.state == .on; canvas.applyStyleToSelection() }
    @objc func changeZoom(_ sender: NSPopUpButton) {
        guard let scale = sender.selectedItem?.representedObject as? Double else { return }
        canvas.setZoom(CGFloat(scale)); updateStatus()
    }
    func fitCanvasToWindow() {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let scroll = canvas.enclosingScrollView else { return }
        let viewport = scroll.contentView.bounds.size, size = canvas.canvasSize
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
    func changed() { if !restoring { dirty = true }; window?.isDocumentEdited = dirty; updateStatus() }
    func updateStatus() { let s = canvas.canvasSize; status.stringValue = "\(Int(s.width)) × \(Int(s.height)) · \(canvas.tool.rawValue.capitalized) · \(dirty ? "Unsaved changes" : "Saved")" }
    func safeName() -> String { let s = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return (s.isEmpty ? "Skitch" : s).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
    func error(_ error: Error) { let a = NSAlert(error: error); a.runModal() }
    func allowDiscard(discardingForTermination: Bool = false) -> Bool {
        if discardedForTermination { return true }
        guard dirty || canvas.hasPendingTextChanges else { return true }
        let a = NSAlert(); a.messageText = "Save your drawing?"; a.informativeText = "This document has changes that have not been saved."; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Discard")
        let result = a.runModal()
        if result == .alertFirstButtonReturn { return save() }
        if result == .alertThirdButtonReturn {
            if discardingForTermination { discardedForTermination = true; dirty = false }
            return true
        }
        return false
    }
    @objc func newFile() { guard !terminationStarted, allowDiscard() else { return }; leaveFrame(); canvas.newBlank(size: NSSize(width: 1000,height: 700)); documentGeneration = UUID(); legacyMetadata = .init(); fitCanvasToWindow(); canvas.editingUndoManager.removeAllActions(); currentURL = nil; nameField.stringValue = "Untitled"; dirty = false; window.isDocumentEdited = false; updateStatus() }
    @objc func openFile() { let p = NSOpenPanel(); p.allowedContentTypes = [.image, .pdf, .data]; p.allowsMultipleSelection = false; if p.runModal() == .OK, let u = p.url { openURL(u) } }
    func openURL(_ url: URL) {
        guard !terminationStarted else { return }
        guard allowDiscard() else { return }
        do {
            if ["skitchredux", "skitch"].contains(url.pathExtension.lowercased()) {
                let file = try SkitchFile.read(url)
                try canvas.loadDocument(data: file.canvasData); legacyMetadata = file.metadata
                // Bundled samples stay intact; ordinary drawings save in place.
                currentURL = url.path.contains(".app/Contents/Resources/") ? nil : url
            }
            else { guard let image = NSImage(contentsOf: url) else { throw NSError(domain: "SkitchRedux", code: 3, userInfo: [NSLocalizedDescriptionKey: "The file could not be read as an image."]) }; var proposed = CGRect(origin: .zero, size: image.size)
                guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                    throw NSError(domain: "SkitchRedux", code: 5, userInfo: [NSLocalizedDescriptionKey: "This image is too large or cannot be decoded safely."])
                }
                canvas.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); canvas.setBackground(image); legacyMetadata = .init(); currentURL = nil }
            documentGeneration = UUID(); leaveFrame(); canvas.editingUndoManager.removeAllActions(); fitCanvasToWindow(); nameField.stringValue = url.deletingPathExtension().lastPathComponent; dirty = false; window.isDocumentEdited = false; updateStatus()
        } catch { self.error(error) }
    }
    func save(forceChoose: Bool = false) -> Bool {
        var url = forceChoose ? nil : currentURL
        if url == nil { let p = NSSavePanel(); p.nameFieldStringValue = safeName()+".skitch"; p.allowedContentTypes = [UTType(filenameExtension: "skitch") ?? .data, UTType(filenameExtension: "skitchredux") ?? .data]; if p.runModal() != .OK { return false }; url = p.url }
        do { guard let url else { return false }; let snapshot = try canvas.snapshotDocumentData(); let document = try CanvasView.validatedDocumentData(snapshot); try SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot).write(to: url); canvas.commitPendingTextEditing(); currentURL = url; dirty = false; window.isDocumentEdited = false; updateStatus(); return true } catch { self.error(error); return false }
    }
    @objc func saveFile() { _ = save() }
    @objc func saveAs() { _ = save(forceChoose: true) }
    func saveRecovery(finalizingTermination: Bool = false) {
        // Queued timer work must not interpret the temporary Discard dirty flag
        // as permission to delete recovery before backend cleanup succeeds.
        guard !terminationStarted || finalizingTermination else { return }
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
    @objc func saveHistory() {
        do { let dir = support.appendingPathComponent("History"); let stem = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))-\(safeName())"; let snapshot = try canvas.snapshotDocumentData(); let document = try CanvasView.validatedDocumentData(snapshot); try SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot).write(to: dir.appendingPathComponent(stem+".skitch")); if let data = canvas.imageData(format: "png") { try data.write(to: dir.appendingPathComponent(stem+".png"), options: .atomic) }; status.stringValue = "Saved to History" } catch { self.error(error) }
    }
    @objc func showHistory() {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: support.appendingPathComponent("History"), includingPropertiesForKeys: nil)) ?? []).filter { ["skitch", "skitchredux"].contains($0.pathExtension) }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        let list = NSStackView(); list.orientation = .vertical; list.spacing = 12; list.alignment = .leading
        if urls.isEmpty { list.addArrangedSubview(label("Your saved images will appear here.")) }
        for (index,url) in urls.enumerated() {
            let preview = NSImageView(); preview.image = NSImage(contentsOf: url.deletingPathExtension().appendingPathExtension("png")); preview.imageScaling = .scaleProportionallyUpOrDown; preview.widthAnchor.constraint(equalToConstant: 160).isActive = true; preview.heightAnchor.constraint(equalToConstant: 100).isActive = true
            let b = button(url.deletingPathExtension().lastPathComponent, #selector(openHistory(_:))); b.tag = index; b.identifier = NSUserInterfaceItemIdentifier(url.path); b.lineBreakMode = .byTruncatingMiddle
            list.addArrangedSubview(stack([preview,b], horizontal: true))
        }
        let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 800,height: 620), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false); w.title = "Skitch History"; w.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: w.contentView!.bounds); scroll.autoresizingMask = [.width,.height]; scroll.hasVerticalScroller = true; scroll.documentView = list; list.frame = NSRect(x: 20,y: 0,width: 740,height: max(120,CGFloat(urls.count)*112)); w.contentView!.addSubview(scroll); historyWindow = w; w.center(); w.makeKeyAndOrderFront(nil)
    }
    @objc func openHistory(_ sender: NSButton) { if let path = sender.identifier?.rawValue { openURL(URL(fileURLWithPath: path)); window.makeKeyAndOrderFront(nil) } }
    @objc func showPhotos() {
        photoBrowser.show(relativeTo: window) { [weak self] url in self?.openURL(url) }
    }
    @objc func exportFile() {
        let p = NSSavePanel(); p.nameFieldStringValue = safeName()+".png"; p.allowedContentTypes = [.png,.jpeg,.tiff,.pdf,.bmp,.svg, UTType(filenameExtension: "skitch") ?? .data]; p.allowsOtherFileTypes = false
        if p.runModal() == .OK, let url = p.url { do { let data: Data; if ["svg", "skitch"].contains(url.pathExtension.lowercased()) { let snapshot = try canvas.snapshotDocumentData(); let document = try CanvasView.validatedDocumentData(snapshot); data = try SkitchFile(document: document, metadata: legacyMetadata, canvasData: snapshot).encoded(includeSupplementalState: url.pathExtension.lowercased() == "skitch") } else { guard let encoded = canvas.imageData(format: url.pathExtension.lowercased()) else { throw NSError(domain: "SkitchRedux", code: 4, userInfo: [NSLocalizedDescriptionKey: "That export format could not be encoded."]) }; data = encoded }; try data.write(to: url, options: .atomic); status.stringValue = "Exported \(url.lastPathComponent)" } catch { self.error(error) } }
    }
    @objc func printImage() { let view = NSImageView(frame: NSRect(origin: .zero,size: canvas.canvasSize)); view.image = canvas.renderedImage(); view.imageScaling = .scaleProportionallyUpOrDown; let p = NSPrintInfo.shared.copy() as! NSPrintInfo; p.horizontalPagination = .fit; p.verticalPagination = .fit; NSPrintOperation(view: view, printInfo: p).run() }
    @objc func share(_ sender: NSButton) { let picker = NSSharingServicePicker(items: [canvas.renderedImage()]); picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY) }
    @objc func shortcutSettings() { hotkeys.showSettings(attachedTo: window) }
    @objc func sharingSettings() { publishing.showSettings(relativeTo: window) }
    @objc func publishImage() {
        guard let data = canvas.imageData(format: "png") else { return }
        status.stringValue = "Publishing image…"
        publishing.publish(data: data, fileName: safeName()+"-"+UUID().uuidString.lowercased()+".png", presenting: window) { [weak self] result in
            Task { @MainActor in self?.receivePublishing(result) }
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
    func startCapture(_ mode: String, delay: Double = 0) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        leaveFrame()
        let generation = documentGeneration
        capture.capture(mode: mode, delay: delay) { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation)
        }
    }
    func receiveCapture(_ result: Result<NSImage,Error>, discardAlreadyApproved: Bool = false, expectedGeneration: UUID? = nil) {
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
            canvas.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); canvas.setBackground(image); documentGeneration = UUID(); legacyMetadata = .init(); canvas.editingUndoManager.removeAllActions(); currentURL = nil; fitCanvasToWindow(); nameField.stringValue = "Screenshot"; dirty = true; window.makeKeyAndOrderFront(nil); updateStatus()
        case .failure(let error): if (error as NSError).code != NSUserCancelledError { self.error(error) } }
    }
    @objc func screenSnap() {
        if frameMode { performFrameSnap(); return }
        startCapture("crosshair")
    }
    @objc func fullscreenSnap() { startCapture("fullscreen") }
    @objc func windowSnap() { startCapture("window") }
    @objc func frameSnap() {
        enterFrame(keepingAnnotations: false)
    }
    @objc func resnap() {
        enterFrame(keepingAnnotations: true)
    }
    func enterFrame(keepingAnnotations: Bool) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        canvas.commitPendingTextEditing()
        if !frameMode {
            frameWindowWasOpaque = window.isOpaque
            frameWindowBackground = window.backgroundColor
            frameScrollDrewBackground = canvas.enclosingScrollView?.drawsBackground ?? true
        }
        frameMode = true; frameKeepsAnnotations = keepingAnnotations
        window.isOpaque = false; window.backgroundColor = .clear
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
        snapButton.title = "Snap Frame"; frameButton.isHidden = true; cancelFrameButton.isHidden = false
        status.stringValue = keepingAnnotations ? "Frame preview · Snap Frame replaces the picture and keeps your drawing" : "Frame preview · Position the window, then choose Snap Frame"
    }
    @objc func cancelFrame() {
        guard !frameCaptureInProgress else { return }
        leaveFrame()
    }
    func leaveFrame() {
        guard frameMode else { return }
        frameMode = false; frameKeepsAnnotations = false
        frameTitlebarBackdrop?.removeFromSuperview(); frameTitlebarBackdrop = nil
        canvas.framePreview = false
        (window.contentView as? FrameChromeView)?.showsCanvasHole = false
        window.isOpaque = frameWindowWasOpaque
        window.backgroundColor = frameWindowBackground
        canvas.enclosingScrollView?.drawsBackground = frameScrollDrewBackground
        snapButton.title = "Screen Snap"; frameButton.isHidden = false; cancelFrameButton.isHidden = true
        updateStatus()
    }
    func performFrameSnap() {
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
        capture.capture(mode: "frame") { [weak self] result in
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
    @objc func timedSnap() { if let s = prompt("Timed Snapshot", text: "Delay in seconds", value: "5"), let d = Double(s), d >= 0, d <= 120 { startCapture("crosshair", delay: d) } }
    @objc func cameraSnap() {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        let generation = documentGeneration
        capture.captureCamera { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation)
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
        let alert = NSAlert(); alert.messageText = "Text Font"
        let family = NSComboBox(); family.addItems(withObjectValues: NSFontManager.shared.availableFontFamilies.sorted()); family.stringValue = NSFont(name: canvas.fontName, size: canvas.fontSize)?.familyName ?? canvas.fontName; family.font = .systemFont(ofSize: 20)
        let size = NSTextField(string: String(Int(canvas.fontSize))); size.font = .systemFont(ofSize: 20)
        let form = stack([label("Font family"), family, label("Size in pixels"), size]); form.frame = NSRect(x: 0, y: 0, width: 380, height: 156); family.widthAnchor.constraint(equalToConstant: 370).isActive = true
        alert.accessoryView = form; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let pixels = Double(size.stringValue), pixels.isFinite, pixels >= 18, pixels <= 4096, let font = NSFontManager.shared.font(withFamily: family.stringValue, traits: [], weight: 5, size: pixels) else { return }
        canvas.fontName = font.fontName; canvas.fontSize = pixels; canvas.applyTextStyleToSelection(); window.makeFirstResponder(canvas)
    }
    @objc func toggleOutline() { canvas.outlined.toggle(); canvas.applyTextStyleToSelection() }
    @objc func resize() { let size = canvas.canvasSize; if let s = prompt("Resize Image", text: "Width × height in pixels", value: "\(Int(size.width)) × \(Int(size.height))") { let parts = s.components(separatedBy: CharacterSet(charactersIn: "x×, ")).filter { !$0.isEmpty }; guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0, w <= 16000, h <= 16000 else { return }; canvas.resizeCanvas(to: NSSize(width: w,height: h)); updateStatus() } }
    var activeUndoManager: UndoManager {
        if let editor = window?.firstResponder as? NSTextView, let manager = editor.undoManager { return manager }
        return canvas.editingUndoManager
    }
    @objc func undo() {
        if let editor = window.firstResponder as? NSTextView { editor.undoManager?.undo() } else { canvas.undo() }
    }
    @objc func redo() {
        if let editor = window.firstResponder as? NSTextView { editor.undoManager?.redo() } else { canvas.redo() }
    }
    @objc func cut() { if let editor = window.firstResponder as? NSTextView { editor.cut(nil) } else { canvas.copySelection(); canvas.deleteSelection() } }; @objc func copyArtwork() { if let editor = window.firstResponder as? NSTextView { editor.copy(nil) } else { canvas.copySelection() } }
    @objc func copyImage() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([canvas.renderedImage()]) }
    @objc func paste() { if let editor = window.firstResponder as? NSTextView { editor.paste(nil) } else { canvas.paste() } }; @objc func selectAll() { if let editor = window.firstResponder as? NSTextView { editor.selectAll(nil) } else { canvas.selectAll() } }; @objc func deleteSelection() { canvas.deleteSelection() }
    @objc func duplicate() { canvas.duplicateSelection() }; @objc func clear() { canvas.clearAnnotations() }; @objc func crop() { canvas.cropSelection() }
    @objc func wipe() { leaveFrame(); canvas.wipe() }
    @objc func wipeSnap() { leaveFrame(); canvas.wipeSnap() }
    @objc func rotateCW() { canvas.rotate(clockwise: true) }; @objc func rotateCCW() { canvas.rotate(clockwise: false) }
    @objc func flipH() { canvas.flip(horizontal: true) }; @objc func flipV() { canvas.flip(horizontal: false) }
    @objc func transparent() { canvas.setBackgroundColor(.clear) }; @objc func white() { canvas.setBackgroundColor(.white) }; @objc func flatten() { canvas.flatten() }
    @objc func front() { canvas.bringSelectionToFront() }; @objc func back() { canvas.sendSelectionToBack() }; @objc func group() { canvas.groupSelection() }; @objc func ungroup() { canvas.ungroupSelection() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Skitch Redux", .applicationVersion: "0.2", .credits: NSAttributedString(string: "Native 64-bit reconstruction for personal use. Feature parity with Skitch 1.0.12 is still in progress.")]) }
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
            try Data("native startup, original-format editable save/load, PNG export succeeded\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        } catch {
            try? Data("FAILED: \(error)\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        }
    }
    func writeLayoutEvidence() {
        let folder = ProcessInfo.processInfo.environment["SKITCH_EVIDENCE_DIR"] ?? support.path
        window.contentView?.layoutSubtreeIfNeeded()
        let rect = window.convertToScreen(canvas.convert(canvas.visibleRect, to: nil))
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let evidence: [String: Any] = ["windowFrame": NSStringFromRect(window.frame), "canvasScreenRect": NSStringFromRect(rect), "canvasInputTopLeft": [rect.minX,top-rect.maxY], "screenFrame": NSStringFromRect(NSScreen.screens.first?.frame ?? .zero), "nativeBackingScale":window.backingScaleFactor, "nameFontSize":nameField.font?.pointSize ?? 0,"statusFontSize":status.font?.pointSize ?? 0]
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: .prettyPrinted) { try? data.write(to: URL(fileURLWithPath:folder).appendingPathComponent("layout.json"), options:.atomic) }
    }
}

@main
@MainActor
enum SkitchReduxMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
