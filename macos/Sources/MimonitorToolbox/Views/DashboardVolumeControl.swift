import SwiftUI
import ToolboxDomain
import ToolboxApplication

/// The same live display-volume control in the dashboard and the existing menu panel.
struct DashboardVolumeControl: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(VolumeModel.self) private var volumeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolboxPreviewAccessibility) private var preview
    @State private var volume = 0.0
    var compact = false

    private var reading: Int? {
        state.dashboardVolumeAvailable && volumeState.dashboardVolume != nil ? Int(volume) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if !compact {
                volumeLabel
            }
            HStack(alignment: compact ? .center : .firstTextBaseline, spacing: 4) {
                if compact {
                    volumeLabel
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.map(String.init) ?? "—")
                        .font(compact ? .system(size: 20, weight: .medium) : Theme.readingFont).monospacedDigit()
                    Text("/ 100").font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                }
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

    private var volumeLabel: some View {
        let symbol = VolumeSymbol.name(for: reading, muted: volumeState.dashboardMuted == true)
        return Label {
            Text("音量")
        } icon: {
            ToolboxSymbolImage(name: symbol, animated: !reduceMotion && !preview.reduceMotion)
                .frame(width: 24, height: 18)
                .accessibilityHidden(true)
        }.font(Theme.sectionFont)
    }

    private var muteButton: some View {
        Button { state.toggleDashboardMute() } label: {
            Label(volumeState.dashboardMuted == true ? "解除静音" : "静音", systemImage: "speaker.slash")
        }.toolboxAction().disabled(!state.dashboardVolumeAvailable)
    }

    private func syncValue() { volume = Double(volumeState.dashboardVolume ?? 0) }
}

/// The dashboard and HUD use the same volume bands, with mute taking precedence.
enum VolumeSymbol {
    static func name(for volume: Int?, muted: Bool = false) -> String {
        if muted { return "speaker.slash.fill" }
        switch volume ?? -1 {
        case 0: return "speaker.slash.fill"
        case 1...33: return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
