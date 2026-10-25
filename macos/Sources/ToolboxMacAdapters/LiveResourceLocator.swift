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
        // 开发态（swift run）没有 .app 的内嵌资源：
        // 1) build_app.sh 下载的缓存 —— 跑过一次打包就有，最省事
        // 2) Homebrew / Android SDK 的常见位置
        // 之前只认 /opt/homebrew/bin/adb，Intel Mac 上是 /usr/local/bin/adb，
        // 开发构建于是静默地一条 adb 命令都执行失败。
        let cache = repoRootURL()
            .appendingPathComponent("macos/.cache/platform-tools/adb").path
        let candidates = [
            cache,
            "/opt/homebrew/bin/adb",                                  // Apple Silicon Homebrew
            "/usr/local/bin/adb",                                     // Intel Homebrew
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // 都不存在：返回缓存路径，让调用方在日志里给出可操作的提示
        return cache
    }

}
