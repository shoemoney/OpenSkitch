#if TEXT_STYLE_FORM_TESTS
import AppKit

@main
struct TextStyleFormTests {
    static func main() {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        let font = NSFont(name: "Courier-Bold", size: 37)!
        let form = TextStyleForm(font: font, outlined: false, shadowed: false)
        expect(form.resolvedFont()?.fontName == "Courier-Bold", "Changing flags must retain the original bold face")
        expect(form.resolvedFont()?.pointSize == 37, "Preserve current size")
        form.size.stringValue = "48.5"
        expect(form.resolvedFont()?.pointSize == 48.5, "Fractional font sizes")
        form.restoreDefault()
        expect(form.resolvedFont()?.fontName == "Helvetica-Bold", "Recovered original displayed font")
        expect(form.resolvedFont()?.pointSize == 48.5, "Default Style preserves entered point size")
        expect(form.outline.state == .on && form.shadowControl.state == .on, "Default Style restores both visibility flags")
        form.family.stringValue = "Courier"
        expect(form.resolvedFont()?.familyName == "Courier", "Changing family resolves a supported installed font")
        form.family.stringValue = "NotAnInstalledFont-skitch-test"
        expect(form.resolvedFont() == nil, "Invalid family cannot silently replace a font")
        form.restoreDefault()
        for value in ["", "nan", "inf", "17", "4097", "word"] {
            form.size.stringValue = value; expect(form.resolvedFont() == nil, "Invalid size " + value)
        }
        for value in ["18", "4096"] {
            form.size.stringValue = value; expect(form.resolvedFont()?.pointSize == CGFloat(Double(value)!), "Supported size boundary")
        }
        for control in [form.family, form.size, form.outline, form.shadowControl, form.defaults] as [NSControl] {
            expect((control.font?.pointSize ?? 0) >= 20, "Readable custom controls")
        }
        form.layoutSubtreeIfNeeded()
        let stack = form.subviews[0] as! NSStackView
        for control in stack.arrangedSubviews { expect(control.frame.maxY <= form.bounds.height + 1, "Accessory contains every control") }
        print("TextStyleFormTests: \(checks) checks passed (native controls; no desktop input)")
    }
}
#endif
