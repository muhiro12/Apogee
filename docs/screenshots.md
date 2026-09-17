# Verified screenshot updates

`update-screenshots` updates only the locale/display directories present in the
local input. Missing directories leave remote sets unchanged. Empty directories
are rejected; they never mean "delete this locale". Number file names to define
their lexicographic display order. Use Apple's exact screenshot display identifiers:

```text
AppStore/Screenshots/en-US/APP_IPHONE_67/01-overview.png
AppStore/Screenshots/en-US/APP_IPHONE_67/02-details.png
AppStore/Screenshots/ja/APP_DESKTOP/01-overview.png
```

Use one platform per invocation. Existing App Store version localizations are
required; missing screenshot sets are created during apply. Custom product pages,
experiments, videos, and creation of localizations are not part of this command.
PNG/JPEG input must contain a single decodable image without alpha. Limits are
64 MiB per file, 10,000 pixels per dimension, 40 million pixels per image, and
512 MiB across at most 100 selected directories. Each selected directory must
have 1–10 distinct images.
Symlinks and unexpected files are rejected. Apple performs final validation of
its current [screenshot dimensions](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
and processing requirements; local image checks alone do not establish acceptance.

## Dry-run and explicit apply

```sh
apogee update-screenshots --version 2.0 --platform IOS \
  --screenshots-path AppStore/Screenshots \
  --recovery-path /private/release-recovery/run-2 \
  --originals-path /private/release-originals --dry-run --output json
```

The plan includes full remote identities, checksums and order, and local SHA-256
fingerprints. Identical content is reused even if a local file was renamed.
A different order changes the plan token. A fresh dry-run after successful apply
has no changes. Dry-run performs no local recovery writes or remote mutations.

For a plan containing deletion or reordering, use its exact token:

```sh
apogee update-screenshots --version 2.0 --platform IOS \
  --screenshots-path AppStore/Screenshots \
  --recovery-path /private/release-recovery/run-2 \
  --originals-path /private/release-originals \
  --apply --allow-destructive --plan-token TOKEN
```

Pure new registration needs explicit apply and a recovery directory, but no
destructive confirmation. The version must be in `PREPARE_FOR_SUBMISSION`,
`DEVELOPER_REJECTED`, `REJECTED`, or `METADATA_REJECTED`; apply rechecks this state
before mutations. Unknown version editability, incomplete inventory,
duplicate remote identities, and unrelated unfinished uploads fail closed.

## Replacement and recovery

A set may already occupy Apple's ten screenshot slots. Replacement can therefore
**delete old screenshots before new images finish uploading**. Apply first copies
and reads back verified original bytes for every affected existing set. Originals
must match Apple's recorded source MD5 and file size. Supply the original files
through `--originals-path`; a processed or resized App Store image is not a verified
original. Files identical to the desired local images can also serve as originals.
Missing or mismatched originals stop the operation before any remote mutation.

The private recovery directory retains immutable image blobs, the original order,
target identity, and IDs reserved by this operation. The `restore/<locale>/<display>`
tree is also a ready-to-use screenshot input in the original order. Keep this directory until
release verification is complete. It must not be shared publicly or checked into
source control. A directory used for another app/version is rejected. A lock
prevents concurrent writers using the same recovery directory; operators must
also prevent other tools from editing the same remote sets.

There is no transaction or automatic rollback. An interrupted replacement may
leave fewer images, an empty set, or a partially updated set. Recovery preserves
the original bytes; re-uploading them remains subject to Apple permissions and
availability. Do not interpret an error as proof that no remote write happened.

To resume, retain the recovery directory, inspect remote state, and obtain a
**fresh dry-run token** using the same directory and desired files. Completed
matching uploads are reused. Unfinished assets are eligible for cleanup only if
their IDs were recorded in this recovery directory. If a reservation response was
lost before its ID could be recorded, stop and inspect App Store Connect; the
command does not guess ownership from a filename or delete unknown assets.

To restore backed-up sets, use `--screenshots-path /private/release-recovery/run-2/restore`
and run the same dry-run/apply workflow with a fresh token. Supply the current
replacement originals through `--originals-path` so those images can be backed up
before deletion too. This restores only saved sets; newly created sets without an
original counterpart are not implicitly deleted. Use a new recovery directory for
a separate replacement operation; reuse an existing directory only to resume or
recover its recorded operation.

## Upload verification

Apogee follows Apple's [asset upload lifecycle](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect):
reservation, complete byte-range transfer, MD5 commit, asynchronous processing,
and ordered read-back. Upload URLs must be unexpired HTTPS Apple asset URLs with
complete non-overlapping byte ranges. Asset requests use a separate uncached
session with no API bearer token, cookies, stored credentials, or redirect
following. Signed URLs and upload headers are not persisted in recovery files.

The command waits up to 30 processing observations, spaced two seconds apart.
`UPLOAD_COMPLETE` is not success; `COMPLETE` and the matching checksum are required.
A timeout or processing failure returns an error and retains recovery files.
No failed transfer or mutation is automatically repeated within an invocation.
Final verification checks IDs, order, source checksums, file sizes, and processing
states. It does not certify visual quality, approval, or publication.
