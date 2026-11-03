// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoundaryLabeling",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "BoundaryLabeling", targets: ["BoundaryLabeling"]),
    ],
    targets: [
        .target(name: "BoundaryLabeling"),
        .testTarget(
            name: "BoundaryLabelingTests",
            dependencies: ["BoundaryLabeling"]
        ),
    ]
)
