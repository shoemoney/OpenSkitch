import AppKit

/// Original MainMenu.nib bindings and PrefsController/SkitchSound preference keys.
/// `appearanceKey` is the one reconstruction key here: it has no original Skitch counterpart.
/// Parent controllers own effects; this store only resolves and persists values.
@MainActor
struct OriginalGeneralPreferences {
    let defaults: UserDefaults
    static let precisionKey = "fittingPrecision"
    static let captureKey = "skitchInSnap"
    static let soundsKey = "disableSounds"
    static let presenceKey = "statusMenu"
    static let overlaysKey = "disableOverlay"
    static let keyboardTipsKey = "disableModtips"
    static let appearanceKey = AppearanceResolver.defaultsKey

    static func precisionTag(_ mode: StrokeSmoothing) -> Int {
        switch mode { case .precise: return 0; case .medium: return 1; case .loose: return 2 }
    }
    static func precision(_ tag: Int) -> StrokeSmoothing? {
        switch tag { case 0: return .precise; case 1: return .medium; case 2: return .loose; default: return nil }
    }
    var state: GeneralPreferencesState {
        // Original engine falls back to Medium when its key is absent. Keep an
        // existing reconstruction choice until an explicit precision change.
        let original = (defaults.object(forKey: Self.precisionKey) as? NSNumber).flatMap { Self.precision($0.intValue) }
        let previous = defaults.string(forKey: "PencilSmoothing").flatMap(StrokeSmoothing.init(rawValue:))
        let presence = defaults.integer(forKey: Self.presenceKey)
        return GeneralPreferencesState(drawingPrecision: original ?? previous ?? .medium,
            arrowHead: defaults.integer(forKey: OriginalArrowGeometry.preferenceKey) == 1 ? 1 : 2,
            includeSkitch: defaults.bool(forKey: Self.captureKey),
            playSounds: !defaults.bool(forKey: Self.soundsKey),
            statusMenu: (0...2).contains(presence) ? presence : 0,
            showToolTips: defaults.object(forKey: Self.overlaysKey) != nil && !defaults.bool(forKey: Self.overlaysKey),
            showKeyboardTips: defaults.object(forKey: Self.keyboardTipsKey) != nil && !defaults.bool(forKey: Self.keyboardTipsKey),
            appearance: AppearanceResolver(defaults: defaults).preferredStyle)
    }
    func setPrecision(_ mode: StrokeSmoothing) {
        defaults.set(Self.precisionTag(mode), forKey: Self.precisionKey)
        defaults.set(mode.rawValue, forKey: "PencilSmoothing")
    }
    func apply(_ proposed: GeneralPreferencesState) {
        let current = state
        if proposed.drawingPrecision != current.drawingPrecision { setPrecision(proposed.drawingPrecision) }
        if proposed.arrowHead != current.arrowHead, [1, 2].contains(proposed.arrowHead) {
            defaults.set(proposed.arrowHead, forKey: OriginalArrowGeometry.preferenceKey)
        }
        if proposed.includeSkitch != current.includeSkitch { defaults.set(proposed.includeSkitch, forKey: Self.captureKey) }
        if proposed.playSounds != current.playSounds { defaults.set(!proposed.playSounds, forKey: Self.soundsKey) }
        if proposed.statusMenu != current.statusMenu, (0...2).contains(proposed.statusMenu) {
            defaults.set(proposed.statusMenu, forKey: Self.presenceKey)
        }
        if proposed.showToolTips != current.showToolTips { defaults.set(!proposed.showToolTips, forKey: Self.overlaysKey) }
        if proposed.showKeyboardTips != current.showKeyboardTips { defaults.set(!proposed.showKeyboardTips, forKey: Self.keyboardTipsKey) }
        if proposed.appearance != current.appearance { AppearanceResolver(defaults: defaults).store(proposed.appearance) }
    }
    func includeApp(mode: String, manualOption: Bool) -> Bool {
        guard mode == "crosshair" || mode == "fullscreen" else { return false }
        return state.includeSkitch != manualOption
    }
}
