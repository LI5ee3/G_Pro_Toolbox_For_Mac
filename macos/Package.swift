// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MimonitorToolbox",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "MimonitorPresetCore", path: "Sources/MimonitorPresetCore"),
        .executableTarget(name: "MimonitorToolbox", dependencies: ["MimonitorPresetCore"],
                          path: "Sources/MimonitorToolbox"),
        .testTarget(name: "MimonitorPresetCoreTests", dependencies: ["MimonitorPresetCore"],
                    path: "Tests/MimonitorPresetCoreTests"),
        .testTarget(name: "MimonitorToolboxTests", dependencies: ["MimonitorToolbox", "MimonitorPresetCore"],
                    path: "Tests/MimonitorToolboxTests"),
    ]
)
