import ToolboxDomain
import ToolboxApplication
import SwiftUI
import Observation

/// Public host API. Hardware construction remains in ToolboxMacAdapters.
@MainActor
@Observable
public final class ToolboxSession {
    package let state: AppCoordinator
    public var settingsPane = ToolboxSettingsPane.general
    public init(coordinator: AppCoordinator) { self.state = coordinator }
    public func start() { state.start() }
    public func stop() { state.stop() }
    public func finishLogs(_ completion: @escaping @MainActor @Sendable () -> Void) {
        state.finishLogs(completion)
    }
    public var closeBehavior: String { state.closeBehavior }
    public func showSettings(_ pane: ToolboxSettingsPane? = nil) {
        if let pane { settingsPane = pane }
        state.requestedPage = .settings
        state.showMainWindow()
    }
}

public enum ToolboxScreen: String, CaseIterable, Identifiable {
    case home, picture, game, source, light, presets, remote, tools, menuBar, settings
    public var id: String { rawValue }
    public var title: String { self == .tools ? "显示器工具" : page.title }
    private var page: Page { Page(rawValue: rawValue)! }
    fileprivate var initialPage: Page { page }
}

private struct ToolboxActionsKey: EnvironmentKey {
    static let defaultValue: AppCoordinator? = nil
}

extension EnvironmentValues {
    // Keep the storage optional: writable key-path projection can read the old value before writing.
    var toolboxActions: AppCoordinator? {
        get { self[ToolboxActionsKey.self] }
        set { self[ToolboxActionsKey.self] = newValue }
    }
}

/// Fail closed when a View consumes missing actions, not while SwiftUI projects the environment key path.
@MainActor @propertyWrapper
struct ToolboxActions: DynamicProperty {
    @Environment(\.toolboxActions) private var coordinator
    var wrappedValue: AppCoordinator {
        guard let coordinator else { preconditionFailure("Inject ToolboxSession from the live or safe-preview host") }
        return coordinator
    }
}

private struct ToolboxEnvironment: ViewModifier {
    let actions: AppCoordinator
    func body(content: Content) -> some View {
        content.environment(\.toolboxActions, actions)
            .environment(actions.settings).environment(actions.logs)
            .environment(actions.connection).environment(actions.picture)
            .environment(actions.presets).environment(actions.navigation)
            .environment(actions.volume).environment(actions.tools).environment(actions.keyboard)
            .background { ToolboxSheetButtonFocus().frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}

public struct ToolboxWindowContent: View {
    private let session: ToolboxSession
    private let screen: ToolboxScreen
    public init(session: ToolboxSession, screen: ToolboxScreen = .home) { self.session = session; self.screen = screen }
    public var body: some View {
        ContentView(initialPage: session.state.requestedPage ?? screen.initialPage)
            .modifier(ToolboxEnvironment(actions: session.state))
            .environment(session)
            .focusedSceneValue(\.toolboxSettingsAction, { session.showSettings($0) })
    }
}

public struct ToolboxMenuBarContent: View {
    private let session: ToolboxSession
    public init(session: ToolboxSession) { self.session = session }
    public var body: some View {
        MenuBarPanel().modifier(ToolboxEnvironment(actions: session.state)).environment(session)
    }
}
