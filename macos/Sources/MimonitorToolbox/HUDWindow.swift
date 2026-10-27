import ToolboxDomain
import ToolboxApplication
import AppKit
import SwiftUI

/// 悬浮提示的数据模型。用 ObservableObject 而不是每次重建视图，
/// 这样反复显示只走 SwiftUI 的差异更新，开销可忽略。
package final class HUDModel: ObservableObject {
    @Published package var isPresented: Bool
    @Published var title: String = ""
    @Published package var value: String = ""
    @Published var operationPhase: HUDOperationPhase?
    @Published var showsCountdown: Bool = false
    /// 倒计时起点与时长，原生 ProgressView 根据时间范围自行更新。
    @Published var countdownStart: Date = .distantPast
    @Published var countdownDuration: TimeInterval = 1

    package init(title: String = "", value: String = "", isPresented: Bool = true) {
        self.title = title
        self.value = value
        self.isPresented = isPresented
    }

    var level: Double? {
        guard operationPhase == nil else { return nil }
        if title == "静音", value == "开" { return 0 }
        guard title == "音量" || title == "背光", let number = Int(value), (0...100).contains(number) else { return nil }
        return Double(number) / 100
    }

    var symbolName: String {
        switch title {
        case "音量": return VolumeSymbol.name(for: Int(value))
        case "静音": return VolumeSymbol.name(for: nil, muted: value == "开")
        case "背光": return "sun.max.fill"
        default: return "display"
        }
    }
}

/// 悬浮提示的界面。
///
/// 菜单栏下方的玻璃胶囊；连续进度按实际 0–100 读数显示，不量化成系统的 16 格。
package struct HUDView: View {
    @ObservedObject var model: HUDModel
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolboxPreviewAccessibility) private var preview

    package init(model: HUDModel) { self.model = model }

    package var body: some View {
        GlassEffectContainer {
            if model.isPresented {
                HUDContent(model: model)
                    .toolboxGlass(cornerRadius: HUDWindow.size.height / 2)
                    .glassEffectID("hud", in: glassNamespace)
                    .glassEffectTransition(.materialize)
            }
        }
        .frame(width: HUDWindow.size.width, height: HUDWindow.size.height)
        .transaction { if reduceMotion || preview.reduceMotion { $0.animation = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue(model.value)
    }
}

private struct HUDContent: View {
    @ObservedObject var model: HUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolboxPreviewAccessibility) private var preview

    var body: some View {
        HStack(spacing: 12) {
            if let phase = model.operationPhase {
                switch phase {
                case .running:
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .frame(width: 32, height: 32)
                case .finished(.success):
                    resultSymbol("checkmark.circle.fill", color: .green, fallback: "完成")
                case .finished(.failure):
                    resultSymbol("exclamationmark.circle.fill", color: .red, fallback: "失败")
                case .finished(.cancelled):
                    resultSymbol("minus.circle", color: .secondary, fallback: "已取消")
                }
            } else {
                Image(systemName: model.symbolName)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .contentTransition(reduceMotion || preview.reduceMotion ? .identity : .symbolEffect(.replace.magic(fallback: .replace)))
                    .animation(reduceMotion || preview.reduceMotion ? nil : .default, value: model.symbolName)
            }
            if let level = model.level {
                HUDLevel(value: level * 100)
                    .animation(reduceMotion || preview.reduceMotion ? nil : .smooth(duration: 0.16), value: level)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(.caption).foregroundStyle(.secondary)
                    Text(model.value).font(.callout.weight(.medium)).monospacedDigit()
                }
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: HUDWindow.size.width, height: HUDWindow.size.height)
        .overlay(alignment: .bottom) {
            if model.showsCountdown {
                ProgressView(timerInterval: model.countdownStart...model.countdownStart.addingTimeInterval(max(model.countdownDuration, 0.01)),
                             countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .controlSize(.mini).tint(.primary)
                .frame(width: 200)
                .padding(.bottom, 7)
            }
        }
    }

    @ViewBuilder
    private func resultSymbol(_ name: String, color: Color, fallback: String) -> some View {
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: fallback) {
            Image(nsImage: symbol).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 32, height: 32).foregroundStyle(color)
        }
        // If unavailable, the status text below already says 完成 / 切换失败 / 已取消.
    }
}

/// Interpolate only the presentation value; the coordinator still writes integer volume targets.
struct HUDLevel: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = min(max(newValue, 0), 100) }
    }

    var body: some View {
        FastSlider(value: .constant(value), range: 0...100, step: 1) { _ in }
            .tint(.primary)
            .allowsHitTesting(false)
            .focusable(false)
    }
}

/// 悬浮窗本体。用 NSPanel 而不是 SwiftUI 的 Window：
///   - `.nonactivatingPanel` 保证不抢焦点（否则会把前台 app 踢下去）
///   - `.borderless` + 透明背景让原生玻璃与桌面合成
///   - 复用同一个 panel，反复显示只改模型，没有创建开销
@MainActor public final class HUDWindow: HUDPresenting {
    public static let shared = HUDWindow()

    private let model = HUDModel(isPresented: false)
    private var panel: NSPanel?
    private var hideTimer: Timer?
    /// Prevent an interrupted removal from hiding a newly presented HUD.
    private var generation = 0
    private var operation = HUDOperationState()

    static let size = NSSize(width: 308, height: 66)
    private let visibleSeconds: TimeInterval = 1.8
    package static let transitionAnimation = Animation.smooth(duration: 0.2)

    private init() {}

    public func stop() {
        hideTimer?.invalidate(); hideTimer = nil
        generation &+= 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.isPresented = false }
        panel?.orderOut(nil)
    }

    // MARK: - 对外接口

    /// 显示一条提示（不带倒计时）。
    public func show(title: String, value: String) {
        guard operation.acceptsValueHint else { return }
        operation.showValueHint()
        model.operationPhase = nil
        model.title = title
        model.value = value
        stopCountdown()
        present()
    }

    /// 显示提示并开始倒计时，走完才真正下发。
    /// 重复调用会重置倒计时 —— 对应"松手后才生效"。
    ///
    /// 这里只记录「起点 + 时长」，原生 ProgressView 自行绘制倒计时。
    public func show(title: String, value: String, countdown seconds: TimeInterval) {
        guard operation.acceptsValueHint else { return }
        operation.showValueHint()
        model.operationPhase = nil
        model.title = title
        model.value = value
        model.countdownDuration = seconds
        model.countdownStart = Date()
        model.showsCountdown = true
        present()
    }

    /// 倒计时结束（值已下发）：隐藏进度条，并重新计时展示
    public func endCountdown() {
        guard !operation.keepsVisible else { return }
        stopCountdown()
        restartHideTimer()
    }

    /// Progress uses the same non-activating panel, and has no auto-hide timer while running.
    public func beginOperation(title: String) -> UUID {
        let token = operation.begin()
        model.title = title
        model.value = "切换中…"
        model.operationPhase = operation.phase
        stopCountdown()
        present(autoHide: false)
        return token
    }

    public func finishOperation(token: UUID, result: HUDOperationResult, title: String? = nil) {
        guard operation.finish(token: token, result: result) else { return }
        if let title { model.title = title }
        model.operationPhase = operation.phase
        switch result {
        case .success: model.value = "完成"
        case .failure: model.value = "切换失败"
        case .cancelled: model.value = "已取消"
        }
        present()
    }

    // MARK: - 内部

    private func stopCountdown() {
        model.showsCountdown = false
    }

    private func present(autoHide: Bool = true) {
        let panel = ensurePanel()
        hideTimer?.invalidate()
        if autoHide { restartHideTimer() }
        generation &+= 1

        // 已经在显示中就完全不碰窗口层级：连按时每 80ms 做一次 orderFront
        //（窗口服务器往返）是明显的开销。
        if !panel.isVisible {
            position(panel)
            panel.orderFrontRegardless()
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        if !model.isPresented {
            withAnimation(Self.transitionAnimation) { model.isPresented = true }
        }
    }

    private func restartHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: visibleSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        // MenuBarExtra 的图标也是本进程窗口；排除下拉面板与 HUD，不依赖私有类名。
        let icons = NSApp.windows.filter { $0.isVisible && $0.level == .statusBar && !($0 is NSPanel) }
        let icon = icons.first { $0.screen == pointerScreen } ?? icons.first
        let screen = icon?.screen ?? pointerScreen ?? NSScreen.main
        guard let screen else { return }
        panel.setFrameOrigin(Self.origin(anchor: icon?.frame, in: screen.visibleFrame))
    }

    static func origin(anchor: NSRect?, in area: NSRect) -> NSPoint {
        let inset: CGFloat = 8
        return NSPoint(
            x: max(area.minX + inset, min((anchor?.midX ?? area.maxX) - size.width / 2,
                                         area.maxX - size.width - inset)),
            y: max(area.minY + inset, min(anchor?.minY ?? area.maxY, area.maxY) - size.height - inset)
        )
    }

    private func fadeOut() {
        guard !operation.keepsVisible else { return }
        guard let panel else { return }
        generation &+= 1
        stopCountdown()
        let thisGeneration = generation
        withAnimation(Self.transitionAnimation, completionCriteria: .removed) {
            model.isPresented = false
        } completion: { [weak self] in
            guard let self, self.generation == thisGeneration, !self.model.isPresented else { return }
            panel.orderOut(nil)
        }
    }
}
