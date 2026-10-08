// Pure executable tests; no Canvas, windows or OS input. From the repository root:
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -D VECTOR_GEOMETRY_TESTS \
//   Sources/{LegacySkitch,LegacyBridge,DocumentModel,VectorGeometry}.swift \
//   tests/VectorGeometryTests.swift -o /tmp/skitch-vector-geometry-tests
// /tmp/skitch-vector-geometry-tests
#if VECTOR_GEOMETRY_TESTS
import AppKit
import CoreGraphics
import Foundation
import Darwin

@main
enum VectorGeometryTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
    }
    static func required<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(description: message) }; return value
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ epsilon: CGFloat = 0.00001) -> Bool {
        abs(a - b) < epsilon
    }
    static func rectangle(_ rect: CGRect, filled: Bool = true, group: UUID? = nil) -> SketchElement {
        var e = SketchElement(kind: .rectangle)
        e.rect = rect; e.filled = filled; e.strokeWidth = 2
        e.color = SketchColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.75))
        e.groupID = group; return e
    }
    static func pathElement(_ commands: [SVGPathCommand]) -> SketchElement {
        var e = SketchElement(kind: .path)
        e.pathCommands = commands; e.filled = true; e.strokeWidth = 0; return e
    }
    static func painted(_ e: SketchElement) throws -> CGPath {
        try required(VectorGeometry.paintedPath(for: e), "Missing painted path for \(e.kind)")
    }
    static func disk(_ center: CGPoint, _ diameter: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                               width: diameter, height: diameter), transform: nil)
    }
    static func contains(_ paths: [CGPath], _ point: CGPoint) -> Bool {
        paths.contains { $0.contains(point, using: .winding) }
    }
    // This oracle reads CGPath directly and never calls VectorGeometry.commands.
    static func rawCommands(_ path: CGPath) -> [SVGPathCommand] {
        var values: [SVGPathCommand] = []
        path.applyWithBlock { item in
            let item = item.pointee, p = item.points
            switch item.type {
            case .moveToPoint: values.append(.move(to: p[0]))
            case .addLineToPoint: values.append(.line(to: p[0]))
            case .addQuadCurveToPoint: values.append(.quadratic(control: p[0], to: p[1]))
            case .addCurveToPoint: values.append(.cubic(control1: p[0], control2: p[1], to: p[2]))
            case .closeSubpath: values.append(.close)
            @unknown default: break
            }
        }
        return values
    }
    static func cubicCount(_ path: CGPath) -> Int {
        rawCommands(path).filter { if case .cubic = $0 { return true }; return false }.count
    }
    // Circular donut made independently, with opposite contour orientations.
    static func donut(center: CGPoint = CGPoint(x: 60, y: 60), outer: CGFloat = 40,
                      inner: CGFloat = 18) -> CGPath {
        let path = CGMutablePath(), k: CGFloat = 0.5522847498307936
        for (r, direction) in [(outer, CGFloat(1)), (inner, CGFloat(-1))] {
            let x = center.x, y = center.y, s = direction
            path.move(to: CGPoint(x: x + r, y: y))
            path.addCurve(to: CGPoint(x: x, y: y + s*r), control1: CGPoint(x: x+r, y: y+s*k*r), control2: CGPoint(x: x+k*r, y: y+s*r))
            path.addCurve(to: CGPoint(x: x-r, y: y), control1: CGPoint(x: x-k*r, y: y+s*r), control2: CGPoint(x: x-r, y: y+s*k*r))
            path.addCurve(to: CGPoint(x: x, y: y-s*r), control1: CGPoint(x: x-r, y: y-s*k*r), control2: CGPoint(x: x-k*r, y: y-s*r))
            path.addCurve(to: CGPoint(x: x+r, y: y), control1: CGPoint(x: x+k*r, y: y-s*r), control2: CGPoint(x: x+r, y: y-s*k*r))
            path.closeSubpath()
        }
        return path
    }
    // Offscreen Core Graphics rasterization, independent of SketchRenderer/Canvas.
    static func mask(_ paths: [CGPath], size: Int = 140) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size*size*4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try required(CGContext(data: storage.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), "Cannot create offscreen bitmap")
            context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: 1, y: -1)
            context.setShouldAntialias(false); context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            for path in paths { context.addPath(path); context.fillPath() }
        }
        return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    }
    static func splitRectangle() throws {
        let controlPixels = try mask([CGPath(rect: CGRect(x: 20, y: 10, width: 10, height: 10), transform: nil)])
        try expect(controlPixels[15*140+25] == 255 && controlPixels[125*140+25] == 0, "Offscreen oracle does not use document top-left coordinates")
        var e = rectangle(CGRect(x: 10, y: 10, width: 100, height: 70))
        e.shadowed = true; e.groupID = UUID()
        let before = e
        let eraser = try required(VectorGeometry.eraserPath(points: [CGPoint(x: 60, y: 0), CGPoint(x: 60, y: 100)], width: 12), "Missing eraser")
        let fragments = try required(VectorGeometry.subtract(element: e, eraser: eraser), "Split returned no change")
        try expect(fragments.count == 2, "Full-height cut must create two editable components")
        try expect(Set(fragments.map(\.id)).count == 2, "Fragments share identity")
        try expect(fragments.allSatisfy { $0.id != e.id }, "Every erased fragment must receive a fresh ID, including the first")
        try expect(e == before, "Subtraction mutated source")
        try expect(fragments.allSatisfy { $0.kind == .path && $0.filled && $0.strokeWidth == 0 && $0.imagePNG == nil && $0.transform == .identity && $0.color == e.color && $0.shadowed && $0.groupID == e.groupID }, "Fragment geometry/style was flattened or lost")
        let paths = try fragments.map(painted)
        for point in [CGPoint(x: 30, y: 40), CGPoint(x: 90, y: 40)] {
            try expect(contains(paths, point), "Retained side missing at \(point)")
        }
        try expect(!contains(paths, CGPoint(x: 60, y: 40)), "Erase gap still painted")
        let pixels = try mask(paths)
        try expect(pixels[40*140+30] == 255 && pixels[40*140+90] == 255 && pixels[40*140+60] == 0, "Offscreen pixels disagree with split geometry")
        var document = SketchDocument(size: CGSize(width: 140, height: 140)); document.elements = fragments
        let loaded = try SketchDocument.decode(document.encoded())
        try expect(loaded == document, "Editable fragments fail exact document round trip")
        var moved = loaded.elements
        let index = try required(paths.firstIndex { $0.contains(CGPoint(x: 30, y: 40)) }, "Missing left fragment")
        moved[index].translate(x: 0, y: 50)
        let movedPaths = try moved.map(painted)
        try expect(!contains(movedPaths, CGPoint(x: 30, y: 40)) && contains(movedPaths, CGPoint(x: 30, y: 90)) && contains(movedPaths, CGPoint(x: 90, y: 40)), "Fragments cannot move independently after loading")
    }
    static func holesAndComponents() throws {
        let ring = donut()
        try expect(ring.contains(CGPoint(x: 90, y: 60)) && !ring.contains(CGPoint(x: 60, y: 60)), "Donut oracle is invalid")
        let components = VectorGeometry.components(of: ring)
        try expect(components.count == 1, "Hole became separate filled component")
        let result = try required(components.first, "Donut component missing")
        try expect(result.contains(CGPoint(x: 90, y: 60)) && !result.contains(CGPoint(x: 60, y: 60)), "Donut component lost hole winding")
        try expect(try mask([result]) == mask([ring]), "Component extraction changed donut pixels")
        let combined = CGMutablePath(); combined.addPath(ring)
        combined.addRect(CGRect(x: 115, y: 110, width: 15, height: 15))
        let separate = VectorGeometry.components(of: combined)
        try expect(separate.count == 2 && !contains(separate, CGPoint(x: 60, y: 60)) && contains(separate, CGPoint(x: 120, y: 115)), "Island/holed-component separation incorrect")
        let e = pathElement(rawCommands(ring)), cut = disk(CGPoint(x: 92, y: 60), 10)
        let fragments = try required(VectorGeometry.subtract(element: e, eraser: cut), "Ring bite ignored")
        try expect(fragments.count == 1, "Small bite incorrectly disconnected ring")
        try expect(fragments[0].id != e.id, "Single retained component reused the erased object's ID")
        let paths = try fragments.map(painted)
        try expect(!contains(paths, CGPoint(x: 60, y: 60)) && !contains(paths, CGPoint(x: 92, y: 60)) && contains(paths, CGPoint(x: 30, y: 60)), "Ring subtraction filled hole or lost retained paint")
    }
    static func commandRoundTrip() throws {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 2, y: 3)); p.addLine(to: CGPoint(x: 20, y: 3))
        p.addQuadCurve(to: CGPoint(x: 30, y: 25), control: CGPoint(x: 40, y: 5))
        p.addCurve(to: CGPoint(x: 2, y: 3), control1: CGPoint(x: 15, y: 50), control2: CGPoint(x: -5, y: 20)); p.closeSubpath()
        p.move(to: CGPoint(x: 80, y: 80)); p.addLine(to: CGPoint(x: 90, y: 90))
        let actual = VectorGeometry.commands(for: p), expected = rawCommands(p)
        try expect(actual == expected, "Command serialization lost controls, subpath or closure")
        let decoded = try SVGPathParser.makeCGPath(actual)
        try expect(rawCommands(decoded) == expected, "Serialized commands changed geometry")
    }
    static func transformedCurves() throws {
        let commands: [SVGPathCommand] = [.move(to: CGPoint(x: 10, y: 10)),
            .cubic(control1: CGPoint(x: 10, y: 70), control2: CGPoint(x: 70, y: 70), to: CGPoint(x: 70, y: 10)),
            .line(to: CGPoint(x: 10, y: 10)), .close]
        var e = pathElement(commands)
        let angle = CGFloat.pi / 5, sx: CGFloat = 1.4, sy: CGFloat = 0.65
        e.transform = SketchTransform(a: sx*cos(angle), b: sx*sin(angle), c: -sy*sin(angle), d: sy*cos(angle), tx: 45, ty: 8)
        var matrix = e.transform.cg
        let reference = try required(try SVGPathParser.makeCGPath(commands).copy(using: &matrix), "Cannot transform oracle")
        let actual = try painted(e)
        try expect(cubicCount(actual) > 0, "Filled transformed cubic was reduced to straight samples")
        try expect(try mask([actual]) == mask([reference]), "Filled cubic geometry changed under affine transform")
        let world = VectorGeometry.element(path: actual, style: e)
        try expect(world.kind == .path && world.transform == .identity && world.filled && world.strokeWidth == 0 && world.id != e.id, "World conversion is not an independent filled editable path")
        try expect(world.pathCommands == rawCommands(actual), "World conversion changed the absolute curve commands")
        var doc = SketchDocument(size: CGSize(width: 200, height: 160)); doc.elements = [world]
        try expect(try SketchDocument.decode(doc.encoded()).elements[0] == world, "Transformed controls fail document round trip")
        let eraser = disk(e.transform.applying(CGPoint(x: 65, y: 20)), 12)
        let pieces = try required(VectorGeometry.subtract(element: e, eraser: eraser), "Transformed cubic erasure ignored")
        let paths = try pieces.map(painted)
        try expect(paths.contains { cubicCount($0) > 0 }, "Boolean subtraction flattened every curved edge")
        for local in [CGPoint(x: 20, y: 20), CGPoint(x: 35, y: 30), CGPoint(x: 50, y: 20)] {
            let p = e.transform.applying(local)
            try expect(contains(paths, p) == (reference.contains(p) && !eraser.contains(p)), "Transformed cubic retained paint incorrect at \(p)")
        }
    }
    static func transformedEllipse() throws {
        var e = rectangle(CGRect(x: 15, y: 20, width: 60, height: 40)); e.kind = .ellipse
        let angle = CGFloat.pi / 6
        e.transform = SketchTransform(a: 1.5*cos(angle), b: 1.5*sin(angle), c: -0.6*sin(angle), d: 0.6*cos(angle), tx: 45, ty: 5)
        let path = try painted(e)
        try expect(cubicCount(path) >= 4, "Transformed ellipse lost curved geometry")
        for p in [CGPoint(x: 45, y: 40), CGPoint(x: 20, y: 40), CGPoint(x: 70, y: 40), CGPoint(x: 45, y: 25)] {
            try expect(path.contains(e.transform.applying(p)), "Scaled/rotated ellipse lost interior")
        }
        for p in [CGPoint(x: 10, y: 40), CGPoint(x: 80, y: 40), CGPoint(x: 45, y: 15), CGPoint(x: 45, y: 65)] {
            try expect(!path.contains(e.transform.applying(p)), "Scaled/rotated ellipse paints outside actual geometry")
        }
    }
    static func transformedStroke() throws {
        var line = SketchElement(kind: .line)
        line.points = [CGPoint(x: 20, y: 40), CGPoint(x: 80, y: 40)]; line.strokeWidth = 10
        line.transform = SketchTransform(a: 0, b: 2, c: -0.5, d: 0, tx: 70, ty: 5)
        let area = try painted(line)
        try expect(area.contains(CGPoint(x: 52, y: 100)) && !area.contains(CGPoint(x: 53, y: 100)), "Nonuniform transform did not scale local stroke thickness")
        try expect(area.contains(CGPoint(x: 50, y: 36)) && !area.contains(CGPoint(x: 50, y: 34)), "Transformed round cap extent incorrect")
        let curve = CGMutablePath(); curve.move(to: CGPoint(x: 20, y: 20))
        curve.addCurve(to: CGPoint(x: 100, y: 100), control1: CGPoint(x: 20, y: 100), control2: CGPoint(x: 100, y: 20))
        var e = pathElement(rawCommands(curve)); e.filled = false; e.strokeWidth = 8
        e.transform = SketchTransform(a: 0.8, b: 0.25, c: -0.1, d: 0.7, tx: 20, ty: 10)
        var t = e.transform.cg
        let reference = try required(curve.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 10).copy(using: &t), "Stroked cubic oracle transform failed")
        let actual = try painted(e)
        try expect(cubicCount(actual) > 0, "Transformed stroked cubic was flattened")
        let expectedPixels = try mask([reference]), actualPixels = try mask([actual])
        let ink = expectedPixels.filter { $0 != 0 }.count
        let mismatch = zip(expectedPixels, actualPixels).filter { $0 != $1 }.count
        try expect(ink > 200 && mismatch <= max(4, ink / 200), "Transformed stroked cubic pixels differ: \(mismatch) of \(ink) painted pixels")
    }
    static func strokeAndArrow() throws {
        var line = SketchElement(kind: .line)
        line.points = [CGPoint(x: 20, y: 40), CGPoint(x: 100, y: 40)]; line.strokeWidth = 10
        let stroke = try painted(line)
        try expect(stroke.contains(CGPoint(x: 60, y: 44)) && !stroke.contains(CGPoint(x: 60, y: 46)), "Stroke width is not actual diameter")
        try expect(stroke.contains(CGPoint(x: 16, y: 40)) && !stroke.contains(CGPoint(x: 14, y: 40)), "Line cap is not round/finite")
        var arrow = line; arrow.kind = .arrow; arrow.strokeWidth = 4
        let head = try painted(arrow)
        try expect(head.contains(CGPoint(x: 87, y: 45)) && !head.contains(CGPoint(x: 87, y: 49)), "Arrowhead paint area omitted or oversized")
        let fragments = try required(VectorGeometry.subtract(element: arrow, eraser: disk(CGPoint(x: 87, y: 45), 4)), "Eraser cannot touch arrowhead independently of shaft")
        let paths = try fragments.map(painted)
        try expect(!contains(paths, CGPoint(x: 87, y: 45)) && contains(paths, CGPoint(x: 50, y: 40)), "Arrowhead erase damaged shaft or failed to erase")
        var brush = line; brush.kind = .brush; brush.points = [CGPoint(x: 60, y: 60)]
        let dot = try painted(brush)
        try expect(dot.contains(CGPoint(x: 64, y: 60)) && !dot.contains(CGPoint(x: 66, y: 60)), "Single-point brush is not a diameter-width disk")
    }
    static func eraserCaps() throws {
        let path = try required(VectorGeometry.eraserPath(points: [CGPoint(x: 30, y: 40), CGPoint(x: 90, y: 40)], width: 12), "Missing swept eraser")
        try expect(near(path.boundingBoxOfPath.minX, 24) && near(path.boundingBoxOfPath.maxX, 96) && near(path.boundingBoxOfPath.height, 12), "Eraser bounds inflate width or omit round caps")
        for p in [CGPoint(x: 25, y: 40), CGPoint(x: 95, y: 40), CGPoint(x: 60, y: 45)] { try expect(path.contains(p), "Round eraser missing expected interior") }
        for p in [CGPoint(x: 25, y: 45), CGPoint(x: 95, y: 45), CGPoint(x: 60, y: 47)] { try expect(!path.contains(p), "Eraser has square caps or wrong diameter") }
        let dot = try required(VectorGeometry.eraserPath(points: [CGPoint(x: 60, y: 60)], width: 12), "Missing single point eraser")
        try expect(dot.contains(CGPoint(x: 65, y: 60)) && !dot.contains(CGPoint(x: 65, y: 65)), "Single-point eraser is not circular")
        let duplicate = try required(VectorGeometry.eraserPath(points: [CGPoint(x: 60, y: 60), CGPoint(x: 60, y: 60)], width: 12), "Repeated-point eraser rejected")
        try expect(try mask([dot]) == mask([duplicate]), "Repeated points change eraser footprint")
    }
    static func noChangeAndProtection() throws {
        var e = rectangle(CGRect(x: 20, y: 20, width: 50, height: 40)); e.shadowed = true; e.groupID = UUID()
        e.transform = .translation(x: 5, y: 4)
        let original = e
        try expect(VectorGeometry.subtract(element: e, eraser: disk(CGPoint(x: 120, y: 120), 10)) == nil, "Disjoint erase must report no change")
        try expect(e == original, "No-change path modified identity/style/transform")
        let all = CGPath(rect: CGRect(x: -100, y: -100, width: 400, height: 400), transform: nil)
        try expect(VectorGeometry.subtract(element: e, eraser: all)?.isEmpty == true, "Complete erasure must return []")
        for kind in [SketchElement.Kind.text, .raster] {
            var protected = SketchElement(kind: kind); protected.rect = e.rect
            protected.text = "Protected"; protected.imagePNG = Data([1, 2, 3])
            let saved = protected
            try expect(VectorGeometry.paintedPath(for: protected) == nil && VectorGeometry.subtract(element: protected, eraser: all) == nil && protected == saved, "Text/raster was modified")
        }
    }
    static func boundsOnlyReconstruction() throws {
        var outline = rectangle(CGRect(x: 20, y: 20, width: 80, height: 80), filled: false, group: UUID())
        outline.shadowed = true; outline.transform = .translation(x: 5, y: 3)
        var diagonal = SketchElement(kind: .line)
        diagonal.points = [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 100)]
        diagonal.strokeWidth = 4; diagonal.groupID = UUID(); diagonal.shadowed = true
        diagonal.color = outline.color
        let fixtures = [(outline, disk(CGPoint(x: 65, y: 63), 12)),
                        (diagonal, disk(CGPoint(x: 35, y: 85), 8))]
        for (source, eraser) in fixtures {
            let sourcePath = try painted(source)
            let beforePixels = try mask([sourcePath]), eraserPixels = try mask([eraser])
            try expect(sourcePath.boundingBoxOfPath.intersects(eraser.boundingBoxOfPath), "Bounds-only oracle does not have overlapping bounds")
            try expect(!zip(beforePixels, eraserPixels).contains { $0 != 0 && $1 != 0 }, "Bounds-only oracle accidentally overlaps actual paint")
            let fragments = try required(VectorGeometry.subtract(element: source, eraser: eraser), "Bounds-overlap erase must reconstruct even without paint intersection")
            try expect(fragments.count == 1 && fragments[0].id != source.id, "Bounds-only reconstruction must produce a fresh component ID")
            let result = fragments[0]
            try expect(result.kind == .path && result.filled && result.strokeWidth == 0 && result.transform == .identity && result.imagePNG == nil, "Bounds-only reconstruction is not an editable world-space filled path")
            try expect(result.color == source.color && result.shadowed == source.shadowed && result.groupID == source.groupID, "Bounds-only reconstruction lost style or pre-regroup group")
            try expect(try mask(fragments.map(painted)) == beforePixels, "Bounds-only reconstruction changed the painted footprint")
            var document = SketchDocument(size: CGSize(width: 140, height: 140)); document.elements = fragments
            try expect(try SketchDocument.decode(document.encoded()) == document, "Bounds-only reconstruction fails editable document round trip")
        }
    }
    static func styleConversion() throws {
        var style = rectangle(CGRect(x: 10, y: 20, width: 30, height: 40), group: UUID())
        style.shadowed = true; style.transform = .translation(x: 50, y: 60)
        let world = CGPath(rect: CGRect(x: 80, y: 90, width: 20, height: 15), transform: nil)
        let fresh = VectorGeometry.element(path: world, style: style)
        let retained = VectorGeometry.element(path: world, style: style, retainID: true)
        try expect(fresh.id != style.id && retained.id == style.id, "retainID contract incorrect")
        try expect(fresh.kind == .path && fresh.transform == .identity && fresh.filled && fresh.strokeWidth == 0 && fresh.color == style.color && fresh.shadowed == style.shadowed && fresh.groupID == style.groupID, "Conversion loses style or reapplies transform")
        let path = try painted(fresh)
        try expect(path.contains(CGPoint(x: 90, y: 97)) && !path.contains(CGPoint(x: 140, y: 157)), "World coordinates transformed twice")
    }
    static func regroupConnectivity() throws {
        let group = UUID(), untouched = UUID()
        let a = rectangle(CGRect(x: 10, y: 10, width: 20, height: 20), group: group)
        let b = rectangle(CGRect(x: 25, y: 10, width: 20, height: 20), group: group)
        let c = rectangle(CGRect(x: 40, y: 10, width: 20, height: 20), group: group)
        let distant = rectangle(CGRect(x: 100, y: 100, width: 15, height: 15), group: group)
        let ungrouped = rectangle(CGRect(x: 15, y: 15, width: 10, height: 10))
        let untouchedElement = rectangle(CGRect(x: 80, y: 10, width: 10, height: 10), group: untouched)
        let input = [a, b, c, distant, ungrouped, untouchedElement]
        let result = VectorGeometry.regroup(elements: input, affectedGroups: [group])
        try expect(result.map(\.id) == input.map(\.id), "Regroup changed layer order/identity")
        try expect(result[0].groupID != nil && result[0].groupID == result[1].groupID && result[1].groupID == result[2].groupID, "Overlap connectivity is not transitive")
        try expect(result[0].groupID != group, "Connected fragments must receive a fresh group ID")
        try expect(result[3].groupID == nil, "Detached singleton must be ungrouped")
        try expect(result[4] == ungrouped && result[5] == untouchedElement, "Regroup changed ungrouped/unaffected element")
        for (original, updated) in zip(input, result) {
            var allowed = original; allowed.groupID = updated.groupID
            try expect(allowed == updated, "Regroup changed geometry/style beyond groupID")
        }
        try expect(VectorGeometry.regroup(elements: input, affectedGroups: []) == input, "Empty affected groups must be exact no-op")
        let singleCluster = VectorGeometry.regroup(elements: [a, b, c], affectedGroups: [group])
        try expect(singleCluster[0].groupID != nil && singleCluster[0].groupID != group && singleCluster.allSatisfy { $0.groupID == singleCluster[0].groupID }, "A sole connected cluster must also receive a fresh group ID")
    }
    static func regroupProtectedLayers() throws {
        let oldGroup = UUID()
        let a = rectangle(CGRect(x: 10, y: 10, width: 25, height: 25), group: oldGroup)
        let b = rectangle(CGRect(x: 25, y: 10, width: 25, height: 25), group: oldGroup)
        let c = rectangle(CGRect(x: 90, y: 10, width: 25, height: 25), group: oldGroup)
        let d = rectangle(CGRect(x: 105, y: 10, width: 25, height: 25), group: oldGroup)
        let singleton = rectangle(CGRect(x: 60, y: 90, width: 10, height: 10), group: oldGroup)
        var text = SketchElement(kind: .text)
        text.rect = CGRect(x: 0, y: 0, width: 140, height: 100); text.text = "Protected bridge"
        text.groupID = oldGroup; text.shadowed = true; text.transform = .translation(x: 3, y: 4)
        var raster = SketchElement(kind: .raster)
        raster.rect = text.rect; raster.imagePNG = Data([1, 2, 3]); raster.groupID = oldGroup
        let ungrouped = rectangle(CGRect(x: 20, y: 10, width: 100, height: 10))
        // Interleave components and protected objects to catch accidental reordering.
        let input = [a, c, text, b, ungrouped, singleton, d, raster]
        let result = VectorGeometry.regroup(elements: input, affectedGroups: [oldGroup])
        try expect(result.map(\.id) == input.map(\.id), "Regroup changed relative layer order or element IDs")
        let left = result[0].groupID, right = result[1].groupID
        try expect(left != nil && right != nil && left != right && left != oldGroup && right != oldGroup, "Disconnected multi-fragment components require distinct fresh group IDs")
        try expect(result[3].groupID == left && result[6].groupID == right, "Connected fragments did not retain component membership")
        try expect(result[5].groupID == nil, "Independent singleton retained a group")
        try expect(result[2] == text && result[7] == raster && result[4] == ungrouped, "Protected old groups or ungrouped layer were modified")
        for (original, updated) in zip(input, result) {
            var allowed = original; allowed.groupID = updated.groupID
            try expect(allowed == updated, "Regroup changed style, identity, geometry or image data")
        }
        try expect(VectorGeometry.regroup(elements: [text, raster], affectedGroups: [oldGroup]) == [text, raster], "A protected-only group must retain exact old IDs and styles")
    }
    static func regroupPaintNotBounds() throws {
        let group = UUID()
        var ring = rectangle(CGRect(x: 10, y: 10, width: 100, height: 100), filled: false, group: group)
        ring.strokeWidth = 4
        let center = rectangle(CGRect(x: 45, y: 45, width: 20, height: 20), group: group)
        let separate = VectorGeometry.regroup(elements: [ring, center], affectedGroups: [group])
        try expect(separate.count == 2 && separate.allSatisfy { $0.groupID == nil }, "Disjoint outline/center singletons must be ungrouped despite overlapping bounds")
        // Two diagonal strokes have intersecting bounds but parallel disjoint paint.
        var a = SketchElement(kind: .line); a.points = [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)]; a.strokeWidth = 2; a.groupID = group
        var b = a; b.id = UUID(); b.points = [CGPoint(x: 10, y: 30), CGPoint(x: 70, y: 90)]
        let lines = VectorGeometry.regroup(elements: [a, b], affectedGroups: [group])
        try expect(lines.allSatisfy { $0.groupID == nil }, "Parallel singleton strokes glued by bounding boxes")
        var crossing = b; crossing.points = [CGPoint(x: 10, y: 90), CGPoint(x: 90, y: 10)]
        let connected = VectorGeometry.regroup(elements: [a, crossing], affectedGroups: [group])
        try expect(connected[0].groupID != nil && connected[0].groupID == connected[1].groupID, "Actual crossing paint failed to glue")
        try expect(connected[0].groupID != group, "Crossing fragments reused the original group ID")
    }
    static func invalidGeometry() throws {
        for width in [CGFloat(0), -1, .nan, .infinity] {
            try expect(VectorGeometry.eraserPath(points: [CGPoint(x: 10, y: 10)], width: width) == nil, "Invalid eraser width accepted: \(width)")
        }
        try expect(VectorGeometry.eraserPath(points: [], width: 10) == nil, "Empty eraser accepted")
        try expect(VectorGeometry.eraserPath(points: [CGPoint(x: CGFloat.nan, y: 10)], width: 10) == nil, "Nonfinite eraser coordinate accepted")
        var badRect = rectangle(CGRect(x: 0, y: 0, width: 30, height: 30)); badRect.rect.origin.x = .infinity
        var badTransform = rectangle(CGRect(x: 0, y: 0, width: 30, height: 30)); badTransform.transform.a = .nan
        var badStroke = rectangle(CGRect(x: 0, y: 0, width: 30, height: 30)); badStroke.strokeWidth = .nan
        let emptyPath = pathElement([])
        let badPath = pathElement([.move(to: .zero), .cubic(control1: CGPoint(x: CGFloat.nan, y: 1), control2: CGPoint(x: 2, y: 3), to: CGPoint(x: 4, y: 5)), .close])
        for e in [badRect, badTransform, badStroke, emptyPath, badPath] {
            try expect(VectorGeometry.paintedPath(for: e) == nil, "Malformed \(e.kind) painted instead of rejected")
            try expect(VectorGeometry.subtract(element: e, eraser: disk(CGPoint(x: 10, y: 10), 10)) == nil, "Malformed element produced erase fragments")
        }
        try expect(VectorGeometry.components(of: CGMutablePath()).isEmpty, "Empty path has connected components")
        try expect(VectorGeometry.commands(for: CGMutablePath()).isEmpty, "Empty path has commands")
    }
    static func main() {
        let cases: [(String, () throws -> Void)] = [
            ("rectangle splits into independently movable document vectors", splitRectangle),
            ("donut holes remain in their connected component", holesAndComponents),
            ("commands preserve exact cubic/quadratic controls and subpaths", commandRoundTrip),
            ("rotated nonuniformly scaled cubic remains editable after erasure", transformedCurves),
            ("rotated nonuniformly scaled ellipse preserves actual paint", transformedEllipse),
            ("affine transforms preserve stroke thickness, caps and cubic paint", transformedStroke),
            ("stroke, arrowhead and single-point brush paint", strokeAndArrow),
            ("eraser diameter and circular swept caps", eraserCaps),
            ("no-change identity, full erasure and text/raster protection", noChangeAndProtection),
            ("bounds-only overlap reconstructs fresh equivalent painted components", boundsOnlyReconstruction),
            ("style conversion retains world coordinates and optional identity", styleConversion),
            ("regroup preserves layers and transitive connectivity", regroupConnectivity),
            ("fresh component groups preserve interleaved protected layers", regroupProtectedLayers),
            ("regroup tests painted overlap rather than bounding boxes", regroupPaintNotBounds),
            ("malformed and nonfinite geometry is safely rejected", invalidGeometry)
        ]
        var failures = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("VectorGeometryTests: \(cases.count - failures)/\(cases.count) cases passed; pure geometry/offscreen pixels, no UI input")
        if failures > 0 { exit(1) }
    }
}
#endif
