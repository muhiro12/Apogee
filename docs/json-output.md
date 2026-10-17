# JSON command results

Use `--output json` to consume `release-status` and plan command results without
parsing the human renderer. `--output text` remains the default for those commands.
This includes `validate-metadata`, `create-version`, `update-release-notes`,
`update-metadata`, `attach-build`, `update-screenshots`, `submit-for-review`, and
`sync-webhooks`. `read-metadata` keeps its existing JSON
[snapshot format](metadata-snapshots.md) and `--save-to` behavior.

```sh
apogee release-status --version 2.0 --output json
apogee update-release-notes --version 2.0 --dry-run --output json
apogee create-version --version 2.0 --apply --output json
```

## Success and failure

The direct executable writes one complete JSON document to stdout only after the
operation succeeds. Errors remain on stderr with the existing nonzero exit behavior;
there is no JSON error document. Argument errors and cancellation do not become
successful results. Help remains normal command help rather than a data result.

`update-screenshots --progress` optionally writes stage observations to stderr
while preserving this final JSON contract. Progress is quiet by default, is not
part of the JSON schema, and does not establish operation success. Keep stderr
separate from stdout. See [screenshot progress](screenshots.md#optional-progress).

Always check the exit status before consuming a result. Empty stdout on failure
does **not** imply that no remote write happened: an apply may have partially
completed or failed verification. Inspect remote state before retrying. JSON output
does not change the dry-run/apply boundary or add transactions, rollback, or retries.

For example, after a successful command this check establishes that its fresh
metadata plan has no mutations or unsupported actions:

```sh
if apogee update-metadata --version 2.0 --dry-run --output json > plan.json; then
  jq -e '.schemaVersion == 1 and .kind == "release-plan" and
    .command == "update-metadata" and .mode == "dry-run" and
    .plan.hasChanges == false and .plan.hasUnsupportedActions == false' plan.json
else
  exit 1
fi
```

Use private storage for this file. Metadata, current/desired diffs, app names, and
resource identifiers are deliberately included without truncation. Credentials,
JWTs, webhook signing secrets, authorization headers, and raw wrapped errors are
excluded. JSON escaping preserves multiline text, Unicode, empty strings, and
control characters when decoded; do not print decoded untrusted values directly
to a terminal without appropriate escaping.

## Schema version 1

Every result contains integer `schemaVersion: 1`, `kind`, `command`, `mode`,
`requestedTarget`, and `target`. Within this schema, compatible fields may be added;
readers must ignore unknown object fields and key ordering. Existing field types,
meanings, and nullability remain stable. Incompatible changes require a new schema
version and an Apogee major release. No permanent multi-schema selector is promised.
Readers should check the schema version, result kind, and expected command before
using the payload, and fail closed on unrecognized modes or action kinds.

| Field | Meaning |
| --- | --- |
| `kind` | `release-status` or `release-plan` |
| `command` | The invoked command name |
| `mode` | `read-only` for status; `local` for offline validation; `dry-run` or `apply` for remote plans |
| `requestedTarget` | Effective lookup after CLI/configuration precedence: nullable `appID`, `bundleID`, `version`, and `platform`. Only the selected app lookup is populated. Null for local validation. |
| `target` | Observed `app` and nullable `version` resources. Null for local validation. Requested values are never substituted for missing remote attributes. |

The app object contains `id`, nullable `bundleID`, and nullable `name`. A plan's
version object contains only identity fields: `id`, nullable `versionString`, and
nullable `platform`. Pre-apply lifecycle state is not presented as post-apply
status. A version object is absent (`null`) for app-scoped webhook plans and a
version-creation dry-run. Successful creation reports the identity read back.

### Release status

The `status` object contains `build` and `reviewSubmissions`:

For this result kind, `target.version` also contains nullable `state`, `releaseType`,
and `earliestReleaseDate` (UTC ISO 8601 with fractional seconds). State and release
type are server strings. Null means unavailable or unset, not a default state.

- `build` is null for a confirmed absent attachment, otherwise an object with
  `id`, nullable `version`, and nullable `processingState`.
- `reviewSubmissions` is an array sorted by ID. Each entry contains `id`, nullable
  `state`, `platform`, `appStoreVersionID`, and `itemIDs`. Null item IDs mean
  unavailable linkage; an empty array means a known empty item list.

This is a read-only observation. Successful output does not imply approval,
publication, write permission, or readiness to submit.

### Plans and verification

The `plan` object contains:

- `title`: descriptive text, not a parsing contract.
- `token`: the opaque plan confirmation token used by existing destructive gates.
  Changing output format does not change it. It is not a lock or authorization.
- `hasChanges` and `plannedMutationCount`: whether and how many actions have kind
  `create`, `update`, `delete`, or `attach`. The count is of plan actions, not HTTP
  requests, resources, or remaining changes after apply. An apply result describes
  the plan that ran; use a fresh dry-run to observe remaining differences.
- `hasDestructiveActions` and `hasUnsupportedActions`: independent flags. A zero
  mutation count does not imply that a provisional operation is supported.
- `actions`: the ordered actions, each with `kind`, `resource`, `locale`, `field`,
  `fieldLabel`, `currentValue`, `desiredValue`, and `isDestructive`.

Action kinds are `create`, `update`, `delete`, `attach`, `unchanged`, `verify`, and
`unsupported`. `resource` is an opaque resource identifier and can name a prospective
resource without an ID. `locale` and `field` are nullable machine identifiers.
Metadata fields use `release_notes`, `description`, `keywords`,
`promotional_text`, `support_url`, and `marketing_url`. `fieldLabel` is nullable
display text. Other action types without a specific metadata field have null field
identifiers.

Current and desired values are nullable strings; null is distinct from an empty
string. Metadata field values are complete text. For other operations, values can
be human summaries rather than separately parseable sub-schemas. Do not parse the
plan title, field label, summaries, or verification details for control flow.

The separate `verification` object contains `status` (`performed` or
`not-performed`) and a `checks` array. Each reported successful check includes
`resource`, nullable `locale`, `status: "passed"`, `scope` (`local-validation` or
`read-back`), and nullable descriptive `details`. Only verification actions actually
returned by Core are reported. An apply with an already-attached build, for example,
has no separate read-back check and reports `not-performed`.

These checks have the scope of the underlying operation. They do not certify all
remote fields, App Review acceptance, or webhook secret contents; webhook read-back
only covers observable settings. A failure returns no successful result document.

## Candidate build feedback

`build-feedback --output json` uses the additional `build-feedback` result kind.
Its target and feedback fields are described in [candidate build feedback](build-feedback.md#json).
The same success-only output and schema evolution rules apply.

## SwiftPM plugin

The plugin forwards `--output json` unchanged. SwiftPM may emit its own build and
plugin diagnostics outside Apogee's output contract. Prefer the direct executable
when stdout must contain only a JSON document; do not combine stderr with stdout
or attempt to extract JSON by stripping arbitrary SwiftPM log lines.
