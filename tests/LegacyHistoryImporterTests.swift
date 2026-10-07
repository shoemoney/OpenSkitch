#if LEGACY_HISTORY_IMPORTER_TESTS
import Foundation
import CoreGraphics

/// Fixture encoder only. Production never unarchives this or any other class.
@objc(HistoryObject)
final class SyntheticHistoryObject: NSObject, NSCoding {
    static var decoded = false
    let fields: [String: Any]
    let old: Bool
    init(_ fields: [String: Any], old: Bool = false) { self.fields = fields; self.old = old }
    required init?(coder: NSCoder) { Self.decoded = true; return nil }
    func encode(with coder: NSCoder) {
        if !old { coder.encode(fields as NSDictionary, forKey: "mInfo"); return }
        for (key, value) in fields {
            if let size = value as? CGSize { coder.encode(size, forKey: key) }
            else if ["mLocal", "mUnsaved", "unsaved"].contains(key), let value = value as? Int {
                coder.encode(value, forKey: key)
            } else { coder.encode(value, forKey: key) }
        }
    }
}

@main
enum LegacyHistoryImporterTests {
    struct Failure: Error { let message: String }
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; count += 1
    }
    static func rejects(_ data: Data, _ message: String, matching expected: ((LegacyHistoryImporter.Failure) -> Bool)? = nil) throws {
        do { _ = try LegacyHistoryImporter.decode(data) }
        catch let error as LegacyHistoryImporter.Failure {
            if let expected, !expected(error) { throw Failure(message: message + ": wrong failure \(error)") }
            count += 1; return
        } catch { throw Failure(message: message + ": unexpected failure \(error)") }
        throw Failure(message: message + ": unexpectedly accepted")
    }
    static func uid(_ index: Any) -> [String: Any] { ["CF$UID": index] }
    static func descriptor(_ name: String) -> [String: Any] {
        let parents: [String: [String]] = [
            "NSMutableArray": ["NSArray", "NSObject"], "NSMutableDictionary": ["NSDictionary", "NSObject"],
            "NSMutableString": ["NSString", "NSObject"], "NSNumber": ["NSValue", "NSObject"]
        ]
        return ["$classname": name, "$classes": [name] + (parents[name] ?? ["NSObject"])]
    }
    static func plist(_ archive: [String: Any], format: PropertyListSerialization.PropertyListFormat = .binary) throws -> Data {
        // XML CF$UID references are recognized by Foundation; reserializing to
        // binary produces actual UID tags rather than ordinary dictionaries.
        let xml = try PropertyListSerialization.data(fromPropertyList: archive, format: .xml, options: 0)
        let graph = try PropertyListSerialization.propertyList(from: xml, options: [], format: nil)
        return try PropertyListSerialization.data(fromPropertyList: graph, format: format, options: 0)
    }
    static func archive(_ objects: [Any], root: Any = uid(1), format: PropertyListSerialization.PropertyListFormat = .binary) throws -> Data {
        try plist(["$archiver": "NSKeyedArchiver", "$version": 100_000, "$objects": objects, "$top": ["root": root]], format: format)
    }
    static func rawXML(_ objects: [Any], root: Any, format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$version": 100_000,
            "$objects": objects, "$top": ["root": root]], format: format, options: 0)
    }
    static func simple(_ info: [String: Any] = ["localPath": "/Pictures/Skitch/proof.skitch"]) -> [Any] {
        ["$null", ["$class": uid(2), "NS.objects": [uid(3)]], descriptor("NSArray"),
         ["$class": uid(4), "mInfo": uid(5)], descriptor("HistoryObject"), info]
    }
    static func widenedUID(_ data: Data, value: UInt64) throws -> Data {
        let bytes = [UInt8](data), trailer = bytes.count - 32
        func read(_ start: Int, _ width: Int) -> UInt64 {
            bytes[start..<(start + width)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func big(_ number: UInt64) -> [UInt8] { (0..<8).reversed().map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) } }
        let width = Int(bytes[trailer + 6]), count = Int(read(trailer + 8, 8)), table = Int(read(trailer + 24, 8))
        var offsets = (0..<count).map { Int(read(table + $0 * width, width)) }
        guard let target = offsets.first(where: { bytes[$0] == 0x80 && bytes[$0 + 1] == 1 }) else {
            throw Failure(message: "Fixture needs UID 1")
        }
        var result = Array(bytes[..<table])
        result.replaceSubrange(target..<(target + 2), with: [0x87] + big(value))
        offsets = offsets.map { $0 > target ? $0 + 7 : $0 }
        for offset in offsets { result += big(UInt64(offset)) }
        result += [UInt8](repeating: 0, count: 6) + [8, bytes[trailer + 7]] + big(UInt64(count)) + big(read(trailer + 16, 8)) + big(UInt64(table + 7))
        return Data(result)
    }
    static func foundationFixture(format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        let current = SyntheticHistoryObject([
            "localPath": "/Users/original/Pictures/Skitch/café.skitch", "remoteURL": "https://example.invalid/café",
            "remotePath": "/imgs/café.png", "date": Date(timeIntervalSince1970: 1_791_000_000),
            "local": false, "saved": true, "size": NSValue(size: CGSize(width: 640, height: 480)),
            "textContent": "résumé\n第二行", "accountID": 17, "noteGUID": "fixture-guid", "count": 3
        ])
        let old = SyntheticHistoryObject([
            "mLocalPath": "~/Pictures/Skitch/old.skitch", "mRemoteURL": "", "mRemotePath": "/old.png",
            "mDate": Date(timeIntervalSince1970: 42), "mLocal": 1, "mUnsaved": 1,
            "mSize": CGSize(width: 321, height: 123)
        ], old: true)
        let coder = NSKeyedArchiver(requiringSecureCoding: false)
        coder.setClassName("HistoryObject", for: SyntheticHistoryObject.self)
        coder.encode(NSMutableArray(array: [current, old]), forKey: NSKeyedArchiveRootObjectKey)
        coder.finishEncoding()
        let graph = try PropertyListSerialization.propertyList(from: coder.encodedData, options: [], format: nil)
        return try PropertyListSerialization.data(fromPropertyList: graph, format: format, options: 0)
    }

    static func main() throws {
        let binary = try foundationFixture(format: .binary), xml = try foundationFixture(format: .xml)
        let binaryGraph = try PropertyListSerialization.propertyList(from: binary, options: [], format: nil)
        try expect(String(describing: binaryGraph).contains("CFKeyedArchiverUID"), "Binary fixture contains actual Foundation UID tags")
        let records = try LegacyHistoryImporter.decode(binary)
        try expect(records == LegacyHistoryImporter.decode(xml), "Binary and XML Foundation fixtures decode identically")
        try expect(records.count == 2 && records.map(\.originalIndex) == [0, 1], "Archive insertion order and original indices survive")
        let first = records[0], old = records[1]
        try expect(first.localPath.hasSuffix("café.skitch") && first.text == "résumé\n第二行", "Unicode paths and annotation text survive")
        try expect(first.remoteURL == "https://example.invalid/café" && first.remotePath == "/imgs/café.png", "Remote references are retained verbatim")
        try expect(first.date == Date(timeIntervalSince1970: 1_791_000_000), "NSDate uses the Foundation 2001 reference epoch")
        try expect(!first.local && first.saved && first.size == CGSize(width: 640, height: 480), "Foundation bools and NSValue size decode")
        try expect(first.accountID == "17" && first.properties == ["noteGUID": "fixture-guid", "count": "3"], "NSNumber account ID and posting metadata survive")
        try expect(old.localPath == "~/Pictures/Skitch/old.skitch", "Importer does not expand paths or read files")
        try expect(old.local && old.saved && old.size == CGSize(width: 321, height: 123), "Old NSCoding keys and encodeSize shape decode")
        try expect(old.date == Date(timeIntervalSince1970: 42) && old.text.isEmpty && old.accountID == nil, "Old missing fields receive deterministic defaults")
        try expect(!SyntheticHistoryObject.decoded, "Reader never calls fixture init(coder:)")
        var objects = simple()
        objects[1] = ["$class": uid(2), "NS.objects": []]
        try expect(LegacyHistoryImporter.decode(archive(objects)).isEmpty, "Empty History archive is supported")

        objects = simple()
        objects[3] = ["$class": uid(4), "mLocalPath": "old.skitch", "mUnsaved": 1, "unsaved": 0, "mLocal": -1]
        let mapped = try LegacyHistoryImporter.decode(archive(objects))[0]
        try expect(!mapped.saved && mapped.local, "unsaved overrides mUnsaved directly, without inversion")
        objects[3] = ["$class": uid(4), "mLocalPath": "old.skitch", "mUnsaved": 0]
        try expect(!LegacyHistoryImporter.decode(archive(objects))[0].saved, "mUnsaved zero maps to saved false")
        objects[3] = ["$class": uid(4), "mInfo": uid(0), "mLocalPath": "fallback.skitch", "mUnsaved": 1]
        try expect(LegacyHistoryImporter.decode(archive(objects))[0].saved, "Null mInfo invokes old-key fallback")
        objects = simple(["localPath": "current.skitch", "saved": false])
        objects[3] = ["$class": uid(4), "mInfo": uid(5), "mLocalPath": "ignored.skitch", "mUnsaved": 1]
        try expect(LegacyHistoryImporter.decode(archive(objects))[0].localPath == "current.skitch" && !LegacyHistoryImporter.decode(archive(objects))[0].saved,
                   "Present mInfo has precedence over every old key")

        for dimensions: Any in ["{ 10.5, 20 }", ["width": 10.5, "height": 20]] {
            let record = try LegacyHistoryImporter.decode(archive(simple(["localPath": "size.skitch", "size": dimensions])))[0]
            try expect(record.size == CGSize(width: 10.5, height: 20), "Size string and width/height dictionary shapes decode")
        }
        // Explicit historical Foundation wrapper shapes, not merely plist scalars.
        objects = simple(["localPath": uid(6), "size": uid(8), "accountID": uid(10), "local": uid(12), "date": uid(13)])
        objects += [["$class": uid(7), "NS.string": "wrapped.skitch"], descriptor("NSMutableString"),
                    ["$class": uid(9), "NS.special": 2, "NS.sizeval": ["width": 12, "height": 34]], descriptor("NSValue"),
                    ["$class": uid(11), "NS.intval": 9], descriptor("NSNumber"),
                    ["$class": uid(11), "NS.boolval": true], ["$class": uid(14), "NS.time": -978307158.0], descriptor("NSDate")]
        let wrapped = try LegacyHistoryImporter.decode(archive(objects))[0]
        try expect(wrapped.localPath == "wrapped.skitch" && wrapped.local && wrapped.accountID == "9", "NSString and NSNumber wrappers decode without class instantiation")
        try expect(wrapped.size == CGSize(width: 12, height: 34) && wrapped.date == Date(timeIntervalSince1970: 42), "NSValue size dictionary and negative NSDate offsets decode")
        objects = simple(["localPath": "empty.skitch", "remoteURL": uid(0), "date": uid(0), "size": uid(0)])
        let nullable = try LegacyHistoryImporter.decode(archive(objects))[0]
        try expect(nullable.remoteURL == nil && nullable.date == nil && nullable.size == nil && !nullable.local && !nullable.saved,
                   "Null optional fields and missing flags decode safely")

        objects = simple(); objects += [descriptor("EvilClass")]
        try rejects(archive(objects), "Unknown unreachable classes are refused") { if case .unsupportedClass = $0 { return true }; return false }
        objects = simple(); objects[4] = ["$classname": "HistoryObject", "$classes": ["HistoryObject", "EvilBase", "NSObject"]]
        try rejects(archive(objects), "Forged known classname with unknown superclass is refused")
        objects = simple(); objects[3] = ["$class": uid(4), "mInfo": uid(5), "unexpected": 1]
        try rejects(archive(objects), "Unknown HistoryObject coding fields are refused")
        objects = simple(); objects[1] = ["$class": uid(2), "NS.objects": [uid(3), uid(999)]]
        try rejects(archive(objects), "Out of bounds UID aborts complete decode") { if case .invalidReference = $0 { return true }; return false }
        for reference: Any in [-1, 1.5, true, UInt64.max] {
            try rejects(rawXML(simple(), root: uid(reference)), "Invalid UID integer is refused")
        }
        try rejects(rawXML(simple(), root: ["CF$UID": 1, "extra": 1]), "Malformed UID dictionary is refused")
        objects = simple(); objects[1] = ["$class": uid(2), "NS.objects": [uid(1)]]
        try rejects(archive(objects), "Root array self-cycle is refused") { if case .cycle = $0 { return true }; return false }
        objects = simple(["localPath": "cycle.skitch", "posting": uid(5)])
        try rejects(archive(objects), "Metadata dictionary cycle is refused") { if case .cycle = $0 { return true }; return false }
        objects = simple(); objects += [uid(7), uid(6)]
        try rejects(archive(objects), "Unreachable mutual UID cycle is refused") { if case .cycle = $0 { return true }; return false }
        objects = simple(); let start = objects.count
        for index in start..<(start + 70) { objects.append(uid(index + 1)) }; objects.append("tail")
        try rejects(archive(objects), "UID chain depth is bounded") { if case .limitExceeded = $0 { return true }; return false }
        objects = simple(); var nested: Any = "leaf"
        for _ in 0..<70 { nested = [nested] }; objects.append(nested)
        try rejects(archive(objects), "Inline plist depth is bounded") { if case .limitExceeded = $0 { return true }; return false }
        objects = simple(); objects += Array(repeating: "padding", count: 20_001)
        try rejects(archive(objects), "Object table count is bounded") { if case .limitExceeded = $0 { return true }; return false }
        try rejects(Data(repeating: 32, count: 8 * 1024 * 1024 + 1), "Input byte count is bounded") { if case .limitExceeded = $0 { return true }; return false }
        try rejects(Data("not a property list".utf8), "Malformed bytes fail closed")
        try rejects(widenedUID(archive(simple()), value: 4_294_967_297), "64-bit binary UID cannot truncate to valid UID 1") { if case .invalidReference = $0 { return true }; return false }
        try rejects(widenedUID(archive(simple()), value: UInt64.max), "Binary UID overflow is refused") { if case .invalidReference = $0 { return true }; return false }
        objects = simple()
        for index in 6..<22 { objects.append(["$class": uid(2), "NS.objects": [uid(index + 1), uid(index + 1)]]) }
        objects.append("leaf")
        try rejects(archive(objects), "Repeated shared UID traversal is work-bounded") { if case .limitExceeded = $0 { return true }; return false }
        let entityKey = String(data: try rawXML(simple(), root: uid(999)), encoding: .utf8)!.replacingOccurrences(of: "CF$UID", with: "CF&#36;UID")
        try rejects(Data(entityKey.utf8), "Entity-encoded UID key cannot bypass index validation")
        let entity = "<?xml version=\"1.0\"?><!DOCTYPE plist [<!ENTITY x \"CF$UID\">]><plist version=\"1.0\"><dict><key>&x;</key><integer>1</integer></dict></plist>"
        try rejects(Data(entity.utf8), "Internal XML entity declarations are refused")
        try rejects(archive(simple([:])), "Missing localPath fails rather than fabricating one")
        try rejects(archive(simple(["localPath": ""])), "Empty localPath is refused")
        try rejects(rawXML(simple(["localPath": "bad\0path"]), root: uid(1), format: .binary), "NUL-bearing localPath is refused")
        try rejects(archive(simple(["localPath": "x.skitch", "local": "true"])), "Wrong flag type is refused")
        try rejects(archive(simple(["localPath": "x.skitch", "saved": 0.5])), "Fractional flags are refused")
        try rejects(archive(simple(["localPath": "x.skitch", "date": 42])), "Numeric date without NSDate is refused")
        for badSize: Any in ["garbage", "{1, 2, 3}", "{-1, 20}", "{nan, 20}", ["width": 3], ["width": true, "height": 2], ["width": 1, "height": 2, "extra": 3]] {
            try rejects(archive(simple(["localPath": "x.skitch", "size": badSize])), "Malformed or unsupported size is refused")
        }
        objects = simple(["localPath": "x.skitch", "size": uid(6)])
        objects += [["$class": uid(7), "NS.special": 1, "NS.pointval": "{1, 2}"], descriptor("NSValue")]
        try rejects(archive(objects), "NSValue point is not mistaken for a size")
        objects = simple(["localPath": "x.skitch", "passwords": ["nested": "opaque"]])
        try rejects(archive(objects), "Structured posting metadata is refused rather than silently lost")
        objects = simple(); objects[5] = ["$class": uid(6), "NS.keys": [uid(7), uid(7)], "NS.objects": ["x", "y"]]
        objects += [descriptor("NSDictionary"), "localPath"]
        try rejects(archive(objects), "Duplicate dictionary keys are refused")
        objects = simple(); objects[5] = ["$class": uid(6), "NS.keys": ["localPath"], "NS.objects": []]
        objects += [descriptor("NSDictionary")]
        try rejects(archive(objects), "Dictionary key/value count mismatch is refused")
        objects = simple(); objects += [Data([1, 2, 3])]
        try rejects(archive(objects), "Unsupported data payload is refused")
        objects = simple(); objects += [["$class": uid(7), "NS.dblval": Double.infinity], descriptor("NSNumber")]
        try rejects(archive(objects), "Nonfinite number payload is refused")
        try rejects(archive(simple(), root: [uid(3)]), "Top root must be an archived object reference")
        try rejects(plist(["$archiver": "Other", "$version": 100_000, "$objects": simple(), "$top": ["root": uid(1)]]), "Wrong archive marker is refused")
        try rejects(plist(["$archiver": "NSKeyedArchiver", "$version": 1, "$objects": simple(), "$top": ["root": uid(1)]]), "Unsupported archive version is refused")
        objects = simple(); objects[0] = "not null"
        try rejects(archive(objects), "Null slot sentinel is required")
        print("Legacy History importer: \(count) synthetic checks passed; no real legacy index verified")
    }
}
#endif
