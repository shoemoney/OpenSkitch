import Foundation
import CoreGraphics

// Original PlatformController applyResize: at 0x10215, SKResize limitImage at
// 0x74a93. These are persisted values, not the Resize.nib control tags.
enum PresetResizeMode: Int, CaseIterable { case crop = 0, scale = 1, limit = 2 }
enum ResizeLimitMode: Int, CaseIterable { case greatest = 0, width = 1, height = 2 }

enum ResizePresetError: Error, LocalizedError, Equatable {
    case invalidField(String), dimensions, pixelCount, protectedBuiltin, unknownID, duplicateID
    case malformedDefaults, staleDefaults

    var errorDescription: String? {
        switch self {
        case .invalidField(let key): return "Invalid resize preset field: \(key)."
        case .dimensions: return "Enter whole pixel dimensions from 1 to 16,384."
        case .pixelCount: return "Choose a size with no more than 32 million pixels."
        case .protectedBuiltin: return "Built-in resize presets cannot be changed or removed."
        case .unknownID: return "The resize preset no longer exists."
        case .duplicateID: return "The resize preset identifier already exists."
        case .malformedDefaults: return "Saved resize presets contain invalid data. The original data has been preserved."
        case .staleDefaults: return "Saved resize presets changed. Reload before editing."
        }
    }
}

struct ResizePreset: Equatable, Identifiable {
    let id: String
    var name: String
    var width: Int
    var height: Int
    var mode: PresetResizeMode
    // Original signed 32-bit _format has no recovered enum or resize consumer.
    // Preserve it as opaque data; 0 is NSObject's zero-initialized default.
    var format: Int
    var anchor: Int
    var proportions: Bool
    var limitSize: Int
    var limitMode: ResizeLimitMode
    var editable: Bool

    // SKResize init (0x7446a): all defaults below are recovered, not UI guesses.
    init(id: String = UUID().uuidString, name: String = "NewSize", width: Int = 640,
         height: Int = 480, mode: PresetResizeMode = .scale, format: Int = 0,
         anchor: Int = 4, proportions: Bool = true, limitSize: Int = 500,
         limitMode: ResizeLimitMode = .greatest, editable: Bool = true) {
        self.id = id; self.name = name; self.width = width; self.height = height
        self.mode = mode; self.format = format; self.anchor = anchor
        self.proportions = proportions; self.limitSize = limitSize
        self.limitMode = limitMode; self.editable = editable
    }

    var size: CGSize { CGSize(width: width, height: height) }
    var anchorPoint: CGPoint { CGPoint(x: CGFloat(anchor % 3) / 2, y: CGFloat(anchor / 3) / 2) }
    var limit: Int { get { limitSize } set { limitSize = newValue } }

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 256 else { throw ResizePresetError.invalidField("id") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 1024, !name.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw ResizePresetError.invalidField(ResizePresetKeys.name)
        }
        guard (1...16_384).contains(width), (1...16_384).contains(height),
              (1...16_384).contains(limitSize) else { throw ResizePresetError.dimensions }
        guard width * height <= 32_000_000 else { throw ResizePresetError.pixelCount }
        guard (0...8).contains(anchor) else { throw ResizePresetError.invalidField(ResizePresetKeys.anchor) }
        guard Int32(exactly: format) != nil else { throw ResizePresetError.invalidField(ResizePresetKeys.format) }
    }

    // Exact ten keys from initWithSettings: (0x73cd6) / settings (0x740ed).
    var settings: [String: Any] {
        [ResizePresetKeys.name: name, ResizePresetKeys.editable: editable,
         ResizePresetKeys.mode: mode.rawValue, ResizePresetKeys.format: format,
         ResizePresetKeys.width: width, ResizePresetKeys.height: height,
         ResizePresetKeys.anchor: anchor, ResizePresetKeys.proportions: proportions,
         ResizePresetKeys.limitMode: limitMode.rawValue, ResizePresetKeys.limitSize: limitSize]
    }

    init(settings: [String: Any], id: String = UUID().uuidString) throws {
        self.init(id: id)
        if let value = settings[ResizePresetKeys.name] {
            guard let value = value as? String else { throw ResizePresetError.invalidField(ResizePresetKeys.name) }
            name = value
        }
        func integer(_ key: String, _ fallback: Int) throws -> Int {
            guard let value = settings[key] else { return fallback }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,
                  number.compare(NSNumber(value: Int32.min)) != .orderedAscending,
                  number.compare(NSNumber(value: Int32.max)) != .orderedDescending,
                  number.compare(NSNumber(value: number.intValue)) == .orderedSame else {
                throw ResizePresetError.invalidField(key)
            }
            return number.intValue
        }
        func boolean(_ key: String, _ fallback: Bool) throws -> Bool {
            guard let value = settings[key] else { return fallback }
            guard let number = value as? NSNumber,
                  number == NSNumber(value: 0) || number == NSNumber(value: 1) else {
                throw ResizePresetError.invalidField(key)
            }
            return number.boolValue
        }
        width = try integer(ResizePresetKeys.width, width)
        height = try integer(ResizePresetKeys.height, height)
        format = try integer(ResizePresetKeys.format, format)
        anchor = try integer(ResizePresetKeys.anchor, anchor)
        limitSize = try integer(ResizePresetKeys.limitSize, limitSize)
        let rawMode = try integer(ResizePresetKeys.mode, mode.rawValue)
        guard let parsedMode = PresetResizeMode(rawValue: rawMode) else {
            throw ResizePresetError.invalidField(ResizePresetKeys.mode)
        }
        mode = parsedMode
        let rawLimitMode = try integer(ResizePresetKeys.limitMode, limitMode.rawValue)
        guard let parsedLimitMode = ResizeLimitMode(rawValue: rawLimitMode) else {
            throw ResizePresetError.invalidField(ResizePresetKeys.limitMode)
        }
        limitMode = parsedLimitMode
        proportions = try boolean(ResizePresetKeys.proportions, proportions)
        editable = try boolean(ResizePresetKeys.editable, editable)
        try validate()
    }

    // loadPresets (0x7527b), in original order and spelling. All are scale=1;
    // KeyFrame and Dribble inherit constrainProportions=1 from SKResize init.
    static let builtins: [ResizePreset] = {
        let rows: [(String, Int, Int)] = [
            ("Ad: Rectangle (Large)", 336, 280), ("Ad: Rectangle (Medium)", 300, 250),
            ("Ad: Rectangle (Small)", 240, 160), ("Ad: Thumbnail", 100, 100),
            ("Ad: Square Pop-up", 250, 250), ("Ad: Leaderboard", 728, 90),
            ("Ad: Banner (Full)", 468, 60), ("Ad: Banner (Half)", 234, 60),
            ("Ad: Sky Scraper", 120, 600), ("Ad: Sky Scraper (Wide)", 160, 600),
            ("KeyFrame: Viddler", 437, 370), ("KeyFrame: YouTube", 425, 355),
            ("Dribble", 400, 300)]
        return rows.enumerated().map { index, row in
            ResizePreset(id: "builtin:\(index)", name: row.0, width: row.1,
                         height: row.2, proportions: index >= 10, editable: false)
        }
    }()
}

enum ResizePresetKeys {
    static let defaults = "SKPresetResizes"
    static let name = "SKPresetResizeNameKey"
    static let editable = "SKPresetResizeEditableKey"
    static let mode = "SKPresetResizeModeKey"
    static let format = "SKPresetResizeFormatKey"
    static let width = "SKPresetResizeWidthKey"
    static let height = "SKPresetResizeHeightKey"
    static let anchor = "SKPresetResizeCropAnchorKey"
    static let proportions = "SKPresetResizeScaleConstrainProportionsKey"
    static let limitMode = "SKPresetResizeLimitModeKey"
    static let limitSize = "SKPresetResizeLimitSizeKey"
    // Optional forward-compatible extension: original initWithSettings ignores it.
    // Kept in the same array so identity and edits commit in one defaults write.
    static let id = "SkitchReduxResizePresetID"
}

/// Foundation-only store. Loading never writes defaults. Mutations commit one
/// complete property-list array and fail closed on corruption or a stale snapshot.
/// Call reload after an external preferences change. UserDefaults provides an
/// atomic value replacement, not an fsync or cross-process transaction guarantee.
final class ResizePresetStore {
    private static let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private var snapshot: Any?
    private var extras: [String: [String: Any]] = [:]
    private(set) var presets: [ResizePreset] = ResizePreset.builtins
    private(set) var loadIssues: [String] = []
    var hasMalformedData: Bool { !loadIssues.isEmpty }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; reload() }

    func reload() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        snapshot = defaults.object(forKey: ResizePresetKeys.defaults)
        presets = ResizePreset.builtins; extras = [:]; loadIssues = []
        guard let raw = snapshot else { return }
        guard let rows = raw as? [Any] else { loadIssues = ["SKPresetResizes must be an array."]; return }
        var seen = Set<String>()
        for (index, row) in rows.enumerated() {
            do {
                guard let dictionary = row as? [String: Any] else {
                    throw ResizePresetError.invalidField("entry")
                }
                let id: String
                if let value = dictionary[ResizePresetKeys.id] {
                    guard let value = value as? String, !value.hasPrefix("builtin:") else {
                        throw ResizePresetError.invalidField(ResizePresetKeys.id)
                    }
                    id = value
                } else { id = "legacy:\(index)" }
                var preset = try ResizePreset(settings: dictionary, id: id)
                if let builtin = ResizePreset.builtins.first(where: { $0.name == preset.name }) {
                    // Names of recovered built-ins are reserved regardless of a
                    // hostile editable flag. Never admit modified canonical data.
                    preset = ResizePreset(id: builtin.id, name: preset.name, width: preset.width,
                        height: preset.height, mode: preset.mode, format: preset.format,
                        anchor: preset.anchor, proportions: preset.proportions,
                        limitSize: preset.limitSize, limitMode: preset.limitMode, editable: preset.editable)
                    guard preset == builtin, seen.insert(builtin.id).inserted else {
                        throw ResizePresetError.protectedBuiltin
                    }
                    extras[builtin.id] = dictionary
                    continue
                }
                guard seen.insert(id).inserted else { throw ResizePresetError.duplicateID }
                presets.append(preset); extras[id] = dictionary
            } catch { loadIssues.append("Entry \(index): \(error.localizedDescription)") }
        }
    }

    func add(_ preset: ResizePreset) throws {
        try mutate { current in
            try preset.validate()
            guard preset.editable, !preset.id.hasPrefix("builtin:"),
                  !ResizePreset.builtins.contains(where: { $0.name == preset.name }) else {
                throw ResizePresetError.protectedBuiltin
            }
            guard !current.contains(where: { $0.id == preset.id }) else { throw ResizePresetError.duplicateID }
            current.append(preset)
        }
    }

    func update(_ preset: ResizePreset) throws {
        try mutate { current in
            guard let index = current.firstIndex(where: { $0.id == preset.id }) else { throw ResizePresetError.unknownID }
            guard current[index].editable, preset.editable,
                  !ResizePreset.builtins.contains(where: { $0.name == preset.name }) else {
                throw ResizePresetError.protectedBuiltin
            }
            try preset.validate(); current[index] = preset
        }
    }

    func remove(id: String) throws {
        try mutate { current in
            guard let index = current.firstIndex(where: { $0.id == id }) else { throw ResizePresetError.unknownID }
            guard current[index].editable else { throw ResizePresetError.protectedBuiltin }
            current.remove(at: index)
        }
    }

    private func mutate(_ body: (inout [ResizePreset]) throws -> Void) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard !hasMalformedData else { throw ResizePresetError.malformedDefaults }
        let actual = defaults.object(forKey: ResizePresetKeys.defaults)
        guard Self.equal(snapshot, actual) else { throw ResizePresetError.staleDefaults }
        var candidate = presets
        try body(&candidate)
        let rows: [[String: Any]] = try candidate.map { preset in
            try preset.validate()
            var row = extras[preset.id] ?? [:]
            row.merge(preset.settings) { _, new in new }
            if preset.id.hasPrefix("builtin:") { row.removeValue(forKey: ResizePresetKeys.id) }
            else { row[ResizePresetKeys.id] = preset.id }
            return row
        }
        guard PropertyListSerialization.propertyList(rows, isValidFor: .binary) else {
            throw ResizePresetError.malformedDefaults
        }
        defaults.set(rows, forKey: ResizePresetKeys.defaults)
        snapshot = rows; presets = candidate
        extras = Dictionary(uniqueKeysWithValues: zip(candidate.map(\.id), rows))
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let lhs?, let rhs?): return NSDictionary(dictionary: ["value": lhs]).isEqual(to: ["value": rhs])
        default: return false
        }
    }
}
