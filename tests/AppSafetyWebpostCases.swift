// Webpost one-click upload: both appearances share these cases. Every transfer is an in-process fake; nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var fakeDestination: () throws -> PublishingSettings {
        {
            var settings = PublishingSettings()
            settings.transport = .sftp; settings.sshAlias = "test-host"; settings.sftpRemoteRoot = "/srv/imgs"
            settings.publicBaseURL = "https://cdn.example.com/imgs"
            return settings
        }
    }

    static var webpostCases: [(String, () throws -> Void)] {
        [
            ("Webpost uploads at once with no sheet, shows progress, copies the public link and reports it", webpostUploadsImmediately),
            ("A second Webpost click during a running upload is ignored with a status message and starts nothing", webpostIgnoresSecondClick),
            ("Webpost with no destination opens Sharing Settings instead of uploading", webpostUnconfiguredOpensSettings),
            ("A failed upload surfaces the error and Webpost works again", webpostFailureRecovers),
            ("The upload button's right-click menu lists the default destination, settings and Share with macOS", webpostMenu),
            ("File menu keeps Share… and Publish Image… goes straight to upload", webpostFileMenu)
        ] + (Appearance.isModern ? [("Modern upload button is icon-only with the iCloud upload symbol and an explicit label", webpostModernIconOnly)] : [])
    }

    private static func webpostButton(_ app: AppDelegate) throws -> NSButton {
        try (app.webpostButton).unwrap("Webpost button")
    }

    private final class UploadProbe: @unchecked Sendable {
        let lock = NSLock(); var calls = 0; var copied: [URL] = []
        let gate = DispatchSemaphore(value: 0); var blocks = false; var failure: Error?
        func begin() -> (Bool, Error?) { lock.lock(); defer { lock.unlock() }; calls += 1; return (blocks, failure) }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    }

    private static func install(_ probe: UploadProbe, on app: AppDelegate) {
        app.publishing.uploader = { _, _, plan, _ in
            let (blocks, failure) = probe.begin()
            if blocks { probe.gate.wait() }
            if let failure { throw failure }
            return plan.publicURL ?? plan.remoteURL
        }
        app.publishing.clipboardWriter = { url in probe.lock.lock(); probe.copied.append(url); probe.lock.unlock() }
    }

    static func webpostUploadsImmediately() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); install(probe, on: app)
        app.nameField.stringValue = "Shot"
        try webpostButton(app).performClick(nil)
        try expect(app.window.attachedSheet == nil && app.status.stringValue == "Uploading Shot…", "Webpost starts at once: no sheet, status reads Uploading Shot… (\(app.status.stringValue))")
        try waitForMain("The upload finishes") { !app.publishing.isBusy && probe.count == 1 }
        try waitForMain("Success is reported") { app.status.stringValue.hasPrefix("Link copied: https://cdn.example.com/imgs/Shot-") }
        try expect(probe.copied.count == 1 && probe.copied[0].absoluteString.hasPrefix("https://cdn.example.com/imgs/Shot-") && app.status.stringValue == "Link copied: " + probe.copied[0].absoluteString,
                   "The verified public URL is copied and named in the status")
        try expect(app.window.attachedSheet == nil && AppSafetyAlert.seen.isEmpty, "No sheet or alert at any point")
    }

    static func webpostIgnoresSecondClick() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.blocks = true; install(probe, on: app)
        let button = try webpostButton(app)
        button.performClick(nil)
        try waitForMain("The first upload reaches the transfer") { probe.count == 1 }
        try expect(app.publishing.isBusy, "The coordinator is busy during the transfer")
        button.performClick(nil)
        try expect(app.status.stringValue == "An upload is already running…" && app.window.attachedSheet == nil && AppSafetyAlert.seen.isEmpty,
                   "A second click only sets a status message (\(app.status.stringValue))")
        probe.gate.signal()
        try waitForMain("The first upload completes") { !app.publishing.isBusy && app.status.stringValue.hasPrefix("Link copied") }
        try expect(probe.count == 1 && probe.copied.count == 1, "Exactly one upload ran (\(probe.count))")
    }

    static func webpostUnconfiguredOpensSettings() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); install(probe, on: app)
        app.publishing.settingsLoader = { PublishingSettings() }
        var opened = 0
        app.sharingSettingsPresenter = { opened += 1 }
        try webpostButton(app).performClick(nil)
        try expect(opened == 1 && probe.count == 0 && !app.publishing.isBusy && app.window.attachedSheet == nil, "Settings open, nothing uploads")
        app.publishing.settingsLoader = { throw PublishingFailure("unreadable") }
        try webpostButton(app).performClick(nil)
        try expect(opened == 2 && probe.count == 0, "An unreadable destination also opens settings")
    }

    static func webpostFailureRecovers() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.failure = PublishingFailure("Server said no."); install(probe, on: app)
        let button = try webpostButton(app)
        AppSafetyAlert.answers = [.init(title: "Server said no.", response: .alertFirstButtonReturn)]
        button.performClick(nil)
        try waitForMain("The failure is surfaced") { AppSafetyAlert.seen == ["Server said no."] && !app.publishing.isBusy }
        try expect(probe.copied.isEmpty, "A failed upload copies nothing")
        probe.failure = nil
        button.performClick(nil)
        try waitForMain("Webpost works again after a failure") { probe.count == 2 && app.status.stringValue.hasPrefix("Link copied") }
    }

    private static func menuLayout(_ app: AppDelegate) throws -> [String] {
        let menu = try webpostButton(app).menu.unwrap("Upload menu")
        app.menuNeedsUpdate(menu)
        return menu.items.map { $0.isSeparatorItem ? "-" : ($0.state == .on ? "✓ " : "") + $0.title + ($0.isEnabled ? "" : " (disabled)") }
    }

    static func webpostMenu() throws {
        let fixture = try Fixture(), app = fixture.app
        let button = try webpostButton(app)
        try expect(button.menu != nil && (button as? OriginalActionButton)?.showMenuOnLeftClick == false
                   && button.toolTip == "Upload and copy link · Right-click for destinations", "The button has a right-click menu, left-click stays the action, and the tooltip says so")
        try expect(try menuLayout(app) == ["✓ SFTP · test-host", "-", "Destination Settings…", "Share with macOS…"], "Configured menu: \(try menuLayout(app))")
        app.publishing.settingsLoader = { PublishingSettings() }
        try expect(try menuLayout(app) == ["No destination configured (disabled)", "-", "Destination Settings…", "Share with macOS…"], "Unconfigured menu: \(try menuLayout(app))")
        // The builder takes any list, so more destinations only add rows; only the default is checked.
        let items = app.uploadDestinationMenuItems(destinations: [.init(id: "a", title: "A"), .init(id: "b", title: "B")], defaultID: "b")
        try expect(items.map(\.state).prefix(2) == [.off, .on] && items.count == 5, "Only the default destination is checked")
        // Items reach the settings sheet and the macOS picker through their seams.
        var opened = 0, shared = 0
        app.sharingSettingsPresenter = { opened += 1 }
        app.sharePickerPresenter = { _, anchor in if anchor === button { shared += 1 } }
        let menu = try button.menu.unwrap("menu"); app.menuNeedsUpdate(menu)
        for title in ["Destination Settings…", "Share with macOS…"] {
            let item = try menu.items.first { $0.title == title }.unwrap(title)
            _ = NSApp.sendAction(try item.action.unwrap("action"), to: item.target, from: item)
        }
        try expect(opened == 1 && shared == 1, "Settings and Share items each fire once, Share relative to the button")
    }

    static func webpostFileMenu() throws {
        let fixture = try Fixture(), app = fixture.app
        let file = try NSApp.mainMenu.unwrap("main menu").items.compactMap(\.submenu).first { $0.title == "File" }.unwrap("File menu")
        let share = try file.items.first { $0.title == "Share…" }.unwrap("File › Share…")
        try expect(share.action == #selector(AppDelegate.shareFromMenu), "File › Share… opens the macOS picker")
        let probe = UploadProbe(); install(probe, on: app)
        let publish = try file.items.first { $0.title == "Publish Image…" }.unwrap("Publish Image…")
        _ = NSApp.sendAction(try publish.action.unwrap("action"), to: app, from: publish)
        try expect(app.window.attachedSheet == nil && app.status.stringValue.hasPrefix("Uploading"), "Publish Image… uploads without a confirmation sheet")
        try waitForMain("it finishes") { !app.publishing.isBusy && probe.count == 1 }
    }

    static func webpostModernIconOnly() throws {
        let fixture = try Fixture(), app = fixture.app
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "Modern chrome required") }
        let button = chrome.shareButton
        try expect(button.title.isEmpty && button.imagePosition == .imageOnly && button.icon == nil && button.image?.isTemplate == true,
                   "The upload button has no title and a native symbol image")
        try expect(ModernEditorChrome.uploadSymbolName == "icloud.and.arrow.up" && NSImage(systemSymbolName: ModernEditorChrome.uploadSymbolName, accessibilityDescription: nil) != nil
                   && button.image?.accessibilityDescription == "Upload", "It shows icloud.and.arrow.up")
        try expect(button.accessibilityLabel() == "Upload to destination", "VoiceOver reads the label, not the symbol name")
        try expect(button.action == #selector(AppDelegate.share(_:)) && button.menu != nil, "It uploads on click and carries the destination menu")
        let width = chrome.surface(for: button)?.fixedSize?.width ?? 999
        try expect(width <= 48 && chrome.surface(for: button)?.fixedSize?.height == 36, "It is a compact circle-sized pill, not a labelled capsule (\(width))")
    }
}

private extension Optional {
    func unwrap(_ name: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(name)") }
        return self
    }
}
#endif
