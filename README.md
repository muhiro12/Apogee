# Apogee

Apogee is a Swift Package for automating App Store release operations through
the official App Store Connect API. It provides:

- `ApogeeCore`: reusable release automation library
- `AppStoreConnectGenerated`: Swift OpenAPI Generator target for the trimmed
  App Store Connect client surface
- `ApogeeCommandPlugin`: SwiftPM command plugin for repository-pinned tool use
- `apogee`: command line tool

The package uses Swift Package Manager, Swift OpenAPI Generator, and Apple's
official App Store Connect API OpenAPI specification.

## Current Capability Status

The initial capability review is recorded in
[`docs/app-store-connect-capabilities.md`](docs/app-store-connect-capabilities.md).

Supported in the first implementation:

- Multiple-locale What's New updates
- Description, keywords, and promotional text updates
- Build attachment
- Review submission with dry-run and read-back verification
- Webhook create/update sync with read-back verification, with destructive
  deletion gated separately

Partial or unsupported:

- Screenshot upload is planned from disk but apply is disabled until the upload
  adapter safely handles reservation, binary upload, checksum commit, and
  processing verification.
- Xcode Cloud workflow sync is visible in OpenAPI but intentionally unsupported
  until Apogee has a dedicated workflow config model.

## Installation and Invocation

### SwiftPM Command Plugin

For team use, prefer adding Apogee to the app or release-tools package as a
SwiftPM dependency. This lets the repository pin the Apogee version in
`Package.resolved` and avoids relying on a globally installed local tool.

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_ORG/Apogee.git", exact: "0.1.0"),
]
```

Run Apogee through the command plugin from that package:

```sh
swift package plugin --allow-network-connections all apogee update-release-notes \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --metadata-path AppStore/Metadata \
  --dry-run
```

SwiftPM command plugins are sandboxed. Apogee talks to App Store Connect, so
plugin invocations must allow network access explicitly with
`--allow-network-connections all`.

For Apogee's top-level help, pass SwiftPM's argument separator before `--help`:

```sh
swift package plugin --allow-network-connections all apogee -- --help
```

### Direct Executable

For local exploration or a globally installed tool, run the executable directly
from an Apogee checkout:

```sh
swift run apogee --help
```

Or build and install the release binary somewhere on your `PATH`:

```sh
swift build -c release
install -m 755 .build/release/apogee /usr/local/bin/apogee
```

## Authentication

Apogee reads App Store Connect API key material from environment variables:

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="/path/to/AuthKey_YOUR_KEY_ID.p8"
```

The private key file is never stored in this repository. JWTs are signed with
ES256 and sent as bearer tokens to App Store Connect.

## Metadata Layout

```text
AppStore/Metadata/
  ja/release_notes.txt
  ja/description.txt
  ja/keywords.txt
  ja/promotional_text.txt
  en-US/release_notes.txt
  en-US/description.txt
  en-US/keywords.txt
  en-US/promotional_text.txt
```

Locales must already exist in App Store Connect. Apogee reports a missing
locale as an error instead of creating one automatically.

## Screenshot Layout

```text
AppStore/Screenshots/
  ja/APP_IPHONE_67/01.png
  ja/APP_IPHONE_67/02.png
  en-US/APP_IPHONE_67/01.png
  en-US/APP_IPHONE_67/02.png
```

`update-screenshots` currently produces a dry-run plan only. Applying screenshot
changes is explicitly unsupported until the upload adapter is implemented and
verified.

## CLI Examples

The examples below use the direct `apogee` executable. When using the SwiftPM
command plugin, replace the leading `apogee` with
`swift package plugin --allow-network-connections all apogee`.

```sh
apogee update-release-notes \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --metadata-path AppStore/Metadata \
  --dry-run

apogee update-metadata \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --metadata-path AppStore/Metadata \
  --dry-run

apogee attach-build \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --build-version 123 \
  --dry-run

apogee update-screenshots \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --screenshots-path AppStore/Screenshots \
  --dry-run

apogee submit-for-review \
  --bundle-id com.example.app \
  --version 1.2.3 \
  --dry-run

apogee sync-webhooks \
  --bundle-id com.example.app \
  --config AppStore/webhooks.json \
  --dry-run
```

Use `--app-id` when you already know the App Store Connect app id. If both
`--app-id` and `--bundle-id` are provided, `--app-id` wins.

## Dry Run and Apply

Dry-run mode is the default. `--apply` is required before Apogee mutates App
Store Connect.

For destructive operations, Apogee also requires a plan token from a prior
dry-run and `--allow-destructive`. The token is derived from the exact plan
title and action values, including current and desired values, so a changed plan
requires a fresh dry-run token. This prevents accidental deletion from a single
command invocation.

## OpenAPI Regeneration

The repository keeps the official source spec and generated-client inputs:

- `OpenAPI/AppStoreConnect/openapi.oas.json`
- `Sources/AppStoreConnectGenerated/openapi.json`
- `Sources/AppStoreConnectGenerated/openapi-generator-config.yaml`
- `Scripts/update-app-store-connect-openapi.sh`
- `Scripts/trim-app-store-connect-openapi.swift`

Regenerate the trimmed OpenAPI document with:

```sh
Scripts/update-app-store-connect-openapi.sh
```

Then build or test with SwiftPM:

```sh
swift build
swift test
```
