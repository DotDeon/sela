// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SelaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SidebarModel", targets: ["SidebarModel"]),
        .library(name: "Sidebar", targets: ["Sidebar"]),
        .library(name: "Favicons", targets: ["Favicons"]),
        .library(name: "SidebarUI", targets: ["SidebarUI"]),
        .library(name: "Archive", targets: ["Archive"]),
        .library(name: "History", targets: ["History"]),
        .library(name: "CommandBar", targets: ["CommandBar"]),
        .library(name: "ArcImport", targets: ["ArcImport"]),
        .library(name: "ArcSnapshot", targets: ["ArcSnapshot"]),
        .library(name: "BrowserImport", targets: ["BrowserImport"]),
        .library(name: "BrowserEngine", targets: ["BrowserEngine"]),
        .library(name: "FakeEngine", targets: ["FakeEngine"]),
        .library(name: "WebKitEngine", targets: ["WebKitEngine"]),
        .library(name: "Browsing", targets: ["Browsing"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "Downloads", targets: ["Downloads"]),
        .executable(name: "sela-arc", targets: ["sela-arc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AdguardTeam/SafariConverterLib", exact: "4.3.1"),
        .package(url: "https://github.com/ameshkov/swift-psl", exact: "1.1.43"),
    ],
    targets: [
        .target(name: "SidebarModel"),
        .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"]),
        .target(name: "Sidebar", dependencies: ["SidebarModel"]),
        .testTarget(name: "SidebarTests", dependencies: ["Sidebar", "SidebarModel", "SelaTestSupport"]),
        .target(name: "SelaTestSupport", dependencies: ["SidebarModel"]),
        .target(name: "Favicons"),
        .testTarget(name: "FaviconsTests", dependencies: ["Favicons"]),
        .target(name: "SidebarUI", dependencies: ["Browsing", "Sidebar", "SidebarModel", "Favicons", "BrowserEngine"]),
        .testTarget(
            name: "SidebarUITests",
            dependencies: ["SidebarUI", "Browsing", "Sidebar", "SidebarModel", "Favicons", "FakeEngine", "SelaTestSupport"]
        ),
        .target(name: "Archive", dependencies: ["Sidebar", "SidebarModel"]),
        .testTarget(name: "ArchiveTests", dependencies: ["Archive", "Sidebar", "SidebarModel", "SelaTestSupport"]),
        .target(name: "History", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "HistoryTests", dependencies: ["History"]),
        .target(name: "CommandBar", dependencies: ["Browsing", "SidebarModel", "SidebarUI"]),
        .testTarget(name: "CommandBarTests", dependencies: ["CommandBar", "Browsing", "SidebarModel"]),
        .target(name: "ArcImport", dependencies: ["SidebarModel"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(
            name: "ArcImportTests",
            dependencies: ["ArcImport", "SidebarModel"],
            resources: [.copy("Fixtures")]
        ),
        .target(name: "BrowserImport", dependencies: ["SidebarModel"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(
            name: "BrowserImportTests",
            dependencies: ["BrowserImport", "SidebarModel"],
            resources: [.copy("Fixtures")]
        ),
        .target(name: "ArcSnapshot"),
        .testTarget(name: "ArcSnapshotTests", dependencies: ["ArcSnapshot"]),
        .target(name: "BrowserEngine"),
        .target(name: "FakeEngine", dependencies: ["BrowserEngine"]),
        .testTarget(name: "FakeEngineTests", dependencies: ["FakeEngine", "BrowserEngine"]),
        .target(name: "WebKitEngine", dependencies: ["BrowserEngine"], resources: [.copy("Resources/content-blocking.js")]),
        .testTarget(name: "WebKitEngineTests", dependencies: ["WebKitEngine", "BrowserEngine"]),
        .testTarget(name: "EngineContractTests", dependencies: ["WebKitEngine", "BrowserEngine"]),
        .target(
            name: "Browsing",
            dependencies: ["BrowserEngine", "Sidebar", "SidebarModel", "Archive", "Downloads", .product(name: "PublicSuffixList", package: "swift-psl")]
        ),
        .testTarget(name: "BrowsingTests", dependencies: ["Browsing", "BrowserEngine", "FakeEngine", "Sidebar", "SidebarModel", "Archive", "Downloads", "SelaTestSupport"]),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "BrowserEngine",
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib"),
                .product(name: "PublicSuffixList", package: "swift-psl"),
            ]
        ),
        .testTarget(name: "ContentBlockingTests", dependencies: ["ContentBlocking", "BrowserEngine", "FakeEngine"]),
        .target(name: "Downloads", dependencies: ["BrowserEngine"]),
        .testTarget(name: "DownloadsTests", dependencies: ["Downloads", "BrowserEngine"]),
        .executableTarget(name: "sela-arc", dependencies: ["ArcImport", "ArcSnapshot", "SidebarModel"]),
    ]
)
