# S2-02 最小实施计划：USB 选择与严格只读就绪验证

基线：`e55ab8c`（S2-01 已通过）。执行状态以 [ROADMAP](../ROADMAP.md) 为准；本项不开放 S2-03 UI，不实现身份绑定、控制入口或 Auto。

## 最小范围与顺序

1. 扩展不可变 `AdbEndpoint` 的 USB 传输和 `isUSB` 判定，保留 TCP host 字节、默认端口及旧 argv。USB serial 只能来自完整枚举中的明确候选，不接受手工拼接端点。
2. 新增 `validateUSBSelection(serial:)`：在现有同步事务与取消上下文内重新完整枚举，按原始 serial 在全部候选中精确匹配且必须唯一；只返回候选端点与结构化就绪结果，不改变活动会话或偏好。
3. 只有用户选定的唯一 unknown 候选可以补充一次有界 `-s SERIAL get-devpath`；严格成功、完整 stdout 为 `usb:` 加非空路径才建立 USB 类型证据。unknown、裸路径、失败、截断及未知/不支持状态均不探 shell。不得批量探测全部候选、按 token 外形猜 USB 或以 transport_id 消歧。
4. USB unauthorized/offline 保持非 ready；device 仍须指定 serial 的成功 get-state 和精确只读 marker。USB connect/disconnect 不发送 TCP 命令，ensureConnected 的 USB 分支不进入 TCP 重连或 host-features 恢复。
5. 收紧现有 deviceState/transportWorks 的 readiness：检查 ProcessResult.succeeded 与 stdout 精确值，保留 unauthorized 原始诊断；不改通用 legacy shell 或扫描协议，不改变原 TCP argv、顺序、超时和 server 恢复策略。
6. 主代理仅添加 coordinator 防误回落边界和逻辑断开测试；本项新 USB 验证不接已有 connect 成功回调、helper 部署、HDR 记忆或自动任务链路。

## 验证

- 新测试使用注入执行器；逐项断言完整 argv、超时、serverPort、拒绝后的零后续命令，覆盖 fresh 选择、重复/消失/未知、授权等待、离线、失败/截断/取消、同目标与跨目标切换、逻辑断开。
- readiness 测试覆盖非零退出但含 marker/device、stderr-only、夹杂文本、超时/信号/启动失败/I/O 失败/截断，严格拒绝误判成功。
- 保留 TCPCompatibilityTests、ServerRecoveryTests、AdbEndpointTests、AdbSessionTests、旧配置与预设测试的原断言；只添加新测试。
- 以独立 S202Agent scratch 编译运行专项；主代理另做全量、架构与 Preview 检查。
- 将锁定 adb `37.0.1-15733141` 的 get-devpath 隔离假 server 脚本、请求/响应 JSON 和 primary source 链接保存到工作区 validation。本证据不访问生产 server/真机，不运行生产 App，不安装或打包。

## 已知限制与回滚

- get-devpath 只反映 server 的现有 devpath；真实 libusb 若两处均无 USB 证据，仍不可选择。假 server 不证明真实 backend/固件行为，M2 必须另行验证，不能以 Mock 豁免。
- 完整枚举与后续命令之间仍可能发生物理插拔；每次验证均重新枚举，后续失败关闭，不宣称跨进程的原子设备锁。端点与成功探活不等于物理身份或业务写权限。
- 官方 adb 普通查询仍可能启动缺失 server 或协调版本；本项不新增显式 server 重启，不把端口当独占凭证。S2-01 的 A18 CLI 信息丢失限制继续保留。
- 新 backend 结果只供后续显式选择使用，当前不连接生产 USB UI。失败/取消不覆盖活动端点、不保存配置；逻辑断开与后续接入的 generation 检查由 coordinator 保证。
- 回滚撤销本项新提交即可恢复 S2-01；无存储迁移、安装、真机写入或授权更改。保留原业务命令映射及历史测试。

## 专项执行结果

- 实现已冻结：Domain 新增 USB endpoint 与 `AdbUSBSelectionResult`/`AdbUSBReadiness`；backend 新增只读 `validateUSBSelection(serial:)`。结果保留可验证端点和 ready/待授权/离线/缺失/歧义/不支持/枚举失败/探活失败/取消状态；不激活会话或写偏好。`isUSB` 供 coordinator 防止 legacy saved_ip 将 USB 误改成 TCP。
- 已知 USB 的成功轨迹严格为 `devices -l`（3 秒）→ `-s SERIAL get-state`（3 秒）→ `-s SERIAL shell echo __mimonitor_probe__`（25 秒）；唯一 unknown 候选只在其后附加一次 `get-devpath`（3 秒），获得明确证据后才探活。每次 USB ensureConnected 都重验完整枚举，不复用旧 ready 结果绕过重复/消失检查。
- 2026-10-22 独立 scratch 专项及兼容命令：`swift test --package-path macos --scratch-path /Users/li5ee3/Documents/Codex/ADB/validation/S2-20261022-222617/S202Agent --filter 'USBSelectionTests|ReadinessTests|TCPCompatibilityTests|TCPLegacyConfigurationTests|ServerRecoveryTests|AdbEndpointTests|AdbSessionTests|AdbClientTests'`，exit 0，**69 项通过、0 失败，无 warning/error**。其中新增 USBSelectionTests 23 项、ReadinessTests 5 项；其余为原兼容断言。日志为工作区 `validation/S2-20261022-222617/S202Agent-tests.log`。
- 完整覆盖包含逐阶段取消、同目标/跨目标替换、在途事务不插队、当前 TCP 会话验证 USB 后 endpoint/token 不变、256 候选时只补查选定一台、unknown/裸路径/坏输出及进程失败拒绝、USB 失败不进入 TCP/server 恢复。已有测试文件与原断言未修改。只读独立复核未发现阻塞问题；`git diff --check` 通过。
- 锁定 adb 的 **6 项 get-devpath 隔离实验 PASS**，可复跑脚本、原始请求/响应 JSON、执行日志与 primary 链接保存于工作区 `validation/S2-02-fake-devpath-20261022/`（`locked_get_devpath.py`、`locked-get-devpath.json`、`execution.log`、`REPORT.md`）。unknown、裸路径和空输出均可能是 exit 0，因此必须单独核对类型证据。该证据不构成真实 libusb 或 M2 验收。
- 此处仅记录子代理 Domain/backend 与专项结果；coordinator 边界、全量回归、父版反证、架构/Preview、提交与推送由主代理在阶段报告登记。未运行生产 App、未访问真实 ADB server/设备、未安装或打包，未开始 S2-03。
