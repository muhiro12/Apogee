#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/apogee-openapi-generation"
PACKAGE_DIR="$WORK_DIR/GeneratorPackage"
TARGET_DIR="$PACKAGE_DIR/Sources/GeneratedClient"
GENERATED_DIR="$TARGET_DIR/GeneratedSources"
OUTPUT_DIR="$ROOT_DIR/Sources/AppStoreConnectGenerated/GeneratedSources"
SPEC_JSON="$WORK_DIR/openapi.oas.json"
TRIMMED_JSON="$TARGET_DIR/openapi.json"
SPEC_ZIP="$(mktemp -t apogee-app-store-connect-openapi.XXXXXX.zip)"

SPEC_URL="https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip"
GENERATOR_VERSION="${APOGEE_OPENAPI_GENERATOR_VERSION:-1.12.2}"

trap 'rm -f "$SPEC_ZIP"' EXIT

mkdir -p "$TARGET_DIR" "$OUTPUT_DIR"
printf '// Temporary target for Swift OpenAPI Generator.\n' > "$TARGET_DIR/Placeholder.swift"

curl -fL "$SPEC_URL" -o "$SPEC_ZIP"
unzip -p "$SPEC_ZIP" openapi.oas.json > "$SPEC_JSON"
swift "$ROOT_DIR/Scripts/trim-app-store-connect-openapi.swift" "$SPEC_JSON" "$TRIMMED_JSON"
cp "$ROOT_DIR/Scripts/OpenAPIGeneration/openapi-generator-config.yaml" "$TARGET_DIR/openapi-generator-config.yaml"

cat > "$PACKAGE_DIR/Package.swift" <<PACKAGE
// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ApogeeOpenAPIGeneration",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "$GENERATOR_VERSION"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "GeneratedClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),
    ]
)
PACKAGE

(
    cd "$PACKAGE_DIR"
    swift package plugin --allow-writing-to-package-directory generate-code-from-openapi --target GeneratedClient
)

cp "$GENERATED_DIR/Client.swift" "$OUTPUT_DIR/Client.swift"
cp "$GENERATED_DIR/Types.swift" "$OUTPUT_DIR/Types.swift"
rm -f "$OUTPUT_DIR/Server.swift"

echo "Updated generated App Store Connect client sources."
echo "Spec SHA-256: $(shasum -a 256 "$SPEC_JSON" | awk '{print $1}')"
