// Pure options, preview text, and lazy controller tests. Never access .view:
// no AppKit controls/windows, save panel, desktop input, permissions, or encoding.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D EXPORT_ACCESSORY_TESTS Sources/ExportAccessory.swift tests/ExportAccessoryTests.swift \
//   -o /tmp/opensnap-export-accessory-tests
// rtk proxy /tmp/opensnap-export-accessory-tests
#if EXPORT_ACCESSORY_TESTS
import Foundation
import CoreGraphics

@main
@MainActor
private enum ExportAccessoryTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    static func main() throws {
        var options = ExportAccessoryOptions()
        try expect(options.format == "png" && !options.originalSize && options.jpegQuality == 0.7,
                   "File-export defaults")
        try expect(!options.jpegControlsEnabled, "PNG disables JPEG controls")
        try expect(options.qualityLabel == "JPEG quality: 70%", "Readable default quality label")
        let formats = ["png", "jpeg", "tiff", "gif", "bmp", "pdf", "svg", "opensnap"]
        let titles = ["PNG", "JPEG", "TIFF", "GIF", "BMP", "PDF", "SVG", "OpenSnap"]
        try expect(ExportAccessoryFormat.allCases.map(\.rawValue) == formats, "All eight formats in order")
        try expect(ExportAccessoryFormat.allCases.map(\.title) == titles, "Format popup labels")
        for format in formats {
            _ = options.setFormat(format.uppercased())
            try expect(options.format == format, "Canonical format \(format)")
            try expect(options.jpegControlsEnabled == (format == "jpeg"), "JPEG-only controls for \(format)")
            try expect(!options.setFormat(format), "Same selection is unchanged")
        }
        try expect(ExportAccessoryFormat.validated(" JPG\n") == .jpeg, "JPEG alias")
        try expect(ExportAccessoryFormat.validated("tif") == .tiff, "TIFF alias")
        for invalid in ["", "webp", "../jpeg", ".png", "image/png", "png\u{0}"] {
            try expect(ExportAccessoryFormat.validated(invalid) == .png, "Unsupported format falls back safely")
        }
        for nonfinite in [Double.nan, .infinity, -.infinity] {
            try expect(ExportAccessoryOptions.validatedQuality(nonfinite) == 0.7, "Nonfinite quality default")
        }
        for low in [-Double.greatestFiniteMagnitude, -1, 0, 0.01, 0.09] {
            try expect(ExportAccessoryOptions.validatedQuality(low) == 0.1, "Lower quality bound")
        }
        for high in [1.01, 2, Double.greatestFiniteMagnitude] {
            try expect(ExportAccessoryOptions.validatedQuality(high) == 1, "Upper quality bound")
        }
        try expect(ExportAccessoryOptions.validatedQuality(0.74) == 0.7, "Snap down to tick")
        try expect(ExportAccessoryOptions.validatedQuality(0.76) == 0.8, "Snap up to tick")
        try expect(ExportAccessoryOptions.validatedQuality(0.75) == 0.8, "Midpoint rounds up")
        try expect(ExportAccessoryOptions.jpegTickCount == 10, "Exactly ten slider ticks")
        for tick in 1...10 {
            let value = Double(tick) / 10
            _ = options.setJPEGQuality(value)
            try expect(options.jpegQuality == value, "Tick \(tick) value")
            try expect(options.qualityLabel == "JPEG quality: \(tick * 10)%", "Tick \(tick) label")
        }
        for index in -100...1100 {
            let value = ExportAccessoryOptions.validatedQuality(Double(index) / 1000)
            guard value.isFinite, value >= 0.1, value <= 1,
                  abs(value * 10 - (value * 10).rounded()) < 1e-12 else {
                throw Failure(description: "Invalid snapped quality at \(index)")
            }
        }
        checks += 1
        _ = options.setFormat("jpeg")
        _ = options.setJPEGQuality(0.4)
        try expect(options.setOriginalSize(true), "Original-size selection changes")
        try expect(!options.setOriginalSize(true), "Original-size selection is stable")
        _ = options.setFormat("svg")
        try expect(options.jpegQuality == 0.4 && options.originalSize, "Format switch retains options")
        _ = options.setFormat("jpeg")
        try expect(options.jpegQuality == 0.4 && options.jpegControlsEnabled, "Return to JPEG retains quality")

        let empty = ExportAccessoryPreview()
        try expect(empty.dimensionsLabel == "Dimensions: Not available", "No invented dimensions")
        try expect(empty.byteCountLabel == "Encoded size: Not available", "No estimated bytes")
        let actual = ExportAccessoryPreview(byteCount: 12_345, size: CGSize(width: 800, height: 600))
        try expect(actual.dimensionsLabel == "Dimensions: 800 × 600 pixels", "Whole pixel preview")
        try expect(actual.byteCount == 12_345 && actual.byteCountLabel != empty.byteCountLabel,
                   "Use actual encoded byte count")
        let noBytes = ExportAccessoryPreview(byteCount: nil, size: CGSize(width: 800, height: 600))
        try expect(noBytes.byteCount == nil && noBytes.size != nil, "Dimensions without encoded bytes")
        try expect(ExportAccessoryPreview(byteCount: -1).byteCount == nil, "Reject negative bytes")
        try expect(ExportAccessoryPreview(byteCount: 0).byteCount == 0, "Zero bytes is explicit")
        let large = ExportAccessoryPreview(byteCount: Int.max, size: CGSize(width: 1, height: 1))
        try expect(!large.byteCountLabel.isEmpty && large.byteCount == Int.max, "Int.max bytes do not overflow")
        for invalid in [CGSize.zero, CGSize(width: CGFloat.nan, height: 1),
                        CGSize(width: 1, height: CGFloat.infinity), CGSize(width: -1, height: 1),
                        CGSize(width: 1.5, height: 2), CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1),
                        CGSize(width: CGFloat(Int.max), height: 1)] {
            let preview = ExportAccessoryPreview(byteCount: 42, size: invalid)
            try expect(preview.size == nil && preview.dimensionsLabel == empty.dimensionsLabel,
                       "Reject invalid dimensions without trapping integer conversion")
            try expect(preview.byteCount == 42, "Caller bytes remain independent of dimension validity")
        }

        var callbacks = 0
        let accessory = ExportAccessory { callbacks += 1 }
        try expect(callbacks == 0 && accessory.format == "png" && accessory.jpegQuality == 0.7,
                   "Initializing lazy controller does not notify or create UI")
        accessory.format = "JPEG"
        try expect(callbacks == 1 && accessory.format == "jpeg", "Format setter callback")
        accessory.format = "jpg"
        try expect(callbacks == 1, "Equivalent JPEG alias does not double-notify")
        accessory.jpegQuality = 0.4
        try expect(callbacks == 2 && accessory.jpegQuality == 0.4, "Quality setter callback")
        accessory.jpegQuality = 0.44
        try expect(callbacks == 2, "Equivalent snapped quality does not double-notify")
        accessory.originalSize = true
        try expect(callbacks == 3 && accessory.originalSize, "Checkbox setter callback")
        accessory.originalSize = true
        try expect(callbacks == 3, "Same checkbox value does not notify")
        accessory.updateByteCount(12_345, size: CGSize(width: 800, height: 600))
        try expect(callbacks == 3 && accessory.preview == actual, "Preview refresh does not recurse into callback")
        try expect(accessory.format == "jpeg" && accessory.jpegQuality == 0.4 && accessory.originalSize,
                   "Preview update preserves every selection")
        accessory.format = "pdf"
        try expect(callbacks == 4 && accessory.preview == empty, "Option change invalidates stale preview")
        accessory.updateByteCount(nil, size: CGSize(width: 1600, height: 1200))
        try expect(accessory.format == "pdf" && accessory.preview.byteCount == nil, "Missing preview keeps format")
        accessory.format = "jpeg"
        try expect(callbacks == 5 && accessory.jpegQuality == 0.4, "JPEG quality persists after non-JPEG")
        accessory.jpegQuality = .nan
        try expect(callbacks == 6 && accessory.jpegQuality == 0.7, "Controller validates nonfinite quality")
        let restored = ExportAccessory(format: "TIFF", originalSize: true, jpegQuality: 0.61)
        try expect(restored.format == "tiff" && restored.originalSize && restored.jpegQuality == 0.6,
                   "Caller-restored selection and snapped quality")
        try expect(ExportAccessoryOptions().jpegQuality == 0.7, "Restoring 60% does not change file default")

        let fixed = ExportAccessory(format: "jpeg", jpegQuality: 0.4)
        fixed.fixedJPEGQuality = 0.75
        try expect(fixed.effectiveJPEGQuality == 0.75, "A fixed quality overrides the stored one")
        fixed.jpegQuality = 0.3
        try expect(fixed.effectiveJPEGQuality == 0.75 && fixed.jpegQuality == 0.3, "A fixed quality survives later quality changes")

        var live: ExportAccessory!
        var liveCallbacks = 0
        live = ExportAccessory(onChange: {
            liveCallbacks += 1
            live.updateByteCount(500, size: CGSize(width: 100, height: 50))
            live.format = live.format // Idempotent callback reentry.
        })
        live.format = "gif"
        try expect(liveCallbacks == 1 && live.preview.byteCount == 500 && live.format == "gif",
                   "Synchronous fresh preview survives callback reentry")
        var assignedCallbacks = 0
        let assigned = ExportAccessory(format: "jpeg", originalSize: true, jpegQuality: 0.5,
                                       onChange: { assignedCallbacks += 100 })
        assigned.onChange = { assignedCallbacks += 1 }
        try expect(assignedCallbacks == 0, "Assigning callback does not notify")
        assigned.format = "png"
        assigned.originalSize = false
        assigned.jpegQuality = 0.8
        try expect(assignedCallbacks == 3, "Assigned callback handles all three option changes")
        assigned.updateByteCount(500, size: CGSize(width: 100, height: 50))
        try expect(assignedCallbacks == 3, "Preview update does not notify assigned callback")
        print("ExportAccessoryTests: \(checks) checks passed (no UI creation or desktop input)")
    }
}
#endif
