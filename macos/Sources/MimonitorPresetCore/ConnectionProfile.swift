import Foundation
import ToolboxDomain

/// Persisted endpoint references are expectations, never discovery or readiness evidence.
package struct ConnectionEndpointReference: Codable, Equatable, Sendable {
    package let isUSB: Bool
    package let tcpHost: String
    package let tcpPort: UInt16?
    package let serial: String
    package init(endpoint: AdbEndpoint) {
        isUSB = endpoint.isUSB; tcpHost = endpoint.tcpHost
        tcpPort = endpoint.tcpPort; serial = endpoint.serial
    }
    package func matches(_ endpoint: AdbEndpoint) -> Bool { self == Self(endpoint: endpoint) }
    var isValid: Bool {
        if isUSB { return tcpHost.isEmpty && tcpPort == nil && AdbEndpoint.supportsUSBSerial(serial) }
        guard let port = tcpPort, let endpoint = AdbEndpoint.inputTCP(host: tcpHost, port: String(port)) else { return false }
        return serial == endpoint.serial
    }
}

package struct ConnectionStoredEvidence: Codable, Equatable, Sendable {
    package let endpoint: ConnectionEndpointReference
    package let sessionID: UUID
    package let sampledAt: Date
    package let policyVersion: Int
    package let roSerialno: String?
    package let roBootSerialno: String?
    init(_ evidence: IdentityEvidence) {
        endpoint = ConnectionEndpointReference(endpoint: evidence.endpoint)
        sessionID = evidence.sessionID; sampledAt = evidence.sampledAt
        policyVersion = evidence.policyVersion; roSerialno = evidence.roSerialno
        roBootSerialno = evidence.roBootSerialno
    }
}

package struct ConnectionDeviceRecord: Codable, Equatable, Sendable {
    package enum BindingSource: String, Codable, Sendable { case verifiedPropertiesWithUserConfirmation }
    package var deviceID: UUID
    package var stableIdentifier: String
    package var presetIdentityKey: String
    package var legacyAliases: [String]
    package var endpoints: [ConnectionEndpointReference]
    package var bindingRevision: Int
    package var bindingSource: BindingSource
    package var evidence: ConnectionStoredEvidence
}

package struct ConnectionProfileMigration: Codable, Equatable, Sendable {
    package var migrationVersion: Int
    package var originalDigest: String
    package var backupIdentifier: String
}

package struct ConnectionProfile: Codable, Equatable, Sendable {
    package enum Preference: String, Codable, Sendable { case tcp, usb }
    package var schemaVersion = 1
    package var revision: Int
    package var preference: Preference
    package var selectedEndpoint: ConnectionEndpointReference?
    package var devices: [ConnectionDeviceRecord]
    package var memoryOwnerDeviceID: UUID?
    package var migration: ConnectionProfileMigration
}

package struct ConnectionProfileSnapshot: Equatable, Sendable {
    package let profile: ConnectionProfile?
    package let error: String?
    package let warning: String?
    package let ownershipKeys: [String]
    /// Digest of presence, property-list types and original values of all three keys.
    package let token: String
}
