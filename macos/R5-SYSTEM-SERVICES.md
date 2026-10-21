# R5：登录项、权限与系统服务

2026-10-21。承接 v2 / R4，仍为 macOS 27+、Apple Silicon。保留原界面布局和设备功能，仅为现有设置补充系统读回、错误说明和设置入口。ADB 客户端、会话、设备端协议、预设引擎与格式、JAR/APK、Bundle ID、用途声明和上游版权内容均未改写。本批未安装或运行生产包，未修改真实登录项、授权、偏好或显示器。

## 阶段与验证

| 独立阶段 | 实现与收益 | 主要风险与控制 | 当阶段验证 |
| --- | --- | --- | --- |
| R5a | `SMAppService.mainApp`；独立 systemQueue；真实状态、旧项迁移与登录启动策略 | 重复启动、误删旧项：精确归属检查、先备份、读回 enabled 后才退役旧文件；错误回读与补偿 | 204 项测试；原生 Debug；边界检查 |
| R5b | 辅助功能返回重检；tap 生命周期；Terminal 真实退出结果和权限入口 | 撤权后吞键、误报成功：撤权停 tap，授权后重新应用；osascript 30 秒与取消，拒绝/未知分别呈现 | 212 项；原生 Debug；边界检查 |
| R5c1 | 默认输出监听缓存与异步读取，按键路径只读快照 | 输出变更/晚到结果：失效立即放行，生命周期和请求代次校验，10 秒有效期 | 217 项；假输出切换、过期、释放、重复启动 |
| R5c2 | 串行日志队列、追加与原子导出、可见错误、退出排空 | 慢盘、旧错误污染新会话：元数据短锁、观察者标识、两秒退出上限 | 224 项；临时目录追加/覆盖/自导出/失败/排空 |
| R5c3 | 私有 OSD 异步故障回退；明确 start/stop | 旧失败重复弹 HUD：只回退最新且不超过 1.2 秒的请求，30 秒冷却；停止后忽略 | 229 项；假传输异步失败/旧响应/停止/冷却 |
| R5d | 安全 Preview 两个新系统场景、准确的网络诊断提示、文档与整体交付 | 预览误连真实服务：依赖图、源码效果、二进制符号与资源四层检查 | 最终 231 项；生产 Debug/Release、Preview Debug；原生模拟交互与签名资源检查 |

原有 182 项测试保留，新增 49 项。仅一项既有系统动作测试改成 async 并等待工作完成，原有断言保留。测试使用假系统端口、内存设备和临时文件；不要求用户授权或联网硬件。Swift 测试无源码警告；Xcode 构建只有未使用 AppIntents 的元数据提取提示和资源脚本每次运行说明。

## 登录项迁移契约

新注册只使用 Apple 的 [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice)，没有提权 helper 或新 daemon。状态区分 notRegistered、enabled、requiresApproval、notFound 和未知；待批准不冒充启用。开关及说明依据系统读回；从系统设置返回和主动重新检测会刷新，不会每次激活都重新注册。

旧文件仅接受当前用户所有的普通文件 `~/Library/LaunchAgents/com.mimonitor.toolbox.plist`，且 Label、RunAtLoad、Interactive、两个参数和当前 app 内的 MimonitorToolbox 可执行路径完全匹配。路径迁移、符号链接、其他键或未知归属均保留，界面提示从原安装位置或系统设置人工处理；这时应用不会代为开关，避免开发包抢占另一安装位置。

识别成功后先把原字节按 SHA256 存入 `~/Library/Application Support/MimonitorToolbox/LoginItemMigration/`。只有新服务读回 enabled 才把旧 plist 移至 retired 文件。待批准、取消或失败保留旧项；新请求必要时撤回。退役失败有补偿，不覆盖其他程序后来写入的文件，也不会在新服务仍启用时恢复旧文件造成重复。

**不会 bootout 当前旧 job**，因为该 job 可能正拥有当前主进程。已识别旧配置没有 KeepAlive 或其他触发条件，移走 plist 使下一次 GUI 登录不再加载，当前进程正常退出。备份不自动删除。参考 Apple [旧服务迁移说明](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)。

原 `--minimized` 兼容保留；SM 登录启动按当前打开应用 AppleEvent 的登录项标记进入菜单栏；普通启动和 Dock/Finder reopen 请求主窗口。窗口默认自动显示受控关闭，仍保留原关窗驻留/退出偏好。启动策略有纯规则测试，真实登录事件交付仍需签名安装环境验证。

## 系统权限的事实边界

- 辅助功能以 AXIsProcessTrusted 读回。撤权停止 event tap；返回应用重新检测并应用设置；已授权但创建 tap 失败单独呈现。停止明确释放 Mach port 和 RunLoop source。启动不主动弹授权，提示留在用户操作中。
- Terminal 只在用户明确请求时执行 AppleScript。一次性 osascript 使用 R4 可取消执行器，等待实际成功退出才报告打开；-1743 归为拒绝，其余失败/超时/取消显示未确认。界面记录“上次请求结果”，不当作全局当前 TCC 查询。已打开的用户终端不会被 Toolbox 停止关闭。
- Apple 没有通用的局域网权限状态查询 API；不把 ping/TCP 失败判为拒权。保留原用途说明和网络功能，只给出系统设置入口与诊断可能原因。依据 [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)。
- 保留本地网络和 Apple Events 用途声明、现有 automation entitlement 与身份；不添加蓝牙或额外输入监听权限要求。ad-hoc 验证不能代表正式签名的 TCC 连续性。

## 性能与生命周期

`DefaultOutputCache` 由 MainActor 管理，独立队列读取默认输出 UID/名称；读后复核默认 device ID，避免混合快照。默认设备变化、唤醒、回到应用使缓存失效，刷新完成前输出限制按未知放行。低频每 5 秒核对，10 秒后旧快照失效；同一默认设备重命名依赖低频核对，不承诺立即感知。测试验证按键读缓存不重复查询；未进行实机 Instruments 性能测量。

日志 IO 在单独串行队列完成，同一时间戳再次开启追加，完整活动日志导出先同步、复制，再原子替换目标。自导出不破坏当前文件；错误会关闭记录并反馈，避免递归写错。退出先 stop，再等队列排空，最多两秒；极慢或阻塞文件系统下不能保证全部落盘。此限时保护与普通顺序排空均需区分。

原生 OSD 的私有 wire 方法、亮度/音量/静音图像与 16 格参数保留。XPC 延迟至首次真实显示请求才创建，失败重建并冷却，回退至已有 HUD。私有接口没有显示确认 ACK；没有错误不等于系统一定显示。本批仅使用假传输验证，没有调用实际私有服务。

构造依然不启动硬件服务。start/stop 拥有输出观察、tap、通知、日志和反馈生命周期；系统操作取消令牌独立于 ADB 会话，切换显示器不会取消登录项工作。App/UI 仍处于 R4 已声明的 Swift 5 渐进边界，本批未扩大到整库 Swift 6。

## Preview 与构建

选择 `ToolboxPreviews`，Tools 页面新增“权限拒绝”“登录待批准”场景；点授权、设置、登录开关、Terminal、文件动作只记录内存动作。生产组合根/SMAppService/真实进程/输出缓存/日志/XPC 不在 Preview 依赖闭包，包内没有 adb/JAR/APK。已用原生窗口实际检查两种状态和按钮，保存 AX 文本及截图；该交互时点没有子进程或网络 socket。此观察与依赖隔离共同构成证据，不代替真机验收。

```sh
swift test
python3 scripts/validate_architecture.py
python3 scripts/validate_preview_boundary.py
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Toolbox.xcodeproj -scheme ToolboxApp -configuration Release -destination 'platform=macOS,arch=arm64' build
```

本机已验证生产 Debug/Release 和 Preview Debug：arm64、最低 27.0、ad-hoc deep/strict 签名；生产 adb 也为 arm64，运行时 JAR/APK/NOTICE 与源资源逐字节一致。未构建或发布 DMG。正式 Developer ID、公证、干净机器升级与真实系统权限连续性属于 R6。

## 回滚与待验收

使用临时 index 保存每阶段完整树，不改原 HEAD 或真实暂存区。引用前缀为 `refs/toolbox-checkpoints/20261021/`：R5-start、R5a、R5b、R5c1、R5c2、R5c3、R5d，R5 指向最终 R5d。阶段依赖从后往前回滚；补丁在临时 index 正反应用比对父/子完整树哈希。

推荐隔离查看：`git worktree add --detach <新目录> refs/toolbox-checkpoints/20261021/R5b`。不要对现有脏工作树 reset。代码回滚不撤销系统注册/TCC；真实迁移后应先停用现代登录项，再经归属检查恢复备份旧文件，不能同时启用两种启动方式。

日志、截图、校验 JSON、各阶段二进制 patch、Git bundle 位于工作区 `architecture-review/2026-10-21/implementation/`。后续签名安装验收需覆盖首次/待批准/拒绝登录项、旧版本升级、退出/注销登录/重启、移动安装位置、AX 撤权与重新授权、真实 Terminal 拒绝、输出切换/唤醒/按键，以及 Instruments；这些系统实测尚未执行。本批保留上述可验证边界，不以单元测试冒充真实系统许可或显示器回读。
