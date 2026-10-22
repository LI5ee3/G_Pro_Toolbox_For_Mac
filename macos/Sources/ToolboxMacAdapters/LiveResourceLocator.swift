import ToolboxDomain
import ToolboxApplication
import Foundation

enum LiveResourceLocator {
    // MARK: - 资源定位

    /// 仓库根目录（开发态定位 assets/ 用）。打包成 .app 后走 Bundle.main。
    static func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MimonitorToolbox
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // Mimonitor_Toolbox（仓库根）
    }

    static func runtimeResource(_ filename: String) -> String? {
        if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "runtime") {
            return url.path
        }
        let dev = repoRootURL().appendingPathComponent("assets/runtime/\(filename)")
        return FileManager.default.fileExists(atPath: dev.path) ? dev.path : nil
    }

    static func guardianApkPath() -> String? {
        if let url = Bundle.main.url(forResource: "adbguardian-signed", withExtension: "apk", subdirectory: "adb_guardian") {
            return url.path
        }
        let dev = repoRootURL().appendingPathComponent("assets/adb_guardian/adbguardian-signed.apk")
        return FileManager.default.fileExists(atPath: dev.path) ? dev.path : nil
    }

    static func locateAdb() -> String {
        if let bundled = runtimeResource("adb"),
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        // 回退到 PATH 上的 adb（brew install android-platform-tools）
        return "/opt/homebrew/bin/adb"
    }

}
