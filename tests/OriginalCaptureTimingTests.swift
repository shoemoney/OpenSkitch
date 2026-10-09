// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -D ORIGINAL_CAPTURE_TIMING_TESTS Sources/OriginalCaptureTiming.swift \
//   tests/OriginalCaptureTimingTests.swift -o /tmp/opensnap-original-capture-timing-tests
// rtk proxy /tmp/opensnap-original-capture-timing-tests
#if ORIGINAL_CAPTURE_TIMING_TESTS
import AppKit

@main
@MainActor
enum OriginalCaptureTimingTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() {
        delayPolicy()
        sixSecondFixture()
        threeSecondFixture()
        boundaryDelays()
        print("OriginalCaptureTimingTests: \(checks) checks passed")
    }

    private static func delayPolicy() {
        expect(OriginalCaptureTiming.originalDelay == 6, "Original screen delay")
        expect(OriginalCaptureTiming.timerInterval == 0.1, "Original repeating timer interval")
        for flags: NSEvent.ModifierFlags in [[], .option, .command, [.control, .capsLock]] {
            expect(OriginalCaptureTiming.manualDelay(flags: flags) == 0, "Only Shift requests timed screen capture")
            expect(OriginalCaptureTiming.selectedDelay(flags: flags, explicitDelay: 0) == 0, "Untimed selection stays immediate")
        }
        for flags: NSEvent.ModifierFlags in [.shift, [.shift, .option, .command, .control]] {
            expect(OriginalCaptureTiming.manualDelay(flags: flags) == 6, "Shift times fullscreen/frame")
            expect(OriginalCaptureTiming.selectedDelay(flags: flags, explicitDelay: 0) == 6, "Shift at selection completion times crosshair")
            expect(OriginalCaptureTiming.selectedDelay(flags: flags, explicitDelay: 2.5) == 2.5, "Explicit selection delay takes precedence")
        }
        expect(OriginalCaptureTiming.selectedDelay(flags: .shift, explicitDelay: -1) == -1, "Invalid delay remains rejectable")
        expect(OriginalCaptureTiming.selectedDelay(flags: .shift, explicitDelay: .nan).isNaN, "NaN remains rejectable")
    }

    private static func sixSecondFixture() {
        var countdown = OriginalCaptureTiming(delay: 6)!
        expect(countdown.total.bitPattern == 0x40c00000, "Original delay argument bits")
        var cues: [Int] = []
        var invisible: [Int] = []
        var frame: OriginalCaptureTiming.Frame!
        for tick in 1...61 {
            frame = countdown.tick()
            if frame.playCue { cues.append(tick) }
            if frame.alpha == 0 { invisible.append(tick) }
            expect(frame.alpha.bitPattern == (invisible.last == tick ? 0 : 0x3f800000), "Alpha uses original binary lookup values")
            expect(frame.imageNumber == (tick <= 20 ? 3 : tick <= 40 ? 2 : 1), "Six seconds has three two-second image segments")
            expect(frame.finished == (tick == 61), "Float32 countdown expires strictly below zero")
            if tick == 1 { expect(countdown.remaining.bitPattern == 0x40bccccd, "First exact Float32 decrement") }
            if tick == 21 { expect(countdown.remaining.bitPattern == 0x407999a2, "Second segment residual bits") }
            if tick == 41 { expect(countdown.remaining.bitPattern == 0x3ff33353, "Third segment residual bits") }
            if tick == 60 { expect(countdown.remaining.bitPattern == 0x36690000, "Positive residual prevents expiry at tick sixty") }
        }
        expect(cues == [1, 21, 41], "Original cue transition ticks")
        expect(invisible == [1] + Array(17...21) + Array(37...41) + Array(57...61), "Blink uses the old remaining value, including transition ticks")
        expect(countdown.remaining.bitPattern == 0xbdcccafb, "Exact final residual")
        let after = countdown.tick()
        expect(after.finished && !after.playCue && after.imageNumber == frame.imageNumber && after.alpha == frame.alpha,
               "Finished state is stable and cannot replay cues")
        expect(countdown.remaining.bitPattern == 0xbdcccafb, "Extra tick cannot mutate a finished countdown")
    }

    private static func threeSecondFixture() {
        var countdown = OriginalCaptureTiming(delay: 3)!
        var cues: [Int] = [], invisible: [Int] = []
        for tick in 1...31 {
            let frame = countdown.tick()
            if frame.playCue { cues.append(tick) }
            if frame.alpha == 0 { invisible.append(tick) }
            expect(frame.imageNumber == (tick <= 10 ? 3 : tick <= 20 ? 2 : 1), "Three-second image segment boundaries")
            expect(frame.finished == (tick == 31), "Three-second Float32 residual expires on tick thirty-one")
        }
        expect(cues == [1, 11, 21], "Three-second cue boundaries")
        expect(invisible == [1] + Array(7...11) + Array(17...21) + Array(27...31), "Three-second blink threshold remains half a second")
        expect(countdown.remaining.bitPattern == 0xbdcccc7b, "Three-second final residual bits")
    }

    private static func boundaryDelays() {
        for delay in [-1.0, Double.nan, .infinity, -.infinity, 3600.0001] {
            expect(OriginalCaptureTiming(delay: delay) == nil, "Invalid or out-of-bounds delay rejected")
        }
        for delay in [0.0, -0.0, Double.leastNonzeroMagnitude] {
            var countdown = OriginalCaptureTiming(delay: delay)!
            let frame = countdown.tick()
            expect(frame.finished && !frame.playCue && frame.alpha == 0 && countdown.remaining == 0,
                   "Immediate/underflowed delay avoids division by zero and cues")
        }
        for delay in [Double(Float32.leastNonzeroMagnitude), 0.001, 0.1, 0.2, 2.5, 3600] {
            var countdown = OriginalCaptureTiming(delay: delay)!
            var ticks = 0
            while ticks < 36_100 {
                ticks += 1
                let frame = countdown.tick()
                expect((1...3).contains(frame.imageNumber) && (frame.alpha == 0 || frame.alpha == 1), "Arbitrary valid delay yields safe original frames")
                if frame.finished { break }
            }
            expect(countdown.remaining < 0 && ticks < 36_100, "Every positive bounded delay terminates without an Int overflow trap")
        }
        // At 3.1 seconds the initial Float32 quotient rounds below three,
        // so the original emits no cue and leaves the initial image unchanged.
        var fractional = OriginalCaptureTiming(delay: 3.1)!
        expect(!fractional.tick().playCue, "Preserve original initial-cue equality quirk for nonstandard delay")
        var tenth = OriginalCaptureTiming(delay: 0.1)!
        expect(!tenth.tick().finished && tenth.remaining == 0, "Exact zero does not finish")
        expect(tenth.tick().finished, "Next tick crossing below zero finishes")
    }
}
#endif
