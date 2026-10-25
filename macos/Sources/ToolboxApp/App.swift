import Observation
import SwiftUI
import AppKit
import MimonitorToolbox
import ToolboxMacAdapters

/// Dock 图标的显隐。
///
/// Info.plist 里**不要**写 `LSUIElement=true`。那个键把 app 注册成「后台型」，
/// 启动台、Dock、Cmd+Tab、强制退出列表全都看不到它 —— 用户从 DMG 拖进
/// Applications 之后在启动台里根本找不到入口。（踩过：一开始按「不在 Dock
/// 常驻」把 LSUIElement 设成了 true，等于理解成了「永远不进 Dock」。）
///
/// 正确做法是保持普通 app 身份，再按「有没有可见窗口」在运行时切显示策略。
/// WPS 那类「Dock 里也有、菜单栏也有」的软件就是这么做的：
///
///   有窗口 → .regular    Dock 出现图标，Cmd+Tab 能切
///   没窗口 → .accessory  Dock 图标消失，只留菜单栏图标继续常驻
///
/// 于是「关掉窗口就退回菜单栏」的行为保住了，同时又能在启动台里找到。
enum DockVisibility {
    private static var observers: [NSObjectProtocol] = []

    static func startMonitoring() {
        // 悬浮提示窗（HUDWindow）和菜单栏下拉面板都是 NSPanel，属于辅助窗口。
        // 它们每次弹出 / 收起都会发这些通知 —— 不排除掉的话，按一下快捷键
        // Dock 图标就会跟着闪一下。
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { note in
                guard !(note.object is NSPanel) else { return }
                // 必须延到下一轮 runloop 再算：willClose 是在窗口**真正隐藏之前**
                // 发出的，此刻遍历 NSApp.windows 它还是 isVisible == true，
                // 于是判定成「还有可见窗口」不切换 —— 而关窗后再没有别的通知进来，
                // 结果就是关掉窗口 Dock 图标永远不消失（实测踩到过）。
                DispatchQueue.main.async { refresh() }
            }
        }
        refresh()
    }

    /// 主窗口即将显示前先切回 .regular。等 didBecomeKey 再切的话，
    /// 窗口已经画出来但 Dock 图标还慢半拍。
    static func showDockIcon() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// 判定「有没有真正的主窗口」。
    ///
    /// 不能只写 `isVisible && !(is NSPanel)`：**菜单栏图标自己也是一个可见窗口**
    /// （NSStatusBarWindow），它不是 NSPanel，于是会被算进来 —— 结果永远是
    /// 「还有窗口」，Dock 图标关掉窗口也不消失（实测踩到过，日志里能看到
    /// `wins=[AppKitWindow:hid NSStatusBarWindow:vis]`）。
    ///
    /// 改成认标题栏：主窗口有 `.titled`，菜单栏图标窗口和悬浮提示窗都没有。
    /// 全是公开 API，不依赖 NSStatusBarWindow 这种私有类名。
    private static func hasMainWindow() -> Bool {
        NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
    }

    private static func refresh() {
        let hasVisibleWindow = hasMainWindow()
        let want: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != want else { return }
        NSApp.setActivationPolicy(want)
    }
}

/// 窗口关闭行为（对应工具页里的「窗口关闭行为」选项，与原版一致）：
///   - tray：关掉窗口只是隐藏，应用继续驻留在菜单栏
///   - exit：关掉窗口直接退出
/// 「隐藏窗口」不会顺带退出 —— 见 DockVisibility：没窗口时应用退回 .accessory
/// 策略，菜单栏图标还在，所以进程继续活着。
@MainActor @Observable
final class AppLaunchState {
    private(set) var windowRequest = 0
    @ObservationIgnored private var handledRequest = 0
    func didFinishLaunching() {
        if !LiveToolboxRuntime.startsInMenuBar() { requestWindow() }
    }
    func requestWindow() { windowRequest &+= 1 }
    func claimWindowRequest() -> Bool {
        guard windowRequest > handledRequest else { return false }
        handledRequest = windowRequest; return true
    }
}

private struct ToolboxMenuIcon: View {
    let launch: AppLaunchState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: "display")
            .onChange(of: launch.windowRequest, initial: true) {
                if launch.claimWindowRequest() { DockVisibility.showDockIcon(); openWindow(id: "main") }
            }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var session: ToolboxSession?
    var launch: AppLaunchState?
    private var terminationPending = false
    private var terminationReplied = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时先把主题应用上，否则会先闪一下系统外观再切换
        session?.start()
        DockVisibility.startMonitoring()
        launch?.didFinishLaunching()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { launch?.requestWindow() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationReplied { return .terminateNow }
        if terminationPending { return .terminateLater }
        guard let session else { return .terminateNow }
        terminationPending = true
        session.stop()
        session.finishLogs { [weak self] in DispatchQueue.main.async { self?.finishTermination(sender) } }
        // A blocked filesystem must not trap the app in termination indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finishTermination(sender) }
        return .terminateLater
    }
    private func finishTermination(_ sender: NSApplication) {
        guard terminationPending, !terminationReplied else { return }
        terminationReplied = true
        sender.reply(toApplicationShouldTerminate: true)
    }
    func applicationWillTerminate(_ notification: Notification) { session?.stop() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        session?.closeBehavior == "exit"
    }
}

@main
struct MimonitorToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: ToolboxSession
    @State private var launch = AppLaunchState()

    init() {
        precondition(ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
                     "Select ToolboxPreviewHost for previews; production adapters are disabled")
        _session = State(initialValue: ToolboxSession(coordinator: LiveToolboxRuntime.makeCoordinator()))
    }
    private func bindLifecycle() { appDelegate.session = session; appDelegate.launch = launch }

    var body: some Scene {
        let _ = bindLifecycle()
        Window("红米G Pro ToolBox", id: "main") {
            ToolboxWindowContent(session: session)
                .frame(minWidth: 1020, minHeight: 740)
                .onAppear { appDelegate.session = session; session.start() }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1120, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .sidebar) {}
        }
        Settings {
            ToolboxSettingsContent(session: session)
                .onAppear { DockVisibility.showDockIcon() }
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            ToolboxMenuBarContent(session: session)
                .onAppear { appDelegate.session = session; session.start() }
        } label: { ToolboxMenuIcon(launch: launch) }
        .menuBarExtraStyle(.window)
    }
}
