// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentUsageCore"),
        .executableTarget(name: "AgentUsage", dependencies: ["AgentUsageCore"]),
        .executableTarget(name: "AgentUsageChecks", dependencies: ["AgentUsageCore"]),
    ]
)
