// Run tools/test-app-safety.sh. These are internal AppKit events, not desktop input.
// The generated App.swift copy replaces alert, window, activation, capture and hotkey
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

// No defaults, Carbon handler or desktop registration is reachable through this
// adapter. GlobalHotkeys.swift still compiles alongside the actual app sources.
@MainActor
final class AppSafetyHotkeyManager {
    static var installations = 0
    func install(globalScreen: @escaping @MainActor () -> Void,
                 globalWindow: @escaping @MainActor () -> Void,
                 globalFullscreen: @escaping @MainActor () -> Void,
                 globalFrame: @escaping @MainActor () -> Void,
                 globalCamera: @escaping @MainActor () -> Void) throws {
        Self.installations += 1
    }
    func unregister() throws {}
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
    func capture(mode: String, delay: Double = 0, completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append(mode); completion(.failure(Self.cancellation))
    }
    func captureCamera(completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append("camera"); completion(.failure(Self.cancellation))
    }
    func captureURL(_ url: URL, completion: @escaping (Result<NSImage, Error>) -> Void) {
        Self.requests.append("web"); completion(.failure(Self.cancellation))
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
    @MainActor
    final class Fixture {
        let app = AppDelegate()
        init() throws {
            let expected = ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"]!
            try expect(app.support.path == expected, "App support must be isolated")
            let recovery = app.support.appendingPathComponent("Recovery.skitchredux")
            if FileManager.default.fileExists(atPath: recovery.path) { try FileManager.default.removeItem(at: recovery) }
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
    static func image() throws -> NSImage {
        let size = NSSize(width: 24, height: 16)
        guard let pixels = SketchRenderer.bitmap(size: size, draw: {
            NSColor.blue.setFill(); NSRect(origin: .zero, size: size).fill()
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
        let data = try Data(contentsOf: app.support.appendingPathComponent("Recovery.skitchredux"))
        let recovered = try SketchDocument.decode(data)
        try expect(recovered.elements.first?.text == text.string, "Recovery must include uncommitted text")
        try expect(app.canvas.document == before && changes == 0, "Recovery must not mutate the live document or notify changes")
        try expect(text.superview === app.canvas && app.window.firstResponder === text && text.selectedRange() == caret,
                   "Recovery must preserve editor, focus and caret")
        try expect(text.undoManager === typingHistory && app.canvas.editingUndoManager.canUndo == canUndo,
                   "Recovery must not create canvas undo or replace typing history")
        text.insertText("!", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        app.saveRecovery()
        try expect(try SketchDocument.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitchredux"))).elements.first?.text == text.string,
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
        let recovered = try SketchDocument.decode(Data(contentsOf: app.support.appendingPathComponent("Recovery.skitchredux")))
        try expect(recovered.elements.first?.text == text.string && app.canvas.document == before,
                   "Recovery must retain pending text even when dirty is false")
        answer(.alertSecondButtonReturn)
        app.newFile()
        try expect(app.canvas.document == before && text.superview === app.canvas,
                   "Discard decisions must protect pending text even when dirty is false")
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
    static func main() {
        guard let evidence = ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"],
              ProcessInfo.processInfo.environment["SKITCH_APP_SUPPORT"] != nil else {
            fputs("Run tools/test-app-safety.sh for isolated execution.\n", stderr); exit(2)
        }
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let tests: [(String, () throws -> Void)] = [
            ("dirty typing protects New and Quit", dirtyTyping),
            ("active editor Undo/Redo and menu validation", typingUndo),
            ("recovery includes pending text without committing", recoverySnapshot),
            ("pending text remains protected with a stale dirty flag", pendingTextFallback),
            ("accepted document drop saves to B and preserves A", acceptedDrop),
            ("cancelled document drop preserves pending typing", cancelledDrop),
            ("capture start cancellation and completion Cancel preserve edits", captureCancellation),
            ("capture completion Discard replaces explicitly", captureDiscard),
            ("capture completion Save persists pending text first", captureSave),
            ("filename focus retains command-menu behavior", filenameCommands)
        ]
        var results: [[String: Any]] = [], failures = 0
        for (name, test) in tests {
            AppSafetyAlert.answers = []; AppSafetyAlert.seen = []; AppSafetyAlert.unexpected = []
            AppSafetyCaptureCoordinator.requests = []
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
            "boundaries": "Nonvisible windows; deterministic modal answers; synthetic cancelled capture and no-registration hotkey adapters; actual app launch and Canvas; isolated support and named drag pasteboard. No desktop events, uploads, live hotkey registrations or general clipboard writes."]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: evidence).appendingPathComponent("results.json"), options: .atomic)
        } catch { failures += 1; fputs("Could not save test evidence: \(error)\n", stderr) }
        print("\(tests.count - results.filter { $0["passed"] as? Bool == false }.count)/\(tests.count) app safety tests passed")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
