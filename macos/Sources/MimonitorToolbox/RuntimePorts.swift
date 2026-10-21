import AppKit
import Foundation
import MimonitorPresetCore

/// Cancellation owns timers, notifications and delayed startup work, not a window lifetime.
final class RuntimeCancellation {
    private var cancellation: (() -> Void)?
    init(_ cancellation: @escaping () -> Void = {}) { self.cancellation = cancellation }
    func invalidate() { cancellation?(); cancellation = nil }
    deinit { invalidate() }
}

protocol RuntimeScheduling: AnyObject {
    func repeating(every interval: TimeInterval, commonModes: Bool, _ action: @escaping () -> Void) -> RuntimeCancellation
    func after(_ delay: TimeInterval, work: DispatchWorkItem)
}

protocol HotkeyDriving: AnyObject {
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool,
               onDisabled: @escaping () -> Void) -> Bool
    func stop()
}

protocol FeedbackPresenting: AnyObject {
    func show(title: String, value: String)
    func show(title: String, value: String, countdown: TimeInterval)
    func endCountdown()
    func beginOperation(title: String) -> UUID
    func finishOperation(token: UUID, result: HUDOperationResult, title: String?)
    func brightness(_ value: Int) -> Bool
    func volume(_ value: Int) -> Bool
    func mute() -> Bool
    func stop()
}

struct RuntimeResources {
    let adbPath: String
    let serverPort: String
    let runtime: (String) -> String?
    let guardianAPK: () -> String?
}

struct CommandRequest {
    let executable: String
    let arguments: [String]
    let serverPort: String
    let timeout: TimeInterval
}

/// Only the production adapter target supplies real implementations of these effects.
struct SystemActions {
    var isTrusted: () -> Bool = { false }
    var promptAccessibility: () -> Bool = { false }
    var openAccessibility: () -> Void = {}
    var defaultOutput: () -> String? = { nil }
    var hostHDR: () -> Bool = { false }
    var targetDisplay: (String) -> CGDirectDisplayID? = { _ in nil }
    var focusedDisplay: () -> CGDirectDisplayID? = { nil }
    var scan: () -> [String] = { [] }
    var subnets: () -> [String] = { [] }
    var tcpOpen: (String, Int, Double) -> Bool = { _, _, _ in false }
    var ping: (String) -> Bool = { _ in false }
    var isExecutable: (String) -> Bool = { _ in false }
    var observeWake: (@escaping () -> Void, @escaping () -> Void) -> RuntimeCancellation = { _, _ in RuntimeCancellation() }
    var setAutostart: (Bool) -> Void = { _ in }
    var autostartEnabled: () -> Bool = { false }
    var applyTheme: (String) -> Void = { _ in }
    var showMainWindow: () -> Void = {}
    var quit: () -> Void = {}
    var copyText: (String) -> Void = { _ in }
    var openURL: (URL) -> Void = { _ in }
    var chooseAPK: (@escaping (URL) -> Void) -> Void = { _ in }
    var chooseLogExport: (@escaping (URL) -> Void) -> Void = { _ in }
    var terminal: (String) -> Bool = { _ in false }
    var startLog: (String) -> Void = { _ in }
    var appendLog: (String) -> Void = { _ in }
    var stopLog: () -> Void = {}
    var exportLog: (URL, String) -> Void = { _, _ in }
    var openLogDirectory: () -> Void = {}
}

struct AppEnvironment {
    enum Mode { case live, simulation }
    let mode: Mode
    let preferences: any PreferencesStore
    let adb: AdbClient
    let hotkeys: HotkeyManager
    let feedback: any FeedbackPresenting
    let scheduler: any RuntimeScheduling
    let system: SystemActions
    let now: () -> Date
    let calendar: Calendar
    let presetDevice: (AdbClient, String) -> any PresetDevice
}

/// A stopped/restarted lifetime cannot execute work queued by an older lifetime.
final class RuntimeGeneration {
    private let lock = NSLock()
    private var revision = 0
    private var enabled = false
    func begin() { lock.lock(); defer { lock.unlock() }; revision &+= 1; enabled = true }
    func end() { lock.lock(); defer { lock.unlock() }; revision &+= 1; enabled = false }
    func token() -> Int { lock.lock(); defer { lock.unlock() }; return revision }
    func allows(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return enabled && revision == token }
}
