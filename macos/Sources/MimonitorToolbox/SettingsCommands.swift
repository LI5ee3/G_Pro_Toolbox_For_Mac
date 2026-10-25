import SwiftUI
import AppKit

private struct ToolboxSettingsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var toolboxSettingsAction: (() -> Void)? {
        get { self[ToolboxSettingsActionKey.self] }
        set { self[ToolboxSettingsActionKey.self] = newValue }
    }
}

/// The same native settings command serves the live host and safe Preview.
public struct ToolboxSettingsCommands: Commands {
    @FocusedValue(\.toolboxSettingsAction) private var focusedSettings
    private let openSettings: (() -> Void)?

    public init(openSettings: (() -> Void)? = nil) { self.openSettings = openSettings }

    public var body: some Commands {
        // The live host fallback opens a closed main window, never a page underneath a sheet.
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                guard !hasSheet else { return }
                (openSettings ?? focusedSettings)?()
            }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(hasSheet || (openSettings == nil && focusedSettings == nil))
        }
    }

    private var hasSheet: Bool { NSApp.windows.contains { $0.attachedSheet != nil } }
}
