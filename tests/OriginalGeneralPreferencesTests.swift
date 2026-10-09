// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit -D ORIGINAL_GENERAL_PREFERENCES_TESTS \
//   Sources/LegacySkitch.swift Sources/StrokeFitting.swift Sources/DocumentModel.swift Sources/GeneralPreferencesForm.swift \
//   Sources/OriginalGeneralPreferences.swift Sources/Appearance.swift tests/OriginalGeneralPreferencesTests.swift \
//   -o build/original-general-preferences-tests
// rtk proxy build/original-general-preferences-tests
// The audio decode checks need the git-ignored original/ archive; without it they print a SKIP line and the rest still run.
#if ORIGINAL_GENERAL_PREFERENCES_TESTS
import AppKit

@main
@MainActor
enum OriginalGeneralPreferencesTests {
    static var checks = 0
    struct Failure: Error { let message: String }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw Failure(message: message) }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let domain = "OpenSkitch.preferences.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = OriginalGeneralPreferences(defaults: defaults)
        let fresh = store.state
        try expect(fresh.drawingPrecision == .medium && fresh.arrowHead == 2 && !fresh.includeSkitch && fresh.playSounds && fresh.statusMenu == 0,
                   "Fresh behavior follows original engine fallback, End/Both defaults, excluded app and enabled sounds")
        store.apply(fresh)
        try expect(defaults.persistentDomain(forName: domain)?.isEmpty != false, "Reading/opening unchanged preferences writes no defaults")
        try expect(!fresh.showToolTips && !fresh.showKeyboardTips, "Original registered defaults disable both overlay kinds on a fresh launch")
        for toolTips in [false, true] {
            for keyboardTips in [false, true] {
                var proposed = store.state; proposed.showToolTips = toolTips; proposed.showKeyboardTips = keyboardTips
                store.apply(proposed)
                let reopened = OriginalGeneralPreferences(defaults: UserDefaults(suiteName: domain)!).state
                try expect(reopened.showToolTips == toolTips && reopened.showKeyboardTips == keyboardTips, "Independent inverse overlay choices reload exactly")
                if defaults.object(forKey: "disableOverlay") != nil {
                    try expect(defaults.bool(forKey: "disableOverlay") == !toolTips, "disableOverlay stores inverse checkbox polarity")
                }
                if defaults.object(forKey: "disableModtips") != nil {
                    try expect(defaults.bool(forKey: "disableModtips") == !keyboardTips, "disableModtips stores inverse checkbox polarity")
                }
            }
        }
        defaults.set("loose", forKey: "PencilSmoothing")
        try expect(store.state.drawingPrecision == .loose, "Existing reconstruction precision survives until explicit choice")
        for (tag, mode) in [(0, StrokeSmoothing.precise), (1, .medium), (2, .loose)] {
            defaults.set(tag, forKey: "fittingPrecision")
            try expect(store.state.drawingPrecision == mode, "Recovered fittingPrecision tag \(tag) takes precedence")
            store.setPrecision(mode)
            try expect(defaults.integer(forKey: "fittingPrecision") == tag && defaults.string(forKey: "PencilSmoothing") == mode.rawValue,
                       "Explicit precision keeps original key and reconstruction compatibility key synchronized")
        }
        defaults.set(99, forKey: "fittingPrecision")
        try expect(store.state.drawingPrecision == .loose, "Malformed original precision preserves valid existing choice")
        defaults.set("invalid", forKey: "PencilSmoothing")
        try expect(store.state.drawingPrecision == .medium, "Invalid precision falls back to original engine Medium")
        defaults.removeObject(forKey: "fittingPrecision"); defaults.removeObject(forKey: "PencilSmoothing")
        for include in [false, true] {
            defaults.set(include, forKey: "skitchInSnap")
            for option in [false, true] {
                for mode in ["crosshair", "fullscreen", "window", "frame", "web"] {
                    let before = defaults.persistentDomain(forName: domain)!
                    try expect(store.includeApp(mode: mode, manualOption: option) == ((mode == "crosshair" || mode == "fullscreen") && (include != option)),
                               "Manual Option policy \(mode)/\(include)/\(option)")
                    try expect(NSDictionary(dictionary: defaults.persistentDomain(forName: domain)!).isEqual(to: before), "Temporary capture reversal never mutates saved settings")
                }
            }
            try expect(OriginalGeneralPreferences(defaults: UserDefaults(suiteName: domain)!).state.includeSkitch == include, "Saved inclusion reloads through another store")
        }
        for presence in [0, 1, 2] {
            var state = store.state; state.statusMenu = presence; state.arrowHead = presence == 1 ? 1 : 2
            state.playSounds = presence == 1; state.drawingPrecision = .precise
            store.apply(state)
            let reopened = OriginalGeneralPreferences(defaults: UserDefaults(suiteName: domain)!).state
            try expect(reopened == state, "Native states persist together and reload exactly")
            try expect(defaults.bool(forKey: "disableSounds") == !state.playSounds, "Original sound binding stores inverse checkbox value")
        }
        let before = store.state
        var invalid = before; invalid.statusMenu = 9; invalid.arrowHead = 9; store.apply(invalid)
        try expect(store.state == before, "Invalid radio tags cannot overwrite valid saved choices")
        defaults.set(17, forKey: "statusMenu"); defaults.set(17, forKey: "arrowHead")
        try expect(store.state.statusMenu == 0 && store.state.arrowHead == 2, "Unknown tags display semantic defaults without destructive rewrites")
        try expect(defaults.integer(forKey: "statusMenu") == 17 && defaults.integer(forKey: "arrowHead") == 17, "Reading invalid tags leaves external preference data intact")
        // Appearance is a reconstruction key (no original Skitch binding), resolved by AppearanceResolver.
        let appearanceDomain = domain + ".appearance"
        let appearanceDefaults = UserDefaults(suiteName: appearanceDomain)!
        defer { appearanceDefaults.removePersistentDomain(forName: appearanceDomain) }
        let appearanceStore = OriginalGeneralPreferences(defaults: appearanceDefaults)
        let resolver = AppearanceResolver(defaults: appearanceDefaults)
        let osDefault: AppearanceStyle = resolver.supportsModern ? .modern : .classic
        let other: AppearanceStyle = osDefault == .modern ? .classic : .modern
        try expect(OriginalGeneralPreferences.appearanceKey == "appearanceStyle" && OriginalGeneralPreferences.appearanceKey == AppearanceResolver.defaultsKey,
                   "Appearance uses the resolver's reconstruction key")
        let originalKeys = [OriginalGeneralPreferences.precisionKey, OriginalGeneralPreferences.captureKey, OriginalGeneralPreferences.soundsKey,
                            OriginalGeneralPreferences.presenceKey, OriginalGeneralPreferences.overlaysKey, OriginalGeneralPreferences.keyboardTipsKey]
        try expect(!originalKeys.contains(OriginalGeneralPreferences.appearanceKey), "Appearance is not mistaken for an original Skitch key")
        let freshAppearance = appearanceStore.state
        try expect(freshAppearance.appearance == osDefault, "A fresh store follows the OS default: Modern on macOS 26 and later, Classic below")
        appearanceStore.apply(freshAppearance)
        try expect(appearanceDefaults.persistentDomain(forName: appearanceDomain)?.isEmpty != false, "Reading and applying the default appearance writes nothing")
        var quiet = appearanceStore.state; quiet.playSounds = false
        appearanceStore.apply(quiet)
        try expect(appearanceDefaults.object(forKey: AppearanceResolver.defaultsKey) == nil && appearanceDefaults.bool(forKey: "disableSounds"),
                   "An unrelated edit never persists the default appearance")
        var chosen = appearanceStore.state; chosen.appearance = other
        let beforeChoice = appearanceDefaults.persistentDomain(forName: appearanceDomain)!
        appearanceStore.apply(chosen)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == other.rawValue && resolver.storedChoice == other, "An explicit choice persists as its word")
        var afterChoice = appearanceDefaults.persistentDomain(forName: appearanceDomain)!
        afterChoice.removeValue(forKey: AppearanceResolver.defaultsKey)
        try expect(NSDictionary(dictionary: afterChoice).isEqual(to: beforeChoice), "Choosing an appearance touches no other preference")
        try expect(OriginalGeneralPreferences(defaults: UserDefaults(suiteName: appearanceDomain)!).state.appearance == other, "The choice reloads through another store")
        chosen.appearance = osDefault
        appearanceStore.apply(chosen)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == osDefault.rawValue && appearanceStore.state.appearance == osDefault,
                   "Choosing the OS default again is still an explicit, persisted choice")
        resolver.store(nil)
        try expect(appearanceDefaults.object(forKey: AppearanceResolver.defaultsKey) == nil && appearanceStore.state.appearance == osDefault,
                   "Removing the key returns to the OS default")
        appearanceDefaults.set("glass", forKey: AppearanceResolver.defaultsKey)
        try expect(appearanceStore.state.appearance == osDefault, "A malformed stored appearance reads as the OS default")
        var neutral = appearanceStore.state; neutral.arrowHead = neutral.arrowHead == 1 ? 2 : 1
        appearanceStore.apply(neutral)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == "glass", "Reading or unrelated edits leave a malformed value untouched")
        neutral.appearance = other
        appearanceStore.apply(neutral)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == other.rawValue, "An explicit choice replaces a malformed value")
        resolver.store(nil)

        // The real form drives the store: radios persist the key, Relaunch persists nothing.
        let form = GeneralPreferencesForm(state: appearanceStore.state, modernAvailable: true)
        form.onChange = { appearanceStore.apply($0); form.synchronize(appearanceStore.state) }
        var relaunches = 0
        form.onRelaunch = { relaunches += 1 }
        let formButtons = descendants(form).compactMap { $0 as? NSTabView }.first!.tabViewItems.flatMap { descendants($0.view!) }.compactMap { $0 as? NSButton }
        func control(_ identifier: String) throws -> NSButton {
            let matches = formButtons.filter { $0.identifier?.rawValue == identifier }
            try expect(matches.count == 1, "Exactly one \(identifier) control")
            return matches[0]
        }
        let modernRadio = try control("appearanceModern"), classicRadio = try control("appearanceClassic"), relaunch = try control("appearanceRelaunch")
        try expect(modernRadio.state == (osDefault == .modern ? .on : .off) && classicRadio.state == (osDefault == .classic ? .on : .off),
                   "The form opens on the stored or default appearance")
        classicRadio.performClick(nil)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == "classic" && classicRadio.state == .on && modernRadio.state == .off,
                   "Classic radio persists classic")
        modernRadio.performClick(nil)
        try expect(appearanceDefaults.string(forKey: AppearanceResolver.defaultsKey) == "modern" && modernRadio.state == .on && classicRadio.state == .off,
                   "Modern radio persists modern")
        let beforeRelaunch = appearanceDefaults.persistentDomain(forName: appearanceDomain)!
        relaunch.performClick(nil)
        try expect(relaunches == 1 && NSDictionary(dictionary: appearanceDefaults.persistentDomain(forName: appearanceDomain)!).isEqual(to: beforeRelaunch),
                   "Relaunch calls back once and writes no preference")
        resolver.store(nil)
        form.synchronize(appearanceStore.state)
        try expect(modernRadio.state == (osDefault == .modern ? .on : .off) && classicRadio.state == (osDefault == .classic ? .on : .off),
                   "Removing the key shows the OS default in the form")
        print("OriginalGeneralPreferencesTests: \(checks) checks passed")
    }
}
#endif
