import Foundation

/// A privacy-reduced feedback summary. Missing optional attributes remain unknown.
/// Tester identities, comments, artifact contents, and download URLs are excluded.
public struct BuildFeedbackSummary: Sendable, Hashable {
    public var id: String
    public var buildID: String
    public var createdDate: Date?
    public var deviceModel: String?
    public var osVersion: String?
    public var hasComment: Bool?

    public init(id: String, buildID: String, createdDate: Date? = nil,
                deviceModel: String? = nil, osVersion: String? = nil, hasComment: Bool? = nil) {
        self.id = id
        self.buildID = buildID
        self.createdDate = createdDate
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.hasComment = hasComment
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

    public var errorDescription: String? {
        switch self {
        case .unsupportedAdapter:
            "This App Store Connect adapter does not support build feedback inspection."
        case .incompleteInventory:
            "Feedback inventory is incomplete, duplicated, or does not match the selected build."
        }
    }
}
