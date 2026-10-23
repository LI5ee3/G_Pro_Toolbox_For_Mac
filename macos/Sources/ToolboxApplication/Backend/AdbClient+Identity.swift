import Foundation
import ToolboxDomain

extension AdbClient {
    /// Read fixed properties from an explicit endpoint in the caller's immutable operation.
    /// This supports a USB candidate before activation and never changes the active session.
    package func probeIdentity(endpoint: AdbEndpoint, sessionID: UUID, sampledAt: Date) -> IdentityProbeResult {
        transaction {
            guard !operationCancelled, operationSession?.sessionID == sessionID else { return .cancelled }
            var values: [String] = []
            for property in ["ro.serialno", "ro.boot.serialno"] {
                let result = run(["-s", endpoint.serial, "shell", "getprop \(property)"], timeout: 3)
                guard !operationCancelled, result.outcome != .cancelled else { return .cancelled }
                guard result.succeeded else {
                    return .unknown("身份读取失败：\(property)（\(result.outcome)，exit \(result.exitCode)，truncated \(result.outputTruncated)）")
                }
                values.append(result.standardOutput)
            }
            return DeviceIdentityParser.resolve(roSerialno: values[0], roBootSerialno: values[1],
                endpoint: endpoint, sessionID: sessionID, sampledAt: sampledAt)
        }
    }
}
