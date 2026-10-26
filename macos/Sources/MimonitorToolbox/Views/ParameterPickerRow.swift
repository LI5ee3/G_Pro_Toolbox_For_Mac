import SwiftUI
import ToolboxDomain

/// A native choice row shared by the dense display, game and lighting pages.
struct ParameterPickerRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let options: [Option]
    let selectedValue: Int
    let onSelect: (Int) -> Void
    var labelWidth: CGFloat = Theme.parameterLabelWidth

    private var selection: Int { options.contains { $0.value == selectedValue } ? selectedValue : -1 }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.controlFont)
                .frame(width: labelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            ParameterMenu(title: title, options: options, selectedValue: selection,
                          isEnabled: isEnabled, onSelect: onSelect)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }
}

struct ParameterMenu: View {
    let title: String
    let options: [Option]
    let selectedValue: Int
    let isEnabled: Bool
    let onSelect: (Int) -> Void

    private var currentLabel: String {
        options.first { $0.value == selectedValue }?.label ?? "未知"
    }

    var selection: Binding<Int> {
        Binding(get: { selectedValue }, set: { value in
            guard isEnabled, options.contains(where: { $0.value == value }) else { return }
            onSelect(value)
        })
    }

    var body: some View {
        ToolboxGlassMenu(currentLabel, accessibilityLabel: title) {
            Picker(title, selection: selection) {
                if selectedValue == -1 { Text("未知").tag(-1).disabled(true) }
                ForEach(options) { option in Text(option.label).tag(option.value) }
            }
            .pickerStyle(.inline).labelsHidden()
        }
        .disabled(!isEnabled)
    }
}
