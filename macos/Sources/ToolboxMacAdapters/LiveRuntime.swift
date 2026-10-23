import Carbon
import ToolboxProcessExecution
import ToolboxConcurrency
import ToolboxDomain
import ToolboxApplication
import AppKit
import Foundation
import MimonitorPresetCore
import UniformTypeIdentifiers

final class LiveScheduler: RuntimeScheduling {
    func repeating(every interval: TimeInterval, commonModes: Bool,
                   _ action: @escaping () -> Void) -> RuntimeCancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        RunLoop.main.add(timer, forMode: commonModes ? .common : .default)
        return RuntimeCancellation { timer.invalidate() }
    }
    func after(_ delay: TimeInterval, work: DispatchWorkItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

final class LiveHotkeyDriver: HotkeyDriving {
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((CGEventType, CGEvent) -> Bool)?
    private var onDisabled: (() -> Void)?
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool,
               onDisabled: @escaping () -> Void) -> Bool {
        self.handler = handler; self.onDisabled = onDisabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return CGEvent.tapIsEnabled(tap: eventTap)
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << 14)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let driver = Unmanaged<LiveHotkeyDriver>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if AXIsProcessTrusted(), let tap = driver.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    driver.onDisabled?()
                    return Unmanaged.passUnretained(event)
                }
                return driver.handler?(type, event) == true ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        eventTap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }
    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        eventTap = nil; source = nil; handler = nil; onDisabled = nil
    }
    deinit { stop() }
}

final class LiveFeedback: FeedbackPresenting {
    private var active = false
    func start() { guard !active else { return }; active = true; NativeOSD.shared.start() }
    func show(title: String, value: String) { guard active else { return }; HUDWindow.shared.show(title: title, value: value) }
    func show(title: String, value: String, countdown: TimeInterval) { guard active else { return }; HUDWindow.shared.show(title: title, value: value, countdown: countdown) }
    func endCountdown() { guard active else { return }; HUDWindow.shared.endCountdown() }
    func beginOperation(title: String) -> UUID { guard active else { return UUID() }; return HUDWindow.shared.beginOperation(title: title) }
    func finishOperation(token: UUID, result: HUDOperationResult, title: String?) { guard active else { return }; HUDWindow.shared.finishOperation(token: token, result: result, title: title) }
    func brightness(_ value: Int) -> Bool {
        guard active else { return false }
        return NativeOSD.shared.showBrightness(value: value) { [weak self] in self?.show(title: "背光", value: "\(value)") }
    }
    func volume(_ value: Int) -> Bool {
        guard active else { return false }
        return NativeOSD.shared.showVolume(value: value) { [weak self] in self?.show(title: "音量", value: "\(value)") }
    }
    func mute(_ muted: Bool) -> Bool {
        guard active else { return false }
        return NativeOSD.shared.showMute { [weak self] in self?.show(title: "静音", value: muted ? "开" : "关") }
    }
    func stop() { guard active else { return }; active = false; HUDWindow.shared.stop(); NativeOSD.shared.stop() }
}

extension AppEnvironment {
    /// Call only from the production composition root, after choosing the runtime mode.
    @MainActor static func live() -> AppEnvironment {
        precondition(ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1", "Use the ToolboxPreviewHost scheme for safe previews")
        let resources = RuntimeResources(adbPath: LiveResourceLocator.locateAdb(),
            serverPort: ProcessInfo.processInfo.environment["MIMONITOR_ADB_SERVER_PORT"] ?? "5038",
            runtime: LiveResourceLocator.runtimeResource, guardianAPK: LiveResourceLocator.guardianApkPath, fileSize: { path in
                ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.intValue ?? 0
            })
        let adb = AdbClient(resources: resources, execute: SystemProcessRunner.run)
        let logFile = LiveLogFile(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MimonitorToolbox/logs"))
        let loginItems = LiveLoginItems()
        let output = DefaultOutputCache.live()
        var system = SystemActions()
        system.backupConnectionProfile = { try ConnectionProfileBackup.write($0, identifier: $1) }
        system.isTrusted = { AXIsProcessTrusted() }
        system.promptAccessibility = {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        system.openAccessibility = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        system.openAutomation = { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
        // macOS 27 accepts Privacy_LocalNetwork but stays on the privacy overview.
        // The Privacy anchor resets a previously selected subpage to the overview;
        // opening the extension without an anchor would restore that old subpage.
        // The UI gives the remaining "本地网络" step.
        system.openLocalNetwork = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
        }
        system.observeActivation = { action in
            let observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { _ in action() }
            return RuntimeCancellation { NotificationCenter.default.removeObserver(observer) }
        }
        system.defaultOutput = { output.snapshot()?.name }
        system.startOutputMonitoring = output.start
        system.refreshOutput = { output.refresh() }
        system.stopOutputMonitoring = output.stop
        system.hostHDR = HDRDetector.hostSideHDR
        system.targetDisplay = { name in
            guard !name.isEmpty else { return nil }
            return NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains(name) }
                .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } }
        }
        system.focusedDisplay = {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            return screen.flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } }
        }
        system.scan = { NetworkScan.scan(cancellation: AdbOperationContext.current?.cancellation ?? CommandCancellation()) }
        system.subnets = { NetworkScan.localIPv4Subnets(cancellation: AdbOperationContext.current?.cancellation ?? CommandCancellation()) }
        system.tcpOpen = { NetworkScan.isTcpOpen(host: $0, port: $1, timeout: $2,
            cancellation: AdbOperationContext.current?.cancellation ?? CommandCancellation()) }
        system.ping = { NetworkScan.ping(host: $0, cancellation: AdbOperationContext.current?.cancellation ?? CommandCancellation()) }
        system.isExecutable = { FileManager.default.isExecutableFile(atPath: $0) }
        system.observeWake = { systemWake, screenWake in
            let center = NSWorkspace.shared.notificationCenter
            let first = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in systemWake() }
            let second = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in screenWake() }
            return RuntimeCancellation { center.removeObserver(first); center.removeObserver(second) }
        }
        system.loginStatus = loginItems.read
        system.reconcileLogin = loginItems.reconcile
        system.updateLogin = { loginItems.setEnabled($0, token: $1) }
        system.openLoginSettings = LiveLoginItems.openSettings
        system.applyTheme = { name in
            NSApp.appearance = name == "dark" ? NSAppearance(named: .darkAqua) : name == "light" ? NSAppearance(named: .aqua) : nil
        }
        system.showMainWindow = { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        system.quit = { NSApp.terminate(nil) }
        system.copyText = { NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string) }
        system.openURL = { NSWorkspace.shared.open($0) }
        system.chooseAPK = { completion in
            let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .item]
            panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url { completion(url) }
        }
        system.chooseLogExport = { completion in
            let panel = NSSavePanel(); let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd_HHmmss"
            panel.nameFieldStringValue = "Mimonitor_log_\(formatter.string(from: Date())).txt"
            panel.allowedContentTypes = [.plainText]; panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url { completion(url) }
        }
        system.terminal = { script, token in
            let request = CommandRequest(executable: "/usr/bin/osascript", arguments: ["-e", script], serverPort: "0", timeout: 30, cancellation: token)
            return TerminalExecution.result(SystemProcessRunner.run(request))
        }
        system.startLog = logFile.start; system.stopLog = logFile.stop
        system.appendLog = logFile.append
        system.observeLogErrors = logFile.observeErrors
        system.finishLogs = logFile.finish
        system.exportLog = { logFile.export($0, text: $1, completion: $2) }
        system.openLogDirectory = logFile.open
        return AppEnvironment(mode: .live, preferences: UserDefaults.standard, adb: adb,
            hotkeys: HotkeyManager(driver: LiveHotkeyDriver()), feedback: LiveFeedback(),
            scheduler: LiveScheduler(), system: system, now: Date.init, calendar: .current,
            presetDevice: { AdbPresetDevice(adb: $0, endpoint: $1, identity: $2) })
    }
}

/// The only public production composition factory. PreviewSupport never imports this module.
public enum LiveToolboxRuntime {
    @MainActor public static func startsInMenuBar() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let login = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        return AppLaunchPolicy.startsInMenuBar(arguments: CommandLine.arguments, loginEvent: login)
    }

    @MainActor public static func makeCoordinator() -> AppCoordinator { AppCoordinator(environment: .live()) }
}
