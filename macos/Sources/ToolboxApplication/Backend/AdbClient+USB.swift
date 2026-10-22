import Foundation
import ToolboxConcurrency
import ToolboxDomain

extension AdbClient {
    /// Fresh, target-pinned validation for an explicitly selected serial. It never activates a
    /// session, persists preferences, deploys helpers, or grants business write access.
    package func validateUSBSelection(serial selectedSerial: String) -> AdbUSBSelectionResult {
        transaction {
            guard !operationCancelled else { return .init(readiness: .cancelled, diagnostic: "cancelled") }
            guard AdbEndpoint.supportsUSBSerial(selectedSerial) else {
                return .init(readiness: .unsupported, diagnostic: "unsupported USB serial")
            }
            let snapshot = discoverDevices()
            guard !operationCancelled else { return .init(readiness: .cancelled, diagnostic: "cancelled") }
            guard case .complete(let devices) = snapshot.outcome else {
                if case .failed(let reason) = snapshot.outcome {
                    if reason == .cancelled { return .init(readiness: .cancelled, diagnostic: "cancelled") }
                    return .init(readiness: .discoveryFailed(reason), diagnostic: "USB discovery failed: \(reason)")
                }
                return .init(readiness: .unsupported, diagnostic: "incomplete USB discovery")
            }
            // Count every row before filtering transport/state; -s cannot disambiguate duplicates.
            let matches = devices.filter { $0.serial == selectedSerial }
            guard !matches.isEmpty else { return .init(readiness: .missing, diagnostic: "USB device not found") }
            guard matches.count == 1, !matches[0].isAmbiguous else {
                return .init(readiness: .ambiguous, diagnostic: "ambiguous USB serial")
            }
            let device = matches[0]
            switch device.state {
            case .device, .unauthorized, .offline: break
            case .unsupported, .unknown:
                return .init(readiness: .unsupported, diagnostic: "unsupported USB state")
            }
            var endpoint = AdbEndpoint.usb(discovered: device)
            if endpoint == nil, device.transport == .unknown {
                // Only the selected unique candidate is queried. Unknown is never evidence.
                let path = run(["-s", selectedSerial, "get-devpath"], timeout: 3)
                guard !operationCancelled, path.outcome != .cancelled else {
                    return .init(readiness: .cancelled, diagnostic: "cancelled")
                }
                if path.succeeded {
                    endpoint = AdbEndpoint.usb(discovered: device,
                        verifiedDevicePath: path.standardOutput.trimmingCharacters(in: .newlines))
                }
            }
            guard let endpoint else {
                return .init(readiness: .unsupported, diagnostic: "USB transport evidence unavailable")
            }
            if device.state == .unauthorized {
                return .init(endpoint: endpoint, readiness: .awaitingAuthorization, diagnostic: "unauthorized")
            }
            if device.state == .offline {
                return .init(endpoint: endpoint, readiness: .offline, diagnostic: "offline")
            }
            let stateResult = run(["-s", selectedSerial, "get-state"], timeout: 3)
            guard !operationCancelled, stateResult.outcome != .cancelled else {
                return .init(readiness: .cancelled, diagnostic: "cancelled")
            }
            let state = checkedDeviceStateOutput(stateResult)
            if state.lowercased().contains("unauthorized") {
                return .init(endpoint: endpoint, readiness: .awaitingAuthorization, diagnostic: state)
            }
            guard state == "device" else {
                return .init(endpoint: endpoint, readiness: state == "offline" ? .offline : .probeFailed, diagnostic: state)
            }
            let probe = run(["-s", selectedSerial, "shell", "echo __mimonitor_probe__"], timeout: 25)
            guard !operationCancelled, probe.outcome != .cancelled else {
                return .init(readiness: .cancelled, diagnostic: "cancelled")
            }
            let ready = isSuccessfulTransportProbe(probe)
            return .init(endpoint: endpoint, readiness: ready ? .ready : .probeFailed,
                diagnostic: ready ? "device" : "USB shell probe failed")
        }
    }

    /// Keep authorization diagnostics compatible, while failed/partial/stderr-only "device"
    /// can never enter the legacy callers' healthy-state fast path.
    internal func checkedDeviceState(target: String) -> String {
        guard !target.isEmpty, !operationCancelled else { return "unknown" }
        let result = run(["-s", target, "get-state"], timeout: 3)
        return checkedDeviceStateOutput(result)
    }

    private func checkedDeviceStateOutput(_ result: ProcessResult) -> String {
        if result.outcome == .cancelled { return "cancelled" }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.lowercased().contains("unauthorized") { return output }
        let state = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !state.isEmpty else {
            return output.isEmpty ? "unknown" : "error: \(output)"
        }
        return state
    }

    internal func strictTransportProbe(target: String) -> Bool {
        guard !target.isEmpty, !operationCancelled else { return false }
        let result = run(["-s", target, "shell", "echo __mimonitor_probe__"], timeout: 25)
        return isSuccessfulTransportProbe(result)
    }

    private func isSuccessfulTransportProbe(_ result: ProcessResult) -> Bool {
        return result.succeeded
            && result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "__mimonitor_probe__"
    }
}
