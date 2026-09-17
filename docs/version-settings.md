# Explicit version settings

`update-version-settings` reads or updates copyright and publication policy for
one existing app/platform/version. It does not create a version, attach a build,
submit for review, or call the publication endpoint. `create-version` continues
to create versions for manual release.

With no setting options, the default dry-run reads all three effective settings:

```sh
apogee update-version-settings --version 2.0 --platform IOS --output json
```

To plan an update:

```sh
apogee update-version-settings --version 2.0 --platform IOS \
  --copyright '2026 Example' --release-type SCHEDULED \
  --earliest-release-date '2026-12-01T09:00:00+09:00' --dry-run
```

After reviewing the plan, run the same command with `--apply`. The default is
read-only; `--apply` and `--dry-run` cannot be combined. Unspecified settings stay
unchanged. An unchanged requested value is omitted from the write. Empty or
control-character-containing copyright values are rejected.

## Publication policy

- `MANUAL`: publication requires a later manual release after approval.
- `AFTER_APPROVAL`: Apple automatically releases the version after approval.
- `SCHEDULED`: Apple automatically releases after approval, no earlier than the
  supplied date. This does not promise publication at an exact time.

These are Apple's [version release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/).
Choosing automatic release authorizes that future behavior; the settings command
itself neither submits nor establishes approval or publication.

`SCHEDULED` requires `--earliest-release-date`; a date without `SCHEDULED` is
rejected. Changing only a scheduled date still requires `--release-type SCHEDULED`.
Supply `YYYY-MM-DDTHH:mm:ssZ` or `YYYY-MM-DDTHH:mm:ss±HH:mm` with a supported explicit
time-zone offset. Unknown `-00:00`, missing zones, invalid calendar dates, fractional
seconds, and past dates are rejected. Plans display the equivalent UTC time.
Scheduled dates are revalidated immediately before the write.

The effective earliest date is meaningful only for `SCHEDULED`. Switching to
`MANUAL` or `AFTER_APPROVAL` writes only the release type, not a null date. Apple may
retain an inactive stored date; Apogee does not treat it as an active schedule or
claim to erase it. Existing status reads still expose the raw stored date.

## State, verification, and failure

Changes are supported only in `PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`,
`REJECTED`, and `METADATA_REJECTED`. This conservative boundary is Apogee's
pre-submission scope, not a claim that Apple permits no edits elsewhere. Unknown
identity, release type, state, or a scheduled policy missing its date fails closed.
Read-only snapshots can still show unknown values. Apple validates account
permissions and any additional restrictions, including pre-order requirements.

Apply reads the selected version again before writing and stops if its snapshot
changed. Keep one writer per app/version: the read and write are not an atomic
transaction or remote lock. After the PATCH, another read must match app-version
identity, platform, state, copyright, release type, and the effective scheduled
date. A failed request or verification can follow a successful remote write.
Inspect a fresh read-only plan before retrying; Apogee does not retry or roll back
automatically.

JSON uses the existing versioned release-plan schema. Actions include complete
current and desired values for `copyright`, `release_type`, and
`earliest_release_date`, including unchanged settings. Absent or inapplicable
values remain null. Failures do not produce success-shaped JSON.

Library callers use `VersionSettingsPatch` and `VersionReleasePolicy` with
`ReleaseAutomation.updateVersionSettings`. The low-level adapter method writes
immediately; use the automation layer for identity, state, and verification checks.
Existing custom adapters inherit an unsupported default until they implement the
new method. Pricing, phased release, rating resets, post-approval publication,
and editing other version attributes remain outside this workflow.
