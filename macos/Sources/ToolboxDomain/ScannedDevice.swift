import Foundation

package struct ScannedDevice: Equatable, Identifiable {
    package init(ip: String, model: String) { self.ip = ip; self.model = model }
    package let ip: String
    package let model: String
    package var id: String { ip }
    package var isMonitor: Bool { model.lowercased().contains("mitv") }
    package var label: String { "\(model) (\(ip))" }
}
