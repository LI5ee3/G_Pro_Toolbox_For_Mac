// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MimonitorToolbox",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ToolboxUI", targets: ["MimonitorToolbox"]),
        .library(name: "ToolboxMacAdapters", targets: ["ToolboxMacAdapters"]),
        .library(name: "ToolboxPreviewSupport", targets: ["ToolboxPreviewSupport"]),
        .executable(name: "MimonitorToolbox", targets: ["ToolboxApp"]),
        .executable(name: "ToolboxPreviewHost", targets: ["ToolboxPreviewHost"]),
    ],
    targets: [
        .target(name: "MimonitorPresetCore"),
        .target(name: "MimonitorToolbox", dependencies: ["MimonitorPresetCore"]),
        .target(name: "ToolboxMacAdapters", dependencies: ["MimonitorToolbox", "MimonitorPresetCore"]),
        .target(name: "ToolboxPreviewSupport", dependencies: ["MimonitorToolbox", "MimonitorPresetCore"]),
        .executableTarget(name: "ToolboxApp", dependencies: ["MimonitorToolbox", "ToolboxMacAdapters"]),
        .executableTarget(name: "ToolboxPreviewHost", dependencies: ["ToolboxPreviewSupport"]),
        .testTarget(name: "MimonitorPresetCoreTests", dependencies: ["MimonitorPresetCore"]),
        .testTarget(name: "MimonitorToolboxTests", dependencies: ["MimonitorToolbox", "MimonitorPresetCore", "ToolboxMacAdapters", "ToolboxPreviewSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
