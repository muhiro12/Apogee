# App Store Connect OpenAPI Capability Matrix

Apogee is based on Apple's official App Store Connect API OpenAPI
specification.

- Source: `https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip`
- Download checked: `2026-07-02`
- Apple artifact timestamp: `2026-06-13 07:24` in the zip, with HTTP `Last-Modified: 2026-06-12 22:26:57 GMT`
- Apple OpenAPI document inside the downloaded zip: `openapi.oas.json`
- OpenAPI version: `3.0.1`
- App Store Connect API version in spec: `4.4`

The full spec contains 929 paths and 1346 schemas. Apogee does not redistribute
Apple's OpenAPI document. Maintainers download it locally and commit only the
generated Swift client sources needed by the first CLI surface.

## Capability Matrix

| Capability | Status | OpenAPI evidence | Apogee behavior |
| --- | --- | --- | --- |
| Multiple-locale What's New updates | Supported | `GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations`, `PATCH /v1/appStoreVersionLocalizations/{id}`, `AppStoreVersionLocalizationUpdateRequest.attributes.whatsNew` | Reads local `release_notes.txt`, compares with existing ASC localizations, updates existing locales only, and verifies by reading back after `--apply`. |
| Description, keywords, promotional text updates | Supported | `AppStoreVersionLocalizationUpdateRequest.attributes.description`, `keywords`, and `promotionalText` | Reads `description.txt`, `keywords.txt`, and `promotional_text.txt`, compares with existing ASC localizations, updates existing locales only, and verifies by reading back after `--apply`. |
| Build attachment | Supported | `GET /v1/builds` with `filter[app]`, `filter[version]`, and `filter[preReleaseVersion.version]`; `PATCH /v1/appStoreVersions/{id}/relationships/build` | Resolves the target build by app, build version, platform, and target App Store marketing version, attaches it to the target App Store version, and verifies the relationship after `--apply`. |
| Screenshot updates | Partially supported | `appScreenshotSets` and `appScreenshots` resources exist; Apple asset upload requires reservation, time-limited upload operations, checksum commit, and asynchronous processing verification | Apogee can read and plan screenshot layouts from disk. Apply is initially `UnsupportedCapability.screenshotUpload` until the upload adapter is proven safe enough to handle reservation, binary upload, commit, deletion/reordering, and read-back validation. |
| Submit for review | Supported with safeguards | `GET /v1/reviewSubmissions` with `include=appStoreVersionForReview`, `POST /v1/reviewSubmissions`, `POST /v1/reviewSubmissionItems`, `PATCH /v1/reviewSubmissions/{id}` with `submitted` | Creates a dry-run plan for submission, reuses an existing matching review submission when present, and rejects unexpected read-back states. `--apply` verifies that the read-back submission still targets the requested App Store version and is in an accepted submitted state. |
| Xcode Cloud / CI workflows | Partially supported | `ciWorkflows` create/get/update/delete operations exist, but setup requires product, repository, Xcode version, macOS version, actions, and start-condition modeling | Classified as available in OpenAPI but not implemented in the first CLI. Apogee reports `UnsupportedCapability.ciWorkflowSync` for workflow sync until a dedicated config model is designed. |
| Webhook sync | Supported | `GET /v1/apps/{id}/webhooks`, `POST /v1/webhooks`, `PATCH /v1/webhooks/{id}`, `DELETE /v1/webhooks/{id}` | Reads `webhooks.json`, compares by unique webhook name, creates/updates matching entries, deletes obsolete entries as destructive actions, and verifies the final remote set after `--apply`. Deletion requires a prior dry-run plan token plus `--allow-destructive` and `--apply`. |

## Safety Rules

- Writes are dry-run by default.
- `--apply` is required for every App Store Connect mutation.
- Missing App Store version localizations are never created automatically.
- Destructive operations require an explicit dry-run plan token before they can
  be applied, and that token is bound to the exact planned action values.
- Secrets are read from environment variables and local key files only.
- Plans and command output must not include private key material, JWT bearer
  tokens, or webhook secret values.
- Unsupported or unsafe operations fail with an explicit `UnsupportedCapability`
  value instead of falling back to untyped HTTP behavior.
