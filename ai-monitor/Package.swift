// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AINewsWatch",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AINewsWatch",
            targets: ["AINewsWatch"]
        )
    ],
    targets: [
        .target(
            name: "AINewsWatch",
            path: "Sources"
        ),
        .testTarget(
            name: "AINewsWatchTests",
            dependencies: ["AINewsWatch"]
        )
    ]
)
