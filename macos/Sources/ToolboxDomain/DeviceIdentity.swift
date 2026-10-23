import Foundation

/// Fresh property evidence, not an application DeviceID, preset ownership key, or binding.
/// A persisted copy is only an expected value; it cannot prove a later session's identity.
package struct IdentityEvidence: Equatable, Sendable {
    package let endpoint: AdbEndpoint
    package let sessionID: UUID
    package let sampledAt: Date
    package let policyVersion: Int
    package let stableIdentifier: String
    package let roSerialno: String?
    package let roBootSerialno: String?

    package init(endpoint: AdbEndpoint, sessionID: UUID, sampledAt: Date, policyVersion: Int = 1,
                 stableIdentifier: String, roSerialno: String?, roBootSerialno: String?) {
        self.endpoint = endpoint
        self.sessionID = sessionID
        self.sampledAt = sampledAt
        self.policyVersion = policyVersion
        self.stableIdentifier = stableIdentifier
        self.roSerialno = roSerialno
        self.roBootSerialno = roBootSerialno
    }
}

package enum IdentityProbeResult: Equatable, Sendable {
    case identified(IdentityEvidence)
    case unknown(String)
    case conflict(String)
    case cancelled
}

package enum DeviceIdentityParser {
    package static let maximumPropertyBytes = 256
    private enum PropertyValue {
        case usable(String), absent, invalid
    }

    /// Revalidate stored property values without constructing a trusted live endpoint.
    /// Success is a syntactic property identifier, never verification of a persisted session.
    package static func stableIdentifier(roSerialno: String?, roBootSerialno: String?) -> String? {
        let serial = parse(roSerialno ?? ""), boot = parse(roBootSerialno ?? "")
        if case .invalid = serial { return nil }
        if case .invalid = boot { return nil }
        let serialValue = usableValue(serial), bootValue = usableValue(boot)
        if let serialValue, let bootValue, serialValue != bootValue { return nil }
        return serialValue ?? bootValue
    }

    /// Parse only complete successful stdout. Policy 1 is deliberately conservative and
    /// does not claim that these properties are globally unique or validated on this firmware.
    package static func resolve(roSerialno: String, roBootSerialno: String, endpoint: AdbEndpoint,
                                sessionID: UUID, sampledAt: Date) -> IdentityProbeResult {
        let serial = parse(roSerialno), boot = parse(roBootSerialno)
        if case .invalid = serial { return .unknown("ro.serialno 不是有效的单行身份读数") }
        if case .invalid = boot { return .unknown("ro.boot.serialno 不是有效的单行身份读数") }
        let serialValue = usableValue(serial), bootValue = usableValue(boot)
        if let serialValue, let bootValue, serialValue != bootValue {
            return .conflict("身份属性不一致：ro.serialno=\(serialValue)，ro.boot.serialno=\(bootValue)")
        }
        guard let identifier = serialValue ?? bootValue else {
            return .unknown("设备未提供可用的稳定身份属性")
        }
        return .identified(IdentityEvidence(endpoint: endpoint, sessionID: sessionID, sampledAt: sampledAt,
            stableIdentifier: identifier, roSerialno: serialValue, roBootSerialno: bootValue))
    }

    private static func usableValue(_ parsed: PropertyValue) -> String? {
        if case .usable(let value) = parsed { return value }
        return nil
    }

    private static func parse(_ output: String) -> PropertyValue {
        // getprop emits a line ending; never normalize the identifier's case, zeroes or spaces.
        var value = output
        // Swift treats CRLF as one Character, just like LF.
        if value.hasSuffix("\r\n") || value.hasSuffix("\n") { value.removeLast() }
        guard value.utf8.count <= maximumPropertyBytes else { return .invalid }
        if value.isEmpty { return .absent }
        guard value.utf8.allSatisfy({ (33...126).contains($0) }) else { return .invalid }
        let lower = value.lowercased()
        let placeholders: Set<String> = ["unknown", "null", "(null)", "none", "n/a", "default", "unset", "serial", "serialno"]
        if placeholders.contains(lower) || lower.allSatisfy({ $0 == "0" }) || lower.allSatisfy({ $0 == "f" }) {
            return .absent
        }
        return .usable(value)
    }
}
