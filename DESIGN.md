# 红米 G Pro ToolBox 设计规范

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
