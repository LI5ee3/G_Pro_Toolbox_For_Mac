import Foundation

// MARK: - 快捷键配置模型

package struct HotkeyConfig: Codable, Equatable {
    package init(modifier: String = "无", key: String = "无") { self.modifier = modifier; self.key = key }
    package var modifier: String = "无"
    package var key: String = "无"
    package var isEnabled: Bool { modifier != "无" && key != "无" }
}

package struct AdjustHotkeyConfig: Codable, Equatable {
    package init(param: String = "backlight", direction: String = "increase", step: Int = 5,
                 modifier: String = "无", key: String = "无") {
        self.param = param; self.direction = direction; self.step = step; self.modifier = modifier; self.key = key
    }
    package var param: String = "backlight"
    package var direction: String = "increase"
    package var step: Int = 5
    package var modifier: String = "无"
    package var key: String = "无"
    package var isEnabled: Bool { modifier != "无" && key != "无" }
}

package enum HotkeyLists {
    /// 下拉里能选到的修饰键组合。名称必须和 `HotkeyMap.modifierName(for:)`
    /// 生成的一致，否则录入的快捷键在下拉里显示不出来。
    package static let modifiers = [
        "无", "Cmd", "Cmd + Shift", "Cmd + Option", "Cmd + Ctrl",
        "Ctrl", "Ctrl + Alt", "Ctrl + Shift",
        "Alt", "Alt + Shift", "Shift",
    ]
}

/// 8 个循环切换动作（对应原版 tools 页 actions_list）
package let hotkeyActions: [(id: String, label: String)] = [
    ("picture_mode_cycle", "画面模式 循环切换"),
    ("local_dimming_cycle", "精密控光 循环切换"),
    ("local_dimming_toggle_off", "精密控光 开关切换"),
    ("color_space_cycle", "色域 循环切换"),
    ("color_temp_cycle", "色温 循环切换"),
    ("response_time_cycle", "响应时间 循环切换"),
    ("freesync_toggle", "FreeSync 开关切换"),
    ("input_source_cycle", "信号源 循环切换"),
]

/// 可调参数（对应 core.py ADJUSTABLE_HOTKEY_PARAMS）
package let adjustableParams: [(id: String, label: String, defaultStep: Int)] = [
    ("backlight", "背光", 5),
    ("black_level", "黑色级别", 5),
    ("contrast", "对比度", 5),
    ("saturation", "饱和度", 5),
    ("hue", "色调", 5),
    ("sharpness", "锐度", 1),
    ("red_gain", "红色增益", 10),
    ("green_gain", "绿色增益", 10),
    ("blue_gain", "蓝色增益", 10),
    ("atmosphere_illumination", "屏幕灯亮度", 1),
]

