import Foundation

/// An in-memory stand-in for a UserDefaults suite. A real suite would create a plist in the owner's real
/// ~/Library/Preferences (CFFIXED_USER_HOME does not redirect the preferences daemon) and the daemon writes it back
/// after removal, so tests never open one. Values are stored as property lists, so types and copies behave like the real
/// thing, and two instances with the same name share storage (a "reopened" store sees what the first one saved).
final class TestDefaults: UserDefaults {
    private final class Box { var values: [String: Any] = [:] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var boxes: [String: Box] = [:]

    private let name: String
    private let box: Box

    init(name: String) {
        self.name = name
        Self.lock.lock(); defer { Self.lock.unlock() }
        box = Self.boxes[name] ?? { let fresh = Box(); Self.boxes[name] = fresh; return fresh }()
        super.init(suiteName: nil)!
    }

    /// Forgets the suite's storage; the counterpart of removePersistentDomain for a throwaway suite.
    static func dispose(_ defaults: UserDefaults, name: String) {
        lock.lock(); defer { lock.unlock() }
        boxes[name] = nil
    }

    private func copy(_ value: Any) -> Any? {
        guard PropertyListSerialization.propertyList(["v": value], isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0),
              let back = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return back["v"]
    }

    override func object(forKey defaultName: String) -> Any? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return box.values[defaultName].flatMap { copy($0) }
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        guard let value else { removeObject(forKey: defaultName); return }
        guard let stored = copy(value) else { return }
        Self.lock.lock(); defer { Self.lock.unlock() }
        box.values[defaultName] = stored
    }
    override func removeObject(forKey defaultName: String) {
        Self.lock.lock(); defer { Self.lock.unlock() }
        box.values[defaultName] = nil
    }
    override func set(_ value: Int, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ url: URL?, forKey defaultName: String) {
        guard let url else { removeObject(forKey: defaultName); return }
        set(try? NSKeyedArchiver.archivedData(withRootObject: url, requiringSecureCoding: true), forKey: defaultName)
    }

    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { object(forKey: defaultName) as? [String: Any] }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    override func integer(forKey defaultName: String) -> Int { (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0 }
    override func float(forKey defaultName: String) -> Float { (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0 }
    override func double(forKey defaultName: String) -> Double { (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0 }
    override func bool(forKey defaultName: String) -> Bool { (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false }

    override func dictionaryRepresentation() -> [String: Any] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return box.values
    }
    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        guard domainName == name else { return nil }
        Self.lock.lock(); defer { Self.lock.unlock() }
        return box.values.isEmpty ? nil : box.values
    }
    override func removePersistentDomain(forName domainName: String) {
        guard domainName == name else { return }
        Self.lock.lock(); defer { Self.lock.unlock() }
        box.values = [:]
    }
    override func synchronize() -> Bool { true }
}
