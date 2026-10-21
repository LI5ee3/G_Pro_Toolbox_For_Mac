import ToolboxDomain
import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class HotkeysModel {
    package var accessibilityTrusted = false
    package var hotkeyDebugEnabled = false
    package var hotkeys: [String: HotkeyConfig] = [:]
    package var adjustHotkeys: [AdjustHotkeyConfig] = []
    package var mediaBrightnessKeysEnabled = false
    package var mediaBrightnessStep = 5
    package var mediaBrightnessNativeOSD = true
    package var mediaBrightnessFocusOnly = true
    package var mediaBrightnessDisplayName = "Mi Monitor"
    package var mediaVolumeKeysEnabled = false
    package var mediaVolumeStep = 5
    package var mediaVolumeNativeOSD = true
    package var mediaVolumeOutputGateEnabled = true
    package var mediaVolumeOutputName = "Mi Monitor"
    package var menuBarItems: [String] = []
    package var hotkeyCountdownEnabled = true
    package var hotkeyCountdownSeconds = 0.8
    package init() {}
}
