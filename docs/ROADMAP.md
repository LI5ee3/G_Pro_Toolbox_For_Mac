# G Pro ToolBox 最终开发路线图

> 唯一项目进度基准。创建于 2026-10-22（UTC+8），同日按用户要求修订自动模式、分层验收和 CI 前置门禁。
> 当前结论：按用户授权依次执行 S1-06、S1-07、S1-09；固定父版 257 Swift/24 Python、独立回滚构建通过，正在复现和修复 S1-06。G1 NOT_PASSED，阶段二至四锁定。
> 后续每次工作先读取本文件，完成一个明确子任务后更新任务状态、证据、风险和下一步；其他文档只承载设计或历史证据，不另设竞争性进度表。

## 1. 范围、基线与执行边界

### 1.1 最终范围

完成 Apple Silicon 原生架构必要整理 → USB/TCP 统一 ADB → Pro B SwiftUI 最终优化 → 真机验收、可重复本地交付和功能冻结。

- 仅 Apple Silicon、macOS 27+；不增加 Windows、Intel Mac 或低版本 macOS 兼容。
- 沿用 Pro B「屏幕即遥控器」：保留设备实体、遥控底座、现有品牌和全部现有控制入口。
- 使用 SwiftUI、AppKit、Observation、CoreAudio、ServiceManagement 等 Apple SDK；复用已验证模块、执行器、设备命令、预设引擎和存储规则。
- 不需要 Developer ID、公证、App Store 或公开二进制发布。它们不再是本轮完成门槛，也不应继续作为“待凭据阻塞”。
- oil UI Pro 已由用户确认安装在开发该项目的 Mac 上，阶段三在该 Mac 使用；本轮无需安装、调用或猜测替代工具。实施时先查阅该安装的实际说明和版本。
- 不新增设备协议、不重写 adb USB/RSA 协议，不因“原生”要求删除在显示器 Android 上运行的 JAR/APK。
- Auto 自动连接模式是本轮必需交付功能：USB 有线 ADB 优先；有线失效自动回退同一物理设备的无线 TCP ADB；有线重新检测且探活稳定后自动切回 USB。手动 USB/TCP 仍保留，旧用户配置默认不强制改为 Auto；“用户可选择 Auto”不等于该功能可延期或省略。

### 1.2 锁定的远端基线

| 项目 | 审计结果 |
| --- | --- |
| 仓库 | LI5ee3/G_Pro_Toolbox_For_Mac，默认分支 master |
| 初版审计的源码 master | [52d90d6ad7a5d39939edd60a5d874311b337ae1d][E01] |
| R6c 回滚标签 | refactor/20261022/R6c → fc231b607aaa03c82e94cb1292b513a44c62c019 |
| 两者关系 | 逐路径/blob 比较：master 相比 R6c 仅 README.md、macos/README.md 不同；没有新增、删除或变化的业务源码。master 包含 USB 硬件纠正说明 |
| 历史回滚 | 远端实际存在 R0、R1、R2a/b、R3、R4、R5、R6、R6c 及细分 refactor 标签；保留，不移动旧标签 |
| 工具链记录 | R6c 记载 Mac mini M4、macOS 27.0.1、Xcode 27.1；新执行时在开发 Mac 重新记录实际版本 |
| 本次修订起点 | d91755f6b0de87a821233324d0fc8c4b3506c06b（初版路线图提交）；源码审计基线仍为上列 52d90d6 |
| 当前执行范围 | S1-06 → S1-07 → S1-09；起点 5eec375737050eb6e668227116533de985909740。逐项复现/最小修复/文档整理、验证与提交推送；不安装/打包/操作真机，不开始阶段二 |

下次实施前复核 master HEAD；若变化，先记录新 SHA 与差异并重新确认受影响任务，不能把移动分支当作固定测试基线。R6c 是历史检查点，不等于本轮已经完成。

### 1.3 执行规则

1. 四阶段严格串行：每阶段先审查，明确计划，再逐个实施；每个子任务只有一个可验证目标。
2. 稳定机制默认保留。任何替换必须写明原问题、收益、最小差异和测试证据；不为了文件大小、命名或语言模式统一重写。
3. 每阶段结束必须报告变更清单、测试证据、遗留风险和验收结论。用户确认该阶段通过后才解锁下一阶段。
4. 初版路线图审计仅做远端读取和文档上传。2026-10-22 用户已分别授权 S1-08、S1-02、A17（S1-10）及各自验证/报告/提交推送；随后单独授权 S1-03 审查与设计、更新报告及提交推送。S1-03 不改业务源码、不开始 S1-04。随后用户单独授权 S1-04 最小 TCP 会话迁移、验证/报告/提交推送；不开放 USB 发现，不开始 S1-05。随后用户单独授权按 ROADMAP/ADB-CONTRACTS 执行 S1-05、验证/报告/提交推送；本次仅该项，不开始 S1-06。随后用户授权按顺序执行 S1-06、S1-07、S1-09，更新报告并提交推送；本次三个子任务逐项实施，不延伸至阶段二。各次授权均不延伸至范围外子任务、安装/打包或真机操作。
5. 后续构建使用独立新输出目录。不得默认生成 DMG/ZIP、运行 reinstall.sh、覆盖现用 App、重绑权限、清理偏好或重置 adb 密钥。S1-08 必须先于首次业务源码修改及其推送完成：默认 CI 仅编译、测试和架构/Preview 边界检查；打包只能由显式请求触发，不能由默认 push、PR 或默认值的手动运行连带触发。
6. 高风险真机写入须事前获得用户对具体操作、目标、原值及恢复方案的明确批准；测试清单中的勾选框不构成操作授权。
7. 普通读连接也可能触发现有自动任务、记忆恢复和 ensureJars 写入。真机只读检查须先识别这些副作用，使用独立只读探针；不能仅因方法名是 connect 就称为“只读”。
8. 初版文档及 S1-08 受控提交使用 [skip ci]，避免旧默认打包路径；S1-08 推送后显式运行未选择打包的默认验证。[GitHub 跳过工作流说明][X05]。后续业务源码提交不得以此免除默认 CI。

## 2. 证据等级与现状审计

### 2.1 初版审计查阅覆盖和验证限制

已通过 GitHub 远端 API 固定到上述 SHA，读取完整非截断目录树、全部 85 个生产/Preview Swift 文件、Package.swift、34 个 Swift 测试目录文件（含辅助文件）、Xcode 配置、权限配置、构建/验证/安装脚本、脚本测试、workflow 和现有架构/收尾文档。没有仓库 AGENTS.md 文件；遵守本次会话提供的 AGENTS.md 原则。

另查阅两份 Java helper 源码及运行时/Guardian 来源说明。未下载或解码 adb/JAR/APK 二进制，资源完整性结论仅限锁定配置与历史记录，新的产物摘要仍需构建时验证。

本轮进行了目录/blob 比对、模块/import 和关键调用路径静态检查、测试定义计数及文档交叉核对。**不等于在 macOS 编译、执行测试、测量 UI 或重做硬件验收。**

| 等级 | 含义 | 本轮使用方式 |
| --- | --- | --- |
| S：源码事实 | 固定 SHA 中直接可见的实现/配置 | 可确认架构、硬编码、调用路径、已有测试断言 |
| H：历史报告 | 仓库文档记录曾经完成 | 引用 R6c 等原记录，不能改称本轮重新通过；部分日志/备份位于旧 Mac 工作区，未独立读取 |
| U：用户提供 | 用户确认的信息 | oil UI Pro 在开发 Mac；不推断它的接口或版本 |
| P：待验证 | 静态风险、未来目标或缺少本轮运行证据 | 需 Mac 上复现、测试或真机签字；不得标 PASS |

源码共有 233 个 Swift test 方法、24 个 Python test 方法，和 R6c 报告计数一致；计数不是执行结果。当前 master 对应 [Actions 运行][E16]在审计时为 queued、conclusion 为空，不能借用旧提交的成功 CI 证明当前提交通过，也不能据此断言 runner 当前一定未配置。

### 2.2 全模块现状与处置

Package.swift 定义 10 个源码 target、2 个测试 target，未声明外部 Swift Package 依赖。[清单][E02]

| 模块 / Swift 文件数 | 当前责任与边界 | 最终处置 |
| --- | --- | --- |
| ToolboxDomain / 15 | Foundation 值类型、固件映射、范围、连接/刷新代次、系统状态；Swift 6 | 保留；增加传输/目标/身份值契约及明确状态 |
| MimonitorPresetCore / 6 | PresetEngine、Codable 配置、日程、应用报告、PresetWorker 所有权；Swift 6 | 保留状态机与 picture_presets_v1；仅接入可靠设备身份 |
| ToolboxConcurrency / 3 | CommandRequest/Result、父子取消、FIFO 异步桥、OwnedWorkSet、生命周期代次；Swift 6 | 保留，不另造第二套任务系统 |
| ToolboxProcessExecution / 1 | 独立进程组、双管道有界排空、期限、TERM/KILL、回收；Swift 6 | 复用；设备发现也必须有界、可取消 |
| ToolboxApplication / 28 | AppCoordinator 与动作扩展、9 个 MainActor Observation 状态模型、注入端口、ADB 门面、系统工作流 | 保留；去除传输与设备身份中的 IP 假设；AppKit/快捷键边界按收益局部整理 |
| ToolboxMacAdapters / 11 | Live 组合根、AdbPresetDevice、网络扫描、CoreAudio、SM 登录项、权限、HUD/OSD、日志 | 保留平台适配；USB 使用现有内嵌 adb，避免引入直接 USB 栈 |
| MimonitorToolbox / 17 | 10 个页面、菜单栏、主题/共享控件、会话与窗口包装 | 保留 Pro B 与动作入口；统一反馈并集成传输选择 |
| ToolboxApp / 1 | 生产组合、窗口/Dock/菜单栏、启动/退出与日志排空 | 保留；USB 生命周期归应用，不能绑在页面出现/消失 |
| ToolboxPreviewSupport / 2 | 内存设备、录制系统动作、虚拟调度、场景画廊 | 扩展 USB/TCP 状态模拟；继续无生产副作用 |
| ToolboxPreviewHost / 1 | 独立安全预览宿主与 Bundle ID | 保留独立 target/scheme、资源与二进制边界 |

当前层次（省略部分 Domain/Core 直接依赖，以 Package.swift 为准）：

~~~mermaid
flowchart TD
    App[ToolboxApp] --> UI[MimonitorToolbox / ToolboxUI]
    App --> Mac[ToolboxMacAdapters]
    Mac --> Application[ToolboxApplication]
    Mac --> Process[ToolboxProcessExecution]
    Process --> Concurrency[ToolboxConcurrency]
    UI --> Application
    Application --> Concurrency
    Application --> Core[MimonitorPresetCore]
    Application --> Domain[ToolboxDomain]
    Core --> Domain
    PreviewHost[ToolboxPreviewHost] --> Preview[ToolboxPreviewSupport]
    Preview --> UI
    Preview --> Application
~~~

**已存在且优先保留的有效设计：**

- 状态：9 个 MainActor + Observation 模型，UI 按属性读取；任务/计时器/引擎不进可观察状态，不恢复全局 AppState/objectWillChange。
- 设备：提交时捕获 AdbSession、子取消令牌和生命周期代次；递归事务锁保证整批 JNI/预设不交错，锁与 TaskLocal 不跨 await。新传输必须延续这些约束。
- 进程：POSIX 执行隔离、每路 16 MiB 上限、取消/超时/截断不冒充成功；不把阻塞 Process 等待放进 MainActor 或 Swift 协作执行器。
- 预设：先保存原始基线，部分失败 applicationIncomplete 保持，禁止混合参数自动保存；自动任务按身份回到原显示器，不因重连越过保护。
- 平台：SMAppService 系统读回、严格旧登录项归属检查、辅助功能撤权放行按键、默认音频输出缓存、异步日志排空和 OSD 故障 HUD 回退。
- Preview：独立 bundle/scheme、内存偏好和设备、虚拟时间；不依赖 MacAdapters/ProcessExecution，不含 adb/JAR/APK，生产组合根拒绝 Preview。
- 构建：arm64、minOS 27.0、锁定资源摘要、显式 prepare、构建不下载、输出拒绝覆盖、App 与打包分离。[E03][E07][E10][E11][E14]

不是所有模块都已 Swift 6：Domain、PresetCore、Concurrency、ProcessExecution 为 v6；Application、MacAdapters、UI、Preview 和宿主保留 Swift 5 过渡模式。全库翻转语言开关不是最终完成的必要条件；只有实际跨线程安全问题必须收敛并测试，剩余边界明确记录。

### 2.3 USB 硬件与应用能力必须分开

[根 README][E00] 和 [Mac README][E17] 记载 2026-10-22 的 32U 真机结果：

- Mac 扩展坞 USB-A → A↔C 数据线 → 显示器 Type-C；内嵌 adb 在 server 5038 上列出 USB serial 76226171600005770，状态 device，并完成指定 serial 的 shell 回读。
- USB 配置状态和内部 Hub 拓扑已被原记录核实；之前“Type-C 无法有线 ADB”的结论已纠正。
- 这是 H 级硬件/adb 传输证据。本轮未复测，不据此保证其他线材、接口、型号或固件。
- 当前应用仍只有网络 IP 输入、网络扫描/诊断；AdbSession.serial 仍拼接 targetIP:5555，USB 产品功能尚未实现。串口、示例 IP、usb 总线地址不可硬编码为默认用户设备。

USB 数据线/ADB 连接不等于视频输入状态；信号源、默认音频输出和控制通道分别显示，保持已有媒体键输出门控。

### 2.4 风险与技术债登记

优先级：B = 当前目标的阶段阻断项；R = 需复现并按影响判定的可靠性风险；N = 可记录的非阻断维护项。原有源码位置固定到基线；S1-02 对 A01–A16 逐项复核并登记 A17，固定当前源码链接与覆盖缺口见 [S1-02 证据报告](acceptance/S1-02.md)。源码事实、Mock、实际 Preview 运行和历史/真机证据分列，不冒称真机复现。

| ID / 级别 | 直接证据与影响 | 计划 |
| --- | --- | --- |
| A01 / B | AdbSession.targetIP / serial、AdbClient.activeIP/connect/disconnect 固定 TCP 5555；不能直接塞 USB serial。[E04][E05] | S1-04 已以 AdbEndpoint 替换 TCP 会话存储，默认 argv/取消兼容本机验证通过（见 8.7）；S2-02 USB 端点/发现未实施，风险未整体关闭 |
| A02 / B | AdbPresetDevice 用 identity:5555，协调器以 adb.ip 判断基线、自动任务和活动预设；传输地址与物理设备身份混用。[E06][E08] | S1-04 已分离预设 endpoint 与 legacy identity 参数，固定目标本机验证通过；旧 IP 所有权规则保持，S2-04 物理身份/别名迁移待实现，风险未整体关闭 |
| A03 / B | ensureConnected/restartServer 恢复可 kill-server；共享 5038 同时承载 USB/TCP，网络故障可能打断 USB。unauthorized 退出 wait 后仍可能进入后续恢复路径。[E05] | S1-05 已移除应用显式 kill/start 恢复循环，统一 unauthorized/取消/25 秒冷却；配置端口不视为独占凭证。官方 adb 启动/版本协调仍可能有 server 副作用，多客户端、USB/TCP 与真机恢复留 S2-02/06，风险未整体关闭（见 8.8） |
| A04 / R | isServerAlive 调用 adb version；该命令只能证明客户端可运行，不能可靠证明 server 响应。[E05][X02] | CLOSED_S1-05：锁定客户端+本地假 server 实测 host-features；成功/拒绝/截断响应与客户端 version 对照，13 新增及原回归/默认 CI 通过；主动查询限制见 8.8 |
| A05 / B | ConnectionStatus 仅四态，连接与扫描列表以 IP/String 表达；缺少 USB 枚举、授权、设备离线/歧义等结构化状态。[E09] | S1-03 已定义连接/发现/身份分开的状态契约；S1-04 仅 TCP 会话替换，状态扩展留 S2-01/03，风险未关闭 |
| A06 / R | local_dimming_memory 解码为任意 Int 字典，状态展示与记忆应用均直接作四元素下标；live start 在连接前也调用展示，负数或 ≥4 可越界。S1-02 已确认源码，未做崩溃复现。[E18] | S1-06 用内存偏好复现后最小校验，保留原字节、不静默写回 |
| A07 / R | applyGameJniMode 将缺失/无效 JNI 值与预期枚举比较后写成 0；读取失败可能被显示为确定“关闭”。[E19] | S1-07 假失败回归；区分未知和关闭，不改有效值映射 |
| A08 / R | 部分 legacy shell 返回 String 且不以 exitCode 判成功；部分普通设置先乐观更新。checkedShell/预设已有更严格路径。[E05][E06] | S1-02 已列 50 shell/5 checkedShell 直接调用及包装/上层语义；本次没有新增具体误报复现，不创建修复任务。后续如确认需单独登记，不整库改协议 |
| A09 / B | 唤醒/轮询从 saved_ip 恢复；Live 只订阅 didWake/screensDidWake，USB 插拔/睡眠中任务语义未定义。[E07][E12] | S2-06；取消旧会话、防旧读数、重枚举并回读，避免重放非幂等写 |
| A10 / B | Preview 当前六种场景，无 USB/双连接/授权等待；布局测试主要断言 fittingSize > 0，不能证明无裁切、键盘可用或深色对比度。[E13] | S2-03/08、S3-07/08 补场景与视觉/交互证据 |
| A11 / B | DESIGN.md 仍写“不新增 USB”、蓝牙操作、macOS 26 回退；当前代码已 ADB-only/macOS 27。README 与旧 R6 发布门槛也需按最终范围统一。[E15] | 本文件范围优先；S1-09 与 S3-01、S4-05 更新现行说明，保留历史事实 |
| A12 / B → CLOSED_S1-08 | 基线 master push 默认 make_dmg，含 distribution/notary/release job；reinstall.sh 有安装副作用。[E14] | S1-08 已隔离默认路径并在 GitHub 实跑确认 build 成功、package 跳过、零包产物；独立前置提交 9994f05。安装脚本不在任何现行 CI 路径，未运行；见第 8.3 节 |
| A13 / N | NativeOSD 仍使用私有 XPC 兼容路径；已有过期保护、冷却和 HUD 回退。[E10] | 保留已验证行为，不再扩大私有 API；验收 HUD 必须可用，私有 OSD 限制单独登记 |
| A14 / N | Application 仍依赖 AppKit、保留状态转发属性、部分大动作文件；这不自动证明架构失效 | 仅删除可证明无引用的代码；不因“纯化”拆空模块/重建协调器 |
| A15 / N | Guardian 源码路径不可复现，整体/图标许可未确认；资源摘要与 NOTICE 已锁定。[E11] | 保留来源和致谢；本轮私人本地交付不以公开再分发审批为阻断，若以后公开发布需另行处理 |
| A16 / R | 设备侧 helper 使用固定 batch/ramp 结果文件；应用内锁不覆盖另一个 Toolbox/Terminal 进程。Guardian 在配置异常时可能重启 adbd，影响两种传输 | S2-05/06 复核共享设备端资源与 Guardian 恢复影响；真机测试隔离其他写入者，不声称应用事务锁是全设备锁 |
| A17 / R → CLOSED_S1-10 | S1-02 发现 SwiftUI Window 默认恢复保存 NSWindow Frame preview；历史失败保留。S1-10 仅给 Preview 场景加 restorationBehavior(.disabled)，本机实际窗口变更/交互/退出/重启与空域运行验证均不再改变偏好 | 修复提交 4cef289；871 次监测无偏好变化，原 plist 字节/mtime 不变，新域无文件；默认 push CI 39777222854 success。旧键保留，未放宽零写入要求，见第 8.5 节；G1 仍待其余任务 |

### 2.5 历史已验证与本轮仍缺证据

| 范围 | 历史记录 H | 本轮 / 最终状态 |
| --- | --- | --- |
| 自动测试 | R6c：233 Swift、24 脚本测试通过 | S1-02 固定基线测试证据见第 8.4 节；S1-10 本机及实际修复提交的默认 push CI 重跑 233 Swift/24 Python 全通过，原用例不变，见第 8.5 节 |
| 原生构建/资源 | R6c：App Debug/Release、Preview Debug、arm64/minOS、ad-hoc、资源一致性；DMG/ZIP 回读 | S1-02 记录的 A17 FAIL 保留为历史；S1-10 一行修复后运行偏好/构建/资源/签名/四层边界通过，未打包或启动新生产 App，完整证据见第 8.5 节 |
| 媒体键/音量 | R6c：音量加/减/静音 USB 独立回读、默认 Mi Monitor 输出 | 不等于应用已有 USB 选择；新 USB/TCP 都要回归 |
| 窗口/退出/日志 | R6c：关窗驻留、重开同 PID、日志导出和退出落盘 | 新版须复验生命周期不泄漏 |
| 真实睡眠/登录/重启 | R6c 明确本轮未做；更早文档有网络唤醒经验 | 最终仍为 PENDING，不能按自动恢复模拟测试豁免 |
| 输出切换/OSD 故障 | 注入测试；真实异常未主动制造 | 普通真实输出门控需补测；危险/不可控系统故障用注入证据并说明限制 |
| 性能 | R6c 两段约 20 秒 Instruments，未记录 >250ms 卡顿；非延迟上界/提速结论 | 新版同条件观察，不编造相对性能数字 |

## 3. 最终 ADB 设计约束（计划，尚未实现）

S1-03 的固定源码审查、决策、状态转换、旧配置兼容/回滚及后续断言详见 [统一 ADB 契约设计](ADB-CONTRACTS.md)。本文继续是唯一进度基准；设计完成不表示 USB/Auto 或身份迁移已经实现。

### 3.1 最小演进方向

在原 Domain / Application / MacAdapters 内增量实现；暂不新增独立仓库、直接 libusb/IOKit 驱动、网络服务或新后台 helper。

概念契约如下，名称是设计建议，实施前对照实际现有 API 确认，不把它们当作已存在接口：

| 概念 | 必须承载的内容 |
| --- | --- |
| 连接偏好 | 手动 USB / 手动 TCP / 必需的 Auto；先完成手动模式子门禁 M2，再交付 Auto 的 USB 优先、失效回退无线、稳定恢复后自动回切 USB |
| ADB 端点 | USB serial，或 TCP host + port（旧配置默认 5555）；非空、类型化，不自动为 USB 追加端口 |
| 设备身份 | 独立于端点的稳定身份与可信来源；USB/TCP 关联的证据、旧 IP 别名、未知/冲突状态 |
| 会话 | 现有 clientID、不可变端点、身份快照、代次与父子取消；transport ID 若使用只能是本次枚举的临时定位 |
| 枚举结果 | serial、传输类别、adb 状态、可用的 model/product/device/transport 信息；原始值保留用于诊断，不能按显示名猜唯一设备 |
| 连接状态 | 未选择/发现中/连接中/待授权/已就绪/离线/恢复中/错误；只读探测成功后才 ready |
| 恢复策略 | 传输局部恢复优先、server 级恢复有边界；用户手动断开抑制恢复，stop 取消所有监听和工作 |

USB 发现/认证首先复用锁定的官方 adb：有界 devices -l 枚举、明确 serial 的 get-state/只读 shell。RSA 授权由 adb/adbd 和显示器端用户确认完成；应用显示待授权与重试，不代替用户同意、不删密钥。[Android 官方文档][X01]

USB 连接不执行 adb connect；逻辑断开清除应用会话并暂停自动接入，不伪造拔线或对 USB 调用 TCP disconnect。TCP 继续明确 connect/disconnect host:port。设备命令全部明确 -s SERIAL，歧义场景不得退到默认 adb、全局 ANDROID_SERIAL、裸 -d/-e 或“列表第一台”。[ADB 命令说明][X02]

### 3.2 身份、配置与双连接

- 保留 saved_ip、现有快捷键/记忆键、picture_presets_v1 的读兼容；旧用户默认沿用 TCP，不在升级时自动切换 USB/Auto。
- USB serial 与 TCP 的设备属性读回只有经过唯一性与同机验证才关联。优先验证 ro.serialno 等实际可读属性；若缺失、重复或不可信，保持两个候选并要求明确选择/绑定，不能按相同 MiTV 型号合并。
- 旧 IP 基线/任务的迁移必须备份、可逆且幂等；未证明同机时保留旧身份，禁止自动向新 serial 还原基线。不要强制重写全部预设 JSON。
- 同一显示器 USB+TCP 双在线时只允许一个活动命令会话；预设事务不跨端点拼接，不让两个队列对同机同时写。
- 多台 USB、同型设备、USB/TCP 关联冲突均显示候选并禁止自动猜测。身份冲突属于写操作阻断，不属于可忽略提示。
- transport ID、usb: 总线位置不能作为永久身份；热插拔/server 重启后重新枚举，不能复用旧编号。

### 3.3 取消、断线与自动策略

- 切目标、同目标重连、断开、stop、睡眠边界都使旧工作失效；旧结果不能刷新新 UI、清除新 busy 或污染 Binder/音量/画面缓存。
- 保留 FIFO/事务锁与 operation ID；USB 发现的列表快照不能抢占活动预设事务。先选有界轮询；若使用长连接跟踪，必须单独定义取消、重连和输出上限，不能无期限占据现有命令执行器。
- unauthorized 等待用户授权，不反复 kill-server；手动 USB 模式拔线后保持该模式的离线/恢复状态，Auto 则按同机绑定自动回退无线 TCP，不能盲扫并连接未知设备；TCP 故障不重启健康 USB 会话。server 级故障恢复须重新验证所有受影响会话。
- Auto 是阶段二及最终结项的必需功能，先通过手动模式子门禁 M2，再实施并验收，不得以“可选择模式”为由列为非阻断待办。M2 的核心连接/控制/恢复须真机通过，例外场景按第 6.0 节严格 Mock 验收。
- Auto 启用后优先已确认同机且 ready 的 USB；有线失效时自动回退该物理设备已验证的无线 TCP 端点；有线重新检测到后，须重新枚举、匹配身份并通过稳定探活，再在安全边界自动切回 USB。TCP 不可用或身份无法确认时保持明确的离线/待确认状态，不切到其他设备。旧用户默认保持原 TCP 偏好，不在升级时擅自启用 Auto。
- 切换须串行化并设代次：停止旧会话接收新工作，使未派发旧任务失效，取消/结束在途工作并完成账务，建立新会话后先回读再接受新动作；任一时刻只允许一个活动写通道。
- 正在执行的写入/预设不能跨传输自动重放；先标记中断/不完整、回读，再决定是否重试。静音 toggle、信号源切换、APK 安装等尤其不能盲重试；超时但可能已经在设备生效的命令不能因换线再发一次。不要宣称远端命令可撤回或具备无法证明的 exactly-once 保证；验收必须核对命令轨迹和设备回读，证明没有由切换引入的重复派发。
- USB 重插、网络恢复、设备/屏幕唤醒必须合并和限流；采用持续探活稳定窗口、失败阈值、切换冷却与退避，避免频繁 USB↔TCP 抖动。具体参数在 S2-08 审查中定义，通过虚拟时钟/故障序列测试和真机往返切换测量后记录；不能无限等待稳定而永不回切，也不能一枚举到 USB 就抢占在途事务。
- 不自动执行 adb usb/tcpip、USB 路由寄存器、重启显示器或恢复出厂，不用改设备模式“修复”连通性。

## 4. 四阶段任务与验收门禁

任务状态：DONE_REMOTE = 初版远端审计已完成；READY = 计划就绪；TODO = 待实施；LOCKED = 前置阶段/任务未验收；PASS = 适用证据门槛满足且阶段已确认；FAIL/BLOCKED = 必须保留原因与下一步。逐用例分开记录 HW_PASS、MOCK_PASS、HW_NOT_TESTED、NOT_RUN：Mock 通过不能写成真机通过。第 6.0 节允许的例外在严格 Mock 通过、未实测限制完整登记并由用户随阶段报告接受后，可满足该例外的验收要求；核心真机项目不能用 Mock 替代。

每个任务均遵循“复核当前源码 → 写本任务最小变更计划/风险 → 实施 → 验证 → 记录”。不并行实施多个任务；发现新问题先登记，不能顺手扩大范围。

### 阶段一：架构整理

入口：本路线图发布；先只读复核 HEAD、工作树、现用应用保护边界和现有 workflow，再执行 CI 前置任务 S1-08。
目的：使现有 TCP 架构能安全承接 USB，补齐可证明的可靠性问题，不重做 R0–R6c。

| ID | 单一子任务 / 交付 | 验证标准 | 初始状态 |
| --- | --- | --- | --- |
| S1-01 | 远端现状审计、范围与证据登记 | SHA、R6c blob 比对、全模块与现有门禁映射可追溯 | DONE_REMOTE |
| S1-08 | 首次业务源码修改/推送前，先独立完成 CI 与打包解耦 | 默认 push/PR/未选择打包的手动运行仅编译、测试和架构/Preview 检查；不生成 DMG/ZIP、不安装、不用 Developer ID；打包仅显式触发，留下独立 CI 提交及验证证据 | DONE（9994f05；见 8.3） |
| S1-02 | S1-08 完成后，在开发 Mac 建立业务源码未改动的基线，并逐个复核风险 | 记录 CI 前置提交和未改动业务源码 SHA；233/24 实际日志、三种构建/边界及现用 App/配置保护；失败先诊断 | DONE_WITH_FINDINGS（当时 A17 FAIL；后由 S1-10 修复；见 8.4/8.5） |
| S1-10 | 独立处理 A17：关闭安全 Preview 宿主窗口偏好持久化 | 审查 Window 恢复/保存；最小 Preview-only 修复；实际移动/缩放、交互、关闭/退出及重启后偏好域/磁盘不变，保留旧值；全量自动回归通过 | DONE（4cef289；见 8.5） |
| S1-03 | 输出统一端点/身份/状态与旧配置兼容设计 | 覆盖 USB/TCP、歧义、身份未知、旧 IP、会话失效；记录决策和不改的协议 | DONE（bf18c78；设计交付，未实施新契约；见 8.6） |
| S1-04 | 最小替换 IP-only 会话契约，先迁移 TCP 路径 | TCP argv/命令顺序与旧行为一致；空端点、同址重连、A→B、预设固定目标测试通过；尚不开放 USB 发现 | DONE（60f476c；见 8.7） |
| S1-05 | 收敛 server 健康检测与恢复决策边界 | 客户端存在/server 不在、unauthorized、冷却、取消的注入测试；不改变有效设备协议 | DONE（8b09ce3；见 8.8） |
| S1-06 | 复现并修复非法控光记忆范围风险 | -1、4、极端 Int、错误 JSON 不崩溃且不向设备下发；有效 0…3 行为保持 | LOCAL_PASS（8 项新增；见 8.9，最终 CI 待完成） |
| S1-07 | 复现并修复 JNI 缺失被当作关闭 | failed/空/无效值呈未知；合法 320Hz/FreeSync 枚举和映射保持 | TODO |
| S1-09 | 更新现行架构说明和必要遗留清理记录 | 依赖/所有权/Swift 模式/目标设计与源码一致；每个删除项有无引用证据；更新本表 | TODO |

任务 ID 保持不变，新增 A17 独立任务 S1-10，按用户要求插入 S1-03 之前。顺序为 S1-01 → S1-08 → S1-02 → S1-10 → S1-03 → S1-04 → S1-05 → S1-06 → S1-07 → S1-09。S1-08 是 CI 专项的首次实施/推送，不能夹带业务源码；其受控提交使用 [skip ci] 避免现有自动打包路径，并在远端确认新默认验证路径后才解除业务源码修改及推送禁令。[X05] 不能用今后每次源码推送都 skip CI 代替这一门禁。

A08 若测试确认有误报，另建单一 S1 任务后再修；不能把它混进会话改造。无需删除全部历史发布脚本；应隔离默认路径并消除现行文档的错误阻断条件。

**G1 通过条件：**

- [x] S1-08 已作为独立前置提交完成并验证，早于首次业务源码修改及其推送；默认 CI 仅编译、测试、架构/Preview 检查，DMG/ZIP 仅显式触发且不安装应用。证据见第 8.3 节。
- [ ] S1 全部必需任务完成；已有 233 Swift/24 脚本断言保留，必要新增用例通过；删除/调整测试必须说明理由，不能降低门槛。
- [ ] App Debug/Release、Preview Debug 在 arm64/macOS 27+ 成功；模块无环、9 模型所有权、Preview 静态/二进制/资源边界通过。
- [ ] TCP 固定目标、取消/超时、FIFO、预设身份与存储兼容没有回归；没有无收益重写或全库 Swift 模式强切。
- [ ] 架构文档、最小调整理由、差异清单、风险及回滚点齐全；未替换现用 App。
- [ ] 最终候选 Preview 实际运行边界满足第 5 节；S1-10 已修复 A17 并实际验证，不等于后续源码的最终复验已完成，不用静态 PASS 替代运行证据。
- [ ] 阶段报告提交并获得用户确认。当前 G1 = **NOT_PASSED**；不能进入 USB 实施。

### 阶段二：USB ADB

入口：G1 PASS。先核对锁定 adb 的实际 help/枚举输出及显示器固件；不重新研究或改写已经验证的 Android 命令。

| ID | 单一子任务 / 交付 | 验证标准 | 初始状态 |
| --- | --- | --- | --- |
| S2-01 | 有界设备枚举与解析 | 0/1/多台、USB+TCP、unauthorized/offline、附加字段、损坏/截断/超时、取消的 fixture 全覆盖 | LOCKED |
| S2-02 | USB 会话选择、授权等待、只读探活、逻辑断开 | USB 不执行 TCP connect/disconnect；待授权不 ready、不重启健康 server；断开后不自动抢回 | LOCKED |
| S2-03 | 最小手动 USB/TCP 选择 UI 与模拟场景 | 模式/端点/实际状态明确，拒绝无目标写入；完整视觉统一留到阶段三 | LOCKED |
| S2-04 | 同机身份绑定与旧 IP 兼容实现 | 同机跨传输保留基线/任务；异机/冲突拒绝恢复；旧 JSON 读入、迁移失败、回滚、二次迁移测试 | LOCKED |
| S2-05 | 所有控制入口接入统一会话 | 音量、画面、游戏、信号源、灯光、遥控、预设、自动任务、菜单栏/快捷键、工具/Terminal 的 USB/TCP argv 契约测试；不复制业务实现 | LOCKED |
| S2-06 | 插拔、网络断线与睡眠任务生命周期 | 旧任务取消/晚到结果丢弃、stop/start、重枚举、局部恢复、忙状态释放和不重放写入的故障注入 | LOCKED |
| S2-07 | 手动模式分层验收子门禁 M2 | USB/TCP 核心连接、控制、同机双在线、手动切换及拔插/恢复必须真机通过；首次授权/第二台设备等例外按第 6.0 节严格 Mock 并记录未实测限制；具体写入按批准执行和恢复 | LOCKED |
| S2-08 | M2 通过后设计并实现必需的 Auto | USB 优先 → 有线失效自动回退同机无线 TCP → 有线稳定恢复后自动回切 USB；单会话、安全切换、不重复派发、稳定窗口/冷却/退避、手动断开抑制均有确定性测试 | LOCKED |
| S2-09 | Auto 核心真机与例外 Mock 的完整阶段回归 | USB→无线 TCP→USB 自动往返、控制回读、同机身份、切换中取消/不重放和睡眠恢复必须真机；多机歧义/不可安全制造的故障严格 Mock，分列结果及限制 | LOCKED |
| S2-10 | 连接/排障/配置迁移文档及报告 | 明确 USB 线材、授权、逻辑断开、TCP 保留、已测固件、回滚限制 | LOCKED |

**G2 通过条件：**

- [ ] M2 核心手动路径真机通过；Auto 作为必需功能实现并完成 USB 优先、失效自动回退同机无线 TCP、稳定恢复后自动切回 USB 的应用端到端真机验收，不以“adb 命令可用”代替；旧用户升级不强制改偏好。
- [ ] 所有现有控制入口经同一会话工作；同机双连接不双写，不向异机还原预设，旧网络配置/基线/快捷键保留。
- [ ] 核心连接、控制、手动/自动切换、插拔、断线、取消、睡眠唤醒、stop/start 有真机证据；同机身份正确、单活动写会话、无切换引入的重复命令、无频繁来回切换，USB 健康会话不被普通 TCP 故障重启。
- [ ] 首次授权无法安全复现、缺少第二台设备等例外按第 6.0 节严格 Mock 通过；分别标记 MOCK_PASS / HW_NOT_TESTED，登记原因、断言、证据、残余限制并由用户随阶段报告接受，不能写成 HW_PASS。
- [ ] 全量测试、构建和 Preview 隔离通过，文档及阶段回滚点完整，用户确认阶段通过。
- [ ] 未完成的核心真机项或未通过的安全测试仍为 BLOCKED/NOT_RUN；只有第 6.0 节符合条件并已接受的例外可以带限制验收，不能因此延期 Auto 或豁免核心真机闭环。当前 G2 = LOCKED。

### 阶段三：SwiftUI 最终优化

入口：G2 PASS。先在开发 Mac 使用已安装的 oil UI Pro 查阅实际工作流，捕获当前全部页面/菜单/弹层的安全 Preview 截图；以 Apple HIG 和当前公开 SDK 为依据。[macOS HIG][X03][Liquid Glass][X04]

| ID | 单一子任务 / 交付 | 验证标准 | 初始状态 |
| --- | --- | --- | --- |
| S3-01 | 现有 UI 审查、HIG 对照与最终组件规范 | Pro B 保留；消除 DESIGN.md 蓝牙/无 USB/旧系统冲突；记录 oil UI Pro 使用情况和 SDK 版本 | LOCKED |
| S3-02 | 统一主题、间距、字级、按钮和状态语义 | 先共享组件后页面；浅深色、减少透明度/动态效果、增加对比度可读；不用颜色独占表达状态 | LOCKED |
| S3-03 | 完成连接设置/首页/菜单栏的传输呈现 | 分开显示物理设备、USB/TCP/Auto、当前活动端点、视频源与授权/恢复状态；不显示虚假已连接 | LOCKED |
| S3-04 | 首页/画面/游戏/信号源/灯光一致化 | 保留已测范围、JNI 映射、禁用原因、未知读数和有效/记忆态区别 | LOCKED |
| S3-05 | 预设/自动任务/遥控/工具/菜单栏设置一致化 | 入口无遗漏，失败保留输入和位置，busy/取消/失败/成功均真实；危险动作有明确影响说明 | LOCKED |
| S3-06 | 原生键盘、焦点、窗口和辅助功能 | Tab/Shift-Tab、Return/Escape、VoiceOver、焦点可见；FastSlider 键盘调整/禁用态可用且提交规则不变 | LOCKED |
| S3-07 | Preview 状态与视觉矩阵完善 | 10 页面+菜单+连接/日志/设置弹层；浅深色、最小/默认/大窗口、正常及错误场景无裁切 | LOCKED |
| S3-08 | UI 性能与协议不变性验收报告 | 同条件 Instruments/交互记录、全量检查；UI diff 不改变设备命令/事务/预设/恢复策略 | LOCKED |

FastSlider、Theme 与窗口行为有历史性能/交互理由，不能仅因 HIG 建议就整体替换为系统 Slider/颜色或重建窗口。优先在现有组件补键盘/焦点/语义；替换需相同场景测量与行为测试支持。新界面尽量使用公开 Apple API；现有私有 OSD 路径与 HUD 回退作为明确兼容边界保留。

**G3 通过条件：**

- [ ] 全部页面/弹层组件规范一致，Pro B 方向与现有功能完整，用户确认最终视觉。
- [ ] 浅色、深色、跟随系统，减少动态效果/透明度，最小 1020×740、默认 1120×820 和 1440×1000 窗口无关键裁切；若调整最小尺寸须单独记录理由。
- [ ] 关键流程无需鼠标也能完成，VoiceOver 标签/值/状态可理解；未知、离线、待授权、错误不误示成功。
- [ ] Preview 不产生真实设备/网络/权限/文件副作用；业务协议回归通过，性能无可复现新增主线程阻塞。
- [ ] 截图、交互记录、检查日志、风险报告和用户确认齐全。当前 G3 = LOCKED。

### 阶段四：最终验收与收尾

入口：G3 PASS；先复核最终候选 SHA、工具链、设备原始状态、权限和真机操作批准范围。

| ID | 单一子任务 / 交付 | 验证标准 | 初始状态 |
| --- | --- | --- | --- |
| S4-01 | 冻结验收候选与执行环境清单 | 固定 SHA、资源锁、工具链/系统/设备固件、配置备份、批准范围、测试顺序 | LOCKED |
| S4-02 | 全量自动化、原生构建和边界检查 | 第 5 节日志/退出码齐全；复核默认 CI 仅编译/测试/架构检查、不生成 DMG/ZIP、不安装，打包仅显式触发 | LOCKED |
| S4-03 | USB/TCP/Auto 和现有功能分层验收矩阵 | 第 6 节核心项真机、双传输等价回读及恢复；例外严格 Mock + HW_NOT_TESTED 限制登记，拒绝只看 UI 推断成功 | LOCKED |
| S4-04 | 登录、重启、睡眠/唤醒与长期运行回归 | 用户安排窗口；关窗驻留/退出、真实下一次登录菜单栏、重启恢复、输出门控、自动任务恢复均验证 | LOCKED |
| S4-05 | 现行文档和历史文档收口 | 架构/使用/开发说明一致；旧阶段记录标明历史，不删除 R0–R6c 证据；清除当前说明中的过期阻断 | LOCKED |
| S4-06 | 本地独立交付物与可重复构建 | 版本化 .app、摘要/验证 JSON、资源 NOTICE、日志与重建步骤；相同锁/工具链重复构建核对 | LOCKED |
| S4-07 | Git/配置/二进制回滚演练 | 独立恢复目录构建和验证；保留原 App，源码/用户配置/系统权限/设备状态分开恢复 | LOCKED |
| S4-08 | 最终验收签字、记录非阻断项并冻结功能 | G4 全部通过后标 COMPLETE；保留最终不可变引用，不自动创建 Release 或开启新功能 | LOCKED |

**G4 / 项目完成条件：**

- [ ] G1、G2、G3 已有验收报告与用户确认；S1-08 前置顺序有提交证据，最终默认 CI 仍仅编译/测试/架构检查，无自动 DMG/ZIP 或安装路径。
- [ ] 必需自动测试通过，核心连接、控制、手动/Auto 切换与恢复用例 HW_PASS；Auto 的 USB→无线 TCP→USB 闭环、同机身份、安全切换、不重复派发和防抖全部有真机证据，不能延期到结项后。
- [ ] 第 6.0 节允许替代的例外全部严格 MOCK_PASS，并明确保留 HW_NOT_TESTED、原因、覆盖断言和残余限制，用户已接受；未执行的硬件步骤不得虚标真机通过，不因缺第二台设备或无法安全重建首次授权而单独阻断结项。
- [ ] 无未解决的崩溃、错设备写入、数据损坏、生命周期或核心恢复阻断；安全 Mock 失败、缺必需证据或核心真机未完成仍阻断验收。
- [ ] 有限的非阻断项及已接受的 Mock 替代限制写明影响、证据、原因和用户接受记录；Developer ID/公证/公开分发/Intel/Windows 为 OUT_OF_SCOPE。
- [ ] 开发 .app 与源码/配置备份、回滚点、资源摘要、工具链和验收证据可定位，现用正常版本仍受保护。
- [ ] 用户确认最终验收通过；将本文件状态置 COMPLETE、冻结功能范围并结束本轮。未通过时保持开发未完成，不能按计划写了多少或测试数量多就结项。

## 5. 可重复检查基准（未来在开发 Mac 执行）

本节为执行清单；各次实际结果分别见第 8.3–8.7 节及对应验收报告，未执行项维持 NOT_RUN，未通过项单独记 FAIL。S1-08 是任何业务源码修改及推送的前置门禁；下列自动检查适用于默认 CI，独立 .app 的本地交付构建属于显式步骤，不得连带生成 DMG/ZIP 或安装。以 macos 目录为工作目录，先记录 git HEAD/工作树、sw_vers、uname -m、xcodebuild -version、swift --version 和 SDK 版本。

~~~sh
python3 scripts/runtime_assets.py check
swift test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/validate_architecture.py
python3 scripts/validate_preview_boundary.py
~~~

资源未准备时才显式运行 python3 scripts/runtime_assets.py prepare；下载遵循 RuntimeAssets.lock.json，不使用 latest/Homebrew 回退。脚本测试中有 lipo/codesign 和锁定 adb 依赖，不能声称全部 Python 测试可在任意操作系统替代执行。

为本次运行选择一个尚不存在的 RUN_DIR，并分别构建：

~~~sh
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxApp -configuration Debug   -derivedDataPath "$RUN_DIR/AppDebug" -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- build
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxApp -configuration Release   -derivedDataPath "$RUN_DIR/AppRelease" -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- build
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug   -derivedDataPath "$RUN_DIR/Preview" -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- build
python3 scripts/validate_preview_boundary.py "$RUN_DIR/Preview/Build/Products/Debug/ToolboxPreviewHost.app"
./build_app.sh --mode development --version <三段版本> --build <数字构建号> --output "$RUN_DIR/Delivery"
~~~

- 记录每条命令退出码及完整日志；测试数量应为原基线加新用例，核查非预期减少。
- 验证 App 和内嵌 adb 仅 arm64、主程序 minOS 27.0、签名和资源锁/NOTICE 一致；使用现有 release_pipeline.py 的 verify-app 路径。
- Preview 至少做依赖图、源码效果、二进制符号、资源四层检查，并在实际交互中观察无生产子进程/外网 socket/用户偏好写入；静态扫描不能取代运行观察。
- 不自动执行 make_dmg.sh、reinstall.sh、setup_signing_cert.sh、export_signing_cert.sh、verify_jni.py，也不 open 生产 App 来做“无副作用”检查。
- verify_jni.py 会写设置再尝试恢复，不能纳入普通自动测试；高风险寄存器即使脚本声称跳过也要先审查。
- 自动测试中的 USB/TCP/Auto 用例使用内存设备/假命令/虚拟时钟，不默认连真机、不要求 RSA/TCC 授权；第 6 节核心项另行完成真实应用与显示器的验收，不能用自动测试替代。
- 可重复构建指从固定源码/资源锁和记录工具链重建可验证 App；若 UUID/签名/时间导致文件哈希不同，报告差异并核对代码、配置和资源，不能未经证明宣称逐字节可复现。

## 6. 真机验收矩阵与批准边界

### 6.0 核心真机与例外 Mock 的统一规则

以下规则同时适用于 M2、G2、G4 及全部验收表，不改变四阶段顺序。

- **核心真机必需**：在现有目标显示器上验证 USB 和无线 TCP 的真实应用连接、同一物理设备身份读回、代表性控制与设备回读、手动传输切换、Auto 的 USB→无线 TCP→USB 自动往返、切换中任务取消/账务、真实断线及睡眠唤醒恢复。不允许因已有 Mock、硬件调查成功或仅 UI 状态正确而豁免。
- **允许替代的特殊场景**：缺少第二台真实设备导致无法做异机/同型冲突测试；首次 RSA 授权无法在不撤销现有信任、不删密钥的前提下安全复现；以及必须破坏现用状态才能制造的极端故障。只能替代具体的特殊分支，不能把核心连接/控制/自动往返整项改为 Mock。
- **严格 Mock 条件**：通过实际生产解析器、状态机、会话/命令边界注入输入和失败，不以直接返回“成功”的空桩代替；使用独立用例断言身份缺失/重复/冲突时不写错设备、未授权不 ready、不重启健康 server、取消/超时/晚到回调无效、部分成功不重放、无重复派发；用虚拟时钟验证防抖/冷却/退避及最终自动回切。核对完整 argv/目标/operation ID、顺序与次数、状态及副作用，保留测试源码、日志、基线和结果。
- **限制登记**：逐项写明缺设备或无法安全复现的原因、未执行的硬件步骤、对应 Mock 断言与证据、仍未覆盖的 USB/固件/系统行为和残余风险。分列 MOCK_PASS 与 HW_NOT_TESTED；没有证据仍为 NOT_RUN，失败仍为 FAIL。
- **阶段裁决**：核心真机全部通过且特殊分支严格 Mock 通过后，用户可随阶段报告接受这些明确限制，阶段据此通过；不把该限制写成 HW_PASS，也不因单纯缺第二台设备或无法安全重建首次授权无限阻断。若安全断言失败、核心真机缺证据或限制未登记/未接受，仍为 BLOCKED。
- **批准边界**：此替代规则不授权高风险操作，也不要求为了凑真机覆盖破坏现有授权/应用/设备。获批范围内能安全完成的真实核心路径仍必须执行。

每条证据记录：用例 ID、日期/时区、源码 SHA、App 版本/路径、Mac/系统、显示器型号/固件、adb/server/选定端点、操作前值、预期、实际回读、恢复后值、日志/截图位置、操作者，以及分开的硬件结果（HW_PASS / FAIL / HW_NOT_TESTED / NOT_RUN）、Mock 结果（MOCK_PASS / FAIL / NOT_RUN）和限制接受记录。serial/IP 在公开材料中按必要程度脱敏；不提交密钥和偏好数据库。

### 6.1 连接与生命周期

| 用例 | 场景 | 必须观察的结果 | 证据要求 | 当前 |
| --- | --- | --- | --- | --- |
| HW-C01 | 无设备、单 USB、单 TCP | 候选/状态准确；只有明确选定且探活成功才 ready | 核心真机 | NOT_RUN |
| HW-C02 | 首次 USB 未授权、用户同意/拒绝或不操作 | 待授权可解释且可退出；不伪成功、不循环重启、不删密钥；已有受信任设备不得为测试擅自撤销授权 | 安全可测则真机；无法安全复现首次授权可严格 Mock + HW_NOT_TESTED | NOT_RUN |
| HW-C03 | USB 拔出/重插与逻辑断开 | 旧写入停止派发，缓存未知，显式断开后不抢回；接回重枚举同机 | 核心真机 | NOT_RUN |
| HW-C04 | 同机 USB+TCP 双在线 | 手动选择可预测，仅单活动会话；身份/预设基线一致 | 同一台显示器双传输真机，不要求第二台设备 | NOT_RUN |
| HW-C05 | 两台或同型/未知设备，USB/TCP 身份冲突 | 不选第一台、不按型号合并、不向错机恢复 | 有第二台则真机；缺少时严格 Mock + HW_NOT_TESTED | NOT_RUN |
| HW-C06 | TCP 故障且 USB 健康，反向故障 | 局部恢复；未受影响传输不被无故 kill-server | 局部断线/恢复核心真机；不可安全制造的极端故障可严格 Mock | NOT_RUN |
| HW-C07 | 操作中切 USB↔TCP / A↔B、同目标重连 | 旧回调无效，不跨端点续写事务或重复 toggle，busy 最终释放 | 同机跨传输/同目标重连核心真机；异机 A→B 可按缺设备例外 Mock | NOT_RUN |
| HW-C08 | Auto：USB 优先 → 有线失效回退无线 TCP → 有线稳定后自动回切 USB，反复抖动 | 真实身份匹配、单活动写会话、安全边界切换、不重复派发，稳定窗口/冷却有效，手动断开抑制 | 自动往返/稳定回切核心真机；极端时序另做虚拟时钟 Mock | NOT_RUN |
| HW-C09 | Mac 睡眠/唤醒、显示器休眠/恢复 | 两个唤醒通知合并，重新探活/回读，任务恢复遵循当前时段 | 核心真机 | NOT_RUN |
| HW-C10 | 关闭窗口、重开、退出/重开、真实登录与重启 | 驻留/退出偏好正确、登录菜单栏、无重复观察者/任务/进程 | 真实生命周期、登录与重启 | NOT_RUN |
| HW-C11 | server 不可用/重启、端口被占用 | 故障原因明确、有限恢复，重新枚举目标；不扰动用户其他 ADB server | 安全可测的真实恢复；破坏性故障分支按第 6.0 节严格 Mock | NOT_RUN |

核心真机重复性门槛：USB 拔插至少 5 次；手动传输切换至少 5 轮；Auto 的 USB→无线 TCP→USB 自动往返至少 5 轮并核对命令轨迹与控制回读；USB、TCP、Auto 各至少 3 次睡眠/唤醒；至少一次真实注销登录和一次 Mac 重启；至少 30 分钟混合使用观察任务/句柄/日志无持续增长。记录恢复耗时，门槛在 S2 审查时结合原有 25/120 秒等超时制定，不凭空缩短超时，也不把短样本当作稳定性上界。

### 6.2 现有功能等价回归

HW-F01 的音量/静音、HW-F02 的安全画面控制、HW-F04/05 的预设与任务、HW-F06 的菜单栏/快捷键等核心控制须在两种传输真机回读，Auto 切换前后亦须验证控制保持有效；异常和高风险分支按第 6.0 节单独判定，不整组豁免。第 6.0 节同时约束下表，未实测功能不得虚报通过。

| 用例 | 功能与证据 | USB / TCP 要求 |
| --- | --- | --- |
| HW-F01 | 首页音量加/减、绝对值、静音/解除、连按和回读 | 都验证；保持 Binder 首次验证及 keyevent 回退、输出门控、HUD/OSD |
| HW-F02 | 画面/背光、色温/增益、HDR/SDR 记忆、游戏状态读数 | 授权范围内写/回读/恢复；未知值不作确定状态 |
| HW-F03 | 信号源、灯光、遥控和游戏功能入口 | 所有入口路由一致；可能黑屏/待机/信号变化的写入先批准 |
| HW-F04 | 预设新建/保存/应用/返回基线、失败/中断 | 核心及同机跨传输真机；不覆盖基线、部分失败保留 applicationIncomplete；异机缺设备和不可安全制造的失败分支按第 6.0 节 Mock |
| HW-F05 | 自动任务开始/结束/重叠/跨日/错过时段/离线恢复 | 返回正确原预设，失效窗口不迟到执行，不重复下发 |
| HW-F06 | 菜单栏、自定义热键、亮度/媒体键、音频输出切换 | 默认目标匹配才拦截，撤权/未知输出安全放行，关窗仍可用 |
| HW-F07 | 工具：诊断、日志、Terminal、Guardian/APK/4K UI 路径 | 安全项真机；高风险部署/改分辨率分项批准；无法安全制造的特殊分支严格 Mock 并保留 HW_NOT_TESTED 限制，不推定真实部署通过 |
| HW-F08 | 深浅色、缩放、弹层错误、键盘/VoiceOver | Preview 全矩阵加真实 App 抽查，无新布局/响应回归 |

真机验证分层：

- 首先做只读设备发现/型号/状态/参数探针，确认地址与身份。生产连接可能自动部署 JAR、触发预设或记忆写入，因此不自动运行现用实例之外的新生产 App。
- 音量、背光和画面设置等写入先记录原值，在明确的测试范围内执行，完成后回读恢复。不能认为“可恢复”就无限扩大测试。
- EDID/320Hz、FreeSync、信号源、4K UI、USB 路由/寄存器、重启/待机/电源、APK/Guardian 部署、清授权或覆盖应用等影响真实状态的操作单独列计划，按用户规则获得明确批准。
- 没有批准的高风险项目不执行。若属于第 6.0 节允许的特殊分支，严格 Mock 通过并记录 HW_NOT_TESTED、残余风险和接受记录后，可带限制验收；若涉及核心真机连接/控制/切换/恢复仍未验证，保持 NOT_RUN/BLOCKED，不能以未获批准或一般 Mock 通过自动豁免。
- 代码/二进制回滚不能撤回已生效的设备设置，也不自动恢复 TCC、SM 登录项或 adb RSA 信任。

## 7. 交付、回滚和文档收尾

- 每个已验收阶段保留唯一不可变源码引用/提交及父基线，不重写 master 历史，不移动 R0–R6c 标签；检查点不使用会自动触发发布的版本标签套路。
- 默认交付：开发 Mac 上新目录中的版本化 development .app、app-verification.json、完整日志、资源锁/摘要/NOTICE、测试报告和本地重建说明。需要 ZIP 或 DMG 时另按用户要求显式生成。
- 保护现用 App：记录其路径/版本/摘要并保留原件。临时验收实例不能与现用实例争抢 Bundle ID、登录项、快捷键、偏好或 server；执行前明确停用/隔离计划，不把换端口误当完全隔离。
- 保留用户配置的受控本地备份，备份不得公开；新增连接/身份偏好提供回滚兼容，原 picture_presets_v1 仍可读。
- 在独立恢复位置验证上一阶段源码可构建、新配置可回退、原 App 完整；不对当前工作树 reset --hard，不默认恢复系统授权或设备状态。
- docs/ARCHITECTURE.md（后续创建）承载现行依赖、状态/并发所有权、ADB 目标/身份与生命周期设计；README.md、macos/README.md、DESIGN.md 承载现行使用/开发/视觉规范。
- REFACTORING.md、R3/R4/R5、R6-RELEASE.md、R6-CLOSEOUT.md 保留为历史；加历史范围和当前文档链接，不能把未做的旧验收改写成已通过。
- 证据可在后续 docs/acceptance/ 分阶段报告中索引，真实大日志/敏感设备资料留受控本地；进度与最终裁决仍只更新本文件。

## 8. 当前进度、阶段报告与下一步

### 8.1 总表

| 项目 | 当前状态 | 已有证据 / 缺口 |
| --- | --- | --- |
| 现状审计与路线图修订 | DONE_REMOTE | 初版证据与修订历史保留；后续 S1-08 独立执行见下行及第 8.3 节 |
| 阶段一 | S1-08 DONE；S1-02 DONE_WITH_FINDINGS（历史）；S1-10 DONE；S1-03 DONE；S1-04 DONE；S1-05 DONE；G1 NOT_PASSED | TCP 会话及 server 恢复边界、本机/默认 CI、实际 Preview 与回滚通过；A04/A17 本任务范围关闭，A01/A02/A03 部分落实；S1-06 未开始，用户阶段验收未进行 |
| 阶段二 | LOCKED | G1 未验收；Auto 为必需交付，USB→无线 TCP→USB 核心真机闭环不能省略 |
| 阶段三 | LOCKED | G2 未验收；oil UI Pro 已在用户开发 Mac |
| 阶段四 | LOCKED | G3 未验收；真实睡眠/登录/重启及最终交付均待执行 |
| 项目结项 | NOT_COMPLETE | 不以路线图上传作为完成开发 |

### 8.2 路线图初次修订报告（历史，不代表当前执行状态）

- **变更清单**：仅修改 docs/ROADMAP.md，保留四阶段和任务 ID；明确 Auto 必需及有线失效回退/恢复回切、安全切换和防抖；增加核心真机/例外严格 Mock 分层；将 S1-08 提前并同步任务依赖、阶段门禁和结项条件。
- **验证证据**：修订起点为 d91755f；初版审计的 10 模块/85 Swift 源文件、233 Swift/24 脚本测试定义等事实保留，本次不冒称重新执行审计或测试。核对任务 ID/实际顺序、Auto 和例外验收表述、引用及 Markdown 结构；上传时核验父节点、仅 ROADMAP 单文件 diff、完整内容回读和 master 指向。
- **未执行**：业务源码修改、CI 配置修改、Swift/Python 测试、Xcode/Preview 构建、CI 运行、真机操作、权限变更、安装覆盖、DMG/ZIP 打包或正式发布。本次文档提交继续使用 [skip ci]，CI 前置任务尚未实施。
- **遗留风险**：第 2.4 节风险待后续处理；核心真机和允许替代的 Mock 本轮均未运行，未实测限制尚无可据以通过的测试证据；所有阶段验收状态保持原状。
- **下一步**：后续启动阶段一时，从 S1-08 的只读审查与最小计划开始，独立完成 CI 前置改造/推送并验证后，才解除业务源码修改及推送禁令；本次不自动实施。

### 8.3 S1-08 执行与验收报告（2026-10-22，UTC+8）

- **固定起点**：76e01144ec7cb8050b88ca424d4ac636b8fb2d8a；从本机 52d90d6 快进，新增两提交只涉及本文件，工作树初始干净。业务源码保持 52d90d6/R6c 基线。
- **审查发现**：默认 build job 在测试和 Release 编译后无条件执行 make_dmg.sh 并上传 DMG/ZIP；distribution/release 虽为显式分支，但仍将本轮不要求的 Developer ID、公证及公开分发放在现行工作流中。build_app.sh/release_pipeline.py 已支持 development ad-hoc、校验资源/arm64/minOS/签名、拒绝覆盖输出，且不安装/启动；make_dmg.sh 已独立，无需重写。
- **单一目标与最小计划**：优先仅调整 .github/workflows/macos.yml；默认 job 保留测试、架构、Preview 和 ad-hoc 编译/验证，补 App Debug 编译并隔离全部构建输出；独立 package job 仅接受 workflow_dispatch 且 package=true，复用现有 development 构建/打包入口；移出现行 workflow 的 distribution/release jobs，历史脚本保留。不修改业务/测试/资源/构建/安装脚本。复核后发现两份现行 README 仍写默认上传包、正式凭据阻断，因此仅同步其中 CI/签名段落；其他使用/架构/历史文档不整理，不提前执行 S1-09。
- **验证计划**：检查 YAML/Actions 语法和 push/PR/默认手动/显式打包的入口矩阵；按新默认命令在独立目录执行现有 Python/Swift 测试、App Debug/Release、Preview 与产物验证；核对无 DMG/ZIP、现用 App 内容摘要不变；受控提交使用 [skip ci]，推送后显式触发默认验证并读回 job/步骤/产物状态。用户未请求生成打包产物，因此仅核对显式打包的门禁与已有打包回归，不实际打包。
- **保护与回滚**：保留 macos/红米G Pro ToolBox.app 原件，记录版本及目录内容 SHA-256；不启动新生产 App、不触碰偏好/TCC/登录项/ADB/显示器。回滚固定父提交 76e0114，采用新提交撤销 CI 差异并用 [skip ci] 防止旧默认打包复活；不 reset --hard、不移动旧标签。审查时远端无注册 runner；本次验证使用单任务临时 runner，未建立常驻服务。
- **本次边界**：只执行 S1-08；S1-02 及后续任务不启动，G1 NOT_PASSED，阶段二至四保持 LOCKED。
- **变更结果**：实施提交只修改 workflow 与本文件，验收补记提交仅更新本文件及两份 README 的 CI 说明，共四个文件。build job 无 make_dmg/上传包/凭据/公证/安装步骤；package job 的条件为 `github.event_name == 'workflow_dispatch' && inputs.package`，boolean 默认 false，并依赖 build 成功。移除现行正式分发 jobs；不删历史脚本。Swift scratch、App Debug、Release、Preview、显式 package 的派生数据/产物各在 runner.temp 的 run ID/attempt 专属目录，不复用现用 App 或原构建目录。
- **本机测试结果**：macOS 27.0.1 (26A434)、arm64、Xcode 27.1 (27A9275)、Apple Swift 6.4、SDK 27.0。从新 workflow 提取默认 job 的原始 run 命令逐条执行，10 条命令全部退出 0：资源 prepare/check；Python 24/24；Swift XCTest 197+36=233/233（另有 Testing 库的 0 tests 行，不作为计数）；架构、Preview 源码检查；App Debug、Preview Debug；Preview 二进制/资源检查；Release development 构建及内置 verify-app（arm64/minOS 27.0/ad-hoc/资源锁）均 PASS。actionlint 1.7.12（官方发行摘要核验）退出 0；7 种触发组合静态断言 PASS；git diff --check 退出 0。
- **本机证据**：受控目录 `../validation/S1-08-20261022-192707/`（相对仓库）：`environment.json`、`workflow.json`、`trigger-matrix.json`、`commands.json`、`02.log`–`11.log`、`local-default/toolbox-build-local-1/app-verification.json` 及其中 `build.log`。命令、退出码、耗时和完整日志可回查，不上传大量构建缓存。
- **无副作用核对**：默认构建输出没有 DMG/ZIP；现用 App 内容树 SHA-256 前后同为 `d12c4857f04c43e6d54e07568ac1ebf6a285521e6237dbb0d8b0092710e4fec6`。没有运行生产 App/安装/证书设置/ADB 探针/真机写入；Mock 为现有测试中的假设备/执行器覆盖，HW_NOT_TESTED，硬件验收不属本子任务。
- **独立提交与远端验收**：CI 提交 `9994f05c1a119b1cd14a3498302f47188dc9f3bb`，父提交 `76e01144ec7cb8050b88ca424d4ac636b8fb2d8a`，仅 workflow/ROADMAP 两文件，使用 [skip ci] 并已推送 origin/master；远端 workflow 完整回读与本机字节一致。取消旧基线排队运行 39698075389 后，以不传任何打包输入的 workflow_dispatch 启动 [39771408162](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39771408162)；2026-10-22 19:33:19–19:35:45（UTC+8）完成，**build=success、package=skipped、总体 success、artifact total_count=0**。远端完整日志确认 24 Python 和 197+36 Swift 测试全部通过，三种构建与各边界/Release 校验成功，退出码均为 0。对应 `remote-default.log`、`remote-run.json`、`remote-jobs.json`、`remote-artifacts.json` 保存在上述受控目录。
- **runner 生命周期与非阻断限制**：校验官方 actions/runner v2.338.0 arm64 发行摘要后临时注册 `s1-08-validation-20261022`，使用单任务 ephemeral 模式（[官方说明](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#ephemeral-runners-for-autoscaling)），没有安装 LaunchAgent/常驻服务或设置发布秘密。job 成功后 runner 进程退出 0，自动删除 .credentials/.runner；API 回读 total_count=0，记录 `runners-after.json`。以后默认 CI 仍需在线的 macOS 27 ARM64 runner，否则排队；这不影响本次已完成的真实远端验证，不把临时验收当作常驻基础设施交付。
- **回滚验证**：在独立 `rollback-checkout/` 恢复固定父提交 76e0114 的 detached checkout，显式资源准备与 development Release 构建退出 0，`rollback-verified-app/app-verification.json` 校验 arm64、minOS 27.0、ad-hoc、资源及 source_head；命令和完整日志见 `rollback-git-commands.json`、`rollback-git-0.log`、`rollback-git-1.log`。初次仅用 archive 的尝试因没有 Git 元数据而在报告 source_head 时退出 1，日志 `rollback-1.log` 保留；未修改产品脚本，改用带 Git 元数据的固定 checkout 重跑通过。当前业务/测试/资源/构建脚本相对父提交无 diff，现用 App 最终摘要仍不变（protected-app-before/after.json）。回滚用新提交恢复父版、保留 [skip ci]，随后暂停旧 workflow 或重应用本门禁，禁止直接运行父版自动打包流程；不 reset --hard，不移动旧标签。无现用二进制/偏好/权限/设备变更需要恢复；阶段四的完整产品/配置演练仍未执行。
- **验收结论**：**S1-08 PASS / DONE**，本机、远端默认手动入口、源码独立提交/上传与父源码回滚构建证据齐全；A12 的默认 CI 打包风险关闭。显式 package=true 的实际打包为 NOT_RUN（本次未请求生成 DMG/ZIP；已有 6 项打包脚本回归通过）；其入口经语法、条件和 development 调用核对。PR/标签/push 及 fork PR 的入口限制是配置/条件证据，未冒称逐事件实跑。Preview 本次仅自动布局测试和静态/二进制/资源检查，无交互观察或真机测试；该限制不属于 CI 解耦阻断项，不豁免后续阶段门禁。
- **用户阶段验收与下一步**：本子任务验收报告已提交供用户审阅；G1 仍为 NOT_PASSED，用户尚未确认阶段一通过。S1-02 仅变为可开始，本次不执行；S1-03 及其他任务保持原计划，阶段二至四 LOCKED。

### 8.4 S1-02 基线与风险复核（2026-10-22，UTC+8）

- **固定起点/前置**：f3a97520a2cdedd0ba360d7f56bcd5e76c2a39cd，远端已 fetch 确认无新增提交，初始工作树干净；S1-08 提交 9994f05 与远端成功运行 39771408162 已回读。Sources/Tests/Config/assets/Package/Xcode/scripts/构建脚本相对 52d90d6、R6c 的路径/blob 均不变。
- **单一目标/计划与保护**：只建立未改动业务源码基线并逐项复核 A01–A16/A08 调用语义；先在受控本地记录计划、工具链、固定树对象和现用 App 内容摘要，备份生产/preview 偏好及现存登录项/ADB 密钥文件，再在全新 Swift/AppDebug/AppRelease/Preview/Delivery 目录验证。只更新本文件与 [证据报告](acceptance/S1-02.md)，不改业务、测试、CI 或构建源码；不安装、打包、启动新生产 App或操作真机，不执行 S1-03。
- **测试/构建**：macOS 27.0.1、arm64、Xcode 27.1、Swift 6.4、SDK 27.0；11 条基线命令退出 0。Swift XCTest 197+36=233/233、Python 24/24；App Debug/Release、Preview Debug、架构与 Preview 依赖/源码/二进制/资源检查 PASS；development 独立 .app 及 verify-app 确认 arm64/minOS 27.0/ad-hoc/锁定资源/NOTICE，dirty_tree=false。未下载缺失资源，未生成 DMG/ZIP；新 .app 未启动。
- **风险复核**：A01–A16 逐条列出固定源码链接、既有测试和缺口；A12 维持关闭，其余没有冒称已修。A06 追加状态展示/live start 的同类下标路径；A07 缺失/无效 JNI 导致 0 的源码事实保留；A08 完整列出 50 shell/5 checkedShell 直接表达式及间接包装语义，既有乐观更新与 checked/预设回读路径区别明确，没有新增具体误报复现，故不新建/修复 A08 任务。
- **Preview 实测与失败诊断**：实际抽查已连接/未知读数/权限拒绝 3 场景、静音/虚拟时钟/模拟 Terminal 反馈，约 83.53 秒、149 次 ps/lsof 采样未见子进程/INET socket，退出已确认。生产偏好与密钥未变；但独立 preview 域新增唯一 NSWindow Frame preview，磁盘和有效域一致。结合 Window 声明推断为框架自动保存，未做调用栈审计；严格零偏好写入 **FAIL**，新增 A17，不用静态 PASS 覆盖。未删除/回写该偏好。第一次在 Preview 编译尚未完成时打开失败，等待构建/边界通过后重试成功，无产品修改。
- **证据目录**：`../validation/S1-02-20261022-194139/`（相对仓库）：environment/source-baseline/commands/risk-review/shell-inventory.json、baseline-01…11.log、Delivery/app-verification.json/build.log、preview-observation.json、Preview 截图/AX 文本；private-protection/ 为受控私密备份，偏好/密钥不上传。Mock=既有假设备/执行器断言通过，硬件统一 HW_NOT_TESTED；无新真机结论。
- **回滚/限制**：固定父基点 f3a9752；源码未变，本次全新目录构建验证相同父源码可构建。报告/路线图可用新提交撤销，不 reset --hard/移动旧标签。现用 App、生产配置/权限/设备未改，不需恢复；Preview 新增窗口元数据保留并明确未恢复。S1-08 的独立 checkout 演练为历史证据，阶段四完整二进制/配置回滚未做；采样不能证明间隔内绝无瞬时行为，三场景抽查不代替完整视觉/交互验收。
- **远端提交/验证**：首个证据提交 337fc9d7b5f9ba59418fa3d2b3dc2b80de2766b8，父节点固定 f3a9752，只有本文件和证据报告，正常 push 已触发 [39773941884](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39773941884)。2026-10-22 19:53:54–19:56:17（UTC+8），总体 success、build success、package skipped、artifact total_count=0；远端日志读回 24 Python/233 Swift、三种构建/自动边界校验通过。临时单任务 runner 退出 0 并注销，远端 runner=0，未安装服务；以后 CI 需有在线 runner。CI 未执行交互观察，不能据此关闭 A17。
- **最终保护**：原 App 内容摘要与 PID、生产偏好/有效域及已记录 ADB 密钥文件在远端验证后再次核对不变；Preview 新增窗口元数据为已知且未恢复的唯一偏好差异。无安装/打包/真机操作。完整结论与逐条清单见证据报告；结果 SHA 由本报告提交的 Git 历史定位，补记仍仅同两份文档，并用 [skip ci] 避免重复文档验证，不免除未来业务源码 CI。
- **当前裁决/下一步**：**S1-02 DONE_WITH_FINDINGS**：未改动业务源码的基线与逐项风险审查目标已完成；自动门禁 PASS、严格 Preview 偏好项 **FAIL（A17）**。这不是阶段 PASS，G1 NOT_PASSED，用户阶段验收尚未进行。仅记录 A17/既有风险与后续归属，不擅自修复、不放宽隔离要求，S1-03 及任何后续任务均未启动。

### 8.5 S1-10 / A17 执行与验收（2026-10-22，UTC+8）

- **授权与固定起点**：用户单独授权先登记并仅处理 A17；起点 4a72bf70fa996e769fb038c710b20f0843f03ec1，fetch 确认远端一致、工作树初始干净。S1-02 的失败证据保留，不将过去 FAIL 改为过去 PASS；S1-03 不开始。
- **审查/最小计划**：实际 Preview 入口为 ToolboxPreviewHost/App.swift 的 SwiftUI Window(id: preview)，没有显式恢复策略；Apple WWDC24 与 Scene.restorationBehavior 文档说明默认恢复会保存尺寸/位置。本机 SDK 确认公开 restorationBehavior(.disabled) 可用，优先只在 Preview Window 场景加此 modifier；不改生产窗口、MemoryPreferences、全局 UserDefaults 或用户文件，不用删除旧值掩盖写入。
- **验证计划**：先独立构建 Preview Debug，运行真实场景，强制移动/缩放、切场景、关闭/重开和退出/重启；比较 preview/生产偏好有效域、原始 plist 字节及 mtime，并采样子进程/socket。现有 preview 值保留；另用仅测试构建的新 Bundle ID 验证空偏好域不产生数据。若公开 modifier 不能阻止保存，按实际证据再决定最小 AppKit 边界修复，不能提前宣称通过。
- **回归/保护**：新输出目录运行原 233 Swift/24 Python、三种构建、架构/Preview 四层检查、development .app/verify-app；不安装、不打包、不启动新生产 App、不操作 ADB/显示器。先在受控本地备份偏好/记录密钥、原 App 摘要/版本/PID；固定父基点回滚，不 reset --hard 或移动旧标签。
- **证据**：本机受控目录 ../validation/S1-10-A17-20261022-200256/；用户偏好和密钥不提交。只允许 Preview 宿主、必要 A17 回归/说明、ROADMAP 与专属验收报告变化，其他任务保持原状。
- **本机实施结果**：仅 PreviewHost/App.swift 加 `.restorationBehavior(.disabled)` 一行，关闭默认场景恢复/几何保存；未使用 AppKit 或全局偏好补丁，旧值不删除。正式偏好域完成移动/zoom/交互/退出/重启和关闭重开；另用仅测试构建的新 Bundle ID 验证空域。共 871 次采样，三个监测窗口 203.43/117.96/95.92 秒（含空闲期），有效域无变化，原 plist 字节/mtime 不变，新域不生成 plist；真实窗口与内存交互正常，A17 本机 PASS。
- **自动回归**：原 233 Swift/24 Python 全通过；11 条基准命令退出 0，App Debug/Release、Preview Debug、架构/Preview 四层检查、独立 development .app 与 verify-app 均 PASS。没有新增/削减既有用例；A17 专项为真实宿主窗口运行回归。local report 为父 HEAD + dirty_tree=true，源码补丁/摘要保留，远端将验证实际提交。
- **保护与证据**：原 App 内容摘要/PID、生产/preview 偏好文件及有效域、已记录密钥/登录项文件均未变，测试实例已退出；无安装/打包/真机操作。完整原因、公开 Apple 文档、命令/日志、窗口交互和探针诊断见 [S1-10/A17 验收报告](acceptance/S1-10-A17.md)。宽松进程匹配误计旁路 PID，精确可执行路径复测无宿主子进程/socket；采样限制如实保留，不冒称系统调用审计。
- **提交/远端验证**：修复提交 4cef289fafbbb121489ee33c86ede5e0443dadab，父基点 4a72bf7；仅 Preview 宿主一行与两份本任务文档，受测源码摘要一致，正常 push 未 skip。[39777222854](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39777222854) 于 2026-10-22 20:19:11–20:21:28（UTC+8）执行，success；build success、package skipped、artifact=0；远端 24 Python/233 Swift、三种构建与自动边界/产物验证通过。
- **最终保护与 runner**：远端结束后再次核对原 App、生产/preview 偏好字节/mtime/有效域、新测试域空/无文件，均 PASS；现用实例保持，历史键保留。临时单任务 runner 退出 0、注销后远端 runner=0，无常驻服务或发布秘密；以后 CI 仍需在线 runner。结果文档补记仅同两份文档并用 [skip ci]，不免除未来源码 CI。
- **最终裁决**：**S1-10 PASS / DONE，A17 CLOSED_S1-10**；原零偏好写入要求未放宽，S1-02 历史 FAIL 不改写。仅关闭本项，不提前标 G1 PASS：其他 S1 任务、最终候选复验和用户阶段验收仍未完成。S1-03 未开始，阶段二至四 LOCKED，本次到此止步。

### 8.6 S1-03 审查与设计验收（2026-10-22，UTC+8）

- **固定起点与单一目标**：a41519a459c36762b8726a4a58507428c8b1b697；fetch 后本机/远端一致、工作树干净。审查现有端点、设备身份、会话与状态，并交付统一契约/旧配置兼容设计；只修改本文件、新增 [设计文档](ADB-CONTRACTS.md) 和 [验收报告](acceptance/S1-03.md)。不改业务/Preview/测试/CI/构建源码，不开始 S1-04。
- **审查与最小计划**：沿实际 AdbClient/AdbSession、ConnectionIntent/9 状态模型、协调器连接/预设/恢复、AdbPresetDevice、PresetStore/Engine/Worker、执行器与 Preview 调用路径审查；核对原测试与锁定资源。先记录基线/现用 App 和配置保护，再写设计、复核来源/兼容矩阵、运行现有自动回归，普通 push 验证默认 CI，最后补齐验收记录。
- **设计决策**：端点、稳定 DeviceID 与旧预设兼容键分离；保留提交快照/父子取消/事务锁/operation ID。连接阶段、枚举与身份分别表达；unknown 不自动认领旧数据，conflict 阻断写入。旧 saved_ip 首读沿用手动 TCP、不默认 Auto、不重写 picture_presets_v1；有证据且经归属确认后用别名桥接，未知 schema/写入失败保持原值并阻断激活。详列二次迁移、并发编辑、崩溃和旧版降级限制。设备协议/命令映射/预设状态机不重写。
- **实证边界**：当前旧任务定义不含设备 ID，仅运行 session 有身份；型号唯一不是同机证据。发现的兼容/安全决策归原 A01/A02/A05、S1-04/05 和阶段二，不将设计标为修复。Auto 仍是必需交付，时序参数待 S2-08，不能提前实现或延期免验收。
- **本机验证**：5 条命令均退出 0，原 233 Swift（197+36）/24 Python 通过；runtime assets check、架构（9 模型/无环）、Preview 源码边界通过。原用例不增删，不把已有测试称为新设计实现验证；后续 D01–D12 契约矩阵保持待实施。证据 `../validation/S1-03-20261022-202833/` 的 baseline.json、commands.json、check-01…05.log，私密备份不上传。
- **保护与回滚**：固定父基点 a41519a；文档变更可通过新提交撤销，保留历史/标签；不 reset --hard。当前 macos 完整树保持 `9dc18e459b763ce7d8358f57f07795e4e8238338`，新候选和父版产品源码相同；设计中的配置迁移/回滚仅方案，未执行用户配置迁移。现用 App 保留原件，不安装、不生成 DMG/ZIP、不操作真机；Preview 交互证据沿用 S1-10 历史，不冒称本次重跑。
- **提交/远端验证**：设计提交 bf18c7888082ae25d71ce32fdfa112ae95926eb9，父节点 a41519a，普通 push 触发 [39779677568](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39779677568)；2026-10-22 20:36:39–20:38:57（UTC+8）build success、package skipped、总体 success、artifact=0。远端原 233 Swift/24 Python、App Debug/Release、Preview Debug、架构/Preview 自动边界及 development 产物校验通过。Release 在脚本内部构建/验证，日志输出 PASS；完整远端日志和 run/jobs/artifacts JSON 留本机证据目录。
- **文档/保护/回滚结果**：17 个固定源码引用、相对文件链接、围栏/验收覆盖、非文档 blob 与 diff 检查通过；在独立临时目录应用文档逆补丁，恢复父版字节，PASS。CI 结束后原 App（20261022.8）目录摘要/PID、生产/Preview 偏好有效域及原文件字节/mtime、已记录 ADB 密钥均不变。没有新生产/Preview 交互、安装、打包或真机操作；动态 Preview 仍仅历史证据。单任务临时 runner 自动退出 0/注销，远端 runner=0，无常驻服务；以后 CI 仍需在线 runner。
- **最终裁决与下一步**：**S1-03 PASS / DONE（设计交付）**。提交与回读只含三份文档，结果补记仅 ROADMAP/验收报告并使用 [skip ci]，产品源码与受测提交/父版完全一致；最终结果 SHA 由该补记提交定位。新契约未实施，A01/A02/A05 未关闭，G1 NOT_PASSED；用户阶段验收未进行。S1-04 尚未开始，本次停止，阶段二至四 LOCKED。

### 8.7 S1-04 TCP 会话迁移与验收（2026-10-22，UTC+8）

- **起点与审查**：固定父基点 ca2bee5d5a4672062e8ddbbbf2e99049e85e6f10，fetch 后本机/远端一致、工作树干净。沿 AdbSession/AdbClient、协调器连接/预设/监控、RuntimePorts、Live/Preview 工厂、PresetDevice/Engine/Store、提交队列与测试审查；先保存现用 App/偏好/密钥摘要和私密备份，再记录最小计划。完整报告见 [S1-04](acceptance/S1-04.md)，契约实施边界见 [ADB-CONTRACTS 第 0 节](ADB-CONTRACTS.md#0-s1-04-实施边界2026-10-22)。
- **最小变更**：增加仅 TCP 的不可变 AdbEndpoint，以 endpoint? 替换 activeIP/targetIP；保留旧 ip 兼容入口、默认 5555 和 serverPort。连接/断开/临时扫描只替换目标构造；预设 endpoint 与 legacy identity 分参，从既有提交会话取固定目标。原锁/FIFO/取消/晚到回调、预设引擎/JSON/命令映射、状态/UI、恢复决策不改。10 个 Sources 文件（含新文件）、3 个测试文件、3 份文档；无 workflow/脚本/资源/工程改动。
- **对照与回归**：独立父版原 233 Swift/24 Python 及 development Release 构建/验证通过；5 个同源码 TCP/旧配置 fixture 在父版和候选均通过。候选 244 Swift（208+36，原 233 + 新 11）/24 Python、资源、架构、Preview 源码、App Debug/Release、Preview Debug、二进制/资源边界、development App 与 verify-app 全部 exit 0。原测试断言保留，仅既有预设 fixture 构造增加等价 endpoint 参数。
- **实际 Preview**：已连接模拟音量、预设创建/画面调整、模拟时钟、未知读数、断开并连接新 TCP 目标、窗口缩放、退出/重启；118.49 秒/251 样本，其中 167 个有宿主进程。两次宿主 PID 均未观察到子进程或 INET socket；生产/Preview 有效偏好域、原文件字节/mtime、ADB 密钥不变。A17 旧窗口键保持，测试预设重启不保留；采样局限与四层静态证据见报告。
- **风险/范围**：A01 仅 TCP 会话部分、A02 仅 endpoint/identity 传参分离；物理身份、USB/Auto 和 A05 状态仍未实现。S1-05/A08、S1-06/07 OUT_OF_SCOPE；本次所有硬件项 HW_NOT_TESTED，不作为阶段二真机验收替代。无安装、DMG/ZIP、生产 App 启动或真机操作。
- **保护/回滚**：现用 20261022.8 App 摘要/PID、偏好及 ADB 密钥保持；父版在独立 rollback-checkout 构建通过，候选 16 个文件正逆补丁在独立检出验证恢复干净父版，PASS。本次不改持久化 schema，不需转换配置；不在工作树 reset，不移动历史标签，不恢复系统权限/设备状态。
- **提交/远端验收**：实现提交 60f476c21d08c86c465f8b65c2e49bb392f33a53，父节点 ca2bee5；普通 push 触发 [39783249813](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39783249813)。2026-10-22 21:02:17–21:04:34（UTC+8）build success、package skipped，21:05:43 总体 success，artifact=0。远端 244 Swift/24 Python、App Debug/Release、Preview Debug、架构与 Preview 自动边界通过；保留完整步骤日志和 CI Release build.log/app-verification.json，确认 source_head=60f476c、dirty_tree=false、development/ad-hoc，无 Developer ID。临时 runner 自动退出 0/删除凭据，API runner=0，无常驻服务。
- **最终裁决**：**S1-04 PASS / DONE（仅 TCP 最小迁移）**。原 233 测试保留、11 新增通过，工作文件与被测提交一致，16 文件正逆补丁/文档检查通过；CI 后原 App/PID/配置/密钥保护复核通过。结果补记仅 ROADMAP/本报告，使用 [skip ci]，macos 产品树与受测 60f476c 相同；最终 SHA 由补记提交定位。远端文档完整回读/最终清洁状态记录在 `final-verification.json`。证据目录 `../validation/S1-04-20261022-204444/`，私密备份不上传。G1 NOT_PASSED，用户阶段验收未进行；S1-05 未开始，阶段二至四 LOCKED。本次停止。

### 8.8 S1-05 server 查询与恢复边界（2026-10-22，UTC+8）

- **授权/基线**：本次仅 S1-05，固定起点/回滚父基点 0bd6c05c5840c1344db50137c11b72205fd30e33；fetch 后与 origin/master 相同，工作树干净。先记录 tracked blob、工具链、原 App/PID、偏好/密钥及私密备份，再独立父版验证。完整报告见 [S1-05](acceptance/S1-05.md)。
- **审查/最小计划**：version 只证明客户端；monitor 存在绕过冷却的重启入口；unauthorized 可能落入恢复；配置端口不证明独占 server。只改 AdbClient 和 monitor 调用边界，新增专项测试。移除应用显式 kill/start 恢复循环，保留成功 TCP 轨迹与目标重连；失败后仅一次 25 秒冷却的 host-features 查询，成功才允许最终目标重试。冷却用单调时钟，失败也记账；未授权/取消不恢复。
- **锁定接口核验**：37.0.1-15733141 原始 adb SHA-256 1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b；help/version 与本地假 Unix socket 实测确认 host:version → host:host-features，成功/拒绝/截断响应区分。空本地 socket 的 version 仍成功；显式远端 host 模式下仅访问空 loopback 端口，查询失败且不启动 daemon。没有访问现用 server/设备。host-features 未列入当前 help，实际锁定二进制行为和官方源码共同支撑选型。
- **生命周期限制**：host-features 是主动查询，普通官方 adb 命令可自动启动缺失 server，版本不匹配时可自行替换；本次不宣称其只读或完全消除 server 级副作用。显式预热与执行器环境保持，不新造 server/USB/RSA 栈。A03 仅收敛应用恢复决策；多客户端/版本冲突、USB/TCP 故障及真机恢复仍须 S2-02/06 验证；A08 不混入本次。
- **本机验证**：基线 244 Swift/24 Python、独立父版 development Release 构建通过；候选 257 Swift（原 244 + 新 13）/24 Python、11 条回归命令、三种构建、架构/Preview 四层边界及 development 产物检查全部 exit 0。实际 Preview 音量/场景/zoom/退出重启，85.97 秒 180 样本（122 有宿主），无子进程/INET/偏好或密钥变化；原 App 内容/PID 保持。6 文件正逆补丁在独立父版恢复干净源码、原测试保留和文档检查通过。本机与默认 CI 均通过。证据 `../validation/S1-05-20261022-211401/`，私密备份不上传；S1-06 未开始，G1 NOT_PASSED。

- **提交/默认 CI**：实现提交 8b09ce3cf7fd6bda2e1f6dd37566e8fa95d24bf2，6 文件；172 个 macos 文件与受测摘要一致，普通 push 触发 [39787115283](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39787115283)。2026-10-22 21:29:10–21:31:30（UTC+8）build success，package skipped，21:32:22 总体 success、artifact=0；远端 257 Swift/24 Python、构建与自动边界通过。保存 clean HEAD Release 构建/验证报告（development、team=null）；临时 runner 退出 0/自动注销，远端 runner=0，无常驻服务；以后 CI 仍需在线 runner。
- **最终裁决**：**S1-05 PASS / DONE**；A04 CLOSED_S1-05，A03 仅完成应用恢复边界，不整体关闭；A08 不变。CI 后原 App/PID、偏好及密钥保护再次通过，无安装/打包/真机操作。结果补记仅本文件与验收报告，使用 [skip ci]，产品树与受测实现一致；最终完整文档回读/清洁状态记录 `final-verification.json`。本次硬件 HW_NOT_TESTED，不替代阶段二核心真机门禁；G1 NOT_PASSED，用户阶段验收未进行。S1-06 未开始，阶段二至四 LOCKED，本次停止。

### 8.9 S1-06、S1-07、S1-09 顺序执行与验收（2026-10-22，UTC+8）

- **授权/基线**：本次依次执行上述三个独立子任务；父基点 5eec375737050eb6e668227116533de985909740，与 fetch 后 origin/master 相同、工作树干净。先记录源码/工具链及原 App/PID、生产/Preview 偏好/密钥，私密备份仅本机。固定父版 257 Swift/24 Python、资源、架构/Preview 源码、development Release 构建/产物检查全通过。
- **计划**：S1-06 在独立父版内存 fixture 复现非法记忆下标，再复用既有 RegisterMap.localDimmingNames 校验显示/恢复及写入入口；不清洗或静默写回原 JSON。通过后再实施 S1-07 的 JNI 游戏读数未知语义，保留合法枚举/命令；最后实施 S1-09 的现行架构/历史边界说明，不做无证据代码删除。只读审查可并行，修复和子任务提交保持顺序。
- **验证/回滚**：原测试保留，逐项专项及全量测试；最终三种构建/四层 Preview 边界/实际 Preview、受测源码与提交一致性、独立父版正逆补丁和默认 CI。新目录 `../validation/S1-06-07-09-20261022-213923/` 保存证据，不替换现用 App，不安装/打包/操作真机；不 reset 工作树或移动旧标签。完整报告见 [专项验收报告](acceptance/S1-06-07-09.md)。
- **S1-06 本机结果**：独立父版合法 3 fixture 通过，非法状态 fixture 确认 Index out of range；最小 2 文件修复后 265 Swift（原 257 + 新 8）、架构/Preview 源码通过。非法范围/坏 JSON 零命令且原数据保留；合法 0…3 目标/命令顺序保持，原测试不改。S1-06 LOCAL_PASS，最终 CI 待完成。
- **状态**：S1-07/S1-09 尚未实施，G1 NOT_PASSED。三个子任务完成后提供阶段一技术门禁结果，用户确认前阶段二至四仍 LOCKED。

### 8.10 后续每个任务/阶段必填记录模板

~~~text
任务/阶段 ID：
起始/结果 SHA：
审查发现与本次单一目标：
最小实施计划 / 明确保留项：
变更文件与理由：
执行命令、退出码、用例数和证据路径：
Mock / 真机 / 历史证据的区别；硬件结果与 Mock 结果分别记录：
Mock 替代原因、具体未实测步骤、覆盖断言、残余限制和用户接受记录：
原值、实际回读与恢复结果（如涉及设备）：
遗留问题：阻断 / 非阻断 / OUT_OF_SCOPE：
回滚点与验证：
验收结论：阶段 PASS（如含已接受限制须明示）/ FAIL / BLOCKED / NOT_RUN：
核心真机 HW_PASS；例外 MOCK_PASS + HW_NOT_TESTED；不得将 Mock 记为真机通过：
用户阶段验收记录：
下一任务（仅前置门禁通过才解锁）：
~~~

## 9. 审计来源

下列仓库链接锁定本轮基线；外部文档只指导设计，不替代锁定 adb/macOS SDK 的实际验证。

- [E00：根 README / USB 硬件纠正][E00]
- [E01：master 基线提交][E01]
- [E02：Package.swift][E02]
- [E03：R3 状态与模块历史][E03]
- [E04：AdbSession][E04]
- [E05：AdbClient][E05]
- [E06：AdbPresetDevice][E06]
- [E07：AppCoordinator 生命周期与恢复][E07]
- [E08：预设与身份使用][E08]
- [E09：连接模型与入口][E09]
- [E10：R5 系统服务与私有 OSD 回退边界][E10]
- [E11：R6 构建/资源历史][E11]
- [E12：LiveRuntime 与系统事件][E12]
- [E13：Preview 布局测试][E13]
- [E14：现有 workflow][E14]
- [E15：旧 DESIGN 约束][E15]
- [E16：基线 Actions 运行][E16]
- [E17：Mac README][E17]
- [E18：控光记忆读取与数组下标][E18]
- [E19：JNI 游戏状态刷新][E19]
- [E20：R6c 收尾与未验收项][E20]
- [X01：Android 官方 ADB][X01]
- [X02：AOSP ADB CLI 说明][X02]
- [X03：Apple macOS HIG][X03]
- [X04：Apple SwiftUI Liquid Glass][X04]
- [X05：GitHub 跳过 CI][X05]

[E00]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/README.md
[E01]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/commit/52d90d6ad7a5d39939edd60a5d874311b337ae1d
[E02]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Package.swift
[E03]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/R3-ARCHITECTURE.md
[E04]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/Backend/AdbSession.swift
[E05]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/Backend/AdbClient.swift
[E06]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxMacAdapters/AdbPresetDevice.swift
[E07]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/AppCoordinator.swift
[E08]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/AppCoordinator+Presets.swift
[E09]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/AppCoordinator+Connection.swift
[E10]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/R5-SYSTEM-SERVICES.md
[E11]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/R6-RELEASE.md
[E12]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxMacAdapters/LiveRuntime.swift
[E13]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Tests/MimonitorToolboxTests/PreviewRenderingTests.swift
[E14]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/.github/workflows/macos.yml
[E15]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/DESIGN.md
[E16]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/39698075389
[E17]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/README.md
[E18]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/AppCoordinator+DisplayMemory.swift
[E19]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/Sources/ToolboxApplication/AppCoordinator+Refresh.swift
[E20]: https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/blob/52d90d6ad7a5d39939edd60a5d874311b337ae1d/macos/R6-CLOSEOUT.md
[X01]: https://developer.android.com/tools/adb
[X02]: https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md
[X03]: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
[X04]: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
[X05]: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs
