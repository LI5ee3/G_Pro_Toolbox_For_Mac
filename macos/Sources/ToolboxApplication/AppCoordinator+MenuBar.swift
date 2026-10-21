import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func setAutostart(_ enabled: Bool) {
        environment.system.setAutostart(enabled)
        autostartEnabled = environment.system.autostartEnabled()
        log(enabled ? "已设置开机自启动（下次登录生效）" : "已取消开机自启动")
    }


    /// 已加入菜单栏的条目 id，顺序即菜单显示顺序。持久化到 UserDefaults。
    package var menuBarItems: [String] {
        get { keyboard.menuBarItems }
        set { keyboard.menuBarItems = newValue; guard !isConfiguring else { return }; preferences.set(menuBarItems, forKey: Self.menuBarKey) }
    }

    internal static func loadMenuBarItems(_ preferences: any PreferencesStore) -> [String] {
        guard let saved = preferences.array(forKey: menuBarKey) as? [String] else {
            return MenuBarCatalog.defaultEnabled
        }
        // 过滤掉清单里已经不存在的 id（版本升级后清理）
        return saved.filter { MenuBarCatalog.entry($0) != nil }
    }

    package func toggleMenuBarItem(_ id: String) {
        if let idx = menuBarItems.firstIndex(of: id) {
            menuBarItems.remove(at: idx)
        } else {
            menuBarItems.append(id)
        }
    }

    package func isMenuBarItemEnabled(_ id: String) -> Bool {
        menuBarItems.contains(id)
    }

    /// 列表拖动排序（SwiftUI List 的 onMove 直接转过来）
    package func moveMenuBarItems(from: IndexSet, to: Int) {
        menuBarItems = OrderedItems.move(menuBarItems, from: from, to: to)
    }

    /// 该条目对应的当前值，用于在菜单里给选项打勾
    package func menuBarValue(for id: String) -> Int? {
        switch id {
        case "picture_mode":        return intValue("picture_mode", default: -1)
        case "local_dimming":       return intValue("picture_local_dimming", default: -1)
        case "gamut":               return intValue("tv_picture_advanced_video_color_space", default: -1)
        case "color_temp":          return intValue("picture_color_temperature", default: -1)
        case "response_time":       return intValue("picture_response_time", default: -1)
        case "dynamic_definition":  return intValue("picture_dynamic_definition", default: -1)
        case "hdr_tone_mapping":    return intValue("settings_display_hdr_color_tone", default: -1)
        case "source":              return intValue("mitv.tvplayer.hdmi.last.source", default: -1)
        case "freesync":            return intValue("freesync", default: -1)
        case "light_sensor":        return intValue("tv_picture_light_sensor", default: -1)
        case "backlight":           return intValue("picture_backlight", default: -1)
        case "black_level":         return intValue("picture_brightness", default: -1)
        case "contrast":            return intValue("picture_contrast", default: -1)
        case "saturation":          return intValue("picture_saturation", default: -1)
        case "hue":                 return intValue("picture_hue", default: -1)
        case "sharpness":           return intValue("picture_sharpness", default: -1)
        case "light_mode":          return intValue("atmosphere_light_switcher_pm2", default: -1)
        default:                    return nil
        }
    }

    /// 从菜单栏选中一个取值
    package func applyMenuBarOption(_ id: String, value: Int) {
        guard !isPresetBusy, !presetConfiguration.applicationIncomplete else { return }
        switch id {
        case "picture_mode":        setMode(value)
        case "local_dimming":       setLocalDimming(value)
        case "gamut":               setGamut(value)
        case "color_temp":          setColorTemp(value)
        case "response_time":       setResponseTime(value)
        case "dynamic_definition":  setDynamicDefinition(value)
        case "hdr_tone_mapping":    setHdrToneMapping(value)
        case "source":              setSource(value)
        case "freesync":            setFreesync(value == 1)
        case "light_sensor":        setLightSensor(value == 1)
        case "light_mode":          setLightMode(value)
        default: break
        }
    }


    /// app 回到前台时重新查一次：用户去系统设置勾选后切回来，警告应该自动消失
}
