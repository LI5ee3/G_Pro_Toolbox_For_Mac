import SwiftUI
import AppKit
import ToolboxPreviewSupport
import MimonitorToolbox

@main
struct ToolboxPreviewHostApp: App {
    @State private var selection = ToolboxPreviewSelection()
    var body: some Scene {
        Window("S3-07 视觉覆盖 · 安全 Preview", id: "preview") {
            ToolboxPreviewGallery(selection: selection).onAppear { NSApp.activate() }
        }
            .defaultSize(width: 1120, height: 820)
            .restorationBehavior(.disabled)
            .commands { ToolboxSettingsCommands() }
        MenuBarExtra("调节提示 · 安全预览", systemImage: "display") {
            Button("显示音量提示") { HUDWindow.shared.show(title: "音量", value: "50") }
        }
    }
}
