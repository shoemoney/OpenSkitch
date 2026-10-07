// Pure tests only: no windows, application launch, desktop input, or permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D RESIZE_PANEL_TESTS Sources/ResizePanel.swift tests/ResizePanelTests.swift \
//   -o /tmp/skitch-resize-panel-tests
// rtk proxy /tmp/skitch-resize-panel-tests
#if RESIZE_PANEL_TESTS
import Foundation
import CoreGraphics

@main
@MainActor
private enum ResizePanelTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static func rejects(_ body: () throws -> Void) throws {
        do { try body() }
        catch is ResizePanelValidation.Failure { checks += 1; return }
        throw Failure(description: "Invalid dimension request was accepted")
    }

    static func main() throws {
        for text in ["", " ", "0", "-1", "+10", "1.5", "10px", "1e2", "1,000", "nan", "inf",
                     "Infinity", "16385", "9999999999999999999999999", "١٢", "１２", "12 3"] {
            try rejects { _ = try ResizePanelValidation.dimension(from: text) }
        }
        try expect(try ResizePanelValidation.dimension(from: " 00120\n") == 120, "Trimmed integer")
        try expect(try ResizePanelValidation.dimension(from: "16384") == 16384, "Maximum dimension")
        for value: CGFloat in [0, -1, .nan, .infinity, -.infinity, 1.25, 16_385,
                               .greatestFiniteMagnitude] {
            try rejects { _ = try ResizePanelValidation.validate(CGSize(width: value, height: 1)) }
            try rejects { _ = try ResizePanelValidation.validate(CGSize(width: 1, height: value)) }
            _ = ResizePanelValidation.text(for: value) // No trapping Int conversion.
        }
        try expect(try ResizePanelValidation.validate(CGSize(width: 8000, height: 4000))
                   == CGSize(width: 8000, height: 4000), "Inclusive 32M pixel boundary")
        try rejects { _ = try ResizePanelValidation.size(width: "8000", height: "4001") }
        try rejects { _ = try ResizePanelValidation.size(width: "16384", height: "16384") }
        try expect(try ResizePanelValidation.size(width: "1", height: "16384")
                   == CGSize(width: 1, height: 16384), "Extreme legal aspect ratio")

        var state = ResizePanelState(size: CGSize(width: 800, height: 600))
        try expect(state.mode == .resize && state.preserveRatio && state.locksProportions,
                   "Original default: resize with proportions locked")
        try expect(state.anchor == .center, "Original default: centered anchor")
        state.edit(.width, text: "400")
        try expect(try state.submission().size == CGSize(width: 400, height: 300), "Width drives ratio")
        state.edit(.height, text: "150")
        try expect(try state.submission().size == CGSize(width: 200, height: 150), "Height drives ratio")
        state.edit(.width, text: "bad")
        try expect(state.widthText == "bad" && state.heightText == "150", "Retain invalid input")
        try rejects { _ = try state.submission() }
        state.edit(.width, text: "400")
        state.setPreserveRatio(false)
        state.edit(.height, text: "120")
        try expect(try state.submission().size == CGSize(width: 400, height: 120), "Unlocked dimensions")
        state.setPreserveRatio(true)
        try expect(try state.submission().size == CGSize(width: 160, height: 120), "Relock uses last edit")

        state.setMode(.crop)
        try expect(state.preserveRatio && !state.locksProportions, "Crop suspends resize ratio preference")
        state.edit(.width, text: "320")
        state.edit(.height, text: "90")
        state.anchor = .bottomRight
        try expect(try state.submission() == ResizePanelSubmission(size: CGSize(width: 320, height: 90),
                   isCrop: true, anchor: CGPoint(x: 1, y: 1)), "Independent crop dimensions and payload")
        state.setMode(.resize)
        try expect(state.locksProportions && state.anchor == .bottomRight, "Mode preferences persist")
        try expect(try state.submission().size == CGSize(width: 120, height: 90), "Return to original ratio")
        try expect(try !state.submission().isCrop, "Resize callback flag is false")
        state.setPreserveRatio(false)
        state.setMode(.crop)
        state.edit(.width, text: "250")
        state.setMode(.resize)
        try expect(!state.preserveRatio && state.widthText == "250" && state.heightText == "90",
                   "Unlocked preference survives round trip")

        var rounding = ResizePanelState(size: CGSize(width: 7, height: 3))
        rounding.edit(.width, text: "10")
        try expect(rounding.heightText == "4", "Nearest whole pixel")
        rounding.edit(.height, text: "3")
        try expect(rounding.widthText == "7", "Original ratio prevents rounding drift")
        var extreme = ResizePanelState(size: CGSize(width: 16384, height: 1))
        extreme.edit(.width, text: "1")
        try expect(extreme.heightText == "1", "Subpixel companion occupies one pixel")
        extreme.edit(.height, text: "2")
        try rejects { _ = try extreme.submission() }
        var area = ResizePanelState(size: CGSize(width: 800, height: 400))
        area.edit(.width, text: "8002")
        try rejects { _ = try area.submission() }
        for initial in [CGSize.zero, CGSize(width: CGFloat.nan, height: 12),
                        CGSize(width: 12.5, height: 10), CGSize(width: 16384, height: 16384)] {
            var invalid = ResizePanelState(size: initial)
            invalid.setPreserveRatio(true)
            try expect(!invalid.locksProportions, "Invalid original cannot produce a ratio")
            try rejects { _ = try invalid.submission() }
            invalid.edit(.width, text: "800")
            invalid.edit(.height, text: "600")
            try expect(try invalid.submission().size == CGSize(width: 800, height: 600), "Recover invalid original")
        }

        let titles = ["Top Left", "Top Center", "Top Right", "Middle Left", "Center", "Middle Right",
                      "Bottom Left", "Bottom Center", "Bottom Right"]
        let points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0),
                                CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0.5),
                                CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 1)]
        try expect(ResizePanelAnchor.allCases.count == 9, "Nine crop anchors")
        for (index, anchor) in ResizePanelAnchor.allCases.enumerated() {
            try expect(anchor.title == titles[index] && anchor.point == points[index], "Anchor \(titles[index])")
        }

        var delivered: [ResizePanelSubmission] = []
        var endedSheet = false
        let session = ResizePanelSession(size: CGSize(width: 800, height: 600)) { size, crop, anchor in
            precondition(endedSheet, "Sheet must end before callback")
            delivered.append(ResizePanelSubmission(size: size, isCrop: crop, anchor: anchor))
        }
        session.state.edit(.width, text: "NaN")
        try rejects { _ = try session.apply { endedSheet = true } }
        try expect(!session.isFinished && !endedSheet && delivered.isEmpty, "Invalid input keeps sheet and callback")
        session.state.setMode(.crop)
        session.state.edit(.width, text: "320")
        session.state.edit(.height, text: "240")
        session.state.anchor = .topLeft
        try expect(try session.apply { endedSheet = true }, "Valid apply")
        try expect(delivered == [ResizePanelSubmission(size: CGSize(width: 320, height: 240),
                   isCrop: true, anchor: .zero)], "Exact callback arguments")
        try expect(try !session.apply(), "Second apply rejected")
        session.cancel()
        try expect(delivered.count == 1, "Completion is exactly once")

        let cancelled = ResizePanelSession(size: CGSize(width: 800, height: 600)) { _, _, _ in
            delivered.append(ResizePanelSubmission(size: .zero, isCrop: false, anchor: .zero))
        }
        cancelled.cancel()
        cancelled.cancel()
        try expect(try !cancelled.apply(), "Cancel prevents later apply")
        try expect(delivered.count == 1, "Cancel never calls callback")
        var reentrant: ResizePanelSession!
        reentrant = ResizePanelSession(size: CGSize(width: 100, height: 50)) { _, crop, _ in
            precondition(!crop)
            precondition((try? reentrant.apply()) == false, "Reentrant callback cannot apply twice")
        }
        try expect(try reentrant.apply(), "Reentrant delivery guarded")
        print("ResizePanelTests: \(checks) checks passed (pure state; no desktop input)")
    }
}
#endif
