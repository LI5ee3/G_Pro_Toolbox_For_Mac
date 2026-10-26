import SwiftUI
import ToolboxDomain

// Option/value API retained from YiHoooong/Mimonitor_Toolbox (upstream 56fa67e8d990a2dd8d7ebe1b6865d3b18928d08d).
/// Settings use the same native glass selection surface as the picture-mode buttons.
struct SegmentedOptionPicker: View {
    let options: [Option]
    let selectedValue: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button { onSelect(option.value) } label: {
                        Text(option.label).frame(maxWidth: .infinity)
                    }
                    .font(Theme.controlFont).controlSize(.large)
                    .modifier(ToolboxSelectionButtonSurface(selected: selectedValue == option.value))
                    .accessibilityLabel(option.label)
                    .accessibilityValue(selectedValue == option.value ? "已选择" : "未选择")
                    .accessibilityAddTraits(selectedValue == option.value ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
