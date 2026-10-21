import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func toggleLogFile(_ enabled: Bool) {
        logToFileEnabled = enabled
        if enabled { environment.system.startLog(Self.fileTimeFormatter.string(from: environment.now())) }
        else { environment.system.stopLog() }
        log(enabled ? "本地日志记录: 开启" : "本地日志记录: 关闭")
    }

    package func exportLog(to url: URL) {
        environment.system.exportLog(url, logLines.joined(separator: "\n"))
        log("日志已导出: \(url.path)")
    }
    package func chooseLogExport() { environment.system.chooseLogExport { [weak self] in self?.exportLog(to: $0) } }
    package func chooseAPK() { environment.system.chooseAPK { [weak self] in self?.installApk($0) } }
    package func copyLog() { environment.system.copyText(logLines.joined(separator: "\n")); log("日志已复制到剪贴板") }
    package func openLogDir() { environment.system.openLogDirectory() }
    package func requestAccessibilityPrompt() { _ = environment.system.promptAccessibility() }


    /// 信号源页停留期间每 2 秒轮询一次：显示器可能被遥控器/按键切走，
    /// 这个页面要反映实时状态（对应原版 _start_source_polling）。
    package func runDiagnostics() {
        log("===== 网络诊断 =====")
        let ip = ipInput.trimmingCharacters(in: .whitespaces)
        let connected = isConnected
        runBackground {
            var lines: [String] = []

            lines.append("adb 路径: \(self.adb.adbPath)")
            lines.append("adb 可执行: \(self.environment.system.isExecutable(self.adb.adbPath) ? "✅" : "❌ 找不到 adb")")
            lines.append("adb server 端口: \(self.adb.serverPort)")

            let subnets = self.environment.system.subnets()
            lines.append("本机网段: \(subnets.isEmpty ? "❌ 未识别" : "✅ " + subnets.joined(separator: ", "))")

            if ip.isEmpty {
                lines.append("⚠️ 未填写显示器 IP，跳过连通性测试")
            } else {
                let sameSubnet = subnets.contains { ip.hasPrefix($0 + ".") }
                lines.append("与目标同网段: \(sameSubnet ? "✅" : "❌ 不在同一网段")")
                lines.append("ping \(ip): \(self.environment.system.ping(ip) ? "✅ 通" : "❌ 不通")")
                let tcp = self.environment.system.tcpOpen(ip, 5555, 2.0)
                lines.append("TCP \(ip):5555: \(tcp ? "✅ 开放" : "❌ 连不上")")
                if !tcp {
                    lines.append("  → 设备在线但端口不通，通常是显示器的「无线调试」没开")
                }
                if connected {
                    lines.append("adb 设备状态: \(self.adb.deviceState())")
                }
            }

            lines.append("提示: 三者全 ❌ 且同网段 → 多半是本 app 缺「本地网络」权限")
            lines.append("      到 系统设置 → 隐私与安全性 → 本地网络，打开本应用开关")
            lines.append("提示: 不同网段 → 显示器与 Mac 不在同一 Wi-Fi/VLAN")
            lines.append("===== 诊断结束 =====")

            self.publish { lines.forEach { self.log($0) } }
        }
    }


    package func installApk(_ url: URL) {
        guard isConnected else { log("请先连接显示器"); return }
        log("正在安装: \(url.lastPathComponent) ...")
        runBackground {
            let r = self.adb.installApk(url.path)
            self.publish {
                if r.succeeded && r.output.contains("Success") {
                    self.log("APK 安装成功")
                } else {
                    self.log("APK 安装失败: \(r.outcome): \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }

    /// 进入显示器上的 adb shell。
    package func openAdbShell() {
        guard isConnected else { log("请先连接显示器"); return }
        openTerminal(title: "Mimonitor · Shell",
                     command: "adb -s \(adb.serial) shell")
    }

    /// 打开一个配好环境的终端：PATH 里有 adb，端口也设好了，直接敲 `adb devices` 就能用。
    ///
    /// **故意不要求已连接** —— 连不上的时候正是最需要这个终端的时候。
    /// 以前这里跑的是 `adb shell`（没带 -s），设备多于一个时报
    /// "more than one device/emulator"，而且那个终端里也没有 adb 可用。
    package func openAdbCmd() {
        openTerminal(title: "Mimonitor · ADB", command: "")
    }

    internal func openTerminal(title: String, command: String) {
        let adbDir = (adb.adbPath as NSString).deletingLastPathComponent
        // 把 adb 所在目录塞进 PATH，用户才能直接敲 adb
        let setup = "export PATH=\"\(adbDir):$PATH\"; export ANDROID_ADB_SERVER_PORT=\(adb.serverPort)"
        let body = command.isEmpty ? "\(setup); clear" : "\(setup); clear; \(command)"

        let script = """
        tell application "Terminal"
            -- 已经开过就切过去，不再新开一个 —— 之前点一次开一个，很快就堆一堆窗口
            repeat with w in windows
                repeat with t in tabs of w
                    if (custom title of t) is "\(title)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            set newTab to do script "\(Self.appleScriptEscape(body))"
            set custom title of newTab to "\(title)"
            activate
        end tell
        """

        let ok = environment.system.terminal(script)
        log(ok ? "已在终端打开 ADB 会话（\(title)）" : "打开终端失败，请检查自动化权限与终端状态")
    }

    /// 套进 AppleScript 字符串字面量前的转义
    internal static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }


    /// 检测显示器当前是否处于 4K UI 模式（移植自原版 _check_4k_state）。
    /// Override size 存在且任一边大于 1920x1080 即视为已开启。
    package func check4KState() {
        guard isConnected else { return }
        runBackground {
            let override = self.adb.getOverrideSize()
            let density = self.adb.getOverrideDensity()
            self.publish {
                let is4k = override.map { $0.width > 1920 || $0.height > 1080 } ?? false
                let changed = (self.is4KUI != is4k)
                if changed { self.is4KUI = is4k }
                // 只在状态变化时记日志：工具页每次出现都会检测一遍，
                // 无脑记录会把日志刷满
                if changed || override == nil {
                    let sizeText = override.map { "\($0.width)×\($0.height)" } ?? "无 Override（面板原生）"
                    let densityText = density.map { "，DPI \($0)" } ?? ""
                    self.log("4K UI 检测: \(is4k ? "已开启" : "未开启")（\(sizeText)\(densityText)）")
                }
            }
        }
    }

    package func toggle4K(_ enabled: Bool) {
        guard isConnected else { return log("请先连接显示器") }
        log(enabled ? "已设置 4K UI (3840×2160 / DPI 640)，显示器即将重启..." : "已恢复 1080p UI，显示器即将重启...")
        runBackground {
            if enabled {
                self.adb.shell("wm size 3840x2160")
                self.adb.shell("wm density 640")
            } else {
                self.adb.shell("wm size 1920x1080")
                self.adb.shell("wm density 320")
            }
            self.adb.shell("reboot")
        }
    }


    package func checkGuardian() {
        guard isConnected else { return log("请先连接显示器") }
        guardianStatus = "状态：正在检测..."
        runBackground {
            let s = self.readGuardianStatus()
            self.publish {
                self.guardianStatus = s.summary
                // 把结论一起写进日志：只写"检测完成"的话，导出日志看不到守护到底正不正常
                self.log("ADB 保活守护检测完成 —— \(s.summary)")
            }
        }
    }

    package func deployGuardian() {
        guard isConnected else { return log("请先连接显示器") }
        guard let apk = adb.resources.guardianAPK() else { log("找不到保活 APK（assets/adb_guardian/adbguardian-signed.apk）"); return }
        guardianStatus = "状态：正在部署/修复..."
        log("正在部署 ADB 保活守护...")
        runBackground {
            let r = self.adb.installApk(apk)
            if r.succeeded && r.output.contains("Success") {
                self.adb.shell("pm grant \(Guardian.package) android.permission.WRITE_SECURE_SETTINGS 2>/dev/null || true")
                self.adb.shell("cmd deviceidle whitelist +\(Guardian.package) 2>/dev/null || true")
                self.enableGuardianAccessibility()
                self.startGuardianCommands()
                guard self.adb.pause(3) else { return }
                _ = self.adb.reconnect()
                let s = self.readGuardianStatus()
                self.publish {
                    self.guardianStatus = s.summary
                    self.log(s.ok ? "ADB 保活守护部署并回读验证完成" : "APK 已安装，但保活检查未通过：\(s.summary)")
                }
            } else {
                self.publish {
                    self.guardianStatus = "状态：部署失败"
                    self.log("ADB 保活守护部署失败: \(r.outcome): \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }

    package func startGuardian() {
        guard isConnected else { return log("请先连接显示器") }
        guardianStatus = "状态：正在启动保活..."
        runBackground {
            self.enableGuardianAccessibility()
            self.startGuardianCommands()
            guard self.adb.pause(2) else { return }
            let s = self.readGuardianStatus()
            self.publish {
                self.guardianStatus = s.summary
                self.log(s.ok ? "ADB 保活守护已启动并通过检查" : "已请求启动保活，检查结果：\(s.summary)")
            }
        }
    }

    nonisolated internal func enableGuardianAccessibility() {
        let current = adb.shell("settings get secure enabled_accessibility_services 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let services: String
        if current.isEmpty || current == "null" {
            services = Guardian.accessibility
        } else if current.split(separator: ":").map(String.init).contains(Guardian.accessibility) {
            services = current
        } else {
            services = "\(current):\(Guardian.accessibility)"
        }
        adb.shell("settings put secure enabled_accessibility_services '\(services)'")
        adb.shell("settings put secure accessibility_enabled 1")
    }

    nonisolated internal func startGuardianCommands() {
        adb.shell("am start -n \(Guardian.mainActivity) >/dev/null")
        adb.shell("am broadcast -a \(Guardian.package).ACTION_KEEP_ALIVE -p \(Guardian.package) >/dev/null")
    }

    nonisolated internal func readGuardianStatus() -> GuardianStatus {
        let acc = adb.shell("settings get secure enabled_accessibility_services 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = adb.shell("pm path \(Guardian.package) 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = adb.shell("pidof \(Guardian.package) 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mask = adb.shell("getprop persist.appcontrol_w_mask 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adbEnabled = adb.shell("settings get global adb_enabled 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wifiEnabled = adb.shell("settings get global adb_wifi_enabled 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let servicePort = adb.shell("getprop service.adb.tcp.port 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let persistPort = adb.shell("getprop persist.adb.tcp.port 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adbd = adb.shell("getprop init.svc.adbd 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stopped = adb.shell("dumpsys package \(Guardian.package) 2>/dev/null | grep stopped=true | head -n 1").isEmpty == false
        return GuardianStatus(
            installed: !path.isEmpty && path.hasPrefix("package:"),
            pid: pid,
            accessibility: acc.contains(Guardian.accessibility),
            adbEnabled: adbEnabled == "1",
            adbWifiEnabled: wifiEnabled == "1",
            servicePort: servicePort,
            persistPort: persistPort,
            adbd: adbd,
            mask: mask,
            stopped: stopped
        )
    }


    package var isSimulation: Bool { environment.mode == .simulation }
    package func showMainWindow() { environment.system.showMainWindow() }
    package func quit() { environment.system.quit() }
    package func openProjectSource(upstream: Bool = false) {
        let address = upstream ? "https://github.com/YiHoooong/Mimonitor_Toolbox" : "https://github.com/LI5ee3/Mimonitor_Toolbox"
        environment.system.openURL(URL(string: address)!)
    }
}
