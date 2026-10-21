# 红米G Pro ToolBox — macOS (SwiftUI)

Redmi G Pro 27U / 32U 显示器的原生 macOS 控制工具，使用 SwiftUI、AppKit 和 CoreAudio。
仅支持 macOS 27 及以上的 Apple Silicon Mac（M 系列芯片）。本仓库仅维护 Mac 应用；设备端协议与实现源自 [原项目](https://github.com/YiHoooong/Mimonitor_Toolbox)，在此基础上继续开发。

## Xcode 开发与安全 Preview（R0–R3）

开发与运行均要求 macOS 27 或更新的 Apple Silicon Mac，使用本机已验证的 Xcode 27.1 工具链。

打开 `Toolbox.xcodeproj`，两个共享 scheme：

- **ToolboxApp**：真实应用；运行会启动现有网络 ADB、快捷键和后台任务。
- **ToolboxPreviews**：隔离的 App Target；不链接 `ToolboxMacAdapters`，不包含 adb/JAR/APK。

选 **ToolboxPreviews**，打开 `Sources/ToolboxPreviewSupport/PreviewGallery.swift`，刷新 Canvas。也可以直接运行该 scheme 得到独立预览窗口。顶部选择页面与场景，底部按钮推进虚拟时间；所有权限、文件、终端、登录项和设备动作均为内存模拟。不要用真实 App scheme 预览：生产组合根会检测并拒绝 Xcode Preview 运行上下文。

```sh
swift test
python3 scripts/validate_architecture.py
python3 scripts/validate_preview_boundary.py
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxApp -configuration Release -destination 'platform=macOS,arch=arm64' build
```

生产 App 的 Xcode 资源复制阶段只使用已有 `assets/runtime/adb` 或 `.cache/platform-tools/adb`，不在 Preview 或编译期间下载程序。首次准备运行资源可沿用下方 `build_app.sh` 的官方 platform-tools 缓存流程；必需的 JAR/APK、图标及 NOTICE 缺失时 Xcode 构建失败。CLI `swift build --product MimonitorToolbox` 入口继续保留，应用实现与 Xcode 宿主共享同一库。

当前模块：`ToolboxDomain`（Swift 6 纯规则）、`MimonitorPresetCore`（预设引擎）、`ToolboxApplication`（九个 MainActor Observation 模型与动作协调）、`MimonitorToolbox`（共享 UI）、`ToolboxMacAdapters`（真实平台实现）、`ToolboxPreviewSupport`（内存模拟）。旧 AppState 已移除；架构、阶段验证和回滚见 [R3-ARCHITECTURE.md](R3-ARCHITECTURE.md)。完整并发与进程迁移继续留待 R4。

CI 已显式要求带 `toolbox-macos27` 标签的专用 macOS 27 ARM64 runner；未注册该 runner 时任务会排队。本批未配置远端 runner 或触发远端 CI。同仓库受信任分支可运行，外部 fork PR 不自动在该自托管 runner 上执行。

构建产物不自动替换已安装/正在运行的应用；先检查签名和资源，再由用户选择安装。正式 Developer ID、公证和发布治理属于 R6。

## ADB 音量控制

键盘音量加减和静音通过已连接的网络 ADB 控制显示器，声音可继续通过 DP/HDMI 输出。保留辅助功能授权、默认音频输出限制、自定义步长和原生 OSD 16 格。ADB 离线时不接管系统音量键；CoreAudio 只读取默认输出设备，不写入音量。原蓝牙控制已移除，系统配对不受影响。

## 本分支更新：唤醒恢复与保活状态验证

- 同时响应 Mac 系统唤醒和屏幕唤醒，延迟 1.5 秒检查网络 ADB；连接失败后继续使用现有周期重连机制。
- 检查实际 ADB shell 探针，避免把残留的 `device` 状态误判为连接正常。
- 连接恢复后刷新媒体音量和 AdbGuardian 状态；唤醒时连接仍正常也刷新这两项状态。
- 用户主动断开或切换连接后，不执行旧唤醒事件排队的重连。
- AdbGuardian 安装或启动后，日志依据设备端回读检查给出成功或未通过原因，避免仅因 APK 安装成功就提示部署完成。

网络 ADB 仍需 Mac 和显示器处于可互通的网络。显示器深度待机时网络可能关闭，恢复时间取决于显示器系统和 AdbGuardian；Mac 端无法在网络不可达时修改显示器设置。

在 Mac mini M4、Redmi G Pro 32U 2026（P32UEA-RGP，固件 OS3.0.120.0.UFFMAMN）上，前序实机测试中电源键待机唤醒约 18 秒恢复 ADB、Android 重启约 41 秒首次连通且约 58 秒起稳定、DP 息屏唤醒约 28 秒恢复 ADB。这些是该设备和网络下的观察结果，其他型号和固件仍需实测。

本分支沿用原项目的网络 ADB 连接界面。

## C 方向界面更新：屏幕即遥控器

- 用顶部导航替代固定侧栏；画面、游戏、信号源、灯光、预设、自动任务和遥控器均保留独立入口，工具与菜单栏配置在右上角设置中。
- 首页以显示器轮廓呈现连接、输入源和画面模式，下方集中放置音量、静音、背光与常用模式。未知读数显示「—」，断开时禁用设备控制。
- 音量滑块和静音复用现有媒体音量提交逻辑；键盘音量键仍保留原来的输出设备过滤、步长、OSD 与权限设置。
- 统一浅色/深色配色、分组和选中状态，重排长页面与快捷键配置；高级系统操作保持可访问，部署保活前明确说明权限与影响。
- 提供按压反馈、导航选中块过渡和首次进入淡入；响应系统「减少动态效果」。自绘滑块支持辅助功能增减操作。

<img src="assets/screenshots/ui-c-home.png" width="800" alt="C 方向控制台">
<img src="assets/screenshots/ui-c-remote.png" width="800" alt="C 方向遥控器">

本轮通过 Swift debug 构建、全部页面原生界面检查，以及隔离模拟设备上的音量/静音、断开重连、预设创建/重命名/收藏、自动任务保存和重启读回检查。没有向真实显示器发送 UI 测试指令，也没有重复测试真实键盘拦截或显示器待机/重启。下方旧版截图保留作历史参考。

## 命名

对外的名字是「红米G Pro ToolBox」，但两个内部标识**保持英文、不要改**：

| | 值 | 为什么 |
| --- | --- | --- |
| bundle id | `com.mimonitor.toolbox` | 权限、保存的 IP、快捷键配置都挂在它上面 |
| 可执行文件名 | `MimonitorToolbox` | 必须与 `Package.swift` 产物名、`CFBundleExecutable` 三者一致 |

`.app` 的目录名可以用中文（系统不看目录名）。唯一副作用：改名后已授权的机器会重新
问一次权限，重新允许即可 —— bundle id 和签名身份没变。

**分发文件（DMG / zip）的文件名必须是 ASCII**：GitHub Release 会改写非 ASCII 名
（实测 `红米G Pro ToolBox.dmg` → `G.Pro.ToolBox.dmg`，中文被剥掉、空格变点）。
由 `PACKAGE_NAME` 控制，CI 有白名单校验。DMG 的**卷标**和包内的 `.app` 不受影响，仍是中文。

## 旧版软件截图

以下为改版前截图，均为深色模式（`assets/screenshots/`）。

| | |
| --- | --- |
| **主页 & 连接**<br><img src="assets/screenshots/home.png" width="420"> | **画面设置**<br><img src="assets/screenshots/picture.png" width="420"> |
| **游戏模式**<br><img src="assets/screenshots/game.png" width="420"> | **信号源切换**<br><img src="assets/screenshots/source.png" width="420"> |
| **屏幕灯**<br><img src="assets/screenshots/light.png" width="420"> | **菜单栏**<br><img src="assets/screenshots/menubar.png" width="420"> |
| **工具与设置**<br><img src="assets/screenshots/tools.png" width="420"> | **遥控器**<br><img src="assets/screenshots/remote.png" width="420"> |

**菜单栏面板**（点顶栏图标展开，不用开主窗口就能调）：

<img src="assets/screenshots/menubar-panel.png" width="320">

## 运行前提

最终用户双击 .app 即可，**不需要装任何东西**。从源码构建只需要 **Xcode 命令行工具**
（`xcode-select -p` 能返回路径）。adb 在打包时自动下载并内嵌。显示器需已开启无线 ADB（端口 5555）。

## 应用图标

`assets/AppIcon.png` 是独立的 1024×1024 图标源。修改后运行 `./make_icon.sh`，生成包含标准尺寸的 `assets/AppIcon.icns`；打包直接使用 icns。

## 编译 / 运行

```bash
cd macos
swift build
swift test                 # 连接状态与 ADB 客户端回归测试
swift run MimonitorToolbox     # 开发调试
```

### 打包

```bash
./build_app.sh
open "红米G Pro ToolBox.app"
```

产物：`红米G Pro ToolBox.app`（约 20MB，自包含、零外部依赖）+ `MimonitorToolbox-macos-arm64.dmg`。

构建固定使用 `--arch arm64`，不提供其他架构或通用包。主程序和内嵌 adb 都只包含 arm64；从官方 platform-tools 获取的多架构 adb 在打包时提取 arm64，原始缓存保持不变。

脚本会内嵌 adb（仓库里没有就从 Google 官方下载，缓存在 `macos/.cache/`）、两个 jar、
保活 apk，生成 `Info.plist`，签名，最后打 DMG。想固定 adb 版本就把 macOS 版 adb
放到仓库根的 `assets/runtime/adb`。

```bash
./reinstall.sh --no-build      # 本机安装到 /Applications 并重启
```

### 签名与分发

用 `setup_signing_cert.sh` 创建的自签名证书签名。**不能用 ad-hoc**：macOS 15 起
「本地网络」权限要靠稳定的代码身份才能记住授权，而 ad-hoc 的身份是内容哈希、每次编译
都变，系统认不出会**静默拒绝**（连弹窗都不给）—— 表现就是「连不上、也搜不到显示器」，
界面上没有任何提示。固定证书的身份是「bundle id + 证书指纹」，跨编译稳定。

```bash
./setup_signing_cert.sh            # 本机：创建固定证书
./export_signing_cert.sh --write   # CI：导出并写进 GitHub Secrets（需 gh 已登录）
```

CI 用 `MACOS_CERT_P12` / `MACOS_CERT_PASSWORD` 两个 Secret。没配时回退 ad-hoc
（fork 提的 PR 走这条路），但校验步骤会在「配了证书却仍打出 ad-hoc 包」时**直接失败**。

别人拿到 DMG 后首次打开会被 Gatekeeper 拦一次，需到 **系统设置 → 隐私与安全性**
点「仍要打开」。要彻底消除提示需要 Apple Developer ID（$99/年）+ 公证。

## 首次使用注意

- **全局快捷键**需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能。
  **授权后必须重启 app** —— TCC 的授权结果是进程启动时读取的。
- **开机自启动**（LaunchAgent）写入后需重新登录才生效。

## 目录结构

```
macos/
├─ Toolbox.xcodeproj/             # 原生 App / 安全 Preview App Target
├─ Config/                       # Info.plist、开发签名权限
├─ Package.swift                 # 共享模块与 CLI 兼容宿主
├─ prepare_runtime.sh            # Xcode 生产 Target 的离线资源准备
├─ build_app.sh / make_dmg.sh     # 保留的 CLI 打包与 DMG 流程
├─ scripts/validate_preview_boundary.py
└─ Sources/
   ├─ ToolboxApp/                # 生产组合根、AppDelegate、Dock 生命周期
   ├─ ToolboxPreviewHost/        # 独立安全预览 App 入口
   ├─ ToolboxPreviewSupport/     # #Preview 画廊、内存设备和虚拟时间
   ├─ ToolboxMacAdapters/        # Process、tap、CoreAudio 读取、HUD、资源、登录项
   ├─ ToolboxDomain/             # 独立 Swift 6、映射、范围、步进和纯值规则
   ├─ MimonitorPresetCore/       # 预设模型、计划、迁移、存储接口
   ├─ ToolboxApplication/       # Observation 模型、动作协调、无 Process 的命令门面
   └─ MimonitorToolbox/          # 共享 UI、环境注入和主题
```

首批改造的范围、验证与限制见 [REFACTORING.md](REFACTORING.md)。

## Mac 功能

| 功能 | 实现 |
| --- | --- |
| 画面 / 游戏 / 信号源 / 屏幕灯 / 遥控器 | 网络 ADB、settings 与显示器端 JNI |
| 键盘音量键 | 网络 ADB；支持自定义步长及 16 格 OSD |
| 全局快捷键与亮度键 | CGEventTap，需辅助功能权限 |
| HDR/SDR 分区控光记忆 | 主机 EDR 与显示器画面模式综合判断 |
| 登录后自动启动 | LaunchAgent |
| ADB 保活守护 | AdbGuardian 部署与实际状态回读 |
| APK 安装 / ADB 命令行 / 4K UI | 工具页高级功能 |
| 日志 | 落盘、导出与打开目录 |
| 网络扫描 | ifconfig 网段识别与 TCP 探测 |
| 主题与悬浮提示 | 跟随系统 / 深色 / 浅色；自定义 HUD 或原生 OSD |

### 系统集成

| 能力 | 说明 |
| --- | --- |
| **菜单栏常驻 + Dock 图标按需显隐** | 普通 app 身份（启动台能找到），关掉窗口后 Dock 图标收起、只留顶栏 |
| **菜单栏快捷项**（「菜单栏」页） | 自选把哪些控制放进顶栏下拉：画面模式 / 精密控光 / 色域 / 色温 / 背光… 支持拖动排序 |
| **菜单栏面板** | 顶栏下拉是 `.window` 样式面板 —— 选项型是下拉、数值型是真滑块，不用开主窗口就能调 |
| **悬浮提示（HUD）** | 按快捷键时屏幕底部弹出，带倒计时进度条 |
| **独立 adb 终端** | 「ADB CMD」开的终端里已注入 PATH 与端口，可以直接敲 `adb devices` |
| **主题切换** | `NSApp.appearance` 全局生效，悬浮窗等 AppKit 面板也跟着变 |

## 设计要点

实现中需要关注的行为与边界。**详细原因写在对应源码的注释里**，这里只列要点。

**通信与状态**

- **网络扫描**：`SO_SNDTIMEO` 不约束 `connect()`，连不存在的主机会一直等 ARP 超时并占满线程池，结果「什么都扫不到」。必须非阻塞 connect + `poll` + 回读 `SO_ERROR`。
- **`adb connect` 是异步的**，挂上 TCP 就返回，此时 `get-state` 往往还是 `offline`，要轮询等它翻转。健康监控在 `.connecting` / `.scanning` 期间必须让路，否则会把进行中的连接打断。
- **循环动作（如 FreeSync 开关）的当前状态必须现读设备**。拿缓存值判断时，一次 JNI 回读失败就会把缓存留在 0，于是每次都算出「要开启」→ 按了没反应。
- **页面刷新分两阶段**：`settings list global` 一次拿回全部（~0.08s）先上屏撤掉遮罩，JNI `batchGet`（~0.9s）到达后静默修正。逐个 `settings get` 要 2.29s，差 28 倍。
- **画面页的值以 JNI 回读为准**：用户用显示器自带 OSD 改过设置后，`settings get` 会和硬件实际状态漂移。
- **FreeSync Pro 记忆只记「标准 / 游戏 / 电影」三个模式**。`picture_mode` 里混了信号驱动的值（Dolby Vision、HDR 系列）和用户手选的值，光看数字分不出，强行还原可能和当前信号不匹配。

**界面**

- **不要用 SwiftUI 的 `Slider`**：底层 `NSSlider` 每次创建都要向 CoreUI 解析主题 rendition，6 个滑条就是 500ms。用自绘的 `FastSlider`。`Color(nsColor:)` 这类 AppKit 语义色同理，改用 `Theme.card` / `Theme.control`。
- **改动后的刷新必须合并**：改画面模式会连带换掉一整套参数，需要延迟重读，但每次改动都排一次刷新会让连按 10 次 = 10 次全文刷新，ADB 通道被占满。用 `scheduleCoalescedRefresh` 取消上一次未执行的刷新。
- **Dock 图标按需显隐**：不设 `LSUIElement`（设了会被当成后台型 app，启动台 / Dock / Cmd+Tab 全都看不到），由 `DockVisibility` 按「有没有可见窗口」运行时切 `.regular` / `.accessory`。判定窗口时要认标题栏 —— 菜单栏图标自己也是一个可见窗口。
- **快捷键防抖是「前沿 + 尾部」**：450ms 窗口内单按立刻生效，连按只推进预览、停手后补发最终值。纯尾部防抖会让单按也白等 450ms，手感是「迟滞」。
- **主题用 `NSApp.appearance`** 而不是 `.preferredColorScheme`，后者只影响被修饰的那棵视图树，AppKit 面板会漏掉。

**快捷键**

- **ANSI 按键码要逐个列出**，不能按 `kVK_ANSI_A + 偏移` 硬算 —— macOS 的字母按 QWERTY 物理位置排（A=0x00, D=0x02, C=0x08…），数字也乱序。见 `HotkeyMap.ansiTables`。
- **`CGEventTap` 回调太慢会被系统静默 disable**（tap 还在，只是收不到事件），要处理 `tapDisabledByTimeout` 并重新 enable。`tapCreate` 失败会返回 nil 且不报错，所以 `start()` 返回 Bool 并把结果写进日志。
- **亮度调节键有多种到达形式，要全覆盖**：`NX_SYSDEFINED`（事件类型 14、subtype 8、data1 高 16 位是键类型 2/3）、普通 keyDown 的 keyCode 144/145（Apple 内置键盘常见）、以及开了「功能键当标准功能键」后发出的普通功能键 keyDown。前两种要在 tap 回调里 `return nil` 把事件吞掉，否则内置屏幕会跟着变亮度。见「自定义全局快捷键」面板里的「亮度调节键调显示器背光」。
- **亮度键：反馈立即，写入去抖**。OSD/HUD 立刻跟着手走，但真正写显示器只在停手后合并；每个中间值都触发写会造成来回闪。约一个原生 OSD 格（6–7%）只做一次 JNI 写入，不拆成多个 1% 小步；更大的变化保留渐变。另外**背光写入不发 `refreshPq`**：`PIC_MODE_CHANGED` 广播会让显示器重载画面参数、背光闪一下；`settings put`（ContentObserver 立即生效）+ `JNI set`（直接改硬件）已经足够。基准值也要「粘住」，不能中途读设备回读值。预览由所有写背光的路径共同维护，只在应用预设时清空。
- **步进首次对齐**：亮度值不在步长格点上时，第一次按键先跳到方向上的最近格点（6、步长 10 → 10），之后按步长增减。见 `ControlStep.alignToStep`。
- **原生亮度 OSD** 走私有 `com.apple.OSDUIHelper`（macOS 26/27 的 mach service），和系统亮度键弹出的提示条是同一套；调用失败就回退到自绘 HUD。开原生 OSD 时步长固定为「16 格、每按一次一格」——否则用户步长（如 10）和 16 格对不齐，会出现按一下走一格、再按走两格的抖动。
- **多屏鼠标门**：亮度键只在鼠标位于目标显示器（默认按系统名 `Mi Monitor` 匹配，可在面板改）上时拦截，否则原样放行给系统；找不到目标显示器时不过滤。
- **音量调节键**：同样覆盖 `NX_SYSDEFINED`（键类型 0/1/7）和普通 keyDown（keyCode 72/73/74），开了「功能键当标准功能键」时兜底 F12/F11/F10。与亮度键不同，**只有当前默认音频输出（CoreAudio）的名字匹配目标时**才拦截（默认关键字 `Mi Monitor`；eqMac 转发出来的「Mi Monitor (eqMac)」也能命中），其余情况原样交给系统去调内置扬声器 / AirPods。读不到输出设备名时也不拦截。
- **音量走 AudioService binder，不用 keyevent 逐级发**：`cmd media_session volume --set` 在这台机器上会被 AudioService 拒掉（它把 callingPackage 写死成 `com.android.server.media`，过不了 AppOps 的包名/uid 校验），`settings put system volume_music_speaker` 没有观察者、不触发 AudioService。直接 `service call audio` 调 `setStreamVolume` / `adjustStreamVolume`（静音 ±100）/ `isStreamMute` 才是既精确又快（一次往返）的通道；txn code 和系统版本绑定，首次调用会回读验证，失败退回 `input keyevent` 逐级调整。读音量要用 `getStreamVolumeForMute`：`getStreamVolume` 在静音时返回 0，而 `settings` 在刚写完的约 1 秒内还是旧值。
- **不弹显示器自己的音量 UI**：实测 binder 路径（`setStreamVolume` / `adjustStreamVolume`，flags=0）不会触发 Xiaomi SystemUI 的 `VolumeUIMananger` 窗口（`dumpsys window` 里不会出现），所以音量条只在 Mac 这边弹；只有 `input keyevent` 回退路径会让显示器自己弹条。静音也一样：`adjustStreamVolume` 的 ±100 不弹，`KEYCODE_VOLUME_MUTE` 会弹。
- **音量键的反馈和去抖**：和亮度键一致——OSD/HUD 立即跟手、连按合并成最后一次绝对写入；静音状态下按音量加减键会先解除静音（跟系统行为一致）。

**调试方法**

- **测量工具本身会骗人**。AppleScript 的 `entire contents` 一次查询要 ~4 秒且会打热 CoreUI；`keysend` 每次进程启动要 120ms。测 UI 耗时用 `screencapture` 截图对比（`measure_render.py`），别用 AX 查询。
- **UI 不刷新时，先确认你读到的是最新状态**：`sqlite3` 加 `?immutable=1` 会忽略 WAL，读一个正在被写的库会拿到旧快照。
- **`log show` 在部分机器上抓不到进程日志**，调试时写文件更可靠。
- **崩溃日志在 `~/Library/Logs/DiagnosticReports/*.ips`**，先看 faulting thread 的调用栈，基本能直接定位。
- **`@objc private protocol` 不能嵌在类里给 `NSXPCInterface` 用**：那时 `remoteObjectProxy as? Protocol` 的动态转换会直接崩（swift_dynamicCast → EXC_BAD_ACCESS）。协议放文件作用域就好（加 `@objc(名字)`）。

## JNI 验证工具

`verify_jni.py` 核对「app 显示的值」和「显示器硬件实际值」是否一致：

```bash
python3 verify_jni.py     # 需要已连接显示器（adb server 在 5038）
```

记录所有被测键的原始值 → 逐个写入不同值并回读比对 → **无条件还原**。
EDID / FreeSync 这类会改变显示器输入信号格式（可能黑屏或改分辨率）的键只读不写。

- **色彩增益写入是异步的**，约 0.5s 后才生效。立刻回读拿到旧值不是故障。
- **HDR 色调映射只在部分画面模式下存在**，SDR 模式下隐藏该控件。

## CI

`.github/workflows/macos.yml` 是本项目唯一的应用构建与发布流程：

- **触发**：主分支的 push / PR（包含共享资源的变动）、`v*` 标签，以及手动运行
- **runner**：需要专用的 macOS 27、Apple Silicon、Xcode 27.1 自托管 runner，标签为 `toolbox-macos27`；未配置时任务会排队。本轮没有注册 runner 或运行远程 CI。外部 fork PR 不运行自托管构建。
- **build**：平台检查 → debug 编译与单元测试 → Preview 边界及原生 Target 构建 → 原有签名打包与产物校验 → 上传 artifact
- **release**：仅标签触发，把 DMG 和 zip 附到 GitHub Release

校验步骤逐项确认：可执行文件存在、内嵌 adb / 两个 jar / 保活 apk 齐全、**确实是
仅含 arm64 的主程序与内嵌 adb**、签名有效且**不是 ad-hoc**、`LSUIElement` 未被设置、
分发包文件名只含 `[A-Za-z0-9._-]`、内嵌的 adb 真的能跑起来。
