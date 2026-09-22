// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DreamTravel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DreamTravelApp", targets: ["DreamTravelApp"])
    ],
    targets: [
        .executableTarget(
            name: "DreamTravelApp",
            path: "Sources/DreamTravelApp",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("MapKit"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
