import ToolboxDomain
import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class PictureModel {
    package var currentValues: [String: String] = [:]
    package var activeSource: String = "未知"
    package var loadedPages: Set<String> = []
    package var isBusy: Bool = false
    package var loadingPages: Set<String> = []
    package init() {}
    package var pictureModeHint: String {
        let raw = currentValues["picture_mode"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, let mode = Int(raw) else {
            return "当前场景：未知（\(raw ?? "无")）"
        }
        if let group = RegisterMap.pictureModeGroupName(mode) {
            return "当前场景：\(group)（\(mode)）"
        }
        let scene = RegisterMap.sceneNames[mode] ?? "未知场景"
        return "当前场景：\(scene)（\(mode)），不匹配上方模式按钮"
    }

    /// 游戏模式提示的三态（移植自 _update_game_mode_hint）
    package enum GameModeState { case unknown, active, inactive }

    package var gameModeState: GameModeState {
        // 两个键任一有有效值就算"已知"；原版还会容忍 "null"/"N/A"
        let keys = ["picture_mode", "picture_preset_scenario"]
        let known = keys.contains { key in
            guard let v = currentValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !v.isEmpty && v != "null" && v != "N/A"
        }
        guard known else { return .unknown }
        let isGame = keys.contains { RegisterMap.isGamePictureMode(currentValues[$0]) }
        return isGame ? .active : .inactive
    }

    package var gameModeHintText: String {
        switch gameModeState {
        case .unknown: return "当前画面模式未知；高亮值尚未确认是否生效。"
        case .active: return "当前为游戏模式；下方高亮为当前生效值。"
        case .inactive: return "当前不是游戏模式；下方高亮为记忆值，功能当前未生效。"
        }
    }

    /// 未知 / 非游戏模式用琥珀色警示，游戏模式用常规色
    package func intValue(_ key: String, default fallback: Int) -> Int {
        guard let s = currentValues[key],
              let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return fallback }
        return v
    }

    package var gameModeHintIsWarning: Bool { gameModeState != .active }
    package var isCustomColorTemp: Bool { intValue("picture_color_temperature", default: 1) == 3 }
}
