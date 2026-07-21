// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XSpoonMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "XSpoonMenu", targets: ["XSpoonMenu"])
    ],
    targets: [
        .executableTarget(
            name: "XSpoonMenu",
            path: ".",
            exclude: ["Package.swift", "README.md", "WAYFINDER.md", "2026-07-13_XSPOON_LIVE_OVERLAY_FINDINGS.md", "script", ".codex", "dist"],
            resources: [.process("Resources")]
        )
    ]
)
