// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SmartClipBoard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SmartClipBoard",
            path: "Sources/SmartClipBoard"
        )
    ]
)
