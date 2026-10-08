import AppKit
import CoreText

/// Font Awesome Pro glyph table. The Pro fonts never live in this repository: tools/fetch-fontawesome.sh subsets
/// them to exactly the codepoints listed here by grepping this file for hex literals, so the codepoint switch
/// below must stay the only place they appear.
enum FAFamily: String, CaseIterable, Sendable {
    case regular, solid
    var postScriptName: String { self == .regular ? "FontAwesome7Pro-Regular" : "FontAwesome7Pro-Solid" }
    var resourceName: String { postScriptName + "-subset" }
}

enum FAIcon: String, CaseIterable, Sendable {
    case eyeSlash = "eye-slash", toolbox, images, floppyDisk = "floppy-disk", clockRotateLeft = "clock-rotate-left",
         arrowPointer = "arrow-pointer", paintbrush, slashForward = "slash-forward", circle, square, fillDrip = "fill-drip",
         eraser, text, arrowUpRight = "arrow-up-right", cropSimple = "crop-simple", crosshairs, frameViewfinder = "camera-viewfinder",
         xmark, font, arrowRotateLeft = "arrow-rotate-left", broom, maximize, minimize, rulerCombined = "ruler-combined",
         arrowUpFromBracket = "arrow-up-from-bracket"

    var codepoint: UInt32 {
        switch self {
        case .eyeSlash: return 0xF070
        case .toolbox: return 0xF552
        case .images: return 0xF302
        case .floppyDisk: return 0xF0C7
        case .clockRotateLeft: return 0xF1DA
        case .arrowPointer: return 0xF245
        case .paintbrush: return 0xF1FC
        case .slashForward: return 0x002F
        case .circle: return 0xF111
        case .square: return 0xF0C8
        case .fillDrip: return 0xF576
        case .eraser: return 0xF12D
        case .text: return 0xF893
        case .arrowUpRight: return 0xE09F
        case .cropSimple: return 0xF565
        case .crosshairs: return 0xF05B
        case .frameViewfinder: return 0xE0DA
        case .xmark: return 0xF00D
        case .font: return 0xF031
        case .arrowRotateLeft: return 0xF0E2
        case .broom: return 0xF51A
        case .maximize: return 0xF31E
        case .minimize: return 0xF78C
        case .rulerCombined: return 0xF546
        case .arrowUpFromBracket: return 0xE09A
        }
    }

    var sfSymbolFallback: String {
        switch self {
        case .eyeSlash: return "eye.slash"
        case .toolbox: return "wrench.and.screwdriver"
        case .images: return "photo.on.rectangle"
        case .floppyDisk: return "square.and.arrow.down"
        case .clockRotateLeft: return "clock.arrow.circlepath"
        case .arrowPointer: return "cursorarrow"
        case .paintbrush: return "paintbrush"
        case .slashForward: return "line.diagonal"
        case .circle: return "circle"
        case .square: return "square"
        case .fillDrip: return "drop.fill"
        case .eraser: return "eraser"
        case .text: return "textformat"
        case .arrowUpRight: return "arrow.up.right"
        case .cropSimple: return "crop"
        case .crosshairs: return "scope"
        case .frameViewfinder: return "viewfinder"
        case .xmark: return "xmark"
        case .font: return "textformat.size"
        case .arrowRotateLeft: return "arrow.uturn.backward"
        case .broom: return "clear"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .rulerCombined: return "ruler"
        case .arrowUpFromBracket: return "square.and.arrow.up"
        }
    }
}

/// Process-scoped registration of the bundled subset fonts. Only fonts registered here count as available,
/// so a Font Awesome install elsewhere on the machine never changes which icon branch ChromeIcons takes.
@MainActor
enum FontAwesomeFont {
    private static var registered: [FAFamily: URL] = [:]

    @discardableResult
    static func registerBundledFonts(bundle: Bundle = .main) -> Set<FAFamily> {
        for family in FAFamily.allCases where registered[family] == nil {
            if let url = bundle.url(forResource: family.resourceName, withExtension: "ttf") { register(url: url, family: family) }
        }
        return Set(registered.keys)
    }

    @discardableResult
    static func register(url: URL, family: FAFamily) -> Bool {
        if registered[family] != nil { return true }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        error?.release()
        guard NSFont(name: family.postScriptName, size: 12) != nil else {
            if ok { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
            return false
        }
        registered[family] = url
        return true
    }

    static func isAvailable(_ family: FAFamily) -> Bool { registered[family] != nil }

    static func font(_ family: FAFamily, pointSize: CGFloat) -> NSFont? {
        isAvailable(family) ? NSFont(name: family.postScriptName, size: pointSize) : nil
    }

    static func resetForTesting() {
        for url in registered.values { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        registered = [:]
    }
}

@MainActor
enum FontAwesomeIcons {
    private struct FontBox: @unchecked Sendable { let font: CTFont }

    static var subsetUnicodes: [UInt32] { Array(Set(FAIcon.allCases.map(\.codepoint))).sorted() }

    static func glyphExists(_ icon: FAIcon, family: FAFamily) -> Bool {
        guard let font = FontAwesomeFont.font(family, pointSize: 16) else { return false }
        return glyphIndex(icon.codepoint, in: font) != nil
    }

    /// Resolves through UTF-16 so supplementary-plane codepoints work too; CoreText stores a pair's glyph in slot zero.
    static func glyphIndex(_ codepoint: UInt32, in font: CTFont) -> CGGlyph? {
        guard let scalar = Unicode.Scalar(codepoint) else { return nil }
        let units = Array(String(Character(scalar)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    /// Template image on a square canvas of ceil(pointSize * 1.25), centered on the glyph's own outline bounds
    /// (not line metrics) so wide and short glyphs like the ruler or the slash sit at the visual center.
    /// The outline's tight box is preferred: CTFontGetBoundingRectsForGlyphs includes curve control points,
    /// which pushes round glyphs such as the undo arrow about a point off center.
    static func image(_ icon: FAIcon, family: FAFamily, pointSize: CGFloat) -> NSImage? {
        guard pointSize > 0, let nsFont = FontAwesomeFont.font(family, pointSize: pointSize) else { return nil }
        let font = nsFont as CTFont
        guard var glyph = glyphIndex(icon.codepoint, in: font) else { return nil }
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
        if let outline = CTFontCreatePathForGlyph(font, glyph, nil) { bounds = outline.boundingBoxOfPath }
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        let side = ceil(pointSize * 1.25)
        let origin = CGPoint(x: side / 2 - bounds.midX, y: side / 2 - bounds.midY)
        let box = FontBox(font: font), drawn = glyph
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            var glyph = drawn, position = origin
            CTFontDrawGlyphs(box.font, &glyph, &position, 1, context)
            return true
        }
        image.isTemplate = true
        return image
    }
}
