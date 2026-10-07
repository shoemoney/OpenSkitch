import AppKit

/// Pure text/metadata boundary. The parent owns hover events, suppression while
/// field editing, the top bevel, and tool state; this type owns no native objects.
/// Recovered from Skitch 1.0.12 i386 (SHA256
/// 536bcddce08e8064e966e74363cf5cf396fe9a00cae9f573745943dbe82a5268).
/// Copy is unchanged, including case, newlines, º and the original Apple glyph.
@MainActor
enum OriginalHintMessages {
    struct PaletteEntry: Equatable {
        let tag: Int
        let name: String
        /// Original Float32 components, not calibrated or converted NSColor.
        let rgba: [Float]
    }

    // PlatformController::flagsChanged, decompiled.c:1047; engine bit layout.
    static func originalModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.shift) { result |= 1 }
        if flags.contains(.option) { result |= 2 }
        if flags.contains(.control) { result |= 4 }
        if flags.contains(.command) { result |= 8 }
        return result
    }

    /// Tool array established by DocumentController ctor at 0x001d515a.
    /// Index 9 is ToolHand (empty help), and has no SketchTool equivalent.
    /// Reconstruction Crop is a mode, not a recovered tool-array entry.
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

    /// DocumentController::setModifiers, 0x001e480a: Command overrides Control.
    /// The original Control exception is Text (index 4), NOT Fill (index 7).
    /// This resolves a selected base tool; it does not model deferred drag state.
    static func effectiveTool(_ tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> SketchTool? {
        guard tool != .crop else { return nil }
        if modifiers.contains(.command) { return .select }
        if modifiers.contains(.control), tool != .text { return .eraser }
        return tool
    }

    /// Exact vtable +0x40 getHelp() copy, recovered at VM 0x25c87a...0x25d1a2.
    static func toolHelp(_ tool: SketchTool) -> String {
        switch tool {
        case .select: return "option = Copy. shift = Multiple Selections"
        case .arrow: return "option = Arrow in reverse direction. shift = 45º arrows"
        case .line: return "option = Polygon. shift = 45º lock"
        case .rectangle: return "option = Centered. shift = Perfect square"
        case .ellipse: return "option = Centered. shift = Perfect circle"
        case .brush: return "option = Eyedropper. shift = Less smoothing"
        case .text: return "just type at any time, when using any tool!"
        case .fill: return "option = Eyedropper. shift = Non-grouping fill"
        case .eraser: return "shift = less smoothing"
        case .crop: return "" // No original getHelp implementation recovered.
        }
    }

    /// Exact Tool::getHelpForModifiers, 0x001b4fb0, decompiled.c:277165.
    /// All ten original vtables use this base method at +0x44: zero mask is
    /// empty; ANY nonzero engine mask returns the complete virtual getHelp.
    /// This low-level API takes an already-effective tool, without re-routing it.
    static func getHelpForModifiers(tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> String {
        originalModifiers(modifiers) == 0 ? "" : toolHelp(tool)
    }

    /// Parent-facing modifier hint for a selected base tool. Hover help instead
    /// describes the hovered tool, independent of temporary modifier tool choice.
    static func modifierHint(tool: SketchTool, modifiers: NSEvent.ModifierFlags) -> String {
        guard let effective = effectiveTool(tool, modifiers: modifiers) else { return "" }
        return getHelpForModifiers(tool: effective, modifiers: modifiers)
    }

    // PlatformController::mouseEnteredInView, VM 0x21d3b2 (49 UTF-8 bytes).
    static let toolHoverPrefix = "command(\u{F8FF}) = Grab. control = Eraser. tab = Pen\n"

    /// Parent routing API: nil clears the bevel for the reconstruction-only Crop.
    static func hover(tool: SketchTool) -> String? {
        tool == .crop ? nil : toolHoverPrefix + toolHelp(tool)
    }

    /// Parent routing API: selected base tool + event flags. An empty original
    /// hint becomes nil, so the bevel can hide rather than show a blank panel.
    static func modifiers(tool: SketchTool, flags: NSEvent.ModifierFlags) -> String? {
        let message = modifierHint(tool: tool, modifiers: flags)
        return message.isEmpty ? nil : message
    }

    /// Parent action routing API. Recovered Snap text advertises Shift timing,
    /// so it is opt-in only after the parent implements the advertised actions.
    /// Font has no recovered action help. Tag 40 is Drag Me, not Font.
    static func hover(actionTag: Int, mappedSketchTool: SketchTool? = nil,
                      frameMode: Bool = false, captureActionsSupported: Bool = false) -> String? {
        if mappedSketchTool == nil, (200...203).contains(actionTag), !captureActionsSupported { return nil }
        let message = actionHoverHint(tag: actionTag, mappedSketchTool: mappedSketchTool, frameMode: frameMode)
        return message.isEmpty ? nil : message
    }

    /// Exact DocumentController::getHelpForActionTag, 0x001e8fb0. An explicit
    /// mapping lets the parent route a modern tool control without assuming its
    /// tag matches the original nib. With no mapping, original tags are used.
    /// Tag 40 really contains Drag help; no Font help is invented from its label.
    static func actionHelp(tag: Int, mappedSketchTool: SketchTool? = nil, frameMode: Bool = false) -> String {
        if let tool = mappedSketchTool { return toolHelp(tool) }
        if let tool = self.mappedSketchTool(forActionTag: tag) { return toolHelp(tool) }
        if let entry = palette.first(where: { $0.tag == tag }) {
            return entry.name + "\nshift-click to set canvas background color"
        }
        switch tag {
        case 20: return "hold shift for non-preset sizes"
        case 40: return "drag me to Mail, the desktop, anywhere!"
        case 50: return "first click clears drawing, second erases background"
        case 200...202: return "shift-click for timed snap\noption-click to show Skitch during snap"
        case 203: return "click for timed snap\nshift-click for instant snap"
        case 1000, 1002, 1004, 1006:
            return frameMode ? "hold shift to resize proportionally" : "hold shift and click to set size to 100%"
        default: return "" // Includes original explicitly-empty tag 30.
        }
    }

    /// Full user-visible action hover text: the native controller prepends the
    /// common modifier line to tool buttons, but not to colors or other actions.
    static func actionHoverHint(tag: Int, mappedSketchTool: SketchTool? = nil, frameMode: Bool = false) -> String {
        let tool = mappedSketchTool ?? self.mappedSketchTool(forActionTag: tag)
        if let tool { return tool == .crop ? "" : toolHoverPrefix + toolHelp(tool) }
        return actionHelp(tag: tag, frameMode: frameMode)
    }

    /// Names: VM 0x25d38d...0x25d3e4. RGBA: initializer at 0x001dc570,
    /// decompiled.c:307164, populating 0x296b74...0x296c20. Tag 110 is the
    /// original INITIAL user color (cyan); the parent owns later custom values.
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
        entry(110, "User color", [0, 0x3f800000, 0x3f800000, 0x3f800000])
    ]

    private static func entry(_ tag: Int, _ name: String, _ bits: [UInt32]) -> PaletteEntry {
        PaletteEntry(tag: tag, name: name, rgba: bits.map { Float(bitPattern: $0) })
    }
}
