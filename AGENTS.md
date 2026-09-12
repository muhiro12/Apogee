# Apogee repository contract

Apogee is a macOS release-operations package, not an iOS runtime dependency.
Keep app-specific product behavior and private release plans in adopting
repositories. Public documentation, comments, and identifiers use English;
localized metadata examples may use their locale's language.

## Boundaries

- `ApogeeCore` owns planning, validation, and verified execution.
- `apogee` and `ApogeeCommandPlugin` adapt that library to command-line use.
- Use the generated App Store Connect client. Regenerate committed sources with
  the maintainer tool described in `docs/openapi-generation.md`; do not hand-edit
  generated Swift or commit Apple's downloaded OpenAPI document.
- Preserve dry-run defaults, explicit apply, destructive plan confirmation,
  and fail-closed handling of unknown or incomplete remote state.
- Keep credentials, private keys, webhook secrets, real account payloads, and
  unpublished adopter metadata out of source control and test fixtures.

## Verification

From the repository root, use the documented SwiftPM checks:

```sh
swift test
swift test --package-path Tools/OpenAPIGeneration
swift build -c release --product apogee
bash Tests/Integration/cli-smoke.sh .build/release/apogee
```

For public library, CLI, or plugin changes, also run the two consumer commands
in `Examples/ReleaseTools/README.md`. Tests and smoke checks must not require real
App Store Connect credentials or make remote mutations. Preserve the supported
Swift tools baseline in every package manifest. Run `git diff --check` before
committing.

Use the actual release Xcode for compatibility evidence. Record Xcode and Swift
versions and keep newer-beta results separate. When using an active Xcode
workspace, discover its available actions, preserve its original scheme and
destination, and restore them after verification. SwiftPM is the repository's
standalone package and CI path.

Build/test success does not establish live API write permissions, App Review
acceptance, or publication. Keep those adopter checks separate; see
`docs/adoption.md`.
