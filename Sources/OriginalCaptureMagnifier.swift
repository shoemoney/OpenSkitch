import AppKit
import CoreGraphics

/// pqCHSMagnifierView geometry. Every constant is read from the original binary
/// (floats at the cited DAT_ addresses; file offset = address - 0x1000).
enum OriginalCaptureMagnifierGeometry {
    /// initWithFrame: ivars +0x58/+0x5c/+0x60 = 10.0 (decompiled.c:68880-68882).
    static let zoom: CGFloat = 10
    static let sourcePixels = NSSize(width: 10, height: 10)
    /// viewDidMoveToWindow boolForKey: (decompiled.c:18890-18898).
    static let defaultsKey = "showCrosshairMagnifier"
    /// pqCHSView.viewDidMoveToWindow adds DAT_00260520 to (mouse - requiredSize);
    /// movss 0x242463(%ebx) at 0x1e417 with ebx = 0x1e0bd (popl) -> 0x260520 = -2.0f.
    static let placementOffset: CGFloat = -2
    /// Initial view frame 0x42c80000 = 100 square (decompiled.c:18890-18900).
    static let initialSize = NSSize(width: 100, height: 100)

    /// decompiled.c:69416-69436: origin (6,6), size (10*10, 10*10).
    static var magnifierRect: NSRect {
        NSRect(x: 6, y: 6, width: sourcePixels.width * zoom, height: sourcePixels.height * zoom)
    }
    /// decompiled.c:69437-69479: NSInsetRect(magnifierRect, -3, -3).
    static var magnifierBorderRect: NSRect { magnifierRect.insetBy(dx: -3, dy: -3) }

    /// decompiled.c:69338-69405: inset(union(border, label), -3, -3).size.
    static func requiredDisplaySize(labelRect: NSRect) -> NSSize {
        magnifierBorderRect.union(labelRect).insetBy(dx: -3, dy: -3).size
    }

    /// decompiled.c:69462-69530 (labelRect): centered under the border, overlapping
    /// its bottom by 10, 8 wider and 14 taller than the text.
    static func labelRect(textSize: NSSize) -> NSRect {
        let border = magnifierBorderRect
        return NSRect(x: border.minX + border.width * 0.5 - (textSize.width * 0.5 + 4),
                      y: border.maxY - 10,
                      width: textSize.width + 8,
                      height: textSize.height + 10 + 4)
    }

    /// Point-space source square (decompiled.c:69150-69168): zero rect at mouse+0.5,
    /// inset by -0.5*zoom, made integral.
    static func sourceRect(mousePoint: NSPoint) -> NSRect {
        let half = zoom * 0.5
        return NSRect(x: mousePoint.x + 0.5, y: mousePoint.y + 0.5, width: 0, height: 0)
            .insetBy(dx: -half, dy: -half).integral
    }

    /// Frame origin: (mouse - requiredSize) + offset (decompiled.c:18905-18912),
    /// kept fully inside the overlay.
    static func placementFrame(mousePoint: NSPoint, requiredSize: NSSize, in bounds: NSRect) -> NSRect {
        var origin = NSPoint(x: mousePoint.x - requiredSize.width + placementOffset,
                             y: mousePoint.y - requiredSize.height + placementOffset)
        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - requiredSize.width))
        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - requiredSize.height))
        return NSRect(origin: origin, size: requiredSize)
    }
}

final class OriginalCaptureMagnifierView: NSView {
    var mousePoint = NSPoint.zero { didSet { needsDisplay = true } }
    var labelString = "" { didSet { needsDisplay = true } }
    /// Screen pixels behind the overlay; `imageScale` is pixels per overlay point.
    /// Rows are top-first (CGImage order) while overlay points are bottom-left.
    var sourceImage: CGImage? { didSet { needsDisplay = true } }
    var imageScale: CGFloat = 1

    override var isFlipped: Bool { true }

    private var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]
    }
    private var labelTextSize: NSSize { (labelString as NSString).size(withAttributes: labelAttributes) }
    var labelRect: NSRect { OriginalCaptureMagnifierGeometry.labelRect(textSize: labelTextSize) }
    var requiredDisplaySize: NSSize { OriginalCaptureMagnifierGeometry.requiredDisplaySize(labelRect: labelRect) }

    /// Sampled pixel window for the current pointer, top-left pixel coordinates.
    func samplePixelRect(imageHeight: Int) -> CGRect {
        let src = OriginalCaptureMagnifierGeometry.sourceRect(mousePoint: mousePoint)
        return CGRect(x: src.minX * imageScale,
                      y: CGFloat(imageHeight) - src.maxY * imageScale,
                      width: src.width * imageScale, height: src.height * imageScale)
    }

    override func draw(_ dirtyRect: NSRect) {
        let geometry = OriginalCaptureMagnifierGeometry.self
        let border = geometry.magnifierBorderRect
        let lens = geometry.magnifierRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black; shadow.shadowBlurRadius = 4
        shadow.set()
        NSColor.white.setFill(); border.fill()
        NSGraphicsContext.restoreGraphicsState()
        if let image = sourceImage, let cg = NSGraphicsContext.current?.cgContext,
           let crop = image.cropping(to: samplePixelRect(imageHeight: image.height)) {
            cg.saveGState()
            cg.interpolationQuality = .none
            cg.translateBy(x: lens.minX, y: lens.maxY)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(crop, in: CGRect(origin: .zero, size: lens.size))
            cg.restoreGState()
        } else {
            NSColor(calibratedWhite: 0.5, alpha: 1).setFill(); lens.fill()
        }
        NSColor.black.setStroke()
        let centre = NSRect(x: lens.midX - geometry.zoom * 0.5, y: lens.midY - geometry.zoom * 0.5,
                            width: geometry.zoom, height: geometry.zoom)
        NSBezierPath(rect: centre).stroke()
        let label = labelRect
        NSColor(calibratedWhite: 1, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: label, xRadius: 3, yRadius: 3).fill()
        (labelString as NSString).draw(at: NSPoint(x: label.minX + 4, y: label.minY + 5), withAttributes: labelAttributes)
    }
}
