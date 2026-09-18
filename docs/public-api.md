# Public API contract

`ApogeeCore` is the supported library product for macOS release tooling. Its supported
surface, CLI/configuration contract below, and documented safety behavior form
the semantic-versioning boundary. This is a source-package contract, not a binary
ABI or persistent Swift hash-value guarantee. A build does not prove account permissions,
App Review acceptance, or live write/read-back success; see [adoption](adoption.md).

## Surface classification

Each row classifies the named type and **all** its public initializers,
properties, methods, enum cases, raw values, and declared protocol conformances.
The member exception below overrides its enclosing type. Straightforward
value initializers preserve supplied values; they do not independently validate
server acceptance. Synthesized Codable/Hashable behavior belongs to its type.

| Type | Status | Responsibility |
| --- | --- | --- |
| `ReleaseAutomation` | Supported | Planning and verified execution |
| `ReleaseExecutionOptions` | Supported | Explicit mode and destructive confirmation |
| `OperationMode` | Supported | Dry-run or apply |
| `Platform` | Supported | API platform values |
| `AppLookup` | Supported | Unique app selection |
| `ReleaseStatus` | Supported | Observed release snapshot |
| `MetadataSnapshot` | Supported | Read-only localized metadata snapshot |
| `ReleasePlan` | Supported | Structured differences and opaque confirmation token |
| `PlannedAction` | Supported | One difference or observation |
| `PlannedActionKind` | Supported | Change/verification classifications |
| `PlanRenderer` | Supported | Human output; exact text layout is not a parsing contract |
| `ApogeeConfiguration` | Supported | Repository defaults and path resolution |
| `AppStoreConnectCredentialEnvironment` | Supported | Credential variable names |
| `AppStoreConnectCredentials` | Supported | Team key loading and redacted descriptions |
| `SecretEnvironment` | Supported | Deferred webhook secret lookup |
| `AppStoreConnectAPI` | Supported | Low-level adapter/test-double boundary |
| `GeneratedAppStoreConnectAPI` | Supported | Production adapter and transport injection |
| `AppStoreConnectApp` | Supported | Remote app snapshot |
| `AppStoreConnectVersion` | Supported | Version and release timing snapshot |
| `AppStoreConnectLocalization` | Supported | Remote localized metadata |
| `AppStoreConnectBuild` | Supported | Build snapshot |
| `AppStoreConnectReviewSubmission` | Supported | Review state and complete-or-nil item linkage |
| `AppStoreConnectReviewSubmissionItem` | Supported | Review item identity |
| `AppStoreConnectWebhook` | Supported | Observable webhook settings |
| `MetadataPatch` | Supported | Nil means omit; empty string requests clear except for support URL |
| `LocalizedMetadata` | Supported | Selected local or remote fields |
| `MetadataField` | Supported | Supported file basenames |
| `MetadataValidationError` | Supported | Invalid URL fields without echoing their values |
| `MetadataLoader` | Supported | Local UTF-8 validation |
| `WebhookSyncConfiguration` | Supported | Complete desired webhook list |
| `DesiredWebhook` | Supported | Webhook settings and explicit secret rotation |
| `WebhookConfigurationLoader` | Supported | JSON and event type validation |
| `ApogeeError` | Supported | Domain errors and safe request failure categories |
| `BuildFeedback` | Supported | Read-only candidate-build feedback snapshot |
| `BuildFeedbackSummary` | Supported | Privacy-reduced feedback resource |
| `BuildFeedbackArtifact` | Supported | Sensitive time-limited artifact location |
| `BuildFeedbackExport` | Supported | Explicit private artifact destination |
| `BuildFeedbackError` | Supported | Unsupported, incomplete, or unsafe feedback inspection |
| `VersionReleasePolicy` | Supported | Explicit manual, automatic, or scheduled publication policy |
| `VersionSettingsPatch` | Supported | Requested copyright and release policy; nil preserves values |
| `VersionSettingsError` | Supported | Version-settings validation, state, and verification failures |
| `VersionCreationError` | Supported | Version creation validation and unsupported adapters |
| `UnsupportedCapability` | Supported | Explicit unsupported-operation failures |
| `ScreenshotAPI` | Supported | Opt-in low-level screenshot adapter; mutations write immediately |
| `RemoteScreenshotSet` | Supported | Observed localization/display set |
| `RemoteScreenshot` | Supported | Observed identity, source checksum, and processing state |
| `ScreenshotUploadOperation` | Supported | Sensitive time-limited asset upload instructions |
| `ScreenshotRecovery` | Supported | Explicit private recovery directory and original file source |
| `ScreenshotError` | Supported | Screenshot validation, recovery, and execution failures |
| `ScreenshotSet` | Provisional | Inventory only |
| `ScreenshotFile` | Provisional | File information only |
| `ScreenshotLoader` | Provisional | Inventory without image or upload validation |

`ReleaseAutomation.updateScreenshots(...)` supports verified apply when its adapter
also conforms to `ScreenshotAPI`. Older custom adapters retain their provisional
inventory-only behavior and fail apply with `unsupported(.screenshotUpload)`.
The legacy `screenshotLoader` initializer parameter remains provisional; production
screenshot execution uses strict image validation and private recovery storage.

### Metadata URL migration

`MetadataField` now includes `supportURL` and `marketingURL`; its `allCases`
therefore includes six fields. This addition is shipped as an explicit minor-release
exception to source compatibility. Consumers with exhaustive switches must handle
the two new cases before updating. Existing four-field behavior can be selected
explicitly. Missing URL files leave those fields untouched, and
`update-release-notes` still selects only release notes.

### Internal implementation and migration from 0.4

The generated client target now uses the generator's `package` access modifier.
Its `Client`, `Components`, `Operations`, `APIProtocol`, and other declarations
are not supported consumer API. Generation stays committed and requires no
generator dependency during adoption. Use `AppStoreConnectAPI` and its Apogee
models instead of importing generated types. The unused public marker
`AppStoreConnectGeneratedModule` has also been removed.

`JSONWebTokenSigner`, `SignedToken`, and `AppStoreConnectTokenProvider`, including
all former public members, are now internal. Construct
`GeneratedAppStoreConnectAPI(credentials:)` to obtain signing and token caching.
Existing CLI/plugin consumers and callers of `ReleaseAutomation` require no
source changes. Direct users of these former public helpers must migrate before
updating their exact 0.x pin.

### External types and adapter responsibility

The default adapter initializer needs only `ApogeeCore` and Foundation's `URL`
when overriding the server. The explicit `transport:` initializer exposes
`OpenAPIRuntime.ClientTransport`. A custom transport consumer must declare a
direct `swift-openapi-runtime` dependency/product and normally `swift-http-types`
for request/response types, with versions compatible with Apogee's manifest.
Moving this initializer to an incompatible external major version counts as an
Apogee breaking change. Crypto, URLSession transport implementation, generated
schemas, JWT encoding, and token-cache details are not public contracts.

Only use trusted server URLs and transports: both receive authorization data.
Direct `AppStoreConnectAPI` mutation methods write immediately. They do not
apply the CLI's dry-run or confirmation gates. Custom adapters must return every
page, preserve unknown optional state and complete-or-nil review item linkage,
and preserve cancellation. Use `ReleaseAutomation` for guarded operations.

`AppStoreConnectAPI.createAppStoreVersion` has a default implementation that throws
`VersionCreationError.unsupportedAdapter`. Existing adapters remain source-compatible;
adapters opting into creation must configure manual release. The production adapter
implements this operation through the generated client.

### Unrecoverable replacement migration

`ReleaseExecutionOptions` gains `allowUnrecoverableReplacement`, defaulting to false;
its initializer defaults keep existing call sites source compatible, and its
synthesized equality and hashing now include that value. `ScreenshotError` gains
`unrecoverableReplacementRequiresConfirmation` and `setCapacityExceeded`, so
consumers with exhaustive switches over it must handle the two new cases.

Screenshot plans now include a `replacementStrategy` action for any set whose
obsolete images have no verified original in the supplied recovery inputs. Plans
therefore depend on `--recovery-path` and `--originals-path`; use the same paths for
the dry-run and the apply. See [verified screenshot updates](screenshots.md).

### Feedback artifact migration

`BuildFeedbackError` gains `invalidExportDestination`, `exportConflict`, and
`unsafeArtifact`. Consumers with exhaustive switches over it must handle the three
new cases before updating. `BuildFeedbackSummary` gains `hasArtifact`, `artifacts`,
and `exportedFiles`; its initializer defaults keep existing call sites source
compatible, and its synthesized equality now includes those values.

`AppStoreConnectAPI.downloadFeedbackArtifact` has a default implementation that
performs a credential-free Apple asset request, so existing adapters remain source
compatible. `ReleaseAutomation.buildFeedback` downloads nothing unless it is given
a `BuildFeedbackExport`. Artifact locations are capabilities: keep them out of logs
and persisted files. See [candidate build feedback](build-feedback.md).

`AppStoreConnectAPI.updateVersionSettings` defaults to throwing
`VersionSettingsError.unsupportedAdapter`. The automation layer verifies version
identity and editability, then reads back the complete effective settings. See
[version settings](version-settings.md) for state and inactive-date semantics.

## CLI and configuration

All commands support `--apogee-config` and `--help`/`-h`. An absent implicit
`apogee.json` uses defaults; an explicitly selected missing file fails. The
SwiftPM plugin forwards the same command/option surface and runs relative to the
consumer package, including invocation through `--package-path`.

Status and plan commands also accept `--output text|json`, defaulting to text.
The versioned [JSON output contract](json-output.md) is supported CLI surface.
`read-metadata` retains its separate JSON snapshot format. Internal reporting
context and machine field identifiers do not change existing plan/action equality,
hashing, human rendering, or confirmation tokens.

| Command | Additional options | Behavior |
| --- | --- | --- |
| `validate-metadata` | `--metadata-path`, `--release-notes-only` | Local-only validation |
| `build-feedback` | Lookup, `--version`, `--build-version`, `--platform`, `--output`, `--export-path` | Remote feedback reads; artifacts download only into an explicit private destination |
| `release-status` | Lookup, `--version`, `--platform` | Remote read only |
| `read-metadata` | Lookup, `--version`, `--platform`, `--save-to` | Remote read only; JSON snapshot with optional new-file export |
| `create-version` | Lookup, `--version`, `--platform`, mode | Create an absent version for manual release; verify identity, release type, and preparation state |
| `update-release-notes` | Lookup, `--version`, `--platform`, mode, `--metadata-path` | What's New only |
| `update-metadata` | Lookup, `--version`, `--platform`, mode, `--metadata-path` | Four supported fields |
| `update-version-settings` | Lookup, `--version`, `--platform`, mode, `--copyright`, `--release-type`, `--earliest-release-date` | Explicit version settings; no options reads the current effective values |
| `attach-build` | Lookup, `--version`, `--platform`, mode, `--build-version` | Existing valid build |
| `submit-for-review` | Lookup, `--version`, `--platform`, mode | Submit an existing version |
| `sync-webhooks` | Lookup, mode, `--config`, `--allow-destructive`, `--plan-token` | Complete desired webhook list |
| `update-screenshots` | Lookup, `--version`, `--platform`, mode, `--screenshots-path`, `--recovery-path`, `--originals-path`, `--allow-destructive`, `--allow-unrecoverable-replacement`, `--plan-token` | Verified screenshot updates with recovery before deletion, or opt-in upload-first replacement |

Lookup precedence is `--app-id`, `--bundle-id`, configuration `appID`, then
configuration `bundleID`. Version/build numbers are explicit command inputs.
Platform precedence is `--platform`, `defaultPlatform`, then `IOS`; accepted
values are `IOS`, `MAC_OS`, `TV_OS`, and `VISION_OS`.
Mode is `--dry-run` or `--apply`, never both; omission means dry-run.

| Configuration key | Default or meaning |
| --- | --- |
| `appID`, `bundleID` | Optional app lookup defaults |
| `defaultPlatform` | Optional platform; CLI falls back to `IOS` |
| `metadataPath` | `AppStore/Metadata` |
| `screenshotsPath` | `AppStore/Screenshots` |
| `webhooksPath` | `AppStore/webhooks.json` |
| `credentials.keyIDEnvironment` | `ASC_KEY_ID` |
| `credentials.issuerIDEnvironment` | `ASC_ISSUER_ID` |
| `credentials.privateKeyPathEnvironment` | `ASC_PRIVATE_KEY_PATH` |
| `credentials.privateKeyBase64Environment` | `ASC_PRIVATE_KEY_BASE64` |

Relative configured content paths, including defaults, resolve against the loaded
configuration file's directory. Explicit CLI content paths resolve against the
working directory. Directly constructed/decoded configurations have no file base.
The private key path is an environment value, not a configuration-relative path.
A nonempty base64 key takes precedence over a file path. Credentials never belong
in configuration JSON.

Metadata lives in `<metadataPath>/<locale>/`: `release_notes.txt`,
`description.txt`, `keywords.txt`, `promotional_text.txt`, `support_url.txt`, and
`marketing_url.txt`. Missing files leave fields unchanged and boundary newlines
are trimmed. Empty files request clearing, except `support_url.txt`, which must
be nonempty. See [URL validation](metadata-urls.md).
Webhooks JSON contains `webhooks`, each with `name`, `url`, `eventTypes`,
`secretEnvironmentVariable`, optional `enabled` (true), and optional `rotateSecret`
(false). Omitting a remote webhook from this complete list plans its deletion.

## Errors, secrets, and partial execution

`ApogeeError` cases and associated values form the programmatic error contract;
exact English descriptions and renderer whitespace do not. Request failures
distinguish transport failure, HTTP status, response decoding, date decoding,
and a generic request failure. They omit raw response bodies, authorization
headers, webhook secrets, and wrapped errors. Operation labels are diagnostic
context, not a second enum to parse. `CancellationError` is preserved, including
cancellation propagated through the generated runtime.

Local file/JSON loaders may also throw Foundation errors. Custom adapters can
throw their own errors. Caller-supplied error strings, local paths, resource IDs,
metadata, and webhook URLs are not universally redacted. Credential and secret
container descriptions redact values, but secret accessors return real values.
Keep release output private unless deliberately sanitized for publication.

Apply is sequential and not transactional. A timeout, cancellation, or failed
read-back can occur after a successful write; no rollback or automatic retry is
promised. Inspect the remote state and run a fresh dry-run before retrying.
Destructive apply additionally requires an exact current plan token and explicit
confirmation. Tokens are opaque and not authentication, locking, or a persistent
format. Unknown/incomplete remote states fail closed. Webhook secret rotation is
not readable remotely, so verification covers observable settings only.

## DocC reference

The source catalog is [ApogeeCore.docc](../Sources/ApogeeCore/ApogeeCore.docc).
Build it with the selected supported Xcode from the repository root:

```sh
bash Tools/Documentation/build.sh
```

This uses SwiftPM symbol graphs and Xcode's `docc`, with documentation warnings
treated as errors. The archive and compiler-derived per-declaration classification
are written below `.build/documentation/`; no plugin dependency is added to adopters.
New public types require a classification row above; update member exceptions
when a public declaration intentionally differs from its enclosing type.
