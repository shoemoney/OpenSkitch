import AppKit

enum AppearanceStyle: String, CaseIterable, Codable, Sendable { case classic, modern }

/// Pure resolver; no views. Environment override, then stored preference, then the OS default.
/// Modern needs macOS 26, so anything below always resolves to Classic.
struct AppearanceResolver {
    /// Reconstruction key, not one of the original Skitch preferences: "classic" or "modern".
    static let defaultsKey = "appearanceStyle"
    /// Test pin and developer override; read only by `effectiveStyle`.
    static let environmentKey = "SKITCH_APPEARANCE"
    private let environment: [String: String]
    private let defaults: UserDefaults
    private let operatingSystem: OperatingSystemVersion

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         defaults: UserDefaults = .standard,
         operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.environment = environment
        self.defaults = defaults
        self.operatingSystem = operatingSystem
    }

    var supportsModern: Bool { operatingSystem.majorVersion >= 26 }
    var storedChoice: AppearanceStyle? { defaults.string(forKey: Self.defaultsKey).flatMap(AppearanceStyle.init(rawValue:)) }
    var preferredStyle: AppearanceStyle { storedChoice ?? (supportsModern ? .modern : .classic) }
    var effectiveStyle: AppearanceStyle {
        let requested = environment[Self.environmentKey].flatMap(AppearanceStyle.init(rawValue:)) ?? preferredStyle
        return supportsModern ? requested : .classic
    }

    /// `nil` removes the stored choice, so the OS default applies again.
    func store(_ style: AppearanceStyle?) {
        if let style { defaults.set(style.rawValue, forKey: Self.defaultsKey) }
        else { defaults.removeObject(forKey: Self.defaultsKey) }
    }
}

/// The style this process runs with, resolved once on first use; changing it takes a relaunch.
@MainActor
enum Appearance {
    private static var resolved: AppearanceStyle?
    static var current: AppearanceStyle {
        if let resolved { return resolved }
        let style = AppearanceResolver().effectiveStyle
        resolved = style
        return style
    }
    static var isModern: Bool { current == .modern }
    /// Pins the style for tests; `nil` releases the pin so the next read resolves again.
    static func overrideForTesting(_ style: AppearanceStyle?) { resolved = style }
}

/// The three system display options the chrome adapts to, as a value so tests can inject them.
struct ChromeAccessibility: Equatable, Sendable {
    var reduceTransparency: Bool, increaseContrast: Bool, reduceMotion: Bool
    static let none = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false)
    @MainActor static var live: ChromeAccessibility { reading(.shared) }
    @MainActor static func reading(_ workspace: NSWorkspace) -> ChromeAccessibility {
        ChromeAccessibility(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}
