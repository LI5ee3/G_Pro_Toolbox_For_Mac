import SwiftUI
import AppKit
import ToolboxPreviewSupport

@main
struct ToolboxPreviewHostApp: App {
    var body: some Scene {
        Window("S3-03 控制工作区 · 安全 Preview", id: "preview") { ToolboxPreviewGallery().onAppear { NSApp.activate() } }
            .defaultSize(width: 1120, height: 820)
            .restorationBehavior(.disabled)
    }
}
