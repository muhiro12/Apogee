import Foundation

/// A sensitive time-limited location for one downloadable feedback artifact.
///
/// The URL is a capability supplied by App Store Connect. Never print, log, or persist
/// it; use ``BuildFeedbackExport`` to write the artifact to explicit private storage.
public struct BuildFeedbackArtifact: Sendable, Hashable {
    public var url: String
    public var expirationDate: Date?
    public var width: Int?
    public var height: Int?

    public init(url: String, expirationDate: Date? = nil, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.expirationDate = expirationDate
        self.width = width
        self.height = height
    }
}

/// An explicit private destination for exported feedback artifacts.
///
/// Exported screenshots are tester-supplied material that can contain personal data.
/// Apogee downloads nothing without this destination, creates it with owner-only
/// permissions, and never overwrites an existing file.
public struct BuildFeedbackExport: Sendable {
    public var directory: String

    public init(directory: String) {
        self.directory = directory
    }
}

/// A privacy-reduced feedback summary. Missing optional attributes remain unknown.
/// Tester identities, comments, and artifact contents are excluded. Artifact locations
/// are carried for an explicit export only and are excluded from rendered output.
public struct BuildFeedbackSummary: Sendable, Hashable {
    public var id: String
    public var buildID: String
    public var createdDate: Date?
    public var deviceModel: String?
    public var osVersion: String?
    public var hasComment: Bool?
    /// Whether Apple reported downloadable artifacts for this submission; nil is unknown.
    public var hasArtifact: Bool?
    /// Sensitive artifact locations Apogee can export, in the order Apple reported them.
    public var artifacts: [BuildFeedbackArtifact]
    /// Files written by an explicit export, relative to its destination directory.
    public var exportedFiles: [String]

    public init(id: String, buildID: String, createdDate: Date? = nil,
                deviceModel: String? = nil, osVersion: String? = nil, hasComment: Bool? = nil,
                hasArtifact: Bool? = nil, artifacts: [BuildFeedbackArtifact] = [],
                exportedFiles: [String] = []) {
        self.id = id
        self.buildID = buildID
        self.createdDate = createdDate
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.hasComment = hasComment
        self.hasArtifact = hasArtifact
        self.artifacts = artifacts
        self.exportedFiles = exportedFiles
    }
}

/// Read-only feedback observed for one candidate build; counts are not release gates.
public struct BuildFeedback: Sendable, Hashable {
    public var app: AppStoreConnectApp
    public var version: String
    public var platform: Platform
    public var build: AppStoreConnectBuild
    public var crashes: [BuildFeedbackSummary]
    public var screenshots: [BuildFeedbackSummary]

    public init(app: AppStoreConnectApp, version: String, platform: Platform,
                build: AppStoreConnectBuild, crashes: [BuildFeedbackSummary], screenshots: [BuildFeedbackSummary]) {
        self.app = app
        self.version = version
        self.platform = platform
        self.build = build
        self.crashes = crashes
        self.screenshots = screenshots
    }
}

/// Failures specific to feedback inspection, preserving existing error enums.
public enum BuildFeedbackError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedAdapter
    case incompleteInventory
    case invalidExportDestination
    case exportConflict
    case unsafeArtifact

    public var errorDescription: String? {
        switch self {
        case .unsupportedAdapter:
            "This App Store Connect adapter does not support build feedback inspection."
        case .incompleteInventory:
            "Feedback inventory is incomplete, duplicated, or does not match the selected build."
        case .invalidExportDestination:
            "Artifact export requires an explicit private directory whose parent exists and which is not a symbolic link."
        case .exportConflict:
            "An artifact file already exists at the export destination. Choose an unused destination; existing files are never overwritten."
        case .unsafeArtifact:
            "An artifact location, identity, or downloaded payload is unsafe or expired. No artifact was exported for it."
        }
    }
}
