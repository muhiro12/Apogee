// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Apogee",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ApogeeCore",
            targets: ["ApogeeCore"]
        ),
        .executable(
            name: "apogee",
            targets: ["apogee"]
        ),
        .plugin(
            name: "ApogeeCommandPlugin",
            targets: ["ApogeeCommandPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AppStoreConnectGenerated",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .target(
            name: "ApogeeCore",
            dependencies: [
                "AppStoreConnectGenerated",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .executableTarget(
            name: "apogee",
            dependencies: [
                "ApogeeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ApogeeCLI",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .plugin(
            name: "ApogeeCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "apogee",
                    description: "Run the Apogee release automation command line tool."
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(),
                        reason: "Apogee reads and writes App Store Connect API resources."
                    ),
                ]
            ),
            dependencies: [
                "apogee",
            ]
        ),
        .testTarget(
            name: "ApogeeCoreTests",
            dependencies: [
                "ApogeeCore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            exclude: [
                "Fixtures",
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
