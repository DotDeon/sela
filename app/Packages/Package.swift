// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SidebarModel", targets: ["SidebarModel"]),
        .library(name: "ArcImport", targets: ["ArcImport"]),
    ],
    targets: [
        .target(name: "SidebarModel"),
        .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"]),
        .target(name: "ArcImport", dependencies: ["SidebarModel"]),
        .testTarget(
            name: "ArcImportTests",
            dependencies: ["ArcImport", "SidebarModel"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
