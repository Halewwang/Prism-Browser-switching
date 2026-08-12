// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrismNative",
    platforms: [.macOS(.v15)],
    products: [.library(name: "PrismCore", targets: ["PrismCore"])],
    targets: [
        .target(name: "PrismCore"),
        .testTarget(name: "PrismCoreTests", dependencies: ["PrismCore"])
    ]
)
