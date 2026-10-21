import ToolboxDomain
import SwiftUI
import ToolboxApplication

extension ConnectionModel {
    var statusColor: Color {
        switch connectionStatus {
        case .disconnected, .connecting, .scanning: return Theme.warning
        case .connected: return Theme.success
        }
    }
}
