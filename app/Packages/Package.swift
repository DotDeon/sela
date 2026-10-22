// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SidebarModel", targets: ["SidebarModel"]),
        .library(name: "ArcImport", targets: ["ArcImport"]),
        .library(name: "ArcSnapshot", targets: ["ArcSnapshot"]),
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
        .target(name: "ArcSnapshot"),
        .testTarget(name: "ArcSnapshotTests", dependencies: ["ArcSnapshot"]),
    ]
)
