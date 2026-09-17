import Foundation

/// The effective publication policy after App Review approval.
public enum VersionReleasePolicy: Sendable, Hashable {
    case manual
    case afterApproval
    case scheduled(Date)

    var releaseType: String {
        switch self {
        case .manual: "MANUAL"
        case .afterApproval: "AFTER_APPROVAL"
        case .scheduled: "SCHEDULED"
        }
    }

    var earliestReleaseDate: Date? {
        if case let .scheduled(date) = self {
            return date
        }
        return nil
    }
}

/// Explicit version-level changes. Nil preserves the corresponding setting.
/// A scheduled policy always supplies its date; other policies never supply one.
public struct VersionSettingsPatch: Sendable, Hashable {
    public var copyright: String?
    public var releasePolicy: VersionReleasePolicy?

    public init(copyright: String? = nil, releasePolicy: VersionReleasePolicy? = nil) {
        self.copyright = copyright
        self.releasePolicy = releasePolicy
    }

    func validate(now: Date = .now) throws {
        if let copyright {
            guard !copyright.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !copyright.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw VersionSettingsError.invalidCopyright
            }
        }
        if let date = releasePolicy?.earliestReleaseDate {
            let seconds = date.timeIntervalSince1970
            guard seconds.isFinite, seconds <= 253_402_300_799,
                  seconds.rounded(.towardZero) == seconds, date > now else {
                throw VersionSettingsError.invalidDate
            }
        }
    }
}

/// Version-settings failures never imply rollback or permission to publish.
public enum VersionSettingsError: Error, Sendable, Equatable, LocalizedError {
    case invalidCopyright
    case invalidDate
    case invalidReleasePolicy
    case unsupportedAdapter
    case unknownState
    case remoteChanged
    case readBackMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidCopyright:
            "Copyright must be nonempty and contain no control characters."
        case .invalidDate:
            "Scheduled release requires a future whole-second ISO 8601 date with an explicit time zone."
        case .invalidReleasePolicy:
            "Use MANUAL, AFTER_APPROVAL, or SCHEDULED. Only SCHEDULED requires an earliest release date."
        case .unsupportedAdapter:
            "This adapter does not support version-settings updates."
        case .unknownState:
            "Version settings cannot be changed in an unknown, incomplete, or unsupported App Store state."
        case .remoteChanged:
            "The version changed before apply. Inspect its state and obtain a fresh plan."
        case .readBackMismatch:
            "Version-settings read-back did not match. A write may have occurred; inspect remote state before retrying."
        }
    }
}

extension AppStoreConnectVersion {
    var effectiveReleaseDate: Date? {
        releaseType == "SCHEDULED" ? earliestReleaseDate : nil
    }

    func validateSettingsIdentity(version: String, platform: Platform) throws {
        guard !id.isEmpty, versionString == version, self.platform == platform else {
            throw VersionSettingsError.unknownState
        }
    }

    func validateEditableSettings() throws {
        guard ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"].contains(state ?? ""),
              ["MANUAL", "AFTER_APPROVAL", "SCHEDULED"].contains(releaseType ?? ""),
              releaseType != "SCHEDULED" || earliestReleaseDate != nil else {
            throw VersionSettingsError.unknownState
        }
    }
}
