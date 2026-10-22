# R6：构建、签名和发布门禁

> 历史范围：以下正文保留本阶段当时的实现、测试、限制与回滚记录；不代表当前源码或本轮重新验收。现行架构见 [ARCHITECTURE](../docs/ARCHITECTURE.md)，唯一进度与执行门禁见 [ROADMAP](../docs/ROADMAP.md)；旧签名/发布要求不作为当前 development 构建的完成条件。

后续已完成开发包本机安装与 R6c 非注销/重启回归，网络权限入口的实际定位边界及回滚说明见 [R6-CLOSEOUT.md](R6-CLOSEOUT.md)。以下保留 R6 原阶段的交付记录。

2026-10-22。v2 R6a 已完成本机验证；R6b 的正式签名/公证流程已实现并完成失败路径测试，**实际正式分发尚未完成**，需要 Developer ID、公证凭据和签名安装环境验收。没有运行新生产应用、安装替换、修改 TCC/登录项、触发真实 ADB 或推送远端发布。

## 阶段和回滚边界

| 阶段 | 收益 / 影响 | 风险控制 | 验证 |
| --- | --- | --- | --- |
| R6a1 | 统一 Xcode 资源入口；版本、摘要及 NOTICE 成对锁定 | 资源缺失/变更即失败；显式联网 prepare，构建和 Preview 不下载；缓存原件不改 | 6 项资源测试、官方固定版本 ZIP 与已有 adb/NOTICE 摘要核对 |
| R6a2 | CLI 构建统一使用原生 Release App Target；共享 Info/entitlements，独立目录发布 | development / local / distribution 显式分离；固定身份失败不降级；Hardened Runtime；已有目录拒绝覆盖 | 13 项资源/签名规则测试；实际原生 Release 构建及二进制/签名门禁 |
| R6a3 | DMG/ZIP 完整回读、清理、原子发布 | 只读挂载；Applications 目标验证；签名后所有字节/权限/链接一致；失败非零，不产生成功输出 | 6 项封装/公证拒绝/清理测试；真实开发 DMG、ZIP 及完整回读 |
| R6b-ready | Developer ID / timestamp / 公证 / staple / Gatekeeper；CI 凭据与发布分离；版权说明入包 | 无凭据不产正式包；专用临时钥匙串、无系统 trustRoot 或登录钥匙串导出；失败清理；正式包仅可进草稿发布 | 最终 24 项脚本测试、231 项既有 Swift 测试；7 类真实故障检查；Debug/Release/Preview 构建。真实签名公证待凭据 |

新代码只修改构建/发布脚本、工程 Release Hardened Runtime 配置和文档/致谢资源。所有 Swift 源码、既有 Swift 测试、ADB 协议、预设与原设备资源字节保留。原主分支 HEAD 和真实暂存区不动；使用临时 index 的独立快照。每阶段引用位于 `refs/toolbox-checkpoints/20261022/`，从 R6-start 依次为 R6a1、R6a2、R6a3、R6b-ready，R6 指向最终源码。依赖阶段从后向前回滚，建议新 worktree 查看，禁止 reset 当前脏工作树。

## 日常开发与本机产物

```sh
# 仓库中已有锁定 adb+NOTICE 时无需联网；没有时显式准备：
python3 scripts/runtime_assets.py prepare
python3 scripts/runtime_assets.py check
swift test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/validate_architecture.py
python3 scripts/validate_preview_boundary.py

# 每次选新输出目录，保留上一版；默认是 development（明确 ad-hoc，非正式包）。
./build_app.sh --output .build/artifacts/dev-001
./make_dmg.sh --app '.build/artifacts/dev-001/红米G Pro ToolBox.app' --output .build/artifacts/packages-001
```

默认 build 输出 `.build/artifacts/development`，默认 make_dmg 从该目录取 App，输出 `.build/artifacts/packages-development`。两步独立且均失败即非零；不再顺带覆盖 `macos/红米G Pro ToolBox.app`，不会更换现用应用。CLI 用完整 Xcode（已验证 27.1 / SDK 27+）；纯 `swift build --product MimonitorToolbox` 开发入口仍保留，但发行不再有另一套重复 plist/资源组装实现。

开发文件名带 `-development`，local 带 `-local`；仅已正式签名并公证通过的输出可命名为无后缀的 `MimonitorToolbox-macos-arm64.dmg/.zip`。`.app` 中文名、Bundle ID、可执行名和窗口行为保持不变。构建版本由 `--version x.y.z --build 数字[.数字]` 显式传入；CI 版本取标签，构建号取 run number，避免硬编码旧版本。

可选 local 模式需 `--mode local --identity <唯一SHA1>`，与 development 一样仅作本机开发，不能等同 Developer ID 或保证 TCC 连续性。旧 setup_signing_cert.sh 仅保留显式手动的历史本机用途，打包/CI 不调用它。旧 export_signing_cert.sh 已停用：原脚本的 `security export -t identities` 会导出整个登录钥匙串的身份，而不只是指定证书。

`reinstall.sh` 仍是显式安装入口，会改变本机安装状态；默认读取新开发构建路径，也可显式 `TOOLBOX_APP_PATH`。本批没有执行它。正式升级应先保留旧签名 App 和 DMG，再在固定安装路径进行独立验收；源码回滚不自动恢复签名/TCC/SM 状态。

## 校验和不可变性

资源锁固定官方 `platform-tools_r37.0.1-darwin.zip`，不再下载 latest。先校验 ZIP 摘要，再仅提取锁定 adb/NOTICE，避免不受控解包和 Homebrew 回退。Xcode 拷贝阶段先验证全部输入，任何 JAR/APK/图标/NOTICE 缺失均失败。

主程序和所有识别到的 Mach-O 必须仅 arm64；主程序 minOS 27.0，嵌入 adb 最低系统可更早但不得高于支持门槛。只允许系统动态依赖；未审查新增可执行代码阻止发布。App 身份、用途声明、automation entitlement、非 Sandbox 及正式包禁止 get-task-allow 均验证。签名由内向外；`--deep` 仅作校验，不作递归签名捷径。签名后不裁剪或改 bundle 内容。资源脚本完整声明输入/输出，避免新增资源时 Xcode 沿用旧 CodeResources；发行入口在拷贝完成后明确再做最终 App seal 并验证，增量构建也不能漏签。Debug 与安全 Preview 保留开发配置，Hardened Runtime 的发行门禁针对 Release。

adb 源文件完整摘要锁定。产物代码校验在临时副本移除签名后比较全部字节，仅归一化签名变化造成的 __LINKEDIT 虚拟分配大小；不改实际源/产物。JAR/APK/NOTICE/致谢等逐字节比对。DMG 挂载后比较完整 App 的内容、权限和链接，ZIP 解压后同样复验。输出仅在全部完成时原子改名到目标目录，已有输出拒绝覆盖。`SHA256SUMS` 和 release-manifest.json 记录模式、版本、资源锁与摘要；build 另保留工具链和 source HEAD/dirty 状态，不宣称当前脏工作树可只靠 HEAD 复现。

DMG 使用 UDZO、readonly/nobrowse/noautoopen；清理只针对自身挂载点，正常卸载失败会尝试受限强制卸载且仍向调用方报告失败。SIGTERM/SIGINT 走清理；机器断电或 SIGKILL 无法承诺清理。失败证据留在 `.toolbox-package-*`，失败封装改为 `FAILED-*.partial`，不会被成功产物 glob 混入。公证超时保留 submission 结果，Apple 服务可能仍继续；应先凭 id 查询，不应盲目重复提交。

## 正式凭据与公证

当前本机检查结果为 **0 个有效 codesigning identity**。正式执行需要：

1. 已导入本机钥匙串或专用钥匙串的 **Developer ID Application 证书及对应私钥**，提供唯一 SHA1 与 10 位 Team ID；自签名、Apple Development、缺失身份一律拒绝。
2. 已安全存储的 `notarytool` Keychain profile。可使用 App Store Connect API key 或 Apple ID 专用密码在本机交互设置，不把私钥/密码发到聊天或提交仓库。

```sh
# 以下占位符需替换；公证 profile 预先在本机安全配置。
./build_app.sh --mode distribution --identity '<SHA1>' --team '<TEAMID>' \
  --version 0.1.0 --build 20261022.6 --output .build/artifacts/official-app-001
./make_dmg.sh --mode distribution --identity '<SHA1>' --team '<TEAMID>' \
  --profile '<Keychain-profile>' --app '.build/artifacts/official-app-001/红米G Pro ToolBox.app' \
  --output .build/artifacts/official-packages-001
```

自定义钥匙串可通过 `TOOLBOX_SIGNING_KEYCHAIN` 供 build 定位，并为 make_dmg 传 `--keychain`。没有改变用户钥匙串搜索列表或系统信任库。正式签名检查 Developer ID authority、TeamIdentifier、runtime 和安全 Timestamp；不会因失败改用 ad-hoc。

正式路径先公证 App ZIP 并取得日志，只有 Accepted 才给 App staple/validate；然后创建、签名、公证及 staple DMG，再 Gatekeeper assess、挂载回读，最后从已 stapled App 创建并解压验证 ZIP。这样 ZIP 和 DMG 内的 App 均携带票据。外层 DMG 单独签名和公证是容器所需；App 额外公证用于提供独立 ZIP。没有正式凭据时只测试规则和失败路径，不能宣称公证/Gatekeeper 已成功。

依据 Apple [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)、[packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) 与 [custom notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

## CI 和远端发布

开发 job 不注入签名秘密；外部 fork PR 不在自托管机器执行。Actions 全部锁定已核实的完整 commit SHA。默认 push/tag 只验证并上传明确 development artifact；**不再自动把自签名包发布为 Release**。

正式分发仅 `workflow_dispatch` 在 `vX.Y.Z` 标签上显式选择 distribute，进入 `macos-release` environment，在带 `toolbox-release` 标签的隔离 macOS 27 ARM64 runner 执行。需管理员实际配置 environment 审批人、标签/分支保护和一次性或干净专用 runner；写在 YAML 中不等于远端已启用。本批未注册 runner、设置 secrets、触发 CI 或创建 GitHub Release。

Environment secrets：DEVELOPER_ID_P12_BASE64、DEVELOPER_ID_P12_PASSWORD、NOTARY_KEY_P8_BASE64。Environment vars：DEVELOPER_TEAM_ID、NOTARY_KEY_ID、NOTARY_ISSUER_ID。P12 仅包含选定 Developer ID 身份；建议通过钥匙串访问导出所选项，不导出登录钥匙串。CI 创建权限受限的临时目录/钥匙串，单独指明签名查找范围，导入后删除 P12/P8，always 清理凭据；不 sudo 添加 trustRoot、不回写用户默认搜索列表。security 工具部分参数必需经 argv，需隔离 runner，脚本不打印秘密或失败命令；中断/主机故障仍须通过 runner 重建防止残留。

仅正式公证 artifact 能进入后续 job，下载后核对 SHA256SUMS，上传到 **草稿** GitHub Release。最终发布前仍需维护者确认签名首启/升级和版权来源。

## 版权与签名环境验收仍待完成

原 README 来源、源码作者注释与 Git 历史保留；包内增加 Acknowledgements.txt，不擅自补写 MIT 或其他许可证。adb 官方完整 NOTICE 现已随每个来源路径入包。JAR 有仓库源代码；Guardian README 指向此 checkout 不存在的 `/home/hq/mitv/adb_guardian`，未能确认可复现源码及再分发授权。项目整体与图标许可证也未确认。**完整性、公证通过都不代表再分发权已确认，公开发布前必须解决这些已有来源问题。**

收到正式凭据后还需实际签名、公证 Accepted/log/staple/Gatekeeper 验证，并在干净账号/机器检查下载隔离首启、固定路径覆盖升级、登录项迁移、AX/Terminal/局域网授权、旧版回退和显示器回读。当前测试不能替代这些系统/硬件验收，也不能保证跨签名身份保留权限。
