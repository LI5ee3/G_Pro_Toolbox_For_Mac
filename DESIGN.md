# 红米 G Pro ToolBox 设计规范

更新：2026-10-24 · **S3-01 方向已由用户采用并合并；S3-02 共享组件实现待 review**。

用户已采用 PR #5 的“控制优先的原生工作区”作为后续 UI 实现方向，并单独授权 S3-02。PR #5 复核 HEAD `c71f7995445a7f84c744ddf546d0be2b7588bb2f` 与已 review 版本一致，默认 CI [#33](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/40093006793) 通过后，以 merge commit `b6648bccf47117b3619a465af98ffc435704f323` 合入 master；合并后的默认 CI [#34](https://github.com/LI5ee3/G_Pro_Toolbox_For_Mac/actions/runs/40097070825) 亦通过。设计分支引用已正常删除，原工作树与内容保留。本轮仅实施下面的共享规则，不迁移页面结构，不开始 S3-03；现用 App 不替换。M2/G2 NOT_PASSED、Auto DEFERRED、G3 未通过。下文 S3-01 提案与 Pro B 取舍作为形成过程保留，旧的“待确认/不开始 S3-02”停止点由本次授权取代。

平台及业务边界见 [ARCHITECTURE](docs/ARCHITECTURE.md)，进度以 [ROADMAP](docs/ROADMAP.md) 为准。

## S3-02：共享组件规则与本轮范围（实现待 review）

沿用已采用的北极星：打开后直接调显示器，需要精调时仍能迅速找到每个参数。本轮在合并后的 master 上使用独立分支 `ui/s3-02-shared-components`，实际读取已安装 **oil-ui-pro 0.24.2** 的 SKILL、存量项目、组件、交互与状态及视觉精修规则；不升级技能、不重新探索方向或组织评分。以下是共享样式的落地，S3-01 原型不复制进生产代码。

- **颜色与性能**：在现有 `Theme` 内将画布、内容、次级控件、边界和辅助文字改为中性灰角色。保留已有浅深自适应 RGB 求值路径与 accent/onAccent、成功/警告配对，避免把高频表面机械换成 CoreUI 语义色；强调色仍只辅助主动作和选中。本项先保留可用的强调色配对，不建立动态主题引擎。
- **字级与间距**：页头 22pt semibold，分组 14pt semibold，按钮及滑块标签/读数 13pt；读数等宽。共享分组内距 16pt、内容间距 12pt；控件圆角 8pt、分组圆角 12pt。只提取当前实际复用的三个样式值。`ButtonGroupSection` 沿用现有结构并复用分组字级。
- **动作与选择**：`toolboxAction` 普通动作为中性实底加边界，主动作使用原生 `borderedProminent`，减少高频按钮的玻璃装饰；`toolboxGlass` 继续只服务已有浮动功能层。`SelectableButton` 以勾选、字重和边界表达选中，保留原有 selected 辅助功能 trait；勾选预留位置，切换不挤动按钮。禁用时保持可读文字与轮廓，点击语义沿用 SwiftUI。
- **参数与状态**：`SliderRow` 仅统一标签、数值、实底和边界，现有宽度、Binding、步长、范围、松手/辅助功能提交和外部读数同步不变；`FastSlider` 实现逐字保持。`ConnectionPresentation` 直接从已有 `connectionStatus` 派生图标和色彩：未连接/连接中/扫描中为中性；授权、离线、失败为警告；已连接为成功。首页、原连接 sheet 与菜单面板复用它，始终保留原模型的状态文字，没有新业务状态或发布机制。
- **辅助功能**：复用系统减少透明度、减少动态效果。高对比度时共享表面改用清晰的主文字色边界，玻璃回退实底；减少动态效果时沿用原有无缩放/位移分支。当前 SDK 的这些环境值只读，因此仅增加一个 package 内的三布尔 Preview 注入点，默认全 false，与真实系统值合并；不改系统全局设置、不持久化，不新增配置层。原生系统控件继续由系统处理其辅助功能。

实际检查生产共享组件的安全入口现在是 [`ToolboxPreviewGallery`](macos/Sources/ToolboxPreviewSupport/PreviewGallery.swift)，宿主默认打开它；顶部外观和辅助功能开关仅属于 Preview。既有内存 fake、会话和动作继续复用。S3-01 的 [`ToolboxS301Gallery`](macos/Sources/ToolboxPreviewSupport/S301DesignPreview.swift) 与 `#Preview("S3-01 原生设计提案")` 保留，仍可在 Xcode 打开提案；不拿独立提案样式代替生产组件验证。

只构建现有安全 Preview（输出目录应为本轮独立临时目录）：

```sh
xcodebuild -project macos/Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug \
  -derivedDataPath /tmp/s3-02-review-preview -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=- build
```

打开 `/tmp/s3-02-review-preview/Build/Products/Debug/ToolboxPreviewHost.app`，使用顶部场景/页面选择及外观开关。所有设备、读数、权限与系统动作均为内存模拟；关闭后丢弃，不接触现用 App 或 5038 server。

必要检查：安全 Preview 编译与既有依赖/源码副作用/二进制资源边界 PASS；源码核对 FastSlider 及 SliderRow 提交/外部同步保持。实际看图覆盖默认 1120×880 宿主内的浅色首页、深色画面页、参数底部，以及减少透明度/动态效果和增加对比度注入下的浅深代表画面；选中勾选、禁用项、授权/未连接文字及图标可读。截图为原生运行的模拟界面静态记录，不是生产 App 或真机验收：

[浅色首页](docs/design/S3-02/home-light.jpg) · [深色参数](docs/design/S3-02/picture-dark.jpg) · [辅助功能模拟与参数底部](docs/design/S3-02/picture-accessibility-light.jpg) · [深色授权与禁用](docs/design/S3-02/home-authorization-dark.jpg) · [原连接面板](docs/design/S3-02/connection-accessibility-light.jpg)。

纯样式未新增单元测试；本机不重复完整 Swift/Python 回归、三种构建、全页视觉矩阵、Instruments 或真机验收，完整默认检查由自然触发的 CI 承担。没有新一轮独立评分。临时 Preview 已退出、临时 App/构建输出已清理；七个原未提交文件、其他工作树、历史标签、现用 App 文件及 App/5038 server 的 PID/启动时间核对一致。S3-02 停在独立草稿 PR review；S3-03 保留连接/首页/菜单栏结构迁移，后续参数页重排、菜单系统集成、焦点与完整视觉矩阵按原后续项处理。本轮不宣称这些页面已按提案迁移。

## S3-01 原提案与交付记录（方向已采用）

以下正文和检查记录描述 S3-01 当时交付，提案中的页面结构留待相应后续项实施。

## 推荐方向：控制优先的原生工作区（Agent 提案）

**北极星：打开后直接调显示器，需要精调时仍能迅速找到每个参数。**

核心对象是一台已识别的物理显示器；主动作是调音量、静音、背光；使用频率是每天多次的短操作，偶尔连续精调。设备名称与控制状态先于装饰。取消大幅机身插画，把首页原来被实体占据的空间交给真实控件和当前上下文。

- **结构**：可缩放双栏窗口；左侧常驻分组导航，右侧为当前任务。十个既有页面全部可见，不再把五页藏在“全部工具”内。连接入口常驻于侧栏设备区与页头，日志不占首页主体。
- **首页**：紧凑设备摘要 → 音量/背光/画面模式的一个连贯控制面 → 视频输入/预设/自动任务的开放信息行。高频控件不放在窗口底部；未知值使用“—”。
- **参数页**：单列对齐的专业参数，标签 100pt、数值 42pt、范围 62pt，轨道伸缩。基础画面行高 34pt；色彩、光影与响应以标题和留白分组，不逐行套卡。多选项用原生菜单，少数互斥高频选项用分段控件。
- **连接**：620pt 宽的原生 sheet，固定标题/底部动作，正文滚动。“活动连接”和“选择连接目标”分开。浏览 USB/TCP 不触发切换；按“断开并连接所选目标”才复用现有 disconnect/mode/connect 行为。切换失败保留目标和输入；不承诺原端点继续在线或自动回滚。
- **菜单栏**：360pt 快捷面板，设备/活动端点 → 音量/静音/背光 → 预设 → “打开主窗口”与“更多”。连接、配置、断开、退出收在“更多”；可选条目沿用现有目录和排序，不把完整专业参数页搬进小面板。
- **风格与密度**：中性背景、系统字体和系统强调色。正文 13pt，分组 14–15pt，页面标题 20–24pt，高频读数 28pt、等宽数字。常用按钮至少 28pt 高；12/16/24/28pt 的间距节奏。普通内容不铺玻璃、渐变或大阴影。
- **识别点**：音量与背光同一条阅读轴，当前值和动作相邻；活动端点与候选端点明确分区。辨识度来自控制对象和操作秩序，保留 App 名称、图标与设备称呼，不额外引入品牌素材。
- **放弃**：拟物遥控底座、首页屏幕插画、横向溢出导航、指标卡阵列、整页加载遮罩及装饰动画。

与现有 Pro B 截图 `macos/assets/screenshots/ui-c-home.png` 及当前入口代码比较：不是换皮，导航由顶部折叠菜单改成侧栏；首页从实体展示改成控制工作区；画面页从多张独立控件卡改成统一阅读列。侧栏沿用 macOS 的熟悉关系，但内容组织来自本项目的高频动作，不模仿其他产品的品牌/业务模块。本轮没有值得另做完整方案的结构性分歧，按用户要求只交付这一方向。

## Apple HIG 依据与可实现性（Agent 提案）

2026-10-24 实际查阅 Apple 官方 [HIG](https://developer.apple.com/design/human-interface-guidelines) 及下列章节（页面的官方 `.md` 版本亦已读取）。采用本机 **macOS 27.0.1 (26A434)、Xcode 27.1 (27A9275)、macOS SDK 27.0、arm64**；不推断未来 SDK 接口。

| 官方依据 | 本项目的取舍 | 公开实现入口 |
| --- | --- | --- |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | 窗口可缩放、舒适密度、菜单命令与键盘操作；不以移动端大卡片稀释专业信息 | `NavigationSplitView`、sidebar `List`、`Commands`、`keyboardShortcut` |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | 重要操作放上方；对齐、分组、渐进披露；窗口缩小时保留任务入口 | `ScrollView`、`DisclosureGroup`、伸缩轨道、sheet 正文独立滚动 |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | 材质表达功能层级；参数内容实底；系统导航与弹层按语义使用材质 | 原生 sidebar、`.bar`、菜单快捷面板 `.regularMaterial`；不依赖私有玻璃 API |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | 状态同时有文字与图标，未知不等于 0；标准焦点、键盘与读屏标签；减弱动态和透明效果 | `accessibilityLabel/Value`、`FocusState`、系统按钮/Picker、`accessibilityReduceMotion/Transparency` |

颜色采用语义角色：主内容 `controlBackgroundColor`、分组 `.background`、导航/工具条 `.bar`、文字 `.primary/.secondary`、分隔 `.separator`、选中/主动作系统 accent。系统灰在浅深色下形成低对比表面与高对比文字；绿只辅助“已连接”，并始终配勾选图标和文字。具体像素随系统外观与 accent 变化，不锁死冷白钴蓝。减少透明度时面板回退实底；增加对比度时加强边界。原 Theme 的 CoreUI 性能经验仍是后续实现约束，不能把本轮小原型的系统色用法直接视为已通过全量页面性能验证。

## 功能与导航对应（Agent 提案）

| 现有入口/功能 | 新入口与布局 | 沿用的实现与语义 |
| --- | --- | --- |
| 手动 USB/TCP、内网扫描、填写地址诊断、授权、断开 | 页头/侧栏“连接设置…”；活动连接在上，USB 候选或 TCP 表单在下 | `AppCoordinator+Connection/+USBConnection`；明确选择、单活动会话、USB 逻辑断开与恢复暂停 |
| 活动端点、同传输恢复、睡眠恢复 | 设备区简短状态，连接 sheet 解释恢复意图、取消和重试 | 原 `ConnectionModel/ConnectionIntent`；恢复中不显示 ready，不混入 Auto |
| 设备身份、保存连接偏好、数据归属、备份/恢复 | sheet“设备身份与数据归属”；工具与设置提供自动备份/内部恢复限制说明，不新增恢复按钮 | `ConnectionIdentityControls` 对应原会话/token 确认、两类归属选择；不按型号/IP猜同机 |
| 音量、静音、背光、三类画面模式 | 控制台主控制面；菜单栏与现有快捷键继续可达 | `setDashboardVolume/toggleDashboardMute/setPictureSlider/setMode`，保留输出门控、提交队列与结果语义 |
| 基础画面、色温/增益（524–1524）、色域、控光、HDR、清晰度、响应 | 画面 → 基础画面/色彩/光影与响应 | 既有 `OptionLists/ControlRanges`、JNI/settings 映射；自定义色温才展开 RGB；HDR 按真实模式显示 |
| 320Hz、FreeSync、游戏辅助、准星/动态准星、狙击镜/夜视、刷新率/计时/秒表、记忆联动 | 游戏 → 刷新与同步/游戏辅助/屏幕工具/记忆与联动 | 未读/失败为未知；记忆态与实际生效态分开；不删已有参数 |
| DP/HDMI 1/HDMI 2/USB-C 视频输入 | 信号源 → 当前输入与四个选择项 | 原 `OptionLists.source`；视频 USB-C 与 USB ADB 分别命名；影响画面的操作保持现有语义 |
| 灯光模式、亮度挡位、色温、纯色 | 灯光 → 模式/亮度/颜色 | 原五种模式与范围；关闭时保留记忆，选色/色温会切换模式的说明必须可见 |
| 创建/命名/重命名/删除/应用/编辑预设、无预设、菜单栏可见性 | 预设 → 列表；所选预设的行内动作和“更多”；编辑进画面页 | `PresetEngine/Store/Worker`、原 JSON；自动保存对象与不完整应用保护保持 |
| 时段创建/编辑/删除、启用、优先级、跨日、返回目标 | 自动任务 → 时间/预设/状态列表，表单只编辑时段 | 既有调度、冲突和恢复；**保留已实现自动任务，不是 Auto 连接策略** |
| 方向/OK、主页/菜单/返回、音量/静音及现有键码 | 遥控器 → 紧凑方向区与动作行 | 既有 `RemoteView` 键码和提交；不发明新遥控能力 |
| 保活、4K UI、APK、ADB 命令行/Shell、诊断/日志 | 工具与设置 → 显示器工具/排障；日志另可从页头打开 | 现有权限、部署、重启说明与结果读回；按需展开开发信息 |
| 辅助功能/自动化/本地网络、媒体键/亮度键/组合键、OSD/HUD、登录项、外观、关窗行为、源码 | 工具与设置 → 键盘控制与权限/应用/关于 | 现有系统适配与读回，不通过新 UI 重绑权限或修改登录项 |
| 菜单栏条目、顺序、默认项及预设 | 菜单栏配置 → 已启用列表与目录；上移/下移补足拖动的键盘等价路径 | `MenuBarCatalog/OrderedItems` 和原存储；面板内容有限高滚动 |
| 菜单栏的断开/重连、显示主窗口、退出 | 快捷面板底部“打开主窗口”与“更多”；连接设置负责重连，已连接时显示断开 | 原关窗驻留、退出及连接抑制；原型不安装额外 status item |

其他页面共享上述窗口外壳、页头、参数行与原位反馈。游戏的真实/记忆状态做同行说明；信号源用四个选择行；灯光按模式披露颜色；预设和任务用列表而非堆叠卡片；遥控器只对方向控制保留空间型布局；工具按任务分组。以上规则足以推导其余页面，不追加多套完整设计稿。原型中的这些页面是布局文字骨架，未接入动作；不把它们当作生产完成。

## 关键交互与状态（Agent 提案）

1. **连接**：任意页面 → 连接设置 → 浏览 USB/TCP → 选明确候选或填写地址/端口 → 点击连接。存在活动连接时，主动作明确为“断开并连接所选目标”。先结束旧会话再验证新目标；只有原探活/身份规则满足才显示可用。成功后用户可继续保存偏好或确认归属，也可完成返回原页面。
2. **授权/离线/失败**：待授权指向显示器上的 ADB 请求；离线保留目标；失败保留输入、原因、诊断与重试。执行中主按钮转为取消；取消沿原会话失效规则，不承诺远端已执行命令可撤回。手动断开明确暂停恢复。同传输恢复显示活动传输，不展示跨传输 Auto 开关。
3. **控制**：拖动本地读数立即反馈，松手沿原动作提交；执行状态/失败显示在相关控件附近，保留上次成功值并标明已过期。未知显示“—”，不把缓存作为新成功。预设不完整时按原策略禁用并给“重新应用/返回无预设”。不重新实现队列、节流、取消或业务发布。
4. **返回和焦点**：sheet 初始焦点在首个输入；Return 提交、Escape 完成/关闭并返回触发器；Tab/Shift-Tab 在原生控件间移动。`⌘K` 打开连接设置；`⌘,` 作为后续应用设置入口，系统快捷键不覆盖。所有主要动作既有文字又有明确焦点。
5. **菜单栏**：音量/静音/背光无需开主窗口；更多参数回主窗口原目的地。面板不是另一个连接客户端，复用同一状态与动作。原型只承载面板内容，没有注册真实菜单栏项；其主窗口/配置跳转只导航到提案表面或骨架，退出调用既有模拟动作，详见下方范围。

动效沿用克制的系统手感：原生按钮按下反馈；原生 sheet 开合；连接文字/符号 160ms 短淡变。没有整页入场或装饰运动：高频工具需要立即可读，这一取舍优先于 oil 通用“首次入场”建议。减少动态时状态直接到位。临时 Preview 不改变系统的外观或辅助功能设置。

## 滑块、窗口与生产复用（Agent 提案）

- 原型为检验公开 API 与键盘焦点，使用系统 `Slider`，局部 Binding 对整数参数舍入、夹取，`ticks: {}` 避免逐值刻度噪声，`onEditingChanged(false)` 时调用原 Coordinator。**不修改生产 FastSlider**。原控件已提供松手提交、VoiceOver 增减与禁用态；若未来替换，收益应限定为标准焦点和键盘交互，必须保持离散步长、范围夹取、松手/辅助功能提交、快捷键节流、取消/旧结果隔离及已有性能约定，届时仅验证实际差异。不声称系统 Slider 已更快。
- 参数取值列用局部 `NSPopUpButton`（180×28pt）承载现有 `OptionLists`，保留原生键盘菜单和辅助功能标签；目的是收齐可见控件边界，避免 SwiftUI 菜单外框随短标签收缩。它仅在本提案文件内，不形成新通用组件层。
- 提案暂保留生产最小 **1020×740**、推荐 **1120×820**；主区连续纵向滚动、轨道随宽度伸缩、侧栏可调宽。高频操作在上半窗，精调页底部允许滚动，不缩小字体塞屏。大窗主内容限宽 970pt，避免轨道横跨整屏。
- Theme 与窗口外观可在后续获准实施时调整；本轮新规则只在 Preview 内。业务层、设备协议、ADB、恢复、预设存储、权限及自动任务执行完全沿用，不批量替换生产页面。

## 可视交付与打开方式

截图集中于 [`docs/design/S3-01/`](docs/design/S3-01/)，为**实际运行的原生 SwiftUI 安全 Preview 截图**，非生图/HTML 仿真，也不是生产 App 实测。所有画面中的活动 TCP `192.0.2.27:5555`、草稿 TCP `198.51.100.42:5566`、USB `000PreviewUSB`、稳定标识 `PREVIEW-STABLE-0001`、音量 10、背光 45、标准模式、DP 输入均为沿用/整理的明确模拟数据；不代表现用显示器读数。

![S3-01 推荐方案原生截图总览](docs/design/S3-01/stitch.png)

| 代表界面 | 可直接打开的截图 | 重点 |
| --- | --- | --- |
| 主窗口 | [浅色](docs/design/S3-01/home-light.jpg) · [1020×740 紧凑](docs/design/S3-01/home-compact-light.jpg) | 十个入口常驻；高频控制在上半窗；底部内容可滚动 |
| 手动连接 | [活动 TCP / 选择 USB](docs/design/S3-01/connection-usb-light.jpg) | 活动端点与候选独立；明确勾选；切换前说明结束当前会话 |
| 连接交互跟进 | [草稿 B / 保存活动 A](docs/design/S3-01/connection-draft-save-light.jpg) · [完整归属确认](docs/design/S3-01/connection-ownership-light.jpg) | 保存对象明确，结果随模型发布；确认依据在弹窗打开时固定 |
| 密集参数 | [深色上部](docs/design/S3-01/picture-dark.jpg) · [滚动到底部](docs/design/S3-01/picture-dark-lower.jpg) | 连续参数列、对齐的原生选项、范围、提交说明 |
| 菜单栏 | [浅色快捷面板](docs/design/S3-01/menubar-light.jpg) | 音量/静音/背光优先，低频管理集中到“更多” |
| 必要状态 | [未知读数](docs/design/S3-01/home-unknown-light.jpg) · [已断开/恢复暂停](docs/design/S3-01/connection-disconnected.jpg) · [等待授权](docs/design/S3-01/connection-authorization-light.jpg) · [执行中](docs/design/S3-01/connection-working-light.jpg) · [失败与重试](docs/design/S3-01/connection-failed-light.jpg) | 未知不等于 0；输入保留；取消与恢复意图可见 |

这些截图是原生运行画面的静态记录；交互能力由下述安全 Preview 提供。底栏的界面/状态/外观选择器属于预览宿主，不进入产品设计。菜单栏图展示面板内容，外层临时窗口不代表最终 status item 容器。

原型源码：[`S301DesignPreview.swift`](macos/Sources/ToolboxPreviewSupport/S301DesignPreview.swift)，入口 [`ToolboxPreviewHost/App.swift`](macos/Sources/ToolboxPreviewHost/App.swift)。S3-01 当时未改原 PreviewGallery/PreviewRuntime，并以“原界面”切回安全画廊；S3-02 宿主现已默认打开生产组件画廊，提案文件及其 #Preview 独立保留。没有新 target/依赖/构建体系。

在开发 Mac 的独立目录只构建已有安全 Preview（不需要 prepare 生产资源）：

```sh
xcodebuild -project macos/Toolbox.xcodeproj -scheme ToolboxPreviews -configuration Debug \
  -derivedDataPath /tmp/s3-01-review-preview -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=- build
```

打开 `/tmp/s3-01-review-preview/Build/Products/Debug/ToolboxPreviewHost.app` 后，底栏选择主窗口/画面/连接面板/菜单栏、模拟状态和浅深色；“紧凑”切到 1020×740。原型对连接、扫描、诊断、归属与首页音量/静音/背光复用现有内存运行时。画面参数也调用原模拟动作，未实施完整读回绑定，不能作为业务验证；其余页面只展示布局文字骨架。执行中场景是固定演示状态，不是正在执行真实任务。关闭后所有模拟数据丢弃。

## oil UI Pro 使用与必要检查

实际安装名 **`oil-ui-pro` 0.23.8**，对应用户所称 oil UI Pro；路径 `~/.codex/skills/oil-ui-pro/SKILL.md`。实际读取并采用其 `existing-project`、`design-direction/direction-workspace`、`interaction-and-state`、`layout-surfaces`、`motion`、`media`、`visual-polish` 与 `visual-review/review-loop` 流程：品类与主任务 → 单方向卡 → 代表界面 → 实际看图 → 独立评审与局部修正。本次用户明确只要一套，跳过三方向与选择确认；用户明确要求在原 DESIGN 记录待 review 提案，因此本文件不把新方向标成用户已确认。

工具能力是宿主中立的设计技能，附带 `shoot.mjs` 提供浏览器截图与已有图片拼接。已实际查阅其 `--help`，使用 `--stitch <截图> --label <名称> --columns 2 --out docs/design/S3-01` 拼成总览。原生 App 的截图/交互采用宿主 CUA 原生能力；拼图成功不代表执行了浏览器 CSS lint 或原生可访问性全验收。图像素材判断为不需要额外照片/插画，使用 SF Symbols 与真实控件。版本检查提示可更新到 0.24.2，本轮保持已安装版本，未执行更新。

检查只覆盖原型编译、功能入口映射、代表画面、关键连接/控制模拟流程与公开 API；不跑本机 Swift/Python 全量、三种构建、完整视觉矩阵或真机验收。默认 PR CI 保持仓库原规则，不追加手动触发。历史 M2/G2 **NOT_PASSED**、Auto **DEFERRED**、G3 **未通过**。

2026-10-24 实际检查结果：

- **原型编译与隔离边界通过**：仅 `ToolboxPreviews` scheme 构建；既有 `validate_preview_boundary.py <Preview.app>` 检查依赖图、源码副作用、二进制/资源边界 PASS。未构建、安装或启动生产候选。
- **代表布局已看图**：1120×820 首页和画面、1020×740 首页、620pt 连接 sheet、360pt 菜单内容；浅色首页与深色参数没有明显不可读或关键裁切。参数底部通过滚动可达，没有缩字塞屏。未执行完整尺寸/状态/辅助功能组合矩阵。
- **关键模拟流程读回**：浏览 USB 保留当前 TCP；明确提交后活动端点变为模拟 USB；断开后恢复暂停。失败重试保留 TCP 输入并可回到模拟连接；菜单静音/解除静音、音量原生增减、主窗口跳转可用。核对 `⌘K`、Tab/Shift-Tab、Return、Escape 及参数原生菜单的标签/选项；未做完整 VoiceOver 或真机手感验收。
- **oil 独立看图复核完成三轮**：发现并修正 USB 未显式选中、密集滑块刻度、菜单管理区过重、参数选项外框不齐和深色分组灰字偏暗；删掉三处重复说明。末轮对六张相关截图逐项复核为修好/做到位、未观察到本批新问题，静态视觉评分 **9/10**。末轮未评动效与未知/授权状态；这些状态由本轮原型和补充截图单独说明，评分不是用户确认或 G3 通过。
- **环境保护读回一致**：原七个文件的 SHA-256/大小/mtime、原工作树状态、历史标签和其他工作树未变；现用 App 的全部 11 个文件及其 mtime 未变，App/5038 server 原 PID 与启动时间保持。临时 Preview 已退出，其 App 与构建输出已清理，仅保留提案源码和截图。

2026-10-24 PR #5 原型交互跟进（基线 `bb765c96e45647a7850788f82d467fad3b1a5ac7`）：继续使用当前已安装的 **oil-ui-pro 0.24.2**，按其交互与状态规则修复指定问题；未执行技能升级、重新设计或新一轮评分。

- “诊断填写地址”点击时临时传入草稿 host/port，既有入口同步固定诊断对象后恢复原输入；不调用传输切换或连接方法。“保存当前连接偏好”明确只保存活动端点，调用既有保存入口时使用该端点，不保存未连接候选，也不改掉草稿。忙碌时显示提交中，结束后直接显示 `profileMessage`；移除发起异步操作后立即复制结果的做法。
- 归属确认沿用生产 `ConnectionIdentityControls` 的方式：打开时固定 session、profile token、包含当前端点/身份/旧数据归属的完整文案和可用选项；确认提交这份依据，由原业务校验拒绝过期确认。
- 仅构建安全 Preview、检查隔离边界，并从本文件直接提取 Fixture 编译临时探针，复用现有内存 fake 和异步完成屏障：A 连接时诊断 B，A 的端点/session/传输保持；候选不同时读回的保存目标仍是活动 TCP/USB；忙碌→成功及旧快照失败的消息发布正确，失败不改原配置；弹窗完整依据固定后，profile token 或 session 改变均由已有校验拒绝。实际 UI 亦读回诊断 B 的日志、保存结果和完整确认文案。未跑全量回归、生产构建或真机检查，未新增测试框架。
- 只更新五张受保存文案影响的连接截图及依赖总览，补充上述两张交互截图；首页、画面、菜单栏原图保持。临时 Preview、探针和本轮构建输出在检查后清理。方向仍为待 review 提案，S3-02 未启动，M2/G2、Auto、G3 状态不变。

## 历史记录：Pro B（2026-10-21/22）

以下为此前设计文档的原始记录；“用户确认”仅描述当时取舍。本轮已解除其强制视觉约束，不能继续作为新提案的约束，也不将历史“仅 TCP”等语句当作当前功能事实。

### 原设计规范

更新：2026-10-22（S1-09 现行范围同步；保留既有视觉方向）

当前平台与运行边界见 [ARCHITECTURE](docs/ARCHITECTURE.md)，执行范围以 [ROADMAP](docs/ROADMAP.md) 为准。下列 2026-10-21 用户取舍记录保留；本次不进行界面重设计。

## 方向
- Pro B「屏幕与光」：以显示器实体为主角，声音、背光和模式集中在其下的遥控底座。（用户确认）
- 冷白与钴蓝、开放画布、紧凑顶部导航；所有现有功能保持可访问。（用户确认）

## 品牌资产
- 保留应用名称、当前图标、Redmi G Pro 设备身份，不引入另一套品牌标识。（Agent 推断）
- 显示器按用户参考图绘制：黑色窄框、略厚下沿、带椭圆走线孔的立柱、扁平黑底座；屏幕无宣传图片。（用户确认）

## 语义角色
- 颜色在 `macos/Sources/MimonitorToolbox/Views/Components.swift` 的 `Theme` 定义；强调色仅用于主动作、当前位置和选中状态。（Agent 推断）
- `canvas` 为开放工作区，`card` 为参数与正文实底，`control` 为次级控件底，`secondaryText` 必须在浅深主题均清楚可读。（Agent 推断）
- 正文 13–14pt，参数页标题 23pt；首页数值使用等宽数字及圆体，单位弱于数值。（Agent 推断）
- 相同层级动作采用同一按钮形态；禁止用大量系统默认渐变与另一套自绘主按钮并列竞争。（Agent 推断）

## 原生玻璃
- 原生 Liquid Glass 用于导航、遥控底座和菜单栏面板，不覆盖长段参数文字。（用户确认：采用原生玻璃；应用范围为 Agent 推断）
- 当前仅支持 macOS 27+ / Apple Silicon，使用公开 SwiftUI `glassEffect`/`GlassEffectContainer`；“减少透明度”时回退实底，不承诺旧系统兼容。（现行源码核对）
- 按压约 140ms，导航选中转场约 200ms，首次进入淡入约 300ms；减少动态效果时取消位移和缩放。（Agent 推断）

## 共享组件
- `MonitorHardwareView { screen }`：1000×835 实体画布、精确16:9屏内、透明走线孔；首页/信号源必须复用。（Agent 推断）
- `SectionCard`：必要的内容分组，不层层套卡；连续专业参数用开放分组。（Agent 推断）
- `SelectableButton`、`SliderRow`、`FastSlider`、`PageHeader`：保持公共语义及辅助功能动作。（Agent 推断）
- `.toolboxAction()`：普通动作；`.toolboxAction(prominent: true)`：当前区域唯一主动作。（Agent 推断）
- `.toolboxGlass()`：仅浮动功能层使用；不为装饰滥用。（Agent 推断）

## 样板页面
- `macos/Sources/MimonitorToolbox/Views/HomeView.swift`：设备、实体和控制底座的关系。
- `macos/Sources/MimonitorToolbox/ContentView.swift`：紧凑导航及所有页面入口。

## 用户取舍
- 2026-10-21：选 Pro B；显示器外形替换为用户提供的黑色机身，去除屏内宣传图。（用户确认）

## 不要做
- 不把视频输入可用等同于网络 ADB 已连接，不伪造 nits、dB、帧率、延迟或桌面实时预览。（Agent 推断）
- 未读数用“—”或明确“未知”，320Hz/FreeSync 的失败或未知 JNI 值不能显示为确定“关闭”；可用通道决定控件启用。当前声音操作使用 ADB，CoreAudio 只读取默认输出；原蓝牙控制已移除，系统配对不受影响。（现行源码核对）
- 保留快捷键、预设、任务、保活、诊断、日志等现有功能。当前应用仍仅开放 TCP ADB；USB/Auto 是 ROADMAP 阶段二及 [ADB-CONTRACTS](docs/ADB-CONTRACTS.md) 的后续设计，须经过门禁，不能凭历史 CLI 实测宣称 App 已支持。（原功能保留原则与现行范围同步）
- 保存失败保留输入和位置；成功以实际结果为准，不能仅按安装/提交返回就宣称成功。（Agent 推断）

## 生效与记忆值
- 游戏辅助与屏幕工具未在游戏场景生效时，记忆值采用中性色选中并提供可读状态；320Hz与FreeSync按各自真实状态表达。（Agent推断，源码语义核对）
- 灯光关闭态减弱下级参数；选择色温或纯色会直接切换对应模式，必须明确说明。（Agent推断，源码语义核对）
- 深色实体在缩略图中仍应可辨立柱、走线孔和底座；主操作按钮使用统一large尺寸。（Agent推断，截图修正）
