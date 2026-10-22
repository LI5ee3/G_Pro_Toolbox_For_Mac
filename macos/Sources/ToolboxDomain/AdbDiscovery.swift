import Foundation

/// Enumeration is evidence about a transport, never proof of device identity or readiness.
package enum AdbDiscoveredState: Equatable, Sendable {
    case device, unauthorized, offline
    case unsupported(String), unknown(String)

    fileprivate init(_ raw: String) {
        switch raw {
        case "device": self = .device
        case "unauthorized": self = .unauthorized
        case "offline": self = .offline
        case "bootloader", "recovery", "sideload", "rescue", "no permissions": self = .unsupported(raw)
        default: self = .unknown(raw)
        }
    }
}

package enum AdbDiscoveredTransport: Equatable, Sendable {
    case usb(path: String)
    case tcp(host: String, port: UInt16)
    case unknown, unsupported
}

/// Ordered fields retain unknown keys, duplicate keys, and unstructured diagnostic tokens.
package struct AdbDiscoveryField: Equatable, Sendable {
    package let key: String
    package let value: String?
}

package struct AdbDiscoveredDevice: Equatable, Sendable {
    package let serial: String
    package let state: AdbDiscoveredState
    package let transport: AdbDiscoveredTransport
    package let fields: [AdbDiscoveryField]
    package let rawLine: String
    package fileprivate(set) var isAmbiguous = false

    /// Selection can include authorization/offline diagnostics; it grants no write capability.
    package var isSelectable: Bool {
        guard !isAmbiguous else { return false }
        switch state {
        case .device, .unauthorized, .offline: break
        case .unsupported, .unknown: return false
        }
        switch transport {
        case .usb, .tcp: return true
        case .unknown, .unsupported: return false
        }
    }
}

package enum AdbDiscoveryFailure: Equatable, Sendable {
    case commandFailed(Int32), signalled(Int32), timedOut, cancelled
    case launchFailed(Int32), ioFailure(Int32), truncated
    case invalidOutput(line: Int)
    case limitExceeded
}

package enum AdbDiscoveryOutcome: Equatable, Sendable {
    case complete([AdbDiscoveredDevice])
    case failed(AdbDiscoveryFailure)
}

package struct AdbDiscoverySnapshot: Equatable, Sendable {
    package let id: UUID
    package let sampledAt: Date
    package let outcome: AdbDiscoveryOutcome

    package init(outcome: AdbDiscoveryOutcome, id: UUID = UUID(), sampledAt: Date = Date()) {
        self.id = id
        self.sampledAt = sampledAt
        self.outcome = outcome
    }
}

package enum AdbDeviceListParser {
    package static let maximumBytes = 1_048_576
    package static let maximumLineBytes = 4_096
    package static let maximumDevices = 256

    /// Only parse stdout after the caller verifies the complete ProcessResult.
    /// Limits apply before splitting; a damaged list never publishes a partial selection list.
    package static func parse(_ output: String) -> AdbDiscoveryOutcome {
        guard output.utf8.count <= maximumBytes else { return .failed(.limitExceeded) }
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasSuffix("\n") else { return .failed(.invalidOutput(line: 1)) }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "List of devices attached" else { return .failed(.invalidOutput(line: 1)) }
        var devices: [AdbDiscoveredDevice] = []
        for (index, line) in lines.enumerated().dropFirst() {
            guard line.utf8.count <= maximumLineBytes else { return .failed(.limitExceeded) }
            guard line.unicodeScalars.allSatisfy({
                $0.value == 9 || (!CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0))
            }) else {
                return .failed(.invalidOutput(line: index + 1))
            }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if tokens.isEmpty { continue }
            guard tokens.count >= 2, line != "List of devices attached" else {
                return .failed(.invalidOutput(line: index + 1))
            }
            guard devices.count < maximumDevices else { return .failed(.limitExceeded) }
            let noPermissions = tokens.count >= 3 && tokens[1] == "no" && tokens[2] == "permissions"
            let state = AdbDiscoveredState(noPermissions ? "no permissions" : tokens[1])
            let fields = tokens.dropFirst(noPermissions ? 3 : 2).map { token -> AdbDiscoveryField in
                let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                return AdbDiscoveryField(key: String(parts[0]), value: parts.count == 2 ? String(parts[1]) : nil)
            }
            devices.append(AdbDiscoveredDevice(serial: tokens[0], state: state,
                transport: classify(serial: tokens[0], fields: fields), fields: fields, rawLine: String(line)))
        }
        let counts = Dictionary(grouping: devices, by: \.serial).mapValues(\.count)
        for index in devices.indices { devices[index].isAmbiguous = counts[devices[index].serial, default: 0] > 1 }
        return .complete(devices)
    }

    private static func classify(serial: String, fields: [AdbDiscoveryField]) -> AdbDiscoveredTransport {
        let lower = serial.lowercased()
        guard !lower.hasPrefix("emulator-"), !lower.contains("_adb"), !lower.contains("._tcp"),
              !serial.contains("/"), !serial.contains("\\"), !serial.contains("%") else { return .unsupported }
        let usb = fields.filter { $0.key == "usb" }
        if serial.contains(":") {
            let parts = serial.split(separator: ":", omittingEmptySubsequences: false)
            guard usb.isEmpty, parts.count == 2, supportsTCPHost(String(parts[0])),
                  !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let port = UInt16(parts[1]), port > 0 else { return .unsupported }
            return .tcp(host: String(parts[0]), port: port)
        }
        guard !usb.isEmpty else { return .unknown }
        // Conservative argv token boundary; retain unsupported raw serials for diagnosis.
        // Case and leading zeroes remain exact. Do not infer USB from this spelling alone.
        let serialBytes = Array(serial.utf8)
        guard usb.count == 1, let path = usb[0].value, !path.isEmpty,
              serialBytes.first.map(asciiAlphanumeric) == true,
              serialBytes.allSatisfy({ asciiAlphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }) else {
            return .unsupported
        }
        return .usb(path: path)
    }

    private static func asciiAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    package static func supportsTCPHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if host.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) {
            return labels.count == 4 && labels.allSatisfy { label in
                !label.isEmpty && label.count <= 3 && UInt8(label) != nil
            }
        }
        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            return !bytes.isEmpty && bytes.count <= 63 && asciiAlphanumeric(bytes[0]) && asciiAlphanumeric(bytes[bytes.count - 1])
                && bytes.allSatisfy { asciiAlphanumeric($0) || $0 == 45 }
        }
    }
}
