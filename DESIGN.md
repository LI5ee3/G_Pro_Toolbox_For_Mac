# 红米 G Pro ToolBox 设计规范

更新：2026-10-21

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
- macOS 26+ 使用公开 SwiftUI `glassEffect`/`GlassEffectContainer`；旧系统和“减少透明度”回退实底。（Agent 推断）
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
- 未读数用“—”，可用通道决定控件启用；蓝牙音量可用时不以 ADB 离线为由禁用声音操作。（Agent 推断）
- 不隐藏蓝牙、快捷键、预设、任务、保活、诊断、日志等现有功能；不新增 USB ADB。（用户确认：保留全部功能；USB 范围沿用前序确认）
- 保存失败保留输入和位置；成功以实际结果为准，不能仅按安装/提交返回就宣称成功。（Agent 推断）

## 生效与记忆值
- 游戏辅助与屏幕工具未在游戏场景生效时，记忆值采用中性色选中并提供可读状态；320Hz与FreeSync按各自真实状态表达。（Agent推断，源码语义核对）
- 灯光关闭态减弱下级参数；选择色温或纯色会直接切换对应模式，必须明确说明。（Agent推断，源码语义核对）
- 深色实体在缩略图中仍应可辨立柱、走线孔和底座；主操作按钮使用统一large尺寸。（Agent推断，截图修正）
