import ToolboxDomain
import ToolboxApplication
import SwiftUI
import AppKit

// MARK: - 主题色
// Canvas and both app hosts share the same Graphite Teal resources.

enum Theme {
    static let accent = Color("AccentColor", bundle: .module)
    static let actionAccent = Color("AccentSelection", bundle: .module)
    // Native segment labels stay white, so their selected fill uses the darker anchor.
    static let selectedAccent = NSColor(named: "AccentSelection", bundle: .module) ?? .controlAccentColor
    // Status text keeps the established contrast on light and dark content surfaces.
    static let success = statusColor(NSColor(srgbRed: 0.07, green: 0.43, blue: 0.27, alpha: 1),
                                     NSColor(srgbRed: 0.38, green: 0.84, blue: 0.64, alpha: 1))
    static let warning = statusColor(NSColor(srgbRed: 0.65, green: 0.28, blue: 0.07, alpha: 1),
                                     NSColor(srgbRed: 1, green: 0.68, blue: 0.36, alpha: 1))
    private static func statusColor(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let control = Color(nsColor: .controlColor)
    static let stroke = Color(nsColor: .separatorColor)
    static let secondaryText = Color.secondary
    // A small system-font scale shared by the window, panels and settings.
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let deviceTitle = Font.system(size: 21, weight: .semibold)
    static let sectionFont = Font.system(size: 14, weight: .semibold)
    static let bodyFont = Font.system(size: 14)
    static let controlFont = Font.system(size: 13, weight: .medium)
    static let detailFont = Font.system(size: 13)
    static let captionFont = Font.system(size: 12)
    static let readingFont = Font.system(size: 32, weight: .medium)
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

private struct ToolboxActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        let button = content.font(Theme.controlFont).controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: Theme.controlRadius))
            .focusEffectDisabled()
        if reduceTransparency || preview.reduceTransparency || contrast == .increased || preview.increasedContrast {
            if prominent { button.buttonStyle(.borderedProminent).tint(Theme.actionAccent) }
            else { button.buttonStyle(.bordered) }
        } else {
            if prominent { button.buttonStyle(.glassProminent).tint(Theme.actionAccent) }
            else { button.buttonStyle(.glass).tint(nil as Color?) }
        }
    }
}

/// Selection updates only tint and content, preserving the native button's keyboard focus.
struct ToolboxSelectionButtonSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolboxPreviewAccessibility) private var preview
    let selected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || preview.reduceTransparency || contrast == .increased || preview.increasedContrast {
            content.buttonStyle(.borderedProminent)
                .focusEffectDisabled()
                .tint(selected ? Theme.actionAccent : Theme.control)
                .foregroundStyle(selected ? Color.white : Color.primary)
        } else {
            content.buttonStyle(.glass).focusEffectDisabled().tint(selected ? Theme.actionAccent : nil)
        }
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

/// System alerts create AppKit buttons separately from their SwiftUI action declarations.
/// Scope their focus-ring appearance to sheets owned by this host window.
struct ToolboxSheetButtonFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> SheetObserverView { SheetObserverView() }
    func updateNSView(_ nsView: SheetObserverView, context: Context) {}

    final class SheetObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(sheetWillBegin(_:)),
                name: NSWindow.willBeginSheetNotification, object: nil)
        }

        @objc private func sheetWillBegin(_ notification: Notification) {
            guard let hostWindow = window, let presentingWindow = notification.object as? NSWindow else { return }
            var ancestor = presentingWindow
            while ancestor !== hostWindow {
                guard let parent = ancestor.sheetParent else { return }
                ancestor = parent
            }
            DispatchQueue.main.async { [weak presentingWindow] in
                guard let content = presentingWindow?.attachedSheet?.contentView else { return }
                Self.hideButtonFocus(in: content)
            }
        }

        private static func hideButtonFocus(in view: NSView) {
            if let button = view as? NSButton { button.focusRingType = .none }
            for child in view.subviews { hideButtonFocus(in: child) }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
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
        GroupBox {
            content.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).font(Theme.sectionFont)
        }
    }
}

// MARK: - 共享原生滑块
// Keep the existing call-site contract; SwiftUI owns the track, thumb and interaction effects.

struct FastSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: (Double) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    @State private var isEditing = false

    private var steppedValue: Binding<Double> {
        Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { newValue in
            guard isEnabled else { return }
            let rounded = step > 0 ? (newValue / step).rounded() * step : newValue
            let next = min(max(rounded, range.lowerBound), range.upperBound)
            guard next != value else { return }
            value = next
            // Native keyboard/accessibility changes may arrive without a mouse editing session.
            if !isEditing { onCommit(next) }
        })
    }

    var body: some View {
        // Explicitly omit ticks; integer steps must not add 100 marks to percentage controls.
        Slider(value: steppedValue, in: range, label: { EmptyView() }, ticks: {}, onEditingChanged: { editing in
            let wasEditing = isEditing
            isEditing = editing
            if wasEditing && !editing { onCommit(value) }
        })
        .labelsHidden()
        .controlSize(.regular)
        .frame(minHeight: 28)
        .allowsHitTesting(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
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
            Text(title).font(Theme.controlFont)
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
            Text(title).font(Theme.pageTitle)
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
