// swift-tools-version: 6.2

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
        .target(
            name: "OpenAPIGenerationSupport",
            path: "Sources/OpenAPIGenerationSupport",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .executableTarget(
            name: "UpdateAppStoreConnectClient",
            dependencies: [
                "OpenAPIGenerationSupport",
            ],
            path: "Sources/UpdateAppStoreConnectClient",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "OpenAPIGenerationSupportTests",
            dependencies: [
                "OpenAPIGenerationSupport",
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
