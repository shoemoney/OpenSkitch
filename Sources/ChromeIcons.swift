import AppKit

enum ChromeIconSource: Equatable { case fontAwesome(FAFamily), sfSymbol(String), none }

/// One icon, one fallback chain: Font Awesome glyph, then SF Symbol, then nothing.
@MainActor
enum ChromeIcons {
    struct Resolved { let image: NSImage?; let source: ChromeIconSource }

    /// Test seam: lets tests force the SF Symbol branch to miss.
    static var symbolName: (FAIcon) -> String = { $0.sfSymbolFallback }

    static func resolve(_ icon: FAIcon, family: FAFamily = .regular, pointSize: CGFloat = 22) -> Resolved {
        if let image = FontAwesomeIcons.image(icon, family: family, pointSize: pointSize) {
            return Resolved(image: image, source: .fontAwesome(family))
        }
        let name = symbolName(icon)
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) ?? symbol
            image.isTemplate = true
            return Resolved(image: image, source: .sfSymbol(name))
        }
        return Resolved(image: nil, source: .none)
    }
}
