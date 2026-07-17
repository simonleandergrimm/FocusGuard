// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusGuardCore", targets: ["FocusGuardCore"]),
        .executable(name: "FocusGuardApp", targets: ["FocusGuardApp"]),
        .executable(name: "FocusGuardHelper", targets: ["FocusGuardHelper"]),
    ],
    targets: [
        .target(name: "FocusGuardCore"),
        .executableTarget(
            name: "FocusGuardApp",
            dependencies: ["FocusGuardCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "FocusGuardHelper",
            dependencies: ["FocusGuardCore"],
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .testTarget(
            name: "FocusGuardCoreTests",
            dependencies: ["FocusGuardCore"]
        ),
    ]
)
