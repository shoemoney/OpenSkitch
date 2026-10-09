// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D ORIGINAL_HINT_MESSAGES_TESTS \
//   Sources/SVGPath.swift Sources/DocumentModel.swift Sources/OriginalHintMessages.swift \
//   tests/OriginalHintMessagesTests.swift -o /tmp/opensnap-hint-messages-tests
// /tmp/opensnap-hint-messages-tests
#if ORIGINAL_HINT_MESSAGES_TESTS
import AppKit

/// Table of the exact hint copy. Pure text and modifier routing: no app,
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
        let copy: String
    }
    static let tools: [ToolFixture] = [
        .init(tag: 0, tool: .brush, copy: "Option picks a color. Shift smooths less."),
        .init(tag: 1, tool: .select, copy: "Option copies. Shift adds to the selection."),
        .init(tag: 2, tool: .ellipse, copy: "Option draws from the center. Shift makes a circle."),
        .init(tag: 3, tool: .rectangle, copy: "Option draws from the center. Shift makes a square."),
        .init(tag: 4, tool: .text, copy: "Just start typing, with any tool."),
        .init(tag: 5, tool: .eraser, copy: "Shift smooths less."),
        .init(tag: 6, tool: .arrow, copy: "Option reverses the arrow. Shift snaps to 45°."),
        .init(tag: 7, tool: .fill, copy: "Option picks a color. Shift fills without grouping."),
        .init(tag: 8, tool: .line, copy: "Option draws a polygon. Shift locks to 45°."),
        .init(tag: 9, tool: nil, copy: "")
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

    static func flags(_ nativeMask: Int) -> NSEvent.ModifierFlags {
        // Independent bridge fixture: raw AppKit bits verified in flagsChanged.
        NSEvent.ModifierFlags(rawValue: UInt(
            ((nativeMask & 1) << 17) | ((nativeMask & 2) << 18) |
            ((nativeMask & 4) << 16) | ((nativeMask & 8) << 17)))
    }

    static func main() throws {
        let prefix = "Command selects. Control erases. Tab switches to the pen.\n"
        try expect(OriginalHintMessages.toolHoverPrefix == prefix, "Exact hover prefix, including Apple glyph/newline")

        for fixture in tools {
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

        let paletteFixture: [(Int, String, [UInt32])] = [
            (100,"red",[0x3f800000,0,0,0x3f800000]),
            (101,"yellow",[0x3f800000,0x3f77f7f8,0,0x3f800000]),
            (102,"blue",[0x3dc8c8c9,0x3eeeeeef,0x3f800000,0x3f800000]),
            (103,"pink",[0x3f7cfcfd,0x3d40c0c1,0x3eb2b2b3,0x3f800000]),
            (104,"translucent gray",[0,0,0,0x3edc28f6]),
            (105,"orange",[0x3f800000,0x3f008081,0x3db8b8b9,0x3f800000]),
            (106,"green",[0,0x3f68e8e9,0,0x3f800000]),
            (107,"white",[0x3f800000,0x3f800000,0x3f800000,0x3f800000]),
            (108,"black",[0,0,0,0x3f800000]),
            (109,"translucent highlighter",[0x3f800000,0x3f800000,0,0x3eb33333]),
            (110,"custom color",[0,0x3f800000,0x3f800000,0x3f800000])
        ]
        let suffix = "\nShift-click to set the canvas background color"
        try expect(OriginalHintMessages.palette.count == 11, "Exactly eleven original colors, including initial user color")
        for (tag, name, bits) in paletteFixture {
            let entry = OriginalHintMessages.palette.first { $0.tag == tag }
            try expect(entry?.name == name && entry?.rgba.map(\.bitPattern) == bits, "Original RGBA Float32 bits and name \(tag)")
            try expect(OriginalHintMessages.actionHoverHint(tag: tag) == name + suffix, "Native color-hover copy \(tag)")
            try expect(OriginalHintMessages.hover(actionTag: tag) == name + suffix, "Parent color routing retains exact name and suffix")
        }

        let actionFixture: [(Int, String)] = [
            (20,"Hold Shift for custom sizes."),
            (40,"Drag this to Mail, the desktop, or anywhere else."),
            (50,"First click clears the drawing; a second click erases the background."),
            (200,"Shift-click for a timed snap.\nOption-click to keep OpenSnap visible during the snap."),
            (201,"Shift-click for a timed snap.\nOption-click to keep OpenSnap visible during the snap."),
            (202,"Shift-click for a timed snap.\nOption-click to keep OpenSnap visible during the snap."),
            (203,"Click for a timed snap.\nShift-click for an instant snap.")
        ]
        for (tag, copy) in actionFixture {
            try expect(OriginalHintMessages.actionHelp(tag: tag) == copy && OriginalHintMessages.actionHoverHint(tag: tag) == copy,
                       "Exact unprefixed action copy \(tag)")
        }
        for tag in [200,201,202,203] {
            let expected = actionFixture.first { $0.0 == tag }!.1
            try expect(OriginalHintMessages.hover(actionTag: tag) == nil, "Unimplemented manual timing cannot advertise a capture hint")
            try expect(OriginalHintMessages.hover(actionTag: tag, captureActionsSupported: true) == expected,
                       "Parent may opt into the recovered copy only after implementing the advertised behavior")
        }
        let normal = "Hold Shift and click to reset the size to 100%.", frame = "Hold Shift to resize proportionally."
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
                print("PASS OriginalHintMessagesTests: \(checks) checks; 144 routed modifier cases; 11 RGBA entries; no desktop")
    }
}
#endif
