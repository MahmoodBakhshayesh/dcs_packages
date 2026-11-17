// swift-tools-version: 5.9
// Swift Package Manager manifest for the macOS side of dcs_zebra.
// CocoaPods (../dcs_zebra.podspec) builds the same sources, so both paths stay supported.

import PackageDescription

let package = Package(
    name: "dcs_zebra",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        .library(name: "dcs-zebra", targets: ["dcs_zebra"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "dcs_zebra",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
