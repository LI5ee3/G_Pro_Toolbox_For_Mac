import ToolboxDomain

extension AdbClient {
    /// One bounded list query, serialized with existing transactions. It never selects a target.
    /// Official adb may start a missing server; this is not a passive server probe.
    package func discoverDevices() -> AdbDiscoverySnapshot {
        let result = run(["devices", "-l"], timeout: 3)
        let failure: AdbDiscoveryFailure?
        switch result.outcome {
        case .cancelled: failure = .cancelled
        case .timedOut: failure = .timedOut
        case .signalled(let signal): failure = .signalled(signal)
        case .launchFailed(let code): failure = .launchFailed(code)
        case .ioFailure(let code): failure = .ioFailure(code)
        case .exited:
            if result.outputTruncated { failure = .truncated }
            else if result.exitCode != 0 { failure = .commandFailed(result.exitCode) }
            else { failure = nil }
        }
        return AdbDiscoverySnapshot(outcome: failure.map(AdbDiscoveryOutcome.failed)
            ?? AdbDeviceListParser.parse(result.standardOutput))
    }
}
