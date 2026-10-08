import AppKit

/// Pure timing policy and Float32 countdown recovered from the original i386
/// snapTimer: (0x23d28; analysis/decompiled.c:23009). No timer or UI ownership.
struct OriginalCaptureTiming: Sendable {
    static let originalDelay: Double = 6
    static let timerInterval: Double = 0.1

    static func manualDelay(flags: NSEvent.ModifierFlags) -> Double {
        flags.contains(.shift) ? originalDelay : 0
    }

    /// Explicit delay precedence is caller policy; the original selected snap
    /// used the latched Shift flag and six seconds. Invalid values are preserved
    /// for the coordinator/initializer to reject, rather than silently repaired.
    static func selectedDelay(flags: NSEvent.ModifierFlags, explicitDelay: Double) -> Double {
        explicitDelay == 0 ? manualDelay(flags: flags) : explicitDelay
    }

    struct Frame: Equatable, Sendable {
        let imageNumber: Int
        let alpha: Float32
        let playCue: Bool
        let finished: Bool
    }

    private(set) var remaining: Float32
    let total: Float32
    private var imageNumber = 3
    private var alpha: Float32 = 0
    private var finished: Bool

    // Original Mach-O virtual addresses, decoded through its LC_SEGMENT map.
    private static let decrement = Float32(bitPattern: 0xbdcccccd) // 0x260454
    private static let segments = Float32(bitPattern: 0x40400000) // 0x26045c
    private static let blinkThreshold = Float32(bitPattern: 0x3f000000) // 0x260444
    private static let hiddenAlpha = Float32(bitPattern: 0x00000000) // 0x2606e8
    private static let shownAlpha = Float32(bitPattern: 0x3f800000) // 0x2606ec

    init?(delay: Double) {
        guard delay.isFinite, delay >= 0, delay <= 3_600 else { return nil }
        total = Float32(delay)
        remaining = total
        // Zero (including positive Double values that round to Float32 zero)
        // means immediate capture. The original never started a zero timer.
        finished = total == 0
    }

    mutating func tick() -> Frame {
        guard !finished else { return frame(playCue: false) }
        let oldRemaining = remaining
        let oldScaled = oldRemaining * Self.segments
        let oldRatio = oldScaled / total
        let oldStage = Self.truncateLikeI386(oldRatio)
        let segmentFloor = oldRatio.rounded(.down)
        let segmentProduct = segmentFloor * total
        let segmentBoundary = segmentProduct / Self.segments
        let phase = oldRemaining - segmentBoundary
        alpha = phase >= Self.blinkThreshold ? Self.shownAlpha : Self.hiddenAlpha

        remaining = oldRemaining + Self.decrement
        let newScaled = remaining * Self.segments
        let newRatio = newScaled / total
        let newStage = Self.truncateLikeI386(newRatio)
        let playCue = newStage != oldStage || Float32(oldStage) == total
        if playCue {
            switch newStage {
            case 1: imageNumber = 2
            case 2: imageNumber = 3
            default: imageNumber = 1
            }
        }
        finished = remaining < 0
        return frame(playCue: playCue)
    }

    private func frame(playCue: Bool) -> Frame {
        Frame(imageNumber: imageNumber, alpha: alpha, playCue: playCue, finished: finished)
    }

    // cvttss2si returns the integer-indefinite value for NaN/overflow. Tiny valid
    // delays can overflow the post-decrement quotient; Swift Int must not trap.
    private static func truncateLikeI386(_ value: Float32) -> Int {
        guard value.isFinite, value >= -2_147_483_648, value < 2_147_483_648 else {
            return Int(Int32.min)
        }
        return Int(value)
    }
}
