import ToolboxDomain
import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class NavigationModel {
    package var requestedPage: Page?
    package var showsConnectionSettings = false
    package init() {}
}
