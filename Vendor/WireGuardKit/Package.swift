// swift-tools-version:5.5
// Vendored from https://github.com/amnezia-vpn/amneziawg-apple (v3.1.5), MIT licensed.
// Trimmed to the AmneziaWG engine only (no XRay). libwg-go.a is produced by the
// WireGuardGoBridge* targets in project.yml and found through BUILT_PRODUCTS_DIR.

import PackageDescription

let package = Package(
    name: "WireGuardKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "WireGuardKit", targets: ["WireGuardKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WireGuardKit",
            dependencies: ["WireGuardKitGo", "WireGuardKitC"]
        ),
        .target(
            name: "WireGuardKitC",
            dependencies: [],
            publicHeadersPath: "."
        ),
        .target(
            name: "WireGuardKitGo",
            dependencies: [],
            exclude: [
                "goruntime-boottime-over-monotonic.diff",
                "go.mod",
                "go.sum",
                "api-apple.go",
                "Makefile"
            ],
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedLibrary("wg-go"),
                .linkedLibrary("resolv")
            ]
        )
    ]
)
