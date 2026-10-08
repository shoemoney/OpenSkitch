// Pure tests only: no windows, application launch, desktop input, or permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D RESIZE_PANEL_TESTS Sources/ResizePresets.swift Sources/ResizePanel.swift tests/ResizePanelTests.swift \
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
        var previews: [ResizePanelSubmission] = []
        var finishes: [Bool] = []
        let previewSession = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { previews.append($0) }, onFinish: { finishes.append($0) })
        previewSession.state.edit(.width, text: "400")
        try expect(try previewSession.preview(), "Apply previews without closing")
        try expect(!previewSession.isFinished && previews.count == 1 && finishes.isEmpty,
                   "Preview leaves session open and uncommitted")
        try expect(try previewSession.preview() && previews.count == 1, "Duplicate Apply does not repeat crop")
        previewSession.state.edit(.width, text: "0")
        try rejects { _ = try previewSession.preview() }
        try expect(previews.count == 1 && !previewSession.isFinished, "Invalid preview preserves previous preview")
        previewSession.state.edit(.width, text: "200")
        var sheetEnded = false
        try expect(try previewSession.apply { sheetEnded = true }, "OK previews last edit then commits")
        try expect(sheetEnded && previews.map(\.size) == [CGSize(width: 400, height: 300), CGSize(width: 200, height: 150)]
                   && finishes == [false], "OK delivers current dimensions and one commit")
        previewSession.cancel()
        try expect(try !previewSession.preview() && finishes == [false], "Sheet cleanup cannot cancel accepted changes")
        let cancelledPreview = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { previews.append($0) }, onFinish: { finishes.append($0) })
        cancelledPreview.state.edit(.width, text: "320")
        _ = try cancelledPreview.preview()
        cancelledPreview.cancel(); cancelledPreview.cancel()
        try expect(finishes == [false, true] && cancelledPreview.isFinished, "Cancel rolls back exactly once after Apply")
        struct PreviewFailure: Error {}
        let failedPreview = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { _ in throw PreviewFailure() }, onFinish: { finishes.append($0) })
        do { _ = try failedPreview.apply(); throw Failure(description: "Failed shell preview committed") }
        catch is PreviewFailure {}
        try expect(!failedPreview.isFinished && failedPreview.lastPreview == nil && finishes == [false, true],
                   "Failed shell crop leaves sheet open and does not commit")
        failedPreview.cancel()
        var nestedPreview: ResizePanelSession!
        nestedPreview = ResizePanelSession(size: CGSize(width: 100, height: 50), onPreview: { _ in
            precondition((try? nestedPreview.preview()) == false)
            precondition((try? nestedPreview.apply()) == false)
        }, onFinish: { _ in })
        try expect(try nestedPreview.preview(), "Reentrant previews and commits are suppressed")
        nestedPreview.cancel()
        var limitState = ResizePanelState(size: CGSize(width: 800, height: 600))
        limitState.setMode(.limit); limitState.limitText = "400"
        try expect(try limitState.submission().size == CGSize(width: 400, height: 300), "Limit longest side shrinks proportionally")
        limitState.limitMode = .height
        try expect(try limitState.submission().size == CGSize(width: 533, height: 400), "Height limit uses current output aspect")
        limitState.limitMode = .width; limitState.limitText = "1600"
        try expect(try limitState.submission().size == CGSize(width: 1600, height: 1200), "Limit allows enlargement")
        limitState.limitText = "0"
        try rejects { _ = try limitState.submission() }
        limitState.limitText = "16384"
        try rejects { _ = try limitState.submission() }
        let unlocked = ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero, constrainProportions: false)
        let expanded = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90), request: unlocked)
        let expandedRect = expanded.rect ?? .zero
        try expect(expanded.output == unlocked.size && abs(expandedRect.minX + 570) < 0.00001 && abs(expandedRect.minY) < 0.00001
                   && abs(expandedRect.width - 1440) < 0.00001 && abs(expandedRect.height - 180) < 0.00001,
                   "Unlocked Scale fits proportionally then expands centered source; it never stretches")
        let constrained = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90),
            request: ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero))
        try expect(constrained.rect == nil && constrained.output == CGSize(width: 167, height: 100), "Constrained Scale fits inside both limits")
        let anchored = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90),
            request: ResizePanelSubmission(size: CGSize(width: 80, height: 60), isCrop: true, anchor: CGPoint(x: 1, y: 1)))
        try expect(anchored.rect == CGRect(x: 140, y: 60, width: 160, height: 120) && anchored.output == CGSize(width: 80, height: 60),
                   "Crop anchor uses initial source/output relationship")
        for preset in ResizePreset.builtins {
            var presetState = ResizePanelState(size: CGSize(width: 800, height: 600))
            presetState.selectPreset(preset)
            let selected = try presetState.submission()
            try expect(selected.size == preset.size && !selected.isCrop && selected.constrainProportions == preset.proportions,
                       "Built-in target dimensions/constraint flags survive UI selection: \(preset.name)")
        }
        var customState = ResizePanelState(size: CGSize(width: 800, height: 600))
        let custom = ResizePreset(id: "custom-geometry", name: "Custom", width: 640, height: 400, mode: .crop,
                                  format: 19, anchor: 8, proportions: false, limitSize: 1000, limitMode: .height)
        customState.selectPreset(custom)
        try expect(try customState.preset(id: custom.id, name: custom.name, format: custom.format) == custom,
                   "UI preserves all custom preset fields and opaque format metadata")
        print("ResizePanelTests: \(checks) checks passed (pure state; no desktop input)")
    }
}
#endif
