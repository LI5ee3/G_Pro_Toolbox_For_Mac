# G Pro ToolBox 最终开发路线图

> 唯一项目进度基准。创建于 2026-10-22（UTC+8）。
> 当前结论：远端现状审计与四阶段计划已建立；本轮仅提交本文件。阶段一尚未通过验收，阶段二至四锁定。
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

### 1.2 锁定的远端基线

| 项目 | 审计结果 |
| --- | --- |
| 仓库 | LI5ee3/G_Pro_Toolbox_For_Mac，默认分支 master |
| master | [52d90d6ad7a5d39939edd60a5d874311b337ae1d][E01] |
| R6c 回滚标签 | refactor/20261022/R6c → fc231b607aaa03c82e94cb1292b513a44c62c019 |
| 两者关系 | 逐路径/blob 比较：master 相比 R6c 仅 README.md、macos/README.md 不同；没有新增、删除或变化的业务源码。master 包含 USB 硬件纠正说明 |
| 历史回滚 | 远端实际存在 R0、R1、R2a/b、R3、R4、R5、R6、R6c 及细分 refactor 标签；保留，不移动旧标签 |
| 工具链记录 | R6c 记载 Mac mini M4、macOS 27.0.1、Xcode 27.1；新执行时在开发 Mac 重新记录实际版本 |
| 当前文档范围 | 本次只新增 docs/ROADMAP.md；不修改其他文档、源码、资源、workflow 或安装状态 |

下次实施前复核 master HEAD；若变化，先记录新 SHA 与差异并重新确认受影响任务，不能把移动分支当作固定测试基线。R6c 是历史检查点，不等于本轮已经完成。

### 1.3 执行规则

1. 四阶段严格串行：每阶段先审查，明确计划，再逐个实施；每个子任务只有一个可验证目标。
2. 稳定机制默认保留。任何替换必须写明原问题、收益、最小差异和测试证据；不为了文件大小、命名或语言模式统一重写。
3. 每阶段结束必须报告变更清单、测试证据、遗留风险和验收结论。用户确认该阶段通过后才解锁下一阶段。
4. 本轮仅允许远端读取和路线图上传；没有 clone、pull、archive 解包或在本地保存仓库源码，没有执行 Swift/Xcode、真实 ADB 或硬件操作。
5. 后续构建使用独立新输出目录。不得默认生成 DMG、运行 reinstall.sh、覆盖现用 App、重绑权限、清理偏好或重置 adb 密钥。
6. 高风险真机写入须事前获得用户对具体操作、目标、原值及恢复方案的明确批准；测试清单中的勾选框不构成操作授权。
7. 普通读连接也可能触发现有自动任务、记忆恢复和 ensureJars 写入。真机只读检查须先识别这些副作用，使用独立只读探针；不能仅因方法名是 connect 就称为“只读”。
8. 本次文档提交使用 [skip ci]：现有 push 工作流会构建 DMG/ZIP，不能因上传计划触发默认打包。[GitHub 跳过工作流说明][X05]。此标记仅用于本次文档提交，不免除未来源码检查。

## 2. 证据等级与现状审计

### 2.1 本轮查阅覆盖和验证限制

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

优先级：B = 当前目标的阶段阻断项；R = 需复现并按影响判定的可靠性风险；N = 可记录的非阻断维护项。下表源码位置均固定到基线，风险项不冒称已经在真机复现。

| ID / 级别 | 直接证据与影响 | 计划 |
| --- | --- | --- |
| A01 / B | AdbSession.targetIP / serial、AdbClient.activeIP/connect/disconnect 固定 TCP 5555；不能直接塞 USB serial。[E04][E05] | S1-03/04 统一目标，S2-02 USB 生命周期 |
| A02 / B | AdbPresetDevice 用 identity:5555，协调器以 adb.ip 判断基线、自动任务和活动预设；传输地址与物理设备身份混用。[E06][E08] | S1-03 明确身份契约；S2-04 迁移/别名与跨传输防错 |
| A03 / B | ensureConnected/restartServer 恢复可 kill-server；共享 5038 同时承载 USB/TCP，网络故障可能打断 USB。unauthorized 退出 wait 后仍可能进入后续恢复路径。[E05] | S1-05 明确 server 所有权、健康和恢复策略；S2-02/06 实现传输区分与故障注入 |
| A04 / R | isServerAlive 调用 adb version；该命令只能证明客户端可运行，不能可靠证明 server 响应。[E05][X02] | S1-05 以假执行器覆盖“客户端在/server 不在”，选锁定 adb 已支持的 server 探测；先实查 help/行为 |
| A05 / B | ConnectionStatus 仅四态，连接与扫描列表以 IP/String 表达；缺少 USB 枚举、授权、设备离线/歧义等结构化状态。[E09] | S1-03/04 状态契约，S2-01/03 发现与呈现 |
| A06 / R | local_dimming_memory 解码为任意 Int 字典，随后直接作四元素数组下标；负数或 ≥4 的损坏偏好有越界风险。[E18] | S1-06 用内存偏好复现后最小校验，保留原字节、不静默写回 |
| A07 / R | applyGameJniMode 将缺失/无效 JNI 值与预期枚举比较后写成 0；读取失败可能被显示为确定“关闭”。[E19] | S1-07 假失败回归；区分未知和关闭，不改有效值映射 |
| A08 / R | 部分 legacy shell 返回 String 且不以 exitCode 判成功；部分普通设置先乐观更新。checkedShell/预设已有更严格路径。[E05][E06] | S1-02 列调用点和已有语义；若复现误报，仅修具体调用，不能整库改抛错/改协议 |
| A09 / B | 唤醒/轮询从 saved_ip 恢复；Live 只订阅 didWake/screensDidWake，USB 插拔/睡眠中任务语义未定义。[E07][E12] | S2-06；取消旧会话、防旧读数、重枚举并回读，避免重放非幂等写 |
| A10 / B | Preview 当前六种场景，无 USB/双连接/授权等待；布局测试主要断言 fittingSize > 0，不能证明无裁切、键盘可用或深色对比度。[E13] | S2-03/08、S3-07/08 补场景与视觉/交互证据 |
| A11 / B | DESIGN.md 仍写“不新增 USB”、蓝牙操作、macOS 26 回退；当前代码已 ADB-only/macOS 27。README 与旧 R6 发布门槛也需按最终范围统一。[E15] | 本文件范围优先；S1-09 与 S3-01、S4-05 更新现行说明，保留历史事实 |
| A12 / B | master push workflow 默认 make_dmg；还有 distribution/notary/release job；reinstall.sh 会退出进程、删除/替换应用并可能重启 Dock。[E14] | 本轮 skip CI；S1-08 计划/实现默认验证与打包解耦，安装脚本不进验收命令 |
| A13 / N | NativeOSD 仍使用私有 XPC 兼容路径；已有过期保护、冷却和 HUD 回退。[E10] | 保留已验证行为，不再扩大私有 API；验收 HUD 必须可用，私有 OSD 限制单独登记 |
| A14 / N | Application 仍依赖 AppKit、保留状态转发属性、部分大动作文件；这不自动证明架构失效 | 仅删除可证明无引用的代码；不因“纯化”拆空模块/重建协调器 |
| A15 / N | Guardian 源码路径不可复现，整体/图标许可未确认；资源摘要与 NOTICE 已锁定。[E11] | 保留来源和致谢；本轮私人本地交付不以公开再分发审批为阻断，若以后公开发布需另行处理 |
| A16 / R | 设备侧 helper 使用固定 batch/ramp 结果文件；应用内锁不覆盖另一个 Toolbox/Terminal 进程。Guardian 在配置异常时可能重启 adbd，影响两种传输 | S2-05/06 复核共享设备端资源与 Guardian 恢复影响；真机测试隔离其他写入者，不声称应用事务锁是全设备锁 |

### 2.5 历史已验证与本轮仍缺证据

| 范围 | 历史记录 H | 本轮 / 最终状态 |
| --- | --- | --- |
| 自动测试 | R6c：233 Swift、24 脚本测试通过 | 本轮仅核对定义数；未来每个代码提交须在 Mac 重跑相关与全量门禁 |
| 原生构建/资源 | R6c：App Debug/Release、Preview Debug、arm64/minOS、ad-hoc、资源一致性；DMG/ZIP 回读 | 本轮未构建；最终只要求独立 App 和证据包，不默认 DMG |
| 媒体键/音量 | R6c：音量加/减/静音 USB 独立回读、默认 Mi Monitor 输出 | 不等于应用已有 USB 选择；新 USB/TCP 都要回归 |
| 窗口/退出/日志 | R6c：关窗驻留、重开同 PID、日志导出和退出落盘 | 新版须复验生命周期不泄漏 |
| 真实睡眠/登录/重启 | R6c 明确本轮未做；更早文档有网络唤醒经验 | 最终仍为 PENDING，不能按自动恢复模拟测试豁免 |
| 输出切换/OSD 故障 | 注入测试；真实异常未主动制造 | 普通真实输出门控需补测；危险/不可控系统故障用注入证据并说明限制 |
| 性能 | R6c 两段约 20 秒 Instruments，未记录 >250ms 卡顿；非延迟上界/提速结论 | 新版同条件观察，不编造相对性能数字 |

## 3. 最终 ADB 设计约束（计划，尚未实现）

### 3.1 最小演进方向

在原 Domain / Application / MacAdapters 内增量实现；暂不新增独立仓库、直接 libusb/IOKit 驱动、网络服务或新后台 helper。

概念契约如下，名称是设计建议，实施前对照实际现有 API 确认，不把它们当作已存在接口：

| 概念 | 必须承载的内容 |
| --- | --- |
| 连接偏好 | 手动 USB / 手动 TCP；手动功能验收后才解锁用户主动选择的 Auto（USB 优先） |
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
- unauthorized 等待用户授权，不反复 kill-server；USB 拔线不进入 TCP IP 扫描；TCP 故障不重启健康 USB 会话。server 级故障恢复须重新验证所有受影响会话。
- Auto 仅在手动 USB/TCP 的 Mock 与真机验收完成后提供；默认保持旧 TCP。用户主动启用后，先选择已确认同机且 ready 的 USB，否则尝试该设备已有 TCP 配置。
- 正在执行的写入/预设不能跨传输自动重放；先标记中断/不完整、回读，再决定是否重试。静音 toggle、信号源切换、APK 安装等尤其不能盲重试。
- USB 重插、网络恢复、设备/屏幕唤醒必须合并和限流，避免传输来回切换；具体退避/稳定窗口通过锁定设备测量与测试确定后记录。
- 不自动执行 adb usb/tcpip、USB 路由寄存器、重启显示器或恢复出厂，不用改设备模式“修复”连通性。

## 4. 四阶段任务与验收门禁

任务状态：DONE_REMOTE = 本轮远端审计已完成；READY = 计划就绪；TODO = 待实施；LOCKED = 前置阶段未验收；PASS = 有执行证据且阶段已确认；FAIL/BLOCKED = 必须保留原因与下一步。未运行项目必须记 NOT_RUN，不能勾为通过。

每个任务均遵循“复核当前源码 → 写本任务最小变更计划/风险 → 实施 → 验证 → 记录”。不并行实施多个任务；发现新问题先登记，不能顺手扩大范围。

### 阶段一：架构整理

入口：本路线图发布；实施前在开发 Mac 复核 HEAD、工作树和现用应用保护边界。
目的：使现有 TCP 架构能安全承接 USB，补齐可证明的可靠性问题，不重做 R0–R6c。

| ID | 单一子任务 / 交付 | 验证标准 | 初始状态 |
| --- | --- | --- | --- |
| S1-01 | 远端现状审计、范围与证据登记 | SHA、R6c blob 比对、全模块与现有门禁映射可追溯 | DONE_REMOTE |
| S1-02 | 开发 Mac 重新建立未改动基线，并逐个复核风险 | 233/24 实际执行日志、三种构建/边界结果、现用 App/配置保护清单；失败先诊断 | READY |
| S1-03 | 输出统一端点/身份/状态与旧配置兼容设计 | 覆盖 USB/TCP、歧义、身份未知、旧 IP、会话失效；记录决策和不改的协议 | TODO |
| S1-04 | 最小替换 IP-only 会话契约，先迁移 TCP 路径 | TCP argv/命令顺序与旧行为一致；空端点、同址重连、A→B、预设固定目标测试通过；尚不开放 USB 发现 | TODO |
| S1-05 | 收敛 server 健康检测与恢复决策边界 | 客户端存在/server 不在、unauthorized、冷却、取消的注入测试；不改变有效设备协议 | TODO |
| S1-06 | 复现并修复非法控光记忆范围风险 | -1、4、极端 Int、错误 JSON 不崩溃且不向设备下发；有效 0…3 行为保持 | TODO |
| S1-07 | 复现并修复 JNI 缺失被当作关闭 | failed/空/无效值呈未知；合法 320Hz/FreeSync 枚举和映射保持 | TODO |
| S1-08 | 默认检查/本地 App 交付与打包发行解耦 | 默认执行不生成 DMG、不安装、不用 Developer ID；旧打包仅显式调用；workflow/脚本检查通过 | TODO |
| S1-09 | 更新现行架构说明和必要遗留清理记录 | 依赖/所有权/Swift 模式/目标设计与源码一致；每个删除项有无引用证据；更新本表 | TODO |

A08 若测试确认有误报，另建单一 S1 任务后再修；不能把它混进会话改造。无需删除全部历史发布脚本；应隔离默认路径并消除现行文档的错误阻断条件。

**G1 通过条件：**

- [ ] S1 全部必需任务完成；已有 233 Swift/24 脚本断言保留，必要新增用例通过；删除/调整测试必须说明理由，不能降低门槛。
- [ ] App Debug/Release、Preview Debug 在 arm64/macOS 27+ 成功；模块无环、9 模型所有权、Preview 静态/二进制/资源边界通过。
- [ ] TCP 固定目标、取消/超时、FIFO、预设身份与存储兼容没有回归；没有无收益重写或全库 Swift 模式强切。
- [ ] 架构文档、最小调整理由、差异清单、风险及回滚点齐全；未替换现用 App。
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
| S2-07 | 手动模式真机验收子门禁 M2 | 开发 Mac 上 USB、TCP、同机双在线、授权与拔插/恢复证据；具体写入按批准执行并回读恢复 | LOCKED |
| S2-08 | 基于 M2 结果设计并实现可选择的 Auto | M2 明确通过后才实施；仅已绑定同机回退、无抖动、手动断开抑制、不跨端点重放 | LOCKED |
| S2-09 | Auto 真机与完整阶段回归 | USB 优先、USB 失效回退、USB 恢复、两台歧义、任务中断、睡眠恢复均有可复核证据 | LOCKED |
| S2-10 | 连接/排障/配置迁移文档及报告 | 明确 USB 线材、授权、逻辑断开、TCP 保留、已测固件、回滚限制 | LOCKED |

**G2 通过条件：**

- [ ] M2 和 Auto 都有真实证据，不以“adb 命令可用”代替应用端到端验收；Auto 不在旧用户升级时默认启用。
- [ ] 所有现有控制入口经同一会话工作；同机双连接不双写，不向异机还原预设，旧网络配置/基线/快捷键保留。
- [ ] 授权、插拔、断线、改目标、取消、睡眠唤醒、stop/start 的矩阵全部通过；USB 健康会话不被普通 TCP 故障重启。
- [ ] 全量测试、构建和 Preview 隔离通过，文档及阶段回滚点完整，用户确认阶段通过。
- [ ] 未获批准或未能完成的必需真机项保留 BLOCKED/NOT_RUN，不能包装成非阻断事项。当前 G2 = LOCKED。

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
| S4-02 | 全量自动化、原生构建和边界检查 | 第 5 节命令全部有日志/退出码；不默认打包或安装 | LOCKED |
| S4-03 | USB/TCP/Auto 和现有功能真机矩阵 | 第 6 节逐项证据、双传输等价回读、测试后恢复；拒绝只看 UI 推断成功 | LOCKED |
| S4-04 | 登录、重启、睡眠/唤醒与长期运行回归 | 用户安排窗口；关窗驻留/退出、真实下一次登录菜单栏、重启恢复、输出门控、自动任务恢复均验证 | LOCKED |
| S4-05 | 现行文档和历史文档收口 | 架构/使用/开发说明一致；旧阶段记录标明历史，不删除 R0–R6c 证据；清除当前说明中的过期阻断 | LOCKED |
| S4-06 | 本地独立交付物与可重复构建 | 版本化 .app、摘要/验证 JSON、资源 NOTICE、日志与重建步骤；相同锁/工具链重复构建核对 | LOCKED |
| S4-07 | Git/配置/二进制回滚演练 | 独立恢复目录构建和验证；保留原 App，源码/用户配置/系统权限/设备状态分开恢复 | LOCKED |
| S4-08 | 最终验收签字、记录非阻断项并冻结功能 | G4 全部通过后标 COMPLETE；保留最终不可变引用，不自动创建 Release 或开启新功能 | LOCKED |

**G4 / 项目完成条件：**

- [ ] G1、G2、G3 已有验收报告与用户确认。
- [ ] 所有必需自动/真机用例 PASS；未执行不能算通过；无未解决的崩溃、错设备写入、数据损坏、生命周期或必需恢复阻断。
- [ ] 有限的非阻断项写明影响、证据、原因和用户接受记录；Developer ID/公证/公开分发/Intel/Windows 为 OUT_OF_SCOPE。
- [ ] 开发 .app 与源码/配置备份、回滚点、资源摘要、工具链和验收证据可定位，现用正常版本仍受保护。
- [ ] 用户确认最终验收通过；将本文件状态置 COMPLETE、冻结功能范围并结束本轮。未通过时保持开发未完成，不能按计划写了多少或测试数量多就结项。

## 5. 可重复检查基准（未来在开发 Mac 执行）

本节为执行清单，本轮全部 NOT_RUN。以 macos 目录为工作目录，先记录 git HEAD/工作树、sw_vers、uname -m、xcodebuild -version、swift --version 和 SDK 版本。

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
- 新增 USB 测试使用内存设备/假命令，不默认连真机、不要求 RSA/TCC 授权。
- 可重复构建指从固定源码/资源锁和记录工具链重建可验证 App；若 UUID/签名/时间导致文件哈希不同，报告差异并核对代码、配置和资源，不能未经证明宣称逐字节可复现。

## 6. 真机验收矩阵与批准边界

每条证据记录：用例 ID、日期/时区、源码 SHA、App 版本/路径、Mac/系统、显示器型号/固件、adb/server/选定端点、操作前值、预期、实际回读、恢复后值、日志/截图位置、PASS/FAIL/NOT_RUN、操作者。serial/IP 在公开材料中按必要程度脱敏；不提交密钥和偏好数据库。

### 6.1 连接与生命周期

| 用例 | 场景 | 必须观察的结果 | 当前 |
| --- | --- | --- | --- |
| HW-C01 | 无设备、单 USB、单 TCP | 候选/状态准确；只有明确选定且探活成功才 ready | NOT_RUN |
| HW-C02 | 首次 USB 未授权、用户同意/拒绝或不操作 | 待授权可解释且可退出；不伪成功、不循环重启、不删密钥；已有受信任设备不得为测试擅自撤销授权 | NOT_RUN |
| HW-C03 | USB 拔出/重插与逻辑断开 | 旧写入停止派发，缓存未知，显式断开后不抢回；接回重枚举同机 | NOT_RUN |
| HW-C04 | 同机 USB+TCP 双在线 | 手动选择可预测，仅单活动会话；身份/预设基线一致 | NOT_RUN |
| HW-C05 | 两台或同型/未知设备，USB/TCP 身份冲突 | 不选第一台、不按型号合并、不向错机恢复 | NOT_RUN |
| HW-C06 | TCP 故障且 USB 健康，反向故障 | 局部恢复；未受影响传输不被无故 kill-server | NOT_RUN |
| HW-C07 | 操作中切 USB↔TCP / A↔B、同目标重连 | 旧回调无效，不跨端点续写事务或重复 toggle，busy 最终释放 | NOT_RUN |
| HW-C08 | Auto：USB 优先、回退、USB 恢复、反复抖动 | 仅绑定同机，稳定窗口有效，不重放写入，手动断开抑制 | NOT_RUN |
| HW-C09 | Mac 睡眠/唤醒、显示器休眠/恢复 | 两个唤醒通知合并，重新探活/回读，任务恢复遵循当前时段 | NOT_RUN |
| HW-C10 | 关闭窗口、重开、退出/重开、真实登录与重启 | 驻留/退出偏好正确、登录菜单栏、无重复观察者/任务/进程 | NOT_RUN |
| HW-C11 | server 不可用/重启、端口被占用 | 故障原因明确、有限恢复，重新枚举目标；不扰动用户其他 ADB server | NOT_RUN |

重复性门槛：USB 拔插至少 5 次；手动传输切换至少 5 轮；USB、TCP、Auto 各至少 3 次睡眠/唤醒；至少一次真实注销登录和一次 Mac 重启；至少 30 分钟混合使用观察任务/句柄/日志无持续增长。记录恢复耗时，门槛在 S2 审查时结合原有 25/120 秒等超时制定，不凭空缩短超时，也不把短样本当作稳定性上界。

### 6.2 现有功能等价回归

| 用例 | 功能与证据 | USB / TCP 要求 |
| --- | --- | --- |
| HW-F01 | 首页音量加/减、绝对值、静音/解除、连按和回读 | 都验证；保持 Binder 首次验证及 keyevent 回退、输出门控、HUD/OSD |
| HW-F02 | 画面/背光、色温/增益、HDR/SDR 记忆、游戏状态读数 | 授权范围内写/回读/恢复；未知值不作确定状态 |
| HW-F03 | 信号源、灯光、遥控和游戏功能入口 | 所有入口路由一致；可能黑屏/待机/信号变化的写入先批准 |
| HW-F04 | 预设新建/保存/应用/返回基线、失败/中断 | 不覆盖原基线；部分失败保留 applicationIncomplete；跨传输同机和异机保护 |
| HW-F05 | 自动任务开始/结束/重叠/跨日/错过时段/离线恢复 | 返回正确原预设，失效窗口不迟到执行，不重复下发 |
| HW-F06 | 菜单栏、自定义热键、亮度/媒体键、音频输出切换 | 默认目标匹配才拦截，撤权/未知输出安全放行，关窗仍可用 |
| HW-F07 | 工具：诊断、日志、Terminal、Guardian/APK/4K UI 路径 | 安全项真机；高风险部署/改分辨率等分项批准，失败如实反馈 |
| HW-F08 | 深浅色、缩放、弹层错误、键盘/VoiceOver | Preview 全矩阵加真实 App 抽查，无新布局/响应回归 |

真机验证分层：

- 首先做只读设备发现/型号/状态/参数探针，确认地址与身份。生产连接可能自动部署 JAR、触发预设或记忆写入，因此不自动运行现用实例之外的新生产 App。
- 音量、背光和画面设置等写入先记录原值，在明确的测试范围内执行，完成后回读恢复。不能认为“可恢复”就无限扩大测试。
- EDID/320Hz、FreeSync、信号源、4K UI、USB 路由/寄存器、重启/待机/电源、APK/Guardian 部署、清授权或覆盖应用等影响真实状态的操作单独列计划，按用户规则获得明确批准。
- 没有批准的项目只做 Mock/命令契约和只读检测并记 NOT_RUN/BLOCKED；若它是必需验收项，G4 不能通过。确需缩小范围由用户明确变更本路线图。
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
| 本轮现状审计与路线图 | 完成远端审计及计划编写；提交后以 Git 历史确认上传 | 固定 SHA、全树/blob、模块与风险、验收矩阵；无源码改动 |
| 阶段一 | 审计完成，计划就绪，实施未开始；G1 NOT_PASSED | 下一任务 S1-02，需要开发 Mac 上重新建立运行基线 |
| 阶段二 | LOCKED | G1 未验收；USB 硬件历史成功不等于应用实现 |
| 阶段三 | LOCKED | G2 未验收；oil UI Pro 已在用户开发 Mac |
| 阶段四 | LOCKED | G3 未验收；真实睡眠/登录/重启及最终交付均待执行 |
| 项目结项 | NOT_COMPLETE | 不以路线图上传作为完成开发 |

### 8.2 本轮文档交付报告

- **变更清单**：仅新增 docs/ROADMAP.md；将本轮范围、审计事实、风险、四阶段任务、验收门槛、真机边界及回滚规则集中为唯一进度基准。
- **验证证据**：固定远端 master/R6c 对比仅两份 README 不同；10 模块/85 Swift 源文件、233 Swift 和24 脚本测试定义核对；文档上传后检查提交父节点、单文件 diff、完整内容回读和 master 指向。
- **未执行**：Swift/Python 测试、Xcode/Preview 构建、CI、真机控制、权限变更、安装覆盖、DMG/ZIP 打包、正式发布。
- **遗留风险**：第 2.4 节全部待后续处理；历史本机证据和当前开发 Mac 环境未独立复验；当前阶段没有通过运行验收。
- **下一步**：用户后续启动阶段一时，从 S1-02 开始；当前不自动实施架构或 USB 代码。

### 8.3 后续每个任务/阶段必填记录模板

~~~text
任务/阶段 ID：
起始/结果 SHA：
审查发现与本次单一目标：
最小实施计划 / 明确保留项：
变更文件与理由：
执行命令、退出码、用例数和证据路径：
Mock / 真机 / 历史证据的区别：
原值、实际回读与恢复结果（如涉及设备）：
遗留问题：阻断 / 非阻断 / OUT_OF_SCOPE：
回滚点与验证：
验收结论：PASS / FAIL / BLOCKED / NOT_RUN：
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
