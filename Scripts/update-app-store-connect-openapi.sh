#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_DIR="$ROOT_DIR/OpenAPI/AppStoreConnect"
SPEC_JSON="$SPEC_DIR/openapi.oas.json"
SPEC_URL="https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip"
SPEC_ZIP="$(mktemp -t apogee-app-store-connect-openapi.XXXXXX.zip)"

mkdir -p "$SPEC_DIR"
trap 'rm -f "$SPEC_ZIP"' EXIT

curl -L "$SPEC_URL" -o "$SPEC_ZIP"
unzip -o "$SPEC_ZIP" openapi.oas.json -d "$SPEC_DIR"
swift "$ROOT_DIR/Scripts/trim-app-store-connect-openapi.swift" "$SPEC_JSON" "$ROOT_DIR/Sources/AppStoreConnectGenerated/openapi.json"
