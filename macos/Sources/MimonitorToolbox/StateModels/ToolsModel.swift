import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class ToolsModel {
    package var guardianStatus = "状态：未检测"
    package var hdrMemoryEnabled = false
    package var is4KUI = false
    package var freesyncMemoryEnabled = false
    package var hdrMemoryStatusText = ""
    package var freesyncMemoryStatusText = ""
    package var crosshairGameModeOnly = false
    package var crosshairModeStatusText = ""
    package init() {}
}
