// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D ORIGINAL_HINT_MESSAGES_TESTS \
//   Sources/LegacySkitch.swift Sources/DocumentModel.swift Sources/OriginalHintMessages.swift \
//   tests/OriginalHintMessagesTests.swift -o /tmp/skitch-original-hint-messages-tests
// /tmp/skitch-original-hint-messages-tests
#if ORIGINAL_HINT_MESSAGES_TESTS
import AppKit
import CryptoKit

/// Independent expected copy transcribed from the original i386 VM strings and
/// vtables, NOT from OriginalHintMessages. The original binary is a read-only
/// fixture; when the git-ignored archive is absent (fresh clone) its Mach-O
/// evidence is skipped and only the reconstruction-side checks run. No app,
/// preferences, event delivery or desktop is opened.
@main
@MainActor
enum OriginalHintMessagesTests {
    static var checks = 0
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw Failure(description: message) }
    }

    struct ToolFixture {
        let tag: Int
        let tool: SketchTool?
        let vtable: Int
        let getHelp: UInt32
        let stringVM: Int
        let copy: String
    }
    static let tools: [ToolFixture] = [
        .init(tag: 0, tool: .brush, vtable: 0x294950, getHelp: 0x1b3b10, stringVM: 0x25c907, copy: "option = Eyedropper. shift = Less smoothing"),
        .init(tag: 1, tool: .select, vtable: 0x2949c0, getHelp: 0x1b4f38, stringVM: 0x25c940, copy: "option = Copy. shift = Multiple Selections"),
        .init(tag: 2, tool: .ellipse, vtable: 0x294f70, getHelp: 0x1df40c, stringVM: 0x25d0e2, copy: "option = Centered. shift = Perfect circle"),
        .init(tag: 3, tool: .rectangle, vtable: 0x294fe0, getHelp: 0x1dfe82, stringVM: 0x25d116, copy: "option = Centered. shift = Perfect square"),
        .init(tag: 4, tool: .text, vtable: 0x294820, getHelp: 0x1b2442, stringVM: 0x25c87a, copy: "just type at any time, when using any tool!"),
        .init(tag: 5, tool: .eraser, vtable: 0x2948e0, getHelp: 0x1b3386, stringVM: 0x25c8e9, copy: "shift = less smoothing"),
        .init(tag: 6, tool: .arrow, vtable: 0x295050, getHelp: 0x1e12f2, stringVM: 0x25d156, copy: "option = Arrow in reverse direction. shift = 45º arrows"),
        .init(tag: 7, tool: .fill, vtable: 0x294880, getHelp: 0x1b2740, stringVM: 0x25c8ad, copy: "option = Eyedropper. shift = Non-grouping fill"),
        .init(tag: 8, tool: .line, vtable: 0x295100, getHelp: 0x1e2aa2, stringVM: 0x25d1a2, copy: "option = Polygon. shift = 45º lock"),
        .init(tag: 9, tool: nil, vtable: 0x295230, getHelp: 0x1e7774, stringVM: 0x25ce38, copy: "")
    ]

    // Frozen result of setModifiers from a selected base tool, then virtual help:
    // columns are native masks 0...15. -1 is an empty hint. Text/index4 is the
    // Control exception; Command/index1 wins over Control, Shift and Option.
    static let modifierRows: [[Int]] = [
        [-1,0,0,0,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,1,1,1,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,2,2,2,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,3,3,3,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,4,4,4,4,4,4,4,1,1,1,1,1,1,1,1],
        [-1,5,5,5,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,6,6,6,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,7,7,7,5,5,5,5,1,1,1,1,1,1,1,1],
        [-1,8,8,8,5,5,5,5,1,1,1,1,1,1,1,1]
    ]

    struct OriginalBinary {
        let bytes: [UInt8]
        let segments: [(vm: Int, size: Int, file: Int)]
        init(_ url: URL) throws {
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == "536bcddce08e8064e966e74363cf5cf396fe9a00cae9f573745943dbe82a5268" else {
                throw Failure(description: "Original binary fixture changed: \(digest)")
            }
            let originalBytes = Array(data)
            func word(_ offset: Int) -> Int {
                (0..<4).reduce(0) { $0 | Int(originalBytes[offset + $1]) << ($1 * 8) }
            }
            guard word(0) == 0xfeedface else { throw Failure(description: "Expected original i386 Mach-O") }
            var recovered: [(Int, Int, Int)] = [], offset = 28
            for _ in 0..<word(16) {
                if word(offset) == 1 { recovered.append((word(offset + 24), word(offset + 36), word(offset + 32))) }
                offset += word(offset + 4)
            }
            bytes = originalBytes; segments = recovered
        }
        func offset(_ vm: Int) throws -> Int {
            guard let segment = segments.first(where: { vm >= $0.vm && vm - $0.vm < $0.size }) else {
                throw Failure(description: "VM address not file-backed: \(String(vm, radix: 16))")
            }
            return segment.file + vm - segment.vm
        }
        func word(_ vm: Int) throws -> UInt32 {
            let start = try offset(vm)
            return (0..<4).reduce(0) { $0 | UInt32(bytes[start + $1]) << ($1 * 8) }
        }
        func string(_ vm: Int) throws -> String {
            let start = try offset(vm)
            guard let end = bytes[start...].firstIndex(of: 0),
                  let copy = String(bytes: bytes[start..<end], encoding: .utf8) else {
                throw Failure(description: "Invalid original UTF-8 at VM \(vm)")
            }
            return copy
        }
    }

    static func flags(_ nativeMask: Int) -> NSEvent.ModifierFlags {
        // Independent bridge fixture: raw AppKit bits verified in flagsChanged.
        NSEvent.ModifierFlags(rawValue: UInt(
            ((nativeMask & 1) << 17) | ((nativeMask & 2) << 18) |
            ((nativeMask & 4) << 16) | ((nativeMask & 8) << 17)))
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let path = args.isEmpty ? "original/Skitch.app/Contents/MacOS/Skitch" : args[0]
        // An explicit path is a request for that fixture, so only the default may be absent.
        let original = args.isEmpty && !FileManager.default.fileExists(atPath: path) ? nil : try OriginalBinary(URL(fileURLWithPath: path))
        if original == nil { print("SKIP original binary evidence: \(path) not found; running reconstruction-side checks only") }
        let prefix = "command(\u{F8FF}) = Grab. control = Eraser. tab = Pen\n"
        if let original { try expect(try original.string(0x21d3b2) == prefix, "Native action-hover prefix") }
        try expect(OriginalHintMessages.toolHoverPrefix == prefix, "Exact hover prefix, including Apple glyph/newline")

        for fixture in tools {
            if let original {
                try expect(try original.string(fixture.stringVM) == fixture.copy, "Native tool \(fixture.tag) expected copy")
                try expect(try original.word(fixture.vtable + 8 + 0x40) == fixture.getHelp, "Native tool \(fixture.tag) virtual getHelp target")
                try expect(try original.word(fixture.vtable + 8 + 0x44) == 0x1b4fb0, "Native tool \(fixture.tag) uses base getHelpForModifiers")
            }
            try expect(OriginalHintMessages.mappedSketchTool(forActionTag: fixture.tag) == fixture.tool, "Original tool-array mapping \(fixture.tag)")
            guard let tool = fixture.tool else {
                try expect(OriginalHintMessages.actionHelp(tag: fixture.tag).isEmpty, "Hand is empty and has no modern tool mapping")
                continue
            }
            try expect(OriginalHintMessages.toolHelp(tool) == fixture.copy, "Raw virtual tool copy \(fixture.tag)")
            try expect(OriginalHintMessages.actionHelp(tag: fixture.tag) == fixture.copy, "Action tag returns unprefixed tool help")
            try expect(OriginalHintMessages.actionHoverHint(tag: fixture.tag) == prefix + fixture.copy, "Controller adds tool-hover prefix")
            try expect(OriginalHintMessages.hover(tool: tool) == prefix + fixture.copy, "Parent hover API keeps native tool prefix")
            try expect(OriginalHintMessages.actionHoverHint(tag: 777, mappedSketchTool: tool) == prefix + fixture.copy,
                       "Explicit parent mapping works for modern control tags")
            for mask in 0..<16 {
                let modifiers = flags(mask)
                let row = modifierRows[fixture.tag][mask]
                let expected = row < 0 ? "" : tools[row].copy
                try expect(OriginalHintMessages.originalModifiers(modifiers) == mask, "Native bit bridge mask \(mask)")
                try expect(OriginalHintMessages.getHelpForModifiers(tool: tool, modifiers: modifiers) == (mask == 0 ? "" : fixture.copy),
                           "Base method keeps the whole tool hint for any nonzero mask \(fixture.tag)/\(mask)")
                try expect(OriginalHintMessages.modifierHint(tool: tool, modifiers: modifiers) == expected,
                           "Native selected-tool modifier matrix \(fixture.tag)/\(mask)")
                try expect(OriginalHintMessages.modifiers(tool: tool, flags: modifiers) == (expected.isEmpty ? nil : expected),
                           "Parent modifier API clears empty hints and uses native precedence")
                let noisy = modifiers.union([.capsLock, .numericPad, .function])
                try expect(OriginalHintMessages.originalModifiers(noisy) == mask &&
                           OriginalHintMessages.modifierHint(tool: tool, modifiers: noisy) == expected,
                           "Non-engine flags cannot create or change a hint")
            }
        }
        for mask in 0..<16 {
            try expect(OriginalHintMessages.modifierHint(tool: .crop, modifiers: flags(mask)).isEmpty &&
                       OriginalHintMessages.getHelpForModifiers(tool: .crop, modifiers: flags(mask)).isEmpty &&
                       OriginalHintMessages.modifiers(tool: .crop, flags: flags(mask)) == nil,
                       "No invented Crop help for mask \(mask)")
        }
        try expect(OriginalHintMessages.actionHoverHint(tag: 777, mappedSketchTool: .crop).isEmpty, "Unknown Crop hover remains empty")
        try expect(OriginalHintMessages.hover(tool: .crop) == nil, "Parent Crop hover stays unresolved")

        let paletteFixture: [(Int, Int, String, [UInt32])] = [
            (100,0x25d38d,"red",[0x3f800000,0,0,0x3f800000]),
            (101,0x25d391,"yellow",[0x3f800000,0x3f77f7f8,0,0x3f800000]),
            (102,0x25d398,"blue",[0x3dc8c8c9,0x3eeeeeef,0x3f800000,0x3f800000]),
            (103,0x25d39d,"pink",[0x3f7cfcfd,0x3d40c0c1,0x3eb2b2b3,0x3f800000]),
            (104,0x25d3a2,"translucent gray",[0,0,0,0x3edc28f6]),
            (105,0x25d3b3,"orange",[0x3f800000,0x3f008081,0x3db8b8b9,0x3f800000]),
            (106,0x25d3ba,"green",[0,0x3f68e8e9,0,0x3f800000]),
            (107,0x25d3c0,"white",[0x3f800000,0x3f800000,0x3f800000,0x3f800000]),
            (108,0x25d3c6,"black",[0,0,0,0x3f800000]),
            (109,0x25d3cc,"translucent highlighter",[0x3f800000,0x3f800000,0,0x3eb33333]),
            (110,0x25d3e4,"User color",[0,0x3f800000,0x3f800000,0x3f800000])
        ]
        let suffix = "\nshift-click to set canvas background color"
        if let original { try expect(try original.string(0x25d3ef) == suffix, "Native palette suffix") }
        try expect(OriginalHintMessages.palette.count == 11, "Exactly eleven original colors, including initial user color")
        for (tag, vm, name, bits) in paletteFixture {
            if let original { try expect(try original.string(vm) == name, "Native palette name \(tag)") }
            let entry = OriginalHintMessages.palette.first { $0.tag == tag }
            try expect(entry?.name == name && entry?.rgba.map(\.bitPattern) == bits, "Original RGBA Float32 bits and name \(tag)")
            try expect(OriginalHintMessages.actionHoverHint(tag: tag) == name + suffix, "Native color-hover copy \(tag)")
            try expect(OriginalHintMessages.hover(actionTag: tag) == name + suffix, "Parent color routing retains exact name and suffix")
        }

        let actionFixture: [(Int, Int, String)] = [
            (20,0x25d24e,"hold shift for non-preset sizes"),
            (40,0x25d26e,"drag me to Mail, the desktop, anywhere!"),
            (50,0x25d358,"first click clears drawing, second erases background"),
            (200,0x25d2e3,"shift-click for timed snap\noption-click to show Skitch during snap"),
            (201,0x25d2e3,"shift-click for timed snap\noption-click to show Skitch during snap"),
            (202,0x25d2e3,"shift-click for timed snap\noption-click to show Skitch during snap"),
            (203,0x25d326,"click for timed snap\nshift-click for instant snap")
        ]
        for (tag, vm, copy) in actionFixture {
            if let original { try expect(try original.string(vm) == copy, "Native action string \(tag)") }
            try expect(OriginalHintMessages.actionHelp(tag: tag) == copy && OriginalHintMessages.actionHoverHint(tag: tag) == copy,
                       "Exact unprefixed action copy \(tag)")
        }
        for tag in [200,201,202,203] {
            let expected = actionFixture.first { $0.0 == tag }!.2
            try expect(OriginalHintMessages.hover(actionTag: tag) == nil, "Unimplemented manual timing cannot advertise a capture hint")
            try expect(OriginalHintMessages.hover(actionTag: tag, captureActionsSupported: true) == expected,
                       "Parent may opt into the recovered copy only after implementing the advertised behavior")
        }
        let normal = "hold shift and click to set size to 100%", frame = "hold shift to resize proportionally"
        if let original { try expect(try original.string(0x25d296) == normal && original.string(0x25d2bf) == frame, "Native resize handle strings") }
        for tag in [1000,1002,1004,1006] {
            try expect(OriginalHintMessages.actionHelp(tag: tag) == normal &&
                       OriginalHintMessages.actionHelp(tag: tag, frameMode: true) == frame, "Frame-mode handle help \(tag)")
        }
        for tag in [-1,9,10,19,21,30,39,41,49,51,99,111,199,204,777,999,1001,1003,1005,1007,Int.max,Int.min] {
            try expect(OriginalHintMessages.mappedSketchTool(forActionTag: tag) == nil &&
                       OriginalHintMessages.actionHoverHint(tag: tag).isEmpty &&
                       OriginalHintMessages.actionHelp(tag: tag, frameMode: true).isEmpty,
                       "Unsupported/original-empty tag \(tag) cannot invent a hint")
        }
        try expect(NSApp == nil, "Pure fixture/matrix tests must not construct NSApplication")
        let evidence = original == nil ? "original binary evidence skipped" : "10 original vtables"
        print("PASS OriginalHintMessagesTests: \(checks) checks; 144 routed modifier cases; \(evidence); 11 RGBA entries; no desktop")
    }
}
#endif
