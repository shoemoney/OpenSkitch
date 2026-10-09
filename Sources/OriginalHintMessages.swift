import AppKit

/// Pure text/metadata boundary for hover and modifier hints. The parent owns
/// hover events, suppression while field editing, the top bevel, and tool state;
/// this type owns no native objects.
@MainActor
enum OriginalHintMessages {
    struct PaletteEntry: Equatable {
        let tag: Int
        let name: String
        /// Float32 components, not calibrated or converted NSColor.
        let rgba: [Float]
    }

    // Bit layout: shift 1, option 2, control 4, command 8.
    static func originalModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.shift) { result |= 1 }
        if flags.contains(.option) { result |= 2 }
        if flags.contains(.control) { result |= 4 }
        if flags.contains(.command) { result |= 8 }
        return result
    }

    /// Maps a toolbar action tag to its tool. Tag 9 (Hand) has no SketchTool
    /// equivalent, and Crop is a mode rather than a tool-array entry.
    static func mappedSketchTool(forActionTag tag: Int) -> SketchTool? {
        switch tag {
        case 0: return .brush
        case 1: return .select
        case 2: return .ellipse
        case 3: return .rectangle
        case 4: return .text
        case 5: return .eraser
        case 6: return .arrow
        case 7: return .fill
        case 8: return .line
        default: return nil
        }
    }

    /// Command overrides Control. The Control exception is Text, not Fill.
    /// This resolves a selected base tool; it does not model deferred drag state.
    static func effectiveTool(_ tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> SketchTool? {
        guard tool != .crop else { return nil }
        if modifiers.contains(.command) { return .select }
        if modifiers.contains(.control), tool != .text { return .eraser }
        return tool
    }

    /// Hint copy for each tool.
    static func toolHelp(_ tool: SketchTool) -> String {
        switch tool {
        case .select: return "Option copies. Shift adds to the selection."
        case .arrow: return "Option reverses the arrow. Shift snaps to 45°."
        case .line: return "Option draws a polygon. Shift locks to 45°."
        case .rectangle: return "Option draws from the center. Shift makes a square."
        case .ellipse: return "Option draws from the center. Shift makes a circle."
        case .brush: return "Option picks a color. Shift smooths less."
        case .text: return "Just start typing, with any tool."
        case .fill: return "Option picks a color. Shift fills without grouping."
        case .eraser: return "Shift smooths less."
        case .crop: return "" // Crop has no hint.
        }
    }

    /// Zero modifiers give an empty hint; any nonzero mask returns the tool's
    /// whole hint. Takes an already-effective tool, without re-routing it.
    static func getHelpForModifiers(tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> String {
        originalModifiers(modifiers) == 0 ? "" : toolHelp(tool)
    }

    /// Parent-facing modifier hint for a selected base tool. Hover help instead
    /// describes the hovered tool, independent of temporary modifier tool choice.
    static func modifierHint(tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> String {
        guard let effective = effectiveTool(tool, modifiers: modifiers) else { return "" }
        return getHelpForModifiers(tool: effective, modifiers: modifiers)
    }

    /// Shown above a tool's own hint when hovering a tool button.
    static let toolHoverPrefix = "Command selects. Control erases. Tab switches to the pen.\n"

    /// Parent routing API: nil clears the bevel for Crop.
    static func hover(tool: SketchTool) -> String? {
        tool == .crop ? nil : toolHoverPrefix + toolHelp(tool)
    }

    /// Parent routing API: selected base tool + event flags. An empty
    /// hint becomes nil, so the bevel can hide rather than show a blank panel.
    static func modifiers(tool: SketchTool, flags: NSEvent.ModifierFlags) -> String? {
        let message = modifierHint(tool: tool, modifiers: flags)
        return message.isEmpty ? nil : message
    }

    /// Parent action routing API. Snap text advertises Shift/Option timing,
    /// so it is opt-in only after the parent implements the advertised actions.
    /// Font has no action help. Tag 40 is Drag Me, not Font.
    static func hover(actionTag: Int, mappedSketchTool: SketchTool? = nil,
                      frameMode: Bool = false, captureActionsSupported: Bool = false) -> String? {
        if mappedSketchTool == nil, (200...203).contains(actionTag), !captureActionsSupported { return nil }
        let message = actionHoverHint(tag: actionTag, mappedSketchTool: mappedSketchTool, frameMode: frameMode)
        return message.isEmpty ? nil : message
    }

    /// An explicit mapping lets the parent route a tool control without assuming
    /// its tag; with no mapping the built-in tags are used. Tag 40 is Drag help.
    static func actionHelp(tag: Int, mappedSketchTool: SketchTool? = nil, frameMode: Bool = false) -> String {
        if let tool = mappedSketchTool { return toolHelp(tool) }
        if let tool = self.mappedSketchTool(forActionTag: tag) { return toolHelp(tool) }
        if let entry = palette.first(where: { $0.tag == tag }) {
            return entry.name + "\nShift-click to set the canvas background color"
        }
        switch tag {
        case 20: return "Hold Shift for custom sizes."
        case 40: return "Drag this to Mail, the desktop, or anywhere else."
        case 50: return "First click clears the drawing; a second click erases the background."
        case 200...202: return "Shift-click for a timed snap.\nOption-click to keep OpenSnap visible during the snap."
        case 203: return "Click for a timed snap.\nShift-click for an instant snap."
        case 1000, 1002, 1004, 1006:
            return frameMode ? "Hold Shift to resize proportionally." : "Hold Shift and click to reset the size to 100%."
        default: return "" // Includes the deliberately empty tag 30.
        }
    }

    /// Full user-visible action hover text: the native controller prepends the
    /// common modifier line to tool buttons, but not to colors or other actions.
    static func actionHoverHint(tag: Int, mappedSketchTool: SketchTool? = nil, frameMode: Bool = false) -> String {
        let tool = mappedSketchTool ?? self.mappedSketchTool(forActionTag: tag)
        if let tool { return tool == .crop ? "" : toolHoverPrefix + toolHelp(tool) }
        return actionHelp(tag: tag, frameMode: frameMode)
    }

    /// Palette names and Float32 RGBA components. Tag 110 is the initial custom
    /// color (cyan); the parent owns later custom values.
    static let palette: [PaletteEntry] = [
        entry(100, "red", [0x3f800000, 0, 0, 0x3f800000]),
        entry(101, "yellow", [0x3f800000, 0x3f77f7f8, 0, 0x3f800000]),
        entry(102, "blue", [0x3dc8c8c9, 0x3eeeeeef, 0x3f800000, 0x3f800000]),
        entry(103, "pink", [0x3f7cfcfd, 0x3d40c0c1, 0x3eb2b2b3, 0x3f800000]),
        entry(104, "translucent gray", [0, 0, 0, 0x3edc28f6]),
        entry(105, "orange", [0x3f800000, 0x3f008081, 0x3db8b8b9, 0x3f800000]),
        entry(106, "green", [0, 0x3f68e8e9, 0, 0x3f800000]),
        entry(107, "white", [0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000]),
        entry(108, "black", [0, 0, 0, 0x3f800000]),
        entry(109, "translucent highlighter", [0x3f800000, 0x3f800000, 0, 0x3eb33333]),
        entry(110, "custom color", [0, 0x3f800000, 0x3f800000, 0x3f800000])
    ]

    private static func entry(_ tag: Int, _ name: String, _ bits: [UInt32]) -> PaletteEntry {
        PaletteEntry(tag: tag, name: name, rgba: bits.map { Float(bitPattern: $0) })
    }
}
