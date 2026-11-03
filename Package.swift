// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Unmouse",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Unmouse", targets: ["Unmouse"]),
        .library(name: "UnmouseCore", targets: ["UnmouseCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "UnmouseCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/UnmouseCore",
            resources: [
                .copy("Resources"),
            ]
        ),
        .executableTarget(
            name: "Unmouse",
            dependencies: ["UnmouseCore"],
            path: "Sources/Unmouse",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "UnmouseCoreTests",
            dependencies: ["UnmouseCore"],
            path: "Tests/UnmouseCoreTests",
            resources: [
                .copy("Fixtures/configs-example"),
            ]
        ),
    ]
)
