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
        if eventTap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << 14)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let driver = Unmanaged<LiveHotkeyDriver>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = driver.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    driver.onDisabled?()
                    return Unmanaged.passUnretained(event)
                }
                return driver.handler?(type, event) == true ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        eventTap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; source = nil; handler = nil; onDisabled = nil
    }
    deinit { stop() }
}

final class LiveFeedback: FeedbackPresenting {
    func show(title: String, value: String) { HUDWindow.shared.show(title: title, value: value) }
    func show(title: String, value: String, countdown: TimeInterval) { HUDWindow.shared.show(title: title, value: value, countdown: countdown) }
    func endCountdown() { HUDWindow.shared.endCountdown() }
    func beginOperation(title: String) -> UUID { HUDWindow.shared.beginOperation(title: title) }
    func finishOperation(token: UUID, result: HUDOperationResult, title: String?) { HUDWindow.shared.finishOperation(token: token, result: result, title: title) }
    func brightness(_ value: Int) -> Bool { NativeOSD.shared.showBrightness(value: value) }
    func volume(_ value: Int) -> Bool { NativeOSD.shared.showVolume(value: value) }
    func mute() -> Bool { NativeOSD.shared.showMute() }
    func stop() { HUDWindow.shared.stop(); NativeOSD.shared.stop() }
}

private final class LiveLogFile {
    var url: URL?
    var handle: FileHandle?
    var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MimonitorToolbox/logs")
    }
    func start(_ stamp: String) {
        stop()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("log_\(stamp).txt")
        url = target
        if !FileManager.default.fileExists(atPath: target.path) { FileManager.default.createFile(atPath: target.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: target)
    }
    func stop() { try? handle?.close(); handle = nil }
    func export(_ target: URL, text: String) {
        if let url, FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.copyItem(at: url, to: target) }
        else { try? text.write(to: target, atomically: true, encoding: .utf8) }
    }
    func open() {
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }
    deinit { stop() }
}

extension AppEnvironment {
    /// Call only from the production composition root, after choosing the runtime mode.
    static func live() -> AppEnvironment {
        let resources = RuntimeResources(adbPath: LiveResourceLocator.locateAdb(),
            serverPort: ProcessInfo.processInfo.environment["MIMONITOR_ADB_SERVER_PORT"] ?? "5038",
            runtime: LiveResourceLocator.runtimeResource, guardianAPK: LiveResourceLocator.guardianApkPath)
        let adb = AdbClient(resources: resources, execute: SystemProcessRunner.run)
        let logFile = LiveLogFile()
        var system = SystemActions()
        system.isTrusted = { AXIsProcessTrusted() }
        system.promptAccessibility = {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        system.openAccessibility = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        system.defaultOutput = AudioOutputMonitor.defaultOutputDeviceName
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
        system.scan = { NetworkScan.scan() }; system.subnets = NetworkScan.localIPv4Subnets
        system.tcpOpen = { NetworkScan.isTcpOpen(host: $0, port: $1, timeout: $2) }
        system.ping = { host in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "1000", host]; process.standardOutput = Pipe(); process.standardError = Pipe()
            do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
        }
        system.isExecutable = { FileManager.default.isExecutableFile(atPath: $0) }
        system.observeWake = { systemWake, screenWake in
            let center = NSWorkspace.shared.notificationCenter
            let first = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in systemWake() }
            let second = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in screenWake() }
            return RuntimeCancellation { center.removeObserver(first); center.removeObserver(second) }
        }
        system.setAutostart = { Autostart.setEnabled($0, executablePath: Bundle.main.executablePath ?? CommandLine.arguments.first ?? "") }
        system.autostartEnabled = Autostart.isEnabled
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
        system.terminal = { script in
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); task.arguments = ["-e", script]
            do { try task.run(); return true } catch { return false }
        }
        system.startLog = logFile.start; system.stopLog = logFile.stop
        system.appendLog = { try? logFile.handle?.write(contentsOf: Data($0.utf8)) }
        system.exportLog = { logFile.export($0, text: $1) }; system.openLogDirectory = logFile.open
        return AppEnvironment(mode: .live, preferences: UserDefaults.standard, adb: adb,
            hotkeys: HotkeyManager(driver: LiveHotkeyDriver()), feedback: LiveFeedback(),
            scheduler: LiveScheduler(), system: system, now: Date.init, calendar: .current,
            presetDevice: { AdbPresetDevice(adb: $0, identity: $1) })
    }
}
