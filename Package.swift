// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "LiveBundle",
    platforms: [.macOS(.v10_14), .iOS(.v14), .tvOS(.v14), .visionOS(.v26)],
    products: [
        .library( name: "LiveBundle", type: .dynamic, targets: ["LiveBundle"])
    ],
    targets: [
        .target(
            name: "LiveBundle"
        )
    ]
)
