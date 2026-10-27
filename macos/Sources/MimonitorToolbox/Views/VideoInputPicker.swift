import SwiftUI
import ToolboxDomain

/// Both entry points use the same domain values and native button interaction.
struct VideoInputPicker: View {
    let selectedValue: Int
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolboxPreviewAccessibility) private var preview

    var body: some View {
        HStack(spacing: 10) {
            ForEach(OptionLists.source) { option in
                let selected = selectedValue == option.value
                Button { onSelect(option.value) } label: {
                    HStack(spacing: 10) {
                        VideoPortIcon(kind: option.label == "DP" ? .displayPort : option.label == "USB-C" ? .usbC : .hdmi)
                            .frame(width: 29, height: 18)
                            .accessibilityHidden(true)
                        Text(option.label).lineLimit(1)
                        Spacer(minLength: 0)
                        ToolboxSymbolImage(name: selected ? "checkmark.circle.fill" : "circle",
                                           animated: !reduceMotion && !preview.reduceMotion,
                                           tint: selected ? .white : .labelColor)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 5).frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
                }
                .font(Theme.controlFont).controlSize(.large)
                .modifier(ToolboxSelectionButtonSurface(selected: selected))
                .accessibilityLabel(option.label == "DP" ? "DisplayPort" : option.label)
                .accessibilityValue(selected ? "当前输入" : "未选中")
                .help("切换至 \(option.label == "DP" ? "DisplayPort" : option.label)")
            }
        }
    }
}

/// Front-facing sockets: HDMI's two shoulders, DisplayPort's one bevel, USB-C's oval.
/// These are symbols inside native buttons, not replacement controls.
struct VideoPortIcon: View {
    enum Kind { case hdmi, displayPort, usbC }
    let kind: Kind

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                if kind == .usbC {
                    Capsule().strokeBorder(lineWidth: 1.7)
                    Capsule().frame(width: w * 0.62, height: 2)
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 1))
                        path.addLine(to: CGPoint(x: kind == .displayPort ? w - 6 : w - 1, y: 1))
                        if kind == .displayPort {
                            path.addLine(to: CGPoint(x: w - 1, y: 6))
                            path.addLine(to: CGPoint(x: w - 1, y: h - 1))
                            path.addLine(to: CGPoint(x: 1, y: h - 1))
                        } else {
                            path.addLine(to: CGPoint(x: w - 1, y: h * 0.5))
                            path.addLine(to: CGPoint(x: w - 5, y: h - 1))
                            path.addLine(to: CGPoint(x: 5, y: h - 1))
                            path.addLine(to: CGPoint(x: 1, y: h * 0.5))
                        }
                        path.closeSubpath()
                    }.stroke(style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
                    HStack(spacing: 2.5) {
                        ForEach(0..<5) { _ in Capsule().frame(width: 1.3, height: 3) }
                    }
                }
            }
        }
    }
}
