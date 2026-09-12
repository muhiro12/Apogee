import Foundation

/// The supported low-level boundary for App Store Connect adapters and test doubles.
///
/// Mutation methods write immediately and do not enforce dry-run, confirmation, or
/// read-back verification; use ``ReleaseAutomation`` for those guarantees.
/// Implementations must return complete paginated collections, preserve unknown
/// optional state, propagate cancellation, and avoid exposing request secrets in errors.
/// A nil build means a known absent attachment; omitted build linkage must throw.
public protocol AppStoreConnectAPI: Sendable {
    /// Fetches one app by its App Store Connect resource ID.
    func app(id: String) async throws -> AppStoreConnectApp
    /// Returns all apps matching a bundle ID, including every page.
    func apps(bundleID: String) async throws -> [AppStoreConnectApp]
    /// Returns all matching marketing versions for the selected app and platform.
    func appStoreVersions(appID: String, version: String, platform: Platform) async throws -> [AppStoreConnectVersion]
    /// Returns all existing localizations of an App Store version.
    func appStoreVersionLocalizations(versionID: String) async throws -> [AppStoreConnectLocalization]
    /// Immediately patches one localization; nil fields are omitted.
    func updateLocalization(id: String, patch: MetadataPatch) async throws -> AppStoreConnectLocalization
    /// Finds builds scoped by app, build number, marketing version, and platform.
    func builds(appID: String, buildVersion: String, appStoreVersion: String, platform: Platform) async throws -> [AppStoreConnectBuild]
    /// Reads the attached build; nil means confirmed absence, not missing relationship data.
    func build(versionID: String) async throws -> AppStoreConnectBuild?
    /// Immediately replaces the selected version's build relationship.
    func attachBuild(versionID: String, buildID: String) async throws
    /// Returns all submissions for an app and platform, preserving incomplete item linkage as nil.
    func reviewSubmissions(appID: String, platform: Platform) async throws -> [AppStoreConnectReviewSubmission]
    /// Immediately creates a review draft without adding an item or submitting it.
    func createReviewSubmission(appID: String, platform: Platform) async throws -> AppStoreConnectReviewSubmission
    /// Immediately links a version to a review draft.
    func createReviewSubmissionItem(submissionID: String, versionID: String) async throws -> AppStoreConnectReviewSubmissionItem
    /// Immediately submits a review draft; this does not establish approval or publication.
    func submitReviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission
    /// Reads a review submission with its observed version and complete-or-nil item linkage.
    func reviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission
    /// Returns every webhook for the app, without signing secrets.
    func webhooks(appID: String) async throws -> [AppStoreConnectWebhook]
    /// Immediately creates a webhook using the supplied secret; never log the secret.
    func createWebhook(appID: String, webhook: DesiredWebhook, secret: String) async throws -> AppStoreConnectWebhook
    /// Immediately updates a webhook; a nil secret preserves the existing remote secret.
    func updateWebhook(id: String, webhook: DesiredWebhook, secret: String?) async throws -> AppStoreConnectWebhook
    /// Immediately deletes a webhook without plan confirmation.
    func deleteWebhook(id: String) async throws
}

/// An app resource returned by App Store Connect; omitted attributes remain nil.
public struct AppStoreConnectApp: Sendable, Hashable {
    public var id: String
    public var bundleID: String?
    public var name: String?

    public init(id: String, bundleID: String? = nil, name: String? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
    }
}

/// An App Store version snapshot with optional server attributes.
///
/// State and release type preserve server strings. Nil means unavailable, not a safe
/// editable state. The earliest release date does not prove publication or approval.
public struct AppStoreConnectVersion: Sendable, Hashable {
    public var id: String
    public var versionString: String?
    public var state: String?
    public var platform: Platform?
    public var releaseType: String?
    public var earliestReleaseDate: Date?

    public init(id: String, versionString: String? = nil, state: String? = nil, platform: Platform? = nil, releaseType: String? = nil, earliestReleaseDate: Date? = nil) {
        self.id = id
        self.versionString = versionString
        self.state = state
        self.platform = platform
        self.releaseType = releaseType
        self.earliestReleaseDate = earliestReleaseDate
    }
}

/// A remote localization and its currently observable metadata fields.
public struct AppStoreConnectLocalization: Sendable, Hashable {
    public var id: String
    public var locale: String
    public var metadata: LocalizedMetadata

    public init(id: String, locale: String, metadata: LocalizedMetadata) {
        self.id = id
        self.locale = locale
        self.metadata = metadata
    }
}

/// Fields to update on one existing localization.
///
/// Nil omits a field from the request. An empty string explicitly clears its value;
/// acceptance still depends on App Store Connect validation and the version state.
public struct MetadataPatch: Sendable, Hashable {
    public var releaseNotes: String?
    public var description: String?
    public var keywords: String?
    public var promotionalText: String?

    public init(
        releaseNotes: String? = nil,
        description: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil
    ) {
        self.releaseNotes = releaseNotes
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
    }

    public var isEmpty: Bool {
        releaseNotes == nil && description == nil && keywords == nil && promotionalText == nil
    }
}

/// An uploaded build snapshot; automation requires a known `VALID` processing state.
public struct AppStoreConnectBuild: Sendable, Hashable {
    public var id: String
    public var version: String?
    public var processingState: String?

    public init(id: String, version: String? = nil, processingState: String? = nil) {
        self.id = id
        self.version = version
        self.processingState = processingState
    }
}

/// A review submission with observed version and item relationships.
///
/// Missing relationships must remain nil. An empty, complete item list is distinct
/// from unavailable linkage and can affect whether a draft is safe to reuse.
public struct AppStoreConnectReviewSubmission: Sendable, Hashable {
    public var id: String
    public var state: String?
    public var platform: Platform?
    public var appStoreVersionID: String?
    /// The complete item linkage, or nil when it was omitted or truncated.
    public var itemIDs: [String]?

    public init(id: String, state: String? = nil, platform: Platform? = nil, appStoreVersionID: String? = nil, itemIDs: [String]? = nil) {
        self.id = id
        self.state = state
        self.platform = platform
        self.appStoreVersionID = appStoreVersionID
        self.itemIDs = itemIDs
    }
}

/// The identity of an item linking an App Store version to a review submission.
public struct AppStoreConnectReviewSubmissionItem: Sendable, Hashable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

/// Observable webhook settings; App Store Connect does not return the signing secret.
public struct AppStoreConnectWebhook: Sendable, Hashable {
    public var id: String
    public var name: String
    public var url: String
    public var eventTypes: [String]
    public var enabled: Bool

    public init(id: String, name: String, url: String, eventTypes: [String], enabled: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.eventTypes = eventTypes
        self.enabled = enabled
    }
}
