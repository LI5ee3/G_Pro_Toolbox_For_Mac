import SwiftUI

/// Public host API. Hardware construction remains in ToolboxMacAdapters.
@MainActor
public final class ToolboxSession {
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

private struct ToolboxActionsKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    // Keep the storage optional: writable key-path projection can read the old value before writing.
    var toolboxActions: AppState? {
        get { self[ToolboxActionsKey.self] }
        set { self[ToolboxActionsKey.self] = newValue }
    }
}

/// Fail closed when a View consumes missing actions, not while SwiftUI projects the environment key path.
@MainActor @propertyWrapper
struct ToolboxActions: DynamicProperty {
    @Environment(\.toolboxActions) private var coordinator
    var wrappedValue: AppState {
        guard let coordinator else { preconditionFailure("Inject ToolboxSession from the live or safe-preview host") }
        return coordinator
    }
}

public struct ToolboxWindowContent: View {
    private let session: ToolboxSession
    private let screen: ToolboxScreen
    public init(session: ToolboxSession, screen: ToolboxScreen = .home) { self.session = session; self.screen = screen }
    public var body: some View {
        ContentView(initialPage: screen.initialPage).environment(\.toolboxActions, session.state).environment(session.state.settings).environment(session.state.logs)
    }
}

public struct ToolboxMenuBarContent: View {
    private let session: ToolboxSession
    public init(session: ToolboxSession) { self.session = session }
    public var body: some View { MenuBarPanel().environment(\.toolboxActions, session.state).environment(session.state.settings).environment(session.state.logs) }
}
