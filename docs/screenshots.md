# Asset Library screenshot updates

`update-screenshots` uses Apple's App Asset Library for every production upload.
It does not retry through the deprecated screenshot-set API. Only the selected
locale/display directories are changed; omitted directories preserve their
remote placements. Empty directories never request deletion.

## Input and migration

Use `AppAssetLibraryDisplayClass` names for directory names. Number files to
choose their lexicographic order. Use one app platform per invocation:

```text
AppStore/Screenshots/en-US/IPHONE_DUO/01-overview.png
AppStore/Screenshots/en-US/IPHONE_DUO/02-details.png
AppStore/Screenshots/ja/IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY/01-overview.png
```

For macOS, tvOS, and visionOS, use `DEFAULT`; the platform selects its profile.
For iPad and Watch, select the corresponding display class from Apple's current
reference data. Apogee resolves placement groups, image specifications, and
limits through `GET /v1/appAssetLibraryRefData`, rather than guessing group IDs.
Unknown, ambiguous, or unavailable targets fail before remote writes.
If a display class has multiple profiles, each image is assigned to its unique
compatible group by the returned specifications. Order is preserved within each
group; omitted groups remain unchanged.

The previous `APP_*` directory names are no longer production input. Rename
these directories when updating Apogee; do not combine both naming schemes:

| Previous directory | Display class |
| --- | --- |
| `APP_IPHONE_67` | `IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY` |
| `APP_IPHONE_61` | `IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY` |
| `APP_IPHONE_65` | `IPHONE_FACE_ID_LARGE_DISPLAY` |
| `APP_IPHONE_58` | `IPHONE_FACE_ID_MEDIUM_DISPLAY` |
| `APP_IPHONE_55` | `IPHONE_HOME_BUTTON_LARGE_DISPLAY` |
| `APP_IPHONE_47` | `IPHONE_HOME_BUTTON_MEDIUM_DISPLAY` |
| `APP_IPHONE_40` | `IPHONE_HOME_BUTTON_40_DISPLAY` |
| `APP_IPHONE_35` | `IPHONE_HOME_BUTTON_35_DISPLAY` |
| `APP_IPAD_PRO_3GEN_129` | `IPAD_13_DISPLAY` |
| `APP_IPAD_PRO_3GEN_11` | `IPAD_11_DISPLAY` |
| `APP_IPAD_PRO_129` | `IPAD_129_DISPLAY` |
| `APP_IPAD_105` | `IPAD_105_DISPLAY` |
| `APP_IPAD_97` | `IPAD_97_DISPLAY` |
| `APP_WATCH_ULTRA` | `WATCH_ULTRA` |
| `APP_WATCH_SERIES_10` | `WATCH_SERIES_10` |
| `APP_WATCH_SERIES_7` | `WATCH_SERIES_7` |
| `APP_WATCH_SERIES_4` | `WATCH_SERIES_4` |
| `APP_WATCH_SERIES_3` | `WATCH_SERIES_3` |
| `APP_DESKTOP`, `APP_APPLE_TV`, `APP_APPLE_VISION_PRO` | `DEFAULT` |

These examples identify target families; the server's current image specifications
remain authoritative. Confirm the intended current display class and validate
existing files against the reference data. Apogee does not
silently retarget or resize images. iMessage placements are outside this command.

Inputs must be regular, single-image, decodable PNG/JPEG files without alpha.
Limits are 64 MiB per file, 10,000 pixels per dimension, 40 million pixels per
image, 512 MiB across at most 100 directories, and at most ten distinct files per
directory. The reference data can impose stricter limits, dimensions, MIME types,
and extensions. Symlinks and unexpected files are rejected.

## Planning and apply

Existing version localizations are required. Both phases use the same input:

```sh
apogee update-screenshots --version 2.0 --platform IOS \
  --screenshots-path AppStore/Screenshots \
  --recovery-path /private/release-recovery/asset-library-run-1 \
  --dry-run --output json
```

Dry-run reads reference data, placements, and asset metadata. It creates no
recovery files and performs no mutations. The token includes the current ordered
placements and the desired local image identities and compatible specifications.

```sh
apogee update-screenshots --version 2.0 --platform IOS \
  --screenshots-path AppStore/Screenshots \
  --recovery-path /private/release-recovery/asset-library-run-1 \
  --apply --allow-destructive --plan-token TOKEN --progress --output json
```

Removing or reordering existing placements requires `--allow-destructive` and a
fresh matching token. A changed remote inventory stops apply. New registration
requires explicit apply and recovery storage. The editable version is checked
again before changes. An API error never triggers a legacy API fallback.

## Upload and verification

Apple's [migration guide](https://developer.apple.com/documentation/appstoreconnectapi/migrating-to-the-app-asset-library)
replaces screenshot sets with library images and placements. Commits send
`uploaded: true`; Apple no longer exposes `sourceFileChecksum` in this API.
Apogee does not synthesize a remote checksum or claim checksum verification.

Each file gets a local SHA-256 identity in `referenceName`. Existing placements
can reuse an asset when that identity, size, processed state, and compatible
`specId` match. The reference name is writable metadata, not a server-verified
content hash. Keep other writers from changing these identities during a run.

New assets are reserved against the app's library, uploaded using Apple's
credential-free asset instructions, committed, and polled for processing. Byte
ranges must cover the complete source without gaps or overlap. Uploads use an
uncached session without API authorization, cookies, stored credentials, or
redirect following. Signed URLs and request headers are never persisted.

All desired assets across all selected groups must pass processing, byte-count,
identity, and specification checks before any obsolete placement is removed.
Then Apogee creates missing placements and orders them. Final read-back checks
placement IDs, parent localization, group, asset IDs, order, placement readiness,
and processed asset metadata. Polling is bounded to 30 observations at two-second
intervals. A timeout or mismatch fails and retains recovery evidence.

This proves the documented asset and placement observations. It does not prove
a server-side source checksum, visual quality, App Review acceptance, or release.
No live Duo upload has been verified. Separate read-only validation is described
in the placement lifecycle evidence below.

## Placement lifecycle

The workflow accepts `ACTIVE` and `PARENT_PREPARE_FOR_SUBMISSION` as ready
placement states. The same rule covers existing and retained placements, creation
responses, polling, and final verification. `ASSET_PROCESSING` is accepted only
for newly created placements and polling; an existing processing placement blocks
planning until a later read reports readiness. `FAILED`, other parent states,
and unknown states stop the operation. Diagnostics name `appAssetLibraryPlacements`
and include only a bounded state identifier, never arbitrary response text.
Unsupported states use `ApogeeError.unexpectedAPIResponse`; malformed placement
identity or scope still uses `ScreenshotError.incompleteInventory`.

This is a narrow compatibility correction for the public-backend `ACTIVE`
response recorded in [Issue #20](https://github.com/muhiro12/Apogee/issues/20).
The official 4.5.1 specification, rechecked on 2026-10-28 with the same hash below,
lists processing, failure, and parent lifecycle states but omits `ACTIVE`.
Accepting `ACTIVE` in an editable version is based on that observed response,
rather than a claim that Apple documents its complete transition model. The
workflow still independently verifies version editability, image processing,
image specification and byte count, placement identity/scope, and order.

Sanitized HTTP-200 fixtures exercise the generated adapter through the production
workflow, including an unchanged active composition and rejected unknown states.
Synthetic create/poll tests cover both ready states and processing/failure paths.
Separate controlled read-only validation on 2026-10-28 confirmed live `ACTIVE`
placements and an `APPROVED` image through the production adapter, with zero
remote writes. The inspected version was already released, with no editable
version available for a live workflow dry-run. Creating placements and actual
Duo uploads remain unverified. Fixture and read-only success do not establish
write permissions or upload support; see
[Issue #18](https://github.com/muhiro12/Apogee/issues/18) for that remaining
verification. App Store Connect's Asset Library UI remains the manual alternative.

## Recovery

Use a new private directory for a new operation. Its directory and files require
owner-only permissions. Concurrent writers and symlinked paths are refused.
`asset-library-state.json` records the target, owned reservation IDs, local source
identities, transfer/commit progress, and the original ordered placement records.
It contains no signed URLs or upload headers.

Apogee deletes obsolete placements only. It never deletes or archives library
images, including images shared with other localizations, product pages, or
experiments. Previous assets remain available to place again through App Store
Connect or the public placement API, using the IDs and original order in the
journal. The journal is a record of placements, not a local original-byte export;
it cannot restore an image another writer deletes or archives later.

After a failure, inspect remote state, keep the original source files and journal,
and obtain a fresh dry-run. Reuse the same recovery directory to resume. A known
fully transferred upload can be committed or observed again on a later explicit
invocation. An incomplete byte transfer is not replayed from stale upload URLs;
a later apply may reserve a new unplaced asset. An ambiguous response may also
leave an unplaced asset in the library. Inspect such assets before manual cleanup.
There is no automatic rollback or automatic retry within a failed invocation.

Old `state.json` directories belong to the former set-based workflow and are
rejected for new Asset Library operations. `--originals-path` and
`--allow-unrecoverable-replacement` remain accepted for existing custom adapters;
the production Asset Library workflow does not need them because it retains the
library images. See [legacy custom adapters](legacy-screenshot-adapters.md).

## Progress

`--progress` is opt-in and writes privacy-reduced stage observations to stderr.
Stdout keeps the final text or one successful JSON result. Observations distinguish
planning, recovery, upload, commit, processing, replacement verification, obsolete
placement removal, ordering, final read-back, and completion. Image counts can
reach the total before placement work finishes. They are verified asset counts,
not percentages, time estimates, or remote source-checksum counts.

`waitingForChecksum` remains part of the public progress enum for legacy custom
adapters, but the production workflow does not emit it. A `completed` event is
emitted only after final ordered read-back. A failed invocation produces no success
JSON, even if an earlier group finished.

## Apple evidence

Checked on 2026-10-28 against Apple's
[OpenAPI download](https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip),
version 4.5.1, extracted specification SHA-256
`7518d3a94a8bd701ac25c1c601b95b8f53aad92091affb15a2a9d331713dac1a`.
The [4.5.1 release notes](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes)
identify `AppAssetLibraryDisplayClass.IPHONE_DUO` and deprecate the old sets.
The generated-client baseline is documented in [OpenAPI generation](openapi-generation.md).

Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
list 1398 × 2034 or 2034 × 1398 for Duo's outer display, and 2007 × 2853 or
2853 × 2007 for its inner display. Apogee uses runtime specifications to validate
these files, rather than treating an old iPhone/iPad display as a Duo target.
