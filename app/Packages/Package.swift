// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SidebarModel", targets: ["SidebarModel"]),
        .library(name: "Sidebar", targets: ["Sidebar"]),
        .library(name: "Favicons", targets: ["Favicons"]),
        .library(name: "SidebarUI", targets: ["SidebarUI"]),
        .library(name: "ArcImport", targets: ["ArcImport"]),
        .library(name: "ArcSnapshot", targets: ["ArcSnapshot"]),
        .library(name: "BrowserEngine", targets: ["BrowserEngine"]),
        .library(name: "FakeEngine", targets: ["FakeEngine"]),
        .library(name: "WebKitEngine", targets: ["WebKitEngine"]),
        .library(name: "Browsing", targets: ["Browsing"]),
        .executable(name: "brow-arc", targets: ["brow-arc"]),
    ],
    targets: [
        .target(name: "SidebarModel"),
        .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"]),
        .target(name: "Sidebar", dependencies: ["SidebarModel"]),
        .testTarget(name: "SidebarTests", dependencies: ["Sidebar", "SidebarModel", "BrowTestSupport"]),
        .target(name: "BrowTestSupport", dependencies: ["SidebarModel"]),
        .target(name: "Favicons"),
        .testTarget(name: "FaviconsTests", dependencies: ["Favicons"]),
        .target(name: "SidebarUI", dependencies: ["Browsing", "Sidebar", "SidebarModel", "Favicons", "BrowserEngine"]),
        .testTarget(
            name: "SidebarUITests",
            dependencies: ["SidebarUI", "Browsing", "Sidebar", "SidebarModel", "Favicons", "FakeEngine", "BrowTestSupport"]
        ),
        .target(name: "ArcImport", dependencies: ["SidebarModel"]),
        .testTarget(
            name: "ArcImportTests",
            dependencies: ["ArcImport", "SidebarModel"],
            resources: [.copy("Fixtures")]
        ),
        .target(name: "ArcSnapshot"),
        .testTarget(name: "ArcSnapshotTests", dependencies: ["ArcSnapshot"]),
        .target(name: "BrowserEngine"),
        .target(name: "FakeEngine", dependencies: ["BrowserEngine"]),
        .testTarget(name: "FakeEngineTests", dependencies: ["FakeEngine", "BrowserEngine"]),
        .target(name: "WebKitEngine", dependencies: ["BrowserEngine"]),
        .testTarget(name: "WebKitEngineTests", dependencies: ["WebKitEngine", "BrowserEngine"]),
        .testTarget(name: "EngineContractTests", dependencies: ["WebKitEngine", "BrowserEngine"]),
        .target(name: "Browsing", dependencies: ["BrowserEngine", "Sidebar", "SidebarModel"]),
        .testTarget(name: "BrowsingTests", dependencies: ["Browsing", "BrowserEngine", "FakeEngine", "Sidebar", "SidebarModel", "BrowTestSupport"]),
        .executableTarget(name: "brow-arc", dependencies: ["ArcImport", "ArcSnapshot", "SidebarModel"]),
    ]
)
