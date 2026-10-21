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
        .target(name: "MimonitorPresetCore", dependencies: ["ToolboxDomain"]),
        .target(name: "ToolboxConcurrency", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "ToolboxProcessExecution", dependencies: ["ToolboxConcurrency"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "ToolboxDomain", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "ToolboxApplication", dependencies: ["ToolboxDomain", "MimonitorPresetCore", "ToolboxConcurrency"]),
        .target(name: "MimonitorToolbox", dependencies: ["ToolboxApplication", "ToolboxDomain", "MimonitorPresetCore"]),
        .target(name: "ToolboxMacAdapters", dependencies: ["ToolboxProcessExecution", "ToolboxConcurrency", "ToolboxApplication", "ToolboxDomain", "MimonitorPresetCore"]),
        .target(name: "ToolboxPreviewSupport", dependencies: ["ToolboxConcurrency","MimonitorToolbox", "ToolboxApplication", "ToolboxDomain", "MimonitorPresetCore"]),
        .executableTarget(name: "ToolboxApp", dependencies: ["MimonitorToolbox", "ToolboxMacAdapters"]),
        .executableTarget(name: "ToolboxPreviewHost", dependencies: ["ToolboxPreviewSupport"]),
        .testTarget(name: "MimonitorPresetCoreTests", dependencies: ["MimonitorPresetCore"]),
        .testTarget(name: "MimonitorToolboxTests", dependencies: ["ToolboxConcurrency", "ToolboxProcessExecution","MimonitorToolbox", "ToolboxApplication", "ToolboxDomain", "MimonitorPresetCore", "ToolboxMacAdapters", "ToolboxPreviewSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
