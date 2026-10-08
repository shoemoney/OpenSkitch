import AppKit

enum ChromeIconSource: Equatable { case fontAwesome(FAFamily), sfSymbol(String), classicArtwork(String), none }

/// One icon, one fallback chain: Font Awesome glyph, then SF Symbol, then the recovered classic PNG, then nothing.
@MainActor
enum ChromeIcons {
    struct Resolved { let image: NSImage?; let source: ChromeIconSource }

    /// Test seam: lets tests force the SF Symbol branch to miss so the classic artwork branch is reachable.
    static var symbolName: (FAIcon) -> String = { $0.sfSymbolFallback }

    /// Recovered artwork names build.sh copies into the bundle; the Toolbox, Photos, History, Crop, Undo, Wipe and Share glyphs have none.
    static func classicArtworkName(for icon: FAIcon) -> String? {
        switch icon {
        case .eyeSlash: return "Hide"
        case .floppyDisk: return "SaveToHistoryArrow"
        case .arrowPointer: return "ToolOffCursor"
        case .paintbrush: return "ToolOffBrush"
        case .slashForward: return "ToolOffLine"
        case .circle: return "ToolOffCircle"
        case .square: return "ToolOffRect"
        case .fillDrip: return "ToolOffFill"
        case .eraser: return "ToolOffEraser"
        case .text: return "ToolOffText"
        case .arrowUpRight: return "ToolOffArrow"
        case .crosshairs: return "SnapCrosshair"
        case .frameViewfinder: return "SnapSnap"
        case .xmark: return "SnapCancel"
        case .font: return "Font"
        case .maximize: return "ActualSizeToggleOff"
        case .minimize: return "ActualSizeToggleOn"
        case .rulerCombined: return "Resize"
        case .toolbox, .images, .clockRotateLeft, .cropSimple, .arrowRotateLeft, .broom, .arrowUpFromBracket: return nil
        }
    }

    static func resolve(_ icon: FAIcon, family: FAFamily = .regular, pointSize: CGFloat = 22,
                        classic: String? = nil, bundle: Bundle = .main) -> Resolved {
        if let image = FontAwesomeIcons.image(icon, family: family, pointSize: pointSize) {
            return Resolved(image: image, source: .fontAwesome(family))
        }
        let name = symbolName(icon)
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) ?? symbol
            image.isTemplate = true
            return Resolved(image: image, source: .sfSymbol(name))
        }
        if let classic, let url = bundle.url(forResource: classic, withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return Resolved(image: image, source: .classicArtwork(classic))
        }
        return Resolved(image: nil, source: .none)
    }
}
