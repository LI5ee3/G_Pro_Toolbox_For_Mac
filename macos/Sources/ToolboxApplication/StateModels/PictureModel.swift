import ToolboxDomain
import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class PictureModel {
    package var currentValues: [String: String] = [:]
    package var activeSource: String = "未知"
    package var loadedPages: Set<String> = []
    package var isBusy: Bool = false
    package var loadingPages: Set<String> = []
    package init() {}
}
