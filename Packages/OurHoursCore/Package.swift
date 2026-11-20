// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OurHoursCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "OurHoursCore",
            targets: ["OurHoursCore"]
        )
    ],
    targets: [
        .target(
            name: "OurHoursCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OurHoursCoreTests",
            dependencies: ["OurHoursCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
