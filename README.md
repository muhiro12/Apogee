# Apogee

Apogee is a Swift Package for automating App Store release operations through
the official App Store Connect API. It provides:

- `ApogeeCore`: reusable release automation library
- `AppStoreConnectGenerated`: committed Swift OpenAPI Generator output for the
  App Store Connect client surface Apogee uses
- `ApogeeCommandPlugin`: SwiftPM command plugin for repository-pinned tool use
- `apogee`: command line tool

The package uses Swift Package Manager and committed Swift client sources
generated from Apple's official App Store Connect API OpenAPI specification.

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
SwiftPM dependency after publishing a release tag. This lets the repository pin
the Apogee version in `Package.resolved` and avoids relying on a globally
installed local tool.

```swift
dependencies: [
    .package(url: "https://github.com/muhiro12/Apogee.git", exact: "<release-tag>"),
]
```

Replace `<release-tag>` with the GitHub Release tag your repository should pin,
such as the first public release tag `1.0.0`.

Run Apogee through the command plugin from that package:

```sh
swift package plugin --allow-network-connections all apogee update-release-notes \
  --version 1.2.3 \
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

Apogee keeps repository-safe defaults in a root `apogee.json` file and reads
App Store Connect API key material from environment variables.

Minimal `apogee.json`:

```json
{
  "bundleID": "com.example.app"
}
```

Commit this file when it contains only non-secret identifiers and paths. When
paths are omitted, Apogee uses these repository layout defaults:

```json
{
  "metadataPath": "AppStore/Metadata",
  "screenshotsPath": "AppStore/Screenshots",
  "webhooksPath": "AppStore/webhooks.json"
}
```

`defaultPlatform` is optional and defaults to `IOS`. CLI options such as
`--app-id`, `--bundle-id`, `--metadata-path`, `--screenshots-path`, `--config`,
and `--platform` override values from the configuration file. Use
`--apogee-config` to point at a different JSON file.

For local use, point Apogee at a private key file outside the repository:

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="/path/to/AuthKey_YOUR_KEY_ID.p8"
```

For CI, store the private key PEM as a secret and expose it as base64 text:

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_BASE64="BASE64_ENCODED_P8_CONTENTS"
```

`ASC_PRIVATE_KEY_BASE64` takes priority over `ASC_PRIVATE_KEY_PATH` when both
are present. Private keys are never stored in the repository. JWTs are signed
with ES256 and sent as bearer tokens to App Store Connect.

Plans and command output must not include private key material, JWT bearer
tokens, or webhook secret values. Webhook plans may include the secret
environment variable name so dry-runs remain reviewable without exposing the
secret itself.

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
  --version 1.2.3 \
  --dry-run

apogee update-metadata \
  --version 1.2.3 \
  --dry-run

apogee attach-build \
  --version 1.2.3 \
  --build-version 123 \
  --dry-run

apogee update-screenshots \
  --version 1.2.3 \
  --dry-run

apogee submit-for-review \
  --version 1.2.3 \
  --dry-run

apogee sync-webhooks \
  --dry-run
```

These examples assume root `apogee.json` provides the app lookup. The
`AppStore/Metadata`, `AppStore/Screenshots`, and `AppStore/webhooks.json` paths
are used by default unless overridden. Use `--app-id` when you already know the
App Store Connect app id. If both `--app-id` and `--bundle-id` are provided,
`--app-id` wins.

## Dry Run and Apply

Dry-run mode is the default. A dry run still authenticates to App Store Connect,
reads the current remote state, compares it with repository files or command
inputs, and prints the plan that `--apply` would attempt. It does not create,
update, submit, or delete resources.

`--apply` is required before Apogee mutates App Store Connect. Apply operations
perform read-back verification when the operation supports a safe verification
path.

For destructive operations, Apogee also requires a plan token from a prior
dry-run and `--allow-destructive`. The token is derived from the exact plan
title and action values, including current and desired values, so a changed plan
requires a fresh dry-run token. This prevents accidental deletion from a single
command invocation.

## Versioning and Stability

Apogee starts at `1.0.0` and follows semantic versioning for its documented
package products, CLI commands and options, configuration keys, default
repository layout, and release-safety behavior. New commands, options,
configuration keys, and supported App Store Connect operations can be added in
minor releases when they are backward-compatible. Renaming or removing existing
public surfaces, changing documented defaults, or weakening the dry-run/apply
safety model requires a new major version.

The Git tag and GitHub Release are the package version source of truth. Avoid
adding a separate checked-in source version string or README "current version"
value that release automation must keep in sync with tags.

Apogee's minimum Swift tools version tracks the Swift version bundled with the
first official release of the Xcode major series that Apogee supports. The
initial public baseline is Xcode 26.0 / Swift tools 6.2. Later Xcode point
releases can build the package, but the public SwiftPM manifests should not move
to a later tools version unless Apogee intentionally raises its supported Xcode
major baseline.

The safety contract is intentionally more stable than any individual
capability: dry-run remains the default, `--apply` is required for every App
Store Connect mutation, destructive operations require a prior plan token plus
`--allow-destructive`, and operations without a safe verification path must fail
closed or remain unsupported.

## Maintainer OpenAPI Update

Apogee does not redistribute Apple's App Store Connect OpenAPI document.
Maintainers download it from Apple and update the committed generated Swift
client sources with:

```sh
swift run --package-path Tools/OpenAPIGeneration update-app-store-connect-client
```

The maintainer tool writes temporary OpenAPI files under `.build/` and copies
only the generated Swift sources into `Sources/AppStoreConnectGenerated/GeneratedSources/`.
See [`docs/openapi-generation.md`](docs/openapi-generation.md) for the current
generation baseline.

Build or test with SwiftPM:

```sh
swift build
swift test
```
