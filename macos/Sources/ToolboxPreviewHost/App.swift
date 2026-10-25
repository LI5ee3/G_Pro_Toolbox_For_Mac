import SwiftUI
import AppKit
import ToolboxPreviewSupport
import MimonitorToolbox

@main
struct ToolboxPreviewHostApp: App {
    var body: some Scene {
        Window("S3-06 键盘与焦点 · 安全 Preview", id: "preview") { ToolboxPreviewGallery().onAppear { NSApp.activate() } }
            .defaultSize(width: 1120, height: 820)
            .restorationBehavior(.disabled)
            .commands { ToolboxSettingsCommands() }
    }
}
