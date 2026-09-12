# ``ApogeeCore``

Plan, validate, and execute App Store Connect release operations from macOS tooling.

## Overview

Use ``ReleaseAutomation`` with ``GeneratedAppStoreConnectAPI`` for guarded
release operations. A dry-run reads current remote state and returns a
``ReleasePlan``; apply writes and verifies supported observable results.

Apogee is a release tool, not an iOS runtime dependency. API credentials and
unpublished release data belong in the adopting repository's private environment.
See <doc:UsingReleaseAutomation> for execution, errors, and transport boundaries.

## Topics

### Release operations

- <doc:UsingReleaseAutomation>
- ``ReleaseAutomation``
- ``ReleaseExecutionOptions``
- ``OperationMode``
- ``AppLookup``
- ``Platform``
- ``ReleaseStatus``

### Plans

- ``ReleasePlan``
- ``PlannedAction``
- ``PlannedActionKind``
- ``PlanRenderer``

### Repository configuration and credentials

- ``ApogeeConfiguration``
- ``AppStoreConnectCredentialEnvironment``
- ``AppStoreConnectCredentials``
- ``SecretEnvironment``

### Metadata and webhooks

- ``MetadataLoader``
- ``MetadataField``
- ``LocalizedMetadata``
- ``MetadataPatch``
- ``WebhookConfigurationLoader``
- ``WebhookSyncConfiguration``
- ``DesiredWebhook``

### Low-level API adapter

- ``AppStoreConnectAPI``
- ``GeneratedAppStoreConnectAPI``
- ``AppStoreConnectApp``
- ``AppStoreConnectVersion``
- ``AppStoreConnectLocalization``
- ``AppStoreConnectBuild``
- ``AppStoreConnectReviewSubmission``
- ``AppStoreConnectReviewSubmissionItem``
- ``AppStoreConnectWebhook``

### Errors and provisional capabilities

- ``ApogeeError``
- ``UnsupportedCapability``
- ``ScreenshotLoader``
- ``ScreenshotSet``
- ``ScreenshotFile``
