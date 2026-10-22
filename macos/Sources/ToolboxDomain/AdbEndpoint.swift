/// Immutable command destination, separate from a preset's persisted ownership key.
/// Legacy TCP spelling is preserved. USB requires enumerated transport evidence;
/// neither endpoint construction nor a bus path proves physical identity or readiness.
package struct AdbEndpoint: Equatable, Sendable {
    private enum Transport: Equatable, Sendable {
        case tcp(host: String, port: UInt16)
        case usb(serial: String)
    }
    private let transport: Transport

    package static func tcp(host: String, port: UInt16 = 5555) -> AdbEndpoint? {
        guard !host.isEmpty, port > 0 else { return nil }
        return AdbEndpoint(transport: .tcp(host: host, port: port))
    }

    /// The caller must first obtain a fresh complete list and reject duplicate serials.
    /// A supplemental path is accepted only for an otherwise unknown enumerated candidate.
    package static func usb(discovered device: AdbDiscoveredDevice,
                            verifiedDevicePath: String? = nil) -> AdbEndpoint? {
        guard !device.isAmbiguous, supportsUSBSerial(device.serial) else { return nil }
        switch device.state {
        case .device, .unauthorized, .offline: break
        case .unsupported, .unknown: return nil
        }
        switch device.transport {
        case .usb: break
        case .unknown:
            guard let path = verifiedDevicePath, isUSBDevicePath(path) else { return nil }
        case .tcp, .unsupported: return nil
        }
        return AdbEndpoint(transport: .usb(serial: device.serial))
    }

    /// A safe argv token is necessary, but its spelling alone never proves USB transport.
    package static func supportsUSBSerial(_ serial: String) -> Bool {
        func alphanumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        let bytes = Array(serial.utf8)
        return !bytes.isEmpty && bytes.count <= AdbDeviceListParser.maximumLineBytes
            && alphanumeric(bytes[0])
            && bytes.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }
    }

    private static func isUSBDevicePath(_ path: String) -> Bool {
        path.hasPrefix("usb:") && path.utf8.count > 4
            && path.utf8.count <= AdbDeviceListParser.maximumLineBytes
            && path.utf8.allSatisfy { (33...126).contains($0) }
    }

    package var isUSB: Bool {
        if case .usb = transport { return true }
        return false
    }

    /// Compatibility projection for the existing TCP UI and legacy preset identity.
    package var tcpHost: String {
        switch transport {
        case .tcp(let host, _): return host
        case .usb: return ""
        }
    }

    package var serial: String {
        switch transport {
        case .tcp(let host, let port): return "\(host):\(port)"
        case .usb(let serial): return serial
        }
    }
}
