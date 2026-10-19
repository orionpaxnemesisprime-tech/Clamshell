// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ClamshellCore",
    platforms: [
        .iOS("27.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "ClamshellCore", targets: ["ClamshellCore"]),
        // macOS tool that verifies homebrew for the Find Homebrew catalog.
        .executable(name: "clamshell-catalog", targets: ["CatalogTool"]),
    ],
    targets: [
        // melonDS + C facade, produced by Scripts/build-core.sh (not checked in).
        .binaryTarget(
            name: "ClamshellBridge",
            path: "Artifacts/ClamshellBridge.xcframework"
        ),
        .target(
            name: "ClamshellCore",
            dependencies: ["ClamshellBridge"],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .executableTarget(
            name: "CatalogTool",
            dependencies: ["ClamshellCore"]
        ),
        .testTarget(
            name: "ClamshellCoreTests",
            dependencies: ["ClamshellCore"],
            resources: [.copy("ROMs")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
