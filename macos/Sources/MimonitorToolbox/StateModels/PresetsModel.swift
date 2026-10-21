import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class PresetsModel {
    package var presetConfiguration = PresetConfiguration()
    package var isPresetBusy = false
    package var isPresetOperationInFlight = false
    package var presetOperationText = ""
    package var presetError: String?
    package var automaticTaskStatus = ""
    package init() {}
}
