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
        .package(path: "Packages/BoundaryLabeling"),
    ],
    targets: [
        .target(
            name: "UnmouseCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
                "BoundaryLabeling",
            ],
            path: "Sources/UnmouseCore",
            resources: [
                .process("Hint/priority-words.txt"),
            ]
        ),
        .executableTarget(
            name: "Unmouse",
            dependencies: ["UnmouseCore"],
            path: "Sources/Unmouse",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "UnmouseCoreTests",
            dependencies: ["UnmouseCore"],
            path: "Tests/UnmouseCoreTests"
        ),
    ]
)
