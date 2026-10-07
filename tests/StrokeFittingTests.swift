#if STROKE_FITTING_TESTS
import Foundation
import CoreGraphics

// Standalone: swiftc -swift-version 5 -warnings-as-errors -D STROKE_FITTING_TESTS
// Sources/LegacySkitch.swift Sources/StrokeFitting.swift tests/StrokeFittingTests.swift
// No Canvas, application launch, or original runtime is used by these tests.
@main
struct StrokeFittingTests {
    struct Failure: Error, CustomStringConvertible { let description: String; init(_ text: String) { description = text } }
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(message) }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-8) -> Bool { abs(a-b) <= tolerance }
    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-8) -> Bool {
        near(a.x,b.x,tolerance) && near(a.y,b.y,tolerance)
    }
    static func sample(_ x: CGFloat, _ y: CGFloat, _ pressure: CGFloat = 1) -> StrokeSample {
        StrokeSample(point: CGPoint(x:x,y:y),pressure:pressure)
    }
    static func rotated(_ point: CGPoint, _ angle: CGFloat) -> CGPoint {
        CGPoint(x:point.x*cos(angle)-point.y*sin(angle),y:point.x*sin(angle)+point.y*cos(angle))
    }
    static func outline(_ samples: [StrokeSample], size: CGFloat = 12, nib: StrokeNib = .pencil) throws -> CGPath {
        let commands = StrokeFitter.outline(samples:samples,size:size,nib:nib)
        try assertOutline(commands)
        return try SVGPathParser.makeCGPath(commands)
    }
    static func assertOutline(_ commands: [SVGPathCommand]) throws {
        try expect(commands.count >= 4 && commands.last == .close, "Missing closed cubic outline")
        try expect(commands.allSatisfy(\.isFinite), "Nonfinite command")
        guard case .move(let first) = commands[0], case .cubic(_,_,let end) = commands[commands.count-2] else {
            throw Failure("Expected M, C..., close")
        }
        try expect(near(first,end), "Last cubic fails to close exactly")
        for command in commands.dropFirst().dropLast() {
            guard case .cubic = command else { throw Failure("Noncubic segment") }
        }
    }
    static func verticalWidth(_ path: CGPath, x: CGFloat, y: CGFloat = 100) throws -> CGFloat {
        try expect(path.contains(CGPoint(x:x,y:y)), "Cross section excludes stroke center x=\(x)")
        func boundary(_ sign: CGFloat) -> CGFloat {
            var inside: CGFloat = 0, outside: CGFloat = 100
            for _ in 0..<40 {
                let middle = (inside+outside)/2
                if path.contains(CGPoint(x:x,y:y+sign*middle)) { inside = middle } else { outside = middle }
            }
            return (inside+outside)/2
        }
        return boundary(1)+boundary(-1)
    }
    struct Bezier {
        var p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint
        func at(_ t: CGFloat) -> CGPoint {
            let s = 1-t
            return CGPoint(x:s*s*s*p0.x+3*s*s*t*c1.x+3*s*t*t*c2.x+t*t*t*p3.x,
                           y:s*s*s*p0.y+3*s*s*t*c1.y+3*s*t*t*c2.y+t*t*t*p3.y)
        }
    }
    static func curves(_ commands: [SVGPathCommand]) -> [Bezier] {
        var point = CGPoint.zero, result: [Bezier] = []
        for command in commands {
            switch command {
            case .move(let next): point = next
            case .cubic(let a,let b,let next): result.append(Bezier(p0:point,c1:a,c2:b,p3:next)); point = next
            default: break
            }
        }
        return result
    }
    // Independent dense curve evaluation checks geometry, not command counts.
    static func maximumSampleDistance(_ points: [CGPoint], _ commands: [SVGPathCommand]) -> CGFloat {
        let cloud = curves(commands).flatMap { curve in (0...2048).map { curve.at(CGFloat($0)/2048) } }
        return points.map { point in cloud.map { hypot(point.x-$0.x,point.y-$0.y) }.min() ?? .infinity }.max() ?? 0
    }
    static func svg(_ commands: [SVGPathCommand]) -> Data {
        func point(_ p: CGPoint) -> String { "\(Double(p.x)),\(Double(p.y))" }
        let d = commands.map { command -> String in
            switch command {
            case .move(let p): return "M"+point(p)
            case .cubic(let a,let b,let p): return "C"+point(a)+" "+point(b)+" "+point(p)
            case .close: return "z"
            default: return "UNEXPECTED"
            }
        }.joined(separator:" ")
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- Skitch 1.0 -->\n" +
            "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"800\" height=\"600\">" +
            "<path d=\"\(d)\" fill=\"rgb(255,0,0)\" opacity=\"0.65\"/></svg>").utf8)
    }
    // Independent pre-optimization detector. Keep the original scans here as an
    // oracle for corner selection, insufficient endpoint look, and cluster flush.
    static func scannedCorners(_ points: [CGPoint]) -> [Int] {
        guard points.count > 1 else { return points.isEmpty ? [] : [0] }
        var result = [0], candidate: Int?, largest: CGFloat = 0
        for i in 1..<(points.count-1) {
            var before = i, after = i, distance: CGFloat = 0
            while before > 0 && distance < 8 {
                distance += hypot(points[before].x-points[before-1].x,points[before].y-points[before-1].y)
                before -= 1
            }
            let sufficientBefore = distance >= 8
            distance = 0
            while after < points.count-1 && distance < 8 {
                distance += hypot(points[after+1].x-points[after].x,points[after+1].y-points[after].y)
                after += 1
            }
            guard sufficientBefore && distance >= 8 else { continue }
            let ax = points[i].x-points[before].x, ay = points[i].y-points[before].y
            let bx = points[after].x-points[i].x, by = points[after].y-points[i].y
            let a = hypot(ax,ay), b = hypot(bx,by)
            let inverseA: CGFloat = a > 0.000001 ? 1/a : 0, inverseB: CGFloat = b > 0.000001 ? 1/b : 0
            let cosine = (ax*inverseA)*(bx*inverseB)+(ay*inverseA)*(by*inverseB)
            let angle = acos(min(1,max(-1,cosine)))*180/CGFloat.pi
            if angle <= 90 {
                if let candidate { result.append(candidate) }
                candidate = nil; largest = 0
            } else if angle > largest { candidate = i; largest = angle }
        }
        result.append(points.count-1)
        return result
    }
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("Original pressure scale and precision table", {
                for (pressure,scale) in [(CGFloat(0),CGFloat(0.25)),(0.5,0.625),(1,1),(-1,0.25),(2,1)] {
                    try expect(near(StrokeFitter.pressureScale(pressure),scale), "Wrong pressure mapping")
                }
                for (mode,value) in [(StrokeSmoothing.precise,CGFloat(1)),(.medium,2.5),(.loose,5)] {
                    try expect(StrokeFitter.fittingPrecision(mode) == value, "Wrong original precision")
                    try expect(StrokeFitter.fittingPrecision(mode,shiftPrecision:true) == 0.5, "Shift precision override")
                }
            }),
            ("Exact rotated ellipse cubic control points at all pressures", {
                let size: CGFloat = 12, rx = size/2*(1+size/15), ry = size/2
                let angle = (90-2.4*size)*CGFloat.pi/180, k: CGFloat = 0.5522847771644592
                for pressure: CGFloat in [0,0.5,1] {
                    let factor = 0.25+0.75*pressure
                    let commands = StrokeFitter.outline(samples:[sample(80,90,pressure)],size:size)
                    try assertOutline(commands)
                    try expect(commands.count == 6, "Dot must be four ellipse cubics")
                    func transformed(_ p: CGPoint) -> CGPoint {
                        let q = rotated(CGPoint(x:p.x*factor,y:p.y*factor),angle)
                        return CGPoint(x:q.x+80,y:q.y+90)
                    }
                    guard case .move(let first) = commands[0], case .cubic(let c1,let c2,let end) = commands[1] else { throw Failure("Ellipse shape") }
                    try expect(near(first,transformed(CGPoint(x:0,y:-ry))), "Ellipse start")
                    try expect(near(c1,transformed(CGPoint(x:k*rx,y:-ry))), "Original first control")
                    try expect(near(c2,transformed(CGPoint(x:rx,y:-k*ry))), "Original second control")
                    try expect(near(end,transformed(CGPoint(x:rx,y:0))), "Quarter endpoint")
                    let path = try SVGPathParser.makeCGPath(commands)
                    try expect(path.contains(transformed(CGPoint(x:rx*0.6,y:ry*0.6))), "Ellipse interior")
                    try expect(!path.contains(transformed(CGPoint(x:rx*0.8,y:ry*0.8))), "Ellipse exterior")
                }
            }),
            ("Eraser circular diameter is twice tool size before pressure", {
                for pressure: CGFloat in [0,0.5,1] {
                    let path = try outline([sample(100,100,pressure)],size:10,nib:.eraser)
                    let radius = 10*(0.25+0.75*pressure)
                    try expect(near(path.boundingBoxOfPath.width,2*radius), "Eraser diameter")
                    try expect(path.contains(CGPoint(x:100+radius*0.7,y:100+radius*0.7)), "Circle interior")
                    try expect(!path.contains(CGPoint(x:100+radius*0.72,y:100+radius*0.72)), "Circle exterior")
                }
            }),
            ("Single pass filter and open endpoints", {
                let points = [CGPoint(x:0,y:0),CGPoint(x:1,y:4),CGPoint(x:2,y:0),CGPoint(x:3,y:4),CGPoint(x:4,y:0)]
                let expected = [CGPoint(x:0,y:0),CGPoint(x:1,y:2),CGPoint(x:2,y:2),CGPoint(x:3,y:2),CGPoint(x:4,y:0)]
                try expect(StrokeFitter.filteredPoints(points) == expected, "Filter weights or in-place filtering")
                let cyclic = StrokeFitter.filteredPoints(points,closed:true)
                try expect(cyclic[0] == CGPoint(x:1.25,y:1), "Closed filter wraps previous endpoint")
            }),
            ("Deduplicate positions using maximum pressure", {
                let a = sample(10,20,0.2), b = sample(10.0000001,20.0000001,0.8)
                try expect(StrokeFitter.normalizedSamples([a,b,sample(10,20,0.1)]) == [sample(10,20,0.8)], "Duplicate pressure retention")
                try expect(StrokeFitter.outline(samples:[a,b],size:10) == StrokeFitter.outline(samples:[sample(10,20,0.8)],size:10), "Duplicate changes dot")
            }),
            ("Genuine final zero pressure drag is retained, release is caller owned", {
                let input = [sample(40,100,1),sample(200,100,0),sample(280,100,0)]
                try expect(StrokeFitter.normalizedSamples(input) == input, "Zero-pressure drag was mistaken for release")
                let path = try outline(input,size:12,nib:.eraser)
                try expect(path.contains(CGPoint(x:275,y:100)), "Final zero-pressure drag endpoint lost")
                try expect(near(try verticalWidth(path,x:265),6,0.6), "Final genuine zero pressure must be quarter width")
                let callerExcludingRelease = try outline([input[0]],size:12,nib:.eraser)
                try expect(!callerExcludingRelease.contains(CGPoint(x:200,y:100)), "No synthetic release tail")
            }),
            ("Original two-way pressure valley clamp", {
                let input = [sample(0,0,0),sample(2,0,1),sample(4,0,0)]
                let prepared = StrokeFitter.preparedSamples(input,size:10,nib:.eraser)
                try expect(prepared.count == 3, "Pressure preparation discarded zero endpoint")
                try expect(near(prepared[0].pressure,0.95) && near(prepared[2].pressure,0.95), "Drop must be chord/(width+height), in both directions")
                try expect(prepared[1].pressure == 1, "Clamp lowered a peak")
                let bounds = StrokeFitter.nibBounds(size:12)
                let pencil = StrokeFitter.preparedSamples(input,size:12)
                try expect(near(pencil[0].pressure,1-2/(bounds.width+bounds.height)), "Rotated nib pressure denominator")
            }),
            ("Sharp corners use distance eight and strict greater than ninety", {
                let points = [CGPoint(x:0,y:0),CGPoint(x:20,y:0),CGPoint(x:6,y:14),CGPoint(x:-8,y:28),CGPoint(x:-22,y:42)]
                try expect(StrokeFitter.cornerIndices(points) == [0,1,4], "135-degree corner not detected")
                let commands = StrokeFitter.centerline(samples:points.map { StrokeSample(point:$0,pressure:1) })
                try expect(curves(commands).contains(where: { $0.p3 == points[1] }), "Centerline smooths away marked corner")
                let rightAngle = [CGPoint(x:0,y:0),CGPoint(x:20,y:0),CGPoint(x:20,y:20),CGPoint(x:20,y:40)]
                try expect(StrokeFitter.cornerIndices(rightAngle) == [0,3], "Exact90 differs from recovered strict threshold")
                let short = [CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:0,y:1),CGPoint(x:-1,y:2)]
                try expect(StrokeFitter.cornerIndices(short) == [0,3], "Look distance incorrectly interpreted as sample count")
            }),
            ("Linear look windows preserve original scan corner decisions", {
                let threshold = CGFloat(8)
                for look in [threshold.nextDown,threshold,threshold.nextUp] {
                    let points = [CGPoint(x:0,y:0),CGPoint(x:look,y:0),CGPoint(x:0,y:0),CGPoint(x:-16,y:0)]
                    try expect(StrokeFitter.cornerIndices(points) == scannedCorners(points), "8px endpoint sufficiency changed for \(look)")
                }
                // Exact binary chord lengths, duplicates, sharp turns, unfinished
                // clusters, and nonuniform sample spacing exercise pointer movement.
                for seed in 1...48 {
                    var state = UInt64(seed), points = [CGPoint.zero]
                    for _ in 0..<160 {
                        state = state &* 6364136223846793005 &+ 1442695040888963407
                        let direction = Int((state >> 32) & 3), step = CGFloat((state >> 40) & 127)/8
                        let last = points.last!
                        let dx: CGFloat = direction == 0 ? step : (direction == 1 ? -step : 0)
                        let dy: CGFloat = direction == 2 ? step : (direction == 3 ? -step : 0)
                        points.append(CGPoint(x:last.x+dx,y:last.y+dy))
                    }
                    try expect(StrokeFitter.cornerIndices(points) == scannedCorners(points), "Original scan mismatch seed \(seed)")
                }
                // General curved chords also agree away from exact threshold ties.
                for spacing: CGFloat in [0.03,0.1,0.8,3,9] {
                    let points = (0..<240).map { i in CGPoint(x:CGFloat(i)*spacing,y:13*sin(CGFloat(i)*0.17)) }
                    try expect(StrokeFitter.cornerIndices(points) == scannedCorners(points), "Curved chord look mismatch")
                }
            }),
            ("Dense maximum capture corner work remains linear", {
                var previous: (count: Int, work: Int)?
                for count in [1024,4096,StrokeFitter.maximumSamples] {
                    let samples = (0..<count).map { i in sample(20+CGFloat(i)*0.00001,20) }
                    try expect(StrokeFitter.normalizedSamples(samples).count == count, "Dense input unexpectedly deduplicated")
                    let measured = StrokeFitter.cornerDetectionWork(samples.map(\.point))
                    try expect(measured.indices == [0,count-1], "Dense short capture acquired a corner")
                    try expect(measured.work <= 7*count, "Corner look is superlinear: \(measured.work) operations for \(count) points")
                    if let previous {
                        try expect(measured.work-previous.work <= 7*(count-previous.count), "Dense incremental work scaling regressed")
                    }
                    previous = (count,measured.work)
                }
                // Exercise both moving windows over many complete 8px spans.
                let long = (0..<StrokeFitter.maximumSamples).map { i in CGPoint(x:CGFloat(i)/128,y:0) }
                let measured = StrokeFitter.cornerDetectionWork(long)
                try expect(measured.indices == [0,long.count-1] && measured.work <= 7*long.count, "Moving look windows exceed linear work bound")
            }),
            ("Two-point cubic has exact one-third controls", {
                let a = CGPoint(x:2,y:3), b = CGPoint(x:32,y:63)
                let fit = StrokeFitter.fit(points:[a,b],squaredError:0.001)
                try expect(fit == [.move(to:a),.cubic(control1:CGPoint(x:12,y:23),control2:CGPoint(x:22,y:43),to:b)], "Two-point fit controls")
            }),
            ("Least squares Newton split fitting obeys geometric error budget", {
                let points: [CGPoint] = (0...36).map { i in
                    let t = CGFloat(i)/36
                    return CGPoint(x:160*t*t,y:40*sin(t*CGFloat.pi*2))
                }
                let fitted = StrokeFitter.fit(points:points,squaredError:0.04)
                try expect(curves(fitted).count > 1 && curves(fitted).count < points.count-1, "Curve must actually fit and split")
                try expect(maximumSampleDistance(points,fitted) <= 0.215, "Fitted curve misses original samples beyond squared-error tolerance")
                try expect(curves(fitted).first!.p0 == points.first! && curves(fitted).last!.p3 == points.last!, "Fit endpoints changed")
                let segments = curves(fitted)
                for i in 1..<segments.count {
                    try expect(segments[i-1].p3 == segments[i].p0, "Recursive split is disconnected")
                    let a = CGPoint(x:segments[i-1].p3.x-segments[i-1].c2.x,y:segments[i-1].p3.y-segments[i-1].c2.y)
                    let b = CGPoint(x:segments[i].c1.x-segments[i].p0.x,y:segments[i].c1.y-segments[i].p0.y)
                    try expect(abs(a.x*b.y-a.y*b.x) < 1e-6 && a.x*b.x+a.y*b.y >= 0, "Split tangent is discontinuous")
                }
            }),
            ("Shift tightens centerline fidelity after the original filter", {
                let input = (0...40).map { i in sample(CGFloat(i)*4,100+8*sin(CGFloat(i)*0.7)) }
                let points = StrokeFitter.filteredPoints(input.map(\.point))
                let medium = StrokeFitter.centerline(samples:input)
                let shift = StrokeFitter.centerline(samples:input,shiftPrecision:true)
                let mediumError = maximumSampleDistance(points,medium), shiftError = maximumSampleDistance(points,shift)
                try expect(shiftError <= 0.53 && mediumError <= 2.53, "Precision must be squared inside fitter")
                try expect(shiftError < mediumError && curves(shift).count > curves(medium).count, "Shift must materially improve this noisy fixture")
            }),
            ("Horizontal pencil widths agree with rotated ellipse support", {
                let size: CGFloat = 12, angle = (90-2.4*size)*CGFloat.pi/180
                let rx = size/2*(1+size/15), ry = size/2
                let fullWidth = 2*sqrt(pow(rx*sin(angle),2)+pow(ry*cos(angle),2))
                var widths: [CGFloat] = []
                for pressure: CGFloat in [0,0.5,1] {
                    let path = try outline((0...30).map { sample(40+CGFloat($0)*8,100,pressure) },size:size)
                    let expected = fullWidth*(0.25+0.75*pressure)
                    for x: CGFloat in [80,160,240] {
                        let measured = try verticalWidth(path,x:x)
                        try expect(near(measured,expected,0.7), "Nib support width p=\(pressure) x=\(x): \(measured), expected \(expected)")
                        if x == 160 { widths.append(measured) }
                    }
                    try expect(!path.contains(CGPoint(x:160,y:100+expected)), "Outline fills beyond nib")
                }
                try expect(widths[0] < widths[1] && widths[1] < widths[2], "Pressure does not alter geometry")
            }),
            ("Pressure ramp changes actual interior cross sections", {
                let input = (0...60).map { i in sample(40+CGFloat(i)*4,100,CGFloat(i)/60) }
                let path = try outline(input,size:10,nib:.eraser)
                let widths = try [CGFloat(80),160,240].map { try verticalWidth(path,x:$0) }
                try expect(widths[0] < widths[1] && widths[1] < widths[2], "Ramp is a constant-width stroke")
                for (x,width) in zip([CGFloat(80),160,240],widths) {
                    let expected = 20*(0.25+0.75*(x-40)/240)
                    try expect(near(width,expected,0.75), "Pressure interpolation diverges at x=\(x), width=\(width), expected=\(expected)")
                }
            }),
            ("Corner sweep is closed and includes both legs and rounded caps", {
                let input = [sample(60,100),sample(140,100),sample(84,156),sample(28,212),sample(14,226)]
                let path = try outline(input,size:10,nib:.eraser)
                for point in [CGPoint(x:70,y:100),CGPoint(x:110,y:130),CGPoint(x:42,y:198),CGPoint(x:14,y:226)] {
                    try expect(path.contains(point), "Sweep misses leg/cap \(point)")
                }
                try expect(!path.contains(CGPoint(x:100,y:160)), "Sweep bridges distant concavity")
            }),
            ("Deterministic fit of repeated captures", {
                let input = (0...24).map { i in sample(40+CGFloat(i)*6,100+20*sin(CGFloat(i)/4),CGFloat(i%5)/4) }
                let first = StrokeFitter.outline(samples:input,size:8)
                try assertOutline(first)
                for _ in 0..<3 { try expect(StrokeFitter.outline(samples:input,size:8) == first, "Random input jitter leaked into pure fitter") }
            }),
            ("Tiny and all-duplicate strokes remain finite and closed", {
                for input in [[sample(20,20,0),sample(20,20,0)], [sample(20,20),sample(20.00001,20)], [sample(20,20),sample(20.001,20.001)]] {
                    let result = StrokeFitter.outline(samples:input,size:0.01)
                    try expect(!result.isEmpty, "Tiny outline lost: \(input)")
                    try assertOutline(result)
                    let path = try SVGPathParser.makeCGPath(result)
                    let a = input.first!.point, b = input.last!.point
                    try expect(path.boundingBoxOfPath.width > 0 && path.boundingBoxOfPath.height > 0,
                               "Tiny path collapsed to zero area")
                    try expect(path.contains(CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)), "Tiny filled path excludes its center")
                }
            }),
            ("Finite validation and limits reject unsafe requests", {
                let valid = sample(20,20)
                for size: CGFloat in [0,-1,.infinity,.nan,4097] {
                    try expect(StrokeFitter.outline(samples:[valid],size:size).isEmpty, "Invalid size accepted")
                }
                let dirty = [sample(.nan,1),sample(1,.infinity),sample(1,1,.nan),sample(3_000_000,1),valid]
                try expect(StrokeFitter.normalizedSamples(dirty) == [valid], "Invalid sample accepted")
                try expect(StrokeFitter.outline(samples:[],size:10).isEmpty, "Empty stroke fabricated")
                let tooMany = Array(repeating:valid,count:StrokeFitter.maximumSamples+1)
                try expect(StrokeFitter.outline(samples:tooMany,size:10).isEmpty, "Excess input silently truncated")
                try expect(StrokeFitter.fit(points:[.zero,CGPoint(x:1,y:1)],squaredError:.nan).isEmpty, "NaN budget accepted")
            }),
            ("Closed fitted outline retains editable cubic controls through native SVG and Codable", {
                let input = (0...30).map { i in sample(80+CGFloat(i)*7,160+30*sin(CGFloat(i)/6),CGFloat(i)/30) }
                let commands = StrokeFitter.outline(samples:input,size:9)
                try assertOutline(commands)
                let decoded = try LegacySkitch.decode(svg(commands))
                try expect(decoded.paths.count == 1 && decoded.paths[0].commands == commands, "Native SVG round-trip changes cubic control points")
                try expect(near(decoded.paths[0].color.alpha,0.65), "SVG opacity changed")
                let encoded = try JSONEncoder().encode(commands)
                try expect(try JSONDecoder().decode([SVGPathCommand].self,from:encoded) == commands, "Editable command Codable round-trip")
                let before = try SVGPathParser.makeCGPath(commands), after = try SVGPathParser.makeCGPath(decoded.paths[0].commands)
                for x in stride(from:50,through:330,by:5) { for y in stride(from:110,through:220,by:5) {
                    let point = CGPoint(x:x,y:y)
                    try expect(before.contains(point) == after.contains(point), "Filled geometry changed on SVG reopen")
                } }
            })
        ]
        var failures = 0
        for (name,test) in tests {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("StrokeFittingTests: \(tests.count-failures)/\(tests.count) passed")
        if failures != 0 { exit(1) }
    }
}
#endif
