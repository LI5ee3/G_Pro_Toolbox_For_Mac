import MimonitorToolbox
import Cocoa

/// OSDUIHelper 暴露的协议。方法签名必须和系统里的一致，
/// 否则 NSXPCInterface 包装出来的代理调用会失败。
///
/// **必须放在文件作用域**：把 `@objc private protocol` 嵌在类里时，
/// `conn.remoteObjectProxy... as? OSDUIHelperProtocol` 的动态转换会在运行时
/// 崩（栈是 swift_dynamicCast → tryCast，EXC_BAD_ACCESS）。放在文件作用域就好了。
@objc(OSDUIHelperProtocol)
protocol OSDUIHelperProtocol {
    func showImage(_ image: Int64,
                   onDisplayID displayID: UInt32,
                   priority: UInt32,
                   msecUntilFade: UInt32,
                   filledChiclets: UInt32,
                   totalChiclets: UInt32,
                   locked: Bool)
}

/// 调用 macOS 私有的 `OSDUIHelper`（mach service `com.apple.OSDUIHelper`）显示系统
/// 原生亮度 OSD —— 和按系统亮度键弹出的那个提示条是同一套。
///
/// 这是私有 API（BetterDisplay / MonitorControl 都这么做），没有公开文档，
/// 未来系统版本可能失效，所以调用方要做失败回退（`showBrightness` 返回是否成功）。
final class NativeOSD {
    static let shared = NativeOSD()

    /// OSDImage.brightness / volume / mute
    private static let brightnessImage: Int64 = 1
    private static let volumeImage: Int64 = 3
    private static let muteImage: Int64 = 4
    /// 原生亮度 / 音量 OSD 的格子数（系统条就是 16 格）
    static let chicletCount = 16

    private var connection: NSXPCConnection?
    private var proxy: OSDUIHelperProtocol?

    private init() {}

    /// 显示亮度 OSD。`value` / `maxValue` 决定亮几格。返回是否成功投递。
    @discardableResult
    func showBrightness(value: Int, maxValue: Int = 100, displayID: CGDirectDisplayID? = nil) -> Bool {
        showImage(Self.brightnessImage, value: value, maxValue: maxValue, displayID: displayID)
    }

    /// 显示音量 OSD。和按系统音量键弹出的是同一条（16 格 + 喇叭图标）；
    /// 音量为 0 时和系统一样换成静音图标。
    @discardableResult
    func showVolume(value: Int, maxValue: Int = 100, displayID: CGDirectDisplayID? = nil) -> Bool {
        let image = value <= 0 ? Self.muteImage : Self.volumeImage
        return showImage(image, value: value, maxValue: maxValue, displayID: displayID)
    }

    /// 显示静音 OSD（喇叭加斜线），对应系统静音键的提示。
    @discardableResult
    func showMute(displayID: CGDirectDisplayID? = nil) -> Bool {
        guard let helper = helper() else { return false }
        helper.showImage(Self.muteImage,
                         onDisplayID: UInt32(displayID ?? Self.preferredDisplayID()),
                         priority: 0x1F4,
                         msecUntilFade: 1000,
                         filledChiclets: 0,
                         totalChiclets: UInt32(Self.chicletCount),
                         locked: false)
        return true
    }

    private func showImage(_ image: Int64, value: Int, maxValue: Int,
                           displayID: CGDirectDisplayID?) -> Bool {
        guard let helper = helper() else { return false }
        let clamped = min(max(0, value), maxValue)
        let filled = UInt32((Double(clamped) / Double(max(1, maxValue)) * Double(Self.chicletCount)).rounded())
        helper.showImage(image,
                         onDisplayID: UInt32(displayID ?? Self.preferredDisplayID()),
                         priority: 0x1F4,
                         msecUntilFade: 1000,
                         filledChiclets: filled,
                         totalChiclets: UInt32(Self.chicletCount),
                         locked: false)
        return true
    }

    private func helper() -> OSDUIHelperProtocol? {
        if let proxy { return proxy }
        let conn = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.reset() }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.reset() }
        }
        conn.resume()
        connection = conn
        proxy = conn.remoteObjectProxyWithErrorHandler { _ in } as? OSDUIHelperProtocol
        return proxy
    }

    func stop() { reset() }

    private func reset() {
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        proxy = nil
    }

    /// 取鼠标所在屏幕的 displayID（用户正看着的那块），拿不到就退回主屏。
    private static func preferredDisplayID() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }
}
