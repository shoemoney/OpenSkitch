import Foundation
import CoreGraphics

public enum CanvasCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public enum CanvasEdge: CaseIterable {
    case left, right, top, bottom
}

public struct CanvasCropPreview {
    /// Source-space rectangle, relative to the current canvas's top-left origin.
    public let rect: CGRect
    /// Unzoomed output dimensions; cropping retains each axis's output/source density.
    public let outputSize: CGSize
}

/// Pure geometry only. No display lookup, windows, image allocation, or document mutation.
public enum WindowSizingPolicy {
    private static let maximumDimension: CGFloat = 16_384
    private static let maximumPixelCount: CGFloat = 32_000_000

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && (1...maximumDimension).contains(size.width)
            && (1...maximumDimension).contains(size.height)
            && size.width * size.height <= maximumPixelCount
    }

    private static func validCapacity(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
    }

    /// `screen` is the caller's visible screen size, not its full frame.
    /// Original maxFrame/maxFrameOnScreenWithoutScrollers: decompiled.c:358-547;
    /// binary constants 0x260448/4c/50 are -30/-40/-170, followed by a 4-point inset.
    /// The recovered branch reserves 80 vertically when modifier tips are enabled,
    /// and 40 for overlays alone. Both flags retain the 80-point vertical reserve.
    /// Original runtime equivalence remains unverified.
    public static func availableCanvas(screen: CGSize, chrome: CGSize,
                                       modtip: Bool = false, overlay: Bool = false) -> CGSize? {
        guard validCapacity(screen), chrome.width.isFinite, chrome.height.isFinite,
              chrome.width >= 0, chrome.height >= 0 else { return nil }
        let available = CGSize(width: screen.width - chrome.width - 30 - 8 - (overlay ? 170 : 0),
                               height: screen.height - chrome.height - 30 - 8
                                   - (modtip ? 80 : (overlay ? 40 : 0)))
        return validCapacity(available) ? available : nil
    }

    /// Original ActionSetBackground fitting; leaves smaller images at their original size.
    /// Capacity is not an image allocation, so large monitors need no pixel-area limit.
    public static func fittedOutput(source: CGSize, available: CGSize) -> CGSize? {
        guard validSize(source), validCapacity(available) else { return nil }
        let scale = min(1, available.width / source.width, available.height / source.height)
        let output = CGSize(width: source.width * scale, height: source.height * scale)
        return validSize(output) ? output : nil
    }

    /// Original canGoToActualMode uses horizontal pixelSize < 1 in normal snap mode
    /// (decompiled.c:4656). This is entry eligibility; the caller owns mode transitions.
    public static func actualEligible(source: CGSize, output: CGSize, normalMode: Bool) -> Bool {
        normalMode && validSize(source) && validSize(output) && output.width / source.width < 1
    }

    /// `corner` names the dragged corner; its opposite remains anchored by the caller.
    /// Deltas use top-left canvas coordinates: positive X right, positive Y down.
    /// ActionCropResize::_frameForCropResize (decompiled.c:311318-311440): proportional resizing is
    /// width-driven: vertical delta is ignored and height is floor(width * initial.height / initial.width + 0.5).
    /// The proportional minimum is minimumProportionalCanvas; the original clamps by recursing with a
    /// corrected delta, while this returns nil so the caller keeps its last valid preview.
    /// Empty canvases use independent axes when the caller chooses proportional: false.
    /// Which gesture state asks for proportional is resizesProportionally: it is NOT a keyboard
    /// modifier on every snap mode (PlatformController.resizeProportionally, decompiled.c:3756).
    public static func cornerOutput(initial: CGSize, delta: CGPoint, corner: CanvasCorner,
                                    proportional: Bool = true) -> CGSize? {
        guard validSize(initial), delta.x.isFinite, delta.y.isFinite else { return nil }
        let dx: CGFloat
        let dy: CGFloat
        switch corner {
        case .topLeft: dx = -delta.x; dy = -delta.y
        case .topRight: dx = delta.x; dy = -delta.y
        case .bottomLeft: dx = -delta.x; dy = delta.y
        case .bottomRight: dx = delta.x; dy = delta.y
        }
        let output: CGSize
        if proportional {
            let width = initial.width + dx
            guard width.isFinite, (1...maximumDimension).contains(width),
                  width >= minimumProportionalCanvas(initial: initial).width else { return nil }
            output = CGSize(width: width, height: floor(width * initial.height / initial.width + 0.5))
        } else {
            output = CGSize(width: initial.width + dx, height: initial.height + dy)
        }
        return validSize(output) ? output : nil
    }

    /// Deltas are screen points in the same right/down convention as cornerOutput.
    /// Divide by (output/source * zoom) to obtain source-space movement. Expansion
    /// may have a negative origin. Option's symmetric crop moves the opposite edge
    /// equally (original skitchHelp/skitch_resizing.html:88); unrelated delta is ignored.
    /// Fractional dimensions are preserved; pixel rounding belongs to the caller.
    public static func cropPreview(source: CGSize, output: CGSize, delta: CGPoint,
                                   edge: CanvasEdge, symmetric: Bool, zoom: CGFloat) -> CanvasCropPreview? {
        guard validSize(source), validSize(output), delta.x.isFinite, delta.y.isFinite,
              zoom.isFinite, zoom > 0 else { return nil }
        let density = CGSize(width: output.width / source.width, height: output.height / source.height)
        let screenScale = CGSize(width: density.width * zoom, height: density.height * zoom)
        guard screenScale.width.isFinite, screenScale.height.isFinite,
              screenScale.width > 0, screenScale.height > 0 else { return nil }

        var rect = CGRect(origin: .zero, size: source)
        let factor: CGFloat = symmetric ? 2 : 1
        switch edge {
        case .left:
            let movement = delta.x / screenScale.width
            rect.origin.x = movement
            rect.size.width -= movement * factor
        case .right:
            let movement = delta.x / screenScale.width
            rect.origin.x = symmetric ? -movement : 0
            rect.size.width += movement * factor
        case .top:
            let movement = delta.y / screenScale.height
            rect.origin.y = movement
            rect.size.height -= movement * factor
        case .bottom:
            let movement = delta.y / screenScale.height
            rect.origin.y = symmetric ? -movement : 0
            rect.size.height += movement * factor
        }
        guard validSize(rect.size), rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else { return nil }
        let result = CGSize(width: rect.width * density.width, height: rect.height * density.height)
        guard validSize(result) else { return nil }
        return CanvasCropPreview(rect: rect, outputSize: result)
    }

    // MARK: ActionCropResize rules (docs/adr/0001-crop-resize-original-rules.md)

    /// ActionCropResize crop ids. Corners and edges index the original `directionVector` table
    /// (decompiled.c:307215-307240): 0 TL, 1 top, 2 TR, 3 right, 4 BR, 5 bottom, 6 BL, 7 left, 8 centre.
    /// -1 is "resize about the centre": the ctor reads row 4 and always mirrors the delta (311318).
    public static func cropID(corner: CanvasCorner) -> Int {
        switch corner { case .topLeft: return 0; case .topRight: return 2
        case .bottomRight: return 4; case .bottomLeft: return 6 }
    }

    public static func cropID(edge: CanvasEdge) -> Int {
        switch edge { case .top: return 1; case .right: return 3; case .bottom: return 5; case .left: return 7 }
    }

    /// `directionVector[id]`: -1 moves the left/top edge, +1 the right/bottom edge, 0 leaves the axis alone.
    /// Id -1 uses row 4. Returns nil outside -1...8.
    public static func cropDirection(id: Int) -> (x: Int, y: Int)? {
        let table: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (0, 0)]
        let row = id == -1 ? 4 : id
        guard table.indices.contains(row) else { return nil }
        return (table[row].0, table[row].1)
    }

    /// SkitchCropView.mouseDragged passes `centered = modifierFlags >> 19 & 1` (decompiled.c:9990);
    /// bit 19 (0x80000) is NSEventModifierFlagOption.
    public static func isCenteredCrop(modifierFlags: UInt) -> Bool { modifierFlags >> 19 & 1 == 1 }

    /// PlatformController.resizeProportionally (decompiled.c:3756-3790). snapMode 1 follows Shift
    /// (flag 0x20000); snapModes 0 and 3 are proportional unless the document is empty without a
    /// background; every other snapMode is false; frame mode (+0x74 != 0) forces true.
    /// Unresolved: which Swift state maps to the original snapMode integers; the caller must supply them.
    public static func resizesProportionally(snapMode: Int, shiftHeld: Bool, frameMode: Bool,
                                             hasContent: Bool) -> Bool {
        if frameMode { return true }
        switch snapMode {
        case 1: return shiftHeld
        case 0, 3: return hasContent
        default: return false
        }
    }

    /// Smallest proportional canvas: 1 on the shorter-ratio axis, the other axis floor(ratio + 0.5)
    /// (_frameForCropResize 311400-311412, kMinDocumentSize = 1.0).
    public static func minimumProportionalCanvas(initial: CGSize) -> CGSize {
        guard initial.width > 0, initial.height > 0 else { return CGSize(width: 1, height: 1) }
        if initial.width <= initial.height {
            return CGSize(width: 1, height: floor(initial.height / initial.width + 0.5))
        }
        return CGSize(width: floor(initial.width / initial.height + 0.5), height: 1)
    }

    /// SkitchBorderView.maxViewSize (decompiled.c:13944): bounds plus DAT_002606a8 = -8 on each axis.
    public static func maxViewSize(bounds: CGSize) -> CGSize {
        CGSize(width: bounds.width - 8, height: bounds.height - 8)
    }

    /// SkitchBorderView.awakeFromNib (decompiled.c:14164-14175) builds the 12 crop views only when
    /// inActualMode is false.
    public static func cropViewsExist(inActualMode: Bool) -> Bool { !inActualMode }
}
