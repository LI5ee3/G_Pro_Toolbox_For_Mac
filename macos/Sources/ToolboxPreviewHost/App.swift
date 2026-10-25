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
        Settings { ToolboxPreviewSettingsContent(selection: selection) }
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
    }
}
