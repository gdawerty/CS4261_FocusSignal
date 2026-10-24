// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusSignalCore",
    platforms: [.iOS("17.4"), .macOS(.v13)],
    products: [.library(name: "FocusSignalCore", targets: ["FocusSignalCore"])],
    targets: [
        .target(name: "FocusSignalCore"),
        .testTarget(name: "FocusSignalCoreTests", dependencies: ["FocusSignalCore"])
    ]
)
