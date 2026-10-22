import ToolboxDomain
import ToolboxApplication
import SwiftUI
import Observation
import MimonitorToolbox

@MainActor @Observable
private final class PreviewSelection {
    var scenario = PreviewRuntime.Scenario.connected
    var screen = ToolboxScreen.home
}

/// This module has no dependency on ToolboxMacAdapters and cannot launch the live runtime.
public struct ToolboxPreviewGallery: View {
    @State private var selection = PreviewSelection()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            @Bindable var selection = selection
            HStack {
                Label("安全预览 · 内存模拟设备", systemImage: "eye")
                Spacer()
                Picker("场景", selection: $selection.scenario) {
                    ForEach(PreviewRuntime.Scenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 210)
                Picker("页面", selection: $selection.screen) {
                    ForEach(ToolboxScreen.allCases) { Text($0.title).tag($0) }
                }.frame(width: 220)
            }.padding(12)
            Divider()
            PreviewSurface(scenario: selection.scenario, screen: selection.screen)
                .id(selection.scenario.rawValue + selection.screen.rawValue)
        }
        .frame(minWidth: 1060, minHeight: 800)
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
