import ToolboxDomain
import ToolboxApplication
import SwiftUI

/// Public host API. Hardware construction remains in ToolboxMacAdapters.
@MainActor
public final class ToolboxSession {
    package let state: AppCoordinator
    public init(coordinator: AppCoordinator) { self.state = coordinator }
    public func start() { state.start() }
    public func stop() { state.stop() }
    public func finishLogs(_ completion: @escaping @MainActor @Sendable () -> Void) {
        state.finishLogs(completion)
    }
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
    }
}

public struct ToolboxWindowContent: View {
    private let session: ToolboxSession
    private let screen: ToolboxScreen
    public init(session: ToolboxSession, screen: ToolboxScreen = .home) { self.session = session; self.screen = screen }
    public var body: some View {
        ContentView(initialPage: screen.initialPage).modifier(ToolboxEnvironment(actions: session.state))
    }
}

public struct ToolboxMenuBarContent: View {
    private let session: ToolboxSession
    public init(session: ToolboxSession) { self.session = session }
    public var body: some View { MenuBarPanel().modifier(ToolboxEnvironment(actions: session.state)) }
}
