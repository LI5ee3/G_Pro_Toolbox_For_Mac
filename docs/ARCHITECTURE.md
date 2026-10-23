# 现行架构与运行边界

更新：2026-10-23，S2-04。本文描述当前源码，进度、验收与后续授权统一以 [ROADMAP](ROADMAP.md) 为准；[ADB-CONTRACTS](ADB-CONTRACTS.md) 第 0 节记录已实施的 TCP/server、手动 USB 和身份/配置边界；控制入口完整审查、生命周期与 Auto 仍待后续门禁。本文不把设计类型或历史真机结果当作当前已实现、已复验功能。

## 平台、模块与语言模式

运行平台为 Apple Silicon / macOS 27+，开发工具链为本机已验证的 Xcode 27.1。[Package.swift](../macos/Package.swift) 定义共享模块；[Xcode 工程](../macos/Toolbox.xcodeproj/project.pbxproj) 提供原生 App 和安全 Preview 宿主，均为 arm64、最低 macOS 27、Swift 5 语言模式。Swift 工具链版本、Package tools version 与各模块 language mode 是不同概念。

下表列出所有生产/Preview target 的直接内部依赖；依赖名称是 target，`ToolboxUI` 是 `MimonitorToolbox` 对外的 library product。

| Target | 直接内部依赖 | Swift 模式 / 职责 |
| --- | --- | --- |
| ToolboxDomain | 无 | 6；端点与状态值、固件映射、范围、步进等纯规则，仅导入 Foundation |
| ToolboxConcurrency | 无 | 6；请求/结果、取消、FIFO 执行桥和任务所有权 |
| ToolboxProcessExecution | ToolboxConcurrency | 6；有界 POSIX 进程执行与资源回收 |
| MimonitorPresetCore | ToolboxDomain | 6；预设模型、计划、引擎、存储接口及 PresetWorker |
| ToolboxApplication | ToolboxDomain、MimonitorPresetCore、ToolboxConcurrency | 5；状态模型、动作协调、注入端口、ADB 命令门面与快捷键解析 |
| MimonitorToolbox | ToolboxApplication、ToolboxDomain、MimonitorPresetCore | 5；共享 SwiftUI 页面、控件、主题和宿主会话接口 |
| ToolboxMacAdapters | ToolboxProcessExecution、ToolboxConcurrency、ToolboxApplication、ToolboxDomain、MimonitorPresetCore | 5；真实平台端口、资源、登录项、音频读取、日志、HUD 与预设设备适配 |
| ToolboxPreviewSupport | ToolboxConcurrency、MimonitorToolbox、ToolboxApplication、ToolboxDomain、MimonitorPresetCore | 5；内存设备、偏好、假系统动作与虚拟时间 |
| ToolboxApp | MimonitorToolbox、ToolboxMacAdapters | 5；生产组合根及 App/Dock 生命周期 |
| ToolboxPreviewHost | ToolboxPreviewSupport | 5；独立安全预览窗口 |

Application 不导入 SwiftUI 或生产适配器，也不启动真实进程；它仍使用 [AppKit 端口类型](../macos/Sources/ToolboxApplication/RuntimePorts.swift) 和 [Cocoa/Carbon 快捷键类型](../macos/Sources/ToolboxApplication/Platform/HotkeyManager.swift)，并非跨平台纯 Foundation 层。四个 Swift 6 模块不含 `@unchecked Sendable`；其余模块的 Swift 5 过渡边界不能通过文档或直接翻编译开关视为完成迁移。真实进程执行位于 [SystemProcessRunner](../macos/Sources/ToolboxProcessExecution/SystemProcessRunner.swift)，由 MacAdapters 注入。

## 状态与生命周期所有权

旧 AppState 已移除。[AppCoordinator](../macos/Sources/ToolboxApplication/AppCoordinator.swift) 是 MainActor 动作协调器，不承担全局可观察通知；[ToolboxSession](../macos/Sources/MimonitorToolbox/ToolboxSession.swift) 为宿主提供 start/stop 与窗口内容入口，将以下九个 `@MainActor @Observable` 模型注入 UI。

| 模型 | 所有状态 |
| --- | --- |
| [SettingsModel](../macos/Sources/ToolboxApplication/StateModels/SettingsModel.swift) | 外观、关窗行为、登录项读回状态 |
| [LogModel](../macos/Sources/ToolboxApplication/StateModels/LogModel.swift) | 日志行、滚动序号、记录开关 |
| [ConnectionModel](../macos/Sources/ToolboxApplication/StateModels/ConnectionModel.swift) | 手动方式/端点、发现与连接状态、输入/候选、会话身份与能力 |
| [PictureModel](../macos/Sources/ToolboxApplication/StateModels/PictureModel.swift) | 显示器读数、页面加载状态、画面派生说明 |
| [VolumeModel](../macos/Sources/ToolboxApplication/StateModels/VolumeModel.swift) | 首页音量、静音和错误 |
| [PresetsModel](../macos/Sources/ToolboxApplication/StateModels/PresetsModel.swift) | 配置快照、忙状态、操作/错误和任务状态 |
| [NavigationModel](../macos/Sources/ToolboxApplication/StateModels/NavigationModel.swift) | 动作请求的页面跳转 |
| [ToolsModel](../macos/Sources/ToolboxApplication/StateModels/ToolsModel.swift) | Guardian、4K UI、控光/FreeSync 记忆和准星说明 |
| [HotkeysModel](../macos/Sources/ToolboxApplication/StateModels/HotkeysModel.swift) | 快捷键、媒体键、步长、OSD 和菜单项偏好 |

任务、队列、取消句柄、定时器和硬件提交缓存留在协调/执行层，不放进这些模型。UI 读取所需模型，修改通过动作入口；协调器中的计算转发属性不复制状态或广播汇总通知。适配器内部的 [HUDModel](../macos/Sources/ToolboxMacAdapters/HUDWindow.swift) 仍使用 ObservableObject，不能推断全项目已移除该机制。

构造组合根不启动硬件服务。生产 `start()` 启动反馈、输出监控、权限/登录项读回、热键、后台任务和 ADB 预热；simulation 提前返回，不走这些真实服务。`stop()` 取消会话、工作项、系统任务及调度，停止监听和反馈；退出日志由宿主使用有界排空完成。服务生命周期属于应用会话，关主窗口是否退出由原偏好决定。[生产组合根](../macos/Sources/ToolboxMacAdapters/LiveRuntime.swift) 与 [App 宿主](../macos/Sources/ToolboxApp/App.swift) 均拒绝 Xcode Preview 上下文。

## 并发与进程执行

[submitOperation](../macos/Sources/ToolboxApplication/AppCoordinator+Support.swift) 在 MainActor 捕获不可变 ADB 子会话与应用生命周期代次，通过 [BlockingExecutor](../macos/Sources/ToolboxConcurrency/BlockingExecutor.swift) 按 FIFO 提交到连接/设备队列；整项同步协议工作共享 AdbClient 的递归事务锁。TaskLocal 在阻塞工作入口显式安装，嵌套 helper 继承同一目标；锁不跨 await，也不在 MainActor 阻塞等待进程。

`OwnedWorkSet` 拥有根工作项；取消单项不取消同会话其他工作。切换目标、同址重新 beginSession、断开或停止使旧会话失效；发布结果同时检查取消与生命周期，账务完成另有生命周期检查。系统操作使用独立队列和取消令牌，切换显示器不取消登录项动作。[PresetWorker](../macos/Sources/MimonitorPresetCore/PresetWorker.swift) 用同一个 Mutex 独占预设引擎和连接登记事务，只让 Sendable 配置/报告快照离开；FreeSync 连续操作的最新记忆和 settle 状态归设备队列。

[CommandRequest / ProcessResult](../macos/Sources/ToolboxConcurrency/Command.swift) 保留 argv、serverPort、期限、取消及完整退出状态。SystemProcessRunner 使用独立进程组、有界 stdout/stderr、超时/取消和回收；`succeeded` 不接受超时、取消、非零退出或截断。现行 legacy String shell helper 的完整失败语义治理仍是 ROADMAP 的 A08，不把严格预设/JNI/server 路径推广为所有旧 helper 已修复。

取消只能阻止后续工作，不能撤回已经到达显示器的写入。用户明确打开的外部 Terminal 独立于应用事务锁与取消，不提供跨进程单写保证。

## ADB 目标、身份与恢复边界

- [AdbEndpoint](../macos/Sources/ToolboxDomain/AdbEndpoint.swift) 支持 TCP host/port 和经枚举类型验证的 USB serial；设备端口默认 5555，手动输入校验 1–65535。显式发现不激活会话，不自动选择首项；Auto 未实现。
- [AdbSession](../macos/Sources/ToolboxApplication/Backend/AdbSession.swift) 固定提交时的 endpoint、clientID、sessionID 和取消令牌；nil 表示没有设备目标。设备命令显式使用该会话 serial，不退回 adb 默认设备。clientID 区分客户端实例，sessionID 区分每次接入；两者都不是物理设备身份。
- [AdbClient](../macos/Sources/ToolboxApplication/Backend/AdbClient.swift) 的 ip / beginSession(ip:) / disconnect(ip:) 保留为旧 UI/配置兼容入口。serverPort 默认 5038，独立于设备端口，也不表示应用独占该 server。
- [预设提交](../macos/Sources/ToolboxApplication/AppCoordinator+Presets.swift) 把 endpoint 与已确认的兼容身份键分别交给 [AdbPresetDevice](../macos/Sources/ToolboxMacAdapters/AdbPresetDevice.swift)。预设目标固定在提交时，identity 只做原所有权判断。picture_presets_v1 原始 JSON 不批量迁移，connection_profile_v1 保存明确确认的稳定属性证据、旧别名和全局记忆唯一归属；旧 IP 相等不能证明历史所有权。
- 发现状态独立于连接状态，待授权/离线/失败明确显示。严格 get-state 与只读 shell 探针通过后读取本次会话的两项稳定属性；未确认暂停预设/任务/记忆，未知可人工确认当前会话，冲突取消会话并清空端点。固件属性的可靠性尚待真机验证。
- `ensureConnected` 集中现有 TCP 恢复决策：优先原 get-state/shell 探活与目标级 connect/等待/探活；unauthorized 立即返回，不进入 shell/server 恢复。目标恢复失败后，私有边界最多执行一次 3 秒 `host-features` 查询，成功且 stdout 非空才允许最终目标重试；用单调时间施加 25 秒冷却，失败也记账，切换目标不重置冷却。
- 应用不再显式循环 kill-server。`host-features` 是主动 server 查询，官方 adb 仍可能启动缺失 server 或协调不兼容版本；它不是被动健康探测，也不证明设备 ready。多客户端冲突与真实 USB/TCP 恢复未在阶段一获得硬件验收。

生产连接不再隐式保存 IP，明确保存 TCP:5555 才镜像 saved_ip；新 envelope 优先。已经验证且确认的接入仍可能部署 JAR、触发已获准的记忆/预设任务，因此不能当作只读设备探针。USB 数据链路、视频信号源与默认音频输出是独立事实；历史 CLI 验证不替代 App 真机验收。USB 插拔/睡眠恢复与 Auto 没有在 S2-04 实现。

## 偏好与未知读数

[PreferencesStore](../macos/Sources/MimonitorPresetCore/Preferences.swift) 隔离存储，生产注入用户偏好，Preview 注入带锁的 MemoryPreferences。现行预设引擎和旧配置结构保持；读取异常值不授权自动清理用户原始数据。连接登记使用同一 PresetWorker 的原值比较、私密备份、写后回读和失败保护；只证明当前存储视图，不提供断电持久事务或跨进程 CAS，具体恢复限制见 ADB-CONTRACTS §0.3。

S1-06 的 [控光记忆](../macos/Sources/ToolboxApplication/AppCoordinator+DisplayMemory.swift) 使用现有合法映射 0…3：非法 Int/错误 JSON 的显示和应用路径安全退出，不向设备下发非法值，也不在读取时改写偏好原字节；[设置入口](../macos/Sources/ToolboxApplication/AppCoordinator+DisplayCommands.swift) 同样拒绝范围外值。

S1-07 的 [游戏 JNI 派生](../macos/Sources/ToolboxApplication/AppCoordinator+Refresh.swift) 复用严格 batch 结果，失败、缺失、空值、未知来源或枚举分别保留未知，不冒充关闭，也不保留上次确定值。合法 DP/HDMI 的 320Hz、FreeSync 映射保持；[游戏页](../macos/Sources/MimonitorToolbox/Views/GameView.swift) 明示“未知”且没有开/关选中。此处只治理这两项读数，不宣称全应用未知状态或 A08 已完成。

## 真实平台与安全 Preview

[LiveRuntime](../macos/Sources/ToolboxMacAdapters/LiveRuntime.swift) 注入真实资源与 SystemProcessRunner、热键、只读 CoreAudio 默认输出、HUD、文件日志和系统动作。新登录项只用 [SMAppService.mainApp](../macos/Sources/ToolboxMacAdapters/Autostart.swift)，按系统状态读回；旧 LaunchAgent 仅在归属验证、备份和新服务启用确认后退役。权限请求成功不等于权限授予，注册成功不等于下一次真实登录已验收。

[PreviewRuntime](../macos/Sources/ToolboxPreviewSupport/PreviewRuntime.swift) 使用内存设备/偏好、记录动作和 ManualScheduler，传入的 shell 文本仅作数据解析。PreviewHost 的依赖闭包不含 ToolboxMacAdapters、ToolboxProcessExecution 或生产宿主，包内没有 adb/JAR/APK；[Preview 窗口](../macos/Sources/ToolboxPreviewHost/App.swift) 显式 `.restorationBehavior(.disabled)`，防止默认窗口恢复写入用户偏好。

选择 `ToolboxPreviews` scheme，使用 [PreviewGallery](../macos/Sources/ToolboxPreviewSupport/PreviewGallery.swift)。依赖图、源码效果、二进制符号和资源检查由 [validate_preview_boundary.py](../macos/scripts/validate_preview_boundary.py) 执行；实际窗口交互还需独立观察子进程/socket、退出重开及偏好前后差异，静态通过不能替代运行时证据。当前每次任务的实测范围见 ROADMAP 链接的验收报告。

## 构建、验证与回滚

[运行资源锁](../macos/Config/RuntimeAssets.lock.json) 固定 adb/JAR/APK/NOTICE。首次用 [runtime_assets.py](../macos/scripts/runtime_assets.py) 显式 prepare，构建只消费已校验资源，不在编译阶段下载。使用新输出目录进行 App Debug/Release、Preview Debug、Swift/Python、架构和产物验证；真实 Preview 只运行隔离宿主，不运行候选生产 App。

[默认 CI](../.github/workflows/macos.yml) 在带 `toolbox-macos27` 标签的 macOS 27 ARM64 runner 上完成上述编译与自动检查；外部 fork PR 不在该自托管 runner 自动执行。默认 push/PR/标签/手动运行不生成 DMG/ZIP、不安装、不使用 Developer ID。只有手动显式 `package=true` 且 build 成功，独立 job 才生成 development DMG/ZIP；现行 workflow 不执行公证或创建 Release。没有在线 runner 时排队，不代表代码已通过。

回滚保留父基线/不可变提交和 R0–R6c 标签，在独立目录验证前版与逆补丁，不重写 master、不 reset 当前工作树、不覆盖现用 App。源码回滚不自动恢复 TCC、SM 登录项、偏好、adb RSA 信任或设备设置；敏感备份和大日志留受控本地。

## 遗留保留与历史文档

S1-09 删除项为 **0**。本次没有以文档整理为由删除兼容入口或历史脚本；以下引用说明保留原因，并不声称完成全库死代码证明。

| 保留项 | 当前引用 / 用途证据 |
| --- | --- |
| `adb.ip` 及旧 IP 包装入口 | [音量回调](../macos/Sources/ToolboxApplication/AppCoordinator+Volume.swift) 尚保留旧 ip 比较，完整入口审查留 S2-05；[预设所有权](../macos/Sources/ToolboxApplication/AppCoordinator+Presets.swift) 已改用确认后的兼容键；[TCPCompatibilityTests](../macos/Tests/MimonitorToolboxTests/TCPCompatibilityTests.swift) 覆盖旧入口与固定命令轨迹 |
| `LegacyLoginItemFiles` | [LiveLoginItems](../macos/Sources/ToolboxMacAdapters/Autostart.swift) 构造并使用它；[LoginItemTests](../macos/Tests/MimonitorToolboxTests/LoginItemTests.swift) 覆盖归属、备份和迁移，是现行旧配置兼容路径 |
| HUD 的 ObservableObject | [HUDWindow](../macos/Sources/ToolboxMacAdapters/HUDWindow.swift) 的视图观察并持有 HUDModel，仍有真实使用者，不属于已移除的全局 AppState |
| 显式打包/安装与历史签名脚本 | workflow 的手动 package job 调用 [make_dmg.sh](../macos/make_dmg.sh)；[签名规则测试](../macos/scripts/tests/test_release_pipeline.py) 仍覆盖 distribution 门禁；[reinstall.sh](../macos/reinstall.sh) 保留显式安装入口，现行默认 CI 不调用它 |
| R0–R6c 文档与检查点 | 保留当时的设计、测试、限制和回滚证据；旧正式发布凭据要求不作为现行 development 验收门槛 |

历史记录：[R0–R2b](../macos/REFACTORING.md)、[R3](../macos/R3-ARCHITECTURE.md)、[R4](../macos/R4-CONCURRENCY.md)、[R5](../macos/R5-SYSTEM-SERVICES.md)、[R6](../macos/R6-RELEASE.md)、[R6c](../macos/R6-CLOSEOUT.md)。这些文档只补历史入口说明，原正文与当时未验收项保留。使用/开发说明见 [根 README](../README.md)、[macOS README](../macos/README.md)，视觉规范见 [DESIGN](../DESIGN.md)。
