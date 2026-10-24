import SwiftUI
import AppKit
import ToolboxPreviewSupport

@main
struct ToolboxPreviewHostApp: App {
    var body: some Scene {
        Window("S3-01 设计提案 · 安全 Preview", id: "preview") { ToolboxS301Gallery().onAppear { NSApp.activate() } }
            .defaultSize(width: 1120, height: 820)
            .restorationBehavior(.disabled)
    }
}
