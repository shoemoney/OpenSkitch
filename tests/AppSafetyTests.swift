// Run tools/test-app-safety.sh. These are internal AppKit events, not desktop input.
// The generated App.swift copy replaces alert, window, activation, termination, capture and hotkey
// boundaries. App launch wiring, document decisions and Canvas remain real.
#if APP_SAFETY_TESTS
import AppKit
import UniformTypeIdentifiers

final class AppSafetyWindow: NSWindow {
    override func makeKeyAndOrderFront(_ sender: Any?) {}
    override func orderFront(_ sender: Any?) {}
    override func orderBack(_ sender: Any?) {}
}

enum AppSafetyActivation {
    static func suppress() {}
}

@MainActor
enum AppSafetyTermination {
    static var requests = 0
    static var replies: [Bool] = []
    static func request() { requests += 1 }
    static func reply(_ shouldTerminate: Bool) { replies.append(shouldTerminate) }
}

// No defaults, Carbon handler or desktop registration is reachable through this
// adapter. GlobalHotkeys.swift still compiles alongside the actual app sources.
@MainActor
final class AppSafetyHotkeyManager {
    static var installations = 0
    static var unregistrations = 0
    func install(globalScreen: @escaping @MainActor () -> Void,
                 globalWindow: @escaping @MainActor () -> Void,
                 globalFullscreen: @escaping @MainActor () -> Void,
                 globalFrame: @escaping @MainActor () -> Void,
                 globalCamera: @escaping @MainActor () -> Void) throws {
        Self.installations += 1
    }
    func unregister() throws { Self.unregistrations += 1 }
    func showSettings(attachedTo parent: NSWindow? = nil) {
        AppSafetyAlert.unexpected.append("Unexpected shortcut settings window")
    }
}

// Unexpected file dialogs fail the test instead of blocking or showing UI.
final class AppSafetyFilePanel {
    var allowedContentTypes: [UTType] = []
    var nameFieldStringValue = ""
    var allowsOtherFileTypes = false
    var allowsMultipleSelection = false
    var url: URL?
    func runModal() -> NSApplication.ModalResponse {
        AppSafetyAlert.unexpected.append("Unexpected file dialog")
        return .cancel
    }
}
typealias AppSafetySavePanel = AppSafetyFilePanel
typealias AppSafetyOpenPanel = AppSafetyFilePanel

final class AppSafetyAlert: NSAlert {
    convenience init(error: Error) {
        self.init()
        messageText = error.localizedDescription
    }
    struct Answer {
        let title: String
        let response: NSApplication.ModalResponse
        var text: String? = nil
    }
    static var answers: [Answer] = []
    static var seen: [String] = []
    static var unexpected: [String] = []
    @discardableResult
    override func runModal() -> NSApplication.ModalResponse {
        Self.seen.append(messageText)
        guard !Self.answers.isEmpty else {
            Self.unexpected.append(messageText)
            return .alertSecondButtonReturn
        }
        let answer = Self.answers.removeFirst()
        if answer.title != messageText { Self.unexpected.append(messageText) }
        if let text = answer.text, let field = accessoryView as? NSTextField { field.stringValue = text }
        return answer.response
    }
}

@MainActor
final class AppSafetyCaptureCoordinator {
    var frameRect: NSRect?
    static var requests: [String] = []
    static var cancellation: NSError { NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
    static var holdShutdown = false
    static var shutdownRequests = 0
    static var shutdownResult: Result<Void, Error> = .success(())
    static var shutdownCallbacks: [(Result<Void, Error>) -> Void] = []
    static var holdCapture = false
    static var captureCallbacks: [(Result<NSImage, Error>) -> Void] = []
    static var useRealIdleShutdown = false
    static var realIdleShutdowns = 0
    private var realIdleCapture: CaptureCoordinator?
    func shutdown(completion: @escaping (Result<Void, Error>) -> Void) {
        Self.shutdownRequests += 1
        if Self.useRealIdleShutdown {
            Self.realIdleShutdowns += 1
            let real = CaptureCoordinator(); realIdleCapture = real
            real.shutdown { result in MainActor.assumeIsolated { completion(result) } }
            return
        }
        if Self.holdShutdown { Self.shutdownCallbacks.append(completion) }
        else { completion(Self.shutdownResult) }
    }
    func capture(mode: String, delay: Double = 0, completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append(mode); deliver(completion)
    }
    func captureCamera(completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append("camera"); deliver(completion)
    }
    func captureURL(_ url: URL, completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append("web"); deliver(completion)
    }
    private func deliver(_ completion: @escaping (Result<NSImage, Error>) -> Void) {
        if Self.holdCapture { Self.captureCallbacks.append(completion) }
        else { completion(.failure(Self.cancellation)) }
    }
}

// A second invocation of this same test executable exercises NSApp's genuine
// quit loop from a main-dispatch block. Windows/activation/hotkeys remain fake;
// actual Capture/Publishing/Photos are idle and no capture/upload is requested.
@MainActor
final class AppSafetyNativeTerminationDelegate: NSObject, NSApplicationDelegate {
    let evidence: URL
    var fixture: AppSafetyTests.Fixture?
    init(evidence: URL) { self.evidence = evidence }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            AppSafetyCaptureCoordinator.useRealIdleShutdown = true
            fixture = try AppSafetyTests.Fixture()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } catch { fputs("Native termination fixture: \(error)\n", stderr); exit(1) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        fixture!.app.applicationShouldTerminate(sender)
    }
    func applicationWillTerminate(_ notification: Notification) {
        let app = fixture!.app
        app.applicationWillTerminate(notification)
        let passed = app.shutdownPending.isEmpty && AppSafetyCaptureCoordinator.realIdleShutdowns == 1
        do {
            try JSONSerialization.data(withJSONObject: ["passed": passed,
                "actualIdleCaptureShutdowns": AppSafetyCaptureCoordinator.realIdleShutdowns,
                "pendingShutdown": Array(app.shutdownPending).sorted()], options: [.prettyPrinted, .sortedKeys])
                .write(to: evidence.appendingPathComponent("native-termination.json"), options: .atomic)
        } catch { fputs("Native termination evidence: \(error)\n", stderr); exit(1) }
        if !passed { exit(1) }
    }
}

private final class AppSafetyDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint = .zero
    var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(_ board: NSPasteboard) { draggingPasteboard = board; super.init() }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
@MainActor
enum AppSafetyTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func waitForMain(_ message: String, until condition: () -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        try expect(condition(), message)
    }
    @MainActor
    final class Fixture {
        let app = AppDelegate()
        init(nativeRecovery: Data? = nil, legacyRecovery: Data? = nil) throws {
            let expected = ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"]!
            try expect(app.support.path == expected, "App support must be isolated")
            for name in ["Recovery.skitch", "Recovery.skitchredux"] {
                let recovery = app.support.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: recovery.path) { try FileManager.default.removeItem(at: recovery) }
            }
            if let nativeRecovery { try nativeRecovery.write(to: app.support.appendingPathComponent("Recovery.skitch"), options: .atomic) }
            if let legacyRecovery { try legacyRecovery.write(to: app.support.appendingPathComponent("Recovery.skitchredux"), options: .atomic) }
            // Use the real launch method to test onChange and onOpenDocument wiring.
            app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            app.timer?.invalidate(); app.timer = nil
            app.window.isReleasedWhenClosed = false
            try expect(app.window is AppSafetyWindow, "Window must never be ordered on screen")
        }
        deinit {
            MainActor.assumeIsolated {
                app.timer?.invalidate()
                app.window.delegate = nil
                app.window.close()
                app.historyWindow?.delegate = nil
                app.historyWindow?.close()
                NSApp.mainMenu = nil
            }
        }
        func file(_ stem: String) -> URL {
            app.support.appendingPathComponent(stem + "-" + UUID().uuidString + ".skitchredux")
        }
        func saveA() throws -> URL {
            let url = file("A"); app.currentURL = url
            try expect(app.save(), "Initial editable save")
            return url
        }
    }
    static func editor(_ app: AppDelegate, text: String) throws -> NSTextView {
        app.canvas.tool = .text
        let location = app.canvas.convert(NSPoint(x: 30, y: 30), to: nil)
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
            modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
            throw Failure(description: "Internal mouse event allocation")
        }
        app.canvas.mouseDown(with: event)
        guard let editor = app.canvas.subviews.compactMap({ $0 as? NSTextView }).first else {
            throw Failure(description: "Annotation editor was not created")
        }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        try expect(app.window.firstResponder === editor, "Annotation editor must own focus")
        return editor
    }
    static func answer(_ response: NSApplication.ModalResponse) {
        AppSafetyAlert.answers.append(.init(title: "Save your drawing?", response: response))
    }
    static func image(color: NSColor = .blue, size: NSSize = NSSize(width: 24, height: 16)) throws -> NSImage {
        guard let pixels = SketchRenderer.bitmap(size: size, draw: {
            color.setFill(); NSRect(origin: .zero, size: size).fill()
        }) else { throw Failure(description: "Synthetic image rendering") }
        let image = NSImage(size: size); image.addRepresentation(pixels)
        return image
    }
    static func drop(_ url: URL, into app: AppDelegate) throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        try expect(board.writeObjects([url as NSURL]), "Isolated drag pasteboard")
        let drag = AppSafetyDrag(board)
        try expect(app.canvas.draggingEntered(drag) == .copy, "Document callback must accept a file drag")
        try expect(app.canvas.performDragOperation(drag), "Document callback must handle a file drop")
    }
    static func dirtyTyping() throws {
        let fixture = try Fixture(), app = fixture.app
        let text = try editor(app, text: "Unsaved annotation")
        let model = app.canvas.document
        try expect(app.dirty && app.window.isDocumentEdited, "Typing must immediately mark the app dirty")
        answer(.alertSecondButtonReturn)
        app.newFile()
        try expect(app.canvas.document == model && text.string == "Unsaved annotation", "Cancel New must retain pending text and model")
        try expect(text.superview === app.canvas && app.window.firstResponder === text, "Cancel New must retain the live editor")
        answer(.alertSecondButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Quit must consult dirty pending text")
    }
    static func typingUndo() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.setBackgroundColor(.yellow)
        let text = try editor(app, text: "Typing undo")
        let before = app.canvas.document
        let undo = NSMenuItem(title: "Undo", action: #selector(AppDelegate.undo), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: #selector(AppDelegate.redo), keyEquivalent: "Z")
        try expect(text.undoManager?.canUndo == true && app.validateMenuItem(undo), "Undo menu must use typing history")
        try expect(NSApp.sendAction(undo.action!, to: app, from: undo), "Undo action dispatch")
        try expect(text.string.isEmpty && text.superview === app.canvas, "Undo must undo typing without committing or deleting the annotation")
        try expect(app.canvas.document == before, "Typing undo must not consume canvas history")
        try expect(app.validateMenuItem(redo), "Redo menu must use typing history")
        try expect(NSApp.sendAction(redo.action!, to: app, from: redo), "Redo action dispatch")
        try expect(text.string == "Typing undo" && app.canvas.document == before, "Redo must restore typing in the same editor")
        app.canvas.tool = .select
        let committed = app.canvas.document
        app.undo()
        try expect(app.canvas.document.elements.isEmpty && app.canvas.document.backgroundColor == committed.backgroundColor,
                   "Canvas Undo must resume after leaving the text editor")
    }
    static func recoverySnapshot() throws {
        let fixture = try Fixture(), app = fixture.app
        let text = try editor(app, text: "Recovery\nkeeps live text")
        let before = app.canvas.document, caret = text.selectedRange()
        let typingHistory = text.undoManager, canUndo = app.canvas.editingUndoManager.canUndo
        let original = app.canvas.onChange; var changes = 0
        app.canvas.onChange = { changes += 1; original?() }
        app.saveRecovery()
        let data = try Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch"))
        let recovered = try SkitchFile.decode(data).document
        try expect(recovered.elements.first?.text == text.string, "Recovery must include uncommitted text")
        try expect(app.canvas.document == before && changes == 0, "Recovery must not mutate the live document or notify changes")
        try expect(text.superview === app.canvas && app.window.firstResponder === text && text.selectedRange() == caret,
                   "Recovery must preserve editor, focus and caret")
        try expect(text.undoManager === typingHistory && app.canvas.editingUndoManager.canUndo == canUndo,
                   "Recovery must not create canvas undo or replace typing history")
        text.insertText("!", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        app.saveRecovery()
        try expect(try SkitchFile.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch"))).document.elements.first?.text == text.string,
                   "Typing must continue and reach the next recovery snapshot")
    }
    static func pendingTextFallback() throws {
        let fixture = try Fixture(), app = fixture.app
        let text = try editor(app, text: "")
        // Programmatic text replacement does not emit textDidChange. This tests
        // the safety backstop when the app's dirty flag has not been updated.
        text.string = "Pending text without a change notification"
        app.dirty = false; app.window.isDocumentEdited = false
        let before = app.canvas.document
        try expect(app.canvas.hasPendingTextChanges, "Canvas must expose pending text independently of the dirty flag")
        app.saveRecovery()
        let recovered = try SkitchFile.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch"))).document
        try expect(recovered.elements.first?.text == text.string && app.canvas.document == before,
                   "Recovery must retain pending text even when dirty is false")
        answer(.alertSecondButtonReturn)
        app.newFile()
        try expect(app.canvas.document == before && text.superview === app.canvas,
                   "Discard decisions must protect pending text even when dirty is false")
    }
    static func originalMetadataRecovery() throws {
        let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"]!)
        let manifest = try JSONDecoder().decode([[String: String]].self,
            from: Data(contentsOf: evidence.appendingPathComponent("source-manifest.json")))
        guard let path = manifest.first(where: { $0["name"] == "AppSafetyTests.swift" })?["path"] else {
            throw Failure(description: "Original fixture location requires the harness source manifest")
        }
        let originalURL = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("original/Skitch.app/Contents/Resources/firstlaunch.skitch")
        let originalBytes = try Data(contentsOf: originalURL), original = try LegacySkitch.decode(originalBytes)
        var fallback = SketchDocument(size: CGSize(width: 71, height: 53)); fallback.backgroundColor = SketchColor(.green)
        let fallbackBytes = try fallback.encoded()
        let saved: (bytes: Data, document: SketchDocument, metadata: LegacyBridge.Metadata) = try autoreleasepool {
            let fixture = try Fixture(), app = fixture.app
            // Import a private copy so no save/recovery decision can write the original fixture.
            let importedURL = fixture.file("Original").deletingPathExtension().appendingPathExtension("skitch")
            try originalBytes.write(to: importedURL)
            app.openURL(importedURL)
            try expect(app.currentURL == importedURL && app.canvas.document.elements.filter { $0.kind == .path }.count == 3 &&
                       app.canvas.document.elements.filter { $0.kind == .text }.count == 1,
                       "The actual app must import the original fixture as editable paths and text")
            let metadata = app.legacyMetadata
            try expect(metadata.root == original.attributes && !metadata.elements.isEmpty &&
                       metadata.root["skitchBrushColor"] != nil && metadata.root["skitchBrushSize"] != nil,
                       "Original brush/root/object metadata must reach the app, not only the file decoder")
            let text = try editor(app, text: "Pending recovery annotation")
            let before = app.canvas.document, pending = try SketchDocument.decode(app.canvas.snapshotDocumentData())
            let typing = text.undoManager, caret = text.selectedRange()
            app.saveRecovery()
            let recovery = app.support.appendingPathComponent("Recovery.skitch"), bytes = try Data(contentsOf: recovery)
            let decoded = try SkitchFile.decode(bytes), visible = try LegacySkitch.decode(bytes)
            try expect(decoded.document == pending && decoded.metadata == metadata,
                       "Native recovery must retain pending edits and original metadata together")
            try expect(visible.attributes["skitchBrushColor"] == original.attributes["skitchBrushColor"] &&
                       visible.attributes["skitchBrushSize"] == original.attributes["skitchBrushSize"] && visible.paths.count == 3,
                       "Recovery's visible SVG must retain the original brush settings and three editable paths")
            try expect(app.canvas.document == before && text.superview === app.canvas && app.window.firstResponder === text &&
                       text.undoManager === typing && text.selectedRange() == caret && app.legacyMetadata == metadata,
                       "Metadata recovery must not commit or replace the live editor, model, caret or metadata")
            app.saveRecovery()
            try expect(try Data(contentsOf: recovery) == bytes && Data(contentsOf: importedURL) == originalBytes && Data(contentsOf: originalURL) == originalBytes,
                       "Repeated native recovery must be stable and must not overwrite either fixture")
            return (bytes, pending, metadata)
        }
        try autoreleasepool {
            let restored = try Fixture(nativeRecovery: saved.bytes, legacyRecovery: fallbackBytes), app = restored.app
            try expect(app.canvas.document == saved.document && app.legacyMetadata == saved.metadata && app.dirty && app.window.isDocumentEdited,
                       "Actual startup must prefer native recovery over legacy JSON and restore original metadata")
            try expect(app.currentURL == nil && app.nameField.stringValue == "Recovered drawing", "Recovered work must remain unsaved rather than retain a fixture destination")
            app.saveRecovery()
            let recovered = try SkitchFile.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch")))
            try expect(recovered.document == saved.document && recovered.metadata == saved.metadata &&
                       !FileManager.default.fileExists(atPath: app.support.appendingPathComponent("Recovery.skitchredux").path),
                       "Recovery after restart must retain metadata and replace the obsolete JSON recovery")
        }
        try autoreleasepool {
            let restored = try Fixture(legacyRecovery: fallbackBytes), app = restored.app
            try expect(app.canvas.document == fallback && app.legacyMetadata == .init() && app.dirty,
                       "Actual startup must still restore old JSON recovery when native recovery is absent")
            app.saveRecovery()
            let decoded = try SkitchFile.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch")))
            try expect(decoded.document == fallback && !FileManager.default.fileExists(atPath: app.support.appendingPathComponent("Recovery.skitchredux").path),
                       "Legacy JSON recovery must migrate to native recovery without changing the drawing")
        }
    }
    static func acceptedDrop() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), originalA = try Data(contentsOf: a)
        app.canvas.setBackgroundColor(.yellow)
        var documentB = SketchDocument(size: CGSize(width: 123, height: 99))
        documentB.backgroundColor = SketchColor(.green)
        let b = fixture.file("B"); try documentB.encoded().write(to: b)
        answer(.alertThirdButtonReturn)
        try drop(b, into: app)
        try expect(app.currentURL == b && app.canvas.document == documentB && !app.dirty, "Accepted drop must update document and save destination together")
        try expect(!app.canvas.editingUndoManager.canUndo, "Accepted open must clear the previous document's undo history")
        app.canvas.setBackgroundColor(.blue)
        try expect(app.save(), "Save dropped document")
        try expect(try Data(contentsOf: a) == originalA, "Saving B must never overwrite A")
        try expect(try SketchDocument.decode(Data(contentsOf: b)) == app.canvas.document, "Save must write B's new content to B")
    }
    static func cancelledDrop() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), originalA = try Data(contentsOf: a)
        let text = try editor(app, text: "Keep draft on cancelled drop")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let b = fixture.file("B"); try SketchDocument(size: CGSize(width: 123, height: 99)).encoded().write(to: b)
        answer(.alertSecondButtonReturn)
        try drop(b, into: app)
        try expect(app.currentURL == a && app.canvas.document == before && app.dirty, "Cancelled drop must keep old destination, model and dirty state")
        try expect(text.superview === app.canvas && app.window.firstResponder === text && text.undoManager?.canUndo == true,
                   "Cancelled drop must retain live typing and its undo history")
        try expect(try app.canvas.snapshotDocumentData() == pending, "Cancelled drop must preserve all pending text")
        try expect(try Data(contentsOf: a) == originalA, "Cancelled drop must not write the old document")
    }
    static func captureCancellation() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), originalA = try Data(contentsOf: a)
        let text = try editor(app, text: "Keep edits during capture")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        app.startCapture("crosshair", delay: 30)
        app.cameraSnap()
        AppSafetyAlert.answers.append(.init(title: "Snap from Link", response: .alertFirstButtonReturn,
                                          text: "http://127.0.0.1:9/not-requested"))
        app.webSnap()
        try expect(AppSafetyCaptureCoordinator.requests == ["crosshair", "camera", "web"], "Capture starts must not ask to discard existing edits")
        try expect(AppSafetyAlert.seen == ["Snap from Link"], "Capture cancellation must not show a discard prompt")
        answer(.alertSecondButtonReturn)
        app.receiveCapture(.success(try image()))
        try expect(app.currentURL == a && app.canvas.document == before && app.dirty, "Cancel at completion must keep existing drawing and URL")
        try expect(text.superview === app.canvas && app.window.firstResponder === text && text.undoManager?.canUndo == true,
                   "Cancel at completion must preserve pending typing and Undo")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == originalA,
                   "Capture cancellation must preserve pending content and saved bytes")

        // Finish the annotation explicitly before checking view-only framing.
        // Screen Snap changes meaning in Frame mode; picker cancellation keeps
        // the preview ready instead of leaving it or replacing the document.
        app.canvas.tool = .select
        let framed = app.canvas.document, framedPending = try app.canvas.snapshotDocumentData()
        let undoName = app.canvas.editingUndoManager.undoActionName
        app.frameSnap()
        try expect(app.frameMode && !app.frameKeepsAnnotations && app.canvas.framePreview &&
                   AppSafetyCaptureCoordinator.requests == ["crosshair", "camera", "web"],
                   "Frame enters preview without starting a capture or asking to discard")
        app.screenSnap()
        try expect(AppSafetyCaptureCoordinator.requests == ["crosshair", "camera", "web", "frame"] &&
                   app.frameMode && app.canvas.framePreview && !app.frameCaptureInProgress,
                   "Screen Snap in Frame mode must request frame capture; cancellation must leave it ready")
        try expect(app.canvas.document == framed && app.currentURL == a && app.dirty &&
                   app.canvas.editingUndoManager.canUndo && app.canvas.editingUndoManager.undoActionName == undoName,
                   "Cancelled frame capture must preserve the document, destination, dirty state and history")
        try expect(try app.canvas.snapshotDocumentData() == framedPending && Data(contentsOf: a) == originalA &&
                   AppSafetyAlert.seen == ["Snap from Link", "Save your drawing?"],
                   "Frame preview and picker cancellation must not discard, save or show another prompt")
        app.cancelFrame()
        try expect(!app.frameMode && !app.canvas.framePreview && app.canvas.document == framed,
                   "Cancel Frame must leave preview without changing the drawing")
    }
    static func captureDiscard() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try fixture.saveA(); _ = try editor(app, text: "Explicitly discarded")
        answer(.alertThirdButtonReturn)
        app.receiveCapture(.success(try image()))
        try expect(app.canvas.canvasSize == NSSize(width: 24, height: 16) && app.canvas.document.backgroundPNG != nil,
                   "Approved capture must install the synthetic image")
        try expect(app.currentURL == nil && app.dirty && app.nameField.stringValue == "Screenshot", "Approved capture must become a new unsaved drawing")
        try expect(app.canvas.document.elements.isEmpty && !app.canvas.editingUndoManager.canUndo, "Approved replacement must clear old text and history")
    }
    static func captureSave() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(); _ = try editor(app, text: "Save before capture replaces")
        answer(.alertFirstButtonReturn)
        app.receiveCapture(.success(try image()))
        let saved = try SketchDocument.decode(Data(contentsOf: a))
        try expect(saved.elements.first?.text == "Save before capture replaces", "Save choice must persist pending text before replacement")
        try expect(app.currentURL == nil && app.dirty && app.canvas.document.backgroundPNG != nil, "Capture must replace only after successful save")
    }
    static func framePreviewCancellation() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        app.canvas.setBackgroundColor(.yellow); app.canvas.setBackgroundColor(.blue); app.canvas.undo()
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let history = app.canvas.editingUndoManager, undoName = history.undoActionName, redoName = history.redoActionName
        let dirty = app.dirty, name = app.nameField.stringValue, zoom = app.canvas.zoom
        guard let scroll = app.canvas.enclosingScrollView, let exported = app.canvas.imageData(format: "png") else {
            throw Failure(description: "Frame preview fixture requires a real canvas scroll view and PNG export")
        }
        let opaque = app.window.isOpaque, background = app.window.backgroundColor, drawsBackground = scroll.drawsBackground
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery(); let recovered = try Data(contentsOf: recovery)
        try expect(history.canUndo && history.canRedo, "Preview fixture must contain both Undo and Redo history")
        app.frameSnap()
        try expect(app.frameMode && !app.frameKeepsAnnotations && app.canvas.framePreview && !app.window.isOpaque && !scroll.drawsBackground,
                   "Frame must enter a see-through view state without starting capture")
        // Re-enter and switch mode: neither may overwrite the original window appearance.
        app.frameSnap(); app.resnap()
        try expect(app.frameMode && app.frameKeepsAnnotations && app.canvas.framePreview &&
                   AppSafetyCaptureCoordinator.requests.isEmpty && AppSafetyAlert.seen.isEmpty,
                   "Entering or switching Frame/Resnap preview must not capture or prompt")
        try expect(app.canvas.document == before && app.currentURL == a && app.dirty == dirty && app.nameField.stringValue == name && app.canvas.zoom == zoom,
                   "Frame preview must preserve the model, destination, dirty state, name and zoom")
        try expect(try app.canvas.snapshotDocumentData() == pending && app.canvas.imageData(format: "png") == exported,
                   "See-through preview must not alter editable serialization or PNG export")
        app.saveRecovery()
        try expect(try Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Recovery in Frame preview must retain the complete original drawing without writing the saved document")
        app.cancelFrame()
        try expect(!app.frameMode && !app.frameKeepsAnnotations && !app.canvas.framePreview && app.window.isOpaque == opaque &&
                   app.window.backgroundColor == background && scroll.drawsBackground == drawsBackground,
                   "Cancel Frame must restore the original window and scroll appearance")
        try expect(app.canvas.document == before && app.currentURL == a && app.dirty == dirty &&
                   app.canvas.editingUndoManager === history && history.canUndo && history.canRedo &&
                   history.undoActionName == undoName && history.redoActionName == redoName,
                   "Preview enter, switch and Cancel must leave document identity and both history directions intact")
    }
    static func resnapPreservesAnnotations() throws {
        let fixture = try Fixture(), app = fixture.app
        var initial = SketchDocument(size: CGSize(width: 320, height: 180))
        initial.backgroundImage = try image(color: .red)
        var rectangle = SketchElement(kind: .rectangle); rectangle.rect = CGRect(x: 40, y: 30, width: 80, height: 50)
        rectangle.color = SketchColor(.green); rectangle.strokeWidth = 10; rectangle.filled = true
        var annotation = SketchElement(kind: .text); annotation.rect = CGRect(x: 150, y: 80, width: 120, height: 60)
        annotation.text = "Editable after resnap"; annotation.fontSize = 24; annotation.outlined = true
        initial.elements = [rectangle, annotation]
        try app.canvas.loadDocument(data: initial.encoded())
        app.nameField.stringValue = "Preserved destination"
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a), name = app.nameField.stringValue
        app.canvas.setBackgroundColor(.yellow)
        app.canvas.selection = [rectangle.id]
        app.canvas.cropRect = CGRect(x: 10, y: 10, width: 280, height: 150)
        let before = app.canvas.document, selected = app.canvas.selection, crop = app.canvas.cropRect
        try expect(app.canvas.editingUndoManager.canUndo, "Resnap fixture must have a pre-existing document undo step")
        app.resnap()
        try expect(app.frameMode && app.frameKeepsAnnotations && app.canvas.framePreview && AppSafetyAlert.seen.isEmpty,
                   "Resnap must enter preview without a discard decision")
        app.receiveFrameCapture(.success(try image()), keepingAnnotations: true)
        let after = app.canvas.document
        try expect(!app.frameMode && !app.canvas.framePreview && app.currentURL == a && app.nameField.stringValue == name && app.dirty,
                   "Successful resnap must exit preview and retain editable save destination and name")
        try expect(after.size == before.size && after.elements == before.elements && after.backgroundColor == before.backgroundColor &&
                   after.backgroundPNG != nil && after.backgroundPNG != before.backgroundPNG,
                   "Resnap must replace only the picture while preserving canvas dimensions and every editable annotation")
        try expect(app.canvas.selection == selected && app.canvas.cropRect == crop && AppSafetyAlert.seen.isEmpty,
                   "Resnap must preserve selection/crop and must not ask to discard annotations")
        guard let png = after.backgroundPNG, let bitmap = NSBitmapImageRep(data: png) else {
            throw Failure(description: "Resnap must produce a valid background raster")
        }
        try expect(bitmap.pixelsWide == 320 && bitmap.pixelsHigh == 180,
                   "A differently sized resnap must fit the original 320-by-180 viewport")
        try expect(try SketchDocument.decode(app.canvas.snapshotDocumentData()) == after && Data(contentsOf: a) == savedA,
                   "Resnap must remain an editable valid document and must not overwrite its saved destination automatically")
        app.undo()
        try expect(app.canvas.document == before && app.canvas.selection == selected && app.canvas.cropRect == crop && app.canvas.editingUndoManager.canUndo,
                   "One Undo must restore the complete pre-resnap state without losing older undo history")
        app.redo()
        try expect(app.canvas.document == after && app.canvas.selection == selected && app.canvas.cropRect == crop,
                   "Redo must restore the replacement picture and editable annotations together")
        app.undo(); app.undo()
        try expect(app.canvas.document == initial, "The older document undo step must remain usable after resnap Undo/Redo")
    }
    static func normalFrameDiscard() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        _ = try editor(app, text: "Keep until Frame replacement is approved")
        app.canvas.tool = .select
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let undoName = app.canvas.editingUndoManager.undoActionName
        app.frameSnap(); app.screenSnap()
        try expect(AppSafetyCaptureCoordinator.requests == ["frame"] && app.frameMode && !app.frameCaptureInProgress && AppSafetyAlert.seen.isEmpty,
                   "Cancelled Frame picker must leave preview ready without a discard prompt")
        try expect(app.canvas.document == before && app.currentURL == a && app.dirty &&
                   app.canvas.editingUndoManager.canUndo && app.canvas.editingUndoManager.undoActionName == undoName,
                   "Cancelled Frame picker must not alter the drawing or history")
        answer(.alertSecondButtonReturn)
        app.receiveFrameCapture(.success(try image()), keepingAnnotations: false)
        try expect(AppSafetyAlert.seen == ["Save your drawing?"] && app.frameMode && app.canvas.framePreview && !app.frameCaptureInProgress,
                   "Cancel at normal Frame completion must show exactly one prompt and leave Frame ready")
        try expect(app.canvas.document == before && app.currentURL == a && app.dirty && app.canvas.editingUndoManager.undoActionName == undoName,
                   "Cancel at normal Frame completion must preserve drawing, destination and history")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == savedA,
                   "Both Frame cancellation paths must preserve pending editable data and saved bytes")
        answer(.alertThirdButtonReturn)
        // A 40-by-30 screen rectangle returned as 80-by-60 Retina pixels must
        // keep its displayed size rather than doubling the next repeat frame.
        app.activeFrameScreenSize = NSSize(width: 40, height: 30)
        app.receiveFrameCapture(.success(try image(size: NSSize(width: 80, height: 60))), keepingAnnotations: false)
        try expect(AppSafetyAlert.seen == ["Save your drawing?", "Save your drawing?"] &&
                   AppSafetyAlert.answers.isEmpty && AppSafetyAlert.unexpected.isEmpty,
                   "Approved normal Frame must show one additional prompt, never prompt again inside receiveCapture")
        try expect(!app.frameMode && !app.frameCaptureInProgress && !app.canvas.framePreview && app.currentURL == nil &&
                   app.nameField.stringValue == "Screenshot" && app.dirty && app.canvas.canvasSize == NSSize(width: 80, height: 60),
                   "Discard-approved normal Frame must install a new unsaved screenshot and exit preview")
        try expect(app.canvas.zoom == 0.5 && app.canvas.frame.size == NSSize(width: 40, height: 30) &&
                   app.zoomControl.selectedItem?.representedObject as? Double == 0.5,
                   "Retina Frame pixels must retain the original screen footprint and keep the zoom menu synchronized")
        try expect(app.canvas.document.backgroundPNG != nil && app.canvas.document.elements.isEmpty && !app.canvas.editingUndoManager.canUndo,
                   "Discard-approved normal Frame must replace old annotations and history explicitly")
        try expect(try Data(contentsOf: a) == savedA, "Normal Frame replacement must not overwrite the old saved document")
    }
    static func filenameCommands() throws {
        let fixture = try Fixture(), app = fixture.app
        var rectangle = SketchElement(kind: .rectangle); rectangle.rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        app.canvas.document.elements = [rectangle]; app.canvas.selection = []
        app.nameField.stringValue = "Filename"; app.nameField.selectText(nil)
        guard let field = app.window.firstResponder as? NSTextView else { throw Failure(description: "Native filename field editor") }
        field.setSelectedRange(NSRange(location: 0, length: 0))
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: app.window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0) else { throw Failure(description: "Internal key event") }
        try expect(!app.canvas.performKeyEquivalent(with: key), "Canvas must decline shortcuts owned by filename editor")
        _ = app.window.performKeyEquivalent(with: key)
        try expect(app.canvas.selection.isEmpty, "Window key dispatch must not select canvas objects while filename is focused")
        app.selectAll()
        try expect(field.selectedRange().length == "Filename".utf16.count, "Select All menu must act on filename text")
    }
    static func oversizedImageFixture() throws -> URL {
        let support = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"]!)
        // A high-DPI TIFF can have legal point dimensions but excessive pixels.
        // Grayscale keeps the fixture small without mocking AppKit's decoder.
        let oversized = support.appendingPathComponent("oversized-high-dpi.tiff")
        try autoreleasepool {
            if !FileManager.default.fileExists(atPath: oversized.path) {
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8000, pixelsHigh: 4001,
                    bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                    colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0), let pixels = bitmap.bitmapData else {
                    throw Failure(description: "Oversized TIFF fixture allocation")
                }
                pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                bitmap.size = NSSize(width: 800, height: 400.1)
                guard let data = bitmap.representation(using: .tiff, properties: [:]) else {
                    throw Failure(description: "Oversized TIFF fixture encoding")
                }
                try data.write(to: oversized)
            }
            guard let decoded = NSImage(contentsOf: oversized) else { throw Failure(description: "Real TIFF decoding") }
            var proposed = CGRect(origin: .zero, size: decoded.size)
            guard let image = decoded.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                throw Failure(description: "Real TIFF pixel decoding")
            }
            try expect(SketchDocument.validSize(decoded.size), "TIFF point dimensions must be accepted by the old dimension check")
            try expect(!SketchDocument.validSize(NSSize(width: image.width, height: image.height)),
                       "TIFF actual pixels must exceed the document limit")
        }
        return oversized
    }
    static func failedOpenAfterDiscard() throws {
        let support = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"]!)
        let corrupt = support.appendingPathComponent("invalid-image.png")
        try Data("This is not an image".utf8).write(to: corrupt)
        let invalid = support.appendingPathComponent("invalid-version.skitchredux")
        var invalidDocument = SketchDocument(size: CGSize(width: 123, height: 99))
        invalidDocument.version = 99
        // Bypass validated serialization deliberately to create a rejected file.
        try JSONEncoder().encode(invalidDocument).write(to: invalid)
        let oversized = try oversizedImageFixture()
        let cases = [
            (corrupt, "The file could not be read as an image."),
            (invalid, SketchDocumentError.unsupportedVersion.localizedDescription),
            (oversized, "This image is too large or cannot be decoded safely.")
        ]
        for (url, errorTitle) in cases {
            let fixture = try Fixture(), app = fixture.app
            let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
            app.canvas.setBackgroundColor(.yellow); app.canvas.setBackgroundColor(.blue); app.canvas.undo()
            let text = try editor(app, text: "Keep draft after rejected " + url.lastPathComponent)
            let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
            let history = app.canvas.editingUndoManager, typing = text.undoManager, caret = text.selectedRange()
            let undoName = history.undoActionName, redoName = history.redoActionName
            let name = app.nameField.stringValue, zoom = app.canvas.zoom
            try expect(history.canUndo && history.canRedo && typing?.canUndo == true, "Rejected-open fixture must have both canvas and typing history")
            app.saveRecovery()
            let recovery = app.support.appendingPathComponent("Recovery.skitch"), recovered = try Data(contentsOf: recovery)
            answer(.alertThirdButtonReturn)
            AppSafetyAlert.answers.append(.init(title: errorTitle, response: .alertFirstButtonReturn))
            app.openURL(url)
            try expect(app.currentURL == a && app.canvas.document == before && app.dirty && app.window.isDocumentEdited,
                       "Rejected open after Discard must preserve drawing, save destination and dirty indicator: " + url.lastPathComponent)
            try expect(text.superview === app.canvas && app.window.firstResponder === text && text.selectedRange() == caret,
                       "Rejected open must preserve pending editor, focus and caret")
            try expect(app.canvas.editingUndoManager === history && history.canUndo && history.canRedo &&
                       history.undoActionName == undoName && history.redoActionName == redoName &&
                       text.undoManager === typing && typing?.canUndo == true, "Rejected open must preserve canvas and typing history")
            try expect(try app.canvas.snapshotDocumentData() == pending && app.nameField.stringValue == name && app.canvas.zoom == zoom,
                       "Rejected open must preserve name, zoom and pending content")
            try expect(try Data(contentsOf: a) == savedA && Data(contentsOf: recovery) == recovered,
                       "Rejected open must leave saved A and existing recovery byte-for-byte intact")
            app.saveRecovery()
            try expect(try Data(contentsOf: recovery) == recovered, "The next recovery tick must retain the rejected-open draft")
            try expect(AppSafetyAlert.answers.isEmpty && AppSafetyAlert.unexpected.isEmpty, "Rejected open must consume only Discard and its decoding error")
        }
    }
    static func rejectedCaptureSize() throws {
        let oversized = try oversizedImageFixture()
        for mode in ["normal", "frame", "resnap"] {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app
                let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
                app.canvas.setBackgroundColor(.yellow); app.canvas.setBackgroundColor(.blue); app.canvas.undo()
                if mode == "frame" { app.frameSnap() }
                if mode == "resnap" { app.resnap() }
                // Type after entering preview so rejection must preserve a live
                // editor, not merely committed annotations.
                let text = try editor(app, text: "Keep pending text after oversized " + mode)
                let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
                let history = app.canvas.editingUndoManager, typing = text.undoManager, caret = text.selectedRange()
                let undoName = history.undoActionName, redoName = history.redoActionName
                let name = app.nameField.stringValue, zoom = app.canvas.zoom
                let framed = app.frameMode, keepsAnnotations = app.frameKeepsAnnotations
                app.saveRecovery()
                let recovery = app.support.appendingPathComponent("Recovery.skitch"), recovered = try Data(contentsOf: recovery)
                guard let image = NSImage(contentsOf: oversized) else { throw Failure(description: "Oversized capture fixture decoding") }
                let prompts = AppSafetyAlert.seen.count
                AppSafetyAlert.answers.append(.init(title: "This capture is too large or cannot be decoded safely.", response: .alertFirstButtonReturn))
                if mode == "normal" { app.receiveCapture(.success(image)) }
                else {
                    app.frameCaptureInProgress = true
                    app.receiveFrameCapture(.success(image), keepingAnnotations: mode == "resnap")
                }
                try expect(AppSafetyAlert.seen.count == prompts + 1 && AppSafetyAlert.answers.isEmpty && AppSafetyAlert.unexpected.isEmpty,
                           "Oversized " + mode + " capture must show only its decoding error, before any discard prompt")
                try expect(app.currentURL == a && app.canvas.document == before && app.dirty && app.window.isDocumentEdited &&
                           app.nameField.stringValue == name && app.canvas.zoom == zoom,
                           "Rejected " + mode + " capture must preserve document, destination, dirty state, name and zoom")
                try expect(text.superview === app.canvas && app.window.firstResponder === text && text.selectedRange() == caret &&
                           text.undoManager === typing && typing?.canUndo == true && app.canvas.hasPendingTextChanges,
                           "Rejected capture must preserve the same pending editor, focus, caret and typing history")
                try expect(app.canvas.editingUndoManager === history && history.canUndo && history.canRedo &&
                           history.undoActionName == undoName && history.redoActionName == redoName,
                           "Rejected capture must preserve both directions of document history")
                try expect(app.frameMode == framed && app.canvas.framePreview == framed && app.frameKeepsAnnotations == keepsAnnotations && !app.frameCaptureInProgress,
                           "Rejected Frame/Resnap capture must leave its preview mode ready")
                app.saveRecovery()
                try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == savedA && Data(contentsOf: recovery) == recovered,
                           "Rejected capture and subsequent recovery tick must retain all pending data and saved/recovery bytes")
            }
        }
    }
    static func terminationDiscard(windowClose: Bool) throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Explicitly discard pending text at termination")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery()
        let oldRecovery = app.support.appendingPathComponent("Recovery.skitchredux")
        try before.encoded().write(to: oldRecovery)
        try expect(FileManager.default.fileExists(atPath: recovery.path) && app.canvas.hasPendingTextChanges,
                   "Termination fixture must contain both recovery and uncommitted text")
        let prompts = AppSafetyAlert.seen.count
        answer(.alertThirdButtonReturn)
        if windowClose {
            app.showHistory()
            guard let history = app.historyWindow else { throw Failure(description: "Real app History window creation") }
            try expect(history is AppSafetyWindow && !(history is NSPanel), "History must be an isolated ordinary window")
            let requests = AppSafetyTermination.requests
            // The adapter records forwarding without asking AppKit to terminate.
            try expect(!app.windowShouldClose(app.window), "Main Close must defer closing to application termination even while History remains alive")
            try expect(AppSafetyTermination.requests == requests + 1, "Main Close must forward exactly one termination request")
            try expect(AppSafetyAlert.seen.count == prompts && AppSafetyAlert.answers.count == 1,
                       "Main Close must not consume the application's pending Discard answer")
            try expect(app.dirty && app.canvas.document == before && text.superview === app.canvas &&
                       app.historyWindow === history, "Forwarding Close must preserve the editor and History before termination is decided")
            try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == savedA,
                       "Forwarding Close must not change pending text or saved bytes")
        }
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow, "Application termination must make the Discard decision")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow, "Follow-on termination must not ask to discard the same text again")
        try expect(AppSafetyAlert.seen.count == prompts + 1 && AppSafetyAlert.unexpected.isEmpty,
                   "Termination Discard must show exactly one prompt")
        try expect(!app.dirty && app.canvas.hasPendingTextChanges && app.canvas.document == before && text.superview === app.canvas,
                   "Discard approval must leave the pending editor intact until the simulated termination callback")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(!FileManager.default.fileExists(atPath: recovery.path) && !FileManager.default.fileExists(atPath: oldRecovery.path),
                   "Termination must remove both recovery formats instead of resurrecting discarded pending text")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == savedA,
                   "Termination Discard must not commit pending text or alter the saved document")
        try expect(text.superview === app.canvas && app.canvas.hasPendingTextChanges, "Recovery removal must be explicit even while pending text still exists")
    }
    static func mainCloseLifecycle() throws {
        // Retain the previous Window Close + Discard coverage, then independently
        // exercise the continuing-app branch that a forced termination masks.
        try autoreleasepool { try terminationDiscard(windowClose: true) }
        AppSafetyAlert.seen = []
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Keep draft when main Close is cancelled")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery()
        let recovered = try Data(contentsOf: recovery)
        app.showHistory()
        guard let history = app.historyWindow else { throw Failure(description: "History must remain alive during main Close") }
        try expect(history is AppSafetyWindow && !(history is NSPanel), "History must use the actual app's ordinary-window path")
        let requests = AppSafetyTermination.requests
        answer(.alertSecondButtonReturn)
        try expect(!app.windowShouldClose(app.window) && AppSafetyTermination.requests == requests + 1,
                   "Main Close must request termination and decline immediate close while History is alive")
        try expect(AppSafetyAlert.seen.isEmpty && AppSafetyAlert.answers.count == 1 && app.dirty,
                   "Close forwarding must not prompt, mark the draft discarded or consume the queued Cancel")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Cancel at the application boundary must leave the app running")
        try expect(app.currentURL == a && app.canvas.document == before && app.dirty && app.window.isDocumentEdited &&
                   text.superview === app.canvas && text.undoManager?.canUndo == true && app.historyWindow === history,
                   "Cancelled termination must preserve the current draft, editor, typing history and History window")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Cancelled main Close must preserve pending text, recovery and saved bytes")

        // Reopen through the real History action, using its actual openURL path.
        var documentB = SketchDocument(size: CGSize(width: 123, height: 99))
        documentB.backgroundColor = SketchColor(.green)
        let b = fixture.file("History-B"); try documentB.encoded().write(to: b)
        let row = NSButton(); row.identifier = NSUserInterfaceItemIdentifier(b.path)
        answer(.alertSecondButtonReturn); app.openHistory(row)
        try expect(app.currentURL == a && app.canvas.document == before && text.superview === app.canvas && app.dirty,
                   "History Open must still honor Cancel after cancelled main Close")
        answer(.alertThirdButtonReturn); app.openHistory(row)
        try expect(app.currentURL == b && app.canvas.document == documentB && !app.dirty,
                   "Approved History Open must install B with its proper save destination")
        let reopenedText = try editor(app, text: "Protect newer edits in reopened B")
        let reopenedModel = app.canvas.document, reopenedPending = try app.canvas.snapshotDocumentData()
        app.saveRecovery()
        let reopenedRecovery = try Data(contentsOf: recovery)

        // Closing History itself while the editor remains must not request Quit.
        let prompts = AppSafetyAlert.seen.count
        try expect(app.windowShouldClose(history) && AppSafetyTermination.requests == requests + 1,
                   "History Close must be allowed without forwarding another termination request")
        try expect(AppSafetyAlert.seen.count == prompts && app.dirty && reopenedText.superview === app.canvas,
                   "History Close must not ask to discard or mutate the live editor")
        answer(.alertSecondButtonReturn); app.newFile()
        try expect(app.currentURL == b && app.canvas.document == reopenedModel && app.dirty && reopenedText.superview === app.canvas,
                   "New must honor Cancel for newer edits after a cancelled Close and approved History Open")
        answer(.alertSecondButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Quit must still honor Cancel for the reopened document's newer edits")
        app.saveRecovery()
        try expect(try app.canvas.snapshotDocumentData() == reopenedPending && Data(contentsOf: recovery) == reopenedRecovery && Data(contentsOf: a) == savedA,
                   "Continuing after cancelled Close must keep new pending text and recovery intact")
        try expect(try SketchDocument.decode(Data(contentsOf: b)) == documentB, "Cancelled New and Quit must not write reopened B")
    }
    static func quitSave() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        app.canvas.setBackgroundColor(.yellow)
        _ = try editor(app, text: "Persist pending text before Quit")
        let expected = try SketchDocument.decode(app.canvas.snapshotDocumentData())
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery()
        try expect(FileManager.default.fileExists(atPath: recovery.path), "Quit Save fixture must start with recovery")
        answer(.alertFirstButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow, "Quit Save must approve termination after a successful editable save")
        let persisted = try Data(contentsOf: a), decoded = try SketchDocument.decode(persisted)
        try expect(persisted != savedA && decoded == expected && decoded.elements.first?.text == "Persist pending text before Quit",
                   "Quit Save must persist a valid complete document with pending text at the existing destination")
        try expect(app.currentURL == a && !app.dirty && !app.canvas.hasPendingTextChanges && !app.window.isDocumentEdited,
                   "Successful Quit Save must leave a clean committed document")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow && AppSafetyAlert.seen == ["Save your drawing?"],
                   "Successful Quit Save must not show a second prompt")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(!FileManager.default.fileExists(atPath: recovery.path), "Quit Save termination must clear obsolete recovery")
        try expect(try SketchDocument.decode(Data(contentsOf: a)) == expected, "Recovery cleanup must preserve the valid saved document")
    }
    static func deferredShutdownSuccess() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        _ = try editor(app, text: "Discard only when deferred shutdown completes")
        let pending = try app.canvas.snapshotDocumentData(), recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery(); let recovered = try Data(contentsOf: recovery)
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }
        app.timer = timer
        AppSafetyCaptureCoordinator.holdShutdown = true
        answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater,
                   "A pending capture shutdown acknowledgement must defer Quit even when actual Publishing is idle")
        try expect(AppSafetyCaptureCoordinator.shutdownRequests == 1 && AppSafetyCaptureCoordinator.shutdownCallbacks.count == 1 &&
                   AppSafetyTermination.replies.isEmpty && timer.isValid && AppSafetyHotkeyManager.unregistrations == 0,
                   "Before cleanup acknowledgement, Quit must not reply, unregister shortcuts or invalidate recovery timing")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && !app.windowShouldClose(app.window),
                   "Duplicate Quit and main Close must keep waiting for the same cleanup")
        try expect(AppSafetyCaptureCoordinator.shutdownRequests == 1 && AppSafetyCaptureCoordinator.shutdownCallbacks.count == 1 &&
                   AppSafetyAlert.seen == ["Save your drawing?"], "Duplicate termination must not restart cleanup or show another discard prompt")
        let complete = AppSafetyCaptureCoordinator.shutdownCallbacks.removeFirst()
        complete(.success(()))
        try expect(AppSafetyTermination.replies == [true] && timer.isValid && AppSafetyHotkeyManager.unregistrations == 0,
                   "Last cleanup acknowledgement must approve exactly once; final timer/hotkey teardown belongs to WillTerminate")
        complete(.success(()))
        try expect(AppSafetyTermination.replies == [true], "A duplicate backend acknowledgement must never reply to AppKit twice")
        try expect(try Data(contentsOf: recovery) == recovered && app.canvas.snapshotDocumentData() == pending && Data(contentsOf: a) == savedA,
                   "Deferred Discard must retain saved/recovery bytes and pending text until actual termination")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(!FileManager.default.fileExists(atPath: recovery.path) && !timer.isValid && AppSafetyHotkeyManager.unregistrations == 1,
                   "WillTerminate must finally clear discarded recovery, stop its timer and unregister shortcuts")
    }
    static func deferredShutdownFailureRetry() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Recover after deferred cleanup failure")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery(); let recovered = try Data(contentsOf: recovery)
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }
        app.timer = timer
        AppSafetyCaptureCoordinator.holdShutdown = true
        answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater, "Deferred cleanup failure fixture must start in TerminateLater")
        try expect(AppSafetyCaptureCoordinator.shutdownCallbacks.count == 1, "Deferred cleanup callback must remain controllable")
        let failure = NSError(domain: "AppSafety", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fake deferred capture cleanup failure"])
        AppSafetyAlert.answers.append(.init(title: failure.localizedDescription, response: .alertFirstButtonReturn))
        AppSafetyCaptureCoordinator.shutdownCallbacks.removeFirst()(.failure(failure))
        try expect(AppSafetyTermination.replies == [false] && app.dirty && app.window.isDocumentEdited && !app.terminationStarted && !app.discardedForTermination,
                   "Failed asynchronous cleanup must reject Quit and restore dirty/discard protection")
        try expect(timer.isValid && AppSafetyHotkeyManager.unregistrations == 0 && app.canvas.document == before && text.superview === app.canvas,
                   "Failed cleanup must preserve the running editor, timer and installed shortcuts")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Failed cleanup must retain pending edits and both saved/recovery bytes")
        try waitForMain("Deferred cleanup error must be delivered") { AppSafetyAlert.seen.contains(failure.localizedDescription) }
        try expect(AppSafetyAlert.answers.isEmpty && AppSafetyAlert.seen == ["Save your drawing?", failure.localizedDescription],
                   "Cleanup error must be delivered after the termination rejection")
        answer(.alertSecondButtonReturn); app.newFile()
        try expect(app.canvas.document == before && text.superview === app.canvas && app.dirty,
                   "After failed Discard termination, normal New must still honor Cancel")
        AppSafetyCaptureCoordinator.holdShutdown = false
        answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow && AppSafetyCaptureCoordinator.shutdownRequests == 2 &&
                   AppSafetyTermination.replies == [false], "Quit retry with synchronous success must approve without emitting another deferred reply")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(!FileManager.default.fileExists(atPath: recovery.path) && !timer.isValid,
                   "Successful retry must finally clean recovery and stop its timer")
    }
    static func synchronousShutdownFailureRetry() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Preserve draft after synchronous cleanup failure")
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery(); let recovered = try Data(contentsOf: recovery)
        let failure = NSError(domain: "AppSafety", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fake synchronous capture cleanup failure"])
        AppSafetyCaptureCoordinator.shutdownResult = .failure(failure)
        answer(.alertThirdButtonReturn)
        AppSafetyAlert.answers.append(.init(title: failure.localizedDescription, response: .alertFirstButtonReturn))
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel && AppSafetyTermination.replies.isEmpty,
                   "Synchronous cleanup failure must return Cancel directly rather than reply to a nonexistent deferred Quit")
        try expect(app.dirty && app.window.isDocumentEdited && !app.terminationStarted && !app.discardedForTermination &&
                   app.canvas.document == before && text.superview === app.canvas && AppSafetyHotkeyManager.unregistrations == 0,
                   "Synchronous failure must restore the protected draft and leave shortcut cleanup for real termination")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Synchronous cleanup failure must preserve pending text, recovery and saved bytes")
        try waitForMain("Synchronous cleanup error must be delivered") { AppSafetyAlert.seen.contains(failure.localizedDescription) }
        AppSafetyCaptureCoordinator.shutdownResult = .success(())
        answer(.alertSecondButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel && AppSafetyCaptureCoordinator.shutdownRequests == 1,
                   "A Cancelled retry must show the discard decision again without restarting shutdown")
        answer(.alertFirstButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow && AppSafetyCaptureCoordinator.shutdownRequests == 2,
                   "Save on a successful retry must commit before approving shutdown")
        try expect(try SketchDocument.decode(Data(contentsOf: a)) == SketchDocument.decode(pending),
                   "Successful Save retry must persist the complete pending document")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try expect(!FileManager.default.fileExists(atPath: recovery.path), "Save retry must clear obsolete recovery on termination")
    }
    static func pan(_ app: AppDelegate, from start: CGPoint, to end: CGPoint) throws {
        let canvas = app.canvas
        func space(_ type: NSEvent.EventType) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: app.window.windowNumber, context: nil, characters: " ",
                charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) else {
                throw Failure(description: "Internal Space event allocation")
            }
            return event
        }
        canvas.keyDown(with: try space(.keyDown))
        defer { if let event = try? space(.keyUp) { canvas.keyUp(with: event) } }
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let location = canvas.convert(CGPoint(x: point.x * canvas.zoom, y: point.y * canvas.zoom), to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: app.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                throw Failure(description: "Internal pan event allocation")
            }
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
    }
    static func pannedSaveReopenRecovery() throws {
        let saved: (recovery: Data, original: SketchDocument, png: Data, panned: SketchDocument, metadata: LegacyBridge.Metadata) = try autoreleasepool {
            let fixture = try Fixture(), app = fixture.app
            let size = CGSize(width: 100, height: 80)
            guard let bitmap = SketchRenderer.bitmap(size: size, draw: {
                NSColor.blue.setFill(); CGRect(origin: .zero, size: size).fill()
                NSColor.green.setFill(); CGRect(x: 5, y: 5, width: 25, height: 20).fill()
                NSColor.yellow.setFill(); CGRect(x: 80, y: 50, width: 15, height: 20).fill()
            }) else { throw Failure(description: "Pan fixture pixels") }
            let background = NSImage(size: size); background.addRepresentation(bitmap)
            app.canvas.setBackground(background); app.canvas.setZoom(2); app.canvas.tool = .select
            var element = SketchElement(kind: .rectangle)
            element.rect = CGRect(x: 35, y: 30, width: 12, height: 15); element.color = SketchColor(.red)
            app.canvas.document.elements = [element]
            let metadata = LegacyBridge.Metadata(root: ["futurePanSetting": "retained"], originalSize: size)
            app.legacyMetadata = metadata
            app.canvas.editingUndoManager.removeAllActions()
            let original = app.canvas.document
            guard let png = app.canvas.imageData(format: "png") else { throw Failure(description: "Pan fixture PNG") }
            try pan(app, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 20))
            let panned = app.canvas.document, snapshot = try app.canvas.snapshotDocumentData()
            let state = try JSONSerialization.jsonObject(with: snapshot) as! [String: Any]
            try expect(state["canvasPanBackground"] != nil && panned != original && app.dirty,
                       "Actual Space drag must create hidden source pixels and a dirty translated annotation")
            app.saveRecovery()
            let recovery = try Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch"))
            let recovered = try SkitchFile.decode(recovery)
            try expect(try recovered.canvasData == snapshot && recovered.metadata == metadata,
                       "App recovery must preserve the full pan source alongside original metadata")
            let destination = fixture.file("Panned").deletingPathExtension().appendingPathExtension("skitch")
            app.currentURL = destination
            try expect(app.save(), "Actual app native Save of a panned canvas")
            let disk = try SkitchFile.read(destination)
            try expect(try disk.canvasData == snapshot && disk.metadata == metadata && !app.dirty,
                       "App Save must retain hidden pan state instead of only the visible clipped background")
            app.openURL(destination)
            try expect(app.currentURL == destination && app.canvas.document == panned && app.legacyMetadata == metadata,
                       "Actual app reopen must restore the panned document and its destination/metadata")
            try pan(app, from: CGPoint(x: 90, y: 20), to: CGPoint(x: 20, y: 20))
            try expect(app.canvas.document == original && app.canvas.imageData(format: "png") == png && app.dirty,
                       "After app Save/reopen, pan back must recover all hidden colored pixels and annotation coordinates")
            return (recovery, original, png, panned, metadata)
        }
        try autoreleasepool {
            let fixture = try Fixture(nativeRecovery: saved.recovery), app = fixture.app
            try expect(app.canvas.document == saved.panned && app.legacyMetadata == saved.metadata && app.currentURL == nil && app.dirty,
                       "Actual recovery startup must restore the full panned unsaved document and metadata")
            try pan(app, from: CGPoint(x: 90, y: 20), to: CGPoint(x: 20, y: 20))
            try expect(app.canvas.document == saved.original && app.canvas.imageData(format: "png") == saved.png,
                       "After app recovery startup, pan back must recover offscreen original pixels and editable geometry")
        }
    }
    static func lateCallbacksDuringShutdown(failing: Bool) throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Draft protected while operations drain")
        let before = app.canvas.document, snapshot = try app.canvas.snapshotDocumentData()
        let caret = text.selectedRange(), typingUndo = text.undoManager
        app.saveRecovery(); let recoveryURL = app.support.appendingPathComponent("Recovery.skitch")
        let recovery = try Data(contentsOf: recoveryURL)
        let photoURL = app.support.appendingPathComponent("LatePhoto-\(UUID().uuidString).png")
        let captureImage = try image(color: .green)
        try SketchRenderer.png(image: captureImage)!.write(to: photoURL)
        let documentURL = fixture.file("LateDocument")
        try SketchDocument(size: CGSize(width: 61, height: 43)).encoded().write(to: documentURL)
        AppSafetyCaptureCoordinator.holdShutdown = true
        answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && app.terminationStarted,
                   "Late callback fixture must be waiting on actual capture shutdown acknowledgement")
        app.receiveCapture(.success(captureImage))
        app.receiveFrameCapture(.success(captureImage), keepingAnnotations: false)
        app.receiveFrameCapture(.success(captureImage), keepingAnnotations: true)
        let lateError = NSError(domain: "AppSafety", code: 4, userInfo: [NSLocalizedDescriptionKey: "Late capture failure during Quit"])
        app.receiveCapture(.failure(lateError))
        app.receiveFrameCapture(.failure(lateError), keepingAnnotations: false)
        app.receiveFrameCapture(.failure(lateError), keepingAnnotations: true)
        // Photos' admitted-copy callback calls openURL synchronously. Exercise that
        // destination directly without opening the Photos picker or copying assets.
        app.openURL(photoURL)
        try drop(documentURL, into: app)
        app.startCapture("fullscreen"); app.frameSnap(); app.resnap()
        try expect(app.canvas.document == before && app.currentURL == a && text.superview === app.canvas &&
                   app.window.firstResponder === text && text.undoManager === typingUndo && text.selectedRange() == caret,
                   "Late normal/Frame/Resnap, photo callback and dropped document must preserve the editor and destination")
        try expect(try app.canvas.snapshotDocumentData() == snapshot && Data(contentsOf: a) == savedA && Data(contentsOf: recoveryURL) == recovery,
                   "Late completions must not replace pending text or saved/recovery bytes")
        try expect(AppSafetyAlert.seen == ["Save your drawing?"] && AppSafetyCaptureCoordinator.requests.isEmpty && !app.frameMode,
                   "Shutdown guards must suppress new capture/frame work and extra discard prompts")
        let completion = AppSafetyCaptureCoordinator.shutdownCallbacks.removeFirst()
        if failing {
            let failure = NSError(domain: "AppSafety", code: 3, userInfo: [NSLocalizedDescriptionKey: "Late callback cleanup failure"])
            AppSafetyAlert.answers.append(.init(title: failure.localizedDescription, response: .alertFirstButtonReturn))
            completion(.failure(failure))
            try expect(AppSafetyTermination.replies == [false] && !app.terminationStarted && !app.discardedForTermination && app.dirty,
                       "Failed cleanup must end the termination guard and restore discard protection")
            try waitForMain("Late callback cleanup error must be delivered") { AppSafetyAlert.seen.contains(failure.localizedDescription) }
            answer(.alertSecondButtonReturn); app.openURL(photoURL)
            try expect(AppSafetyAlert.seen.filter { $0 == "Save your drawing?" }.count == 2 && text.superview === app.canvas && app.currentURL == a,
                       "After failure, photo open must reach the normal Cancel decision and protect the draft")
            answer(.alertThirdButtonReturn); app.openURL(photoURL)
            try expect(app.currentURL == nil && app.canvas.document.size == captureImage.size && app.canvas.document != before &&
                       text.superview == nil && !app.terminationStarted && !app.discardedForTermination,
                       "After explicit Discard following failed cleanup, the photo destination must be allowed to replace the draft")
            try expect(try Data(contentsOf: a) == savedA, "Resumed photo open must still preserve the prior saved document")
        } else {
            completion(.success(()))
            try expect(AppSafetyTermination.replies == [true] && app.terminationStarted,
                       "Successful acknowledgement must keep document replacement guarded until real termination")
            app.receiveCapture(.success(captureImage)); app.openURL(photoURL)
            try expect(try app.canvas.snapshotDocumentData() == snapshot && app.currentURL == a && text.superview === app.canvas,
                       "Late callbacks after approval must remain harmless before WillTerminate")
        }
    }
    static func shiftPaletteBackground() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.newBlank(size: CGSize(width: 100, height: 80))
        var selected = SketchElement(kind: .rectangle)
        selected.rect = CGRect(x: 10, y: 10, width: 20, height: 15); selected.color = SketchColor(.red)
        selected.strokeWidth = app.canvas.strokeWidth; selected.filled = app.canvas.filled; selected.shadowed = app.canvas.shadowed
        var other = selected; other.id = UUID(); other.rect.origin.x = 60; other.color = SketchColor(.blue)
        app.canvas.document.elements = [selected, other]; app.canvas.selection = [selected.id]
        app.canvas.strokeColor = .red; app.colorWell.color = .red
        app.canvas.editingUndoManager.removeAllActions()
        let before = app.canvas.document, palette = NSColor(deviceRed: 0.2, green: 0.7, blue: 0.4, alpha: 0.35)
        try expect(NSColorPanel.shared.showsAlpha, "Launch must enable original palette alpha without ordering the panel")
        app.colorWell.color = palette
        app.applyChosenColor(palette, modifiers: [.shift])
        let shifted = app.canvas.document
        try expect(shifted.backgroundColor == SketchColor(palette) && shifted.elements == before.elements &&
                   SketchColor(app.canvas.strokeColor) == SketchColor(.red) && SketchColor(app.colorWell.color) == SketchColor(.red) &&
                   app.canvas.selection == [selected.id] && app.dirty,
                   "Shift palette must change backdrop including alpha, preserving annotation styles, stroke, selection and well")
        app.undo(); try expect(app.canvas.document == before && !app.canvas.editingUndoManager.canUndo,
                               "Shift background color must have one exact document Undo")
        app.redo(); try expect(app.canvas.document == shifted, "Shift background color Redo must restore alpha")
        app.canvas.editingUndoManager.removeAllActions()
        app.colorWell.color = palette; app.applyChosenColor(palette, modifiers: [])
        let normal = app.canvas.document
        try expect(normal.backgroundColor == shifted.backgroundColor && normal.elements[0].color == SketchColor(palette) &&
                   normal.elements[1] == other && SketchColor(app.canvas.strokeColor) == SketchColor(palette),
                   "Normal palette must set current stroke and selected annotation color while preserving the unselected element and backdrop")
        app.undo(); try expect(app.canvas.document == shifted && !app.canvas.editingUndoManager.canUndo,
                               "Normal selected-color edit must have one exact document Undo")
        app.redo(); try expect(app.canvas.document == normal, "Normal selected-color Redo must restore selected alpha")
    }
    static func nonTextRecoveryDuringShutdown() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try fixture.saveA()
        app.canvas.setBackgroundColor(.yellow); app.saveRecovery()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        let older = try Data(contentsOf: recovery)
        app.canvas.setBackgroundColor(.blue)
        let current = app.canvas.document
        try expect(!app.canvas.hasPendingTextChanges && app.dirty, "Recovery regression must have non-text unsaved changes")
        AppSafetyCaptureCoordinator.holdShutdown = true; answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && !app.dirty && app.discardedForTermination,
                   "Non-text Discard must wait for cleanup rather than terminate immediately")
        let protected = try Data(contentsOf: recovery)
        try expect(try protected != older && SkitchFile.decode(protected).document == current,
                   "Quit must snapshot the latest non-text edit before its temporary Discard flag")
        app.saveRecovery(); app.newFile()
        try expect(try Data(contentsOf: recovery) == protected && app.canvas.document == current,
                   "Queued recovery and New during cleanup must not remove recovery or replace the discarded draft")
        let error = NSError(domain: "AppSafety", code: 5, userInfo: [NSLocalizedDescriptionKey: "Non-text cleanup failure"])
        AppSafetyAlert.answers.append(.init(title: error.localizedDescription, response: .alertFirstButtonReturn))
        AppSafetyCaptureCoordinator.shutdownCallbacks.removeFirst()(.failure(error))
        try expect(app.dirty && !app.terminationStarted && !app.discardedForTermination && AppSafetyTermination.replies == [false],
                   "Cleanup rejection must restore non-text discard protection")
        try expect(try SkitchFile.decode(Data(contentsOf: recovery)).document == current,
                   "Recovery must exist immediately after rejected Quit, without waiting for another timer tick")
        try waitForMain("Non-text cleanup error must be delivered") { AppSafetyAlert.seen.contains(error.localizedDescription) }
        answer(.alertSecondButtonReturn); app.newFile()
        try expect(app.canvas.document == current && app.dirty, "Restored non-text work must remain protected by Cancel")
    }
    static func staleFrameDocumentReplacement() throws {
        for keeps in [false, true] {
            for replacement in ["new", "native", "raster", "capture"] {
                try autoreleasepool {
                    let fixture = try Fixture(), app = fixture.app
                    try app.canvas.loadDocument(data: SketchDocument(size: CGSize(width: 320, height: 180)).encoded())
                    _ = try fixture.saveA(); app.canvas.setZoom(1)
                    app.window.contentView?.layoutSubtreeIfNeeded()
                    AppSafetyCaptureCoordinator.holdCapture = true
                    keeps ? app.resnap() : app.frameSnap()
                    app.performFrameSnap()
                    try expect(app.frameCaptureInProgress && AppSafetyCaptureCoordinator.captureCallbacks.count == 1,
                               "Stale Frame fixture must hold one admitted capture")
                    let completion = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
                    switch replacement {
                    case "new": app.newFile()
                    case "native":
                        let url = fixture.file("B").deletingPathExtension().appendingPathExtension("skitch")
                        try SkitchFile(document: SketchDocument(size: CGSize(width: 230, height: 150)),
                                       metadata: .init(root: ["replacementMetadata": "B"])).write(to: url)
                        app.openURL(url)
                    case "raster":
                        let url = fixture.file("PhotoB").deletingPathExtension().appendingPathExtension("png")
                        try SketchRenderer.png(image: image(color: .yellow, size: CGSize(width: 40, height: 30)))!.write(to: url)
                        app.openURL(url)
                    default: app.receiveCapture(.success(try image(color: .yellow)))
                    }
                    let before = try app.canvas.snapshotDocumentData(), destination = app.currentURL
                    let metadata = app.legacyMetadata, zoom = app.canvas.zoom, dirty = app.dirty
                    let history = app.canvas.editingUndoManager, undo = history.undoActionName
                    completion(.success(try image(color: .green)))
                    try expect(try app.canvas.snapshotDocumentData() == before && app.currentURL == destination &&
                               app.legacyMetadata == metadata && app.canvas.zoom == zoom && app.dirty == dirty &&
                               history.undoActionName == undo && !app.frameCaptureInProgress && AppSafetyAlert.seen.isEmpty,
                               "A stale \(keeps ? "Resnap" : "Frame") callback must preserve the \(replacement) replacement's pixels, metadata, URL, zoom and history")
                }
            }
        }
    }
    static func staleScreenCameraWebCallbacks() throws {
        for mode in ["crosshair", "camera", "web"] {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app
                AppSafetyAlert.seen = []
                _ = try fixture.saveA(); AppSafetyCaptureCoordinator.holdCapture = true
                switch mode {
                case "camera": app.cameraSnap()
                case "web":
                    AppSafetyAlert.answers.append(.init(title: "Snap from Link", response: .alertFirstButtonReturn,
                                                        text: "http://127.0.0.1:9/not-requested"))
                    app.webSnap()
                default: app.startCapture(mode)
                }
                try expect(AppSafetyCaptureCoordinator.captureCallbacks.count == 1, "Hold the actual \(mode) callback wiring")
                let callback = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
                app.newFile(); let text = try editor(app, text: "New document after \(mode)")
                let before = try app.canvas.snapshotDocumentData(), history = text.undoManager
                callback(.success(try image()))
                try expect(try app.canvas.snapshotDocumentData() == before && app.currentURL == nil && app.dirty &&
                           text.superview === app.canvas && text.undoManager === history && AppSafetyAlert.answers.isEmpty,
                           "Old \(mode) completion must never replace or prompt over the newly created editor")
            }
        }
        try autoreleasepool {
            let fixture = try Fixture(), app = fixture.app
            AppSafetyAlert.seen = []
            _ = try fixture.saveA(); app.startCapture("crosshair")
            let callback = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
            let text = try editor(app, text: "Editing the same admitted document")
            let before = try app.canvas.snapshotDocumentData()
            answer(.alertSecondButtonReturn); callback(.success(try image()))
            try expect(try app.canvas.snapshotDocumentData() == before && text.superview === app.canvas &&
                       AppSafetyAlert.seen == ["Save your drawing?"],
                       "Generation protection must still let same-document completion reach the unsaved-edit decision")
        }
    }
    static func resnapRequiresFullView() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.newBlank(size: CGSize(width: 1000, height: 700)); app.canvas.setZoom(2)
        _ = try fixture.saveA(); app.window.contentView?.layoutSubtreeIfNeeded()
        app.resnap(); let before = try app.canvas.snapshotDocumentData(), zoom = app.canvas.zoom
        try expect(!app.canvasIsFullyVisible, "A 200% document must be clipped by this actual App scroll view")
        AppSafetyCaptureCoordinator.holdCapture = true; app.performFrameSnap()
        try expect(try AppSafetyCaptureCoordinator.requests.isEmpty && !app.frameCaptureInProgress && app.frameMode &&
                   app.status.stringValue.contains("Reduce zoom") && app.canvas.zoom == zoom && app.canvas.snapshotDocumentData() == before,
                   "Clipped Resnap must explain zoom adjustment without capturing, modifying or changing the zoom")
        app.fitCanvasToWindow(); try expect(app.canvasIsFullyVisible, "Fit must make the complete canvas capturable")
        app.performFrameSnap()
        try expect(AppSafetyCaptureCoordinator.captureCallbacks.count == 1, "Full-view Resnap must admit capture")
        let callback = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
        app.canvas.setZoom(app.canvas.zoom * 0.75)
        let text = try editor(app, text: "Typed after frame was admitted"), snapshot = try app.canvas.snapshotDocumentData()
        callback(.success(try image()))
        try expect(try app.canvas.snapshotDocumentData() == snapshot && text.superview === app.canvas &&
                   app.frameMode && !app.frameCaptureInProgress && app.status.stringValue.contains("view changed"),
                   "A view changed during capture must keep new typing and reject a now-misaligned Resnap")
        app.fitCanvasToWindow(); app.performFrameSnap()
        try expect(AppSafetyCaptureCoordinator.captureCallbacks.count == 1, "Adjusted full-view Resnap must remain retryable")
        let retry = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
        let expected = try CanvasView.validatedDocumentData(app.canvas.snapshotDocumentData()), retainedZoom = app.canvas.zoom
        retry(.success(try image()))
        try expect(app.canvas.document.size == expected.size && app.canvas.document.elements == expected.elements &&
                   app.canvas.zoom == retainedZoom && !app.frameMode && text.superview == nil,
                   "Stable full-view Resnap must retain pending text, document geometry and zoom")
    }
    static func rasterPointSizeNormalization() throws {
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Old annotations must be replaced")
        app.legacyMetadata = .init(root: ["oldDocumentMetadata": "remove"])
        guard let bitmap = SketchRenderer.bitmap(size: CGSize(width: 16, height: 16), draw: {
            NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 16, height: 16).fill()
        }) else { throw Failure(description: "Small TIFF pixels") }
        bitmap.size = CGSize(width: 0.5, height: 0.5)
        let url = fixture.file("SmallPoints").deletingPathExtension().appendingPathExtension("tiff")
        try bitmap.representation(using: .tiff, properties: [:])!.write(to: url)
        guard let decoded = NSImage(contentsOf: url) else { throw Failure(description: "Small-point TIFF decode") }
        var rect = CGRect(origin: .zero, size: decoded.size)
        guard let pixels = decoded.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw Failure(description: "Small TIFF bitmap") }
        try expect(!SketchDocument.validSize(decoded.size) && pixels.width == 16 && pixels.height == 16,
                   "Real TIFF must have invalid document point size but valid actual pixels")
        answer(.alertThirdButtonReturn); app.openURL(url)
        try expect(app.canvas.canvasSize == CGSize(width: 16, height: 16) && app.canvas.document.elements.isEmpty &&
                   app.canvas.document.backgroundPNG != nil && text.superview == nil && !app.canvas.editingUndoManager.canUndo &&
                   app.legacyMetadata == .init() && app.currentURL == nil && !app.dirty,
                   "Raster Open must replace the old document using validated pixels and clear old annotations/editor/metadata/history")
        try expect(try Data(contentsOf: a) == savedA, "Normalized raster Open must preserve the prior saved file")
    }
    static func publishingCallbacksDuringQuit() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try fixture.saveA(); app.canvas.setBackgroundColor(.yellow)
        AppSafetyCaptureCoordinator.holdShutdown = true; answer(.alertThirdButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater, "Publishing callback fixture must be draining Quit")
        let status = app.status.stringValue
        let genuine = NSError(domain: "AppSafety", code: 6, userInfo: [NSLocalizedDescriptionKey: "Fake publishing failure"])
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        var delivered = false
        Task { @MainActor in
            app.receivePublishing(.failure(cancellation)); app.receivePublishing(.failure(genuine))
            app.receivePublishing(.success(URL(string: "https://example.invalid/not-requested")!))
            delivered = true
        }
        try waitForMain("Queued publishing callback must actually run before cleanup acknowledgement") { delivered }
        try expect(AppSafetyAlert.seen == ["Save your drawing?"] && app.status.stringValue == status,
                   "Queued publishing successes, cancellations and failures during Quit must neither alert nor overwrite cleanup status")
        let cleanup = NSError(domain: "AppSafety", code: 7, userInfo: [NSLocalizedDescriptionKey: "Publishing callback fixture cleanup failure"])
        AppSafetyAlert.answers.append(.init(title: cleanup.localizedDescription, response: .alertFirstButtonReturn))
        AppSafetyCaptureCoordinator.shutdownCallbacks.removeFirst()(.failure(cleanup))
        try waitForMain("Publishing fixture cleanup error must be delivered") { AppSafetyAlert.seen.contains(cleanup.localizedDescription) }
        app.receivePublishing(.failure(cancellation))
        try expect(AppSafetyAlert.seen == ["Save your drawing?", cleanup.localizedDescription],
                   "Normal publishing cancellation after rejected Quit must remain silent")
        AppSafetyAlert.answers.append(.init(title: genuine.localizedDescription, response: .alertFirstButtonReturn))
        app.receivePublishing(.failure(genuine))
        try expect(AppSafetyAlert.seen.last == genuine.localizedDescription, "A genuine publishing failure while running must still be reported")
    }
    static func realIdleCaptureShutdown() throws {
        AppSafetyCaptureCoordinator.useRealIdleShutdown = true
        let fixture = try Fixture(), app = fixture.app
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow && app.shutdownPending.isEmpty &&
                   AppSafetyTermination.replies.isEmpty && AppSafetyCaptureCoordinator.realIdleShutdowns == 1,
                   "Actual Capture's idle main-actor shutdown must acknowledge before AppKit can enter terminateLater")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    static func frameChromeDrawing() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let chrome = FrameChromeView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
            let scroll = NSScrollView(frame: CGRect(x: 100, y: 100, width: 200, height: 200))
            chrome.addSubview(scroll); chrome.canvasScrollView = scroll
            guard let style = NSAppearance(named: appearance) else { throw Failure(description: "Frame chrome appearance") }
            var normal: NSBitmapImageRep?, frame: NSBitmapImageRep?
            style.performAsCurrentDrawingAppearance {
                normal = SketchRenderer.bitmap(size: chrome.bounds.size) { chrome.draw(chrome.bounds) }
                chrome.showsCanvasHole = true
                frame = SketchRenderer.bitmap(size: chrome.bounds.size) { chrome.draw(chrome.bounds) }
            }
            guard let opaque = normal, let transparent = frame else { throw Failure(description: "Frame chrome bitmap") }
            try expect(opaque.colorAt(x: 200, y: 200)!.alphaComponent > 0.99 &&
                       transparent.colorAt(x: 200, y: 200)!.alphaComponent < 0.01 &&
                       transparent.colorAt(x: 20, y: 20)!.alphaComponent > 0.99 &&
                       transparent.colorAt(x: 380, y: 380)!.alphaComponent > 0.99,
                       "\(appearance.rawValue) Frame must clear only the canvas hole and keep top/sidebar/bottom/status chrome opaque")
        }
        let fixture = try Fixture(), app = fixture.app
        guard let chrome = app.window.contentView as? FrameChromeView else { throw Failure(description: "Actual App chrome view") }
        let before = try app.canvas.snapshotDocumentData()
        app.frameSnap()
        try expect(chrome.showsCanvasHole && chrome.canvasScrollView === app.canvas.enclosingScrollView,
                   "Actual Frame must enable only the wired canvas hole")
        app.cancelFrame()
        try expect(try !chrome.showsCanvasHole && app.canvas.snapshotDocumentData() == before,
                   "Frame cancellation must restore opaque chrome without changing editable data")
    }
    static func main() {
        guard let evidence = ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"],
              ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] != nil else {
            fputs("Run tools/test-app-safety.sh for isolated execution.\n", stderr); exit(2)
        }
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        if CommandLine.arguments.contains("--native-idle-termination") {
            let delegate = AppSafetyNativeTerminationDelegate(evidence: URL(fileURLWithPath: evidence))
            NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            fputs("Native termination returned without exiting.\n", stderr); exit(1)
        }
        let tests: [(String, () throws -> Void)] = [
            ("dirty typing protects New and Quit", dirtyTyping),
            ("active editor Undo/Redo and menu validation", typingUndo),
            ("recovery includes pending text without committing", recoverySnapshot),
            ("pending text remains protected with a stale dirty flag", pendingTextFallback),
            ("original metadata survives native recovery, startup preference and legacy JSON migration", originalMetadataRecovery),
            ("accepted document drop saves to B and preserves A", acceptedDrop),
            ("cancelled document drop preserves pending typing", cancelledDrop),
            ("capture start cancellation and completion Cancel preserve edits", captureCancellation),
            ("capture completion Discard replaces explicitly", captureDiscard),
            ("capture completion Save persists pending text first", captureSave),
            ("Frame preview enter, switch and Cancel preserve document, recovery and history", framePreviewCancellation),
            ("Resnap preserves annotations, destination and usable Undo/Redo", resnapPreservesAnnotations),
            ("normal Frame picker and completion cancellation; Discard prompts exactly once", normalFrameDiscard),
            ("filename focus retains command-menu behavior", filenameCommands),
            ("failed open after Discard preserves edits, history, destination and recovery", failedOpenAfterDiscard),
            ("oversized capture rejects before discard and preserves pending editor in normal/Frame/Resnap", rejectedCaptureSize),
            ("Quit Discard removes pending recovery without a second prompt", { try terminationDiscard(windowClose: false) }),
            ("main Close forwards with History alive; Discard cleanup and Cancel protect later edits", mainCloseLifecycle),
            ("Quit Save persists pending text and clears recovery", quitSave),
            ("deferred shutdown waits, deduplicates Quit and replies once before final cleanup", deferredShutdownSuccess),
            ("asynchronous shutdown failure retains recovery and permits protected Quit retry", deferredShutdownFailureRetry),
            ("synchronous shutdown failure cancels directly and permits Cancel/Save retry", synchronousShutdownFailureRetry),
            ("app native Save, reopen and recovery retain offscreen pan pixels and metadata", pannedSaveReopenRecovery),
            ("pending shutdown and final approval reject late capture/photo/document callbacks", { try lateCallbacksDuringShutdown(failing: false) }),
            ("failed shutdown resets late-callback guards and restores Cancel/Discard protection", { try lateCallbacksDuringShutdown(failing: true) }),
            ("Shift palette changes undoable backdrop; normal palette styles selected annotations", shiftPaletteBackground),
            ("non-text recovery survives deferred Discard and failed shutdown", nonTextRecoveryDuringShutdown),
            ("old Frame/Resnap callbacks cannot mutate new/native/raster/capture replacements", staleFrameDocumentReplacement),
            ("screen/camera/Web callback generations protect new documents but retain same-document prompts", staleScreenCameraWebCallbacks),
            ("Resnap requires a full visible canvas and rejects geometry changes during capture", resnapRequiresFullView),
            ("raster Open uses valid pixels when TIFF logical points are invalid", rasterPointSizeNormalization),
            ("queued publishing callbacks remain silent during Quit; cancellation remains silent afterward", publishingCallbacksDuringQuit),
            ("actual idle Capture acknowledges synchronously before deferred AppKit termination", realIdleCaptureShutdown),
            ("Frame chrome stays opaque around its transparent canvas hole in light/dark appearance", frameChromeDrawing)
        ]
        var results: [[String: Any]] = [], failures = 0
        for (name, test) in tests {
            AppSafetyAlert.answers = []; AppSafetyAlert.seen = []; AppSafetyAlert.unexpected = []
            AppSafetyCaptureCoordinator.requests = []
            AppSafetyCaptureCoordinator.holdShutdown = false
            AppSafetyCaptureCoordinator.shutdownRequests = 0
            AppSafetyCaptureCoordinator.shutdownResult = .success(())
            AppSafetyCaptureCoordinator.shutdownCallbacks = []
            AppSafetyCaptureCoordinator.holdCapture = false
            AppSafetyCaptureCoordinator.captureCallbacks = []
            AppSafetyCaptureCoordinator.useRealIdleShutdown = false
            AppSafetyCaptureCoordinator.realIdleShutdowns = 0
            AppSafetyHotkeyManager.unregistrations = 0
            AppSafetyTermination.requests = 0
            AppSafetyTermination.replies = []
            do {
                try autoreleasepool {
                    try test()
                    try expect(AppSafetyAlert.unexpected.isEmpty, "Unexpected alerts: \(AppSafetyAlert.unexpected)")
                    try expect(AppSafetyAlert.answers.isEmpty, "An expected alert did not run")
                }
                print("PASS \(name)"); results.append(["name": name, "passed": true])
            } catch {
                failures += 1; print("FAIL \(name): \(error)")
                results.append(["name": name, "passed": false, "error": String(describing: error)])
            }
        }
        let report: [String: Any] = ["tests": results, "passed": tests.count - failures, "total": tests.count,
            "architecture": ProcessInfo.processInfo.environment["APP_SAFETY_ARCH"] ?? "unknown",
            "hotkeyAdapterInstallations": AppSafetyHotkeyManager.installations,
            "boundaries": "Nonvisible windows; deterministic modal answers; recorded termination requests; synthetic cancelled capture and no-registration hotkey adapters; actual app launch and Canvas; isolated support and named drag pasteboard. No desktop events, real application termination, uploads, live hotkey registrations or general clipboard writes."]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: evidence).appendingPathComponent("results.json"), options: .atomic)
        } catch { failures += 1; fputs("Could not save test evidence: \(error)\n", stderr) }
        print("\(tests.count - results.filter { $0["passed"] as? Bool == false }.count)/\(tests.count) app safety tests passed")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
