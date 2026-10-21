import Foundation

/// 开机自启动（LaunchAgent）。
/// 通过 ~/Library/LaunchAgents/<label>.plist 记录登录启动项。
/// 写入后下次登录自动加载（当前会话可用 launchctl 加载，这里仅写文件并提示重启登录）。
enum Autostart {
    static let label = "com.mimonitor.toolbox"

    static func plistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL().path)
    }

    static func setEnabled(_ enabled: Bool, executablePath: String) {
        let url = plistURL()
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath, "--minimized"],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: url)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
