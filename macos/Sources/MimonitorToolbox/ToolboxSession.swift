import SwiftUI

/// Public host API. Hardware construction remains in ToolboxMacAdapters.
@MainActor
public final class ToolboxSession: ObservableObject {
    package let state: AppState
    package init(environment: AppEnvironment) { state = AppState(environment: environment) }
    package init(state: AppState) { self.state = state }
    public func start() { state.start() }
    public func stop() { state.stop() }
    public var closeBehavior: String { state.closeBehavior }
}

public enum ToolboxScreen: String, CaseIterable, Identifiable {
    case home, picture, game, source, light, presets, autoTasks, remote, tools, menuBar
    public var id: String { rawValue }
    public var title: String { page.title }
    private var page: Page { Page(rawValue: rawValue)! }
    fileprivate var initialPage: Page { page }
}

public struct ToolboxWindowContent: View {
    private let session: ToolboxSession
    private let screen: ToolboxScreen
    public init(session: ToolboxSession, screen: ToolboxScreen = .home) { self.session = session; self.screen = screen }
    public var body: some View {
        ContentView(initialPage: screen.initialPage).environmentObject(session.state).environment(session.state.settings).environment(session.state.logs)
    }
}

public struct ToolboxMenuBarContent: View {
    private let session: ToolboxSession
    public init(session: ToolboxSession) { self.session = session }
    public var body: some View { MenuBarPanel().environmentObject(session.state).environment(session.state.settings).environment(session.state.logs) }
}
