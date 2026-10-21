import Foundation
import Observation
import MimonitorPresetCore

/// Local app preferences only. Construction loads the injected store without applying system effects.
@MainActor @Observable
package final class SettingsModel {
    @ObservationIgnored private let preferences: any PreferencesStore
    @ObservationIgnored private let applyTheme: (String) -> Void
    @ObservationIgnored private var isConfiguring = true
    package var theme = "auto" {
        didSet {
            guard !isConfiguring else { return }
            preferences.set(theme, forKey: "theme")
            applyTheme(theme)
        }
    }
    package var closeBehavior = "tray" {
        didSet { guard !isConfiguring else { return }; preferences.set(closeBehavior, forKey: "close_behavior") }
    }
    package var autostartEnabled = false
    package init(preferences: any PreferencesStore, applyTheme: @escaping (String) -> Void) {
        self.preferences = preferences; self.applyTheme = applyTheme
        theme = preferences.string(forKey: "theme") ?? "auto"
        closeBehavior = preferences.string(forKey: "close_behavior") ?? "tray"
        isConfiguring = false
    }
}
