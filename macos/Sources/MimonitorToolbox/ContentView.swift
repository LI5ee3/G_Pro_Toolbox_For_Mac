import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct ContentView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PresetsModel.self) private var presets
    @Environment(NavigationModel.self) private var navigation
    @Environment(SettingsModel.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Page = .home
    @State private var showLogs = false
    init(initialPage: Page = .home) { _selection = State(initialValue: initialPage) }

    private func name(_ page: Page) -> String {
        switch page {
        case .home: return "控制台"
        case .picture: return "画面"
        case .game: return "游戏"
        case .source: return "信号源"
        case .light: return "灯光"
        case .presets: return "预设"
        case .menuBar: return "菜单栏配置"
        case .tools: return "显示器工具"
        default: return page.title
        }
    }

    private func navigationSection(_ title: String, pages: [Page]) -> some View {
        Section(title) {
            ForEach(pages) { page in
                Label(name(page), systemImage: page.icon).tag(page)
                    .listItemTint(selection == page ? Theme.actionAccent : Theme.accent)
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image("AppMark", bundle: .module).resizable().frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text("G Pro ToolBox").font(Theme.controlFont).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                List(selection: Binding<Page?>(get: { selection }, set: { if let page = $0 { selection = page } })) {
                    navigationSection("日常", pages: [.home, .presets, .remote])
                    navigationSection("调整显示器", pages: [.picture, .game, .source, .light])
                }
                .listStyle(.sidebar).accessibilityLabel("功能导航")
                Divider().padding(.horizontal, 16)
                List(selection: Binding<Page?>(get: { selection }, set: { if let page = $0 { selection = page } })) {
                    navigationSection("工具", pages: [.tools])
                    navigationSection("应用", pages: [.settings])
                }
                .listStyle(.sidebar).frame(height: 158).accessibilityLabel("工具与应用")

            }
            .navigationSplitViewColumnWidth(min: 184, ideal: 196, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(name(selection)).font(Theme.sectionFont)
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .primaryAction) {
                        if selection != .home {
                            Label(connection.statusTitle, systemImage: connection.statusSymbol)
                                .font(Theme.captionFont).foregroundStyle(connection.statusColor)
                                .lineLimit(1).help(connection.statusText).labelStyle(.titleAndIcon)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { navigation.showsConnectionSettings = true } label: {
                            Label("连接设置", systemImage: "cable.connector")
                        }.labelStyle(.titleAndIcon).keyboardShortcut("k", modifiers: .command)
                            .focusEffectDisabled()
                        Button { showLogs = true } label: { Label("日志", systemImage: "text.alignleft") }
                            .labelStyle(.titleAndIcon)
                            .focusEffectDisabled()
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(state.isSimulation
            ? (settings.theme == "light" ? .light : settings.theme == "dark" ? .dark : nil) : nil)
        .font(Theme.bodyFont)
        .tint(Theme.accent)
        .accentColor(Theme.accent)
        .background(Theme.canvas)
        .sheet(isPresented: Binding(get: { navigation.showsConnectionSettings }, set: { navigation.showsConnectionSettings = $0 })) {
            ConnectionSettingsSheet(connection: connection)
        }
        .sheet(isPresented: $showLogs) { OperationLogSheet() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.refreshSystemStatus() }
        }
        .onChange(of: navigation.requestedPage, initial: true) { _, page in
            guard let page else { return }
            selection = page
            state.requestedPage = nil
        }
        .onChange(of: selection) { _, page in
            if state.needsConnection(page) && !connection.isConnected {
                state.log("未连接显示器，请先在控制台连接。")
                selection = .home
                return
            }
            state.onPageAppear(page)
        }
        .overlay {
            if presets.isPresetBusy {
                ZStack {
                    Color.black.opacity(0.12)
                    VStack(spacing: 14) {
                        ProgressView()
                        Text(presets.presetOperationText).font(Theme.bodyFont)
                    }
                    .padding(28).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
                }
            }
        }
        .alert("预设", isPresented: Binding(
            get: { presets.presetError != nil },
            set: { if !$0 { state.presetError = nil } }
        )) {
            Button("好", role: .cancel) { state.presetError = nil }
        } message: { Text(presets.presetError ?? "") }
    }

    @ViewBuilder private var detailView: some View {
        switch selection {
        case .home: HomeView()
        case .picture: PictureView()
        case .presets: PresetsView()
        case .game: GameView()
        case .source: SourceView()
        case .light: LightView()
        case .menuBar: MenuBarSettingsView()
        case .tools: ToolsView()
        case .settings: AppSettingsView()
        case .remote: RemoteView()
        }
    }
}
