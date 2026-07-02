// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ApogeeOpenAPIGenerationTools",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "update-app-store-connect-client",
            targets: ["UpdateAppStoreConnectClient"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "UpdateAppStoreConnectClient",
            path: "Sources/UpdateAppStoreConnectClient",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
