// Standalone native tests; no windows or desktop automation.
// xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -framework AppKit -D APPEARANCE_TESTS \
//   Sources/Appearance.swift tests/AppearanceTests.swift -o build/appearance-tests
// build/appearance-tests
#if APPEARANCE_TESTS
import AppKit

@main
@MainActor
private enum AppearanceTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    private static func requireSendable<T: Sendable>(_ value: T) -> T { value }

    private final class FakeWorkspace: NSWorkspace {
        let transparency: Bool, contrast: Bool, motion: Bool
        init(transparency: Bool, contrast: Bool, motion: Bool) {
            self.transparency = transparency; self.contrast = contrast; self.motion = motion
            super.init()
        }
        override var accessibilityDisplayShouldReduceTransparency: Bool { transparency }
        override var accessibilityDisplayShouldIncreaseContrast: Bool { contrast }
        override var accessibilityDisplayShouldReduceMotion: Bool { motion }
    }

    private static func system(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    private static func valid(_ value: Any?) -> AppearanceStyle? {
        (value as? String).flatMap(AppearanceStyle.init(rawValue:))
    }

    static func main() throws {
        _ = NSApplication.shared
        let standardBefore = UserDefaults.standard.object(forKey: AppearanceResolver.defaultsKey) as? String
        let environmentBefore = ProcessInfo.processInfo.environment[AppearanceResolver.environmentKey]
        let domain = "OpenSkitch.appearance.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            if let environmentBefore { setenv(AppearanceResolver.environmentKey, environmentBefore, 1) }
            else { unsetenv(AppearanceResolver.environmentKey) }
            Appearance.overrideForTesting(nil)
        }

        // Names and raw values are the persisted/launch contract.
        expect(AppearanceStyle.allCases == [.classic, .modern], "Exactly two styles, classic first")
        expect(AppearanceStyle.classic.rawValue == "classic" && AppearanceStyle.modern.rawValue == "modern", "Raw values are the stored words")
        expect(AppearanceStyle(rawValue: "Modern") == nil && AppearanceStyle(rawValue: "") == nil, "Raw values are case-sensitive and nonempty")
        expect(AppearanceResolver.defaultsKey == "appearanceStyle", "Defaults key")
        expect(AppearanceResolver.environmentKey == "SKITCH_APPEARANCE", "Environment key")
        let encoded = try JSONEncoder().encode([AppearanceStyle.classic, .modern])
        expect(String(decoding: encoded, as: UTF8.self) == "[\"classic\",\"modern\"]", "Codable uses the raw words")
        let decoded = try JSONDecoder().decode([AppearanceStyle].self, from: encoded)
        expect(decoded == [.classic, .modern], "Codable round trip")
        expect(requireSendable(AppearanceStyle.modern) == .modern, "AppearanceStyle is Sendable")

        // Hand-written rows: (major, minor, stored, environment) -> supports, preferred, effective.
        typealias Row = (os: (Int, Int), stored: String?, env: String?, supports: Bool, preferred: AppearanceStyle, effective: AppearanceStyle)
        let pinned: [Row] = [
            ((25, 0), nil, nil, false, .classic, .classic),
            ((25, 9), nil, "modern", false, .classic, .classic),
            ((25, 0), "modern", "modern", false, .modern, .classic),
            ((25, 0), "classic", nil, false, .classic, .classic),
            ((26, 0), nil, nil, true, .modern, .modern),
            ((26, 0), "classic", nil, true, .classic, .classic),
            ((26, 0), "modern", "classic", true, .modern, .classic),
            ((26, 0), "garbage", "garbage", true, .modern, .modern),
            ((26, 0), "classic", "garbage", true, .classic, .classic),
            ((26, 4), nil, "classic", true, .modern, .classic),
            ((27, 0), nil, nil, true, .modern, .modern),
            ((27, 0), "classic", nil, true, .classic, .classic),
            ((27, 0), "classic", "modern", true, .classic, .modern),
            ((27, 0), nil, "classic", true, .modern, .classic),
            ((27, 2), "garbage", "classic", true, .modern, .classic),
            ((13, 0), "modern", "modern", false, .modern, .classic),
            ((99, 0), nil, nil, true, .modern, .modern)
        ]
        for row in pinned {
            defaults.removeObject(forKey: AppearanceResolver.defaultsKey)
            if let stored = row.stored { defaults.set(stored, forKey: AppearanceResolver.defaultsKey) }
            let environment = row.env.map { [AppearanceResolver.environmentKey: $0] } ?? [:]
            let resolver = AppearanceResolver(environment: environment, defaults: defaults, operatingSystem: system(row.os.0, row.os.1))
            let label = "macOS \(row.os.0).\(row.os.1) stored \(row.stored ?? "nil") env \(row.env ?? "nil")"
            expect(resolver.supportsModern == row.supports, "supportsModern for \(label)")
            expect(resolver.preferredStyle == row.preferred, "preferredStyle for \(label)")
            expect(resolver.effectiveStyle == row.effective, "effectiveStyle for \(label)")
        }

        // Full matrix against an independent oracle, including malformed stored and environment values.
        let storedCases: [Any?] = [nil, "classic", "modern", "", "Modern", "CLASSIC", " modern", "glass", "modern\n", 1, true, 2.5, Data([1, 2])]
        let environmentCases: [String?] = [nil, "classic", "modern", "", "Modern", "MODERN", "liquid", "classic ", "0"]
        var matrix = 0
        for major in [12, 13, 14, 15, 25, 26, 27, 28, 99] {
            for minor in [0, 6] {
                for stored in storedCases {
                    for env in environmentCases {
                        defaults.removeObject(forKey: AppearanceResolver.defaultsKey)
                        if let stored { defaults.set(stored, forKey: AppearanceResolver.defaultsKey) }
                        var environment = ["PATH": "/usr/bin", "HOME": "/nonexistent"]
                        if let env { environment[AppearanceResolver.environmentKey] = env }
                        let resolver = AppearanceResolver(environment: environment, defaults: defaults, operatingSystem: system(major, minor))
                        let supports = major >= 26
                        let preferred = valid(stored) ?? (supports ? .modern : .classic)
                        let effective = supports ? (valid(env) ?? preferred) : .classic
                        let label = "macOS \(major).\(minor) stored \(String(describing: stored)) env \(env ?? "nil")"
                        expect(resolver.supportsModern == supports, "supportsModern for \(label)")
                        expect(resolver.storedChoice == valid(stored), "storedChoice for \(label)")
                        expect(resolver.preferredStyle == preferred, "preferredStyle ignores the environment for \(label)")
                        expect(resolver.effectiveStyle == effective, "effectiveStyle for \(label)")
                        expect(resolver.effectiveStyle == .classic || supports, "Modern is never effective below macOS 26 for \(label)")
                        matrix += 1
                    }
                }
            }
        }
        expect(matrix == 9 * 2 * storedCases.count * environmentCases.count, "Whole matrix was walked")

        // Reading never writes: malformed stored values are left for the user to see and fix.
        defaults.set("glass", forKey: AppearanceResolver.defaultsKey)
        let reader = AppearanceResolver(environment: [:], defaults: defaults, operatingSystem: system(27))
        _ = (reader.storedChoice, reader.preferredStyle, reader.effectiveStyle)
        expect(defaults.string(forKey: AppearanceResolver.defaultsKey) == "glass", "Resolving never rewrites a malformed stored value")

        // store(_:) writes the raw word, replaces any value, and nil removes the key without touching neighbours.
        defaults.removeObject(forKey: AppearanceResolver.defaultsKey)
        defaults.set("kept", forKey: "OpenSkitch.appearance.tests.neighbour")
        let writer = AppearanceResolver(environment: [:], defaults: defaults, operatingSystem: system(27))
        writer.store(.classic)
        expect(defaults.string(forKey: AppearanceResolver.defaultsKey) == "classic" && writer.storedChoice == .classic, "store(.classic) persists the word")
        expect(writer.preferredStyle == .classic && writer.effectiveStyle == .classic, "Stored classic beats the macOS 27 default")
        writer.store(.modern)
        expect(defaults.string(forKey: AppearanceResolver.defaultsKey) == "modern" && writer.storedChoice == .modern, "store(.modern) replaces the previous choice")
        expect(AppearanceResolver(environment: [:], defaults: defaults, operatingSystem: system(26)).storedChoice == .modern, "A second resolver sees the persisted word")
        writer.store(nil)
        expect(defaults.object(forKey: AppearanceResolver.defaultsKey) == nil, "store(nil) removes the key")
        expect(writer.storedChoice == nil && writer.preferredStyle == .modern, "Removing the key returns to the OS default")
        writer.store(nil)
        expect(defaults.object(forKey: AppearanceResolver.defaultsKey) == nil, "Removing an absent key is harmless")
        defaults.set("glass", forKey: AppearanceResolver.defaultsKey)
        writer.store(.classic)
        expect(defaults.string(forKey: AppearanceResolver.defaultsKey) == "classic", "A valid choice overwrites a malformed value")
        defaults.set("glass", forKey: AppearanceResolver.defaultsKey)
        writer.store(nil)
        expect(defaults.object(forKey: AppearanceResolver.defaultsKey) == nil, "nil also clears a malformed value")
        expect(defaults.string(forKey: "OpenSkitch.appearance.tests.neighbour") == "kept", "Neighbouring keys are untouched")
        let belowFloor = AppearanceResolver(environment: [:], defaults: defaults, operatingSystem: system(25))
        belowFloor.store(.modern)
        expect(belowFloor.storedChoice == .modern && belowFloor.effectiveStyle == .classic, "A stored Modern is kept but not applied below macOS 26")

        // The default initializer reads this process and this machine.
        let live = AppearanceResolver()
        expect(live.supportsModern == (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26), "Default resolver reads the running OS")

        // Appearance resolves once per process; overrideForTesting pins and nil releases.
        defaults.removeObject(forKey: AppearanceResolver.defaultsKey)
        Appearance.overrideForTesting(.modern)
        expect(Appearance.current == .modern && Appearance.isModern, "Override pins Modern")
        Appearance.overrideForTesting(.classic)
        expect(Appearance.current == .classic && !Appearance.isModern, "Override pins Classic")
        setenv(AppearanceResolver.environmentKey, "modern", 1)
        expect(Appearance.current == .classic, "A pinned style ignores later environment changes")
        Appearance.overrideForTesting(nil)
        let first = Appearance.current
        expect(first == AppearanceResolver().effectiveStyle, "Releasing the pin resolves through AppearanceResolver")
        expect(first == .classic || AppearanceResolver().supportsModern, "Resolved Modern implies a supporting OS")
        expect(Appearance.isModern == (first == .modern), "isModern follows current")
        setenv(AppearanceResolver.environmentKey, first == .modern ? "classic" : "modern", 1)
        let again = Appearance.current
        expect(again == first, "Resolved once per process, not per read")
        Appearance.overrideForTesting(nil)
        setenv(AppearanceResolver.environmentKey, "classic", 1)
        expect(Appearance.current == .classic && !Appearance.isModern, "SKITCH_APPEARANCE=classic pins Classic on any macOS")
        Appearance.overrideForTesting(nil)
        if AppearanceResolver().supportsModern {
            setenv(AppearanceResolver.environmentKey, "modern", 1)
            expect(Appearance.current == .modern && Appearance.isModern, "SKITCH_APPEARANCE=modern reaches Modern on a supporting OS")
        }
        Appearance.overrideForTesting(nil)

        // Accessibility snapshot.
        let none = ChromeAccessibility.none
        expect(!none.reduceTransparency && !none.increaseContrast && !none.reduceMotion, ".none has every option off")
        expect(none == ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false), ".none equals an all-off value")
        var seen: [ChromeAccessibility] = []
        for bits in 0..<8 {
            let value = ChromeAccessibility(reduceTransparency: bits & 1 != 0, increaseContrast: bits & 2 != 0, reduceMotion: bits & 4 != 0)
            expect(!seen.contains(value), "Each option combination is distinct")
            expect((value == none) == (bits == 0), "Only the empty combination equals .none")
            seen.append(value)
        }
        var changed = none
        changed.reduceMotion = true
        expect(changed != none && changed.reduceMotion && !changed.reduceTransparency && !changed.increaseContrast, "Options mutate independently")
        expect(requireSendable(ChromeAccessibility.none) == none, "ChromeAccessibility is Sendable")
        for bits in 0..<8 {
            let fake = FakeWorkspace(transparency: bits & 1 != 0, contrast: bits & 2 != 0, motion: bits & 4 != 0)
            expect(ChromeAccessibility.reading(fake) == ChromeAccessibility(reduceTransparency: bits & 1 != 0, increaseContrast: bits & 2 != 0,
                                                                            reduceMotion: bits & 4 != 0),
                   "Each display option maps to its own flag (combination \(bits))")
        }
        let workspace = NSWorkspace.shared
        expect(ChromeAccessibility.live == ChromeAccessibility(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion), "live reads the three shared workspace display options")

        // Nothing above may leak into the real preferences.
        expect(UserDefaults.standard.object(forKey: AppearanceResolver.defaultsKey) as? String == standardBefore, "Standard defaults were never written")
        print("AppearanceTests: \(checks) checks passed (pure resolver and accessibility snapshot; private defaults suite)")
    }
}
#endif
