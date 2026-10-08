// Pure standalone tests; every defaults write uses a unique disposable suite.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D RESIZE_PRESETS_TESTS Sources/ResizePresets.swift tests/ResizePresetsTests.swift \
//   -o /tmp/skitch-resize-presets-tests
// rtk proxy /tmp/skitch-resize-presets-tests
#if RESIZE_PRESETS_TESTS
import Foundation
import CoreGraphics

@main
private enum ResizePresetsTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }

    static func rejects(_ expected: ResizePresetError? = nil, _ body: () throws -> Void) throws {
        do { try body() }
        catch let error as ResizePresetError {
            try expect(expected == nil || error == expected, "Wrong rejection: \(error)")
            return
        }
        throw Failure(description: "Invalid operation was admitted")
    }

    static func suite(_ body: (UserDefaults) throws -> Void) throws {
        let name = "SkitchRedux.ResizePresetsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { throw Failure(description: "Suite unavailable") }
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
        NSDictionary(dictionary: ["value": lhs]).isEqual(to: ["value": rhs])
    }

    static func main() throws {
        try catalog()
        try validation()
        try persistence()
        try corruption()
        try originalEvidence()
        print("ResizePresetsTests: \(checks) checks passed")
    }

    static func catalog() throws {
        let rows: [(String, Int, Int)] = [
            ("Ad: Rectangle (Large)", 336, 280), ("Ad: Rectangle (Medium)", 300, 250),
            ("Ad: Rectangle (Small)", 240, 160), ("Ad: Thumbnail", 100, 100),
            ("Ad: Square Pop-up", 250, 250), ("Ad: Leaderboard", 728, 90),
            ("Ad: Banner (Full)", 468, 60), ("Ad: Banner (Half)", 234, 60),
            ("Ad: Sky Scraper", 120, 600), ("Ad: Sky Scraper (Wide)", 160, 600),
            ("KeyFrame: Viddler", 437, 370), ("KeyFrame: YouTube", 425, 355),
            ("Dribble", 400, 300)]
        try expect(ResizePreset.builtins.count == 13, "Original catalog count")
        try expect(Set(ResizePreset.builtins.map(\.id)).count == 13, "Unique builtin IDs")
        try expect(PresetResizeMode.crop.rawValue == 0 && PresetResizeMode.scale.rawValue == 1
                   && PresetResizeMode.limit.rawValue == 2, "Original resize mode values")
        try expect(ResizeLimitMode.greatest.rawValue == 0 && ResizeLimitMode.width.rawValue == 1
                   && ResizeLimitMode.height.rawValue == 2, "Original limit mode values")
        for (index, row) in rows.enumerated() {
            let preset = ResizePreset.builtins[index]
            try preset.validate()
            try expect(preset.name == row.0 && preset.width == row.1 && preset.height == row.2, "Catalog row \(index)")
            try expect(preset.mode == .scale && preset.format == 0 && preset.anchor == 4
                       && preset.limitMode == .greatest && preset.limitSize == 500 && !preset.editable,
                       "Inherited original fields \(index)")
            try expect(preset.proportions == (index >= 10), "Original proportions flags \(index)")
            try expect(preset.settings.count == 10, "Exactly ten legacy keys")
            try expect(try ResizePreset(settings: preset.settings, id: preset.id) == preset, "Legacy schema round trip")
        }
        let missing = try ResizePreset(settings: [:], id: "test")
        try expect(missing == ResizePreset(id: "test"), "Missing fields inherit recovered SKResize init defaults")
        try expect(missing.name == "NewSize" && missing.width == 640 && missing.height == 480
                   && missing.proportions && missing.editable, "Recovered init defaults")
        for anchor in 0...8 {
            let preset = ResizePreset(anchor: anchor)
            try expect(preset.anchorPoint == CGPoint(x: CGFloat(anchor % 3) / 2, y: CGFloat(anchor / 3) / 2),
                       "Top-left origin anchor \(anchor)")
        }
    }

    static func validation() throws {
        for field in [ResizePresetKeys.width, ResizePresetKeys.height, ResizePresetKeys.limitSize] {
            for value: Any in [0, -1, 16_385, Int.max, Double.nan, Double.infinity,
                               -Double.infinity, 1.5, "640", true, NSNull(), [1]] {
                try rejects { _ = try ResizePreset(settings: [field: value]) }
            }
            for value in [1, 16_384] {
                var settings = [field: value]
                settings[ResizePresetKeys.width] = field == ResizePresetKeys.width ? value : 1
                settings[ResizePresetKeys.height] = field == ResizePresetKeys.height ? value : 1
                _ = try ResizePreset(settings: settings)
                checks += 1
            }
        }
        try ResizePreset(width: 8000, height: 4000).validate(); checks += 1
        try rejects(.pixelCount) { try ResizePreset(width: 8000, height: 4001).validate() }
        try rejects(.pixelCount) { try ResizePreset(width: 16384, height: 16384).validate() }
        try rejects(.dimensions) { try ResizePreset(width: Int.max, height: Int.max).validate() }
        for field in [ResizePresetKeys.mode, ResizePresetKeys.limitMode] {
            for value: Any in [-1, 3, 2.5, "1", true] {
                try rejects { _ = try ResizePreset(settings: [field: value]) }
            }
        }
        for field in [ResizePresetKeys.editable, ResizePresetKeys.proportions] {
            for value: Any in [-1, 2, 0.5, "true", "1", NSNull()] {
                try rejects { _ = try ResizePreset(settings: [field: value]) }
            }
            for value: Any in [false, true, NSNumber(value: 0), NSNumber(value: 1)] {
                _ = try ResizePreset(settings: [field: value]); checks += 1
            }
        }
        for name in ["", " \n", "bad\0name", String(repeating: "a", count: 1025)] {
            try rejects { try ResizePreset(name: name).validate() }
        }
        try rejects { _ = try ResizePreset(settings: [ResizePresetKeys.name: 3]) }
        for value: Any in [-1, 9, true, "4"] {
            try rejects { _ = try ResizePreset(settings: [ResizePresetKeys.anchor: value]) }
        }
        for value: Any in [Int.max, Int.min, Double.nan, 0.5, true, "0"] {
            try rejects { _ = try ResizePreset(settings: [ResizePresetKeys.format: value]) }
        }
        for value in [Int(Int32.min), Int(Int32.max), 77] {
            try expect(try ResizePreset(settings: [ResizePresetKeys.format: value]).format == value,
                       "Unknown signed 32-bit formats remain opaque")
        }
        try rejects { _ = try ResizePreset(settings: [ResizePresetKeys.width: NSDecimalNumber(string: "1.000000000000001")]) }
    }

    static func persistence() throws {
        try suite { defaults in
            let store = ResizePresetStore(defaults: defaults)
            try expect(store.presets == ResizePreset.builtins && !store.hasMalformedData, "Fresh catalog")
            try expect(defaults.object(forKey: ResizePresetKeys.defaults) == nil, "Read-only initialization")
            var custom = ResizePreset(id: "custom", name: "Website", width: 1000, height: 800,
                                      mode: .crop, format: 77, anchor: 8, proportions: false,
                                      limitSize: 1024, limitMode: .height)
            try store.add(custom)
            try expect(store.presets.count == 14, "Addition")
            let saved = defaults.object(forKey: ResizePresetKeys.defaults)!
            let second = ResizePresetStore(defaults: defaults)
            try expect(second.presets == store.presets, "Reopen entire array")
            try expect(equal(saved, defaults.object(forKey: ResizePresetKeys.defaults)!), "Reopen performs no write")
            custom.name = "Renamed"; custom.mode = .limit; custom.limitMode = .width
            try store.update(custom)
            try expect(ResizePresetStore(defaults: defaults).presets.last == custom, "Update and stable ID")
            try rejects(.staleDefaults) { try second.remove(id: custom.id) }
            second.reload()
            try second.remove(id: custom.id)
            try expect(ResizePresetStore(defaults: defaults).presets == ResizePreset.builtins, "Removal persisted")
            let before = defaults.object(forKey: ResizePresetKeys.defaults)!
            for builtin in ResizePreset.builtins {
                try rejects(.protectedBuiltin) { try second.remove(id: builtin.id) }
                var edited = builtin; edited.editable = true; edited.width = 1
                try rejects(.protectedBuiltin) { try second.update(edited) }
                try rejects(.protectedBuiltin) { try second.add(edited) }
            }
            try rejects(.unknownID) { try second.remove(id: "absent") }
            try rejects(.unknownID) { try second.update(ResizePreset(id: "absent")) }
            var reserved = ResizePreset(name: ResizePreset.builtins[0].name)
            try rejects(.protectedBuiltin) { try second.add(reserved) }
            reserved.name = "Valid"; reserved.width = 0
            try rejects(.dimensions) { try second.add(reserved) }
            try expect(equal(before, defaults.object(forKey: ResizePresetKeys.defaults)!), "Failures make no partial writes")
            try second.add(custom)
            try rejects(.duplicateID) { try second.add(custom) }
        }
        try suite { defaults in
            var legacy = ResizePreset(name: "Legacy", mode: .limit, limitMode: .height).settings
            legacy["UnknownLegacyExtension"] = ["preserve": [1, 2, 3]]
            defaults.set([legacy], forKey: ResizePresetKeys.defaults)
            let store = ResizePresetStore(defaults: defaults)
            try expect(store.presets.count == 14 && store.presets.last?.id == "legacy:0", "Legacy custom migration")
            try expect(equal([legacy], defaults.object(forKey: ResizePresetKeys.defaults)!), "Migration does not write on load")
            var edited = store.presets.last!; edited.name = "Legacy renamed"
            try store.update(edited)
            let rows = defaults.array(forKey: ResizePresetKeys.defaults) as! [[String: Any]]
            try expect(equal(rows.last!["UnknownLegacyExtension"]!, legacy["UnknownLegacyExtension"]!), "Unknown fields survive update")
            try expect(rows.last![ResizePresetKeys.id] as? String == "legacy:0", "ID migrated with same atomic value")
            try expect(ResizePresetStore(defaults: defaults).presets.last == edited, "Migrated identity survives reopen")
            try store.remove(id: edited.id)
            try expect(store.presets == ResizePreset.builtins, "Migrated custom removal")
        }
        try suite { defaults in
            defaults.set(ResizePreset.builtins.map(\.settings), forKey: ResizePresetKeys.defaults)
            let store = ResizePresetStore(defaults: defaults)
            try expect(!store.hasMalformedData && store.presets == ResizePreset.builtins, "Original complete catalog admission")
            try store.add(ResizePreset(name: "Custom"))
            let rows = defaults.array(forKey: ResizePresetKeys.defaults) as! [[String: Any]]
            try expect(rows.prefix(13).allSatisfy { $0.count == 10 }, "Builtins persist original ten-key schema")
        }
        try suite { defaults in
            defaults.set([], forKey: ResizePresetKeys.defaults)
            let store = ResizePresetStore(defaults: defaults)
            try expect(store.presets == ResizePreset.builtins && !store.hasMalformedData, "Original empty-array fallback")
        }
        try suite { defaults in
            let locked = ResizePreset(name: "Legacy locked", editable: false)
            defaults.set([locked.settings], forKey: ResizePresetKeys.defaults)
            let store = ResizePresetStore(defaults: defaults)
            let imported = store.presets.last!
            try expect(!imported.editable && imported.name == locked.name, "Legacy custom protection is retained")
            try rejects(.protectedBuiltin) { try store.remove(id: imported.id) }
            var edited = imported; edited.editable = true
            try rejects(.protectedBuiltin) { try store.update(edited) }
        }
    }

    static func corruption() throws {
        var hostile = ResizePreset.builtins[0].settings
        hostile[ResizePresetKeys.width] = 1
        hostile[ResizePresetKeys.editable] = true
        var duplicate = ResizePreset(name: "Dup").settings
        duplicate[ResizePresetKeys.id] = "same"
        var badID = ResizePreset(name: "BadID").settings
        badID[ResizePresetKeys.id] = 123
        var spoof = ResizePreset(name: "Spoof").settings
        spoof[ResizePresetKeys.id] = "builtin:0"
        let badValues: [Any] = ["bad", 42, Data([0, 1]), ["bad"], [[ResizePresetKeys.width: 0]],
                                [hostile], [duplicate, duplicate], [badID], [spoof],
                                [ResizePreset.builtins[0].settings, ResizePreset.builtins[0].settings]]
        for bad in badValues {
            try suite { defaults in
                defaults.set(bad, forKey: ResizePresetKeys.defaults)
                let store = ResizePresetStore(defaults: defaults)
                try expect(store.hasMalformedData && !store.loadIssues.isEmpty, "Corruption reported")
                try expect(Array(store.presets.prefix(13)) == ResizePreset.builtins, "Canonical builtins remain protected")
                try rejects(.malformedDefaults) { try store.add(ResizePreset(name: "New")) }
                try rejects(.malformedDefaults) { try store.remove(id: "builtin:0") }
                try expect(equal(bad, defaults.object(forKey: ResizePresetKeys.defaults)!), "Malformed legacy data never erased")
            }
        }
        try suite { defaults in
            defaults.set([ResizePreset(name: "Survivor").settings, [ResizePresetKeys.width: -1]],
                         forKey: ResizePresetKeys.defaults)
            let store = ResizePresetStore(defaults: defaults)
            try expect(store.presets.last?.name == "Survivor" && store.hasMalformedData, "Valid rows remain readable in a corrupt array")
            try rejects(.malformedDefaults) { try store.remove(id: store.presets.last!.id) }
        }
        try suite { defaults in
            let store = ResizePresetStore(defaults: defaults)
            defaults.set("external corrupt write", forKey: ResizePresetKeys.defaults)
            try rejects(.staleDefaults) { try store.add(ResizePreset(name: "New")) }
            try expect(defaults.string(forKey: ResizePresetKeys.defaults) == "external corrupt write", "External corruption preserved")
        }
    }

    // Read-only independent fixture evidence. Run from the repository root.
    // Resolves the original i386 Mach-O VM addresses used by disassembly;
    // verifies actual CFString key literals and catalog spellings, not strings
    // copied from the new implementation. No application or live prefs touched.
    // Both inputs are git-ignored, so a fresh clone lacks them: only their absence skips
    // (with a SKIP line); a present but unreadable or mismatched input still throws.
    static func originalEvidence() throws {
        let binaryPath = "original/Skitch.app/Contents/MacOS/Skitch", disassemblyPath = "analysis/disassembly.txt"
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            print("SKIP original evidence: \(binaryPath) not present")
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: binaryPath))
        func word(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        try expect(word(0) == 0xfeedface, "Original i386 Mach-O fixture")
        var segments: [(Int, Int, Int)] = []
        var position = 28
        for _ in 0..<word(16) {
            if word(position) == 1 { segments.append((word(position + 24), word(position + 36), word(position + 32))) }
            position += word(position + 4)
        }
        func offset(_ address: Int) throws -> Int {
            guard let segment = segments.first(where: { address >= $0.0 && address < $0.0 + $0.1 }) else {
                throw Failure(description: "Unmapped original address")
            }
            return segment.2 + address - segment.0
        }
        func pointer(_ address: Int) throws -> Int { word(try offset(address)) }
        func string(_ address: Int) throws -> String {
            let start = try offset(address)
            guard let end = data[start...].firstIndex(of: 0),
                  let value = String(data: data[start..<end], encoding: .utf8) else {
                throw Failure(description: "Invalid original literal")
            }
            return value
        }
        let keys = [ResizePresetKeys.name, ResizePresetKeys.editable, ResizePresetKeys.mode,
                    ResizePresetKeys.format, ResizePresetKeys.width, ResizePresetKeys.height,
                    ResizePresetKeys.anchor, ResizePresetKeys.proportions,
                    ResizePresetKeys.limitMode, ResizePresetKeys.limitSize]
        for (index, key) in keys.enumerated() {
            let cfstring = try pointer(0x288a38 + index * 4)
            try expect(try string(pointer(cfstring + 8)) == key, "Original key pointer \(index)")
        }
        try expect(try string(pointer(0x28c68c + 8)) == ResizePresetKeys.defaults, "Original defaults key")
        for (index, preset) in ResizePreset.builtins.enumerated() {
            try expect(try string(pointer(0x28c69c + index * 16 + 8)) == preset.name, "Original catalog literal \(index)")
        }
        // Recover numeric setter arguments from the original loadPresets body.
        guard FileManager.default.fileExists(atPath: disassemblyPath) else {
            print("SKIP original disassembly evidence: \(disassemblyPath) not present")
            return
        }
        let disassembly = try String(contentsOfFile: disassemblyPath, encoding: .utf8)
        guard let start = disassembly.range(of: "-[SKResizeController loadPresets]:"),
              let end = disassembly.range(of: "-[SKResizeController savePresets]:", range: start.upperBound..<disassembly.endIndex) else {
            throw Failure(description: "Original loadPresets evidence missing")
        }
        let pointerPattern = try NSRegularExpression(pattern: #"(movl|leal)\s+0x([0-9a-f]+)\(%(?:ebx|esi)\)"#)
        let argumentPattern = try NSRegularExpression(pattern: #"movl\s+\$0x([0-9a-f]+), 0x8\(%esp\)"#)
        var recovered: [[String: Int]] = []
        var selector: String?
        var argument: Int?
        for line in disassembly[start.upperBound..<end.lowerBound].components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = pointerPattern.firstMatch(in: line, range: range),
               let kindRange = Range(match.range(at: 1), in: line),
               let numberRange = Range(match.range(at: 2), in: line),
               let displacement = Int(line[numberRange], radix: 16) {
                let address = 0x75289 + displacement
                if line[kindRange] == "movl" { selector = try? string(pointer(address)); argument = nil }
                else if (0x28c69c...0x28c75c).contains(address) {
                    recovered.append([:])
                }
            }
            if let match = argumentPattern.firstMatch(in: line, range: range),
               let valueRange = Range(match.range(at: 1), in: line) {
                argument = Int(line[valueRange], radix: 16)
            }
            if line.contains("calll"), !recovered.isEmpty, let selector = selector,
               selector.hasPrefix("set"), let value = argument {
                recovered[recovered.count - 1][selector] = value
                argument = nil
            }
        }
        try expect(recovered.count == 13, "Disassembled catalog count")
        for (index, preset) in ResizePreset.builtins.enumerated() {
            let values = recovered[index]
            try expect(values["setWidth:"] == preset.width && values["setHeight:"] == preset.height,
                       "Disassembled catalog dimensions \(index)")
            try expect(values["setMode:", default: 1] == preset.mode.rawValue
                       && values["setConstrainProportions:", default: 1] == (preset.proportions ? 1 : 0)
                       && values["setEditable:"] == 0, "Disassembled catalog flags \(index)")
        }
    }
}
#endif
