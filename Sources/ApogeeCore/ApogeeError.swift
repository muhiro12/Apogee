import Foundation

public enum ApogeeError: Error, Sendable, CustomStringConvertible, Equatable, LocalizedError {
    case missingEnvironmentVariable(String)
    case missingCredentialFile(String)
    case invalidPrivateKey(String)
    case invalidPath(String)
    case appNotFound(bundleID: String)
    case appAmbiguous(bundleID: String, matches: Int)
    case appStoreVersionNotFound(appID: String, version: String)
    case appStoreVersionAmbiguous(appID: String, version: String, matches: Int)
    case localizationMissing(locale: String)
    case buildNotFound(appID: String, buildVersion: String)
    case buildAmbiguous(appID: String, buildVersion: String, matches: Int)
    case buildNotReady(id: String, state: String?)
    case reviewSubmissionContentsUnsafe(id: String)
    case reviewSubmissionAmbiguous(versionID: String, matches: Int)
    case reviewSubmissionStateUnexpected(id: String, state: String?, expected: [String])
    case reviewSubmissionVersionMismatch(id: String, expectedVersionID: String, actualVersionID: String?)
    case duplicateWebhookName(String, source: String)
    case applyRequiresPlanToken
    case destructiveApplyRequiresConfirmation
    case appStoreConnectRequestFailed(operation: String)
    case appStoreConnectHTTPError(operation: String, statusCode: Int)
    case unexpectedAPIResponse(String)
    case invalidWebhookEventType(String)
    case unsupported(UnsupportedCapability)

    public var description: String {
        switch self {
        case let .missingEnvironmentVariable(name):
            "Missing required environment variable: \(name)."
        case let .missingCredentialFile(path):
            "Missing App Store Connect private key file: \(path)."
        case let .invalidPrivateKey(reason):
            "Invalid App Store Connect private key: \(reason)."
        case let .invalidPath(path):
            "Invalid path: \(path)."
        case let .appNotFound(bundleID):
            "No App Store Connect app matched bundle id \(bundleID)."
        case let .appAmbiguous(bundleID, matches):
            "Bundle id \(bundleID) matched \(matches) App Store Connect apps."
        case let .appStoreVersionNotFound(appID, version):
            "No App Store version \(version) was found for app \(appID)."
        case let .appStoreVersionAmbiguous(appID, version, matches):
            "App Store version \(version) for app \(appID) matched \(matches) versions."
        case let .localizationMissing(locale):
            "App Store Connect is missing required locale \(locale). Apogee does not create missing locales automatically."
        case let .buildNotFound(appID, buildVersion):
            "No build \(buildVersion) was found for app \(appID)."
        case let .buildAmbiguous(appID, buildVersion, matches):
            "Build \(buildVersion) for app \(appID) matched \(matches) builds."
        case let .buildNotReady(id, state):
            "Build \(id) is not ready: processing state is \(state ?? "unknown"), expected VALID."
        case let .reviewSubmissionContentsUnsafe(id):
            "Review submission \(id) has unknown or additional items. Reconcile its contents in App Store Connect before retrying."
        case let .reviewSubmissionAmbiguous(versionID, matches):
            "App Store version \(versionID) matched \(matches) review submissions."
        case let .reviewSubmissionStateUnexpected(id, state, expected):
            "Review submission \(id) read back state \(state ?? "nil"), expected one of: \(expected.joined(separator: ", "))."
        case let .reviewSubmissionVersionMismatch(id, expectedVersionID, actualVersionID):
            "Review submission \(id) read back appStoreVersionForReview \(actualVersionID ?? "nil"), expected \(expectedVersionID)."
        case let .duplicateWebhookName(name, source):
            "Duplicate webhook name \(name) in \(source)."
        case .applyRequiresPlanToken:
            "Destructive apply requires the plan token printed by a prior dry run."
        case .destructiveApplyRequiresConfirmation:
            "Destructive apply requires --allow-destructive."
        case let .appStoreConnectRequestFailed(operation):
            "App Store Connect request failed while attempting to \(operation)."
        case let .appStoreConnectHTTPError(operation, statusCode):
            "App Store Connect returned HTTP \(statusCode) for \(operation). Check API key access, the resource state, and rate limits before retrying."
        case let .unexpectedAPIResponse(message):
            "Unexpected App Store Connect API response: \(message)."
        case let .invalidWebhookEventType(eventType):
            "Invalid App Store Connect webhook event type: \(eventType)."
        case let .unsupported(capability):
            capability.description
        }
    }

    public var errorDescription: String? {
        description
    }
}
