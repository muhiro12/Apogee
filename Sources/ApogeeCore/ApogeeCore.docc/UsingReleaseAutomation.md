# Using release automation

Choose an explicit execution mode, inspect a plan, and handle partial execution.

## Construct the supported entry point

```swift
import ApogeeCore

let credentials = try AppStoreConnectCredentials.load()
let automation = ReleaseAutomation(
    api: GeneratedAppStoreConnectAPI(credentials: credentials)
)
let plan = try await automation.updateReleaseNotes(
    appLookup: .bundleID("com.example.app"),
    version: "1.2.3",
    metadataPath: "AppStore/Metadata",
    options: .init(mode: .dryRun)
)
print(PlanRenderer().render(plan))
```

This example needs a real account and matching remote resources when executed.
The separate `Examples/ReleaseTools` package compiles this same entry point but
only executes local metadata validation, so its verification requires no account.
Keep rendered plans private: they can include unpublished metadata.

The library requires an explicit mode. Changing it to `apply` authorizes writes;
destructive webhook deletions also need `allowDestructive` and a matching token
from a previous dry-run. Never treat the token as authentication or a remote lock.

## Understand failure and retry

Apply makes sequential requests and verifies supported observable results.
It is not transactional. An earlier patch, draft, item, attachment, or webhook
can persist after a later failure, cancellation, or timeout. Inspect the remote
state and obtain a new dry-run before retrying. Unknown state, ambiguous resources,
and incomplete review linkage are rejected rather than guessed.

Catch `CancellationError` separately from ``ApogeeError``. Request error cases
preserve useful operation/status categories without carrying raw response bodies,
headers, or underlying transport errors. Description wording is for people;
switch on enum cases when behavior depends on the category. Local loaders may
throw Foundation errors and injected adapters may throw custom errors.

``AppStoreConnectCredentials`` and ``SecretEnvironment`` redact their descriptions.
This is not universal output sanitization: explicitly accessed secrets, metadata,
paths, URLs, and caller-created error strings still need appropriate handling.
Webhook secrets cannot be read back; verification covers observable settings,
and `rotateSecret` should be cleared after an intended successful rotation.

## Choose the appropriate API boundary

``AppStoreConnectAPI`` is supported for custom adapters and tests. Its mutation
methods execute immediately and do not provide the automation layer's plan or
confirmation gates. Implementations must return all pages, preserve cancellation,
and keep unknown optional state distinct from confirmed absence.

The default ``GeneratedAppStoreConnectAPI`` transport uses an ephemeral URLSession
with no URL cache. Its `transport:` initializer intentionally exposes
`OpenAPIRuntime.ClientTransport`; declare direct OpenAPI runtime and HTTP types
dependencies when implementing a transport. A custom endpoint or transport
receives credentials and must be trusted. Generated schemas and JWT helpers
remain implementation details.

Screenshot inventory and `updateScreenshots` are provisional. Apply is disabled
until the complete upload and verification path exists. Review submission does
not establish approval, release timing correctness, or publication.
