# Read-only metadata snapshots

`read-metadata` reads every localization of an explicitly selected app version.
It uses the same app lookup, platform defaults, credentials, paginated API
adapter, safe errors, and cancellation behavior as other release operations.
It never updates App Store Connect and accepts neither `--apply` nor `--dry-run`.
No local desired metadata is needed.

```sh
apogee read-metadata --app-id EXAMPLE_APP_ID --platform IOS --version 2.0
apogee read-metadata --app-id EXAMPLE_APP_ID --platform IOS --version 2.0 \
  --save-to /private/path/before-update.json
```

Both commands print a complete JSON document to stdout. `--save-to` also writes
the same bytes to a new file, relative to the working directory if not absolute.
The parent directory must exist. Existing files, directories, and symbolic links
are not overwritten; a save failure exits unsuccessfully without printing a
success document. A disk failure can leave an incomplete new file: remove it or
choose a new destination before retrying. Diagnostics go to stderr.

For the SwiftPM plugin, grant write access only to the intended export directory:

```sh
swift package plugin --allow-network-connections all \
  --allow-writing-to-directory /private/path apogee read-metadata \
  --app-id EXAMPLE_APP_ID --platform IOS --version 2.0 \
  --save-to /private/path/before-update.json
```

SwiftPM may emit build and plugin diagnostics; use the direct executable when
stdout must contain only JSON, or use `--save-to` to consume the snapshot file.

## Snapshot format

```json
{
  "schemaVersion": 1,
  "kind": "metadata-snapshot",
  "app": {"id": "app-1", "bundleID": "com.example.app", "name": null},
  "version": {"id": "version-1", "versionString": "2.0", "platform": "IOS"},
  "localizations": [
    {
      "id": "localization-1",
      "locale": "ja",
      "releaseNotes": "更新内容\n次の行",
      "description": null,
      "keywords": "",
      "promotionalText": "紹介文",
      "supportURL": "https://example.com/support",
      "marketingURL": null
    }
  ]
}
```

`schemaVersion` identifies this snapshot format. Within version 1, field meanings
and types remain compatible; readers should ignore additional fields and object
key order. Incompatible changes require a new schema version and follow Apogee's
public CLI semantic-versioning contract.

App and version IDs identify the resolved remote resources. Optional app and
version attributes remain JSON `null` when unavailable; requested values are not
substituted for missing remote attributes. Localizations include their remote
IDs, are sorted by locale, and may be an empty array. Missing locale identity or
duplicate IDs/locales fail instead of producing an ambiguous snapshot.

All six supported metadata fields are always present. JSON `null` means unset
or unavailable in the API response, while `""` is an observed empty string.
Leading/trailing whitespace, embedded newlines, and Unicode survive JSON decoding
unchanged. No truncation or metadata-loader newline trimming is applied.

This is an inspection format, not an importable `AppStore/Metadata` directory.
Do not convert null values into empty update files: an empty input requests a
remote clear. Capture snapshots before and after an approved update to inspect
stored values, including after a partial write. The same adapter's read-back is
not an independent test of that adapter or a lock against later remote changes.

Credentials, authorization headers, JWTs, and raw wrapped errors are excluded.
The intentionally included metadata can be unpublished or private. Keep stdout,
snapshot files, and comparisons in private storage outside public source control.
