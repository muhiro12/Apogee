# OpenAPI Generation

Apogee uses Swift source generated from Apple's App Store Connect API OpenAPI
specification, but the Apple OpenAPI document itself is not redistributed in
this repository.

Maintainers update the generated client by running:

```sh
Scripts/update-generated-app-store-connect-client.sh
```

The script downloads the current Apple OpenAPI zip, trims it to the operations
Apogee uses, creates a temporary Swift package under `.build/`, runs Swift
OpenAPI Generator, and copies only the generated Swift sources into
`Sources/AppStoreConnectGenerated/GeneratedSources/`.

The trim step keeps the selected fields and operations but removes OpenAPI
`deprecated` markers from the generator input. Swift OpenAPI Generator currently
turns those markers into Swift deprecation annotations that are then referenced
inside generated initializers, producing noisy build warnings for package users.

The generated Swift sources are committed so package users do not need to fetch
Apple's OpenAPI document or run the generator during normal `swift build`.

Current generation baseline:

- Source URL: `https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip`
- Download checked: `2026-07-02`
- Apple zip `Last-Modified`: `2026-06-12 22:26:57 GMT`
- App Store Connect API version in spec: `4.4`
- Swift OpenAPI Generator version: `1.12.2`
