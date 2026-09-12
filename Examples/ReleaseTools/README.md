# Release tools package example

This macOS package exercises both the `ApogeeCore` library and the command plugin
from a separate consumer. Its metadata and app identifier are fictional.

From the Apogee checkout root:

```sh
swift run --package-path Examples/ReleaseTools ReleaseToolsExample \
  Examples/ReleaseTools/AppStore/Metadata
swift package --package-path Examples/ReleaseTools plugin \
  --allow-network-connections all apogee validate-metadata
```

Neither command uses API credentials or contacts App Store Connect. SwiftPM may
download package dependencies. The plugin executes in the consumer package
directory, including when invoked with `--package-path` from another directory.

For adoption, place the package under the app repository's `Tools/Release`, change
the local dependency to an exact published Apogee tag, and commit the consumer's
`Package.resolved`. Set `metadataPath` in that package's `apogee.json` to
`../../AppStore/Metadata` if metadata lives at the app repository root. The sample
executable can be removed when only the command plugin is needed.

See [the adoption guide](../../docs/adoption.md) for staged rollout and recovery.
