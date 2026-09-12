# Adopting Apogee for release operations

Apogee runs on macOS alongside the tools that prepare and distribute an app.
Keep it in a dedicated release-tools package; the iOS app, extensions, widgets,
and watch app do not need to link `ApogeeCore`. Adopting this tool does not change
an app's deployment target, architecture, branching strategy, or release dates.

## Stage adoption around a release

1. Keep the existing release process available while introducing Apogee. A
   version already in review or awaiting publication need not be resubmitted for
   adoption. Use `release-status` to observe it.
2. Pin a published Apogee tag in a macOS SwiftPM package and commit the consumer's
   `Package.resolved`. Test dependency updates separately from the final app
   candidate. The [consumer example](../Examples/ReleaseTools) uses a local
   checkout to verify integration before a tag is published.
3. Start with `validate-metadata`, then a remote dry run of `update-release-notes`
   against an existing editable version. Review every locale and the full text.
   Only present files for selected fields are updated; omitted fields and locales
   are left alone. Empty files intentionally clear fields if Apple permits it.
   An empty directory or no matching files is an error.
4. After validating real-account API access and read-back, adopt metadata updates
   and build attachment. Keep review submission a separate explicit operation
   until the entire app release is ready.
5. Expand use for a subsequent major app update after those steps work. New
   screenshots, review details, privacy declarations, subscriptions, or a release
   date decision may still require App Store Connect or other Apple tools.

The sample manifest does not imply a published release tag. Confirm permission
to use Apogee, package publication, and the adopter's selected version before
distributing a pinned dependency to other repositories.

## Commands and paths

Remote commands currently require a team API key, key ID, issuer ID, and private
key. Configure credentials as described in the [README](../README.md#configuration).
Keep the private key outside the repository. Team keys have account-wide app
access; a configured app ID selects Apogee's target but does not restrict the
key's permissions. Individual API keys are not supported by the current signer.

From the adopting release-tools package directory:

```sh
swift package plugin --allow-network-connections all apogee validate-metadata \
  --release-notes-only
swift package plugin --allow-network-connections all apogee release-status \
  --version 1.2.3
swift package plugin --allow-network-connections all apogee update-release-notes \
  --version 1.2.3 --dry-run
swift package plugin --allow-network-connections all apogee attach-build \
  --version 1.2.3 --build-version 123 --dry-run
swift package plugin --allow-network-connections all apogee submit-for-review \
  --version 1.2.3 --dry-run
```

The plugin runs in the consumer package directory. Relative paths inside
`apogee.json`, including omitted layout defaults, resolve beside that JSON file.
Explicit CLI path overrides resolve from the working directory. Thus an absolute
`--apogee-config` path also works outside the configuration directory.

`validate-metadata` checks selected local UTF-8 files, path safety, and that
matching metadata exists. It does not check Apple's locale availability,
character limits, editability, or account permissions. It needs no API credentials
and makes no network requests; SwiftPM may still fetch dependencies. Remote dry
runs authenticate and read App Store Connect.

Replace `--dry-run` with `--apply` only for the operation being approved. They
are mutually exclusive. `release-status` has no apply mode.

## Coordinate review and publication

`release-status` shows the version's App Store state, release type, earliest
release date in UTC, attached build, and matching review submissions. A review
submission in `COMPLETE` is not proof that the app is published. Check the version
state and the public storefront separately.

Submission plans also show release type and earliest release date:

| Release type | Timing responsibility |
| --- | --- |
| `MANUAL` | Release the approved version explicitly in App Store Connect. |
| `AFTER_APPROVAL` | Apple may publish the version after approval. |
| `SCHEDULED` | Apple applies the configured earliest release date after approval. |
| Unknown | Confirm the release setting in App Store Connect before applying. |

Set or change publication timing in App Store Connect before submission. Apogee
does not choose release dates, change release type, start phased release, or
publish an approved version. See Apple's
[release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/).

## Failure and recovery

- Metadata writes are sequential and not transactional. If a locale fails, earlier
  updates may already exist. Fix the cause, run a fresh dry run, and apply remaining
  differences. An error does not roll back earlier writes.
- Build selection uses the exact app, platform, marketing version, and build
  number. Processing state must be `VALID`. This does not prove export-compliance
  completion or App Review eligibility.
- Review submission checks the attached build and item linkage before submitting.
  It reuses a matching prepared submission or one unambiguous empty draft,
  including a draft left by a failed item-creation request. It rejects unknown,
  truncated, or extra items. Manage submissions that deliberately bundle other
  content in App Store Connect.
- If a review write times out, inspect `release-status` and run a fresh dry run.
  The request may have succeeded remotely. Apogee does not automatically retry
  writes or resubmit matching versions that are already submitted.
- Webhook sync validates event names and loads all required create/rotation secrets
  before writes. Deletions also require `--allow-destructive` and the exact token
  from a fresh dry run. Secret rotation is not observable in read-back; remove
  `rotateSecret` after a successful intentional rotation.
- HTTP errors preserve status and operation without response bodies or credentials.
  Resolve authentication, permission, resource-state, or rate-limit issues before
  retrying. Repeated, unsafe, or over-100-page collections fail closed.

Keep one writer per app/version or webhook configuration during apply. A dry run
does not lock remote resources, and these operations have no shared transaction.
Metadata plans contain full current and desired values. Keep real plan output and
unpublished adopter evidence in private storage.

## Capability boundaries

The initial supported path assumes the app, target version, locales, and uploaded
build already exist. Apogee does not archive or upload binaries, create versions
or locales, configure pricing or subscriptions, or edit review/privacy declarations.
Screenshot replacement and Xcode Cloud workflow sync remain unsupported. These
are explicit boundaries, not prerequisites for release-note and metadata adoption.

## Verification before a package release

Run [the repository checks](../AGENTS.md) and the consumer example on the supported
shipping Xcode. CI covers the first supported Swift tools series and the selected
Xcode 26 point release. Keep newer-Xcode results separate; a beta-only success
does not clear the shipping baseline. Runner availability is defined by the
[official image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).

Tests prove simulated API behavior and local consumer execution. They do not
establish real-account permissions, successful App Store Connect mutations,
App Review acceptance, storefront publication, or the adopting app's quality.
Those checks belong to the actual adopter and its intended release.

### Moving from 0.x to 1.0

Use the 0.x series to verify package distribution and the first adopter workflow.
Before declaring the documented interfaces stable:

- Confirm that the Release workflow publishes the intended commit, automatically
  increments a subsequent version, and reuses the same tag when rerun.
- Resolve an exact published tag from a separate macOS package and exercise both
  the library and command plugin. A local path dependency does not prove that
  the published package can be consumed.
- Pass the supported Xcode checks, then compare read-only release status with
  App Store Connect for the adopting app. Verify an approved metadata update on
  an editable version, including read-back and a fresh dry run with no changes.
- Review the documented API, CLI, configuration, and safety guarantees in the
  [versioning contract](../README.md#versioning-and-stability). Keep unsupported
  operations explicit and preserve the adopter's existing release process.

Keep real account results, unpublished metadata, and adoption decisions in the
adopting repository or private evidence storage. A successful package release
does not authorize an app submission or publication.
