// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExampleReleaseTools",
    platforms: [.macOS(.v15)],
    dependencies: [
        // When adopting, replace this with the repository URL and an exact published tag.
        .package(path: "../.."),
        // Required only for the explicit transport integration example.
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ReleaseToolsExample",
            dependencies: [
                .product(name: "ApogeeCore", package: "Apogee"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),
    ]
)
