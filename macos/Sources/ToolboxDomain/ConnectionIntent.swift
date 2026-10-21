/// 只在主线程修改。后台任务带着开始时的序号返回，过期结果不得改写连接状态。
package struct ConnectionIntent {
    package init() {}
    package private(set) var generation = 0
    package private(set) var allowsAutomaticRecovery = true
    private var scanRequest: Int?

    package var allowsStartupAttempt: Bool {
        generation == 0 && allowsAutomaticRecovery
    }

    package mutating func beginConnection() -> Int {
        scanRequest = nil
        allowsAutomaticRecovery = true
        generation &+= 1
        return generation
    }

    package mutating func beginScan() -> Int {
        allowsAutomaticRecovery = false
        generation &+= 1
        scanRequest = generation
        return generation
    }

    package mutating func disconnect() {
        scanRequest = nil
        allowsAutomaticRecovery = false
        generation &+= 1
    }

    package func isCurrent(_ request: Int) -> Bool {
        request == generation
    }

    package func scanConnectionTarget(request: Int, devices: [ScannedDevice]) -> ScannedDevice? {
        guard scanRequest == request, isCurrent(request) else { return nil }
        let monitors = devices.filter(\.isMonitor)
        return monitors.count == 1 ? monitors.first : nil
    }
}
