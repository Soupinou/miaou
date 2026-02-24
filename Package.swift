// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Miaou",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Miaou",
            path: "Miaou",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
