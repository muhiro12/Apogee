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

The plan also states the replacement strategy a set needs, so give the dry-run and
the apply the same `--recovery-path` and `--originals-path`. Available originals are
part of what the plan describes, and a plan produced from different recovery inputs
does not match the token the apply requires.

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
**delete old screenshots before new images finish uploading**. This is the default
strategy; see [upload-first replacement](#upload-first-replacement) for sets that
have spare capacity but no verified originals. Apply first copies
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

## Upload-first replacement

Sometimes the exact original bytes no longer exist: the images were uploaded long
ago, and App Store Connect exposes their name, size, and source checksum but not a
verified export of the source files. Processed Store images are not originals.

When such a set has room for its existing and replacement images at the same time,
`--allow-unrecoverable-replacement` selects an upload-first strategy:

```sh
apogee update-screenshots --version 4.0 --platform IOS \
  --screenshots-path AppStore/Screenshots \
  --recovery-path /private/release-recovery/run-3 \
  --apply --allow-destructive --allow-unrecoverable-replacement --plan-token TOKEN
```

Every replacement is reserved, uploaded, committed, and read back as `COMPLETE`
with its expected checksum and byte count **while every existing image still
exists**. Only then are the obsolete images deleted, the desired order applied, and
the normal final read-back performed. If any upload, processing, or verification
step fails, no existing `COMPLETE` screenshot is deleted, and reserved IDs stay
recorded in the recovery directory for resume or cleanup.

This strategy is used only when it is needed and allowed. It requires all of:

- verified originals are unavailable for at least one obsolete existing screenshot,
- the existing images plus the replacements fit within Apple's ten-image limit,
- `--allow-destructive` and an exact current plan token,
- the separate `--allow-unrecoverable-replacement` acknowledgement.

Without that acknowledgement the apply stops before any mutation. When capacity
would still force deletion before the replacements are complete, verified originals
remain required and a missing original stops the operation as before.

The dry-run names the strategy for each affected set: how many existing screenshots
have no verified original, and whether upload-first replacement applies or the set
exceeds the limit. In JSON this is an action with `field: "replacementStrategy"`,
which distinguishes it from the recoverable replacement path.

Recovery records the previous IDs and order and the reservations this operation
owns, and marks the set unrecoverable. It stores only the original bytes it actually
has; no `restore/<locale>/<display>` tree is written for an unrecoverable set,
because a partial tree would misrepresent a restorable composition. **The previous
composition cannot be restored from this directory.** Keep the old images available
elsewhere if that matters, or re-upload replacements from local files.

Deletion happens after the replacements are verified, so a failure during deletion
can leave both the old and the new verified images in the set. That state is safe to
inspect: obtain a fresh dry-run and apply it to remove the remaining obsolete images
and fix the order.

## Upload verification

Apogee follows Apple's [asset upload lifecycle](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect):
reservation, complete byte-range transfer, MD5 commit, asynchronous processing,
and ordered read-back. Upload URLs must be HTTPS Apple asset URLs with complete
non-overlapping byte ranges. Apple's upload URLs are time limited, but a current
response does not always carry an `Expires` query parameter: when it is present
it must be one finite future timestamp, and when it is absent the server-side
lifetime applies and the transfer is performed immediately. Asset requests use a
separate uncached session with no API bearer token, cookies, stored credentials,
or redirect following. Signed URLs and upload headers are not persisted in
recovery files.

The command waits up to 30 processing observations, spaced two seconds apart.
`UPLOAD_COMPLETE` is not success; `COMPLETE` and the matching checksum are required.
App Store Connect can report `COMPLETE` before the source checksum is readable,
so an unreadable checksum keeps polling until the timeout, while a different
checksum fails immediately as a permanent mismatch.
A timeout or processing failure returns an error and retains recovery files.
No failed transfer or mutation is automatically repeated within an invocation.
Final verification checks IDs, order, source checksums, file sizes, and processing
states. It does not certify visual quality, approval, or publication.

## Optional progress

Add `--progress` to report concise stage observations to stderr. The default is
quiet, including in automation. Stdout still contains only the final text or one
successful JSON result:

```sh
apogee update-screenshots --version 2.0 --platform IOS \
  --recovery-path /private/release-recovery/run-2 \
  --originals-path /private/release-originals \
  --apply --allow-destructive --plan-token TOKEN \
  --progress --output json > result.json
```

Each line identifies the locale, display type, stage, checksum-verified desired
image count across all selected sets, total desired image count, and monotonic
elapsed seconds since the screenshot workflow began. Counts include reused images
and can reach the total while cleanup and verification are still pending.
Progress omits local paths, file names, upload URLs, headers, and credentials.

Stages distinguish planning, recovery preparation, upload, commit, Apple
processing, checksum availability, replacement verification, obsolete-image
deletion, ordering, final verification, and set completion. Processing and checksum
observations show the current attempt and the 30-observation limit; the same
bounded wait applies with or without progress. These are stage observations,
not byte-transfer percentages, time estimates, retries, or a stall detector.
An in-flight request can remain in its last reported stage until it returns.

For upload-first replacement, `verifyingReplacements` precedes
`deletingObsolete`. A set's `completed` event is emitted only after final ordered
read-back succeeds. A failed operation has no successful final JSON; earlier
progress, including a completed earlier set, does not establish overall success.
Check the exit status and final result and retain recovery storage on failure.
Dry-run reports planning only; an unchanged apply does not invent completion events.

Library consumers can pass a `@Sendable (ScreenshotProgress) -> Void` observer
to the progress overload of `ReleaseAutomation.updateScreenshots`. It runs
synchronously and should return promptly. The original method signature remains
available, including as a function value. Observers do not change plans, tokens,
confirmation requirements, recovery behavior, or verification.
