# Localized support and marketing URLs

Use `support_url.txt` and `marketing_url.txt` inside each existing metadata locale:

```text
AppStore/Metadata/ja/support_url.txt
AppStore/Metadata/ja/marketing_url.txt
```

`validate-metadata` checks these files offline. `update-metadata` includes them in
its default dry-run and updates existing localizations only with explicit `--apply`.
`read-metadata` preserves their full remote values in `supportURL` and `marketingURL`
JSON properties, including the distinction between `null` and `""`. Schema version
1 permits these additive properties. Plans use `support_url` and `marketing_url`
field identifiers with complete current and desired values.

Missing files leave remote fields unchanged. An empty marketing URL file requests
clearing the optional marketing URL. An empty support URL file is rejected because
Apple requires a support URL. Boundary newlines are trimmed as for other metadata;
internal newlines are invalid. `update-release-notes` ignores both files.

## Validation and verification

URLs must be absolute HTTP or HTTPS URLs with a nonempty host and an optional valid
port. Credentials, literal whitespace, control characters, backslashes, malformed
percent escapes, and percent-encoded ASCII control characters are rejected before
remote access. Unicode hosts and paths accepted by Foundation are supported;
Apogee preserves the supplied string rather than rewriting it. Remote snapshots
preserve observed strings even if they would fail local input validation.

Apogee does not request these URLs, resolve their hosts, or test page content,
reachability, redirects, or legal sufficiency. Apple performs server-side validation.
See Apple's [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
for the support/contact requirements and marketing URL description.

Apply verifies exact string values through a fresh remote read. A rejected update,
server normalization (including an empty value returned as null), partial write,
or mismatched read-back is an error, not a successful verification. Earlier writes
may persist after failure. Inspect `read-metadata` and obtain a fresh plan before
retrying; no rollback is claimed. No real-account permission or URL acceptance is
established by offline tests.

## Library migration

`LocalizedMetadata` and `MetadataPatch` expose optional `supportURL` and
`marketingURL` properties. `MetadataField` adds matching cases with file basenames
`support_url` and `marketing_url`. Existing exhaustive switches must add these
cases. This change is intentionally included in a minor release; see the
[public API migration note](public-api.md#metadata-url-migration).
