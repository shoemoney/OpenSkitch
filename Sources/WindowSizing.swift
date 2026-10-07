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
    /// Recovered original proportional resizing is width-driven: vertical delta is
    /// ignored and height is floor(width * initial.height / initial.width + 0.5).
    /// Empty canvases use independent axes when the caller chooses proportional: false.
    /// The API's flag does not assert which original keyboard modifier controls
    /// proportional scaling. That mapping remains unresolved.
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
            guard width.isFinite, (1...maximumDimension).contains(width) else { return nil }
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
}
