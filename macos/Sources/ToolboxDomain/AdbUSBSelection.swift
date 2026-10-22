/// Transport verification only. A ready result does not grant identity or business write access.
package enum AdbUSBReadiness: Equatable, Sendable {
    case ready, awaitingAuthorization, offline, missing, ambiguous, unsupported
    case discoveryFailed(AdbDiscoveryFailure)
    case probeFailed, cancelled
}

package struct AdbUSBSelectionResult: Equatable, Sendable {
    package let endpoint: AdbEndpoint?
    package let readiness: AdbUSBReadiness
    package let diagnostic: String
    package var isReady: Bool { readiness == .ready }

    package init(endpoint: AdbEndpoint? = nil, readiness: AdbUSBReadiness, diagnostic: String = "") {
        self.endpoint = endpoint
        self.readiness = readiness
        self.diagnostic = diagnostic
    }
}
