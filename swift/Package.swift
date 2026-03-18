// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMerge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacMerge",
            path: "Sources/MacMerge",
            resources: [
                .copy("Resources/icon.icns")
            ]
        )
    ]
)
