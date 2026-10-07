import Foundation
import CoreGraphics

struct StrokeSample: Codable, Equatable {
    var point: CGPoint
    var pressure: CGFloat
}
enum StrokeSmoothing: String, Codable { case precise, medium, loose }
enum StrokeNib: String, Codable { case pencil, eraser }

/// Pure recovery of the original fitter's numeric pipeline, not a stroked polyline.
/// Evidence in analysis/decompiled.c (original unslid i386 addresses):
/// addPoint 0x001be91e; nib 0x001be578/0x001be5f0; filter 0x001bfd80;
/// corners 0x001bff06; fit 0x001c0112/0x001c0386; least squares 0x001c079c;
/// chord/Newton/split 0x001c06ee/0x001c10c6/0x001c0fb0;
/// pressure 0x001c134c/0x001c12da; sweep 0x001bea70/0x001c13f6.
/// Original +/-0.01 random input jitter and Path::removeInflections are deliberately
/// not reproduced. This deterministic 64-bit port has not run against i386 output.
enum StrokeFitter {
    static let maximumSamples = 16_384
    static let maximumOutlinePoints = 65_536
    private static let epsilon: CGFloat = 0.000001
    // Exact binary32 constant read at 0x0026131c, used by SubPath::setToEllipse.
    private static let kappa: CGFloat = 0.5522847771644592

    /// Original ToolBrush/ToolEraser precision table; _fitBeziers squares this.
    static func fittingPrecision(_ smoothing: StrokeSmoothing = .medium, shiftPrecision: Bool = false) -> CGFloat {
        if shiftPrecision { return 0.5 }
        switch smoothing { case .precise: return 1; case .medium: return 2.5; case .loose: return 5 }
    }
    static func pressureScale(_ pressure: CGFloat) -> CGFloat {
        guard pressure.isFinite else { return 0.25 }
        return 0.25 + 0.75 * min(1, max(0, pressure))
    }

    /// Invalid samples are removed; over-limit captures return no geometry. Nearby
    /// duplicate positions retain their maximum pressure, as original addPoint does.
    /// Zero-pressure drag samples remain valid quarter-width nib input. The caller
    /// excludes release events; samples alone cannot distinguish drag from release.
    static func normalizedSamples(_ samples: [StrokeSample]) -> [StrokeSample] {
        guard samples.count <= maximumSamples else { return [] }
        var result: [StrokeSample] = []
        for sample in samples {
            guard finite(sample.point), sample.pressure.isFinite else { continue }
            let value = StrokeSample(point: sample.point, pressure: min(1, max(0, sample.pressure)))
            if let last = result.last, abs(last.point.x-value.point.x) < epsilon, abs(last.point.y-value.point.y) < epsilon {
                result[result.count-1].pressure = max(last.pressure, value.pressure)
            } else { result.append(value) }
        }
        return result
    }

    /// _preparePressureData raises valleys in two directions; it does not low-pass
    /// pressure. Allowed drop = sample chord length / (nib bounds width + height).
    static func preparedSamples(_ samples: [StrokeSample], size: CGFloat, nib: StrokeNib = .pencil) -> [StrokeSample] {
        guard validSize(size) else { return [] }
        var result = normalizedSamples(samples)
        guard result.count > 1 else { return result }
        let denominator = nibBounds(size: size, nib: nib).width + nibBounds(size: size, nib: nib).height
        for i in 1..<result.count {
            let drop = length(subtract(result[i].point, result[i-1].point)) / denominator
            result[i].pressure = max(result[i].pressure, result[i-1].pressure-drop)
        }
        for i in stride(from: result.count-2, through: 0, by: -1) {
            let drop = length(subtract(result[i+1].point, result[i].point)) / denominator
            result[i].pressure = max(result[i].pressure, result[i+1].pressure-drop)
        }
        return result
    }

    /// One simultaneous 1/4,1/2,1/4 pass; open endpoints remain exact.
    static func filteredPoints(_ points: [CGPoint], closed: Bool = false) -> [CGPoint] {
        guard points.count <= maximumOutlinePoints, points.allSatisfy(finite) else { return [] }
        guard points.count > 2 else { return points }
        return points.indices.map { i in
            if !closed && (i == 0 || i == points.count-1) { return points[i] }
            return add(add(multiply(points[(i+points.count-1)%points.count], 0.25), multiply(points[i], 0.5)), multiply(points[(i+1)%points.count], 0.25))
        }
    }

    /// Original cumulative chord look, not an eight-sample look. A contiguous
    /// >90-degree turn cluster chooses its largest angle, then commits on exit.
    static func cornerIndices(_ points: [CGPoint]) -> [Int] {
        detectCorners(points).indices
    }

    #if STROKE_FITTING_TESTS
    /// Deterministic work accounting avoids machine-dependent timing assertions.
    /// Counts chord evaluations and every look-window distance comparison.
    static func cornerDetectionWork(_ points: [CGPoint]) -> (indices: [Int], work: Int) {
        detectCorners(points)
    }
    #endif

    private static func detectCorners(_ points: [CGPoint]) -> (indices: [Int], work: Int) {
        guard points.count > 1, points.count <= maximumOutlinePoints, points.allSatisfy(finite) else {
            return (points.isEmpty ? [] : [0], 0)
        }
        var work = 0
        var chord: [CGFloat] = [0]
        chord.reserveCapacity(points.count)
        for i in 1..<points.count {
            chord.append(chord.last! + length(subtract(points[i],points[i-1])))
            work += 1
        }
        var corners = [0], candidate: Int?, largest: CGFloat = 0
        // The nearest endpoint at least 8px away never moves backward as i grows.
        // Each pointer advances at most n times, even for subpixel-dense samples.
        var before = 0, after = 1
        if points.count > 2 {
            for i in 1..<(points.count-1) {
                while before+1 < i {
                    work += 1
                    if chord[i]-chord[before+1] < 8 { break }
                    before += 1
                }
                after = max(after,i+1)
                while after < points.count-1 {
                    work += 1
                    if chord[after]-chord[i] >= 8 { break }
                    after += 1
                }
                work += 2
                let sufficientBefore = chord[i]-chord[before] >= 8
                guard sufficientBefore && chord[after]-chord[i] >= 8 else { continue }
                let incoming = unit(subtract(points[i], points[before]))
                let outgoing = unit(subtract(points[after], points[i]))
                let angle = acos(min(1, max(-1, dot(incoming, outgoing)))) * 180 / .pi
                if angle <= 90 {
                    if let candidate { corners.append(candidate) }
                    candidate = nil; largest = 0
                } else if angle > largest { candidate = i; largest = angle }
            }
        }
        // The original fails to flush an unfinished candidate at the last point;
        // preserve that behavior. Endpoints are already mandatory corners.
        corners.append(points.count-1)
        return (corners,work)
    }

    static func centerline(samples: [StrokeSample], smoothing: StrokeSmoothing = .medium,
                           shiftPrecision: Bool = false) -> [SVGPathCommand] {
        let samples = normalizedSamples(samples)
        guard let first = samples.first else { return [] }
        guard samples.count > 1 else { return [.move(to: first.point)] }
        let precision = fittingPrecision(smoothing, shiftPrecision: shiftPrecision)
        let points = samples.map(\.point), corners = cornerIndices(points)
        var curves: [Cubic] = []
        for (start, end) in zip(corners, corners.dropFirst()) {
            let filtered = filteredPoints(Array(points[start...end]))
            curves += fitCurves(filtered, squaredError: precision*precision)
        }
        return commands(curves)
    }

    /// Parent consumes the result as one filled, nonzero-winding editable path.
    /// Only M/C/close are emitted; pressure changes the entire rotated nib footprint.
    static func outline(samples: [StrokeSample], size: CGFloat, smoothing: StrokeSmoothing = .medium,
                        shiftPrecision: Bool = false, nib: StrokeNib = .pencil) -> [SVGPathCommand] {
        guard validSize(size) else { return [] }
        let samples = preparedSamples(samples, size: size, nib: nib)
        guard let first = samples.first else { return [] }
        let footprint = nibCurves(size: size, nib: nib)
        if samples.count == 1 {
            let scale = pressureScale(first.pressure)
            return commands(footprint.map { $0.transformed { add(first.point, multiply($0, scale)) } }, closed: true)
        }
        let tolerance = flattenDistance(size: size, nib: nib)
        let center = cubics(centerline(samples: samples, smoothing: smoothing, shiftPrecision: shiftPrecision))
        guard !center.isEmpty else { return [] }
        var pathPoints: [CGPoint] = []
        for curve in center {
            guard appendForwardDifference(curve, tolerance: tolerance, to: &pathPoints) else { return [] }
        }
        pathPoints.append(center.last!.p3)
        if pathPoints.count == 2 { pathPoints.insert(multiply(add(pathPoints[0], pathPoints[1]), 0.5), at: 1) }
        guard pathPoints.count >= 3 else { return [] }
        var nibPoints: [CGPoint] = []
        for curve in footprint {
            guard appendNibPoints(curve, tolerance: tolerance, to: &nibPoints) else { return [] }
        }
        var cumulative: [CGFloat] = [0]
        for i in 1..<samples.count { cumulative.append(cumulative.last! + length(subtract(samples[i].point, samples[i-1].point))) }
        let total = cumulative.last!
        func scale(at index: Int) -> CGFloat {
            let position = CGFloat(index)/CGFloat(pathPoints.count-1)*total
            var low = 0, high = cumulative.count-1
            while high-low > 1 {
                let middle = (low+high)/2
                if cumulative[middle] < position { low = middle } else { high = middle }
            }
            let span = cumulative[high]-cumulative[low]
            let t = span > epsilon ? (position-cumulative[low])/span : 0
            return pressureScale(samples[low].pressure*(1-t)+samples[high].pressure*t)
        }
        var boundary: [CGPoint] = [], sharp = Set<Int>(), overflow = false
        func append(_ point: CGPoint, corner: Bool = false) {
            guard boundary.count < maximumOutlinePoints else { overflow = true; return }
            if let last = boundary.last, length(subtract(point,last)) < epsilon { if corner { sharp.insert(boundary.count-1) }; return }
            if corner { sharp.insert(boundary.count) }
            boundary.append(point)
        }
        func support(_ direction: CGPoint) -> Int {
            let normal = CGPoint(x: direction.y, y: -direction.x)
            var best = 0, value = -CGFloat.infinity
            for (i, point) in nibPoints.enumerated() {
                let candidate = dot(point, normal)
                if candidate > value { value = candidate; best = i }
            }
            return best
        }
        func arc(from first: Int, through last: Int, around point: CGPoint, scale: CGFloat) {
            var index = first
            for _ in 0..<nibPoints.count {
                append(add(point, multiply(nibPoints[index], scale)))
                if index == last { break }
                index = (index+1)%nibPoints.count
            }
        }
        func step(_ previous: CGPoint, _ point: CGPoint, _ next: CGPoint, scale: CGFloat) {
            let incoming = subtract(point, previous), outgoing = subtract(next, point)
            let a = support(incoming), b = support(outgoing)
            if a == b { append(add(point, multiply(nibPoints[a],scale))); return }
            if cross(incoming,outgoing) < 0 {
                let p = add(point, multiply(nibPoints[a],scale)), q = add(point, multiply(nibPoints[b],scale))
                let corner = length(subtract(p,q)) >= tolerance
                append(p, corner: corner); append(q, corner: corner)
            } else { arc(from: a, through: b, around: point, scale: scale) }
        }
        for i in 1..<(pathPoints.count-1) {
            step(pathPoints[i-1],pathPoints[i],pathPoints[i+1],scale: scale(at: i))
            if overflow { return [] }
        }
        let last = pathPoints.count-1
        let endSupport = support(subtract(pathPoints[last],pathPoints[last-1]))
        arc(from: endSupport, through: (endSupport+nibPoints.count/2)%nibPoints.count, around: pathPoints[last], scale: scale(at: last))
        for i in stride(from: last-1, through: 1, by: -1) {
            step(pathPoints[i+1],pathPoints[i],pathPoints[i-1],scale: scale(at: i))
            if overflow { return [] }
        }
        let startSupport = support(subtract(pathPoints[0],pathPoints[1]))
        arc(from: startSupport, through: (startSupport+nibPoints.count/2)%nibPoints.count, around: pathPoints[0], scale: scale(at: 0))
        guard !overflow, boundary.count >= 3, boundary.allSatisfy(finite) else { return [] }
        // Match original outline decimation, retaining marked concave corners.
        var reduced = [boundary[0]], marks = Set<Int>(), distance: CGFloat = 0
        for i in 1..<boundary.count {
            distance += length(subtract(boundary[i],boundary[i-1]))
            if distance > tolerance {
                if sharp.contains(i) { marks.insert(reduced.count) }
                reduced.append(boundary[i]); distance = 0
            } else if sharp.contains(i) || i == boundary.count-1 {
                reduced[reduced.count-1] = boundary[i]
                if sharp.contains(i) { marks.insert(reduced.count-1) }
                distance = 0
            }
        }
        // Tiny strokes can be shorter than the decimation distance throughout.
        // Keep their complete boundary instead of indexing a collapsed polygon.
        if reduced.count < 3 { reduced = boundary; marks = sharp }
        // Recovery safety for subpixel tool sizes:
        // the original fixed tolerance can accept a zero-area closed cubic there.
        let precision = min(min(1, tolerance/5), size < 1 ? size/100 : .infinity)
        var fitted: [Cubic] = []
        if let start = marks.min() {
            let order = Array(reduced.indices.dropFirst(start)) + Array(reduced.indices.prefix(start))
            var segment: [CGPoint] = [reduced[start]]
            for i in 1...order.count {
                let index = order[i%order.count]; segment.append(reduced[index])
                if marks.contains(index) || i == order.count {
                    fitted += fitCurves(filteredPoints(segment), squaredError: precision*precision)
                    segment = [reduced[index]]
                }
            }
        } else {
            // Original _findSplitpoint fits a provisional closed curve, then rotates
            // the boundary to its largest squared-error point before cyclic filtering.
            var closed = reduced; closed.append(reduced[0])
            let tangent = unit(subtract(unit(subtract(reduced[reduced.count-1],reduced[0])),unit(subtract(reduced[1],reduced[0]))))
            let provisional = generate(closed, parameters: chordParameters(closed), start: multiply(tangent,-1), end: tangent)
            let split = maximumError(closed, curve: provisional, parameters: chordParameters(closed)).index
            let index = min(split,reduced.count-1)
            reduced = Array(reduced[index...]) + Array(reduced[..<index])
            var filtered = filteredPoints(reduced, closed: true); filtered.append(filtered[0])
            fitted = fitCurves(filtered, squaredError: precision*precision)
        }
        let result = commands(fitted, closed: true)
        return result.allSatisfy(\.isFinite) ? result : []
    }

    /// Geometry helper for parent/tests: fit without input smoothing or corner finding.
    static func fit(points: [CGPoint], squaredError: CGFloat) -> [SVGPathCommand] {
        guard points.count >= 2, points.count <= maximumOutlinePoints, points.allSatisfy(finite), squaredError.isFinite, squaredError > 0 else { return [] }
        return commands(fitCurves(points, squaredError: squaredError))
    }
    static func nibOutline(size: CGFloat, pressure: CGFloat = 1, nib: StrokeNib = .pencil) -> [SVGPathCommand] {
        guard validSize(size), pressure.isFinite else { return [] }
        return commands(nibCurves(size: size, nib: nib).map { $0.transformed { multiply($0,pressureScale(pressure)) } }, closed: true)
    }
    static func nibBounds(size: CGFloat, nib: StrokeNib = .pencil) -> CGRect {
        guard validSize(size), let path = try? SVGPathParser.makeCGPath(nibOutline(size: size,nib: nib)) else { return .zero }
        return path.boundingBoxOfPath
    }

    private struct Cubic {
        var p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint
        func transformed(_ map: (CGPoint) -> CGPoint) -> Cubic { Cubic(p0: map(p0),c1: map(c1),c2: map(c2),p3: map(p3)) }
        func evaluate(_ t: CGFloat) -> CGPoint {
            let s = 1-t
            return add(add(multiply(p0,s*s*s),multiply(c1,3*s*s*t)),add(multiply(c2,3*s*t*t),multiply(p3,t*t*t)))
        }
        func halves() -> (Cubic,Cubic) {
            let a = multiply(add(p0,c1),0.5), b = multiply(add(c1,c2),0.5), c = multiply(add(c2,p3),0.5)
            let d = multiply(add(a,b),0.5), e = multiply(add(b,c),0.5), m = multiply(add(d,e),0.5)
            return (Cubic(p0:p0,c1:a,c2:d,p3:m),Cubic(p0:m,c1:e,c2:c,p3:p3))
        }
    }
    private static func validSize(_ size: CGFloat) -> Bool { size.isFinite && size > 0 && size <= 4096 }
    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite && abs(point.x) <= 2_000_000 && abs(point.y) <= 2_000_000 }
    private static func add(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x:a.x+b.x,y:a.y+b.y) }
    private static func subtract(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x:a.x-b.x,y:a.y-b.y) }
    private static func multiply(_ p: CGPoint,_ scale: CGFloat) -> CGPoint { CGPoint(x:p.x*scale,y:p.y*scale) }
    private static func dot(_ a: CGPoint,_ b: CGPoint) -> CGFloat { a.x*b.x+a.y*b.y }
    private static func cross(_ a: CGPoint,_ b: CGPoint) -> CGFloat { a.x*b.y-a.y*b.x }
    private static func length(_ p: CGPoint) -> CGFloat { hypot(p.x,p.y) }
    private static func unit(_ p: CGPoint) -> CGPoint { let size = length(p); return size > epsilon ? multiply(p,1/size) : .zero }
    private static func commands(_ curves: [Cubic], closed: Bool = false) -> [SVGPathCommand] {
        guard let first = curves.first else { return [] }
        var result: [SVGPathCommand] = [.move(to:first.p0)]
        result += curves.map { .cubic(control1:$0.c1,control2:$0.c2,to:$0.p3) }
        if closed { result.append(.close) }
        return result
    }
    private static func cubics(_ commands: [SVGPathCommand]) -> [Cubic] {
        var point = CGPoint.zero, result: [Cubic] = []
        for command in commands {
            switch command {
            case .move(let p): point = p
            case .cubic(let a,let b,let p): result.append(Cubic(p0:point,c1:a,c2:b,p3:p)); point = p
            default: break
            }
        }
        return result
    }
    private static func nibCurves(size: CGFloat,nib: StrokeNib) -> [Cubic] {
        let rx = nib == .eraser ? size : size/2*(1+size/15)
        let ry = nib == .eraser ? size : size/2
        let angle = nib == .eraser ? 0 : (90-2.4*size)*CGFloat.pi/180
        let curves = [Cubic(p0:CGPoint(x:0,y:-ry),c1:CGPoint(x:kappa*rx,y:-ry),c2:CGPoint(x:rx,y:-kappa*ry),p3:CGPoint(x:rx,y:0)),
            Cubic(p0:CGPoint(x:rx,y:0),c1:CGPoint(x:rx,y:kappa*ry),c2:CGPoint(x:kappa*rx,y:ry),p3:CGPoint(x:0,y:ry)),
            Cubic(p0:CGPoint(x:0,y:ry),c1:CGPoint(x:-kappa*rx,y:ry),c2:CGPoint(x:-rx,y:kappa*ry),p3:CGPoint(x:-rx,y:0)),
            Cubic(p0:CGPoint(x:-rx,y:0),c1:CGPoint(x:-rx,y:-kappa*ry),c2:CGPoint(x:-kappa*rx,y:-ry),p3:CGPoint(x:0,y:-ry))]
        return curves.map { $0.transformed { CGPoint(x:$0.x*cos(angle)-$0.y*sin(angle),y:$0.x*sin(angle)+$0.y*cos(angle)) } }
    }
    private static func flattenDistance(size: CGFloat,nib: StrokeNib) -> CGFloat {
        let rx = nib == .eraser ? size : size/2*(1+size/15), ry = nib == .eraser ? size : size/2
        return min(2,max(0.5,(rx+ry)*0.2))
    }
    /// Original nib flatten splits on endpoint chord length (0x001bc522), not bounds.
    private static func appendNibPoints(_ curve: Cubic,tolerance: CGFloat,to points: inout [CGPoint],depth: Int = 0) -> Bool {
        guard points.count < maximumOutlinePoints else { return false }
        if length(subtract(curve.p3,curve.p0)) <= tolerance || depth >= 32 { points.append(curve.p0); return true }
        let (a,b) = curve.halves()
        return appendNibPoints(a,tolerance:tolerance,to:&points,depth:depth+1) && appendNibPoints(b,tolerance:tolerance,to:&points,depth:depth+1)
    }
    /// Original adaptive forward differences (Bezier::flatten2, 0x001bc9b4).
    private static func appendForwardDifference(_ curve: Cubic,tolerance: CGFloat,to points: inout [CGPoint]) -> Bool {
        let delta = subtract(curve.p3,curve.p0)
        var h = min(1,6/max(epsilon,abs(delta.x)+abs(delta.y)))
        let a = add(subtract(multiply(curve.c1,3),multiply(curve.c2,3)),subtract(curve.p3,curve.p0))
        let b = multiply(add(subtract(curve.p0,multiply(curve.c1,2)),curve.c2),3)
        let c = multiply(subtract(curve.c1,curve.p0),3)
        var d3 = multiply(a,6*h*h*h)
        var d2 = add(multiply(b,2*h*h),d3)
        var d1 = add(add(multiply(c,h),multiply(b,h*h)),multiply(a,h*h*h))
        var t: CGFloat = 0
        while t < 1-epsilon {
            guard points.count < maximumOutlinePoints else { return false }
            points.append(curve.evaluate(t))
            var iterations = 0
            while abs(d1.x)+abs(d1.y) < tolerance*0.5 && h < 1 {
                d1 = add(multiply(d1,2),d2); d2 = multiply(add(d2,d3),4); d3 = multiply(d3,8); h *= 2
                iterations += 1; if iterations > 64 { return false }
            }
            while abs(d1.x)+abs(d1.y) > tolerance*2 && h > 1e-12 {
                d3 = multiply(d3,0.125); d2 = subtract(multiply(d2,0.25),d3); d1 = multiply(subtract(d1,d2),0.5); h *= 0.5
                iterations += 1; if iterations > 128 { return false }
            }
            guard h.isFinite && h > 0 else { return false }
            t += h; d1 = add(d1,d2); d2 = add(d2,d3)
        }
        return true
    }

    private static func fitCurves(_ points: [CGPoint],squaredError: CGFloat) -> [Cubic] {
        guard points.count >= 2 else { return [] }
        var start = unit(subtract(points[1],points[0])), end = unit(subtract(points[points.count-2],points.last!))
        if length(subtract(points[0],points.last!)) < epsilon { start = unit(subtract(start,end)); end = multiply(start,-1) }
        return recursiveFit(points,start:start,end:end,squaredError:squaredError,depth:0)
    }
    private static func chordParameters(_ points: [CGPoint]) -> [CGFloat] {
        var result: [CGFloat] = [0]
        for i in 1..<points.count { result.append(result.last!+length(subtract(points[i],points[i-1]))) }
        let total = result.last!
        if total <= epsilon { return points.indices.map { CGFloat($0)/CGFloat(max(1,points.count-1)) } }
        return result.map { $0/total }
    }
    private static func generate(_ points: [CGPoint],parameters: [CGFloat],start: CGPoint,end: CGPoint) -> Cubic {
        let first = points[0], last = points.last!
        var c00: CGFloat = 0, c01: CGFloat = 0, c11: CGFloat = 0, x0: CGFloat = 0, x1: CGFloat = 0
        for (p,t) in zip(points,parameters) {
            let s = 1-t, b0 = s*s*s, b1 = 3*t*s*s, b2 = 3*t*t*s, b3 = t*t*t
            let a = multiply(start,b1), b = multiply(end,b2)
            let residual = subtract(p,add(multiply(first,b0+b1),multiply(last,b2+b3)))
            c00 += dot(a,a); c01 += dot(a,b); c11 += dot(b,b)
            x0 += dot(a,residual); x1 += dot(b,residual)
        }
        let determinant = c00*c11-c01*c01
        var alpha: CGFloat = 0, beta: CGFloat = 0
        if abs(determinant) >= epsilon { alpha = (x0*c11-x1*c01)/determinant; beta = (c00*x1-c01*x0)/determinant }
        else if abs(c00+c01) > epsilon { alpha = x0/(c00+c01); beta = alpha }
        else if abs(c01+c11) > epsilon { alpha = x1/(c01+c11); beta = alpha }
        if !alpha.isFinite || !beta.isFinite || alpha < epsilon || beta < epsilon { alpha = length(subtract(last,first))/3; beta = alpha }
        return Cubic(p0:first,c1:add(first,multiply(start,alpha)),c2:add(last,multiply(end,beta)),p3:last)
    }
    private static func maximumError(_ points: [CGPoint],curve: Cubic,parameters: [CGFloat]) -> (value: CGFloat,index: Int) {
        var maximum: CGFloat = 0, split = points.count/2
        if points.count > 2 { for i in 1..<(points.count-1) {
            let delta = subtract(curve.evaluate(parameters[i]),points[i]), error = dot(delta,delta)
            if error > maximum { maximum = error; split = i }
        } }
        return (maximum,split)
    }
    private static func newton(_ curve: Cubic,point: CGPoint,t: CGFloat) -> CGFloat {
        let s = 1-t
        let d0 = multiply(subtract(curve.c1,curve.p0),3), d1 = multiply(subtract(curve.c2,curve.c1),3), d2 = multiply(subtract(curve.p3,curve.c2),3)
        let first = add(add(multiply(d0,s*s),multiply(d1,2*s*t)),multiply(d2,t*t))
        let second = add(multiply(subtract(d1,d0),2*s),multiply(subtract(d2,d1),2*t))
        let delta = subtract(curve.evaluate(t),point)
        let denominator = dot(first,first)+dot(delta,second)
        if abs(denominator) <= 1e-8 { return t }
        let next = t-dot(delta,first)/denominator
        return next.isFinite ? next : t
    }
    private static func recursiveFit(_ points: [CGPoint],start: CGPoint,end: CGPoint,squaredError: CGFloat,depth: Int) -> [Cubic] {
        if points.count == 2 {
            let distance = length(subtract(points[1],points[0]))/3
            return [Cubic(p0:points[0],c1:add(points[0],multiply(start,distance)),c2:add(points[1],multiply(end,distance)),p3:points[1])]
        }
        if depth >= 32 { return (1..<points.count).map { i in
            let delta = subtract(points[i],points[i-1])
            return Cubic(p0:points[i-1],c1:add(points[i-1],multiply(delta,1/3)),c2:add(points[i-1],multiply(delta,2/3)),p3:points[i])
        } }
        var parameters = chordParameters(points), split = points.count/2
        for _ in 0..<10 {
            let curve = generate(points,parameters:parameters,start:start,end:end)
            let error = maximumError(points,curve:curve,parameters:parameters); split = error.index
            if error.value <= squaredError && [curve.p0,curve.c1,curve.c2,curve.p3].allSatisfy(finite) { return [curve] }
            if error.value > squaredError*10 { break }
            let refined = zip(points,parameters).map { newton(curve,point:$0.0,t:$0.1) }
            let span = refined.last!-refined[0]
            guard span.isFinite && abs(span) > epsilon else { break }
            let normalized = refined.map { ($0-refined[0])/span }
            // Recovery safety: original accepts non-monotone Newton parameters.
            // Split rather than accepting loops/NaNs from invalid parameter ordering.
            if !normalized.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) || zip(normalized,normalized.dropFirst()).contains(where: { $0 > $1 }) { break }
            parameters = normalized
        }
        split = max(1,min(points.count-2,split))
        let a = unit(subtract(points[split-1],points[split])), b = unit(subtract(points[split],points[split+1]))
        var middle = unit(add(a,b)); if middle == .zero { middle = a == .zero ? b : a }
        return recursiveFit(Array(points[...split]),start:start,end:middle,squaredError:squaredError,depth:depth+1)
            + recursiveFit(Array(points[split...]),start:multiply(middle,-1),end:end,squaredError:squaredError,depth:depth+1)
    }
}
