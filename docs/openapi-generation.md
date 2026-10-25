# OpenAPI Generation

Apogee uses Swift source generated from Apple's App Store Connect API OpenAPI
specification, but the Apple OpenAPI document itself is not redistributed in
this repository.

Maintainers update the generated client by running:

```sh
swift run --package-path Tools/OpenAPIGeneration update-app-store-connect-client
```

The updater is a separate maintainer-only Swift package under
`Tools/OpenAPIGeneration`. The root Apogee package does not depend on Swift
OpenAPI Generator during normal package resolution or builds.

The maintainer package follows Apogee's public Swift tools baseline unless the
generator itself requires a newer version. If that happens, the higher
requirement should stay isolated to maintainer-only tooling.

The tool downloads the current Apple OpenAPI zip, trims it to the operations
Apogee uses, creates a temporary Swift package under `.build/`, resolves and
runs Swift OpenAPI Generator from that temporary package, and copies only the
generated Swift sources into `Sources/AppStoreConnectGenerated/GeneratedSources/`.

Generated declarations use `accessModifier: package`: only targets in Apogee can
use them. The supported consumer boundary is `ApogeeCore`. Change generation
configuration and rerun this tool instead of editing generated Swift directly.
For a reproducible configuration-only update, use `--spec-url file:///.../spec.zip`
with a locally retained baseline archive. Keep the archive and extracted JSON
outside source control, and compare the reported SHA-256 before accepting output.

The updater fails closed when the archive or extracted specification exceeds its
resource limits. Downloads and individual JSON documents are limited to 64 MiB,
archive listings to 1 MiB, candidate JSON entries to 16, and JSON traversal to
128 nested levels. These limits are intentionally above the current Apple
specification while preventing an alternate or compromised archive from
consuming unbounded maintainer or CI resources.

The trim step keeps only the operations called by the production adapter and
their transitive referenced schemas. Unused resource endpoints are not generated
speculatively; add an operation when its
adapter implementation and verification require it.
`appStoreVersions_createInstance` is retained for explicit manual-release version
creation; the adapter does not use its optional metadata or build relationships.
`appStoreVersions_updateInstance` supports explicit version settings; only copyright,
release type, and a scheduled date are sent, never build relationships or other
attributes.

The two app-scoped beta feedback collection operations support read-only
candidate-build inspection; feedback deletion is not generated. Screenshot feedback
carries its image locations in those collection responses, so exporting screenshots
needs no further operation. `betaFeedbackCrashSubmissions_crashLog_getToOneRelated`
reads one crash log's text for the explicit export destination; the linkage-only
relationship read is not generated because that related read already reports a
confirmed absence.

Screenshot operations cover only standard version localizations, individual assets,
and ordering. Binary upload requests use the returned operations through a separate
credential-free transport; they are not App Store Connect API calls.

The trim step removes OpenAPI
`deprecated` markers from the generator input. Swift OpenAPI Generator currently
turns those markers into Swift deprecation annotations that are then referenced
inside generated initializers, producing noisy build warnings for package users.

The generated Swift sources are committed so package users do not need to fetch
Apple's OpenAPI document or run the generator during normal `swift build`.

Current generation baseline:

- Source URL: `https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip`
- Download checked: `2026-10-25`
- App Store Connect API version in spec: `4.5.1`
- Swift OpenAPI Generator version: `1.12.2`
- Specification SHA-256: `7518d3a94a8bd701ac25c1c601b95b8f53aad92091affb15a2a9d331713dac1a`

Asset Library operations include reference data, the app's library, image
reservation/read/commit, scoped localization placements, placement creation and
removal, and ordering. Image deletion is deliberately absent because images can
be shared across surfaces. Legacy screenshot operations remain generated only
for Apogee's existing low-level public API; production automation uses the new
operations and never falls back to the legacy endpoints.

For generator 1.12.2, the trimmer distributes common object properties into
`anyOf` request alternatives so required-only constraints keep their fields.
It also decodes placement relationships by their required image/video key:
the source schema's nested `mediaType` discriminator refers to an attribute
outside the relationships object. The adapter separately validates media type
and parent scope. Regression coverage checks normalized constraints and actual
request/response encoding; generated Swift is never patched by hand.
