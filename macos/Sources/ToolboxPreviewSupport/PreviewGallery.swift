import ToolboxDomain
import ToolboxApplication
import SwiftUI
import Observation
import MimonitorToolbox
import AppKit

@MainActor @Observable
private final class PreviewSelection {
    var scenario = PreviewRuntime.Scenario.connected
    var screen = ToolboxScreen.home
    var colorScheme = ColorScheme.light
    var accessibility = ToolboxPreviewAccessibility()
    var compact = false
}

/// This module has no dependency on ToolboxMacAdapters and cannot launch the live runtime.
public struct ToolboxPreviewGallery: View {
    @State private var selection = PreviewSelection()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            @Bindable var selection = selection
            PreviewSurface(scenario: selection.scenario, screen: selection.screen)
                .id(selection.scenario.rawValue + selection.screen.rawValue)
                .environment(\.toolboxPreviewAccessibility, selection.accessibility)
            Divider()
            HStack(spacing: 12) {
                Label("安全预览", systemImage: "eye")
                Picker("场景", selection: $selection.scenario) {
                    ForEach(PreviewRuntime.Scenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 180)
                Picker("页面", selection: $selection.screen) {
                    ForEach(ToolboxScreen.allCases) { Text($0.title).tag($0) }
                }.frame(width: 185)
                Picker("外观", selection: $selection.colorScheme) {
                    Text("浅色").tag(ColorScheme.light)
                    Text("深色").tag(ColorScheme.dark)
                }.labelsHidden().frame(width: 80)
                Toggle("最小窗口", isOn: $selection.compact).toggleStyle(.checkbox)
                Menu("辅助功能") {
                    Toggle("减少透明度", isOn: $selection.accessibility.reduceTransparency)
                    Toggle("减少动态效果", isOn: $selection.accessibility.reduceMotion)
                    Toggle("增加对比度", isOn: $selection.accessibility.increasedContrast)
                }.fixedSize()
                Spacer(minLength: 0)
            }.font(.system(size: 12)).padding(10).background(.bar)

        }
        .preferredColorScheme(selection.colorScheme)
        .frame(minWidth: 1020, minHeight: 688)
        .onChange(of: selection.compact) { _, small in
            guard let window = NSApp.windows.first(where: { $0.title == "S3-03 控制工作区 · 安全 Preview" }) else { return }
            var frame = window.frame
            let size = NSSize(width: small ? 1020 : 1120, height: small ? 740 : 820)
            frame.origin.y += frame.height - size.height; frame.size = size
            window.setFrame(frame, display: true)
        }
    }
}

/// A single State-owned object keeps the fake clock and action session paired across View reconstruction.
@MainActor
private final class PreviewFixture {
    let runtime: PreviewRuntime
    let session: ToolboxSession
    init(scenario: PreviewRuntime.Scenario) {
        let runtime = PreviewRuntime()
        self.runtime = runtime
        session = ToolboxSession(coordinator: runtime.makeState(scenario))
    }
}

private struct PreviewSurface: View {
    let screen: ToolboxScreen
    @State private var showMenuBar = false
    @State private var fixture: PreviewFixture
    init(scenario: PreviewRuntime.Scenario, screen: ToolboxScreen) {
        self.screen = screen
        _fixture = State(initialValue: PreviewFixture(scenario: scenario))
    }
    var body: some View {
        let session = fixture.session
        VStack(spacing: 0) {
            if screen == .menuBar { ToolboxMenuBarContent(session: session).frame(maxHeight: .infinity) }
            else { ToolboxWindowContent(session: session, screen: screen) }
            Divider()
            HStack {
                Text("所有设备、权限、文件与系统动作均为模拟；不会连接真实显示器。")
                Spacer()
                Button("菜单栏面板") { showMenuBar = true }
                    .popover(isPresented: $showMenuBar) { ToolboxMenuBarContent(session: session) }
                Button("推进 0.2 秒") { fixture.runtime.scheduler.advance(by: 0.2) }
                Button("推进 15 秒") { fixture.runtime.scheduler.advance(by: 15) }
            }.font(.caption).padding(10)
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }
}

#Preview("安全交互画廊") {
    ToolboxPreviewGallery()
}
