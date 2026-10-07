#if TEXT_STYLE_FORM_TESTS
import AppKit

@main
struct TextStyleFormTests {
    static func main() {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        let form = TextStyleForm(outlined: nil, shadowed: nil)
        expect(form.outlineChoice == nil && form.shadowChoice == nil, "Mixed states preserve each annotation value")
        expect(form.outline.state == .mixed && form.shadowControl.state == .mixed, "Native controls display mixed selection")
        var outlines: [Bool] = [], shadows: [Bool] = [], defaults = 0
        form.onOutlineChange = { outlines.append($0) }; form.onShadowChange = { shadows.append($0) }; form.onDefaultRequested = { defaults += 1 }
        form.setChoices(outlined: true, shadowed: false)
        expect(form.outlineChoice == true && form.shadowChoice == false, "Uniform selection states")
        expect(outlines.isEmpty && shadows.isEmpty && defaults == 0, "Selection refresh does not send edit actions")
        form.outline.performClick(nil)
        expect(form.outlineChoice == false && outlines == [false], "Native click toggles outline off")
        form.outline.performClick(nil)
        expect(form.outlineChoice == true && outlines == [false,true], "Native click toggles outline on")
        form.setChoices(outlined: nil, shadowed: nil)
        form.outline.performClick(nil); form.shadowControl.performClick(nil)
        expect(form.outlineChoice == true && form.shadowChoice == true, "Clicking mixed original effect enables it")
        expect(outlines.last == true && shadows == [true], "Live mixed controls send explicit choices")
        form.shadowControl.performClick(nil)
        expect(form.shadowChoice == false && shadows == [true,false], "Shadow can be turned off after mixed selection")
        form.restoreDefault()
        expect(form.outlineChoice == true && form.shadowChoice == true && defaults == 1, "Default action enables both effects and routes one request")
        form.layoutSubtreeIfNeeded()
        for control in [form.outline,form.shadowControl,form.defaults] {
            expect((control.font?.pointSize ?? 0) >= 20, "Readable accessory text")
            expect(control.target === form && control.action != nil, "Every accessory control has a native action")
            expect(control.convert(control.bounds, to: form).maxY <= form.bounds.maxY + 1, "Accessory contains each control")
        }
        print("TextStyleFormTests: \(checks) checks passed (native accessory controls; no desktop input)")
    }
}
#endif
