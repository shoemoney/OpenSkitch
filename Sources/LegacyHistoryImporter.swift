import Foundation
import CoreFoundation
import CoreGraphics

/// Reads the original History index as data, never instantiating archived classes.
/// Verified against synthetic archives only; no real legacy index was available.
enum LegacyHistoryImporter {
    struct Record: Equatable {
        let originalIndex: Int
        let localPath: String
        let remotePath: String?
        let remoteURL: String?
        let date: Date?
        let local: Bool
        let saved: Bool
        let size: CGSize?
        let text: String
        let accountID: String?
        let properties: [String: String]
    }

    enum Failure: Error, LocalizedError {
        case malformed, limitExceeded, invalidReference, cycle, unsupportedClass(String), unsupportedShape(String)
        var errorDescription: String? {
            switch self {
            case .malformed: return "The legacy History index is malformed."
            case .limitExceeded: return "The legacy History index exceeds the reader's limits."
            case .invalidReference: return "The legacy History index contains an invalid object reference."
            case .cycle: return "The legacy History index contains a cycle."
            case .unsupportedClass(let name): return "Unsupported legacy History class: \(name)."
            case .unsupportedShape(let name): return "Unsupported legacy History value: \(name)."
            }
        }
    }

    private static let maximumBytes = 8 * 1024 * 1024
    private static let maximumObjects = 20_000
    private static let maximumDepth = 64
    private static let maximumVisits = 200_000
    private static let uidKey = "$SkitchLegacyUID"

    static func decode(_ data: Data) throws -> [Record] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.limitExceeded }
        let inputUIDs: [Int]
        if data.starts(with: Data("bplist00".utf8)) { inputUIDs = try binaryUIDs(data) }
        else {
            let validator = XMLUIDValidator()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            parser.delegate = validator
            guard parser.parse(), validator.failure == nil else { throw validator.failure ?? Failure.malformed }
            inputUIDs = validator.indices
        }
        let raw: Any
        do { raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { throw Failure.malformed }
        try boundPropertyList(raw)
        guard let rawArchive = raw as? [String: Any], let rawObjects = rawArchive["$objects"] as? [Any],
              inputUIDs.allSatisfy({ rawObjects.indices.contains($0) }) else { throw Failure.invalidReference }

        // Foundation exposes binary UIDs as a private CF type. Its public XML
        // serializer emits CF$UID dictionaries. Rename that reserved key before
        // parsing so Foundation does not turn them back into private UID objects.
        // No KVC, private CF accessors, or NSKeyedUnarchiver are used.
        let xmlData: Data
        do { xmlData = try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0) }
        catch { throw Failure.malformed }
        guard xmlData.count <= maximumBytes * 8,
              let xml = String(data: xmlData, encoding: .utf8),
              !xml.contains("<key>\(uidKey)</key>") else { throw Failure.limitExceeded }
        let normalized = xml.replacingOccurrences(of: "<key>CF$UID</key>", with: "<key>\(uidKey)</key>")
        let plist: Any
        do { plist = try PropertyListSerialization.propertyList(from: Data(normalized.utf8), options: [], format: nil) }
        catch { throw Failure.malformed }
        guard let archive = plist as? [String: Any],
              Set(archive.keys) == ["$archiver", "$version", "$objects", "$top"],
              archive["$archiver"] as? String == "NSKeyedArchiver",
              let version = archive["$version"] as? NSNumber, integer(version) == 100_000,
              let objects = archive["$objects"] as? [Any], !objects.isEmpty,
              objects.count <= maximumObjects, objects[0] as? String == "$null",
              let top = archive["$top"] as? [String: Any], Set(top.keys) == ["root"] else {
            throw Failure.malformed
        }
        let reader = Reader(objects: objects)
        // Validate unreachable objects too: an unknown class cannot be hidden in
        // an otherwise readable index. Descriptors are data, not class lookups.
        for index in objects.indices { _ = try reader.reference(index, depth: 0) }
        guard let root = top["root"], reader.uid(root) != nil,
              case .array(let records) = try reader.value(root, depth: 0) else { throw Failure.malformed }
        return try records.enumerated().map { index, value in
            guard case .history(let fields) = value else { throw Failure.unsupportedShape("History root entry") }
            return try record(fields, index: index)
        }
    }

    /// Check every binary UID before Foundation can narrow its integer width.
    private static func binaryUIDs(_ data: Data) throws -> [Int] {
        guard data.count >= 40 else { throw Failure.malformed }
        let bytes = [UInt8](data), trailer = bytes.count - 32
        func unsigned(_ offset: Int, _ length: Int) throws -> UInt64 {
            guard (1...8).contains(length), offset >= 0, offset <= bytes.count - length else { throw Failure.malformed }
            return bytes[offset..<(offset + length)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        let offsetWidth = Int(bytes[trailer + 6]), referenceWidth = Int(bytes[trailer + 7])
        let objectCount = try unsigned(trailer + 8, 8), top = try unsigned(trailer + 16, 8)
        let table = try unsigned(trailer + 24, 8)
        guard (1...8).contains(offsetWidth), (1...8).contains(referenceWidth),
              objectCount > 0, objectCount <= UInt64(maximumVisits), top < objectCount,
              table >= 8, table <= UInt64(trailer), objectCount * UInt64(offsetWidth) <= UInt64(trailer) - table else {
            throw Failure.malformed
        }
        var seen: Set<Int> = [], result: [Int] = []
        for index in 0..<Int(objectCount) {
            let offset = try unsigned(Int(table) + index * offsetWidth, offsetWidth)
            guard offset >= 8, offset < table, seen.insert(Int(offset)).inserted else { throw Failure.malformed }
            let marker = bytes[Int(offset)]
            if marker & 0xf0 == 0x80 {
                let width = Int(marker & 0x0f) + 1
                guard width <= 8, offset + UInt64(width) < table else { throw Failure.invalidReference }
                let uid = try unsigned(Int(offset) + 1, width)
                guard uid < UInt64(maximumObjects) else { throw Failure.invalidReference }
                result.append(Int(uid))
            }
        }
        return result
    }

    /// Only validates XML UID syntax; PropertyListSerialization parses values.
    /// Entity-decoded keys are checked too, so CF&#36;UID cannot bypass validation.
    private final class XMLUIDValidator: NSObject, XMLParserDelegate {
        struct Frame { var name: String; var text = ""; var keys: [String] = []; var uid: Int? }
        var frames: [Frame] = [], indices: [Int] = [], failure: Failure?
        var nodes = 0
        func fail(_ parser: XMLParser, _ error: Failure) { failure = error; parser.abortParsing() }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            nodes += 1
            guard frames.count <= maximumDepth, nodes <= maximumVisits else { fail(parser, .limitExceeded); return }
            if let parent = frames.last, parent.name == "dict", parent.keys.last == "CF$UID", parent.uid == nil, elementName != "integer" {
                fail(parser, .invalidReference); return
            }
            frames.append(Frame(name: elementName))
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !frames.isEmpty else { return }
            frames[frames.count - 1].text += string
            if frames[frames.count - 1].text.utf8.count > 1_048_576 { fail(parser, .limitExceeded) }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard let frame = frames.popLast(), frame.name == elementName else { fail(parser, .malformed); return }
            if elementName == "key", frames.last?.name == "dict" { frames[frames.count - 1].keys.append(frame.text) }
            if elementName == "integer", frames.last?.name == "dict", frames.last?.keys.last == "CF$UID" {
                guard let index = Int(frame.text.trimmingCharacters(in: .whitespacesAndNewlines)), index >= 0, index < maximumObjects else {
                    fail(parser, .invalidReference); return
                }
                frames[frames.count - 1].uid = index
            }
            if elementName == "dict", frame.keys.contains("CF$UID") {
                guard frame.keys == ["CF$UID"], let index = frame.uid else { fail(parser, .invalidReference); return }
                indices.append(index)
            }
        }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { fail(parser, .unsupportedShape("XML entity")) }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { fail(parser, .unsupportedShape("XML entity")) }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            fail(parser, .unsupportedShape("XML external entity")); return nil
        }
    }

    /// Bound the raw plist tree before the public UID-normalizing round trip.
    private static func boundPropertyList(_ root: Any) throws {
        var pending: [(Any, Int)] = [(root, 0)], visited = 0
        while let (value, depth) = pending.popLast() {
            visited += 1
            guard depth <= maximumDepth, visited <= maximumVisits else { throw Failure.limitExceeded }
            if let values = value as? [Any] {
                guard values.count <= maximumObjects else { throw Failure.limitExceeded }
                pending.append(contentsOf: values.map { ($0, depth + 1) })
            } else if let values = value as? [String: Any] {
                guard values.count <= maximumObjects else { throw Failure.limitExceeded }
                for (key, item) in values {
                    guard key.utf8.count <= 16_384 else { throw Failure.limitExceeded }
                    pending.append((item, depth + 1))
                }
            } else if let string = value as? String {
                guard string.utf8.count <= 1_048_576 else { throw Failure.limitExceeded }
            }
        }
    }

    private indirect enum Value {
        case null, string(String), number(NSNumber), date(Date), size(CGSize)
        case array([Value]), dictionary([String: Value]), history([String: Value]), descriptor(String)
    }

    private final class Reader {
        let objects: [Any]
        var active: Set<Int> = []
        var visits = 0
        init(objects: [Any]) { self.objects = objects }

        func uid(_ raw: Any) -> Int? {
            guard let dictionary = raw as? [String: Any], dictionary.count == 1,
                  let number = dictionary[uidKey] as? NSNumber else { return nil }
            return integer(number)
        }

        func reference(_ index: Int, depth: Int) throws -> Value {
            guard objects.indices.contains(index) else { throw Failure.invalidReference }
            guard active.insert(index).inserted else { throw Failure.cycle }
            defer { active.remove(index) }
            if index == 0 { return .null }
            return try value(objects[index], depth: depth + 1)
        }

        func value(_ raw: Any, depth: Int) throws -> Value {
            visits += 1
            guard depth <= maximumDepth, visits <= maximumVisits else { throw Failure.limitExceeded }
            if let dictionary = raw as? [String: Any], dictionary[uidKey] != nil {
                guard let index = uid(dictionary) else { throw Failure.invalidReference }
                return try reference(index, depth: depth)
            }
            if let string = raw as? String { return .string(string) }
            if let number = raw as? NSNumber {
                guard number.doubleValue.isFinite else { throw Failure.malformed }
                return .number(number)
            }
            if let date = raw as? Date {
                guard date.timeIntervalSinceReferenceDate.isFinite else { throw Failure.malformed }
                return .date(date)
            }
            if let array = raw as? [Any] { return .array(try array.map { try value($0, depth: depth + 1) }) }
            guard let dictionary = raw as? [String: Any] else { throw Failure.unsupportedShape("plist scalar") }
            if dictionary["$classname"] != nil || dictionary["$classes"] != nil {
                return .descriptor(try descriptor(dictionary))
            }
            guard let classReference = dictionary["$class"] else {
                guard !dictionary.keys.contains(where: { $0.hasPrefix("$") || $0.hasPrefix("NS.") }) else {
                    throw Failure.unsupportedShape("uncoded dictionary")
                }
                return .dictionary(try dictionary.mapValues { try value($0, depth: depth + 1) })
            }
            guard uid(classReference) != nil,
                  case .descriptor(let name) = try value(classReference, depth: depth + 1) else {
                throw Failure.unsupportedShape("class reference")
            }
            let body = dictionary.filter { $0.key != "$class" }
            func keys(_ allowed: Set<String>) throws {
                guard Set(body.keys).isSubset(of: allowed) else { throw Failure.unsupportedShape(name) }
            }
            func field(_ key: String) throws -> Value {
                guard let raw = body[key] else { throw Failure.unsupportedShape(name + "." + key) }
                return try value(raw, depth: depth + 1)
            }
            switch name {
            case "NSArray", "NSMutableArray":
                try keys(["NS.objects"])
                guard case .array(let items) = try field("NS.objects") else { throw Failure.unsupportedShape(name) }
                return .array(items)
            case "NSDictionary", "NSMutableDictionary":
                try keys(["NS.keys", "NS.objects"])
                guard case .array(let keyValues) = try field("NS.keys"),
                      case .array(let values) = try field("NS.objects"), keyValues.count == values.count else {
                    throw Failure.unsupportedShape(name)
                }
                var result: [String: Value] = [:]
                for (keyValue, value) in zip(keyValues, values) {
                    guard case .string(let key) = keyValue, result[key] == nil else { throw Failure.unsupportedShape("dictionary key") }
                    result[key] = value
                }
                return .dictionary(result)
            case "NSString", "NSMutableString":
                try keys(["NS.string"])
                guard case .string(let string) = try field("NS.string") else { throw Failure.unsupportedShape(name) }
                return .string(string)
            case "NSDate":
                try keys(["NS.time"])
                guard case .number(let number) = try field("NS.time"), CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                    throw Failure.unsupportedShape(name)
                }
                return .date(Date(timeIntervalSinceReferenceDate: number.doubleValue))
            case "NSNumber":
                let numberKeys: Set<String> = ["NS.boolval", "NS.intval", "NS.dblval", "NS.floatval", "NS.doubleval"]
                try keys(numberKeys)
                guard body.count == 1, let key = body.keys.first,
                      case .number(let number) = try field(key) else { throw Failure.unsupportedShape(name) }
                if key == "NS.boolval" {
                    guard CFGetTypeID(number) == CFBooleanGetTypeID() || integer(number) == 0 || integer(number) == 1 else {
                        throw Failure.unsupportedShape(name)
                    }
                } else if key == "NS.intval" {
                    guard integer(number) != nil else { throw Failure.unsupportedShape(name) }
                } else {
                    guard CFGetTypeID(number) != CFBooleanGetTypeID() else { throw Failure.unsupportedShape(name) }
                }
                return .number(number)
            case "NSValue":
                try keys(["NS.special", "NS.sizeval"])
                guard case .number(let special) = try field("NS.special"), integer(special) == 2 else {
                    throw Failure.unsupportedShape("NSValue other than NSSize")
                }
                return .size(try size(try field("NS.sizeval")))
            case "HistoryObject":
                try keys(["mInfo", "mLocalPath", "mRemotePath", "mRemoteURL", "mDate", "mLocal", "mUnsaved", "unsaved", "mSize"])
                return .history(try body.mapValues { try value($0, depth: depth + 1) })
            default: throw Failure.unsupportedClass(name)
            }
        }

        private func descriptor(_ dictionary: [String: Any]) throws -> String {
            guard Set(dictionary.keys) == ["$classname", "$classes"],
                  let name = dictionary["$classname"] as? String,
                  let chain = dictionary["$classes"] as? [String] else { throw Failure.malformed }
            let chains: [String: [[String]]] = [
                "HistoryObject": [["HistoryObject", "NSObject"]],
                "NSArray": [["NSArray", "NSObject"]],
                "NSMutableArray": [["NSMutableArray", "NSArray", "NSObject"]],
                "NSDictionary": [["NSDictionary", "NSObject"]],
                "NSMutableDictionary": [["NSMutableDictionary", "NSDictionary", "NSObject"]],
                "NSString": [["NSString", "NSObject"]],
                "NSMutableString": [["NSMutableString", "NSString", "NSObject"]],
                "NSDate": [["NSDate", "NSObject"]],
                "NSNumber": [["NSNumber", "NSValue", "NSObject"], ["NSNumber", "NSObject"]],
                "NSValue": [["NSValue", "NSObject"]]
            ]
            guard let accepted = chains[name], accepted.contains(chain) else { throw Failure.unsupportedClass(name) }
            return name
        }
    }

    private static func integer(_ number: NSNumber) -> Int? {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        // Decimal spelling avoids Double rounding at Int.max and trapping casts.
        return Int(number.stringValue)
    }

    private static func size(_ value: Value) throws -> CGSize {
        let width: Double, height: Double
        switch value {
        case .size(let size): return size
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.first == "{", trimmed.last == "}" else { throw Failure.unsupportedShape("size string") }
            let parts = trimmed.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let w = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let h = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else { throw Failure.unsupportedShape("size string") }
            width = w; height = h
        case .dictionary(let fields):
            guard Set(fields.keys) == ["width", "height"],
                  case .number(let w)? = fields["width"], case .number(let h)? = fields["height"] else {
                throw Failure.unsupportedShape("size dictionary")
            }
            guard CFGetTypeID(w) != CFBooleanGetTypeID(), CFGetTypeID(h) != CFBooleanGetTypeID() else {
                throw Failure.unsupportedShape("size dimensions")
            }
            width = w.doubleValue; height = h.doubleValue
        default: throw Failure.unsupportedShape("size")
        }
        guard width.isFinite, height.isFinite, width >= 0, height >= 0 else { throw Failure.unsupportedShape("size dimensions") }
        return CGSize(width: width, height: height)
    }

    private static func record(_ fields: [String: Value], index: Int) throws -> Record {
        var info: [String: Value] = [:]
        let usesOldKeys: Bool
        switch fields["mInfo"] {
        case nil, .null?: usesOldKeys = true
        case .dictionary(let dictionary)?: info = dictionary; usesOldKeys = false
        default: throw Failure.unsupportedShape("mInfo")
        }
        // Old keys are consulted only if mInfo is absent/null, exactly as original.
        if usesOldKeys {
            for (old, new) in [("mLocalPath", "localPath"), ("mRemotePath", "remotePath"), ("mRemoteURL", "remoteURL"),
                               ("mDate", "date"), ("mLocal", "local"), ("mUnsaved", "saved"), ("unsaved", "saved"), ("mSize", "size")] {
                if let value = fields[old] { info[new] = value }
            }
        }
        func string(_ key: String) throws -> String? {
            guard let value = info[key] else { return nil }
            if case .null = value { return nil }
            guard case .string(let string) = value, !string.contains("\0") else { throw Failure.unsupportedShape(key) }
            return string
        }
        func flag(_ key: String) throws -> Bool {
            guard let value = info[key] else { return false }
            if case .null = value { return false }
            guard case .number(let number) = value,
                  CFGetTypeID(number) == CFBooleanGetTypeID() || integer(number) != nil else { throw Failure.unsupportedShape(key) }
            return number.boolValue
        }
        guard let path = try string("localPath"), !path.isEmpty, path.utf8.count <= 16_384 else { throw Failure.unsupportedShape("localPath") }
        let date: Date?
        if let value = info["date"], case .null = value { date = nil }
        else if let value = info["date"] {
            guard case .date(let parsed) = value else { throw Failure.unsupportedShape("date") }; date = parsed
        } else { date = nil }
        let dimensions: CGSize?
        if let value = info["size"], case .null = value { dimensions = nil }
        else if let value = info["size"] { dimensions = try size(value) }
        else { dimensions = nil }
        func scalar(_ value: Value, key: String) throws -> String? {
            switch value {
            case .null: return nil
            case .string(let string): return string
            case .number(let number): return number.stringValue
            default: throw Failure.unsupportedShape("metadata " + key)
            }
        }
        let account = try info["accountID"].flatMap { try scalar($0, key: "accountID") }
        let reserved: Set<String> = ["localPath", "remotePath", "remoteURL", "date", "local", "saved", "size", "textContent", "accountID"]
        var properties: [String: String] = [:]
        for (key, value) in info where !reserved.contains(key) {
            properties[key] = try scalar(value, key: key)
        }
        return Record(originalIndex: index, localPath: path, remotePath: try string("remotePath"), remoteURL: try string("remoteURL"),
                      date: date, local: try flag("local"), saved: try flag("saved"), size: dimensions,
                      text: try string("textContent") ?? "", accountID: account, properties: properties)
    }
}
