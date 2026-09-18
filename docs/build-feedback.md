# Candidate build feedback

Read TestFlight feedback before attaching a candidate build or submitting a version:

```sh
apogee build-feedback --version 2.0 --build-version 42 --platform IOS
apogee build-feedback --version 2.0 --build-version 42 --platform IOS --output json
```

The command resolves the app and one `VALID` build using the same app, platform,
marketing-version, and build-number filters as `attach-build`. It does not require
an App Store version resource and does not attach a build, submit a version,
delete feedback, or create issues. Without `--export-path` it contacts no artifact
download URL.

Apple exposes app-scoped [crash feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions)
and [screenshot feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions).
Both collections are filtered by the selected build ID and read through every
page. Every entry must identify that build, have an ID and attributes, and have
a unique ID within its collection. Missing or ambiguous builds, incomplete
responses, unauthorized requests, repeated pagination, and cancellation fail
without producing a successful result. A confirmed empty collection is zero;
a failed request is never treated as zero.

Output contains IDs, creation dates, device models, OS versions, whether a
comment is present, and how many downloadable artifacts Apple reported. Missing
optional attributes are unknown, represented as `null` in JSON. Empty comment text
is `false`; absent comment text is `null`. Names, email addresses, comment text,
artifact contents, and download URLs are not exposed in the result. The adapter
requests only the fields needed for these summaries and discards comment text
after deriving its presence. Do not enable transport logging of response bodies.

Screenshot feedback reports the images Apple lists for the submission: a listed
image without a location is incomplete inventory, and an omitted list stays
unknown rather than zero. Crash-log availability costs one extra read per crash
submission, so it stays unknown unless `--export-path` asks for the logs
themselves.

Counts describe feedback observed during sequential reads; they are not an
atomic snapshot, crash rate, release approval, or automatic release block.
Investigate relevant feedback in App Store Connect.

Reported pagination totals must be consistent and match the collected entries.
A next-page cursor without a next-page link is rejected as incomplete inventory.

## Artifact export

`--export-path` is the only way Apogee downloads a feedback artifact:

```sh
apogee build-feedback --version 2.0 --build-version 42 \
  --export-path /private/release-evidence/build-42
```

Exported crash logs and screenshots are tester-supplied material and can contain
personal data, account contents, stack traces, and other people's information.
Point the destination at private storage, keep it out of source control, and
delete it when the review is finished.

Crash logs are text that App Store Connect returns directly, so each crash
submission costs one extra authenticated read. Apogee writes that text straight to
the destination and never keeps it in its result, so it cannot reach the command's
output. A confirmed absent crash log is reported as none; an unauthorized,
rate-limited, or malformed read fails the command instead of being reported as
none. Screenshots are fetched from Apple's asset hosts instead, as described below.

The destination is explicit and never inferred: its parent must already exist, it
must not be a symbolic link, and Apogee creates it with owner-only permissions.
Existing destination directories must also have owner-only permissions; Apogee
refuses shared directories without changing their permissions.
Files are written as `crash/<submission id>/01.crash` and
`screenshot/<submission id>/<index>.<png|jpg>` with owner-only permissions and
never overwrite an existing file. Reusing a destination that
already holds an exported file fails with an export conflict instead of replacing
earlier evidence; choose an unused destination, or keep the existing files and
compare them yourself.

Artifact locations are time-limited Apple URLs and are treated as capabilities.
Downloads are `GET` requests over a separate uncached session with no API bearer
token, cookies, stored credentials, or redirect following, and only to `.apple.com`
or `.mzstatic.com` hosts over HTTPS. An expired location, a foreign host, an empty
or oversized response (limited to 32 MiB while streaming), and a payload that is not a PNG or JPEG all fail without
writing a file. A failed artifact leaves no directory behind, and a download failure
after earlier files were written keeps those files; rerun into a fresh destination.

JSON reports `exportedFiles` as paths relative to the destination. Without
`--export-path` the array is empty and nothing is downloaded.

## JSON

The command follows the success-only [JSON output contract](json-output.md), with
`schemaVersion: 1`, `kind: "build-feedback"`, `command: "build-feedback"`, and
`mode: "read-only"`. Check the exit status before reading stdout.

- `requestedTarget` contains the effective app lookup, marketing `version`,
  `platform`, and `buildVersion`.
- `target.app` contains the observed app identity. `target.build` contains `id`,
  `version` (build number), and `processingState`. The requested marketing version
  is not presented as an observed App Store version resource.
- `feedback.crashCount` and `feedback.screenshotCount` count their respective
  `crashes` and `screenshots` arrays. Entries are sorted by ID within each array.
- Each entry has `id`, `buildID`, nullable `createdDate` (UTC ISO 8601 with
  fractional seconds), nullable `deviceModel`, nullable `osVersion`, nullable
  `hasComment`, nullable `hasArtifact`, integer `artifactCount`, and
  `exportedFiles`. `hasArtifact` is `null` when availability was not determined,
  which is the case for crash feedback without `--export-path`. `artifactCount`
  counts the artifacts Apple reported, and `exportedFiles` is empty unless
  `--export-path` was used. Crash log text is never a JSON field.

Store even these reduced summaries privately: app/build identifiers and device
information can be sensitive. They are operational observations, not diagnostics.
