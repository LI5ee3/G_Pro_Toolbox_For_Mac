import ToolboxDomain
import ToolboxApplication
import Cocoa

// Keep this exact private ObjC wire interface at file scope. There is no success acknowledgment.
@objc(OSDUIHelperProtocol)
protocol OSDUIHelperProtocol {
    func showImage(_ image: Int64, onDisplayID displayID: UInt32, priority: UInt32,
                   msecUntilFade: UInt32, filledChiclets: UInt32, totalChiclets: UInt32, locked: Bool)
}

package struct NativeOSDMessage: Sendable, Equatable {
    package let image: Int64
    package let displayID: UInt32
    package let filled: UInt32
}
@MainActor package protocol NativeOSDTransport: AnyObject {
    func send(_ message: NativeOSDMessage, failure: @escaping @MainActor () -> Void) -> Bool
    func reset()
}

/// Private API is optional: a submitted request is not proof the system rendered an OSD. On error
/// fall back once for the newest request, then skip the private service for a 30-second cooldown.
@MainActor package final class NativeOSD {
    static let shared = NativeOSD(transport: LiveOSDTransport())
    static let chicletCount = 16
    private let transport: any NativeOSDTransport
    private let now: () -> TimeInterval
    private let display: @MainActor () -> CGDirectDisplayID
    private var active = false
    private var blockedUntil: TimeInterval = 0
    private var pending: (id: UUID, time: TimeInterval, fallback: @MainActor () -> Void)?
    package init(transport: any NativeOSDTransport,
                 now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                 display: (@MainActor () -> CGDirectDisplayID)? = nil) {
        self.transport = transport; self.now = now; self.display = display ?? Self.preferredDisplayID
    }
    package func start() { guard !active else { return }; active = true; blockedUntil = 0 }
    @discardableResult package func showBrightness(value: Int, maxValue: Int = 100, displayID: CGDirectDisplayID? = nil,
                                                    failure: @escaping @MainActor () -> Void) -> Bool {
        show(image: 1, value: value, maximum: maxValue, displayID: displayID, failure: failure)
    }
    @discardableResult package func showVolume(value: Int, maxValue: Int = 100, displayID: CGDirectDisplayID? = nil,
                                                failure: @escaping @MainActor () -> Void) -> Bool {
        show(image: value <= 0 ? 4 : 3, value: value, maximum: maxValue, displayID: displayID, failure: failure)
    }
    @discardableResult package func showMute(displayID: CGDirectDisplayID? = nil,
                                              failure: @escaping @MainActor () -> Void) -> Bool {
        show(image: 4, value: 0, maximum: 100, displayID: displayID, failure: failure)
    }
    private func show(image: Int64, value: Int, maximum: Int, displayID: CGDirectDisplayID?,
                      failure: @escaping @MainActor () -> Void) -> Bool {
        guard active, now() >= blockedUntil else { return false }
        let id = UUID(), time = now()
        let clamped = min(max(0, value), max(0, maximum))
        let filled = UInt32((Double(clamped) / Double(max(1, maximum)) * Double(Self.chicletCount)).rounded())
        pending = (id, time, failure)
        let sent = transport.send(NativeOSDMessage(image: image, displayID: displayID ?? display(), filled: filled)) { [weak self] in
            // Force an async delivery even for a synchronous test transport, so a failed send
            // can use the caller's immediate HUD fallback without double presentation.
            DispatchQueue.main.async { self?.failed(id) }
        }
        if !sent { pending = nil; blockedUntil = now() + 30 }
        return sent
    }
    private func failed(_ id: UUID) {
        guard active, let pending, pending.id == id else { return }
        self.pending = nil; blockedUntil = now() + 30
        if now() - pending.time <= 1.2 { pending.fallback() }
    }
    package func stop() {
        active = false; pending = nil; blockedUntil = 0; transport.reset()
    }
    private static func preferredDisplayID() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }
}

/// The real transport drops callbacks from invalidated connections and routes connection failure
/// to the newest outstanding presentation. Construction never opens XPC.
@MainActor private final class LiveOSDTransport: NativeOSDTransport {
    private var connection: NSXPCConnection?
    private var proxy: OSDUIHelperProtocol?
    private var generation: UUID?
    private var failure: (@MainActor () -> Void)?
    func send(_ message: NativeOSDMessage, failure: @escaping @MainActor () -> Void) -> Bool {
        guard let helper = helper() else { return false }
        self.failure = failure
        helper.showImage(message.image, onDisplayID: message.displayID, priority: 0x1F4,
                         msecUntilFade: 1000, filledChiclets: message.filled,
                         totalChiclets: UInt32(NativeOSD.chicletCount), locked: false)
        return true
    }
    private func helper() -> OSDUIHelperProtocol? {
        if let proxy { return proxy }
        reset()
        let id = UUID(); generation = id
        let connection = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.failed(id) } }
        connection.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.failed(id) } }
        connection.resume(); self.connection = connection
        proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async { self?.failed(id) }
        } as? OSDUIHelperProtocol
        if proxy == nil { reset() }
        return proxy
    }
    private func failed(_ id: UUID) {
        guard generation == id else { return }
        let failure = failure; reset(); failure?()
    }
    func reset() {
        generation = nil; failure = nil
        connection?.invalidationHandler = nil; connection?.interruptionHandler = nil
        connection?.invalidate(); connection = nil; proxy = nil
    }
    isolated deinit { reset() }
}
