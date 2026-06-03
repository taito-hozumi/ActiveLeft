// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ActiveLeft",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ActiveLeft", targets: ["ActiveLeft"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ActiveLeft",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
