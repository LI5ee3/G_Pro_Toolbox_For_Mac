import Observation

/// A log mutation invalidates only views that read these properties.
@MainActor @Observable
package final class LogModel {
    package var lines: [String] = []
    package var sequence = 0
    package var recordsToFile = false
    package init() {}
    package func append(_ line: String) {
        lines.append(line)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        sequence &+= 1
    }
}
