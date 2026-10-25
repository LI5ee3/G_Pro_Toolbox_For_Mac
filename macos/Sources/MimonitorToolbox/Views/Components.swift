import ToolboxDomain
import ToolboxApplication
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
    static let canvas = adaptive(NSColor(white: 0.96, alpha: 1), NSColor(white: 0.10, alpha: 1))
    static let card = adaptive(.white, NSColor(white: 0.14, alpha: 1))
    static let control = adaptive(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.21, alpha: 1))
    static let stroke = adaptive(NSColor(white: 0.78, alpha: 1), NSColor(white: 0.36, alpha: 1))
    static let secondaryText = adaptive(NSColor(white: 0.38, alpha: 1), NSColor(white: 0.76, alpha: 1))
    static let sectionFont = Font.system(size: 14, weight: .semibold)
    static let parameterLabelWidth: CGFloat = 112
    static let controlRadius: CGFloat = 8
    static let sectionRadius: CGFloat = 12
}

// The SDK accessibility environment values are read-only. This package-only hook lets
// the safe Preview exercise the same rendering branches without changing system settings.
// Live hosts leave all overrides false and continue to use the system values.
package struct ToolboxPreviewAccessibility {
    package var reduceTransparency = false
    package var reduceMotion = false
    package var increasedContrast = false
    package init() {}
}

private struct ToolboxPreviewAccessibilityKey: EnvironmentKey {
    static let defaultValue = ToolboxPreviewAccessibility()
}

extension EnvironmentValues {
    package var toolboxPreviewAccessibility: ToolboxPreviewAccessibility {
        get { self[ToolboxPreviewAccessibilityKey.self] }
        set { self[ToolboxPreviewAccessibilityKey.self] = newValue }
    }
}

/// Liquid Glass is reserved for floating navigation and control surfaces.
/// Text-heavy parameter groups retain opaque backgrounds.
private struct ToolboxGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if !reduceTransparency && !preview.reduceTransparency && contrast != .increased && !preview.increasedContrast {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(contrast == .increased || preview.increasedContrast ? Color.primary.opacity(0.55) : Theme.stroke))
        }
    }
}

struct ToolboxActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    func makeBody(configuration: Configuration) -> some View {
        let reducedMotion = reduceMotion || preview.reduceMotion
        let increasedContrast = contrast == .increased || preview.increasedContrast
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.control : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(increasedContrast ? Color.primary.opacity(0.55) : Theme.stroke))
            .opacity(isEnabled ? 1 : increasedContrast ? 0.7 : 0.5)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct ToolboxActionModifier: ViewModifier {
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if prominent {
            content.controlSize(.large).buttonStyle(.borderedProminent).tint(Theme.accent)
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
        GlassEffectContainer(spacing: 16) { content }
    }
}

/// A small, interruptible response shared by the screen controls and navigation.
struct ControlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolboxPreviewAccessibility) private var preview
    func makeBody(configuration: Configuration) -> some View {
        let reducedMotion = reduceMotion || preview.reduceMotion
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.sectionFont)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.sectionRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.sectionRadius)
            .stroke(contrast == .increased || preview.increasedContrast ? Color.primary.opacity(0.55) : Theme.stroke))
    }
}

// MARK: - 可选中按钮（对应 ToggleButton）

struct SelectableButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let increasedContrast = contrast == .increased || preview.increasedContrast
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(title)
            }
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .frame(minWidth: 56)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(.primary)
                .background(isSelected ? Theme.accent.opacity(0.12) : Theme.control)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .stroke(increasedContrast ? Color.primary.opacity(0.65) : isSelected ? Theme.accent : Theme.stroke))
                .opacity(isEnabled ? 1 : increasedContrast ? 0.7 : 0.5)
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
            Text(title).font(Theme.sectionFont)
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
    @FocusState private var focused: Bool

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
                        focused = true
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
        .focusable(isEnabled, interactions: .edit)
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard isEnabled, press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            let delta = step > 0 ? step : 1
            let direction: Double = press.key == .rightArrow || press.key == .upArrow ? 1 : -1
            let next = min(max(value + direction * delta, range.lowerBound), range.upperBound)
            if next != value {
                value = next
                onCommit(next)
            }
            return .handled
        }
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
    private var readingIsKnown: Bool { range.contains(Double(externalValue)) }

    init(title: String,
         range: ClosedRange<Double>,
         externalValue: Int,
         onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.externalValue = externalValue
        self.onCommit = onCommit
        // Unknown input positions the track without presenting that placeholder as a reading.
        self._value = State(initialValue: range.contains(Double(externalValue)) ? Double(externalValue) : range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13, weight: .medium))
                .frame(width: Theme.parameterLabelWidth, alignment: .leading)
            FastSlider(value: $value, range: range, step: 1) { v in
                onCommit(Int(v))
            }
            .accessibilityLabel(title)
            .accessibilityValue(readingIsKnown ? String(Int(value)) : "未知")
            Text(readingIsKnown ? String(Int(value)) : "—")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .frame(width: 42, alignment: .trailing)
            Text(verbatim: "\(Int(range.lowerBound))–\(Int(range.upperBound))")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .onChange(of: externalValue) { _, newValue in
            value = range.contains(Double(newValue)) ? Double(newValue) : range.lowerBound
        }
    }
}

// MARK: - 页面标题栏 + 刷新按钮

struct PageHeader: View {
    let title: String
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 22, weight: .semibold))
            Spacer()
            Button(action: onRefresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }.toolboxAction()
        }
    }
}

// Domain validation uses integers; native sliders use Double without changing the endpoints.
extension ClosedRange where Bound == Int {
    var sliderBounds: ClosedRange<Double> { Double(lowerBound)...Double(upperBound) }
}
