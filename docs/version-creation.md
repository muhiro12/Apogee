# Create an App Store version

`create-version` adds a version to an existing App Store Connect app. The app,
platform, and version are resolved using the same explicit lookup and configured
defaults as other release commands. It does not create an app record.

```sh
apogee create-version --app-id EXAMPLE_APP_ID --platform IOS --version 2.0
apogee create-version --app-id EXAMPLE_APP_ID --platform IOS --version 2.0 --apply
```

The first command is a read-only plan; `--dry-run` is equivalent. The second
performs one create request and reads the selected app's versions back. The
SwiftPM plugin forwards the same command and flags:

```sh
swift package plugin --allow-network-connections all apogee create-version \
  --app-id EXAMPLE_APP_ID --platform IOS --version 2.0 --dry-run
```

## Scope and safety

- Every created version explicitly uses `MANUAL` release. After approval, release
  it manually or change its release settings in App Store Connect. This command
  does not accept automatic or scheduled release options.
- Metadata updates, build attachment, review submission, and publication remain
  separate operations. Apogee sends no metadata or build relationships during
  creation. Apple may carry metadata forward from the current version; inspect
  the new version with `read-metadata` before preparing updates.
- An existing exact version is an error, not an unchanged result. Multiple
  matches also fail. This applies to dry-run and apply, including repeat runs
  after a successful creation. `release-status` never creates a missing version.
- A dry-run checks app resolution and absence of the requested version across
  all pages. It does not prove create permission or eligibility of the app's
  current state. Apple validates version format, platform, and lifecycle rules
  on creation; Apogee does not reproduce Apple's state machine locally.
- Empty version strings and surrounding whitespace are rejected locally. The
  version is otherwise passed unchanged rather than normalized as a package tag.
- Successful apply requires exactly one read-back match under the selected app,
  with the returned resource ID, requested version and platform, `MANUAL`
  release type, and `PREPARE_FOR_SUBMISSION` state. Missing or mismatched values
  fail closed. No verification action is returned on failure.

## Permissions and recovery

Use a team API key with access to the target app and permission to create a
version. Apple's [new-version guide](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/)
lists the required roles and current-version requirements. The
[creation API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversions)
is the authority for server validation.

HTTP failures retain their status code without raw response bodies or credentials:
check app/key access for 401 or 403, and inspect existing versions and the app's
state for 409. Other validation failures may use different status codes. A dry-run
that succeeded before a conflict does not reserve a version or lock remote state.

A timeout, cancellation, decoding failure, or read-back mismatch can occur after
the server created the version. Apogee never retries the create automatically and
does not delete a version to roll back. Run `release-status` for the exact target
and inspect App Store Connect before deciding whether another create is needed.
If the version exists, continue with the later release operations instead.

Custom `AppStoreConnectAPI` adapters remain source-compatible through a default
implementation of `createAppStoreVersion` that throws
`VersionCreationError.unsupportedAdapter`. Implement that method to
opt into manual version creation. Low-level API calls write immediately; use
`ReleaseAutomation.createVersion` for planning and read-back verification.

`VersionCreationError` also distinguishes invalid local version input and an
already-existing version. Shared lookup, request, and verification failures keep
using `ApogeeError`; its existing cases are unchanged.
