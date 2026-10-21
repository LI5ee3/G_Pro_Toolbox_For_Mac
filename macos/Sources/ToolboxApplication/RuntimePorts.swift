import ToolboxConcurrency
import ToolboxDomain
import AppKit
import Foundation
import MimonitorPresetCore

/// Cancellation owns timers, notifications and delayed startup work, not a window lifetime.
package final class RuntimeCancellation {
    private var cancellation: (() -> Void)?
    package init(_ cancellation: @escaping () -> Void = {}) { self.cancellation = cancellation }
    package func invalidate() { cancellation?(); cancellation = nil }
    deinit { invalidate() }
}

package protocol RuntimeScheduling: AnyObject {
    func repeating(every interval: TimeInterval, commonModes: Bool, _ action: @escaping () -> Void) -> RuntimeCancellation
    func after(_ delay: TimeInterval, work: DispatchWorkItem)
}

package protocol HotkeyDriving: AnyObject {
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool,
               onDisabled: @escaping () -> Void) -> Bool
    func stop()
}

package protocol FeedbackPresenting: AnyObject {
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

package struct RuntimeResources {
    package let adbPath: String
    package let serverPort: String
    package let runtime: (String) -> String?
    package let guardianAPK: () -> String?
    package let fileSize: (String) -> Int
    package init(adbPath: String, serverPort: String, runtime: @escaping (String) -> String?,
                 guardianAPK: @escaping () -> String?, fileSize: @escaping (String) -> Int = { _ in 0 }) {
        self.adbPath = adbPath; self.serverPort = serverPort
        self.runtime = runtime; self.guardianAPK = guardianAPK; self.fileSize = fileSize
    }
}

package struct SystemActions {
    package init() {}
    package var isTrusted: () -> Bool = { false }
    package var promptAccessibility: () -> Bool = { false }
    package var openAccessibility: () -> Void = {}
    package var openAutomation: () -> Void = {}
    package var openLocalNetwork: () -> Void = {}
    package var observeActivation: (@escaping () -> Void) -> RuntimeCancellation = { _ in RuntimeCancellation() }
    package var defaultOutput: @MainActor () -> String? = { nil }
    package var startOutputMonitoring: @MainActor () -> Void = {}
    package var refreshOutput: @MainActor () -> Void = {}
    package var stopOutputMonitoring: @MainActor () -> Void = {}
    package var hostHDR: () -> Bool = { false }
    package var targetDisplay: (String) -> CGDirectDisplayID? = { _ in nil }
    package var focusedDisplay: () -> CGDirectDisplayID? = { nil }
    package var scan: () -> [String] = { [] }
    package var subnets: () -> [String] = { [] }
    package var tcpOpen: (String, Int, Double) -> Bool = { _, _, _ in false }
    package var ping: (String) -> Bool = { _ in false }
    package var isExecutable: (String) -> Bool = { _ in false }
    package var observeWake: (@escaping () -> Void, @escaping () -> Void) -> RuntimeCancellation = { _, _ in RuntimeCancellation() }
    package var loginStatus: () -> LoginItemSnapshot = { LoginItemSnapshot() }
    package var reconcileLogin: (CommandCancellation) -> LoginItemSnapshot = { _ in LoginItemSnapshot() }
    package var updateLogin: (Bool, CommandCancellation) -> LoginItemSnapshot = { _, _ in LoginItemSnapshot() }
    package var openLoginSettings: () -> Void = {}
    package var applyTheme: (String) -> Void = { _ in }
    package var showMainWindow: () -> Void = {}
    package var quit: () -> Void = {}
    package var copyText: (String) -> Void = { _ in }
    package var openURL: (URL) -> Void = { _ in }
    package var chooseAPK: (@escaping (URL) -> Void) -> Void = { _ in }
    package var chooseLogExport: (@escaping (URL) -> Void) -> Void = { _ in }
    package var terminal: (String, CommandCancellation) -> TerminalResult = { _, _ in TerminalResult(outcome: .failed) }
    package var startLog: (String) -> Void = { _ in }
    package var appendLog: (String) -> Void = { _ in }
    package var stopLog: () -> Void = {}
    package var observeLogErrors: @MainActor (@escaping @MainActor @Sendable (String) -> Void) -> RuntimeCancellation = { _ in RuntimeCancellation() }
    package var finishLogs: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void = { $0() }
    package var exportLog: @MainActor (URL, String, @escaping @MainActor @Sendable (FileActionResult) -> Void) -> Void = { _, _, completed in completed(.success) }
    package var openLogDirectory: () -> Void = {}
}

package struct AppEnvironment {
    package enum Mode { case live, simulation }
    package let mode: Mode
    package let preferences: any PreferencesStore
    package let adb: AdbClient
    package let hotkeys: HotkeyManager
    package let feedback: any FeedbackPresenting
    package let scheduler: any RuntimeScheduling
    package let system: SystemActions
    package let now: () -> Date
    package let calendar: Calendar
    package let presetDevice: (AdbClient, String) -> any PresetDevice
    package init(mode: Mode, preferences: any PreferencesStore, adb: AdbClient,
                 hotkeys: HotkeyManager, feedback: any FeedbackPresenting,
                 scheduler: any RuntimeScheduling, system: SystemActions,
                 now: @escaping () -> Date, calendar: Calendar,
                 presetDevice: @escaping (AdbClient, String) -> any PresetDevice) {
        self.mode = mode; self.preferences = preferences; self.adb = adb; self.hotkeys = hotkeys
        self.feedback = feedback; self.scheduler = scheduler; self.system = system
        self.now = now; self.calendar = calendar; self.presetDevice = presetDevice
    }
}

/// Mutable protocol settling state, confined to the serial device queue; never observed by UI.
final class DeviceWorkState {
    var pictureSettleUntil = Date.distantPast
    // Seeded before workers start; subsequently read/written only on deviceQueue. Persistence
    // returns to MainActor, but rapid enable/disable must see the worker's newest remembered mode.
    var freesyncPreviousMode = 0
}
