// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "AIUsageBar",
            targets: ["AIUsageBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AIUsageBar",
            path: "Sources/AIUsageBar",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AIUsageBar/Resources/Info.plist",
                ]),
            ]
        ),
    ]
)
