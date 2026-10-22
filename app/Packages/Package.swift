// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SidebarModel", targets: ["SidebarModel"]),
    ],
    targets: [
        .target(name: "SidebarModel"),
        .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"]),
    ]
)
