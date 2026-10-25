import AppKit
import CoreGraphics

/// 主机侧外接显示器的 HDR 信号，由 LiveRuntime 注入。
/// 使用 potential EDR；当前 EDR 在未播放 HDR 内容时仍可能为 1。
/// 显示器画面模式与综合判定由 AppCoordinator+DisplayMemory 处理。
enum HDRDetector {
    /// 主机侧：任意外接显示器处于 HDR 模式。
    ///
    /// 必须排除内建屏 —— 它的 potential EDR 恒为 2.0，不排除的话永远判成 HDR。
    static func hostSideHDR() -> Bool {
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = CGDirectDisplayID(num.uint32Value)
            if CGDisplayIsBuiltin(displayID) != 0 { continue }
            if screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 { return true }
        }
        return false
    }

}
