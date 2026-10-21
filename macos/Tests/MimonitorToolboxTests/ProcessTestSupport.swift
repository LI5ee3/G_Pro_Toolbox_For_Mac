import ToolboxDomain
import ToolboxApplication
@testable import ToolboxMacAdapters
import Foundation
@testable import MimonitorToolbox

extension AdbClient {
    convenience init(adbPath: String, serverPort: String = "5038") {
        self.init(resources: RuntimeResources(adbPath: adbPath, serverPort: serverPort,
            runtime: { _ in nil }, guardianAPK: { nil }), execute: SystemProcessRunner.run)
    }
}
