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
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if !compact {
                Label("音量", systemImage: volumeState.dashboardMuted == true ? "speaker.slash" : "speaker.wave.2")
                    .font(Theme.sectionFont)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if compact {
                    Label("音量", systemImage: volumeState.dashboardMuted == true ? "speaker.slash" : "speaker.wave.2")
                        .font(Theme.sectionFont)
                    Spacer()
                }
                Text(reading.map(String.init) ?? "—")
                    .font(compact ? .system(size: 20, weight: .medium) : Theme.readingFont).monospacedDigit()
                Text("/ 100").font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                if !compact { Spacer(); muteButton }
            }
            FastSlider(value: $volume, range: ControlRanges.percentage.sliderBounds, step: 1) {
                state.setDashboardVolume(Int($0))
            }
            .accessibilityLabel("显示器音量")
            .accessibilityValue(reading.map(String.init) ?? "未知")
            .disabled(volumeState.dashboardVolume == nil || !state.dashboardVolumeAvailable)
            if compact { muteButton }
            if let error = volumeState.dashboardVolumeError {
                Label(error, systemImage: "exclamationmark.circle").font(Theme.detailFont).foregroundStyle(Theme.warning)
            }
        }
        .onAppear { syncValue(); state.refreshMediaVolumeState() }
        .onChange(of: volumeState.dashboardVolume) { syncValue() }
        .onChange(of: volumeState.dashboardVolumeError) { syncValue() }
        .onChange(of: connection.isConnected) { _, connected in if connected { state.refreshMediaVolumeState() } }
    }

    private var muteButton: some View {
        Button { state.toggleDashboardMute() } label: {
            Label(volumeState.dashboardMuted == true ? "解除静音" : "静音", systemImage: "speaker.slash")
        }.toolboxAction().disabled(!state.dashboardVolumeAvailable)
    }

    private func syncValue() { volume = Double(volumeState.dashboardVolume ?? 0) }
}
