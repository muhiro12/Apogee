import Foundation

/// Validation and adapter-support failures specific to version creation.
///
/// Kept separate from the existing error enums to preserve exhaustive consumer
/// switches. Shared lookup, request, and read-back failures use ``ApogeeError``.
public enum VersionCreationError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case invalidVersion(String)
    case versionAlreadyExists(appID: String, version: String)
    case unsupportedAdapter

    public var description: String {
        switch self {
        case let .invalidVersion(version):
            "Invalid App Store version \(version): provide a nonempty version without surrounding whitespace."
        case let .versionAlreadyExists(appID, version):
            "App Store version \(version) already exists for app \(appID). Inspect its release status instead of creating it again."
        case .unsupportedAdapter:
            "This App Store Connect adapter does not support version creation."
        }
    }

    public var errorDescription: String? {
        description
    }
}
