// Offscreen rendering and process-scoped font registration only; no windows, no desktop input.
// Set OPENSKITCH_FA_FONT_DIR to a folder holding FontAwesome7Pro-{Regular,Solid}-subset.ttf to exercise the glyph branch.
// xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D FONTAWESOME_ICONS_TESTS Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift tests/FontAwesomeIconsTests.swift -o build/fontawesome-icons-tests
#if FONTAWESOME_ICONS_TESTS
import AppKit
import CoreText

@main
@MainActor
private enum FontAwesomeIconsTests {
    private static var checks = 0, skipped: [String] = []
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static let sizes: [CGFloat] = [14, 18, 20, 22, 24.4, 30]
    private static let toolArtwork = ["ToolOffCursor", "ToolOffBrush", "ToolOffLine", "ToolOffCircle", "ToolOffRect", "ToolOffFill", "ToolOffEraser", "ToolOffText", "ToolOffArrow"]
    private static let buildScriptArtwork = ["SnapCrosshair", "SnapISight", "Font", "ActualSizeToggleOff", "ActualSizeToggleOn", "Resize", "SaveToHistoryArrow", "Hide", "SnapSnap", "SnapCancel"]

    static func main() {
        _ = NSApplication.shared
        FontAwesomeFont.resetForTesting()
        table()
        withoutFonts()
        fallbackToArtwork()
        if let directory = ProcessInfo.processInfo.environment["OPENSKITCH_FA_FONT_DIR"], !directory.isEmpty {
            withFonts(URL(fileURLWithPath: directory, isDirectory: true))
        } else {
            skipped.append("glyph branch (OPENSKITCH_FA_FONT_DIR unset)")
        }
        let note = skipped.isEmpty ? "" : "; SKIPPED: " + skipped.joined(separator: ", ")
        print("FontAwesomeIconsTests: \(checks) checks passed (offscreen; no desktop input)\(note)")
    }

    // MARK: sources and files

    private static func searchRoots() -> [URL] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var roots = [here, here.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true)]
        var parent = here
        for _ in 0..<5 { roots.append(parent); parent = parent.deletingLastPathComponent() }
        return roots
    }

    private static func sourceText(_ name: String) -> String? {
        for root in searchRoots() {
            if let text = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) { return text }
        }
        return nil
    }

    private static func originalArtwork(_ name: String) -> URL? {
        for root in searchRoots() {
            let url = root.appendingPathComponent("original/Skitch.app/Contents/Resources/\(name).png")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func temporaryBundle(files: [URL]) -> (bundle: Bundle, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fa-icons-\(UUID().uuidString)", isDirectory: true)
        let resources = root.appendingPathComponent("Test.bundle/Contents/Resources", isDirectory: true)
        try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for file in files { try! FileManager.default.copyItem(at: file, to: resources.appendingPathComponent(file.lastPathComponent)) }
        return (Bundle(url: root.appendingPathComponent("Test.bundle"))!, root)
    }

    // MARK: raster helpers

    private static func raster(_ image: NSImage, scale: Int) -> (alpha: [UInt8], pixels: Int) {
        let pixels = Int(image.size.width) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        var alpha = [UInt8](repeating: 0, count: pixels * pixels)
        let data = rep.bitmapData!
        for y in 0..<pixels { for x in 0..<pixels { alpha[y * pixels + x] = data[y * rep.bytesPerRow + x * 4 + 3] } }
        return (alpha, pixels)
    }

    private static func inkBounds(_ alpha: [UInt8], _ pixels: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in 0..<pixels { for x in 0..<pixels where alpha[y * pixels + x] > 40 {
            if var b = box { b = (min(b.minX, x), max(b.maxX, x), min(b.minY, y), max(b.maxY, y)); box = b } else { box = (x, x, y, y) }
        } }
        return box
    }

    private static func coverage(_ alpha: [UInt8]) -> Int { alpha.reduce(0) { $0 + Int($1) } }

    private static func pngData(_ size: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: table

    private static func table() {
        expect(FAIcon.allCases.count == 26, "Icon table lists the 26 mapped controls")
        expect(Set(FAIcon.allCases.map(\.rawValue)).count == FAIcon.allCases.count, "Icon names are unique")
        expect(FAIcon.allCases.allSatisfy { $0.rawValue == $0.rawValue.lowercased() && !$0.rawValue.contains(" ") }, "Icon names are lowercase kebab-case")
        expect(FAIcon(rawValue: "eye-slash") == .eyeSlash && FAIcon(rawValue: "arrow-up-from-bracket") == .arrowUpFromBracket, "Raw values are the icons.yml keys")
        let codepoints = FAIcon.allCases.map(\.codepoint)
        expect(Set(codepoints).count == codepoints.count, "Every icon has its own codepoint")
        expect(FontAwesomeIcons.subsetUnicodes == Set(codepoints).sorted(), "subsetUnicodes is the sorted unique table")
        expect(FontAwesomeIcons.subsetUnicodes.count == FAIcon.allCases.count, "subsetUnicodes covers every icon exactly once")
        expect(FAIcon.slashForward.codepoint == 0x2F && FAIcon.eyeSlash.codepoint == 0xF070 && FAIcon.arrowUpFromBracket.codepoint == 0xE09A,
               "Spot-checked codepoints match icons.yml")
        expect(FAFamily.regular.postScriptName == "FontAwesome7Pro-Regular" && FAFamily.solid.postScriptName == "FontAwesome7Pro-Solid", "PostScript names")
        expect(FAFamily.allCases.map(\.resourceName) == ["FontAwesome7Pro-Regular-subset", "FontAwesome7Pro-Solid-subset"], "Resource names")
        expect(FAIcon.allCases.allSatisfy { NSImage(systemSymbolName: $0.sfSymbolFallback, accessibilityDescription: nil) != nil },
               "Every SF Symbol fallback exists on this host")

        guard let source = sourceText("FontAwesomeIcons.swift") else { skipped.append("fetch-script grep (FontAwesomeIcons.swift not found)"); return }
        let regex = try! NSRegularExpression(pattern: "0x[0-9A-Fa-f]{2,5}")
        let range = NSRange(source.startIndex..., in: source)
        let found = regex.matches(in: source, range: range).map { UInt32(String(source[Range($0.range, in: source)!]).dropFirst(2), radix: 16)! }
        expect(found.count == FontAwesomeIcons.subsetUnicodes.count, "The source holds exactly one hex literal per subset codepoint (found \(found.count))")
        expect(Set(found).sorted() == FontAwesomeIcons.subsetUnicodes, "Hex literals in the source are exactly subsetUnicodes")

        let script = "grep -oE '0x[0-9A-Fa-f]{2,5}' | sed 's/0x/U+/' | sort -u | paste -sd, -"
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", script]
        process.standardInput = input; process.standardOutput = output
        try! process.run()
        input.fileHandleForWriting.write(Data(source.utf8)); try! input.fileHandleForWriting.close()
        let line = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        let piped = line.split(separator: ",").map { UInt32($0.dropFirst(2), radix: 16)! }
        expect(process.terminationStatus == 0 && !line.isEmpty && piped.sorted() == FontAwesomeIcons.subsetUnicodes && line.hasPrefix("U+"),
               "The fetch-script pipeline produces the subset list from this file (\(line.prefix(40))…)")
    }

    // MARK: no fonts registered

    private static func withoutFonts() {
        for family in FAFamily.allCases {
            expect(!FontAwesomeFont.isAvailable(family) && FontAwesomeFont.font(family, pointSize: 22) == nil, "\(family) unavailable before registration")
            for icon in FAIcon.allCases {
                expect(!FontAwesomeIcons.glyphExists(icon, family: family), "\(icon) has no glyph without a font")
                expect(FontAwesomeIcons.image(icon, family: family, pointSize: 22) == nil, "\(icon) renders nothing without a font")
                let resolved = ChromeIcons.resolve(icon, family: family, pointSize: 22)
                expect(resolved.source == .sfSymbol(icon.sfSymbolFallback), "\(icon)/\(family) falls back to its SF Symbol")
                expect(resolved.image?.isTemplate == true && (resolved.image?.size.width ?? 0) > 0, "\(icon) SF fallback is a sized template image")
            }
        }
        let (empty, root) = temporaryBundle(files: [])
        expect(FontAwesomeFont.registerBundledFonts(bundle: empty).isEmpty && FontAwesomeFont.registerBundledFonts(bundle: .main).isEmpty,
               "Bundles without subset fonts register nothing")
        try? FileManager.default.removeItem(at: root)
        expect(!FontAwesomeFont.register(url: URL(fileURLWithPath: "/nonexistent/FontAwesome7Pro-Regular-subset.ttf"), family: .regular),
               "A missing font file does not register")
        expect(FontAwesomeIcons.glyphIndex(0x1F600, in: CTFontCreateWithName("Apple Color Emoji" as CFString, 20, nil)) != nil,
               "Supplementary-plane codepoints resolve through UTF-16")
        expect(FontAwesomeIcons.glyphIndex(0xD800, in: CTFontCreateWithName("Helvetica" as CFString, 20, nil)) == nil, "Surrogate scalars never resolve")
    }

    // MARK: classic artwork

    private static func fallbackToArtwork() {
        let (bundle, root) = temporaryBundle(files: [])
        let resources = bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try! pngData(24).write(to: resources.appendingPathComponent("ToolOffBrush.png"))
        let original = ChromeIcons.symbolName
        defer { ChromeIcons.symbolName = original; try? FileManager.default.removeItem(at: root) }

        expect(ChromeIcons.resolve(.paintbrush, classic: "ToolOffBrush", bundle: bundle).source == .sfSymbol("paintbrush"),
               "SF Symbol outranks classic artwork")
        ChromeIcons.symbolName = { _ in "no.such.symbol.anywhere" }
        let png = ChromeIcons.resolve(.paintbrush, classic: "ToolOffBrush", bundle: bundle)
        expect(png.source == .classicArtwork("ToolOffBrush"), "Classic artwork is used when FA and SF both miss")
        expect(png.image?.isTemplate == false && png.image?.size == NSSize(width: 24, height: 24),
               "Classic artwork keeps its original colors (not a template)")
        let missing = ChromeIcons.resolve(.paintbrush, classic: "NoSuchArtwork", bundle: bundle)
        expect(missing.source == .none && missing.image == nil, "A missing PNG falls through to text-only")
        let unnamed = ChromeIcons.resolve(.toolbox, bundle: bundle)
        expect(unnamed.source == .none && unnamed.image == nil, "Without classic artwork the chain ends at none")

        let buildScript = sourceText("tools/build.sh") ?? sourceText("../tools/build.sh")
        for icon in FAIcon.allCases {
            guard let name = ChromeIcons.classicArtworkName(for: icon) else { continue }
            expect(name.hasPrefix("ToolOff") ? toolArtwork.contains(name) : buildScriptArtwork.contains(name), "\(name) is artwork build.sh copies")
            if let buildScript, !name.hasPrefix("ToolOff") { expect(buildScript.contains(name), "tools/build.sh still copies \(name)") }
            if let url = originalArtwork(name) { expect(NSImage(contentsOf: url) != nil, "Recovered artwork \(name) decodes") }
            else if icon == .eyeSlash { skipped.append("original artwork lookup (original/Skitch.app not found)") }
        }
        expect(ChromeIcons.classicArtworkName(for: .toolbox) == nil && ChromeIcons.classicArtworkName(for: .cropSimple) == nil, "Icons without artwork map to nil")
    }

    // MARK: fonts registered

    private static func withFonts(_ directory: URL) {
        let regular = directory.appendingPathComponent("\(FAFamily.regular.resourceName).ttf")
        let solid = directory.appendingPathComponent("\(FAFamily.solid.resourceName).ttf")
        expect(FileManager.default.fileExists(atPath: regular.path) && FileManager.default.fileExists(atPath: solid.path), "Subset fonts exist in OPENSKITCH_FA_FONT_DIR")

        expect(!FontAwesomeFont.register(url: regular, family: .solid) && !FontAwesomeFont.isAvailable(.solid), "A font file under the wrong family is rejected")
        expect(FontAwesomeFont.register(url: regular, family: .regular) && FontAwesomeFont.isAvailable(.regular), "Regular subset registers")
        expect(FontAwesomeFont.register(url: regular, family: .regular), "Registering the same family again is a no-op success")
        expect(FontAwesomeFont.register(url: solid, family: .solid) && FontAwesomeFont.isAvailable(.solid), "Solid subset registers")
        for family in FAFamily.allCases {
            expect(FontAwesomeFont.font(family, pointSize: 22)?.fontName == family.postScriptName, "\(family) resolves to its PostScript name")
            expect(FontAwesomeFont.font(family, pointSize: 22)?.pointSize == 22, "\(family) honors the point size")
        }

        let (bundle, root) = temporaryBundle(files: [regular, solid])
        FontAwesomeFont.resetForTesting()
        expect(!FontAwesomeFont.isAvailable(.regular) && FontAwesomeFont.font(.regular, pointSize: 22) == nil, "Reset unregisters the fonts")
        expect(FontAwesomeFont.registerBundledFonts(bundle: .main).isEmpty, "Nothing registers from a bundle without fonts")
        let first = FontAwesomeFont.registerBundledFonts(bundle: bundle)
        let second = FontAwesomeFont.registerBundledFonts(bundle: bundle)
        expect(first == Set(FAFamily.allCases) && second == first, "registerBundledFonts registers both families and is idempotent")
        expect(FontAwesomeFont.registerBundledFonts(bundle: .main) == first, "Later calls keep the registered set")
        defer { FontAwesomeFont.resetForTesting(); try? FileManager.default.removeItem(at: root) }

        let charset = CTFontCopyCharacterSet(FontAwesomeFont.font(.regular, pointSize: 16)! as CTFont) as CharacterSet
        let covered = FontAwesomeIcons.subsetUnicodes.filter { charset.contains(Unicode.Scalar($0)!) }
        expect(covered == FontAwesomeIcons.subsetUnicodes, "The subset font covers every table codepoint")

        var coverageByFamily: [FAFamily: [FAIcon: Int]] = [.regular: [:], .solid: [:]]
        for family in FAFamily.allCases {
            for icon in FAIcon.allCases {
                expect(FontAwesomeIcons.glyphExists(icon, family: family), "\(icon) has a glyph in \(family)")
                let resolved = ChromeIcons.resolve(icon, family: family, pointSize: 22)
                expect(resolved.source == .fontAwesome(family) && resolved.image?.isTemplate == true, "\(icon)/\(family) resolves to its Font Awesome glyph")
                for size in sizes {
                    let image = FontAwesomeIcons.image(icon, family: family, pointSize: size)!
                    let side = ceil(size * 1.25)
                    expect(image.isTemplate && image.size == NSSize(width: side, height: side), "\(icon) at \(size) pt is a \(side) pt square template")
                }
                let (alpha, pixels) = raster(FontAwesomeIcons.image(icon, family: family, pointSize: 22)!, scale: 4)
                guard let ink = inkBounds(alpha, pixels) else { expect(false, "\(icon)/\(family) draws ink"); continue }
                coverageByFamily[family]![icon] = coverage(alpha)
                expect(ink.minX >= 0 && ink.minY >= 0 && ink.maxX < pixels && ink.maxY < pixels && ink.maxX - ink.minX > pixels / 8, "\(icon)/\(family) ink is visible and inside the canvas")
                let offset = max(abs(ink.minX + ink.maxX + 1 - pixels), abs(ink.minY + ink.maxY + 1 - pixels))
                expect(offset <= 2, "\(icon)/\(family) is optically centered (off by \(Double(offset) / 8) pt)")
            }
        }
        expect(coverageByFamily[.solid]![.circle]! > coverageByFamily[.regular]![.circle]! * 3 / 2, "Solid circle is filled where Regular is an outline")
        expect(coverageByFamily[.solid]![.square]! > coverageByFamily[.regular]![.square]! * 3 / 2, "Solid square is filled where Regular is an outline")
        expect(FontAwesomeIcons.image(.circle, family: .regular, pointSize: 0) == nil && FontAwesomeIcons.image(.circle, family: .regular, pointSize: -4) == nil, "Non-positive sizes render nothing")

        let original = ChromeIcons.symbolName
        ChromeIcons.symbolName = { _ in "no.such.symbol.anywhere" }
        defer { ChromeIcons.symbolName = original }
        expect(ChromeIcons.resolve(.camera, classic: "Missing", bundle: bundle).source == .fontAwesome(.regular), "Font Awesome outranks every fallback")
        expect(FontAwesomeIcons.glyphIndex(0x1F600, in: FontAwesomeFont.font(.regular, pointSize: 20)! as CTFont) == nil, "Codepoints outside the subset have no glyph")
    }
}
#endif
