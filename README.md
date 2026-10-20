# 红米G Pro ToolBox for Mac

Redmi G Pro 27U / 32U 显示器的原生 macOS 控制应用，使用 SwiftUI、AppKit 和 CoreAudio。仅支持运行 macOS 13 及以上的 Apple Silicon Mac（M 系列芯片）。

本项目基于 [YiHoooong/Mimonitor_Toolbox](https://github.com/YiHoooong/Mimonitor_Toolbox) 的设备协议与 macOS 实现继续开发，保留原作者贡献。当前仓库仅维护 Mac 应用。

## 功能

- **蓝牙优先的键盘音量控制**：无需网络 ADB，声音仍可走 DP/HDMI；步长设为 1 并关闭原生音量 OSD 后，每次短按按显示器整数音量加减 1。蓝牙不可用时回退至已连接的网络 ADB。
- **画面与游戏设置**：画面模式、背光、色温、色域、精密控光、FreeSync、准星等；具体选项取决于显示器型号与固件。
- **信号源、屏幕灯与遥控器**：切换输入源、调节灯效，并使用虚拟遥控器。
- **Mac 集成**：菜单栏快捷控制、全局快捷键、自定义悬浮提示、亮度键控制背光、登录后自动启动、深浅色主题。
- **预设与自动任务**：保存画面设置、管理常用预设与定时操作。
- **网络 ADB 恢复**：Mac 唤醒后检查实际连接并自动重连，刷新音量与保活状态。
- **AdbGuardian 部署与回读验证**：安装显示器端保活组件后确认实际运行、端口和权限状态。

<img src="macos/assets/screenshots/home.png" width="700" alt="Mac 应用主页">

更多截图、配置和实测范围见 [Mac 使用与开发说明](macos/README.md)。

## 使用条件

- Apple Silicon Mac（M1 或更新的 M 系列芯片），运行 macOS 13 或更高版本。
- 网络 ADB 功能需要显示器开启 ADB，且 Mac 与显示器可通过网络互通（TCP 5555）。视频线本身不提供网络连接。
- 蓝牙音量控制需要先在 macOS 中配对并连接显示器的蓝牙音频设备；无需网络 ADB。其他显示器设置仍通过 ADB 完成。
- 全局键盘控制需要 macOS 辅助功能授权。

已在 Mac mini M4 + Redmi G Pro 32U 2026（P32UEA-RGP）上验证蓝牙音量、网络 ADB 与唤醒恢复。其他型号及固件的兼容性需实测。

## 从源码构建

安装 Xcode 命令行工具后，在仓库根目录运行：

```sh
cd macos
swift build
swift test
./build_app.sh
open "红米G Pro ToolBox.app"
```

生成仅含 arm64 的应用及 `MimonitorToolbox-macos-arm64.dmg`。主程序和内嵌 adb 都仅保留 Apple Silicon 架构。

打包会从 Google 官方获取 macOS 版 adb 并缓存，内嵌 adb、显示器端 JAR 与 AdbGuardian APK。最终用户无需安装 Python、Java 或 adb。使用 DMG 时，将应用拖入 Applications 即可。

## 通信与资源

```text
Mac 原生应用
├─ CoreAudio / 蓝牙 AVRCP → 显示器音量
└─ 网络 ADB（TCP 5555）→ 显示器 Android 系统
   ├─ settings / AudioService → 设置与媒体音量
   ├─ MtkDirectTool.jar → MTK 画面控制
   ├─ ColorfulLedTool.jar → 屏幕灯控制
   └─ AdbGuardian APK → 显示器端 ADB 保活
```

JAR 和 APK 在显示器端运行，是 Mac 应用的设备通信资源。Mac 应用通过 ADB 自动部署所需 JAR；AdbGuardian 由用户在工具页选择部署。

```text
Mimonitor_Toolbox/
├─ macos/
│  ├─ Package.swift               # Swift Package 清单
│  ├─ Sources/                    # 原生应用与预设核心
│  ├─ Tests/                      # Swift 回归测试与可选实机测试
│  ├─ assets/                     # Mac 图标源、icns 与截图
│  ├─ build_app.sh / make_dmg.sh  # App 与 DMG 打包
│  └─ README.md                   # 配置、签名、测试与开发说明
├─ assets/
│  ├─ runtime/                    # 显示器端 JAR
│  └─ adb_guardian/               # 显示器端保活 APK
├─ tools/                         # JAR 的 Java 源码
└─ .github/                      # Apple Silicon CI、发布流程与反馈模板
```

## 持续集成

主分支 push / PR 执行 macOS 构建和 Swift 测试，随后打包、检查资源与签名、上传 DMG / ZIP。`v*` 标签触发 Mac Release 发布；签名与分发要求见 [开发说明](macos/README.md#签名与分发)。
