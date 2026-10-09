// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -framework AppKit -D ORIGINAL_GENERAL_PREFERENCES_TESTS \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/DocumentModel.swift Sources/GeneralPreferencesForm.swift \
//   Sources/OriginalGeneralPreferences.swift tests/OriginalGeneralPreferencesTests.swift \
//   -o build/original-general-preferences-tests
// rtk proxy build/original-general-preferences-tests
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
        let domain = "OpenSnap.preferences.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = OriginalGeneralPreferences(defaults: defaults)
        let fresh = store.state
        try expect(fresh.drawingPrecision == .medium && fresh.arrowHead == 2 && !fresh.includeApp && fresh.statusMenu == 0,
                   "Fresh behavior follows original engine fallback, End/Both defaults and excluded app")
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
            defaults.set(include, forKey: "opensnapInSnap")
            for option in [false, true] {
                for mode in ["crosshair", "fullscreen", "window", "frame", "web"] {
                    let before = defaults.persistentDomain(forName: domain)!
                    try expect(store.includeApp(mode: mode, manualOption: option) == ((mode == "crosshair" || mode == "fullscreen") && (include != option)),
                               "Manual Option policy \(mode)/\(include)/\(option)")
                    try expect(NSDictionary(dictionary: defaults.persistentDomain(forName: domain)!).isEqual(to: before), "Temporary capture reversal never mutates saved settings")
                }
            }
            try expect(OriginalGeneralPreferences(defaults: UserDefaults(suiteName: domain)!).state.includeApp == include, "Saved inclusion reloads through another store")
        }
        for presence in [0, 1, 2] {
            var state = store.state; state.statusMenu = presence; state.arrowHead = presence == 1 ? 1 : 2
            state.drawingPrecision = .precise
            store.apply(state)
            let reopened = OriginalGeneralPreferences(defaults: UserDefaults(suiteName: domain)!).state
            try expect(reopened == state, "Native states persist together and reload exactly")
        }
        let before = store.state
        var invalid = before; invalid.statusMenu = 9; invalid.arrowHead = 9; store.apply(invalid)
        try expect(store.state == before, "Invalid radio tags cannot overwrite valid saved choices")
        defaults.set(17, forKey: "statusMenu"); defaults.set(17, forKey: "arrowHead")
        try expect(store.state.statusMenu == 0 && store.state.arrowHead == 2, "Unknown tags display semantic defaults without destructive rewrites")
        try expect(defaults.integer(forKey: "statusMenu") == 17 && defaults.integer(forKey: "arrowHead") == 17, "Reading invalid tags leaves external preference data intact")
        try expect(defaults.object(forKey: "disableSounds") == nil, "The app is silent and never writes a sound preference")
        print("OriginalGeneralPreferencesTests: \(checks) checks passed")
    }
}
#endif
