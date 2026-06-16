// swift-tools-version: 6.0
import PackageDescription

// Local package vendoring Open Vibe Island's agent-monitoring engine into Atoll.
// Only the UI-agnostic pieces are pulled in: OpenIslandCore (models, bridge
// transport, hook installers, session registry) and the OpenIslandHooks CLI
// that agents invoke. The OpenIslandApp/Setup targets and their MarkdownUI /
// Sparkle dependencies are intentionally dropped — Atoll provides its own UI.
let package = Package(
    name: "OpenIslandEngine",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenIslandCore",
            targets: ["OpenIslandCore"]
        ),
        .library(
            name: "VibeIslandAgentKit",
            targets: ["VibeIslandAgentKit"]
        ),
        .executable(
            name: "OpenIslandHooks",
            targets: ["OpenIslandHooks"]
        ),
    ],
    targets: [
        .target(
            name: "OpenIslandCore"
        ),
        // Atoll-specific glue over the vendored engine: namespacing, Claude
        // session filtering, and hook installation. Keeps the upstream
        // OpenIslandCore sources untouched for easy updates.
        .target(
            name: "VibeIslandAgentKit",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandHooks",
            dependencies: ["OpenIslandCore"]
        ),
        .testTarget(
            name: "VibeIslandAgentKitTests",
            dependencies: ["VibeIslandAgentKit", "OpenIslandCore"]
        ),
    ]
)
