// Pure tests: isolated UserDefaults suite and fake hotkey backend only.
// No app/window creation, OS hotkey registration, Accessibility, keyboard event
// synthesis, credentials, desktop capture, or network.
// xcrun swiftc -D GLOBAL_HOTKEY_TESTS -swift-version 5 -target arm64-apple-macosx13.0 \
//   Sources/GlobalHotkeys.swift tests/GlobalHotkeysTests.swift -o /tmp/skitch-hotkey-tests
// /tmp/skitch-hotkey-tests
// Repeat compilation for x86_64-apple-macosx13.0 (Intel); Swift 6 is also checked.
#if GLOBAL_HOTKEY_TESTS
import AppKit
import Foundation

@MainActor
private final class FakeGlobalHotkeyBackend: GlobalHotkeyBackend {
    var bindings: [UInt32: GlobalHotkeyBinding] = [:]
    var registeredIDs: Set<UInt32> { Set(bindings.keys) }
    var callback: (@MainActor @Sendable (UInt32) -> Void)?
    var reserved: Set<GlobalHotkeyBinding> = []
    var failuresToRegister: [UInt32: Int] = [:]
    var failuresToUnregister: [UInt32: Int] = [:]
    var queryFailure: Error?
    var calls: [String] = []
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {
        calls.append("install"); callback = onEvent
    }
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> {
        calls.append("query")
        if let queryFailure { throw queryFailure }
        return reserved
    }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {
        calls.append("register \(id)")
        if failuresToRegister[id, default: 0] > 0 {
            failuresToRegister[id, default: 0] -= 1
            throw NSError(domain: NSOSStatusErrorDomain, code: -9878,
                          userInfo: [NSLocalizedDescriptionKey: "Synthetic exclusive-key conflict"])
        }
        guard bindings[id] == nil, !bindings.values.contains(binding) else {
            throw NSError(domain: "FakeBackend", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Duplicate native binding or ID"])
        }
        bindings[id] = binding
    }
    func unregister(id: UInt32) throws {
        calls.append("unregister \(id)")
        if failuresToUnregister[id, default: 0] > 0 {
            failuresToUnregister[id, default: 0] -= 1
            throw NSError(domain: NSOSStatusErrorDomain, code: -50,
                          userInfo: [NSLocalizedDescriptionKey: "Synthetic unregister failure"])
        }
        bindings.removeValue(forKey: id)
    }
    func shutdown() throws {
        calls.append("shutdown")
        var errors: [Error] = []
        for id in registeredIDs.sorted() {
            do { try unregister(id: id) } catch { errors.append(error) }
        }
        callback = nil
        if let error = errors.first { throw error }
    }
    func emit(_ action: GlobalHotkeyAction) { callback?(action.carbonID) }
    func emitUnknown() { callback?(999) }
}

@main
@MainActor
private enum GlobalHotkeysTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }
    @discardableResult
    private static func rejects(_ message: String, _ action: () throws -> Void) throws -> NSError {
        do { try action() }
        catch { checks += 1; return error as NSError }
        throw Failure(description: "Unexpectedly accepted: " + message)
    }
    private static func custom() -> GlobalHotkeySettings {
        var settings = GlobalHotkeySettings()
        let codes: [UInt32] = [0,11,8,2,14,3,5] // A, B, C, D, E: independent literal fixtures.
        for (action, code) in zip(GlobalHotkeyAction.allCases, codes) {
            settings[action] = .init(keyCode: code, modifiers: [.control, .option])
        }
        return settings
    }
    private static func install(_ manager: GlobalHotkeyManager,
                                callback: @escaping @MainActor (GlobalHotkeyAction) -> Void = { _ in }) throws {
        try manager.install(globalScreen: { callback(.screen) }, globalWindow: { callback(.window) },
                            globalFullscreen: { callback(.fullscreen) }, globalFrame: { callback(.frame) },
                            globalCamera: { callback(.camera) }, globalUpload: { callback(.upload) },
                            globalShow: { callback(.show) })
    }
    private static func drainCallbacks() async throws {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    static func main() async {
        do { try await run(); print("PASS GlobalHotkeysTests (\(checks) checks; pure fake backend)") }
        catch { fputs("FAIL GlobalHotkeysTests: \(error)\n", stderr); exit(1) }
    }
    private static func run() async throws {
        let suite = "SkitchRedux.GlobalHotkeys.Tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(description: "Could not create isolated preferences suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalHotkeyStore(defaults: defaults)

        let first = try store.load()
        try expect(first == .defaults, "Fresh preferences are safely unassigned")
        try expect(first.screen == .none && first.fullscreen == .none, "Modern screenshot conflicts are disabled by default")
        try expect(first.window == .none && first.camera == .none, "Unverified modes start unassigned")
        let originalFrame = GlobalHotkeySettings.originalBindings[.frame]!
        try expect(first.frame == .none && first.activeBindings.isEmpty, "No original shortcut is automatically claimed on first launch")
        try expect(originalFrame.keyCode == 26 && originalFrame.modifiers == [.command, .shift], "Verified original frame hardware code and flags are metadata only")
        try expect(originalFrame.modifiers.carbonFlags == 0x300, "Original frame maps to Carbon Command+Shift")
        let originalUpload = GlobalHotkeySettings.originalBindings[.upload]!
        try expect(originalUpload.keyCode == 23 && originalUpload.modifiers == [.command, .shift, .control] && originalUpload.modifiers.carbonFlags == 0x1300, "Original Upload chord is code 0x17 flags 0x1300, metadata only")
        try expect(GlobalHotkeySettings.originalBindings[.show] == nil && first.upload == .none && first.show == .none, "Show has no original default and neither new action is claimed on first launch")
        try expect(GlobalHotkeyAction(rawValue: "upload") == .upload && GlobalHotkeyAction(rawValue: "show") == .show, "Upload/Show raw values")
        try expect(Set(GlobalHotkeyAction.allCases.map(\.carbonID)).count == 7 && GlobalHotkeyAction.allCases.count == 7, "Seven actions with distinct carbon IDs")
        try expect(GlobalHotkeyAction.upload.title == "Upload" && GlobalHotkeyAction.show.title == "Show Skitch", "Upload/Show titles")
        let legacy = Data(#"{"version":1,"enabled":true,"screen":{"modifiers":0},"window":{"modifiers":0},"fullscreen":{"modifiers":0},"frame":{"modifiers":0},"camera":{"modifiers":0}}"#.utf8)
        let decodedLegacy = try? JSONDecoder().decode(GlobalHotkeySettings.self, from: legacy)
        try expect(decodedLegacy?.upload == GlobalHotkeyBinding.none && decodedLegacy?.show == GlobalHotkeyBinding.none, "Preferences saved before Upload/Show still load")
        try expect(GlobalHotkeyModifiers(carbonFlags: 0x1800) == [.control, .option], "Carbon Control+Option conversion")
        try expect(GlobalHotkeyModifiers(appKitFlags: [.control, .option, .capsLock]) == [.control, .option], "AppKit uses semantic modifiers, ignoring Caps Lock")
        try expect(GlobalHotkeyKeys.choices.count == Set(GlobalHotkeyKeys.choices.map(\.code)).count, "Physical key catalog has unique hardware positions")
        try expect(GlobalHotkeyKeys.code(forMenuKey: "S") == 1, "Uppercase menu equivalent maps to S position")
        try expect(GlobalHotkeyKeys.code(forMenuKey: ",") == 43, "Preferences punctuation maps to comma")
        try expect(GlobalHotkeyBinding.none.displayName == "None", "None displays explicitly")
        try first.validate()
        let firstLaunchBackend = FakeGlobalHotkeyBackend()
        firstLaunchBackend.reserved = [originalFrame]
        firstLaunchBackend.queryFailure = NSError(domain: NSOSStatusErrorDomain, code: -50)
        let firstLaunch = GlobalHotkeyManager(defaults: defaults, backend: firstLaunchBackend)
        try install(firstLaunch)
        try expect(firstLaunch.isRunning && firstLaunch.lastError == nil && firstLaunchBackend.bindings.isEmpty,
                   "First launch is healthy even when original chords are taken or system lookup fails")
        try expect(!firstLaunchBackend.calls.contains("query"), "All-None launch does not need a system conflict lookup")
        try expect(defaults.object(forKey: GlobalHotkeyStore.defaultsKey) == nil, "First launch does not overwrite user preferences with automatic bindings")
        try firstLaunch.unregister()
        try custom().validate()
        try GlobalHotkeySettings.disabled.validate()

        for invalidModifiers: GlobalHotkeyModifiers in [[], .shift, .option, [.option, .shift], .init(rawValue: 16)] {
            var settings = custom(); settings.screen.modifiers = invalidModifiers
            try rejects("typing keys / unsupported modifier bits") { try settings.validate() }
        }
        for code: UInt32 in [51,53,55,123,127,UInt32.max] {
            var settings = custom(); settings.screen.keyCode = code
            try rejects("unsupported modifier/navigation key code") { try settings.validate() }
        }
        var candidate = custom(); candidate.camera = candidate.screen
        try rejects("duplicate actions") { try candidate.validate() }
        candidate.enabled = false
        try rejects("latent duplicate while disabled") { try candidate.validate() }
        candidate = custom(); candidate.camera = .init(keyCode: nil, modifiers: .control)
        try rejects("None carrying modifiers") { try candidate.validate() }
        candidate = custom(); candidate.version = 2
        try rejects("future settings schema") { try candidate.validate() }
        for reserved in GlobalHotkeySettings.internalBindings.union(GlobalHotkeySettings.screenshotBindings) {
            candidate = GlobalHotkeySettings(); candidate.screen = reserved
            try rejects("reserved app or screenshot binding") { try candidate.validate() }
        }
        candidate = GlobalHotkeySettings(); candidate.screen = .init(keyCode: 22, modifiers: [.command, .shift, .control])
        try rejects("Control+6 stays reserved for the macOS Touch Bar screenshot") { try candidate.validate() }
        candidate = GlobalHotkeySettings(); candidate.upload = GlobalHotkeySettings.originalBindings[.upload]!
        try candidate.validate()
        candidate = custom()
        try rejects("parent-provided extra internal conflict") { try candidate.validate(additionalReserved: [candidate.screen]) }

        candidate = custom(); candidate.camera = .none
        try store.save(candidate)
        try expect(try store.load() == candidate, "Custom settings and per-action None round-trip")
        let payload = defaults.data(forKey: GlobalHotkeyStore.defaultsKey)!
        let json = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        try expect(Set(json.keys) == Set(["version","enabled","screen","window","fullscreen","frame","camera","upload","show"]), "Persistence schema contains only version, enabled and known action bindings")
        let camera = json["camera"] as! [String: Any]
        try expect(camera["keyCode"] == nil, "None persists without a hardware code")
        try expect(!String(decoding: payload, as: UTF8.self).contains("password") && !String(decoding: payload, as: UTF8.self).contains("credential"), "No credential fields persisted")
        let before = payload
        var invalid = candidate; invalid.window = invalid.screen
        try rejects("invalid save") { try store.save(invalid) }
        try expect(defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == before, "Rejected save leaves previous preferences intact")
        candidate.enabled = false
        try store.save(candidate)
        try expect(try store.load() == candidate && candidate.activeBindings.isEmpty, "Disable persists while remembering key choices")
        candidate = GlobalHotkeySettings(); try store.save(candidate)
        try expect(try store.load().frame == .none, "Explicit None overrides the original frame default across restarts")
        for malformed: Any in ["not data", Data("{".utf8), Data(repeating: 1, count: 16_385), Data("{}".utf8)] {
            defaults.set(malformed, forKey: GlobalHotkeyStore.defaultsKey)
            try rejects("malformed persisted preferences") { _ = try store.load() }
        }
        var future = custom(); future.version = 9
        defaults.set(try JSONEncoder().encode(future), forKey: GlobalHotkeyStore.defaultsKey)
        let failedBackend = FakeGlobalHotkeyBackend()
        let failedManager = GlobalHotkeyManager(defaults: defaults, backend: failedBackend)
        try expect(failedManager.settings == .disabled && failedManager.lastError != nil, "Corrupt/future preferences fail closed with an actual error")
        try rejects("install from corrupt preferences") { try install(failedManager) }
        try expect(failedBackend.bindings.isEmpty && failedBackend.calls.isEmpty, "Corrupt preferences never touch desktop backend")
        try failedManager.apply(.disabled)
        try install(failedManager)
        try expect(failedManager.isRunning && failedBackend.bindings.isEmpty, "Explicit corrected disabled configuration can install without any binding")
        try failedManager.unregister()

        try store.save(custom())
        let backend = FakeGlobalHotkeyBackend()
        let manager = GlobalHotkeyManager(defaults: defaults, backend: backend)
        try expect(backend.calls.isEmpty && manager.registeredActions.isEmpty, "Manager init does not install unknown/user shortcuts")
        try rejects("register before callbacks") { try manager.register() }
        var fired: [GlobalHotkeyAction] = []
        try install(manager) { action in
            precondition(Thread.isMainThread, "Capture callback must be on main thread")
            fired.append(action)
        }
        try expect(manager.isRunning && backend.registeredIDs.count == 7 && manager.registeredActions.count == 7, "Install registers each enabled action once")
        for action in GlobalHotkeyAction.allCases { backend.emit(action) }
        backend.emitUnknown()
        try expect(fired.isEmpty, "Hotkey delivery is queued rather than reentrant")
        try await drainCallbacks()
        try expect(fired == GlobalHotkeyAction.allCases, "Each ID invokes its correct main-thread callback, ignoring unknown IDs")
        let registrationCount = backend.calls.filter { $0.hasPrefix("register ") }.count
        try manager.register()
        try expect(backend.calls.filter { $0.hasPrefix("register ") }.count == registrationCount, "Repeated register is idempotent")

        let saved = defaults.data(forKey: GlobalHotkeyStore.defaultsKey)
        let explicitBackend = FakeGlobalHotkeyBackend()
        explicitBackend.reserved = [custom().screen]
        let explicitManager = GlobalHotkeyManager(defaults: defaults, backend: explicitBackend)
        try rejects("explicit saved binding already in use") { try install(explicitManager) }
        try expect(explicitManager.settings == custom() && explicitManager.lastError != nil &&
                   defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == saved,
                   "Saved user binding remains unchanged with a clear conflict error")
        var repaired = explicitManager.settings
        repaired.screen = .init(keyCode: 35, modifiers: [.control, .option])
        try explicitManager.apply(repaired)
        try expect(explicitManager.isRunning && explicitBackend.bindings.count == 7 && explicitManager.lastError == nil,
                   "Saving a repaired explicit binding recovers failed launch without relaunch")
        try expect((try store.load()) == repaired, "Only explicitly repaired choices are persisted")
        try explicitManager.unregister()
        try store.save(custom()) // Restore this test's isolated persistence fixture.
        let activeBefore = backend.bindings
        invalid = manager.settings; invalid.window = invalid.screen
        try rejects("invalid live update") { try manager.apply(invalid) }
        try expect(backend.bindings == activeBefore && defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == saved, "Invalid live update changes neither active keys nor preferences")
        var changed = manager.settings; changed.screen = .init(keyCode: 35, modifiers: [.control, .option]) // P
        backend.failuresToRegister[GlobalHotkeyAction.screen.carbonID] = 1
        let registrationError = try rejects("native registration failure") { try manager.apply(changed) }
        try expect(registrationError.domain == NSOSStatusErrorDomain && registrationError.code == -9878, "Actual native status is preserved")
        try expect(backend.bindings == activeBefore && manager.settings == custom() && defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == saved, "Failed update restores previous active bindings without saving candidate")
        backend.failuresToRegister[GlobalHotkeyAction.screen.carbonID] = 2
        let rollbackError = try rejects("rollback failure") { try manager.apply(changed) }
        try expect((rollbackError.userInfo["RelatedErrors"] as? [NSError])?.count == 2, "Rollback failure reports original and restoration errors")
        try expect(!manager.registeredActions.contains(.screen) && backend.bindings.count == 6, "Actual missing registration remains visible after failed rollback")
        try expect(manager.settings == custom() && defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == saved, "Rollback failure does not fabricate successful preferences")
        try manager.register()
        try expect(backend.bindings == activeBefore, "Register can repair a previous failed rollback")

        backend.reserved = [changed.screen]
        try rejects("enabled macOS symbolic hotkey conflict") { try manager.apply(changed) }
        try expect(backend.bindings == activeBefore, "System clash leaves active state intact")
        backend.reserved = []
        backend.queryFailure = NSError(domain: NSOSStatusErrorDomain, code: -50)
        let queryError = try rejects("system lookup failure") { try manager.apply(changed) }
        try expect(queryError.code == -50 && backend.bindings == activeBefore, "System lookup failure is actual, not an assumed free key")
        try manager.disableAll()
        try expect(!manager.settings.enabled && backend.bindings.isEmpty, "Disable All works even if system-shortcut lookup fails")
        backend.queryFailure = nil
        var reenabling = manager.settings; reenabling.enabled = true
        try manager.apply(reenabling)
        try expect(backend.bindings == activeBefore, "Re-enable restores remembered binding choices")

        fired = []
        backend.emit(.screen)
        try manager.disableAll()
        try await drainCallbacks()
        try expect(fired.isEmpty, "Queued callback is invalidated by disabling shortcuts")
        try manager.apply(custom())
        backend.emit(.frame)
        try manager.unregister()
        try await drainCallbacks()
        try expect(fired.isEmpty && backend.bindings.isEmpty && !manager.isRunning, "Unregister invalidates queued callbacks and frees registrations")
        try manager.unregister()
        try expect(defaults.data(forKey: GlobalHotkeyStore.defaultsKey) == saved, "Lifecycle stop preserves preferences")
        try manager.register()
        backend.failuresToUnregister[GlobalHotkeyAction.screen.carbonID] = 1
        let unregisterError = try rejects("native unregister failure") { try manager.unregister() }
        try expect(unregisterError.code == -50 && !manager.isRunning && manager.registeredActions == [.screen], "Unregister failure retains actual outstanding ownership but disables dispatch")
        backend.emit(.screen)
        try await drainCallbacks()
        try expect(fired.isEmpty, "Outstanding failed removal cannot dispatch after stop")
        try manager.unregister()
        try expect(backend.bindings.isEmpty && manager.registeredActions.isEmpty, "Unregister retry frees outstanding registration")

        try store.save(custom())
        let partialBackend = FakeGlobalHotkeyBackend()
        partialBackend.failuresToRegister[GlobalHotkeyAction.fullscreen.carbonID] = 1
        let partialManager = GlobalHotkeyManager(defaults: defaults, backend: partialBackend)
        try rejects("partial startup registration failure") { try install(partialManager) }
        try expect(partialBackend.bindings.isEmpty && partialManager.registeredActions.isEmpty && !partialManager.isRunning, "Failed startup removes already-registered keys")
        try partialManager.unregister()
        let extraBackend = FakeGlobalHotkeyBackend()
        let extraManager = GlobalHotkeyManager(defaults: defaults, reservedBindings: [custom().camera], backend: extraBackend)
        try rejects("parent's internal shortcut clashes") { try install(extraManager) }
        try expect(extraBackend.bindings.isEmpty, "Parent-provided reserved chords never register")
        try manager.resetDefaults()
        try expect(manager.settings == .defaults && (try store.load()) == .defaults && backend.bindings.isEmpty, "Reset persists verified safe defaults without registering while stopped")
        try manager.register()
        try expect(manager.registeredActions.isEmpty, "Reset plus start claims no shortcuts until configured")
        try manager.unregister()
        try expect(NSApp == nil, "Pure test suite never creates an application or desktop window")
    }
}
#endif
