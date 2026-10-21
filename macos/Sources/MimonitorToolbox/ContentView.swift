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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Page = .home
    @State private var appeared = false
    @Namespace private var navigationAnimation
    init(initialPage: Page = .home) { _selection = State(initialValue: initialPage) }

    private let pages: [Page] = [.home, .picture, .game, .source, .light, .presets, .autoTasks, .remote]

    private func name(_ page: Page) -> String {
        switch page {
        case .home: return "控制台"
        case .picture: return "画面"
        case .game: return "游戏"
        case .source: return "信号源"
        case .light: return "灯光"
        case .presets: return "预设"
        case .autoTasks: return "自动任务"
        default: return page.title
        }
    }

    private func select(_ page: Page) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = page }
    }

    private func navigationButton(_ page: Page) -> some View {
        Button { select(page) } label: {
            Label(name(page), systemImage: page.icon)
                .font(.system(size: 13, weight: selection == page ? .semibold : .regular))
                .foregroundColor(selection == page ? Theme.accent : Theme.secondaryText)
                .padding(.horizontal, 14).frame(height: 34)
                .background {
                    if selection == page {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.card)
                            .matchedGeometryEffect(id: "selection", in: navigationAnimation)
                    }
                }
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityAddTraits(selection == page ? .isSelected : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ToolboxGlassGroup {
                    HStack(spacing: 3) {
                        ForEach([Page.home, .picture, .game]) { page in
                            navigationButton(page)
                        }
                        Menu {
                            ForEach([Page.source, .light, .presets, .autoTasks, .remote]) { page in
                                Button { select(page) } label: { Label(name(page), systemImage: page.icon) }
                            }
                        } label: {
                            Label([Page.source, .light, .presets, .autoTasks, .remote].contains(selection)
                                  ? name(selection) : "全部工具", systemImage: "square.grid.2x2")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor([Page.source, .light, .presets, .autoTasks, .remote].contains(selection)
                                                 ? Theme.accent : Theme.secondaryText)
                                .padding(.horizontal, 12).frame(height: 34)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    .padding(4).toolboxGlass(cornerRadius: 14)
                }
                Spacer()
                Menu {
                    Button { select(.tools) } label: { Label("工具与设置", systemImage: "slider.horizontal.3") }
                    Button { select(.menuBar) } label: { Label("菜单栏配置", systemImage: "menubar.rectangle") }
                } label: {
                    Label(selection == .menuBar ? "菜单栏" : "设置", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor([Page.tools, .menuBar].contains(selection) ? Theme.accent : Theme.secondaryText)
                        .padding(.horizontal, 12).frame(height: 34)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 28).frame(height: 64)
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(reduceMotion || appeared ? 1 : 0)
                .offset(y: reduceMotion || appeared ? 0 : 6)
        }
        .preferredColorScheme(state.isSimulation
            ? (settings.theme == "light" ? .light : settings.theme == "dark" ? .dark : nil) : nil)
        .font(.system(size: 14))
        .tint(Theme.accent)
        .accentColor(Theme.accent)
        .background(Theme.canvas)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.refreshAccessibilityStatus() }
        }
        .onChange(of: navigation.requestedPage) { _, page in
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
                        Text(presets.presetOperationText).font(.system(size: 14))
                    }
                    .padding(28).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
                }
            }
        }
        .alert("预设与自动任务", isPresented: Binding(
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
        case .autoTasks: AutomaticTasksView()
        case .game: GameView()
        case .source: SourceView()
        case .light: LightView()
        case .menuBar: MenuBarSettingsView()
        case .tools: ToolsView()
        case .remote: RemoteView()
        }
    }
}
