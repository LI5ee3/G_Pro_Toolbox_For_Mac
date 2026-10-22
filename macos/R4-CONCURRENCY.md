# R4：ADB 会话、进程边界与渐进并发迁移

> 历史范围：以下正文保留本阶段当时的实现、测试、限制与回滚记录；不代表当前源码或本轮重新验收。现行架构见 [ARCHITECTURE](../docs/ARCHITECTURE.md)，唯一进度与执行门禁见 [ROADMAP](../docs/ROADMAP.md)；旧签名/发布要求不作为当前 development 构建的完成条件。

这是 R4 完成时的阶段记录；后续登录项、Terminal、日志和生命周期改进见 [R5-SYSTEM-SERVICES.md](R5-SYSTEM-SERVICES.md)。

2026-10-21。macOS 27+ / Apple Silicon。保留现有 UI、设备端命令、音量 Binder/keyevent 回退、预设存储格式、资源与上游贡献说明。本阶段未部署到真实显示器，未替换已安装应用；R5 登录项与 R6 正式发布不在本批范围。

## 执行与隔离契约

1. MainActor 在提交时捕获不可变 `AdbSession`：client identity、目标 IP 和会话取消令牌。连接 B、重连同一 IP、断开或停止都会使旧会话失效；空目标不会落入 adb 的默认设备选择。
2. 每个工作项创建会话的子取消令牌。`BlockingExecutor.submit` 立即按 FIFO 入队，`BlockingJob.value()` 用 async/await 等待结果。`OwnedWorkSet` 持有根任务，stop 时取消并释放句柄；单项取消不取消同会话的其他工作。
3. 阻塞的设备命令留在专用队列，整项同步工作在现有递归事务锁内执行。`@TaskLocal` 上下文在队列入口显式安装，嵌套协议 helper 继承同一目标；锁和这个同步作用域都不跨 await。没有把 Process 等待搬进 actor。
4. 连接使用类型化异步结果回到 MainActor。渐进保留的同步动作通过 `publish` 发布值，同时检查原始生命周期代次和会话取消；`publishCompletion` 只处理必须完成的账务，并带原生命周期和预设 operation ID，避免旧任务清掉新任务的忙状态。
5. 事务内不再 `DispatchQueue.main.sync`。生命周期状态用 `Mutex` 保护，UI 模型继续归 MainActor / Observation。`PresetWorker` 用独立同步所有权保护 PresetEngine；只让 Sendable 配置/报告快照离开，不让 MainActor 读取正在变化的引擎。
6. Binder 验证缓存按 serial 分开。FreeSync 记忆的最新模式归 deviceQueue，持久化回 MainActor，连续开关仍能还原刚刚记住的模式。

## 进程边界

`ToolboxConcurrency` 包含纯请求、结果、取消与执行桥；真正启动进程的实现仅在 `ToolboxProcessExecution`。Preview 依赖前者，不依赖后者。

- `posix_spawn` 每次创建独立进程组；参数数组及现有 `ANDROID_ADB_SERVER_PORT` 保留，stdin 为 `/dev/null`，其他父进程描述符默认不继承。
- stdout/stderr 由单个工作线程非阻塞、公平读取，没有双线程修改 Data。使用 ContinuousClock 期限、`waitid(WNOWAIT)` 保留 PID 到清理结束，再用 `waitpid(WNOHANG)` 回收；不再无期限 `waitUntilExit()`。
- 超时/取消先发 SIGTERM，150ms 后仍未退出则升级 SIGKILL；清理循环最多额外等待 500ms。父进程退出后，继承管道的后代最多额外排空 200ms，然后清理本进程组并关闭读端。极少数尚未可回收的子进程由异步 WNOHANG reaper 回收，不留下阻塞等待线程。
- 每路最多保留 16MiB，超出后继续排空并标记截断；完整退出码、stdout、stderr、超时/取消/信号/启动或 I/O 失败分别保留。`succeeded` 不接受截断。APK/Guardian 安装同时检查进程成功和原有 Success 文本，部分输出不能冒充成功。
- 原有 shell 25 秒、install 120 秒等期限不缩短。协议层恢复/settle 等待支持合作取消；已取消的工作不再进入后续 shell、fallback 或重启 server。
- `ifconfig` / `ping` 也使用同一受限执行器，分别为 3 秒 / 2 秒。扫描保留最多四个网段、5555 端口、128 并发默认值、15 秒预算、原网段过滤与数字排序；取消/预算到期停止派发，socket poll 检查取消，结果返回锁保护快照。

这些界限约束已启动的本地命令和等待。取消不会撤回已发到显示器的命令，也不能保证设备端 JNI 同步停止。多条预设部分完成时仍沿用现有失败/回读与 applicationIncomplete 机制。内核 spawn 调用及远端执行不属于可强制回滚的事务。

用户主动打开的 Terminal 是外部交互会话，保留原来的异步 osascript 启动入口；不会因 Toolbox 停止而关闭用户终端。该入口没有同步等待子进程，不参与一次性设备工作项的进程组清理。

## Swift 6 范围

| 模块 | 语言模式与边界 |
| --- | --- |
| ToolboxDomain | Swift 6，原纯规则保持不变 |
| ToolboxConcurrency | Swift 6，新取消、执行桥与任务所有权，无系统控制 |
| ToolboxProcessExecution | Swift 6，单一 POSIX 进程资源所有者 |
| MimonitorPresetCore | 本批迁移为 Swift 6；同步引擎行为/存储不变，新增 PresetWorker 所有权 |
| ToolboxApplication / MacAdapters / UI / Preview / 宿主 | 明确保留 Swift 5 过渡模式，逐条迁移旧 AppKit/调度闭包；不是全项目 Swift 6 已完成 |

上述四个 Swift 6 模块没有 `@unchecked Sendable`。没有用全局预并发导入压掉诊断。遗留 Application 的非 Sendable 运行环境、AppKit 回调和设备工作状态仍是后续逐模块迁移边界，不能仅翻语言开关。

## 验证

本批最终 182 项测试通过：应用/适配/Preview 146，预设核心 36；原 144 项全部保留。新增覆盖硬超时、忽略 TERM、双管道大输出、持管道后代、关闭输出但不退出、关闭管道且忽略 TERM 的后代、启动失败、信号、取消/退出竞态、FIFO、取消的父子关系和任务句柄、A→B 旧结果、同 IP 重连、显式断开、stop/start、Binder 目标缓存、APK 部分成功、FreeSync 连续开关及无 socket 的扫描模拟。

两个中间并发检查点已补入 FreeSync FIFO 修复，且在隔离目录重新跑全量测试；原缺陷用红测试复现。最终 Debug/Release 原生 App 与安全 Preview 均单独构建。运行的仅为 Mock Preview，实际点击静音两次并调整音量；该时点无子进程和 Internet socket。所有页面/菜单的 NSHostingView 布局测试与静态/二进制边界检查通过。

复查命令（本目录）：

```sh
swift test
python3 scripts/validate_architecture.py
python3 scripts/validate_preview_boundary.py /path/to/ToolboxPreviewHost.app
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxApp -configuration Release -destination 'platform=macOS,arch=arm64' build
```

没有对真实设备写入，也没有重新验证真实热键拦截、唤醒、Guardian 部署、网络延迟、Developer ID、公证或 DMG 发行。单元测试/Mock 延迟不能当作真机性能测量。

## 分阶段回滚

私有引用前缀 `refs/toolbox-checkpoints/20261021/`，不改当前分支 HEAD 和真实暂存区。

| 检查点 | 内容 | 回到前阶段 |
| --- | --- | --- |
| R4-start | R3 后完整工作树基线 | R3 |
| R4a1 | 纯并发端口 + 有界 POSIX 进程执行器 | R4-start |
| R4a2 | 不可变 ADB 会话、取消与过期发布过滤 | R4a1 |
| R4b1 | async 桥、任务所有权、Core Swift 6、引擎所有权 | R4a2 |
| R4b2 | 类型化连接与移除事务内 MainActor 同步等待 | R4b1 |
| R4b3 / R4 | 网络命令收敛、APK 结构化结果、最终验证和文档 | R4b2 |

`*-before-memory-fix` / `*-before-process-fix` 只作缺陷审计，不能作为健康回滚点。健康引用均已补入进程组身份保留与后代清理测试，R4b1/R4b2 还补入 FreeSync FIFO 回归修复，并在隔离目录重新测试。

完整二进制补丁、checkpoint JSON、正反向 tree hash 验证、Git bundle、测试/构建日志和截图保存在工作区 `architecture-review/2026-10-21/implementation/`。恢复时先在空目录用 `git archive <健康引用>` 解包核对，或在独立恢复分支检查差异；不要对当前含用户历史修改的工作树运行 reset --hard。保留 R0/R3 等原检查点和 bundle。设备端已生效写入与持久化运行设置不由源码回滚自动撤销。
