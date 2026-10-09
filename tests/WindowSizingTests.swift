// Pure geometry tests: no NSApplication, windows, images, desktop input, or permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D WINDOW_SIZING_TESTS Sources/WindowSizing.swift tests/WindowSizingTests.swift \
//   -o /tmp/opensnap-window-sizing-tests
// rtk proxy /tmp/opensnap-window-sizing-tests
#if WINDOW_SIZING_TESTS
import Foundation
import CoreGraphics

@main
private enum WindowSizingTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static func close(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
        actual.isFinite && abs(actual - expected) <= 1e-9 * max(1, abs(expected))
    }

    private static func size(_ actual: CGSize?, _ expected: CGSize, _ message: String) throws {
        guard let actual else { throw Failure(description: "\(message): unexpected nil") }
        try expect(close(actual.width, expected.width) && close(actual.height, expected.height),
                   "\(message): got \(actual), expected \(expected)")
    }

    private static func preview(_ actual: CanvasCropPreview?, rect expected: CGRect,
                                output: CGSize, _ message: String) throws {
        guard let actual else { throw Failure(description: "\(message): unexpected nil") }
        try expect(close(actual.rect.minX, expected.minX) && close(actual.rect.minY, expected.minY)
                   && close(actual.rect.width, expected.width) && close(actual.rect.height, expected.height),
                   "\(message): got rect \(actual.rect), expected \(expected)")
        try size(actual.outputSize, output, "\(message) output")
    }

    static func main() throws {
        let screen = CGSize(width: 1440, height: 900)
        let chrome = CGSize(width: 80, height: 120)
        try size(WindowSizingPolicy.availableCanvas(screen: screen, chrome: chrome),
                 CGSize(width: 1322, height: 742), "Visible frame minus chrome, 30 and 8")
        try size(WindowSizingPolicy.availableCanvas(screen: screen, chrome: chrome, modtip: true),
                 CGSize(width: 1322, height: 662), "Recovered keyboard hint 80-point allowance")
        try size(WindowSizingPolicy.availableCanvas(screen: screen, chrome: chrome, overlay: true),
                 CGSize(width: 1152, height: 702), "Overlay reserves 170 horizontal and 40 vertical")
        try size(WindowSizingPolicy.availableCanvas(screen: screen, chrome: chrome, modtip: true, overlay: true),
                 CGSize(width: 1152, height: 662), "Both flags use the recovered keyboard hint vertical reserve")
        try size(WindowSizingPolicy.availableCanvas(screen: CGSize(width: 39, height: 39), chrome: .zero),
                 CGSize(width: 1, height: 1), "Smallest valid capacity")
        for small in [CGSize(width: 38, height: 39), CGSize(width: 39, height: 38),
                      CGSize(width: 208, height: 78)] {
            try expect(WindowSizingPolicy.availableCanvas(screen: small, chrome: .zero,
                       overlay: small.width == 208) == nil, "Exhausted screen capacity")
        }
        try size(WindowSizingPolicy.availableCanvas(screen: CGSize(width: 100_000, height: 100_000), chrome: .zero),
                 CGSize(width: 99_962, height: 99_962), "Large screen capacity is not an image allocation")

        let source = CGSize(width: 800, height: 600)
        try size(WindowSizingPolicy.fittedOutput(source: source, available: CGSize(width: 1600, height: 1200)),
                 source, "Fit never enlarges")
        try size(WindowSizingPolicy.fittedOutput(source: source, available: CGSize(width: 400, height: 500)),
                 CGSize(width: 400, height: 300), "Width-limited fit")
        try size(WindowSizingPolicy.fittedOutput(source: source, available: CGSize(width: 700, height: 150)),
                 CGSize(width: 200, height: 150), "Height-limited fit")
        try size(WindowSizingPolicy.fittedOutput(source: CGSize(width: 7, height: 3),
                 available: CGSize(width: 5, height: 2)), CGSize(width: 14.0 / 3, height: 2), "Fractional ratio retained")
        try size(WindowSizingPolicy.fittedOutput(source: source,
                 available: WindowSizingPolicy.availableCanvas(screen: screen, chrome: chrome)!),
                 source, "Fit uses recovered normal-screen capacity")
        try size(WindowSizingPolicy.fittedOutput(source: CGSize(width: 8000, height: 4000),
                 available: CGSize(width: 99_962, height: 99_962)),
                 CGSize(width: 8000, height: 4000), "Inclusive 32M fit and oversized monitor")
        try expect(WindowSizingPolicy.fittedOutput(source: CGSize(width: 16_384, height: 1),
                   available: CGSize(width: 1, height: 1)) == nil, "Fit rejects sub-one-pixel companion")

        try expect(WindowSizingPolicy.actualEligible(source: source, output: CGSize(width: 400, height: 300),
                   normalMode: true), "Actual available below horizontal density one")
        try expect(!WindowSizingPolicy.actualEligible(source: source, output: source, normalMode: true), "Actual strict threshold")
        try expect(WindowSizingPolicy.actualEligible(source: source,
                   output: CGSize(width: source.width.nextDown, height: source.height), normalMode: true),
                   "Actual accepts immediately below one without an arbitrary tolerance")
        try expect(!WindowSizingPolicy.actualEligible(source: source, output: CGSize(width: 900, height: 600),
                   normalMode: true), "Actual unavailable above horizontal density one")
        try expect(!WindowSizingPolicy.actualEligible(source: source, output: CGSize(width: 800, height: 300),
                   normalMode: true), "Height-only reduction does not enable Actual")
        try expect(WindowSizingPolicy.actualEligible(source: source, output: CGSize(width: 799.5, height: 900),
                   normalMode: true), "Actual checks width even with enlarged height")
        try expect(!WindowSizingPolicy.actualEligible(source: source, output: CGSize(width: 400, height: 300),
                   normalMode: false), "Actual requires normal mode")

        // Corner identifies the handle being dragged. Positive Y points down.
        let corners: [(CanvasCorner, CGPoint)] = [(.topLeft, CGPoint(x: -80, y: -30)),
            (.topRight, CGPoint(x: 80, y: -30)), (.bottomLeft, CGPoint(x: -80, y: 30)),
            (.bottomRight, CGPoint(x: 80, y: 30))]
        try expect(CanvasCorner.allCases.count == 4, "All four corners exposed")
        try expect(CanvasEdge.allCases.count == 4, "All four edges exposed")
        for (corner, delta) in corners {
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: delta, corner: corner),
                     CGSize(width: 880, height: 660), "\(corner): width drives proportional expansion")
            try size(WindowSizingPolicy.cornerOutput(initial: source,
                     delta: CGPoint(x: -delta.x, y: -delta.y), corner: corner),
                     CGSize(width: 720, height: 540), "\(corner): contraction")
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: delta, corner: corner, proportional: false),
                     CGSize(width: 880, height: 630), "\(corner): independent axes")
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: .zero, corner: corner), source, "\(corner): no movement")
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: 0, y: 3000), corner: corner),
                     source, "\(corner): proportional height-only drag has no effect")
            let vertical: CGFloat = corner == .topLeft || corner == .topRight ? -120 : 120
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: 0, y: vertical),
                     corner: corner, proportional: false), CGSize(width: 800, height: 720),
                     "\(corner): empty-canvas caller can choose independent height")
            let xSign: CGFloat = delta.x < 0 ? -1 : 1
            for (width, height): (CGFloat, CGFloat) in [(2.98, 1), (3, 2), (3.02, 2)] {
                try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 8, height: 4),
                         delta: CGPoint(x: (width - 8) * xSign, y: 1000), corner: corner),
                         CGSize(width: width, height: height), "\(corner): original half-up height rounding at width \(width)")
            }
        }
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 1000, height: 100),
                 delta: CGPoint(x: 50, y: 20), corner: .bottomRight),
                 CGSize(width: 1050, height: 105), "Larger relative height delta cannot drive proportional output")
        try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: 80, y: -120), corner: .bottomRight),
                 CGSize(width: 880, height: 660), "Opposing larger vertical delta cannot override width expansion")
        try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: 80, y: -60), corner: .bottomRight),
                 CGSize(width: 880, height: 660), "Opposing equal relative deltas still use width")
        try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: -80, y: 120), corner: .bottomRight),
                 CGSize(width: 720, height: 540), "Width contraction wins despite vertical expansion")
        try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 16_384, height: 1),
                   delta: CGPoint(x: -8192, y: 0), corner: .bottomRight) == nil,
                   "ActionCropResize minimum width floor(w/h+0.5)=16384 for a 16384x1 canvas (decompiled.c:311400)")
        try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 16_384, height: 1),
                   delta: CGPoint(x: -8193, y: 0), corner: .bottomRight) == nil,
                   "Derived height that rounds to zero is rejected")
        try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 1, height: 16_384),
                   delta: CGPoint(x: 1, y: 0), corner: .bottomRight) == nil,
                   "Rounded derived height beyond maximum is rejected")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 8000, height: 4000), delta: .zero, corner: .topLeft),
                 CGSize(width: 8000, height: 4000), "32M corner boundary")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 16_384, height: 1), delta: .zero, corner: .bottomRight),
                 CGSize(width: 16_384, height: 1), "Maximum legal dimension")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 2, height: 2),
                 delta: CGPoint(x: -1, y: -1), corner: .bottomRight), CGSize(width: 1, height: 1), "Minimum corner dimensions")

        // Nonuniform density and zoom: X screen scale = 1; Y screen scale = 0.5.
        let output = CGSize(width: 400, height: 150)
        let edges: [(CanvasEdge, CGPoint, CGRect, CGRect, CGSize, CGSize)] = [
            (.left, CGPoint(x: 40, y: 999), CGRect(x: 40, y: 0, width: 760, height: 600),
             CGRect(x: 40, y: 0, width: 720, height: 600), CGSize(width: 380, height: 150), CGSize(width: 360, height: 150)),
            (.right, CGPoint(x: -40, y: 999), CGRect(x: 0, y: 0, width: 760, height: 600),
             CGRect(x: 40, y: 0, width: 720, height: 600), CGSize(width: 380, height: 150), CGSize(width: 360, height: 150)),
            (.top, CGPoint(x: 999, y: 15), CGRect(x: 0, y: 30, width: 800, height: 570),
             CGRect(x: 0, y: 30, width: 800, height: 540), CGSize(width: 400, height: 142.5), CGSize(width: 400, height: 135)),
            (.bottom, CGPoint(x: 999, y: -15), CGRect(x: 0, y: 0, width: 800, height: 570),
             CGRect(x: 0, y: 30, width: 800, height: 540), CGSize(width: 400, height: 142.5), CGSize(width: 400, height: 135))
        ]
        for (edge, delta, rect, centered, croppedOutput, centeredOutput) in edges {
            try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: delta,
                        edge: edge, symmetric: false, zoom: 2), rect: rect, output: croppedOutput, "\(edge): inward crop")
            try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: delta,
                        edge: edge, symmetric: true, zoom: 2), rect: centered, output: centeredOutput, "\(edge): symmetric crop")
            let reverse = CGPoint(x: -delta.x, y: -delta.y)
            let horizontal = edge == .left || edge == .right
            let expanded = CGRect(x: edge == .left ? -40 : 0, y: edge == .top ? -30 : 0,
                                  width: horizontal ? 840 : 800, height: horizontal ? 600 : 630)
            let symmetricExpansion = CGRect(x: horizontal ? -40 : 0, y: horizontal ? 0 : -30,
                                            width: horizontal ? 880 : 800, height: horizontal ? 600 : 660)
            try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: reverse,
                        edge: edge, symmetric: false, zoom: 2), rect: expanded,
                        output: horizontal ? CGSize(width: 420, height: 150) : CGSize(width: 400, height: 157.5),
                        "\(edge): outward expansion")
            try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: reverse,
                        edge: edge, symmetric: true, zoom: 2), rect: symmetricExpansion,
                        output: horizontal ? CGSize(width: 440, height: 150) : CGSize(width: 400, height: 165),
                        "\(edge): symmetric expansion retains center")
            for symmetric in [false, true] {
                try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: .zero,
                            edge: edge, symmetric: symmetric, zoom: 0.5), rect: CGRect(origin: .zero, size: source),
                            output: output, "\(edge): no-op at different zoom")
            }
        }
        try preview(WindowSizingPolicy.cropPreview(source: source, output: output, delta: CGPoint(x: 0.25, y: 0),
                    edge: .left, symmetric: false, zoom: 0.5), rect: CGRect(x: 1, y: 0, width: 799, height: 600),
                    output: CGSize(width: 399.5, height: 150), "Subpixel screen drag maps through zoom without rounding")

        let invalid: [CGSize] = [.zero, CGSize(width: -1, height: 1), CGSize(width: 0.5, height: 2),
            CGSize(width: 16_385, height: 1), CGSize(width: 8000, height: 4001),
            CGSize(width: 16_384, height: 16_384), CGSize(width: CGFloat.nan, height: 1),
            CGSize(width: 1, height: CGFloat.infinity), CGSize(width: -CGFloat.infinity, height: 1),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1)]
        for bad in invalid + invalid.map({ CGSize(width: $0.height, height: $0.width) }) {
            try expect(WindowSizingPolicy.fittedOutput(source: bad, available: screen) == nil, "Invalid fit source")
            try expect(WindowSizingPolicy.cornerOutput(initial: bad, delta: .zero, corner: .topLeft) == nil, "Invalid corner initial")
            try expect(!WindowSizingPolicy.actualEligible(source: bad, output: source, normalMode: true), "Invalid Actual source")
            try expect(!WindowSizingPolicy.actualEligible(source: source, output: bad, normalMode: true), "Invalid Actual output")
            try expect(WindowSizingPolicy.cropPreview(source: bad, output: output, delta: .zero,
                       edge: .left, symmetric: false, zoom: 1) == nil, "Invalid crop source")
            try expect(WindowSizingPolicy.cropPreview(source: source, output: bad, delta: .zero,
                       edge: .left, symmetric: false, zoom: 1) == nil, "Invalid crop output")
        }
        for value: CGFloat in [0, -1, 0.5, .nan, .infinity, -.infinity] {
            for bad in [CGSize(width: value, height: 900), CGSize(width: 1440, height: value)] {
                try expect(WindowSizingPolicy.availableCanvas(screen: bad, chrome: .zero) == nil, "Invalid screen")
                try expect(WindowSizingPolicy.fittedOutput(source: source, available: bad) == nil, "Invalid fit capacity")
            }
        }
        for value: CGFloat in [-1, .nan, .infinity, -.infinity] {
            for bad in [CGSize(width: value, height: 0), CGSize(width: 0, height: value)] {
                try expect(WindowSizingPolicy.availableCanvas(screen: screen, chrome: bad) == nil, "Invalid chrome")
            }
        }
        for value: CGFloat in [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            for delta in [CGPoint(x: value, y: 0), CGPoint(x: 0, y: value)] {
                for corner in CanvasCorner.allCases {
                    for proportional in [false, true] {
                        let result = WindowSizingPolicy.cornerOutput(initial: source, delta: delta, corner: corner,
                                     proportional: proportional)
                        if proportional && value.isFinite && delta.x == 0 {
                            try size(result, source, "Finite unbounded vertical delta is ignored in proportional mode")
                        } else {
                            try expect(result == nil, "Invalid or unbounded corner drag")
                        }
                    }
                }
                for edge in CanvasEdge.allCases {
                    for symmetric in [false, true] {
                        // Finite movement on the unrelated axis has no effect.
                        let unrelated = ((edge == .left || edge == .right) && delta.x == 0)
                            || ((edge == .top || edge == .bottom) && delta.y == 0)
                        let result = WindowSizingPolicy.cropPreview(source: source, output: output, delta: delta,
                                     edge: edge, symmetric: symmetric, zoom: 1)
                        try expect(value.isFinite && unrelated ? result != nil : result == nil, "Invalid or unbounded crop drag")
                    }
                }
            }
        }
        for zoom: CGFloat in [0, -1, .nan, .infinity, -.infinity, .leastNonzeroMagnitude] {
            try expect(WindowSizingPolicy.cropPreview(source: source, output: output, delta: CGPoint(x: 1, y: 1),
                       edge: .left, symmetric: false, zoom: zoom) == nil, "Invalid or underflowed zoom")
        }
        try expect(WindowSizingPolicy.cropPreview(source: CGSize(width: 1, height: 1), output: source,
                   delta: .zero, edge: .left, symmetric: false, zoom: .greatestFiniteMagnitude) == nil, "Overflowed effective zoom")
        for (corner, growth) in corners {
            for proportional in [false, true] {
                try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 8000, height: 4000),
                           delta: growth, corner: corner, proportional: proportional) == nil,
                           "\(corner): 32M expansion rejected")
                let xSign: CGFloat = growth.x < 0 ? -1 : 1
                let ySign: CGFloat = growth.y < 0 ? -1 : 1
                try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 16_384, height: 1),
                           delta: CGPoint(x: xSign, y: 0), corner: corner, proportional: proportional) == nil,
                           "\(corner): maximum dimension cannot grow")
                try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 1, height: 1),
                           delta: CGPoint(x: -xSign, y: -ySign), corner: corner, proportional: proportional) == nil,
                           "\(corner): one-pixel canvas cannot collapse")
            }
        }
        try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 16_384, height: 1),
                   delta: CGPoint(x: 1, y: 0), corner: .bottomRight, proportional: false) == nil, "Corner exceeds dimension limit")
        try expect(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: -800, y: 0),
                   corner: .bottomRight) == nil, "Corner cannot collapse or cross anchor")
        for edge in CanvasEdge.allCases {
            let horizontal = edge == .left || edge == .right
            let inward: CGFloat = edge == .left || edge == .top ? 1 : -1
            let delta = horizontal ? CGPoint(x: inward * 400, y: 0) : CGPoint(x: 0, y: inward * 150)
            for symmetric in [false, true] {
                try expect(WindowSizingPolicy.cropPreview(source: source, output: output, delta: delta,
                           edge: edge, symmetric: symmetric, zoom: 1) == nil, "\(edge): collapsed/crossed bounds rejected")
                let bigSource = CGSize(width: 8000, height: 4000)
                let outward = horizontal ? CGPoint(x: -inward, y: 0) : CGPoint(x: 0, y: -inward)
                try expect(WindowSizingPolicy.cropPreview(source: bigSource, output: bigSource, delta: outward,
                           edge: edge, symmetric: symmetric, zoom: 1) == nil, "\(edge): expanded source exceeds 32M")
                try expect(WindowSizingPolicy.cropPreview(source: source, output: bigSource, delta: outward,
                           edge: edge, symmetric: symmetric, zoom: 1) == nil, "\(edge): expanded output exceeds 32M")
                try preview(WindowSizingPolicy.cropPreview(source: bigSource, output: bigSource, delta: .zero,
                            edge: edge, symmetric: symmetric, zoom: 1), rect: CGRect(origin: .zero, size: bigSource),
                            output: bigSource, "\(edge): inclusive 32M crop boundary")
                try preview(WindowSizingPolicy.cropPreview(source: CGSize(width: 1, height: 1),
                            output: CGSize(width: 1, height: 1), delta: .zero, edge: edge, symmetric: symmetric, zoom: 1),
                            rect: CGRect(x: 0, y: 0, width: 1, height: 1), output: CGSize(width: 1, height: 1),
                            "\(edge): inclusive one-pixel crop boundary")
                let maxSize = horizontal ? CGSize(width: 16_384, height: 1) : CGSize(width: 1, height: 16_384)
                try expect(WindowSizingPolicy.cropPreview(source: maxSize, output: maxSize, delta: outward,
                           edge: edge, symmetric: symmetric, zoom: 1) == nil, "\(edge): expanded dimension exceeds 16384")
                let tinyOutput = CGSize(width: 1, height: 1)
                let smallInward = horizontal ? CGPoint(x: inward * 0.001, y: 0) : CGPoint(x: 0, y: inward * 0.001)
                try expect(WindowSizingPolicy.cropPreview(source: source, output: tinyOutput, delta: smallInward,
                           edge: edge, symmetric: symmetric, zoom: 1) == nil, "\(edge): output below one pixel rejected")
            }
        }
        // ActionCropResize rules (ADR 0001).
        let ids: [(CanvasCorner, Int, Int, Int)] = [(.topLeft, 0, -1, -1), (.topRight, 2, 1, -1),
                                                    (.bottomRight, 4, 1, 1), (.bottomLeft, 6, -1, 1)]
        for (corner, id, dirX, dirY) in ids {
            try expect(WindowSizingPolicy.cropID(corner: corner) == id, "ActionCropResize id for \(corner)")
            let dir = WindowSizingPolicy.cropDirection(id: id)
            try expect(dir?.x == dirX && dir?.y == dirY, "directionVector row \(id)")
            // dx grows the canvas by dir.x * delta.x (execute adds dScale to the frame width)
            try size(WindowSizingPolicy.cornerOutput(initial: source, delta: CGPoint(x: 10, y: 10), corner: corner,
                     proportional: false), CGSize(width: 800 + CGFloat(dirX) * 10, height: 600 + CGFloat(dirY) * 10),
                     "ActionCropResize \(corner) signs follow directionVector")
        }
        let edgeIDs: [(CanvasEdge, Int, Int, Int)] = [(.top, 1, 0, -1), (.right, 3, 1, 0),
                                                      (.bottom, 5, 0, 1), (.left, 7, -1, 0)]
        for (edge, id, dirX, dirY) in edgeIDs {
            try expect(WindowSizingPolicy.cropID(edge: edge) == id, "ActionCropResize id for \(edge)")
            let dir = WindowSizingPolicy.cropDirection(id: id)
            try expect(dir?.x == dirX && dir?.y == dirY, "directionVector row \(id)")
        }
        let centre = WindowSizingPolicy.cropDirection(id: 8)
        try expect(centre?.x == 0 && centre?.y == 0, "directionVector row 8 is the centre")
        let about = WindowSizingPolicy.cropDirection(id: -1)
        try expect(about?.x == 1 && about?.y == 1, "id -1 reads row 4")
        try expect(WindowSizingPolicy.cropDirection(id: 9) == nil && WindowSizingPolicy.cropDirection(id: -2) == nil,
                   "directionVector has exactly rows 0...8")
        // centered = modifierFlags >> 19 & 1 (OriginalCropView.mouseDragged)
        try expect(WindowSizingPolicy.isCenteredCrop(modifierFlags: 1 << 19), "Option (bit 19) centres the crop")
        for bit in [16, 17, 18, 20, 23] {
            try expect(!WindowSizingPolicy.isCenteredCrop(modifierFlags: 1 << UInt(bit)), "bit \(bit) does not centre")
        }
        try expect(WindowSizingPolicy.isCenteredCrop(modifierFlags: 0x1A0000 | 0x80000), "Option among other flags")
        // resizeProportionally
        try expect(WindowSizingPolicy.resizesProportionally(snapMode: 1, shiftHeld: true, frameMode: false, hasContent: false),
                   "snapMode 1 + Shift is proportional")
        try expect(!WindowSizingPolicy.resizesProportionally(snapMode: 1, shiftHeld: false, frameMode: false, hasContent: true),
                   "snapMode 1 without Shift is free")
        for mode in [0, 3] {
            try expect(WindowSizingPolicy.resizesProportionally(snapMode: mode, shiftHeld: false, frameMode: false, hasContent: true),
                       "snapMode \(mode) with content is proportional")
            try expect(!WindowSizingPolicy.resizesProportionally(snapMode: mode, shiftHeld: true, frameMode: false, hasContent: false),
                       "snapMode \(mode) empty is free")
        }
        try expect(!WindowSizingPolicy.resizesProportionally(snapMode: 2, shiftHeld: true, frameMode: false, hasContent: true),
                   "other snap modes are never proportional")
        try expect(WindowSizingPolicy.resizesProportionally(snapMode: 2, shiftHeld: false, frameMode: true, hasContent: false),
                   "frame mode forces proportional")
        // floor(x + 0.5) rounding and width-driven height
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 3, height: 2), delta: CGPoint(x: 1, y: 99),
                 corner: .bottomRight), CGSize(width: 4, height: 3), "ActionCropResize floor(4*2/3+0.5)=3, dy ignored")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 4, height: 1), delta: CGPoint(x: 2, y: 0),
                 corner: .bottomRight), CGSize(width: 6, height: 2), "ActionCropResize floor(1.5+0.5)=2 rounds half up")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 5, height: 2), delta: CGPoint(x: 1, y: 0),
                 corner: .bottomRight), CGSize(width: 6, height: 2), "ActionCropResize floor(2.4+0.5)=2")
        // minimum clamp: 1 on the shorter-ratio axis, floor(ratio + 0.5) on the other
        try size(WindowSizingPolicy.minimumProportionalCanvas(initial: CGSize(width: 400, height: 100)),
                 CGSize(width: 4, height: 1), "ActionCropResize wide minimum")
        try size(WindowSizingPolicy.minimumProportionalCanvas(initial: CGSize(width: 100, height: 250)),
                 CGSize(width: 1, height: 3), "ActionCropResize tall minimum floor(2.5+0.5)")
        try size(WindowSizingPolicy.minimumProportionalCanvas(initial: CGSize(width: 50, height: 50)),
                 CGSize(width: 1, height: 1), "ActionCropResize square minimum")
        try expect(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 400, height: 100), delta: CGPoint(x: -397, y: 0),
                   corner: .bottomRight) == nil, "ActionCropResize wide canvas below its minimum width 4")
        try size(WindowSizingPolicy.cornerOutput(initial: CGSize(width: 400, height: 100), delta: CGPoint(x: -396, y: 0),
                 corner: .bottomRight), CGSize(width: 4, height: 1), "ActionCropResize wide canvas at its minimum width")
        // OriginalBorderView
        try size(WindowSizingPolicy.maxViewSize(bounds: CGSize(width: 640, height: 480)),
                 CGSize(width: 632, height: 472), "OriginalBorderView.maxViewSize is bounds - 8")
        try expect(WindowSizingPolicy.cropViewsExist(inActualMode: false) && !WindowSizingPolicy.cropViewsExist(inActualMode: true),
                   "OriginalBorderView.awakeFromNib builds crop views only outside actual mode")
        print("WindowSizingTests: \(checks) checks passed (pure geometry; no desktop UI)")
    }
}
#endif
