import SwiftUI
import ToolboxPreviewSupport

@main
struct ToolboxPreviewHostApp: App {
    var body: some Scene {
        Window("ToolBox 安全预览", id: "preview") { ToolboxPreviewGallery() }
            .defaultSize(width: 1120, height: 880)
    }
}
