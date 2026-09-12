// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExampleReleaseTools",
    platforms: [.macOS(.v15)],
    dependencies: [
        // When adopting, replace this with the repository URL and an exact published tag.
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "ReleaseToolsExample",
            dependencies: [.product(name: "ApogeeCore", package: "Apogee")]
        ),
    ]
)
