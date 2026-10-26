import SwiftUI
import AppKit

private struct ToolboxSettingsActionKey: FocusedValueKey {
    typealias Value = (ToolboxSettingsPane?) -> Void
}

extension FocusedValues {
    var toolboxSettingsAction: ((ToolboxSettingsPane?) -> Void)? {
        get { self[ToolboxSettingsActionKey.self] }
        set { self[ToolboxSettingsActionKey.self] = newValue }
    }
}

/// The same native settings command serves the live host and safe Preview.
public struct ToolboxSettingsCommands: Commands {
    @FocusedValue(\.toolboxSettingsAction) private var focusedSettings
    private let openSettings: ((ToolboxSettingsPane?) -> Void)?

    public init(openSettings: ((ToolboxSettingsPane?) -> Void)? = nil) { self.openSettings = openSettings }

    public var body: some Commands {
        // The live host fallback opens a closed main window, never a page underneath a sheet.
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                guard !hasSheet else { return }
                (openSettings ?? focusedSettings)?(nil)
            }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(hasSheet || (openSettings == nil && focusedSettings == nil))
            Button("连接…") {
                guard !hasSheet else { return }
                (openSettings ?? focusedSettings)?(.connection)
            }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(hasSheet || (openSettings == nil && focusedSettings == nil))
        }
    }

    private var hasSheet: Bool { NSApp.windows.contains { $0.attachedSheet != nil } }
}
