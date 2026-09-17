# Candidate build feedback

Read TestFlight feedback before attaching a candidate build or submitting a version:

```sh
apogee build-feedback --version 2.0 --build-version 42 --platform IOS
apogee build-feedback --version 2.0 --build-version 42 --platform IOS --output json
```

The command resolves the app and one `VALID` build using the same app, platform,
marketing-version, and build-number filters as `attach-build`. It does not require
an App Store version resource and does not attach a build, submit a version,
delete feedback, create issues, or contact artifact download URLs.

Apple exposes app-scoped [crash feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions)
and [screenshot feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions).
Both collections are filtered by the selected build ID and read through every
page. Every entry must identify that build, have an ID and attributes, and have
a unique ID within its collection. Missing or ambiguous builds, incomplete
responses, unauthorized requests, repeated pagination, and cancellation fail
without producing a successful result. A confirmed empty collection is zero;
a failed request is never treated as zero.

Output contains IDs, creation dates, device models, OS versions, and whether a
comment is present. Missing optional attributes are unknown, represented as
`null` in JSON. Empty comment text is `false`; absent comment text is `null`.
Names, email addresses, comment text, artifact contents, and download URLs are
not exposed in the result. The adapter requests only the fields needed for these
summaries and discards comment text after deriving its presence. Do not enable
transport logging of response bodies.

Counts describe feedback observed during sequential reads; they are not an
atomic snapshot, crash rate, release approval, or automatic release block.
Investigate relevant feedback in App Store Connect. This initial command does
not assess downloadable artifact availability or export crash logs/screenshots.
Such files may contain personal data and require a separately designed explicit
private destination and overwrite protection.

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
  fractional seconds), nullable `deviceModel`, nullable `osVersion`, and nullable
  `hasComment`.

Store even these reduced summaries privately: app/build identifiers and device
information can be sensitive. They are operational observations, not diagnostics.
