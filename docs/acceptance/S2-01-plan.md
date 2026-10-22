# S2-01 最小实施计划：有界 ADB 枚举

基线：`1222557614b2b855891b12927d4bfaf15b78cd61`。本文件只描述 S2-01 的实现与风险；执行状态以 [ROADMAP](../ROADMAP.md) 为准。

## 单一目标与边界

通过现有锁定 adb、CommandRequest/ProcessResult 和执行器，提供一次有界 `devices -l` 查询；用纯 Domain 解析器生成结构化发现快照。发现仅返回候选和诊断，不选择设备、不替换或取消当前会话、不执行 connect/disconnect、shell、helper 部署、设备写入或偏好写入。本次不接 UI，不开始 S2-02，不执行真机枚举。

## 最小修改

1. 新增 Domain 发现值：原始 serial、枚举状态（保留未知原值）、附加字段、可确认的传输类别、完整/失败原因、重复 serial 歧义及候选是否可选择。
2. 解析器设置明确的输入字节、行长和候选数量上限；要求有效 header 与完整行结构。损坏/超限/失败不伪装为完整空列表，保留可诊断原因；未知 state/附加字段不丢弃。
3. 可确定的 IPv4/ASCII hostname 加独立合法端口识别为 TCP；显式 `usb:` 字段才提供本次 USB 分类证据。缺该字段时保留 unknown，不猜 USB；emulator、mDNS、IPv6/zone 等不支持类别保留诊断且不可选择。重复 serial 不通过 `-s` 或 transport_id 消歧。
   USB 候选仅接受以 ASCII 字母/数字开头、其后为 ASCII 字母/数字或 `._-` 的完整 serial；保持大小写与前导零。其他拼写保留原值但不可选择，不将命令片段/URL 变成可选端点。该保守规则并非宣称覆盖所有硬件 serial。
4. AdbClient 新增显式 discovery API：复用既有执行器，以一次 `devices -l`、固定 timeout、现有 serverPort 与调用取消令牌返回快照。完整成功条件使用 ProcessResult.succeeded，解析只消费 stdout。枚举不会触发现有连接入口或改变 endpoint；原 TCP 会话、argv 和协议保持。
5. 本次不必让未知候选构造 AdbEndpoint；如新增 USB endpoint 值，只允许由可靠枚举结果生成，仍不开放生产接入。现有 TCP 入口不趁此进行全库校验或协议重构。

## 验证

- 使用锁定 adb 与独立本地假 server 实证 `devices -l` 的客户端请求/响应；先建立并监听隔离 socket，再执行客户端，保持正确 server version，避免客户端启动/替换 daemon；不访问现用 5038。help/version 只作客户端能力证据。
- 纯解析器覆盖 0/1/多台、USB+TCP、unauthorized/offline/未知状态、额外字段、无 usb 字段、重复 serial、错误 header/损坏行/超限、CRLF 与保留原 serial。
- 注入执行器覆盖 exit failure/超时/取消/信号/启动或 I/O 失败/截断；有效 stdout 加失败结果不能变成功。断言唯一完整 argv、timeout、serverPort、无 shell/connect/disconnect、副作用以及当前会话不变。
- 专项测试后交主代理执行原 276 Swift/24 Python、构建/Preview、保护及默认 CI；不删除或放宽旧测试。子任务提交由主代理完成。

## 风险与回滚

- 官方 adb 的普通查询可能自动启动缺失 server 或协调版本；有界枚举不等于被动读取或无 server 副作用。本次假 server 证据不能当作真实 USB/固件验收。
- libusb 可省略 `usb:`，缺字段候选暂时不可选择是保守限制；后续只有核验过的额外证据才能提升分类，不能将 token 外形当作 USB 证明。
- transport_id/USB 总线路径仅为当前快照诊断；不当作稳定身份。发现完成不表示设备 ready，未授权/离线/未知或重复候选不能产生写权限。
- 锁定 CLI 的隔离实证发现 A18：假 server 回复非法长度头 `OKAYZZZZ` 时，adb 返回 exit 0、标准空列表且无 stderr；应用无法从 ProcessResult 恢复已经丢失的信息。完整坏行仍由应用语义解析；server FAIL、声明长度后短读及执行器可见截断均拒绝成功。本次不重写 ADB 协议，不宣称覆盖 CLI 已掩盖的协议损坏。证据位于工作区 `validation/S2-01-fake-discovery-20261022-222707/REPORT.md` 与同目录 JSON/脚本；所有设备均为合成 fixture。
- 新类型/API 暂无生产调用者，回滚以新提交撤销 S2-01 文件差异；无存储迁移、设备操作或系统状态恢复。保留现用 App、偏好与密钥，由主代理执行保护和独立父版验证。

## 本项实现与专项结果

- 实际变更仅新增 `AdbDiscovery.swift`、`AdbClient+Discovery.swift` 与 `AdbDiscoveryTests.swift`；未改原端点、会话、连接入口或既有测试。枚举命令为一次 `devices -l`，进程期限 3 秒；沿用事务锁，不能插入正在执行的预设事务。输入最多 1 MiB、单行最多 4096 字节、候选最多 256 项，超限整批失败。
- Domain 分开表达枚举 state、传输证据、歧义与完整/失败；无 ready 或写权限。未知状态/字段/原行保留，重复 serial 全部不可选。`isSelectable` 仅表示允许后续显式选择，unauthorized/offline 仍不是可控状态。
- 2026-10-22 专项命令 `swift test --package-path macos --scratch-path /Users/li5ee3/Documents/Codex/ADB/validation/S2-20261022-222617/S201Agent --filter AdbDiscoveryTests`：exit 0，21 项通过，无 warning/error。全部使用纯解析或注入执行器，不启动真实 ADB/应用；完整回归由主代理记录于阶段二报告。
- 专项日志：工作区 `validation/S2-20261022-222617/S201Agent-tests.log`。锁定 CLI 8 场景的隔离证据不构成真实 USB、授权或身份验收；A18 与缺少 `usb:` 的保守限制保留。
