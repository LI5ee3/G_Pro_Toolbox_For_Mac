import ToolboxDomain
import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class VolumeModel {
    package var dashboardVolume: Int?
    package var dashboardMuted: Bool?
    package var dashboardVolumeError: String?
    package init() {}
}
