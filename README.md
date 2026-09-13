# Apogee

Apogee is a Swift Package for automating App Store release operations through
the official App Store Connect API. It provides:

- `ApogeeCore`: reusable release automation library
- `ApogeeCommandPlugin`: SwiftPM command plugin for repository-pinned tool use
- `apogee`: command line tool

The package uses Swift Package Manager and committed Swift client sources
generated from Apple's official App Store Connect API OpenAPI specification.

Apogee runs on macOS; an iOS app does not link it at runtime. See the
[adoption guide](docs/adoption.md) for introducing it alongside an existing
release process, and the [consumer example](Examples/ReleaseTools) for a runnable
library and command-plugin integration.

See the [public API contract](docs/public-api.md) for supported and provisional
surfaces, migration notes, and how to build the DocC reference. The generated
`AppStoreConnectGenerated` target is package-scoped implementation, not a consumer
product. Use `ApogeeCore` to access supported operations.

## Current Capability Status

The initial capability review is recorded in
[`docs/app-store-connect-capabilities.md`](docs/app-store-connect-capabilities.md).

Supported in the first implementation:

- Read-only release status, including publication timing and review state
- Offline metadata validation without API credentials
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

Prefer adding Apogee to a dedicated macOS release-tools package as a
SwiftPM dependency after publishing a release tag. This lets the repository pin
the Apogee version in `Package.resolved` and avoids relying on a globally
installed local tool.

```swift
dependencies: [
    .package(url: "https://github.com/muhiro12/Apogee.git", exact: "<release-tag>"),
]
```

Replace `<release-tag>` with the GitHub Release tag your repository should pin,
after that tag is published. Use the local consumer example before publication;
a version mentioned in documentation is not evidence that a tag exists.

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
The current authentication flow requires a **team API key** and its issuer ID;
individual API keys are not supported. See Apple's
[API key setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).

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

Relative configured paths and omitted layout defaults resolve beside the loaded
JSON file. Explicit CLI path overrides resolve from the working directory. The
plugin uses the consumer package directory as its working directory.

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
apogee validate-metadata --release-notes-only

apogee release-status --version 1.2.3

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

Release tags and titles use `major.minor` when the patch is zero, such as `1.0`,
and `major.minor.patch` for a nonzero patch, such as `1.0.1`, without a `v` prefix.
The omitted patch means zero for semantic version ordering. Before `1.0`, public
interfaces may change between minor versions; review the release notes and pin
an exact version. Starting with `1.0`, Apogee follows semantic versioning for
its documented package products, CLI commands and options, configuration keys,
default repository layout, and release-safety behavior. New commands, options,
configuration keys, and supported App Store Connect operations can be added in
minor releases when they are backward-compatible. Renaming or removing existing
public surfaces, changing documented defaults, or weakening the dry-run/apply
safety model requires a new major version.

SwiftPM accepts these short Git tags but requires three components in manifest
version requirements: use `exact: "1.0.0"` to consume tag `1.0`. Its generated
`Package.resolved` also records the normalized `1.0.0` version. Keep those
machine-readable versions intact; the public tag and release title remain `1.0`.

The Git tag and GitHub Release are the package version source of truth. Avoid
adding a separate checked-in source version string or README "current version"
value that release automation must keep in sync with tags.

The [Release workflow](.github/workflows/release.yml) verifies `main` with the
same checks as pull requests before publishing. The first release requires an
explicit version, which can be supplied through
**Actions → Release → Run workflow** on `main`.
After that, a push to `main` automatically increments the minor version and
omits the zero patch, such as `1.0` or `1.0.1` to `1.1`. To select a major or patch
version for a push, add a `Release-Version: 2.0` or `Release-Version: 1.0.1`
trailer to that push's final commit message. Select the major version before
merging a breaking change to `main`. A manually dispatched version takes
precedence over the trailer.
Explicit zero-patch inputs such as `2.0.0` are normalized to `2.0`. Legacy
three-component tags are still recognized when ordering versions; conflicting
short and zero-patch aliases fail rather than changing a published revision.
Rerunning a completed release reuses its tag. Releases contain source archives;
the workflow does not upload compiled binaries or contact App Store Connect.

For documentation or release-automation maintenance that should not publish a
package, use a `Release-Version: none` commit trailer or dispatch with version
`none`. All CI checks still run, but no tag or release is created or changed.

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

## Licensing and Third-Party Software

Apogee does not grant a license for its original source code. Public visibility
does not grant general permission to reuse or redistribute that code.
Third-party components retain their own licenses; see the
[dependency license inventory](docs/third-party-software.md).

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

The full local verification contract, including maintainer-tool tests, CLI smoke
checks, and a separate consumer build, is documented in [AGENTS.md](AGENTS.md).
CI and dependency alert ownership are documented in
[dependency maintenance](docs/dependency-maintenance.md).
