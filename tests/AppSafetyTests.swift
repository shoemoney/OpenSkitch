// Run tools/test-app-safety.sh. These are internal AppKit events, not desktop input.
// The generated App.swift copy replaces alert, window, activation, termination, capture and hotkey
// boundaries. App launch wiring, document decisions and Canvas remain real.
#if APP_SAFETY_TESTS
import AppKit
import UniformTypeIdentifiers
import ObjectiveC

private enum AppSafetyClipboard { static var board: NSPasteboard? }
private extension NSPasteboard {
    @objc class func appSafetyGeneralPasteboard() -> NSPasteboard { AppSafetyClipboard.board! }
}

final class AppSafetyWindow: NSWindow {
    var simulatedSheet: NSWindow?
    var simulatesVisibility = false
    var shown = false
    var minimized = false
    override var isVisible: Bool { simulatesVisibility && shown }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { simulatedSheet ?? super.attachedSheet }
    override func makeKeyAndOrderFront(_ sender: Any?) { if simulatesVisibility { shown = true } }
    override func orderFront(_ sender: Any?) { if simulatesVisibility { shown = true } }
    override func orderOut(_ sender: Any?) { shown = false }
    override func miniaturize(_ sender: Any?) { minimized = true; shown = false }
    override func deminiaturize(_ sender: Any?) { minimized = false; shown = true }
    override func orderBack(_ sender: Any?) {}
}

final class AppSafetyFontPanel: NSFontPanel {
    var shown = false
    var conversion: ((NSFont) -> NSFont)?
    override var isVisible: Bool { shown }
    override func orderFront(_ sender: Any?) { shown = true }
    override func makeKeyAndOrderFront(_ sender: Any?) { shown = true }
    override func orderOut(_ sender: Any?) { shown = false }
    override func close() { shown = false }
    override func convert(_ font: NSFont) -> NSFont { conversion?(font) ?? font }
}

final class AppSafetyDragPanel: NSPanel {
    var fronts = 0
    override var isVisible: Bool { false }
    override func orderFrontRegardless() { fronts += 1 }
    override func orderOut(_ sender: Any?) {}
    override func close() {}
}

enum AppSafetyActivation {
    static var isActive = true
    static func suppress() {}
}
enum AppSafetyAnimations { static var reduceMotion = true }

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
    struct Answer {
        let response: NSApplication.ModalResponse
        var url: URL? = nil
    }
    static var answers: [Answer] = []
    var title = ""
    var nameFieldLabel = ""
    var prompt = ""
    var accessoryView: NSView?
    var firstResponder: NSResponder?
    @discardableResult
    func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        firstResponder = responder
        return true
    }
    var allowedContentTypes: [UTType] = []
    var nameFieldStringValue = ""
    var allowsOtherFileTypes = false
    var allowsMultipleSelection = false
    var url: URL?
    func runModal() -> NSApplication.ModalResponse {
        if !Self.answers.isEmpty {
            let answer = Self.answers.removeFirst()
            url = answer.url
            return answer.response
        }
        AppSafetyAlert.unexpected.append("Unexpected file dialog")
        return .cancel
    }
}
typealias AppSafetySavePanel = AppSafetyFilePanel
typealias AppSafetyOpenPanel = AppSafetyFilePanel

final class AppSafetyPageLayout {
    static var response: NSApplication.ModalResponse = .cancel
    static var update: ((NSPrintInfo) -> Void)?
    func runModal(with settings: NSPrintInfo) -> Int {
        Self.update?(settings)
        return Self.response.rawValue
    }
}

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
                app.historyFollowTimer?.invalidate()
                app.dragPreviewTimer?.invalidate()
                app.navigatorTimer?.invalidate()
                app.closeFontPanel()
                app.removeDragThumbnail()
                app.navigatorWindow?.orderOut(nil)
                app.navigatorWindow?.close()
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
            (app.window as! AppSafetyWindow).simulatesVisibility = true
            (app.window as! AppSafetyWindow).shown = true
            app.showHistory()
            guard let history = app.historyWindow else { throw Failure(description: "Real app History window creation") }
            try expect(history is AppSafetyWindow && !(history is NSPanel), "History must be an isolated ordinary window")
            let requests = AppSafetyTermination.requests
            try expect(!app.windowShouldClose(app.window), "Main Close hides the editor while retaining the session")
            try expect(AppSafetyTermination.requests == requests, "Main Close must never request termination")
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
        // Close hides. Explicit Quit retains its independent Cancel/Discard policy.
        try autoreleasepool { try terminationDiscard(windowClose: true) }
        AppSafetyAlert.seen = []
        let fixture = try Fixture(), app = fixture.app
        let a = try fixture.saveA(), savedA = try Data(contentsOf: a)
        let text = try editor(app, text: "Keep draft when main Close is cancelled")
        (app.window as! AppSafetyWindow).simulatesVisibility = true
        (app.window as! AppSafetyWindow).shown = true
        let before = app.canvas.document, pending = try app.canvas.snapshotDocumentData()
        let recovery = app.support.appendingPathComponent("Recovery.skitch")
        app.saveRecovery()
        let recovered = try Data(contentsOf: recovery)
        app.showHistory()
        guard let history = app.historyWindow else { throw Failure(description: "History must remain alive during main Close") }
        try expect(history is AppSafetyWindow && !(history is NSPanel), "History must use the actual app's ordinary-window path")
        let requests = AppSafetyTermination.requests
        answer(.alertSecondButtonReturn)
        try expect(!app.windowShouldClose(app.window) && AppSafetyTermination.requests == requests && !app.window.isVisible,
                   "Main Close hides without requesting termination while History is alive")
        try expect(AppSafetyAlert.seen.isEmpty && AppSafetyAlert.answers.count == 1 && app.dirty,
                   "Close forwarding must not prompt, mark the draft discarded or consume the queued Cancel")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Cancel at the application boundary must leave the app running")
        try expect(app.currentURL == a && app.canvas.document == before && app.dirty && app.window.isDocumentEdited &&
                   text.superview === app.canvas && text.undoManager?.canUndo == true && app.historyWindow === history,
                   "Cancelled termination must preserve the current draft, editor, typing history and History window")
        try expect(try app.canvas.snapshotDocumentData() == pending && Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Cancelled main Close must preserve pending text, recovery and saved bytes")

        // Original History Open is an undoable document transaction. Cancelling
        // main Close must not disable it or discard the recoverable prior draft.
        let store = try app.archiveStore()
        let historySnapshot = try historyDrawing("Archived B after cancelled Close", color: .green)
        let historyID = try store.archive(historySnapshot, name: "History B", action: .archived)
        let historyPrompts = AppSafetyAlert.seen.count, prior = try app.historyEditorState()
        app.openHistory(historyID)
        try expect(try app.canvas.snapshotDocumentData() == SkitchFile.decode(historySnapshot.native).canvasData &&
                   app.currentArchiveID == historyID && app.currentURL == nil && app.dirty &&
                   AppSafetyAlert.seen.count == historyPrompts,
                   "History UUID Open after cancelled Close is undoable and does not prompt to discard the prior draft")
        app.undo()
        try expectHistoryState(app, prior, "Undo History after cancelled main Close restores all prior pending text, identity and dirty flags")
        try expect(try Data(contentsOf: recovery) == recovered && Data(contentsOf: a) == savedA,
                   "Undoable History Open leaves the prior recovery and exported original unchanged")

        // Ordinary file replacement retains its separate Cancel/Discard policy.
        let restoredDraft = app.canvas.document
        var documentB = SketchDocument(size: CGSize(width: 123, height: 99))
        documentB.backgroundColor = SketchColor(.green)
        let b = fixture.file("History-B"); try documentB.encoded().write(to: b)
        answer(.alertSecondButtonReturn); app.openURL(b)
        try expect(try app.currentURL == a && app.canvas.document == restoredDraft && app.canvas.snapshotDocumentData() == pending && app.dirty,
                   "File Open must still honor Cancel after cancelled main Close")
        answer(.alertThirdButtonReturn); app.openURL(b)
        try expect(app.currentURL == b && app.canvas.document == documentB && !app.dirty,
                   "Approved file Open must install B with its proper save destination")
        let reopenedText = try editor(app, text: "Protect newer edits in reopened B")
        let reopenedModel = app.canvas.document, reopenedPending = try app.canvas.snapshotDocumentData()
        app.saveRecovery()
        let reopenedRecovery = try Data(contentsOf: recovery)

        // Closing History itself while the editor remains must not request Quit.
        let prompts = AppSafetyAlert.seen.count
        try expect(app.windowShouldClose(history) && AppSafetyTermination.requests == requests,
                   "History Close must be allowed without forwarding another termination request")
        try expect(AppSafetyAlert.seen.count == prompts && app.dirty && reopenedText.superview === app.canvas,
                   "History Close must not ask to discard or mutate the live editor")
        answer(.alertSecondButtonReturn); app.newFile()
        try expect(app.currentURL == b && app.canvas.document == reopenedModel && app.dirty && reopenedText.superview === app.canvas,
                   "New must honor Cancel for newer edits after a cancelled Close and approved file Open")
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
    // Each History case gets its own index under the harness support directory;
    // startup/recovery tests and earlier automatic exports cannot contaminate it.
    static func isolatedHistory(_ app: AppDelegate) throws -> HistoryStore {
        app.historyFollowTimer?.invalidate(); app.historyFollowTimer = nil
        let store = try HistoryStore(directory: app.support.appendingPathComponent("HistorySafety-" + UUID().uuidString))
        app.historyStore = store; app.currentArchiveID = nil
        return store
    }
    static func historyDrawing(_ title: String, color: NSColor = .red) throws -> HistoryStore.Snapshot {
        var document = SketchDocument(size: CGSize(width: 120, height: 90))
        var shape = SketchElement(kind: .rectangle)
        shape.rect = CGRect(x: 12, y: 15, width: 30, height: 20); shape.filled = true; shape.color = SketchColor(color)
        var text = SketchElement(kind: .text)
        text.text = title; text.rect = CGRect(x: 10, y: 40, width: 100, height: 40)
        document.elements = [shape, text]
        return try HistoryStore.Snapshot(canvasData: document.encoded(),
            metadata: .init(root: ["futureHistorySetting": title], originalSize: document.size), preview: nil)
    }
    static func preparePannedHistory(_ app: AppDelegate) throws -> Data {
        let size = CGSize(width: 100, height: 80)
        try app.canvas.loadDocument(data: SketchDocument(size: size).encoded())
        let background = try image(size: size)
        app.canvas.setBackground(background); app.canvas.tool = .select; app.canvas.setZoom(1)
        var shape = SketchElement(kind: .rectangle)
        shape.rect = CGRect(x: 15, y: 20, width: 18, height: 22); shape.color = SketchColor(.red)
        app.canvas.document.elements = [shape]
        app.legacyMetadata = .init(root: ["futureHistorySetting": "A with hidden pixels"], originalSize: size)
        app.canvas.editingUndoManager.removeAllActions()
        let unpanned = try app.canvas.snapshotDocumentData()
        try pan(app, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 85, y: 20))
        let raw = try app.canvas.snapshotDocumentData()
        let object = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        try expect(object["canvasPanBackground"] != nil && raw != unpanned, "History fixture must contain actual hidden pan pixels")
        return unpanned
    }
    static func expectHistoryState(_ app: AppDelegate, _ state: AppDelegate.HistoryEditorState, _ message: String) throws {
        try expect(try app.canvas.snapshotDocumentData() == state.data && app.legacyMetadata == state.metadata &&
                   app.nameField.stringValue == state.name && app.currentURL == state.url &&
                   app.currentArchiveID == state.archiveID && app.dirty == state.dirty && app.window.isDocumentEdited == state.dirty,
                   message)
    }
    static func historyOpenUndoRedo() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        _ = try preparePannedHistory(app)
        let beforeColor = try app.canvas.snapshotDocumentData()
        app.canvas.setBackgroundColor(.yellow)
        app.nameField.stringValue = "A original filename"
        let destination = fixture.file("History-A").deletingPathExtension().appendingPathExtension("skitch")
        app.currentURL = destination
        try expect(app.save(), "Panned A must save successfully before History Open")
        let prior = try app.historyEditorState(), disk = try Data(contentsOf: destination)
        try expect(prior.archiveID != nil && !prior.dirty && app.canvas.editingUndoManager.canUndo,
                   "A must have a clean destination, archive association and pre-existing Undo")
        let snapshotB = try historyDrawing("B archived metadata", color: .green)
        let idB = try store.archive(snapshotB, name: "B filename", action: .archived)
        app.openHistory(idB)
        let opened = try app.historyEditorState(), fileB = try SkitchFile.decode(snapshotB.native)
        try expect(try opened.data == fileB.canvasData && opened.metadata == fileB.metadata && opened.name == "B filename" &&
                   opened.url == nil && opened.archiveID == idB && opened.dirty,
                   "History Open restores B's full native state as an unsaved independent destination")
        app.undo(); try expectHistoryState(app, prior, "Undo History Open restores A's raw pan, metadata, filename, URL, archive and clean flags")
        app.redo(); try expectHistoryState(app, opened, "Redo History Open restores B's complete identity and dirty flags")
        app.undo(); app.undo()
        try expect(try app.canvas.snapshotDocumentData() == beforeColor && app.legacyMetadata == prior.metadata &&
                   app.currentURL == destination && app.currentArchiveID == prior.archiveID && app.dirty,
                   "History Open must retain prior canvas Undo actions without redirecting Save or metadata")
        app.redo(); app.redo()
        try expectHistoryState(app, opened, "Redo can traverse the prior canvas edit and the History Open transaction")
        try expect(try Data(contentsOf: destination) == disk && store.read(prior.archiveID!).canvasData == prior.data,
                   "Opening and traversing History must never overwrite A's exported original or lose its hidden pixels")
    }
    static func historyOpenPendingText() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let destination = try fixture.saveA(), original = try Data(contentsOf: destination)
        app.nameField.stringValue = "Pending A"; app.legacyMetadata = .init(root: ["futureHistorySetting": "pending A"])
        let text = try editor(app, text: "Uncommitted before History Open")
        text.string += " without notification"
        app.dirty = false; app.window.isDocumentEdited = false
        let pending = try app.canvas.snapshotDocumentData(), metadata = app.legacyMetadata
        let id = try store.archive(historyDrawing("Pending B"), name: "B", action: .archived)
        app.openHistory(id); app.undo()
        try expect(try app.canvas.snapshotDocumentData() == pending && app.legacyMetadata == metadata &&
                   app.currentURL == destination && app.nameField.stringValue == "Pending A" && app.currentArchiveID == nil &&
                   app.dirty && app.window.isDocumentEdited,
                   "History Undo must retain the entire previously pending annotation and mark it unsaved even with a stale dirty flag")
        try expect(app.canvas.editingUndoManager.canUndo, "Committing pending text for History must retain its own older Undo action")
        app.undo(); try expect(app.canvas.document.elements.isEmpty, "Older Undo still removes the newly committed annotation")
        app.redo(); try expect(try app.canvas.snapshotDocumentData() == pending, "Redo restores exact text from the pending snapshot")
        app.redo(); try expect(app.currentArchiveID == id && app.currentURL == nil && app.legacyMetadata.root["futureHistorySetting"] == "Pending B",
                               "Redo History after typing Undo restores B's metadata and save destination policy")
        try expect(try Data(contentsOf: destination) == original && AppSafetyAlert.seen.isEmpty,
                   "Undoable History Open neither silently saves the prior file nor asks to discard its recoverable edits")
    }
    static func historyFollowReplacement() throws {
        for replacement in ["new", "native", "capture"] {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
                _ = try preparePannedHistory(app); app.nameField.stringValue = "Follow A"
                try expect(try app.archive(app.historySnapshot(), name: app.safeName(), action: .archived, generation: app.documentGeneration),
                           "History action must attach the current nonempty document")
                let id = app.currentArchiveID!, entry = store.entry(id)!
                let text = try editor(app, text: "Latest pending text for " + replacement), typing = text.undoManager
                app.nameField.stringValue = "Renamed A " + replacement
                if replacement == "new" {
                    try expect(app.historyFollowTimer != nil, "A live edit must schedule the modern latest-copy debounce")
                    try waitForMain("The scheduled History follow must record the latest pending text", until: {
                        (try? store.read(id).document.elements.contains { $0.kind == .text && $0.text == text.string }) == true
                    })
                    try expect(text.superview === app.canvas && text.undoManager === typing && app.canvas.hasPendingTextChanges,
                               "Automatic History debounce must leave the editor and typing Undo intact")
                }
                app.followHistory()
                let followed = try app.canvas.snapshotDocumentData()
                try expect(try store.read(id).canvasData == followed && store.entry(id)?.name == app.safeName() &&
                           store.entry(id)?.date == entry.date && store.entry(id)?.action == entry.action,
                           "Follow writes pending text, hidden pixels and rename while retaining the original action identity/date")
                try expect(text.superview === app.canvas && text.undoManager === typing && app.canvas.hasPendingTextChanges,
                           "Following History must not commit the live annotation editor or replace its typing history")
                app.saveRecovery()
                try expect(try SkitchFile.read(app.support.appendingPathComponent("Recovery.skitch")).canvasData == followed &&
                           text.superview === app.canvas && text.undoManager === typing && app.canvas.hasPendingTextChanges,
                           "Recovery of an associated archive must retain pending text without ending the live editor")
                text.string += " final before replacement"
                let latest = try app.canvas.snapshotDocumentData(), metadata = app.legacyMetadata
                answer(.alertThirdButtonReturn)
                switch replacement {
                case "new": app.newFile()
                case "native":
                    let url = fixture.file("Follow-B").deletingPathExtension().appendingPathExtension("skitch")
                    try historyDrawing("Native replacement B").native.write(to: url)
                    app.openURL(url)
                default: app.receiveCapture(.success(try image()))
                }
                try expect(try app.currentArchiveID == nil && store.entries.count == 1 && store.read(id).canvasData == latest &&
                           store.read(id).metadata == metadata && AppSafetyAlert.answers.isEmpty,
                           "\(replacement) replacement must flush A's latest immutable copy before detaching it")
                app.canvas.setBackgroundColor(.green); app.followHistory()
                try expect(try store.read(id).canvasData == latest && store.entries.count == 1,
                           "Edits to the replacement must not follow into A's previous archive")
            }
        }
    }
    static func historyFailedIndexWrite() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        _ = try preparePannedHistory(app)
        try expect(try app.archive(app.historySnapshot(), name: "Committed A", action: .archived, generation: app.documentGeneration),
                   "History failure fixture must have a committed revision")
        let id = app.currentArchiveID!, entry = store.entry(id)!
        let nativeURL = store.directory.appendingPathComponent(entry.nativeFile), indexURL = store.directory.appendingPathComponent("index.json")
        let native = try Data(contentsOf: nativeURL), index = try Data(contentsOf: indexURL)
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        let text = try editor(app, text: "Keep editor despite failed History follow"), typing = text.undoManager
        let pending = try app.canvas.snapshotDocumentData()
        store.writeIndex = { _, _ in throw Failure(description: "Injected History index failure") }
        defer { store.writeIndex = { try $0.write(to: $1, options: .atomic) } }
        app.followHistory()
        try expect(store.entry(id) == entry && app.currentArchiveID == id && app.status.stringValue.contains("previous archive was preserved"),
                   "Failed follow must retain the committed index, association and actionable status")
        try expect(try Data(contentsOf: nativeURL) == native && Data(contentsOf: indexURL) == index &&
                   Set(FileManager.default.contentsOfDirectory(atPath: store.directory.path)) == files,
                   "Failed index commit preserves every prior byte and cleans only the uncommitted revision")
        let reloaded = try HistoryStore(directory: store.directory)
        try expect(try reloaded.entries == [entry] && reloaded.read(id).canvasData == SkitchFile.decode(native).canvasData,
                   "A fresh store must still read the previous full drawing after the failed update")
        try expect(try !app.archive(app.historySnapshot(), name: "Rejected action", action: .exported, destination: "local-test", generation: app.documentGeneration) &&
                   app.currentArchiveID == id && store.entries == [entry],
                   "A failed new archive cannot replace the previous association or append an index record")
        try expect(try app.canvas.snapshotDocumentData() == pending && text.superview === app.canvas && text.undoManager === typing && app.dirty,
                   "History write failures must preserve the pending document and live typing history")
    }
    static func historySaveOutcomes() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        _ = try preparePannedHistory(app); app.nameField.stringValue = "Saved History A"
        _ = try editor(app, text: "Saved pending text")
        let snapshot = try app.canvas.snapshotDocumentData(), metadata = app.legacyMetadata
        let destination = fixture.file("History-save").deletingPathExtension().appendingPathExtension("skitch")
        app.currentURL = destination
        try expect(app.save(), "Successful native Save")
        let id = app.currentArchiveID!, entry = store.entry(id)!, exported = try Data(contentsOf: destination)
        try expect(try store.entries.count == 1 && entry.action == .exported && entry.destination == destination.path &&
                   entry.name == "Saved History A" && store.read(id).canvasData == snapshot && store.read(id).metadata == metadata &&
                   SkitchFile.decode(exported).canvasData == snapshot && !app.dirty,
                   "Only a successful Save creates an Exported archive with exact saved pending text, pan source and metadata")
        let text = try editor(app, text: "Unsaved after successful export"), pending = try app.canvas.snapshotDocumentData()
        let invalid = app.support.appendingPathComponent("missing-parent-" + UUID().uuidString).appendingPathComponent("failed.skitch")
        let proposed = try SkitchFile(document: CanvasView.validatedDocumentData(pending), metadata: metadata, canvasData: pending)
        let errorTitle: String
        do { try proposed.write(to: invalid); throw Failure(description: "Missing directory write unexpectedly succeeded") }
        catch let failure as Failure { throw failure }
        catch { errorTitle = error.localizedDescription }
        AppSafetyAlert.answers.append(.init(title: errorTitle, response: .alertFirstButtonReturn))
        app.currentURL = invalid
        try expect(!app.save(), "Failed native Save must report failure")
        try expect(try store.entries == [entry] && app.currentArchiveID == id && store.read(id).canvasData == snapshot &&
                   Data(contentsOf: destination) == exported && !FileManager.default.fileExists(atPath: invalid.path),
                   "Failed Save must not archive output, update the prior revision or overwrite the successful export")
        try expect(try app.canvas.snapshotDocumentData() == pending && text.superview === app.canvas && app.dirty,
                   "Failed Save keeps pending edits and the native editor uncommitted")
    }
    static func historyStaleArchiveCompletion() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        _ = try preparePannedHistory(app); app.nameField.stringValue = "Captured output A"
        let captured = try app.historySnapshot(), generation = app.documentGeneration, name = app.safeName()
        let exported = fixture.file("Immutable-output").deletingPathExtension().appendingPathExtension("skitch")
        try captured.native.write(to: exported)
        answer(.alertThirdButtonReturn); app.newFile()
        try app.canvas.loadDocument(data: SkitchFile.decode(historyDrawing("Current B").native).canvasData)
        app.legacyMetadata = .init(root: ["futureHistorySetting": "Current B"])
        app.currentURL = fixture.file("Current-B"); app.nameField.stringValue = "Current B"
        let text = try editor(app, text: "Pending current B"), typing = text.undoManager
        // Seed B's existing association through the store so this regression
        // exercises the stale callback independently of preview-generation bugs.
        let snapshotB = try HistoryStore.Snapshot(canvasData: app.canvas.snapshotDocumentData(), metadata: app.legacyMetadata, preview: nil)
        let idB = try store.archive(snapshotB, name: app.safeName(), action: .archived)
        app.currentArchiveID = idB
        let current = try app.historyEditorState(), entryB = store.entry(idB)!
        var completed = false, archived = false
        DispatchQueue.main.async {
            archived = app.archive(captured, name: name, action: .exported, destination: exported.path, generation: generation)
            completed = true
        }
        try waitForMain("Captured archive callback did not complete", until: { completed })
        try expect(archived && store.entries.count == 2 && store.entry(idB) == entryB, "Stale success creates A's record without following or changing B's record")
        guard let entryA = store.entries.first(where: { $0.id != idB }) else { throw Failure(description: "Missing old-generation archive") }
        let fileA = try store.read(entryA.id), capturedFile = try SkitchFile.decode(captured.native)
        try expect(try fileA.canvasData == capturedFile.canvasData && fileA.metadata == capturedFile.metadata &&
                   entryA.name == name && entryA.action == .exported && entryA.destination == exported.path && Data(contentsOf: exported) == captured.native,
                   "A delayed success archives only the captured immutable bytes/metadata/name, never the replacement drawing")
        try expectHistoryState(app, current, "An old-generation completion must not attach its archive or change the current drawing's identity")
        try expect(text.superview === app.canvas && text.undoManager === typing && app.canvas.hasPendingTextChanges,
                   "Delayed archive completion must retain B's live editor and typing Undo")
    }
    static func historyEmptyAndCancelledOutputs() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let empty = try app.historySnapshot()
        try expect(empty.isEmpty && !app.archive(empty, name: "Empty", action: .exported, destination: "unused", generation: app.documentGeneration),
                   "A blank document cannot create an output archive")
        app.currentURL = fixture.file("Empty-save")
        try expect(app.save() && store.entries.isEmpty && app.currentArchiveID == nil, "A valid blank Save writes the requested file without creating an empty History record")
        _ = try preparePannedHistory(app); let pending = try app.canvas.snapshotDocumentData()
        AppSafetyFilePanel.answers.append(.init(response: .cancel))
        try expect(!app.save(forceChoose: true) && store.entries.isEmpty && app.currentArchiveID == nil,
                   "Cancel Save As cannot create a successful-output archive")
        let savedURL = app.currentURL
        app.startCapture("interactive")
        try expect(try app.canvas.snapshotDocumentData() == pending && app.currentURL == savedURL && app.dirty &&
                   store.entries.isEmpty && app.currentArchiveID == nil && AppSafetyFilePanel.answers.isEmpty && AppSafetyAlert.seen.isEmpty,
                   "A cancelled capture must keep the draft and cannot create an empty or cancelled-output record")
    }
    static func sheetEditingCommands() throws {
        let fixture = try Fixture(), app = fixture.app
        var shape = SketchElement(kind: .rectangle); shape.rect = CGRect(x: 10, y: 10, width: 40, height: 40)
        app.canvas.document.elements = [shape]; app.canvas.selection.removeAll()
        let document = app.canvas.document
        let sheet = AppSafetyWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        let editor = NSTextView(frame: sheet.contentView!.bounds); editor.allowsUndo = true; editor.string = "580"
        sheet.contentView = editor; sheet.makeFirstResponder(editor)
        (app.window as! AppSafetyWindow).simulatedSheet = sheet
        defer { (app.window as! AppSafetyWindow).simulatedSheet = nil; sheet.close() }
        app.selectAll()
        try expect(editor.selectedRange() == NSRange(location: 0, length: 3) && app.canvas.selection.isEmpty,
                   "Sheet Select All must select field text rather than canvas objects")
        try expect(app.activeTextEditor === editor && app.activeUndoManager === editor.undoManager,
                   "Sheet field editor owns command routing and Undo")
        app.deleteSelection()
        try expect(editor.string.isEmpty && app.canvas.document == document,
                   "Sheet Delete removes field text while preserving the editing document")
    }
    static func exportSizingLifecycle() throws {
        let keys = ["ExportFormat", "ExportOriginalSize", "ExportQuality"]
        let defaults = UserDefaults.standard, previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set("png", forKey: "ExportFormat"); defaults.set(false, forKey: "ExportOriginalSize"); defaults.set(0.7, forKey: "ExportQuality")
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        app.canvas.setBackground(try image(size: CGSize(width: 300, height: 180)))
        _ = app.canvas.resizeImage(to: CGSize(width: 150, height: 90))
        let destination = fixture.file("PriorFile"); app.currentURL = destination
        let text = try editor(app, text: "Export should leave me typing")
        let before = try app.canvas.snapshotDocumentData(), live = app.canvas.document, undo = app.canvas.editingUndoManager.undoActionName
        AppSafetyFilePanel.answers.append(.init(response: .cancel)); app.exportFile()
        try expect(try app.canvas.snapshotDocumentData() == before && app.canvas.document == live && text.superview === app.canvas &&
                   app.currentURL == destination && app.canvas.editingUndoManager.undoActionName == undo && store.entries.isEmpty,
                   "Cancelled native Export preserves pending text, output geometry, destination, Undo and History")
        let normal = try app.exportData(format: "png", originalSize: false, jpegQuality: 0.7)
        let full = try app.exportData(format: "png", originalSize: true, jpegQuality: 0.7)
        try expect(NSBitmapImageRep(data: normal)?.pixelsWide == 150 && NSBitmapImageRep(data: full)?.pixelsWide == 300,
                   "App export dispatch uses normal and original-size rendering")
        let svg = String(decoding: try app.exportData(format: "svg", originalSize: false, jpegQuality: 0.7), as: UTF8.self)
        try expect(svg.contains("viewBox=\"0 0 300.000000 180.000000\"") && svg.contains("width=\"150.000000\""),
                   "Ordinary SVG output uses independent dimensions and source viewBox")
        let native = try SkitchFile.decode(app.exportData(format: "skitch", originalSize: false, jpegQuality: 0.7))
        let nativeFull = try SkitchFile.decode(app.exportData(format: "skitch", originalSize: true, jpegQuality: 0.7))
        try expect(native.document.outputSize == CGSize(width: 150, height: 90) && nativeFull.document.outputSize == CGSize(width: 300, height: 180) &&
                   native.document.elements == nativeFull.document.elements && native.document.backgroundPNG == nativeFull.document.backgroundPNG,
                   "Native original-size export changes only the exported copy's output dimensions")
        let target = fixture.file("Output").deletingPathExtension().appendingPathExtension("png")
        AppSafetyFilePanel.answers.append(.init(response: .OK, url: target)); app.exportFile()
        try expect(try Data(contentsOf: target) == normal && app.canvas.snapshotDocumentData() == before && text.superview === app.canvas &&
                   app.currentURL == destination && app.canvas.editingUndoManager.undoActionName == undo,
                   "Successful native Export writes preview-equivalent bytes and preserves editing and save identity")
        try expect(store.entries.count == 1 && store.entries[0].size == CGSize(width: 150, height: 90) &&
                   store.entries[0].text.contains("Export should leave me typing"),
                   "History snapshot keeps the normal output dimensions and pending editable annotation")
    }
    // Exercise the actual shell APIs without ordering the main window or its
    // navigator. A deliberately nonuniform source/output pair detects geometry
    // flattening and accidental use of presentation pixels as source pixels.
    static func viewportFixture(_ app: AppDelegate, drawing: Bool = true) throws {
        app.canvas.newBlank(size: CGSize(width: 300, height: 180))
        if drawing {
            app.canvas.setBackground(try image(size: CGSize(width: 300, height: 180)))
            var element = SketchElement(kind: .rectangle)
            element.rect = CGRect(x: 45, y: 30, width: 24, height: 18)
            element.color = SketchColor(.red); element.groupID = UUID()
            app.canvas.document.elements = [element]; app.canvas.selection = [element.id]
        }
        try expect(app.canvas.setPresentationOutputSize(CGSize(width: 150, height: 90)), "Viewport fixture output")
        app.setCanvasDisplayZoom(1, label: "Test")
        app.canvas.editingUndoManager.removeAllActions()
        app.dirty = false; app.window.isDocumentEdited = false
        try expect(!app.window.isVisible, "Viewport fixtures must remain hidden")
    }
    static func actualViewportHistory() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        app.canvas.setBackgroundColor(.yellow); app.canvas.setBackgroundColor(.green); app.canvas.undo()
        let before = try app.canvas.snapshotDocumentData(), document = app.canvas.document
        let selection = app.canvas.selection, frame = app.window.frame, zoom = app.canvas.zoom
        let history = app.canvas.editingUndoManager
        let undo = history.undoActionName, redo = history.redoActionName
        app.dirty = false; app.window.isDocumentEdited = false
        try expect(app.canToggleActualSize && history.canUndo && history.canRedo, "Actual entry with existing Undo and Redo")
        app.toggleActualSize()
        try expect(app.isActualSize && app.canvas.outputSize == CGSize(width: 300, height: 180) && app.canvas.zoom == 1,
                   "Actual mode presents source resolution")
        try expect(app.canvas.canvasSize == document.size && app.canvas.document.backgroundPNG == document.backgroundPNG &&
                   app.canvas.document.elements == document.elements && app.canvas.selection == selection,
                   "Actual mode retains raw backdrop, editable paths, groups, IDs and selection")
        try expect(!app.dirty && !app.window.isDocumentEdited && history.undoActionName == undo && history.redoActionName == redo,
                   "Mode entry must not add Undo, clear Redo or mark the drawing edited")
        try expect(app.navigatorWindow != nil && app.navigatorWindow?.isVisible == false &&
                   app.window.childWindows?.contains(where: { $0 === app.navigatorWindow }) != true,
                   "Hidden fixture navigator must never be ordered or attached as a visible child")
        app.toggleActualSize()
        try expect(try !app.isActualSize && app.canvas.snapshotDocumentData() == before && app.canvas.zoom == zoom && app.window.frame == frame,
                   "Normal return restores complete document/output, zoom and window frame")
        app.undo()
        try expect(app.canvas.document.backgroundColor == .white && !history.canUndo,
                   "First Undo after a mode roundtrip reaches the existing edit, with no mode Undo")
        app.redo()
        try expect(app.canvas.document == document && history.canRedo, "Roundtrip preserves the existing Redo chain")
    }
    static func textStyleCommands() throws {
        let fixture = try Fixture(), app = fixture.app
        var text = SketchElement(kind: .text); text.text = "Blue text"; text.color = SketchColor(.blue)
        text.fontName = "Courier-Bold"; text.fontSize = 37; text.outlined = false; text.shadowed = false
        text.rect = CGRect(x: 20, y: 20, width: 250, height: 80)
        var shape = SketchElement(kind: .rectangle); shape.rect = CGRect(x: 320, y: 20, width: 100, height: 80)
        app.canvas.document.elements = [text, shape]; app.canvas.selection = [text.id, shape.id]
        let before = try app.canvas.snapshotDocumentData()
        app.chooseFont()
        guard let panel = app.fontPanel as? AppSafetyFontPanel, let form = app.textStyleForm else { throw Failure(description: "Native Font Panel factory") }
        try expect(panel.isVisible && app.window.attachedSheet == nil && panel.accessoryView === form && NSFontManager.shared.target === app, "Font Panel is modeless with original custom effects accessory")
        try expect(app.validModesForFontPanel(panel).rawValue == 7 && NSFontManager.shared.selectedFont?.fontName == "Courier-Bold" && NSFontManager.shared.selectedFont?.pointSize == 37, "Original face size collections mask and selected font")
        try expect(try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo, "Opening Fonts has no document mutation")
        app.chooseFont(); try expect(!panel.isVisible && (try app.canvas.snapshotDocumentData()) == before, "Original Show/Hide toggle does not change artwork")
        app.chooseFont()
        panel.conversion = { _ in NSFont(name: "Helvetica-Bold", size: 48)! }
        form.setChoices(outlined: true, shadowed: true); app.changeFont(NSFontManager.shared)
        let after = app.canvas.document
        try expect(after.elements[0].fontName == "Helvetica-Bold" && after.elements[0].fontSize == 48 && after.elements[0].outlined && after.elements[0].shadowed, "Native font action applies converted font and effects live")
        try expect(after.elements[0].color == text.color && after.elements[1] == shape && panel.isVisible, "Live action leaves colors/shapes intact and keeps Fonts open")
        try expect(app.windowShouldClose(panel) && AppSafetyTermination.requests == 0, "Closing Fonts does not quit the application")
        panel.close(); try expect(!panel.isVisible && app.canvas.document == after, "Closing modeless Fonts retains committed live changes")
        app.canvas.undo(); try expect(try app.canvas.snapshotDocumentData() == before, "App font action is one Undo")
        app.toggleTextShadow(); app.toggleOutline()
        try expect(app.canvas.document.elements[0].fontName == text.fontName && app.canvas.document.elements[0].fontSize == 37 && app.canvas.document.elements[0].outlined && app.canvas.document.elements[0].shadowed && app.canvas.document.elements[1] == shape, "Effect toggles invert selected text rather than stale defaults, preserving fonts and shapes")
        app.canvas.undo(); app.canvas.undo()
        app.defaultTextStyle()
        try expect(app.canvas.document.elements[0].fontSize == 37 && app.canvas.document.elements[0].outlined && app.canvas.document.elements[0].shadowed, "Default menu action preserves selected size")
        let textMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "Text" }!
        let spelling = textMenu.items.compactMap(\.submenu).first { $0.title == "Spelling" }!
        try expect(spelling.items.map { NSStringFromSelector($0.action!) } == ["showGuessPanel:", "checkSpelling:", "toggleContinuousSpellChecking:"] && spelling.items.allSatisfy { $0.target == nil }, "Original spelling selectors retain responder-chain routing")
        try expect(spelling.items.map(\.keyEquivalent) == [":", ";", ""], "Original spelling keyboard equivalents")
    }
    static func fontPanelContextAndPending() throws {
        let fixture = try Fixture(), app = fixture.app
        var a = SketchElement(kind: .text); a.text = "First"; a.fontName = "Helvetica-Bold"; a.fontSize = 23
        a.rect = CGRect(x: 30, y: 30, width: 250, height: 70); a.outlined = false; a.shadowed = true
        var b = a; b.id = UUID(); b.text = "Second"; b.fontSize = 37; b.rect.origin.y = 160; b.outlined = true; b.shadowed = false
        app.canvas.document.elements = [a,b]; app.canvas.selection = [a.id,b.id]
        app.chooseFont()
        let panel = app.fontPanel as! AppSafetyFontPanel, form = app.textStyleForm!
        try expect(NSFontManager.shared.isMultiple && form.outlineChoice == nil && form.shadowChoice == nil, "Different selected effects display original mixed states")
        panel.conversion = { NSFontManager.shared.convert($0, toFamily: "Courier") }
        app.changeFont(NSFontManager.shared)
        for (old,new) in zip([a,b],app.canvas.document.elements) {
            try expect(NSFont(name: new.fontName, size: new.fontSize)?.familyName == "Courier" && new.fontSize == old.fontSize && new.outlined == old.outlined && new.shadowed == old.shadowed, "Panel converts each selected font without flattening mixed sizes or effects")
        }
        app.canvas.zoom = 0.5
        try expect(NSFontManager.shared.selectedFont?.pointSize == 11.5, "Panel follows displayed font scale without modifying source size")
        app.canvas.selection = [b.id]
        try expect(!NSFontManager.shared.isMultiple && NSFontManager.shared.selectedFont?.pointSize == 18.5 && form.outlineChoice == true && form.shadowChoice == false, "Changing selection refreshes the same modeless panel")
        let beforeReplacement = app.canvas.document
        let field = try editor(app, text: "Live field")
        let typing = field.undoManager, caret = field.selectedRange()
        panel.conversion = { NSFontManager.shared.convert($0, toSize: 20) }
        app.changeFont(NSFontManager.shared)
        try expect(field.superview === app.canvas && app.window.firstResponder === field && field.undoManager === typing && field.selectedRange() == caret && panel.isVisible, "Modeless font action retains native typing focus and history")
        let pending = try SketchDocument.decode(app.canvas.snapshotDocumentData())
        try expect(pending.elements.last?.fontSize == 40 && field.font?.pointSize == 20 && app.dirty, "Displayed panel size converts back to source pixels and dirties recovery")
        app.defaultTextStyle()
        let defaults = try SketchDocument.decode(app.canvas.snapshotDocumentData()).elements.last!
        try expect(defaults.fontSize == 40 && defaults.fontName == "Helvetica-Bold" && defaults.outlined && defaults.shadowed && field.superview === app.canvas, "Default Style preserves pending size and native editor")
        app.toggleOutline(); app.toggleOutline(); app.toggleTextShadow(); app.toggleTextShadow()
        let toggled = try SketchDocument.decode(app.canvas.snapshotDocumentData()).elements.last!
        try expect(toggled.outlined && toggled.shadowed && field.superview === app.canvas,
                   "Repeated text-menu toggles use staged effects and retain active typing")
        app.canvas.cancelOperation(nil)
        try expect(app.canvas.document == beforeReplacement, "Cancel abandons new field and its live font changes")
        app.canvas.newBlank(size: NSSize(width: 200, height: 150))
        panel.conversion = { NSFontManager.shared.convert($0, toFamily: "Courier") }
        app.changeFont(NSFontManager.shared)
        try expect(app.canvas.document.elements.isEmpty && app.canvas.fontName.contains("Courier"), "An open panel follows a replaced document and changes only future defaults")
        let future = app.canvas.fontName; app.terminationStarted = true
        panel.conversion = { NSFontManager.shared.convert($0, toFamily: "Helvetica") }
        app.changeFont(NSFontManager.shared); form.outline.performClick(nil)
        try expect(app.canvas.fontName == future && app.canvas.document.elements.isEmpty, "Termination blocks late panel and accessory actions")
    }
    static func resizeSheetPreviewLifecycle() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let before = try app.canvas.snapshotDocumentData(), selection = app.canvas.selection
        let frame = app.window.frame, zoom = app.canvas.zoom
        let history = app.canvas.editingUndoManager
        guard let session = app.makeResizeSession() else { throw Failure(description: "Resize session admission") }
        try expect(app.makeResizeSession() == nil, "A second Resize cannot replace the current preview transaction")
        session.state.edit(.width, text: "75")
        _ = try session.preview()
        try expect(app.canvas.outputSize == CGSize(width: 75, height: 45) && !session.isFinished && !history.canUndo,
                   "Apply previews proportional output without closing or registering Undo")
        session.state.setMode(.crop)
        session.state.edit(.width, text: "80"); session.state.edit(.height, text: "60")
        session.state.anchor = .bottomRight
        _ = try session.preview()
        try expect(app.canvas.canvasSize == CGSize(width: 160, height: 120) && app.canvas.outputSize == CGSize(width: 80, height: 60),
                   "Crop preview uses the original source/output scale, not the earlier resize preview")
        let cropPreview = try app.canvas.snapshotDocumentData()
        session.state.edit(.width, text: "8000"); session.state.edit(.height, text: "4000")
        do { _ = try session.preview(); throw Failure(description: "Oversized crop accepted") }
        catch let failure as Failure { throw failure }
        catch {}
        try expect(try app.canvas.snapshotDocumentData() == cropPreview && !history.canUndo,
                   "Rejected source crop retains the last valid preview and open transaction")
        session.cancel()
        try expect(try app.canvas.snapshotDocumentData() == before && app.canvas.selection == selection &&
                   app.window.frame == frame && app.canvas.zoom == zoom && !app.dirty && !history.canUndo,
                   "Cancel after mixed Apply previews restores exact hidden pixels, selection, window, clean state and Undo")
        guard let accepted = app.makeResizeSession() else { throw Failure(description: "Resize after Cancel") }
        accepted.state.setMode(.crop)
        accepted.state.edit(.width, text: "80"); accepted.state.edit(.height, text: "60")
        accepted.state.anchor = .center
        _ = try accepted.preview()
        accepted.state.edit(.width, text: "60"); accepted.state.edit(.height, text: "30")
        _ = try accepted.apply()
        let final = try app.canvas.snapshotDocumentData()
        try expect(app.canvas.canvasSize == CGSize(width: 120, height: 60) && app.canvas.outputSize == CGSize(width: 60, height: 30)
                   && app.dirty && history.canUndo, "OK applies the latest size from the original crop baseline and records one edit")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before && !history.canUndo && history.canRedo,
                   "One Undo restores all previews at once including retained source pixels")
        app.redo()
        try expect(try app.canvas.snapshotDocumentData() == final, "Redo restores the accepted final crop only")
    }
    static func resizePreviewInterruptionAndSave() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        guard let unopened = app.makeResizeSession() else { throw Failure(description: "Resize without preview") }
        app.canvas.setBackgroundColor(.yellow)
        let editedBeforeApply = try app.canvas.snapshotDocumentData()
        unopened.cancel()
        try expect(try app.canvas.snapshotDocumentData() == editedBeforeApply && app.activeResizeSession == nil,
                   "Cancel without Apply does not revert edits made after panel opening")
        guard let session = app.makeResizeSession() else { throw Failure(description: "Resize save session") }
        session.state.edit(.width, text: "75"); _ = try session.preview()
        session.state.edit(.width, text: "90")
        app.currentURL = fixture.file("resize-preview-save").deletingPathExtension().appendingPathExtension("skitch")
        try expect(app.save() && session.isFinished && app.activeResizeSession == nil && app.canvas.outputSize == CGSize(width: 90, height: 54),
                   "Native Save accepts the latest Resize field values, commits the preview and finishes the session")
        let saved = try app.canvas.snapshotDocumentData()
        session.cancel()
        try expect(try app.canvas.snapshotDocumentData() == saved && !app.dirty,
                   "Cancel after Save cannot restore older preview state with a false clean flag")
        try expect(try SkitchFile.decode(Data(contentsOf: app.currentURL!)).canvasData == saved,
                   "Saved native state matches the committed resize after late Cancel")
        guard let interrupted = app.makeResizeSession() else { throw Failure(description: "Interrupted Resize") }
        interrupted.state.edit(.width, text: "45"); _ = try interrupted.preview()
        app.canvas.setBackgroundColor(.green)
        try expect(interrupted.isFinished && app.activeResizeSession == nil && app.canvas.outputSize == CGSize(width: 90, height: 54),
                   "An independent edit cancels the resize preview before recording its own change")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == saved,
                   "Undo of an interruption restores the accepted resize, never a transient preview")
    }
    static func resizePreviewRecoveryAndHistory() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        try viewportFixture(app); app.canvas.setBackgroundColor(.yellow)
        app.saveHistory(); app.saveRecovery()
        guard let id = app.currentArchiveID else { throw Failure(description: "Resize baseline History") }
        let baseline = try app.canvas.snapshotDocumentData()
        let recovered = try Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch"))
        let entry = store.entry(id), archive = try store.read(id).canvasData
        guard let session = app.makeResizeSession() else { throw Failure(description: "Resize recovery preview") }
        session.state.setMode(.crop); session.state.edit(.width, text: "60"); session.state.edit(.height, text: "40")
        _ = try session.preview()
        try expect(try app.canvas.snapshotDocumentData() != baseline, "Recovery test must have a real preview")
        app.saveRecovery(); app.followHistory()
        try expect(try Data(contentsOf: app.support.appendingPathComponent("Recovery.skitch")) == recovered
                   && store.entry(id) == entry && store.read(id).canvasData == archive,
                   "Timer recovery and History follow cannot persist an unaccepted Resize preview")
        session.cancel()
        try expect(try app.canvas.snapshotDocumentData() == baseline && SkitchFile.decode(recovered).canvasData == baseline,
                   "Cancel and crash recovery both retain the first-Apply baseline")
        guard let next = app.makeResizeSession() else { throw Failure(description: "Resize before History Open") }
        next.state.edit(.width, text: "75"); _ = try next.preview()
        let target = try SkitchFile.decode(historyDrawing("Replacement").native)
        try app.restoreHistoryEditorState(.init(data: target.canvasData, metadata: target.metadata, name: "Replacement",
                                               url: nil, archiveID: nil, dirty: false))
        try expect(next.isFinished && app.activeResizeSession == nil, "History Open cancels Resize before inverse capture")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == baseline,
                   "Undo History Open restores accepted baseline artwork rather than cancelled preview pixels")
    }
    static func resizePreviewGeometryInterruptions() throws {
        for command in ["flatten", "rotate", "flip", "normal"] {
            let fixture = try Fixture(), app = fixture.app
            try viewportFixture(app)
            let baseline = try app.canvas.snapshotDocumentData()
            guard let session = app.makeResizeSession() else { throw Failure(description: "Resize \(command)") }
            session.state.setMode(.crop); session.state.edit(.width, text: "60"); session.state.edit(.height, text: "40")
            _ = try session.preview()
            switch command { case "flatten": app.canvas.flatten()
            case "rotate": app.canvas.rotate(clockwise: true)
            case "normal": app.canvas.setSnapToNormalSize()
            default: app.canvas.flip(horizontal: true) }
            try expect(session.isFinished && app.activeResizeSession == nil, "\(command) cancels Resize before computing geometry")
            let expected = command == "rotate" ? CGSize(width: 180, height: 300) : CGSize(width: 300, height: 180)
            try expect(app.canvas.canvasSize == expected, "\(command) operates on original source size")
            if command == "flatten" {
                let pixels = app.canvas.document.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                try expect(pixels?.width == 300 && pixels?.height == 180, "Flatten renders baseline pixels before cancelling transient crop")
            }
            app.undo()
            try expect(try app.canvas.snapshotDocumentData() == baseline, "\(command) Undo restores baseline source, annotations and output")
        }
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        guard let session = app.makeResizeSession() else { throw Failure(description: "Resize before New") }
        app.newFile()
        try expect(session.isFinished && app.activeResizeSession == nil && app.canvas.canvasSize == CGSize(width: 1000, height: 700),
                   "New before first Apply clears the stale Resize session")
        app.currentURL = fixture.file("new-before-preview-save").deletingPathExtension().appendingPathExtension("skitch")
        try expect(app.save(), "New before first Apply cannot leave Save blocked by an old generation")
    }
    static func actualSaveThenNormal() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let normal = app.canvas.document
        let target = fixture.file("ActualSave").deletingPathExtension().appendingPathExtension("skitch")
        app.currentURL = target; app.toggleActualSize()
        try expect(app.save() && !app.dirty && app.actualView?.savedWhileActive == true, "Save while Actual records its presentation")
        let saved = try SkitchFile.read(target)
        try expect(saved.document.outputSize == normal.size && saved.document.backgroundPNG == normal.backgroundPNG &&
                   saved.document.elements == normal.elements, "Actual Save preserves source and editable geometry")
        app.leaveActualSize()
        try expect(app.canvas.document == normal && app.currentURL == target && app.dirty && app.window.isDocumentEdited &&
                   !app.canvas.editingUndoManager.canUndo,
                   "Restoring normal output after Actual Save marks the output difference dirty without a mode Undo")
        try expect(app.save() && SkitchFile.read(target).document == normal, "Normal-size subsequent Save persists restored output")
    }
    static func actualRejectedReplacement() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app); app.toggleActualSize()
        app.canvas.setBackgroundColor(.yellow)
        let before = try app.canvas.snapshotDocumentData(), generation = app.documentGeneration
        let undo = app.canvas.editingUndoManager.undoActionName
        let valid = fixture.file("ActualCancelled")
        try SketchDocument(size: CGSize(width: 123, height: 99)).encoded().write(to: valid)
        answer(.alertSecondButtonReturn); app.openURL(valid)
        try expect(try app.isActualSize && app.canvas.snapshotDocumentData() == before && app.documentGeneration == generation &&
                   app.canvas.editingUndoManager.undoActionName == undo, "Cancelled Open preserves Actual mode and document/history")
        let invalid = fixture.file("ActualInvalid")
        var rejected = SketchDocument(); rejected.version = 99
        try JSONEncoder().encode(rejected).write(to: invalid)
        answer(.alertThirdButtonReturn)
        AppSafetyAlert.answers.append(.init(title: SketchDocumentError.unsupportedVersion.localizedDescription, response: .alertFirstButtonReturn))
        app.openURL(invalid)
        try expect(try app.isActualSize && app.canvas.snapshotDocumentData() == before && app.documentGeneration == generation &&
                   app.dirty && app.canvas.editingUndoManager.undoActionName == undo,
                   "Validated-before-replacement Open must preserve Actual state even after Discard was chosen")
        app.receiveCapture(.failure(AppSafetyCaptureCoordinator.cancellation))
        try expect(try app.isActualSize && app.canvas.snapshotDocumentData() == before, "Cancelled capture preserves Actual mode")
        let panels = NSApp.windows.count
        app.resize()
        let menu = NSMenuItem(title: "Resize", action: #selector(AppDelegate.resize), keyEquivalent: "")
        try expect(!app.validateMenuItem(menu) && app.resizeButton?.isEnabled == false && NSApp.windows.count == panels && app.isActualSize,
                   "Numeric Resize stays disabled and creates no panel in Actual mode")
    }
    static func actualSuccessfulReplacement() throws {
        for replacement in ["new", "native", "raster", "capture"] {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app
                try viewportFixture(app); app.toggleActualSize()
                let generation = app.documentGeneration
                switch replacement {
                case "new": app.newFile()
                case "native":
                    var document = SketchDocument(size: CGSize(width: 123, height: 99))
                    document.renderSize = CGSize(width: 61, height: 49)
                    let target = fixture.file("ActualNative").deletingPathExtension().appendingPathExtension("skitch")
                    try SkitchFile(document: document, metadata: .init()).write(to: target)
                    app.openURL(target)
                    try expect(app.canvas.document == document, "Native Open retains saved output instead of applying raster fit")
                case "raster":
                    let target = fixture.file("ActualRaster").deletingPathExtension().appendingPathExtension("tiff")
                    guard let bytes = try image(size: CGSize(width: 80, height: 60)).tiffRepresentation else {
                        throw Failure(description: "Raster replacement fixture")
                    }
                    try bytes.write(to: target); app.openURL(target)
                default:
                    app.receiveCapture(.success(try image(size: CGSize(width: 80, height: 60))))
                }
                try expect(!app.isActualSize && app.actualView == nil && app.documentGeneration != generation &&
                           !app.canvas.editingUndoManager.canUndo && app.navigatorWindow?.isVisible != true,
                           "Successful \(replacement) replacement exits Actual mode and clears old undo")
                let after = try app.canvas.snapshotDocumentData()
                app.leaveActualSize()
                try expect(try app.canvas.snapshotDocumentData() == after, "Old normal viewport cannot restore across \(replacement) generation")
            }
        }
    }
    static func borderResizeLifecycle() throws {
        for corner in CanvasCorner.allCases {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app
                try viewportFixture(app)
                let before = try app.canvas.snapshotDocumentData(), source = app.canvas.document
                let left = corner == .topLeft || corner == .bottomLeft
                let width: CGFloat = left ? 130 : 170
                try expect(app.beginWindowGesture(.corner(corner), flags: []), "Begin normal corner transaction")
                try expect(!app.canToggleActualSize && !app.beginWindowGesture(.edge(.left)), "Active border transaction excludes mode changes and nesting")
                app.previewBorderGesture(delta: CGPoint(x: 10, y: 90), flags: [])
                app.previewBorderGesture(delta: CGPoint(x: 20, y: 127), flags: [.shift])
                try expect(app.canvas.outputSize == CGSize(width: width, height: (width * 0.6).rounded()) &&
                           app.canvas.document.elements == source.elements && app.canvas.document.backgroundPNG == source.backgroundPNG &&
                           !app.canvas.editingUndoManager.canUndo,
                           "Normal corner is width-driven, ignores vertical sizing delta/Shift unlock, and previews without Undo")
                app.endWindowGesture()
                let after = try app.canvas.snapshotDocumentData()
                try expect(app.canvas.editingUndoManager.undoActionName == "Resize Image", "Corner completion registers the resize")
                app.undo()
                try expect(try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo,
                           "Multiple corner previews produce exactly one Undo")
                app.redo(); try expect(try app.canvas.snapshotDocumentData() == after, "Corner Redo restores final preview")
            }
        }
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app, drawing: false)
        try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin empty corner")
        app.previewBorderGesture(delta: CGPoint(x: 20, y: 37), flags: [])
        try expect(app.canvas.outputSize == CGSize(width: 170, height: 127), "Empty canvas corner changes axes independently")
        app.endWindowGesture(cancelled: true)
        try expect(app.canvas.outputSize == CGSize(width: 150, height: 90) && !app.canvas.editingUndoManager.canUndo,
                   "Cancelled empty resize leaves no Undo")
    }
    static func borderCropPanLifecycle() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        try pan(app, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 20))
        let before = try app.canvas.snapshotDocumentData(), source = app.canvas.document
        let frame = app.window.frame, selection = app.canvas.selection
        let pixels = app.canvas.imageData(format: "png")
        let graph = try JSONSerialization.jsonObject(with: before) as! [String: Any]
        try expect(graph["canvasPanBackground"] != nil, "Border fixture must include offscreen pan pixels")
        app.canvas.editingUndoManager.removeAllActions()
        try expect(app.beginWindowGesture(.edge(.left)), "Begin symmetric crop")
        app.previewBorderGesture(delta: CGPoint(x: 5, y: 99), flags: [.option])
        app.previewBorderGesture(delta: CGPoint(x: 15, y: 99), flags: [.option])
        try expect(app.canvas.canvasSize == CGSize(width: 240, height: 180) && app.canvas.outputSize == CGSize(width: 120, height: 90) &&
                   app.canvas.document.elements[0].bounds.minX == source.elements[0].bounds.minX - 30 &&
                   app.canvas.document.elements[0].rect == source.elements[0].rect &&
                   app.canvas.selection == selection, "Option-left crops both edges at output/source density and translates the editable annotation")
        app.endWindowGesture(cancelled: true)
        try expect(try app.canvas.snapshotDocumentData() == before && app.canvas.imageData(format: "png") == pixels &&
                   app.window.frame == frame && !app.canvas.editingUndoManager.canUndo,
                   "Crop cancellation restores full pan graph, pixels, selection/window and history")
        try expect(app.beginWindowGesture(.edge(.left)), "Restart crop after Cancel")
        app.previewBorderGesture(delta: CGPoint(x: CGFloat.nan, y: 0), flags: [.option])
        try expect(try app.canvas.snapshotDocumentData() == before, "Invalid crop preview cannot mutate state")
        app.previewBorderGesture(delta: CGPoint(x: 15, y: 0), flags: [.option])
        app.endWindowGesture()
        let after = try app.canvas.snapshotDocumentData()
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before && app.canvas.imageData(format: "png") == pixels &&
                   !app.canvas.editingUndoManager.canUndo, "Committed crop is one Undo including hidden source pixels")
        app.redo(); try expect(try app.canvas.snapshotDocumentData() == after, "Crop Redo retains the complete cropped pan state")
    }
    static func rasterFitAndCameraOutput() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let capacity = app.maximumNormalCanvas else { throw Failure(description: "Hidden fixture needs a screen capacity") }
        let size = CGSize(width: ceil(capacity.width + 300), height: ceil(capacity.height + 150))
        try expect(SketchDocument.validSize(size), "Bounded large raster fixture")
        let raster = try image(size: size)
        app.receiveCapture(.success(raster), discardAlreadyApproved: true)
        let background = app.canvas.document.backgroundPNG
        try expect(app.canvas.canvasSize == size && app.canvas.outputSize.width < size.width && app.canvas.outputSize.height < size.height &&
                   app.isLargeShot && !app.canvas.editingUndoManager.canUndo,
                   "Ordinary capture fits output to the screen while retaining raw source dimensions")
        app.dragOriginalControl.state = .off; try expect(!app.dragAtOriginalSize, "Large-shot unchecked drag uses normal output")
        app.dragOriginalControl.state = .on; try expect(app.dragAtOriginalSize, "Large-shot checked drag uses source output")
        app.toggleActualSize(); app.dragOriginalControl.state = .off
        try expect(app.dragAtOriginalSize && app.canvas.document.backgroundPNG == background,
                   "Actual drag forces original size without replacing source pixels")
        AppSafetyCaptureCoordinator.holdCapture = true
        app.cameraSnap()
        try expect(AppSafetyCaptureCoordinator.requests.last == "camera" && AppSafetyCaptureCoordinator.captureCallbacks.count == 1,
                   "Camera test must use the wired callback")
        let callback = AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()
        answer(.alertThirdButtonReturn)
        callback(.success(raster))
        // Capture adapters currently deliver synchronously; queued main-actor
        // delivery is also accepted without a desktop capture request.
        try waitForMain("Camera completion", until: { !app.isActualSize })
        try expect(app.canvas.canvasSize == size && app.canvas.outputSize == size && app.canvas.document.backgroundPNG == background,
                   "Camera fitOutput:false exits Actual and retains full output instead of automatic screen fitting")
        app.dragOriginalControl.state = .off
        try expect(!app.dragAtOriginalSize, "Normal mode does not force full-size drag solely because it followed Actual")
    }
    static func actualEditUndoNormalOutput() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let before = try app.canvas.snapshotDocumentData()
        app.toggleActualSize(); app.canvas.setBackgroundColor(.yellow); app.leaveActualSize()
        let edited = try app.canvas.snapshotDocumentData()
        try expect(app.canvas.outputSize == CGSize(width: 150, height: 90), "Actual edit exits to prior normal output")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before && app.canvas.outputSize == CGSize(width: 150, height: 90) &&
                   !app.isActualSize && !app.canvas.editingUndoManager.canUndo,
                   "Undo of an Actual edit after exit cannot resurrect transient full-size output")
        app.redo()
        try expect(try app.canvas.snapshotDocumentData() == edited && app.canvas.outputSize == CGSize(width: 150, height: 90),
                   "Redo of an Actual edit remains normalized to normal output")
    }
    static func actualPriorResizeHistory() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let normal = try app.canvas.snapshotDocumentData(), source = app.canvas.document
        let selection = app.canvas.selection, frame = app.window.frame
        let history = app.canvas.editingUndoManager
        func expectPixels(_ size: CGSize, _ message: String) throws {
            guard let data = app.canvas.imageData(format: "png"), let bitmap = NSBitmapImageRep(data: data) else {
                throw Failure(description: "Resize history PNG fixture")
            }
            try expect(bitmap.pixelsWide == Int(size.width) && bitmap.pixelsHigh == Int(size.height) &&
                       app.canvas.document.backgroundPNG == source.backgroundPNG &&
                       app.canvas.document.elements == source.elements && app.canvas.selection == selection,
                       message)
        }
        try expect(app.canvas.resizeImage(to: CGSize(width: 120, height: 72)), "Seed normal resize Undo")
        let resized = try app.canvas.snapshotDocumentData()
        try expectPixels(CGSize(width: 120, height: 72), "Normal resize changes exported pixels while retaining source and editable geometry")
        app.toggleActualSize(); app.undo()
        try expect(app.isActualSize && app.canvas.outputSize == source.size && !history.canUndo && history.canRedo,
                   "Undo in Actual updates persistent normal output without losing full-resolution presentation or Redo")
        try expectPixels(source.size, "Actual Undo still exports full-resolution pixels without scaling annotations")
        app.leaveActualSize()
        try expect(try !app.isActualSize && app.canvas.snapshotDocumentData() == normal && app.window.frame == frame &&
                   !history.canUndo && history.canRedo,
                   "Leaving Actual restores the normal output reached by Undo rather than the entry output, preserving Redo")
        try expectPixels(CGSize(width: 150, height: 90), "Actual exit exports the restored 150-pixel normal output")
        app.redo()
        try expect(try app.canvas.snapshotDocumentData() == resized && history.canUndo && !history.canRedo,
                   "Redo after Actual exit restores the original 120-pixel resize as the only edit")
        try expectPixels(CGSize(width: 120, height: 72), "Redo restores resized export pixels with full source retained")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == normal && !history.canUndo && history.canRedo,
                   "A second Undo returns to 150 pixels without consuming or inserting mode history")
        try expectPixels(CGSize(width: 150, height: 90), "Final Undo restores normal export pixels and selection")
    }
    static func shiftCornerResetBaseline() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let normal = try app.canvas.snapshotDocumentData(), source = app.canvas.document
        app.setCanvasDisplayZoom(2, label: "Test")
        app.setWindowFrame(CGRect(x: 250, y: 200, width: 1400, height: 1000))
        guard let scroll = app.canvas.enclosingScrollView else { throw Failure(description: "Shift corner viewport") }
        app.window.contentView?.layoutSubtreeIfNeeded()
        let oldFrame = app.window.frame
        let chrome = CGSize(width: oldFrame.width - scroll.contentView.bounds.width,
                            height: oldFrame.height - scroll.contentView.bounds.height)
        let expected = CGSize(width: max(app.window.minSize.width, chrome.width + 300 + 20),
                              height: max(app.window.minSize.height, chrome.height + 180 + 20))
        try expect(!app.isLargeShot, "Shift reset fixture must be eligible for normal-size reset")
        try expect(app.beginWindowGesture(.corner(.bottomRight), flags: [.shift]), "Begin Shift corner reset")
        guard let gesture = app.windowGesture else { throw Failure(description: "Shift corner baseline") }
        let reset = try app.canvas.snapshotDocumentData(), fittedFrame = app.window.frame
        try expect(app.canvas.outputSize == source.size && app.canvas.zoom == 1 &&
                   abs(fittedFrame.width - expected.width) < 0.5 && abs(fittedFrame.height - expected.height) < 0.5 &&
                   fittedFrame.size != oldFrame.size && gesture.windowFrame == fittedFrame &&
                   gesture.outputSize == source.size && gesture.zoom == 1,
                   "Shift resets full normal output and fits the window before recording the drag baseline")
        app.previewBorderGesture(delta: CGPoint(x: 20, y: 99), flags: [.shift])
        try expect(app.canvas.outputSize == CGSize(width: 320, height: 192) &&
                   app.canvas.document.backgroundPNG == source.backgroundPNG && app.canvas.document.elements == source.elements,
                   "Corner preview starts at reset output and zoom, retaining full source and editable geometry")
        app.endWindowGesture(cancelled: true)
        try expect(try app.canvas.snapshotDocumentData() == reset && app.window.frame == fittedFrame,
                   "Escape restores the fitted Shift baseline rather than the preceding smaller output or oversized window")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == normal && !app.canvas.editingUndoManager.canUndo,
                   "Shift normal-size reset remains one Undo; canceled corner preview adds none")
        app.redo()
        try expect(try app.canvas.snapshotDocumentData() == reset && !app.canvas.editingUndoManager.canRedo,
                   "Redo restores only the Shift output reset")
        try expect(!app.window.isVisible, "Shift sizing must never order the hidden test window")
    }
    static func largeRasterBorderHistoryRestoresWindow() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        app.canvas.setBackground(try image(size: CGSize(width: 3000, height: 2000)))
        try expect(app.canvas.setPresentationOutputSize(CGSize(width: 1350, height: 900)), "Large native document output")
        app.setCanvasDisplayZoom(1, label: "Test")
        app.sizeNormalWindowToCanvas(); app.updateStatus()
        app.canvas.editingUndoManager.removeAllActions()
        let before = try app.canvas.snapshotDocumentData(), source = app.canvas.document
        let frame = app.window.frame, history = app.canvas.editingUndoManager
        var windowFailures: [String] = []
        func recordWindowRestore(_ route: String) {
            if app.window.frame.size != frame.size || abs(app.window.frame.minX - frame.minX) >= 0.5 ||
                abs(app.window.frame.maxY - frame.maxY) >= 0.5 {
                windowFailures.append("\(route): expected \(frame), got \(app.window.frame)")
            }
        }
        func expectVisible(_ message: String) throws {
            try expect(app.canvas.visibleRect.contains(app.canvas.bounds.insetBy(dx: 0.5, dy: 0.5)) &&
                       !app.canvasBorder.isHidden && !app.window.isVisible,
                       message)
        }
        try expectVisible("Fitted large-source output must be fully visible with crop border available in the hidden fixture")
        try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin large-source corner shrink")
        app.previewBorderGesture(delta: CGPoint(x: -80, y: -70), flags: [])
        app.endWindowGesture()
        let resized = try app.canvas.snapshotDocumentData(), resizedFrame = app.window.frame
        try expect(app.canvas.outputSize == CGSize(width: 1270, height: 847) && resizedFrame.width < frame.width &&
                   resizedFrame.height < frame.height && history.canUndo && !history.canRedo &&
                   history.undoActionName == "Resize Image", "Large source corner produces one proportional output resize")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before && app.window.frame.size == frame.size &&
                   abs(app.window.frame.minX - frame.minX) < 0.5 && abs(app.window.frame.maxY - frame.maxY) < 0.5 &&
                   !history.canUndo && history.canRedo,
                   "App Undo restores 1350x900 output and fitted window at the same top-left, without another history entry")
        try expectVisible("Undo must reveal the entire restored canvas and crop border instead of leaving a shrunk scrolling viewport")
        app.redo()
        try expect(try app.canvas.snapshotDocumentData() == resized && history.canUndo && !history.canRedo,
                   "App Redo restores the exact resized document and single resize history entry")
        if app.window.frame.size != resizedFrame.size {
            windowFailures.append("Menu Redo: expected size \(resizedFrame.size), got \(app.window.frame.size)")
        }
        try expect(app.canvas.document.backgroundPNG == source.backgroundPNG && app.canvas.document.elements == source.elements &&
                   app.canvas.canvasSize == CGSize(width: 3000, height: 2000),
                   "App Redo retains the original 3000x2000 pixels and editable geometry")
        try expectVisible("Redo keeps the smaller output completely visible with crop border available")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before &&
                   !history.canUndo && history.canRedo, "Repeated Undo restores the original fitted window without stack drift")
        recordWindowRestore("Second menu Undo")
        try expectVisible("Repeated Undo keeps the full restored output and border visible")
        try expect(app.window.makeFirstResponder(app.canvas), "Focus canvas for keyboard history dispatch")
        func historyKey(redo: Bool) throws {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: redo ? [.command, .shift] : [.command], timestamp: 0,
                windowNumber: app.window.windowNumber, context: nil, characters: redo ? "Z" : "z",
                charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6) else {
                throw Failure(description: "Internal canvas history key event")
            }
            try expect(app.canvas.performKeyEquivalent(with: event), "Canvas must consume its focused history shortcut")
        }
        try historyKey(redo: true)
        try expect(try app.canvas.snapshotDocumentData() == resized &&
                   history.canUndo && !history.canRedo,
                   "Canvas Command-Shift-Z must refit the resized window through the launched history callback")
        if app.window.frame.size != resizedFrame.size {
            windowFailures.append("Keyboard Redo: expected size \(resizedFrame.size), got \(app.window.frame.size)")
        }
        try expectVisible("Keyboard Redo keeps the entire canvas and crop border available")
        try historyKey(redo: false)
        try expect(try app.canvas.snapshotDocumentData() == before &&
                   !history.canUndo && history.canRedo,
                   "Canvas Command-Z restores fitted normal output at the original top-left without extra Undo")
        recordWindowRestore("Keyboard Undo")
        try expectVisible("Keyboard Undo must reveal the full restored output and crop border")
        try expect(windowFailures.isEmpty, "Window restoration must not drift across menu/keyboard history: " + windowFailures.joined(separator: "; "))
    }
    static func borderSaveThenCancel() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let before = try app.canvas.snapshotDocumentData()
        app.currentURL = fixture.file("BorderSave").deletingPathExtension().appendingPathExtension("skitch")
        try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin border edit before Save")
        app.previewBorderGesture(delta: CGPoint(x: 40, y: 100), flags: [])
        let preview = try app.canvas.snapshotDocumentData()
        try expect(preview != before && app.save(), "Save must accept the current viewport preview")
        let saved = try SkitchFile.read(app.currentURL!)
        try expect(app.windowGesture == nil && saved.canvasData == preview && !app.dirty,
                   "Save closes/commits border transaction before serializing the exact live state")
        app.endWindowGesture(cancelled: true)
        try expect(try app.canvas.snapshotDocumentData() == saved.canvasData && !app.dirty && !app.window.isDocumentEdited,
                   "Escape after successful Save cannot restore an older viewport while falsely clean")
        app.undo()
        try expect(try app.canvas.snapshotDocumentData() == before && app.dirty && app.window.isDocumentEdited &&
                   !app.canvas.editingUndoManager.canUndo, "Saved border change remains exactly one undoable, dirty-on-Undo edit")
    }
    static func borderInterruptedByCommands() throws {
        for command in ["paste", "wipe"] {
            try autoreleasepool {
                let fixture = try Fixture(), app = fixture.app
                try viewportFixture(app)
                let before = try app.canvas.snapshotDocumentData(), frame = app.window.frame
                try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin interrupted border gesture")
                app.previewBorderGesture(delta: CGPoint(x: 60, y: 100), flags: [])
                if command == "paste" {
                    // Redirect only this synchronous command to an isolated board;
                    // neither read nor modify the user's system clipboard.
                    let board = NSPasteboard.withUniqueName()
                    guard let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard")),
                          let replacement = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("appSafetyGeneralPasteboard")) else {
                        throw Failure(description: "Isolated general-pasteboard test adapter")
                    }
                    let original = method_getImplementation(general)
                    AppSafetyClipboard.board = board
                    method_setImplementation(general, method_getImplementation(replacement))
                    defer {
                        method_setImplementation(general, original); AppSafetyClipboard.board = nil; board.releaseGlobally()
                    }
                    board.setString("Paste during border drag", forType: .string)
                    app.window.makeFirstResponder(app.canvas); app.paste()
                    try expect(app.canvas.document.elements.count == 2 && app.canvas.document.elements.last?.text == "Paste during border drag",
                               "Paste interruption must perform a real editable text paste")
                } else {
                    app.wipe()
                    try expect(app.canvas.document.elements.isEmpty && app.canvas.document.backgroundPNG != nil,
                               "First Wipe interruption removes drawing while retaining the snap")
                }
                try expect(app.windowGesture == nil && app.canvas.outputSize == CGSize(width: 150, height: 90) && app.window.frame == frame,
                           "\(command) cancels both Canvas preview and shell window geometry")
                let after = try app.canvas.snapshotDocumentData()
                app.endWindowGesture(cancelled: true)
                try expect(try app.canvas.snapshotDocumentData() == after, "Late mouse-up/Escape cannot revert \(command)")
                app.undo()
                try expect(try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo,
                           "\(command) records its own edit without leaving a border Undo")
            }
        }
    }
    static func actualNavigatorAndGates() throws {
        let fixture = try Fixture(), app = fixture.app
        try viewportFixture(app)
        let menu = NSMenuItem(title: "Actual", action: #selector(AppDelegate.toggleActualSize), keyEquivalent: "")
        for blocked in ["frame", "termination"] {
            let before = try app.canvas.snapshotDocumentData()
            app.frameMode = blocked == "frame"; app.terminationStarted = blocked == "termination"
            app.updateViewportChrome()
            try expect(!app.canToggleActualSize && !app.validateMenuItem(menu) && app.actualButton?.isEnabled == false,
                       "Actual button and menu both reject \(blocked)")
            app.toggleActualSize()
            try expect(try !app.isActualSize && app.canvas.snapshotDocumentData() == before, "Blocked \(blocked) toggle cannot mutate output")
            app.frameMode = false; app.terminationStarted = false
        }
        app.canvas.document.size = CGSize(width: 2000, height: 1500)
        try expect(app.canvas.setPresentationOutputSize(CGSize(width: 500, height: 375)), "Scrollable navigator fixture")
        app.updateViewportChrome(); app.toggleActualSize()
        guard let scroll = app.canvas.enclosingScrollView, let panel = app.navigatorWindow,
              let navigate = app.navigator.onNavigate else { throw Failure(description: "Actual navigator launch wiring") }
        try expect(!panel.isVisible && panel.frame.minX == app.window.frame.minX - panel.frame.width + 5 &&
                   panel.frame.minY == app.window.frame.minY + 30, "Hidden child navigator stays beside the parent's left edge")
        let before = try app.canvas.snapshotDocumentData()
        func dragNavigator(to point: CGPoint) throws {
            guard let rect = NavigatorGeometry.imageRect(documentSize: app.navigator.documentSize, bounds: app.navigator.bounds) else {
                throw Failure(description: "Navigator thumbnail geometry")
            }
            for (type, pointer) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: rect.midX, y: rect.midY)),
                                    (.leftMouseDragged, point), (.leftMouseUp, point)] {
                let location = app.navigator.convert(pointer, to: nil)
                guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                    throw Failure(description: "Internal navigator event allocation")
                }
                switch type {
                case .leftMouseDown: app.navigator.mouseDown(with: event)
                case .leftMouseDragged: app.navigator.mouseDragged(with: event)
                default: app.navigator.mouseUp(with: event)
                }
            }
        }
        try dragNavigator(to: CGPoint(x: 100_000, y: 100_000))
        let visible = app.canvas.visibleRect
        try expect(visible.minX >= 0 && visible.minY >= 0 && visible.maxX <= app.canvas.bounds.maxX + 0.5 &&
                   visible.maxY <= app.canvas.bounds.maxY + 0.5 && app.navigator.viewport == visible,
                   "Navigator drag through wired onNavigate clamps to the current visible canvas and synchronizes overview highlight: \(visible), canvas \(app.canvas.bounds), highlight \(app.navigator.viewport)")
        try dragNavigator(to: CGPoint(x: -100_000, y: -100_000))
        try expect(app.canvas.visibleRect.origin == .zero && app.navigator.viewport == app.canvas.visibleRect &&
                   scroll.contentView.bounds.origin == .zero, "Navigator clamps negative origin at top left")
        try expect(try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo,
                   "Overview navigation changes viewport only, not serialized document/history")
        app.leaveActualSize(); let origin = scroll.contentView.bounds.origin
        navigate(CGPoint(x: 500, y: 500))
        try expect(scroll.contentView.bounds.origin == origin, "Stale navigator callback cannot move the normal viewport")
    }
    static func main() {
        guard let evidence = ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"],
              ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] != nil else {
            fputs("Run tools/test-app-safety.sh for isolated execution.\n", stderr); exit(2)
        }
        NSFontManager.setFontPanelFactory(AppSafetyFontPanel.self)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        guard NSFontManager.shared.fontPanel(true) is AppSafetyFontPanel else {
            fputs("Font panel test factory failed; no window will be ordered.\n", stderr); exit(2)
        }
        if CommandLine.arguments.contains("--native-idle-termination") {
            let delegate = AppSafetyNativeTerminationDelegate(evidence: URL(fileURLWithPath: evidence))
            NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            fputs("Native termination returned without exiting.\n", stderr); exit(1)
        }
        let tests: [(String, () throws -> Void)] = [
            ("Text context/font/default/shadow actions and original spelling responder routes", textStyleCommands),
            ("Modeless Fonts follows mixed selections scale pending editors and document replacement", fontPanelContextAndPending),
            ("Resize Apply previews from one baseline; Cancel restores all state; OK commits one crop Undo", resizeSheetPreviewLifecycle),
            ("Resize first-Apply baseline, native Save and independent edits prevent stale preview rollback", resizePreviewInterruptionAndSave),
            ("Resize previews cannot overwrite recovery/History or enter Open History Undo", resizePreviewRecoveryAndHistory),
            ("Flatten/Rotate/Flip and New interrupt Resize before reading source geometry", resizePreviewGeometryInterruptions),
            ("Actual mode preserves raw source, geometry, selection and existing Undo/Redo without ordering a navigator", actualViewportHistory),
            ("Actual Save then Normal restores output and marks the unsaved size difference dirty", actualSaveThenNormal),
            ("cancelled/invalid Open and capture preserve Actual; numeric Resize is denied", actualRejectedReplacement),
            ("successful New/native/raster/capture replacement exits Actual across generations", actualSuccessfulReplacement),
            ("normal corners are width-driven, blank axes independent, with one resize Undo", borderResizeLifecycle),
            ("Option crop Cancel/Undo/Redo retains hidden pan pixels, selection and editable geometry", borderCropPanLifecycle),
            ("ordinary raster fitting and camera full output retain raw source and drag original-size gates", rasterFitAndCameraOutput),
            ("Undo/Redo after Actual edit and exit cannot restore transient full output", actualEditUndoNormalOutput),
            ("normal resize Undo in Actual survives exit, Redo and Undo with correct export pixels", actualPriorResizeHistory),
            ("Shift corner resets output and fits the window before the cancelable drag baseline", shiftCornerResetBaseline),
            ("large-source corner Undo/Redo restores fitted window, full visible canvas and crop border", largeRasterBorderHistoryRestoresWindow),
            ("Save commits border preview so later Escape cannot create a false-clean mismatch", borderSaveThenCancel),
            ("Paste/Wipe cancel border Canvas and window together before recording their own edit", borderInterruptedByCommands),
            ("Actual button/menu gating and hidden navigator clamped viewport callback", actualNavigatorAndGates),
            ("native sheet text commands target the sheet field editor", sheetEditingCommands),
            ("native Export cancellation/success, original size and SVG preserve editing", exportSizingLifecycle),
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
            ("main Close hides with History alive; explicit Quit Discard and Cancel protect later edits", mainCloseLifecycle),
            ("Close Hide and Minimize preserve pending typing; reopen and inactive toggle restore the same session", {
                let fixture = try Fixture(), app = fixture.app
                (app.window as! AppSafetyWindow).simulatesVisibility = true
                (app.window as! AppSafetyWindow).shown = true
                let key = "statusMenu", previous = UserDefaults.standard.object(forKey: key)
                defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }; AppSafetyActivation.isActive = true }
                UserDefaults.standard.set(0, forKey: key)
                app.timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in }
                let destination = try fixture.saveA(), saved = try Data(contentsOf: destination)
                let editor = try editor(app, text: "Keep this pending draft while hidden")
                let pending = try app.canvas.snapshotDocumentData(), generation = app.documentGeneration
                let frame = app.window.frame, undo = editor.undoManager, caret = editor.selectedRange()
                app.toggleVisible()
                try expect(!app.window.isVisible && !app.window.isMiniaturized && !app.terminationStarted && app.dirty && app.currentURL == destination,
                           "Default presence hides the editor without miniaturizing, discarding or terminating")
                try expect(app.timer!.fireDate.timeIntervalSinceNow > 1_000 && AppSafetyAlert.seen.isEmpty && AppSafetyTermination.requests == 0,
                           "Hidden document timer is paused and no Quit decision is reached")
                try expect(!app.applicationShouldTerminateAfterLastWindowClosed(NSApp), "A hidden editor must keep the app alive")
                _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
                try expect(app.window.isVisible && !app.window.isMiniaturized && app.window.frame == frame && app.timer!.fireDate.timeIntervalSinceNow <= 15,
                           "Dock reopen restores the editor even while an auxiliary window is visible")
                try expect(try app.canvas.snapshotDocumentData() == pending && app.documentGeneration == generation && editor.superview === app.canvas && editor.undoManager === undo && editor.selectedRange() == caret && Data(contentsOf: destination) == saved,
                           "Hide/reopen preserves pending typing, Undo, selection, generation, geometry and saved bytes")
                AppSafetyActivation.isActive = false; app.toggleVisible()
                try expect(app.window.isVisible, "Inactive toggle activates the existing editor instead of hiding it")
                AppSafetyActivation.isActive = true
                app.vanish(); app.vanish()
                try expect(!app.window.isVisible, "Minimize on an already hidden editor cannot reopen it")
                app.makeVisible()
                let sheet = AppSafetyWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
                (app.window as! AppSafetyWindow).simulatedSheet = sheet
                app.toggleVisible(); try expect(app.window.isVisible, "A live modal sheet prevents hiding the editor")
                (app.window as! AppSafetyWindow).simulatedSheet = nil
                UserDefaults.standard.set(2, forKey: key); app.toggleVisible()
                try expect(app.window.isMiniaturized && !app.window.isVisible, "Dock-only presence follows original native miniaturization branch")
                app.makeVisible()
                try expect(app.window.isVisible && !app.window.isMiniaturized, "Dock-only restore deminiaturizes the same editor")
                app.terminationStarted = true; app.toggleVisible(); app.makeVisible()
                try expect(app.window.isVisible, "Termination blocks late visibility mutations")
                app.terminationStarted = false
            }),
            ("Quit Save persists pending text and clears recovery", quitSave),
            ("Drag export snapshots remain immutable across successful, cancelled and failed promises", {
                let view = DragExportView(frame: NSRect(x: 0, y: 0, width: 115, height: 50))
                var begun: [UUID] = [], left: [UUID] = [], ended: [(UUID, Bool)] = [], failed: [UUID] = [], deliveries: [URL] = []
                view.onBegin = { begun.append($0) }; view.onLeaveControl = { left.append($0) }
                view.onEnd = { ended.append(($0, $1)) }; view.onDeliveryFailure = { failed.append($0) }
                let bytes = Data("immutable promised image".utf8)
                let payload = DragExportView.Payload(data: bytes, name: "Captured drawing", format: "jpg", delivered: { deliveries.append($0) })
                let rect = NSRect(x: 100, y: 200, width: 115, height: 50)
                let provider = NSFilePromiseProvider(fileType: UTType.jpeg.identifier, delegate: view)
                try expect(view.beginExport(provider: provider, payload: payload, controlRect: rect), "A prepared export starts once")
                try expect(!view.beginExport(provider: NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: view), payload: payload, controlRect: rect), "A held mouse drag cannot start a second promise")
                view.moveExport(to: NSPoint(x: 110, y: 210)); try expect(left.isEmpty, "Inside Drag Me cannot iconify the editor")
                view.moveExport(to: NSPoint(x: 300, y: 210)); try expect(left == begun, "Crossing the screen-space boundary requests iconify for that export")
                try expect(view.filePromiseProvider(provider, fileNameForType: UTType.jpeg.identifier) == "Captured drawing.jpg", "Filename and selected format belong to the captured promise")
                let destination = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"]!).appendingPathComponent("promised-drawing.jpg")
                var completionError: Error?
                view.filePromiseProvider(provider, writePromiseTo: destination) { completionError = $0 }
                try expect(completionError == nil && (try Data(contentsOf: destination)) == bytes && deliveries == [destination], "Delivery writes captured bytes and archives only after a successful write")
                view.endExport(provider: ObjectIdentifier(provider), succeeded: true)
                try expect(ended.count == 1 && ended[0].0 == begun[0] && ended[0].1, "Delivery before the native end callback still leaves the right thumbnail expandable")
                let cancelled = NSFilePromiseProvider(fileType: UTType.jpeg.identifier, delegate: view)
                try expect(view.beginExport(provider: cancelled, payload: payload, controlRect: rect), "A second export starts after the first finishes")
                view.endExport(provider: ObjectIdentifier(cancelled), succeeded: false)
                view.filePromiseProvider(cancelled, writePromiseTo: destination) { completionError = $0 }
                try expect(completionError != nil && deliveries.count == 1 && failed.isEmpty && !ended[1].1, "Cancelled promise cannot overwrite or archive an existing output")
                let unwritable = NSFilePromiseProvider(fileType: UTType.jpeg.identifier, delegate: view)
                try expect(view.beginExport(provider: unwritable, payload: payload, controlRect: rect), "Failure fixture starts")
                view.endExport(provider: ObjectIdentifier(unwritable), succeeded: true)
                view.filePromiseProvider(unwritable, writePromiseTo: destination.appendingPathComponent("missing/image.jpg")) { completionError = $0 }
                try expect(completionError != nil && failed == [begun[2]] && deliveries.count == 1, "A delayed write failure identifies only its own thumbnail and never archives")
            }),
            ("Drag thumbnail uses original geometry and restores document, committed text and Undo", {
                let fixture = try Fixture(), app = fixture.app, window = fixture.app.window as! AppSafetyWindow
                window.simulatesVisibility = true; window.shown = true
                app.timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in }
                let destination = try fixture.saveA(), saved = try Data(contentsOf: destination)
                let editor = try editor(app, text: "Drag thumbnail proof")
                let drag = app.dragExportView!, provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: drag)
                let generation = app.documentGeneration, frame = window.frame
                let payload = drag.prepare!()!
                try expect(editor.superview == nil && app.canvas.document.elements.contains { $0.text == "Drag thumbnail proof" }, "Drag start commits pending typing as the original stopFieldEditing action did")
                let state = try app.canvas.snapshotDocumentData()
                try expect(drag.beginExport(provider: provider, payload: payload, controlRect: NSRect(x: 10, y: 10, width: 115, height: 50)), "Prepared native export begins")
                let id = app.activeDragID!
                drag.moveExport(to: NSPoint(x: 500, y: 500))
                try expect(app.dragThumbnailID == id && app.dragThumbnailWindow is AppSafetyDragPanel && !window.isVisible && !window.isMiniaturized,
                           "Leaving Drag Me creates the separate panel and hides, rather than miniaturizes, the editor")
                let thumbnail = app.dragThumbnailWindow!.contentView as! DragThumbnailView
                try expect(thumbnail.image != nil && !thumbnail.clickToExpand && app.timer!.fireDate.timeIntervalSinceNow > 1_000, "In-flight thumbnail retains the editor snapshot and pauses recovery")
                drag.endExport(provider: ObjectIdentifier(provider), succeeded: true)
                try expect(app.activeDragID == nil && thumbnail.clickToExpand && !window.isVisible, "Success leaves a persistent click-to-expand thumbnail")
                try expect(thumbnail.accessibilityPerformPress(), "The thumbnail exposes the same restore action to accessibility")
                try expect(app.dragThumbnailWindow == nil && window.isVisible && window.frame == frame && app.timer!.fireDate.timeIntervalSinceNow <= 15,
                           "Thumbnail click restores the same frame, editor and timer")
                try expect(try app.canvas.snapshotDocumentData() == state && app.documentGeneration == generation && app.currentURL == destination && Data(contentsOf: destination) == saved,
                           "Restoring does not change artwork, identity, destination or saved bytes")
                app.canvas.editingUndoManager.undo()
                try expect(!app.canvas.document.elements.contains { $0.text == "Drag thumbnail proof" }, "Committed drag text retains document Undo")
                app.canvas.editingUndoManager.redo()
                try expect(app.canvas.document.elements.contains { $0.text == "Drag thumbnail proof" }, "Committed drag text retains document Redo")
                let rect = AppDelegate.dragThumbnailRect(windowFrame: NSRect(x: 0, y: 0, width: 1000, height: 500), controlRect: NSRect(x: 200, y: 300, width: 100, height: 50))
                try expect(rect == NSRect(x: 186, y: 280, width: 128, height: 90), "Recovered thumbnail long side128, minimum dimension90 and control-centered placement")
            }),
            ("Cancelled drag, failed delivery and stale callbacks cannot strand or replace the editor", {
                let fixture = try Fixture(), app = fixture.app, window = app.window as! AppSafetyWindow
                window.simulatesVisibility = true; window.shown = true
                let drag = app.dragExportView!
                @MainActor func start() throws -> (NSFilePromiseProvider, UUID) {
                    let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: drag)
                    try expect(drag.beginExport(provider: provider, payload: drag.prepare!()!, controlRect: NSRect(x: 0, y: 0, width: 115, height: 50)), "Lifecycle export starts")
                    let id = app.activeDragID!; drag.moveExport(to: NSPoint(x: 200, y: 200)); return (provider, id)
                }
                let (cancelled, oldID) = try start()
                drag.endExport(provider: ObjectIdentifier(cancelled), succeeded: false)
                try expect(window.isVisible && app.dragThumbnailWindow == nil, "Cancellation immediately restores the editor")
                let (current, currentID) = try start()
                app.restoreDragThumbnail(oldID); app.endDrag(oldID, succeeded: false)
                try expect(app.dragThumbnailID == currentID && !window.isVisible, "Old callbacks cannot restore or end a newer drag")
                drag.endExport(provider: ObjectIdentifier(current), succeeded: true)
                var failure: Error?
                drag.filePromiseProvider(current, writePromiseTo: fixture.file("missing").appendingPathComponent("image.png")) { failure = $0 }
                try expect(failure != nil && window.isVisible && app.dragThumbnailWindow == nil, "Promised-file failure after successful native drop restores the matching editor")
                let (last, lastID) = try start()
                app.terminationStarted = true; app.restoreDragThumbnail(lastID); app.endDrag(lastID, succeeded: false)
                try expect(!window.isVisible && app.dragThumbnailID == lastID, "Late drag callbacks cannot reopen the editor during Quit")
                app.terminationStarted = false
                drag.endExport(provider: ObjectIdentifier(last), succeeded: false)
                try expect(window.isVisible, "A cancelled Quit still permits the drag cancellation to restore")
                let (replaced, replacedID) = try start()
                app.newFile()
                try expect(window.isVisible && app.dragThumbnailWindow == nil && app.activeDragID == nil, "New drawing retires a previous drag thumbnail and shows the replacement")
                app.restoreDragThumbnail(replacedID)
                drag.endExport(provider: ObjectIdentifier(replaced), succeeded: true)
                try expect(window.isVisible && app.dragThumbnailWindow == nil, "Late old drag completion cannot hide or thumbnail the new drawing")
            }),
            ("Recovered drag zoom completes once; cancel, reopen, Quit and replacement retire stale animations", {
                let fixture = try Fixture(), app = fixture.app, window = app.window as! AppSafetyWindow
                window.simulatesVisibility = true; window.shown = true
                AppSafetyAnimations.reduceMotion = false
                defer { AppSafetyAnimations.reduceMotion = true }
                let drag = app.dragExportView!
                @MainActor func start() throws -> NSFilePromiseProvider {
                    let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: drag)
                    try expect(drag.beginExport(provider: provider, payload: drag.prepare!()!, controlRect: NSRect(x: 0, y: 0, width: 115, height: 50)), "Animated drag starts")
                    drag.moveExport(to: NSPoint(x: 200, y: 200)); return provider
                }
                @MainActor func finish(_ animation: WindowZoomAnimation) {
                    for _ in 0...animation.frameCount { animation.advance() }
                }
                let state = try app.canvas.snapshotDocumentData(), generation = app.documentGeneration, frame = window.frame
                let provider = try start(), shrinking = app.windowZoom!
                let thumbnail = app.dragThumbnailWindow as! AppSafetyDragPanel
                try expect(shrinking.state == .running && shrinking.frameCount == 25 && thumbnail.fronts == 0 && !window.isVisible,
                           "Shrink overlay owns presentation before the thumbnail appears")
                drag.endExport(provider: ObjectIdentifier(provider), succeeded: true)
                try expect((thumbnail.contentView as! DragThumbnailView).clickToExpand, "Early drop success marks the future thumbnail expandable")
                finish(shrinking)
                try expect(app.windowZoom == nil && thumbnail.fronts == 1 && !window.isVisible, "Recovered shrink completion orders the persistent thumbnail exactly once")
                _ = (thumbnail.contentView as! DragThumbnailView).accessibilityPerformPress()
                let restoring = app.windowZoom!
                try expect(app.dragThumbnailWindow == nil && restoring.direction == .restore && restoring.frameCount == 15 && !window.isVisible,
                           "Restore replaces the thumbnail with the recovered15-frame overlay")
                finish(restoring)
                try expect(window.isVisible && app.windowZoom == nil && window.frame == frame && app.documentGeneration == generation && (try app.canvas.snapshotDocumentData()) == state,
                           "Animation completion restores the same editor without document or geometry changes")
                let cancelled = try start(), previousShrink = app.windowZoom!
                drag.endExport(provider: ObjectIdentifier(cancelled), succeeded: false)
                try expect(previousShrink.state == .cancelled && previousShrink.timer == nil && app.windowZoom?.direction == .restore,
                           "Cancelling an in-flight shrink retires its callback and starts restore")
                let interruptedRestore = app.windowZoom!
                app.newFile()
                interruptedRestore.advance(); previousShrink.advance()
                try expect(window.isVisible && app.windowZoom == nil && app.dragThumbnailWindow == nil && interruptedRestore.state == .cancelled,
                           "Replacement retires both animations and cannot be hidden by their late callbacks")
                let reopened = try start(), interruptedShrink = app.windowZoom!
                app.makeVisible(); interruptedShrink.advance()
                drag.endExport(provider: ObjectIdentifier(reopened), succeeded: true)
                try expect(window.isVisible && app.windowZoom == nil && app.dragThumbnailWindow == nil && interruptedShrink.state == .cancelled,
                           "Dock/menu reopen completes immediately and prevents stale thumbnail ordering")
                let quitting = try start(), quitAnimation = app.windowZoom!
                app.dirty = true; AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertSecondButtonReturn)]
                try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel && window.isVisible && quitAnimation.state == .cancelled && app.windowZoom == nil,
                           "Quit during animation restores the editor before a cancelled decision; no overlay is stranded")
                drag.endExport(provider: ObjectIdentifier(quitting), succeeded: false)
                AppSafetyAnimations.reduceMotion = true
                let reduced = try start()
                try expect(app.windowZoom == nil && (app.dragThumbnailWindow as! AppSafetyDragPanel).fronts == 1, "System Reduce Motion keeps the instant lifecycle")
                drag.endExport(provider: ObjectIdentifier(reduced), succeeded: false)
                try expect(window.isVisible && app.windowZoom == nil, "Reduce Motion cancellation restores immediately")
            }),
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
            ("Frame chrome stays opaque around its transparent canvas hole in light/dark appearance", frameChromeDrawing),
            ("History Open Undo/Redo retains full pan, metadata, filename, URL, archive, dirty flags and prior Undo", historyOpenUndoRedo),
            ("History Open preserves pending text through older Undo/Redo without saving its prior destination", historyOpenPendingText),
            ("History follow keeps latest pending edits and detaches on New/native/capture replacement", historyFollowReplacement),
            ("History index failure preserves prior readable revision and live editor", historyFailedIndexWrite),
            ("successful Save archives exported native state; failed Save archives nothing", historySaveOutcomes),
            ("asynchronous old-generation archive preserves immutable output and current document identity", historyStaleArchiveCompletion),
            ("blank Save, cancelled Save As and cancelled capture cannot archive empty/cancelled outputs", historyEmptyAndCancelledOutputs),
            ("Page Setup Cancel preserves settings; OK retains orientation and margins for printing", {
                let fixture = try Fixture(), app = fixture.app
                let previous = NSPrintInfo.shared
                defer { NSPrintInfo.shared = previous; AppSafetyPageLayout.update = nil; AppSafetyPageLayout.response = .cancel }
                let baseline = previous.copy() as! NSPrintInfo
                baseline.orientation = .portrait; baseline.leftMargin = 37
                NSPrintInfo.shared = baseline
                AppSafetyPageLayout.update = { $0.orientation = .landscape; $0.leftMargin = 54 }
                AppSafetyPageLayout.response = .cancel
                app.pageSetup()
                try expect(NSPrintInfo.shared === baseline && baseline.orientation == .portrait && baseline.leftMargin == 37,
                           "Cancelled Page Setup must not leak preview settings")
                AppSafetyPageLayout.response = .OK
                app.pageSetup()
                try expect(NSPrintInfo.shared !== baseline && NSPrintInfo.shared.orientation == .landscape && NSPrintInfo.shared.leftMargin == 54,
                           "Accepted Page Setup must retain the chosen settings without changing the prior object")
                try expect(baseline.orientation == .portrait && baseline.leftMargin == 37, "Page Setup edits a copy")
            }),
            ("selected tool labels remain readable on bright and dark accent colors", {
                let colors: [NSColor] = [.yellow, .white, .black, .blue, .red, .green,
                    NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                    NSColor(srgbRed: 0.25, green: 0.45, blue: 0.9, alpha: 1)]
                for background in colors {
                    let foreground = ToolButton.textColor(on: background)
                    let rgb = background.usingColorSpace(.deviceRGB)!
                    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { c in
                        c <= 0.04045 ? Double(c) / 12.92 : pow((Double(c) + 0.055) / 1.055, 2.4)
                    }
                    let brightness = zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0.0) { $0 + $1.0 * $1.1 }
                    let contrast = foreground == .black ? (brightness + 0.05) / 0.05 : 1.05 / (brightness + 0.05)
                    try expect(contrast >= 4.5, "Selected tool label contrast is too low: \(contrast)")
                }
                try expect(ToolButton.textColor(on: .yellow) == .black, "Yellow needs a dark selected label")
                try expect(ToolButton.textColor(on: .blue) == .white, "Dark blue needs a light selected label")
            })
        ]
        var results: [[String: Any]] = [], failures = 0
        for (name, test) in tests {
            AppSafetyAlert.answers = []; AppSafetyAlert.seen = []; AppSafetyAlert.unexpected = []
            AppSafetyFilePanel.answers = []
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
                    try expect(AppSafetyFilePanel.answers.isEmpty, "An expected file panel did not run")
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
