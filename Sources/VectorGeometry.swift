import AppKit

/// Boolean operations act on painted annotation areas in document coordinates.
/// Shadows, text and photographs are not pen geometry in the original engine.
enum VectorGeometry {
    static func paintedPath(for element: SketchElement) -> CGPath? {
        guard element.kind != .text, element.kind != .raster,
              element.strokeWidth.isFinite, element.strokeWidth >= 0, element.strokeWidth <= 4096 else { return nil }
        let path = CGMutablePath()
        let area: CGPath
        switch element.kind {
        case .path:
            guard let original = try? SVGPathParser.makeCGPath(element.pathCommands) else { return nil }
            area = element.filled ? original : original.copy(strokingWithWidth: element.strokeWidth,
                lineCap: .round, lineJoin: .round, miterLimit: 10)
        case .rectangle, .ellipse:
            let rect = element.rect.standardized
            guard rect.width > 0, rect.height > 0, finite(rect) else { return nil }
            if element.kind == .rectangle { path.addRect(rect) } else { path.addEllipse(in: rect) }
            let stroke = path.copy(strokingWithWidth: element.strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            area = element.filled ? path.union(stroke) : stroke
        case .line, .arrow, .brush:
            guard !element.points.isEmpty, element.points.allSatisfy(finite) else { return nil }
            if element.points.count == 1, let point = element.points.first {
                area = CGPath(ellipseIn: CGRect(x: point.x - element.strokeWidth/2, y: point.y - element.strokeWidth/2,
                    width: element.strokeWidth, height: element.strokeWidth), transform: nil)
            } else {
                path.move(to: element.points[0])
                for point in element.points.dropFirst() { path.addLine(to: point) }
                let stroke = path.copy(strokingWithWidth: element.strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
                if element.kind == .arrow, let end = element.points.last {
                    let start = element.points[element.points.count-2]
                    let angle = atan2(end.y-start.y, end.x-start.x)
                    let length = max(14, element.strokeWidth*4), halfWidth = max(6, element.strokeWidth*1.8)
                    let head = CGMutablePath(); head.move(to: end)
                    head.addLine(to: CGPoint(x: end.x-length*cos(angle)+halfWidth*sin(angle), y: end.y-length*sin(angle)-halfWidth*cos(angle)))
                    head.addLine(to: CGPoint(x: end.x-length*cos(angle)-halfWidth*sin(angle), y: end.y-length*sin(angle)+halfWidth*cos(angle)))
                    head.closeSubpath(); area = stroke.union(head)
                } else { area = stroke }
            }
        case .text, .raster: return nil
        }
        var transform = element.transform.cg
        guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({ $0.isFinite }),
              let absolute = area.copy(using: &transform), !absolute.isEmpty else { return nil }
        return absolute.normalized()
    }

    static func commands(for path: CGPath) -> [SVGPathCommand] {
        var commands: [SVGPathCommand] = []
        path.applyWithBlock { element in
            let item = element.pointee
            switch item.type {
            case .moveToPoint: commands.append(.move(to: item.points[0]))
            case .addLineToPoint: commands.append(.line(to: item.points[0]))
            case .addQuadCurveToPoint: commands.append(.quadratic(control: item.points[0], to: item.points[1]))
            case .addCurveToPoint: commands.append(.cubic(control1: item.points[0], control2: item.points[1], to: item.points[2]))
            case .closeSubpath: commands.append(.close)
            @unknown default: break
            }
        }
        return commands
    }

    static func components(of path: CGPath) -> [CGPath] {
        path.componentsSeparated().filter { !$0.isEmpty && $0.boundingBoxOfPath.width > 0.0000001 && $0.boundingBoxOfPath.height > 0.0000001 }
    }

    static func element(path: CGPath, style: SketchElement, retainID: Bool = false) -> SketchElement {
        var result = style
        if !retainID { result.id = UUID() }
        result.kind = .path; result.points = []; result.rect = path.boundingBoxOfPath
        result.pathCommands = commands(for: path); result.imagePNG = nil
        result.transform = .identity; result.filled = true; result.strokeWidth = 0
        return result
    }

    /// Width here is the actual mask diameter, independent of the tool's nib size.
    static func eraserPath(points: [CGPoint], width: CGFloat) -> CGPath? {
        guard !points.isEmpty, points.allSatisfy(finite), width.isFinite, width > 0, width <= 8192 else { return nil }
        let path = CGMutablePath(); path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        if points.allSatisfy({ $0 == points[0] }) {
            let p = points[0]
            return CGPath(ellipseIn: CGRect(x: p.x-width/2, y: p.y-width/2, width: width, height: width), transform: nil)
        }
        return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized()
    }

    /// nil means unchanged/protected, while an empty array means fully erased.
    static func subtract(element original: SketchElement, eraser: CGPath) -> [SketchElement]? {
        guard let source = paintedPath(for: original), source.boundingBoxOfPath.intersects(eraser.boundingBoxOfPath) else { return nil }
        let remaining = components(of: source.subtracting(eraser))
        return remaining.map { path in element(path: path, style: original) }
    }

    static func regroup(elements: [SketchElement], affectedGroups: Set<UUID>) -> [SketchElement] {
        var result = elements
        for group in affectedGroups {
            let indexes = result.indices.filter { result[$0].groupID == group && paintedPath(for: result[$0]) != nil }
            let paths = Dictionary(uniqueKeysWithValues: indexes.compactMap { index in paintedPath(for: result[index]).map { (index, $0) } })
            var unseen = Set(indexes), clusters: [[Int]] = []
            while let first = unseen.min() {
                unseen.remove(first); var cluster = [first], cursor = 0
                while cursor < cluster.count {
                    let index = cluster[cursor]; cursor += 1
                    guard let path = paths[index] else { continue }
                    for candidate in unseen.sorted() {
                        guard let other = paths[candidate], path.boundingBoxOfPath.intersects(other.boundingBoxOfPath), path.intersects(other) else { continue }
                        unseen.remove(candidate); cluster.append(candidate)
                    }
                }
                clusters.append(cluster)
            }
            for cluster in clusters {
                let id: UUID? = cluster.count > 1 ? UUID() : nil
                for index in cluster { result[index].groupID = id }
            }
        }
        return result
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite && abs(point.x) <= 1_000_000 && abs(point.y) <= 1_000_000 }
    private static func finite(_ rect: CGRect) -> Bool { finite(rect.origin) && rect.width.isFinite && rect.height.isFinite && rect.width <= 1_000_000 && rect.height <= 1_000_000 }
}
