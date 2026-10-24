import SwiftUI
import ToolboxDomain
import ToolboxApplication

/// The same live display-volume control in the dashboard and the existing menu panel.
struct DashboardVolumeControl: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(VolumeModel.self) private var volumeState
    @State private var volume = 0.0
    var compact = false

    private var reading: Int? {
        state.dashboardVolumeAvailable && volumeState.dashboardVolume != nil ? Int(volume) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("音量", systemImage: volumeState.dashboardMuted == true ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(reading.map(String.init) ?? "—")
                    .font(.system(size: compact ? 20 : 28, weight: .medium)).monospacedDigit()
                Text("/ 100").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            FastSlider(value: $volume, range: ControlRanges.percentage.sliderBounds, step: 1) {
                state.setDashboardVolume(Int($0))
            }
            .accessibilityLabel("显示器音量")
            .accessibilityValue(reading.map(String.init) ?? "未知")
            .disabled(volumeState.dashboardVolume == nil || !state.dashboardVolumeAvailable)
            Button { state.toggleDashboardMute() } label: {
                Label(volumeState.dashboardMuted == true ? "解除静音" : "静音", systemImage: "speaker.slash")
            }.toolboxAction().disabled(!state.dashboardVolumeAvailable)
            if let error = volumeState.dashboardVolumeError {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Theme.warning)
            }
        }
        .onAppear { syncValue(); state.refreshMediaVolumeState() }
        .onChange(of: volumeState.dashboardVolume) { syncValue() }
        .onChange(of: volumeState.dashboardVolumeError) { syncValue() }
        .onChange(of: connection.isConnected) { _, connected in if connected { state.refreshMediaVolumeState() } }
    }

    private func syncValue() { volume = Double(volumeState.dashboardVolume ?? 0) }
}
