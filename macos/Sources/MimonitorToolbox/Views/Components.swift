import SwiftUI
import AppKit

// MARK: - 主题色
//
// 不要用 Color(nsColor: .controlColor) 这类语义色。它们的求值会走 macOS 的 CoreUI
// 主题系统（CUICoreThemeRenderer::CopyMeasurementsForRendition），内部是字符串哈希
// 查找；卡片和按钮一多，每次重绘要查几十上百次，足以让切页卡好几秒。
// 用 Color.primary 叠加透明度代替：同样是浅灰/浅白，但完全由 SwiftUI 解析，开销可忽略。

enum Theme {
    static let accent = adaptive(NSColor(srgbRed: 0.19, green: 0.35, blue: 0.98, alpha: 1),
                                 NSColor(srgbRed: 0.49, green: 0.63, blue: 1, alpha: 1))
    static let onAccent = adaptive(.white, NSColor(srgbRed: 0.06, green: 0.09, blue: 0.17, alpha: 1))
    static let success = adaptive(NSColor(srgbRed: 0.07, green: 0.43, blue: 0.27, alpha: 1),
                                  NSColor(srgbRed: 0.38, green: 0.84, blue: 0.64, alpha: 1))
    static let warning = adaptive(NSColor(srgbRed: 0.65, green: 0.28, blue: 0.07, alpha: 1),
                                  NSColor(srgbRed: 1, green: 0.68, blue: 0.36, alpha: 1))
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    static let canvas = adaptive(NSColor(srgbRed: 0.967, green: 0.976, blue: 0.989, alpha: 1),
                                 NSColor(srgbRed: 0.075, green: 0.087, blue: 0.12, alpha: 1))
    static let card = adaptive(.white, NSColor(srgbRed: 0.115, green: 0.13, blue: 0.17, alpha: 1))
    static let control = adaptive(NSColor(srgbRed: 0.934, green: 0.948, blue: 0.975, alpha: 1),
                                  NSColor(srgbRed: 0.17, green: 0.19, blue: 0.25, alpha: 1))
    static let stroke = adaptive(NSColor(srgbRed: 0.84, green: 0.88, blue: 0.94, alpha: 1),
                                 NSColor(srgbRed: 0.25, green: 0.29, blue: 0.37, alpha: 1))
    static let secondaryText = adaptive(NSColor(srgbRed: 0.32, green: 0.38, blue: 0.48, alpha: 1),
                                       NSColor(srgbRed: 0.7, green: 0.76, blue: 0.86, alpha: 1))
}

/// Liquid Glass is reserved for floating navigation and control surfaces.
/// Text-heavy parameter groups retain opaque backgrounds.
private struct ToolboxGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.stroke.opacity(0.7)))
        }
    }
}

struct ToolboxActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.control : Theme.card,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke.opacity(0.8)))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct ToolboxActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if prominent {
            if #available(macOS 26.0, *), !reduceTransparency {
                content.controlSize(.large).buttonStyle(.glassProminent)
            } else { content.controlSize(.large).buttonStyle(.borderedProminent) }
        } else { content.buttonStyle(ToolboxActionStyle()) }
    }
}

extension View {
    func toolboxGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(ToolboxGlassSurface(cornerRadius: cornerRadius))
    }
    func toolboxAction(prominent: Bool = false) -> some View {
        modifier(ToolboxActionModifier(prominent: prominent))
    }
}

struct ToolboxGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else { content }
    }
}

/// A small, interruptible response shared by the screen controls and navigation.
struct ControlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - 页面刷新时的 loading 遮罩（对应原版 _show_loading_overlay）

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.10)
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text("正在刷新数据...").font(.callout).foregroundColor(.secondary)
                    }
                    .padding(22)
                    // 用系统材质：自动适配浅色/深色模式，也是 macOS 上浮层的惯用做法。
                    // 卡片本身不大，模糊合成的开销可以接受（之前性能问题出在整页遮罩上）。
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading))
    }
}

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke.opacity(0.65), lineWidth: 1))
    }
}

// MARK: - 可选中按钮（对应 ToggleButton）

struct SelectableButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(minWidth: 56)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Theme.control)
                .foregroundColor(isSelected ? Theme.onAccent : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 选项按钮组（对应 _btn_section）

struct ButtonGroupSection: View {
    let title: String
    let options: [Option]
    let selectedValue: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(options) { opt in
                    SelectableButton(title: opt.label,
                                     isSelected: opt.value == selectedValue) {
                        onSelect(opt.value)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 轻量滑条
//
// 不用 SwiftUI 的 Slider：它底层是 AppKit 的 NSSlider，每创建一个都要向 CoreUI
// 主题系统解析 rendition（字符串哈希查找）。实测画面页 6 个滑条要 500ms，
// 切页时肉眼可见地卡。自绘一个纯 SwiftUI 的滑条，创建开销可以忽略。

struct FastSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: (Double) -> Void

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 17
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = geo.size.height
            let span = range.upperBound - range.lowerBound
            let ratio = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = min(max(ratio, 0), 1)
            let knobX = clamped * (width - knobSize) + knobSize / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: clamped * width, height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .position(x: knobX, y: height / 2)
            }
            .frame(height: height)
            // 整条轨道都要能接收拖拽，而不只是滑块本身
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = min(max(g.location.x, 0), width)
                        var v = range.lowerBound + (x / width) * span
                        if step > 0 { v = (v / step).rounded() * step }
                        let clampedV = min(max(v, range.lowerBound), range.upperBound)
                        if clampedV != value { value = clampedV }
                    }
                    .onEnded { _ in onCommit(value) }
            )
        }
        .frame(height: 28)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("调节数值")
        .accessibilityValue(String(format: "%g", value))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = step > 0 ? step : 1
            switch direction {
            case .increment: value = min(value + delta, range.upperBound)
            case .decrement: value = max(value - delta, range.lowerBound)
            @unknown default: return
            }
            onCommit(value)
        }
    }
}

// MARK: - 滑条行（对应 _add_slider，松手提交）

struct SliderRow: View {
    let title: String
    let range: ClosedRange<Double>
    let externalValue: Int
    let onCommit: (Int) -> Void

    @State private var value: Double

    init(title: String,
         range: ClosedRange<Double>,
         externalValue: Int,
         onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.externalValue = externalValue
        self.onCommit = onCommit
        self._value = State(initialValue: Double(externalValue))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 96, alignment: .leading)
            FastSlider(value: $value, range: range, step: 1) { v in
                onCommit(Int(v))
            }
            .accessibilityLabel(title)
            Text("\(Int(value))")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        // 和按钮组一样套一层卡片：原版每个滑条也是独立的 SimpleCardWidget
        // （pages.py:_add_slider）。这样滑条标签才能和「画面模式」「色温」的
        // 标题左边对齐，视觉上落在同一条竖线上。
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: externalValue) { newValue in
            value = Double(newValue)
        }
    }
}

// MARK: - 页面标题栏 + 刷新按钮

struct PageHeader: View {
    let title: String
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 23, weight: .semibold))
            Spacer()
            Button(action: onRefresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }.toolboxAction()
        }
    }
}
