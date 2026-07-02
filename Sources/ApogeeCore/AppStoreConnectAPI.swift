import Foundation

public protocol AppStoreConnectAPI: Sendable {
    func app(id: String) async throws -> AppStoreConnectApp
    func apps(bundleID: String) async throws -> [AppStoreConnectApp]
    func appStoreVersions(appID: String, version: String, platform: Platform) async throws -> [AppStoreConnectVersion]
    func appStoreVersionLocalizations(versionID: String) async throws -> [AppStoreConnectLocalization]
    func updateLocalization(id: String, patch: MetadataPatch) async throws -> AppStoreConnectLocalization
    func builds(appID: String, buildVersion: String, platform: Platform) async throws -> [AppStoreConnectBuild]
    func build(versionID: String) async throws -> AppStoreConnectBuild?
    func attachBuild(versionID: String, buildID: String) async throws
    func reviewSubmissions(appID: String, platform: Platform) async throws -> [AppStoreConnectReviewSubmission]
    func createReviewSubmission(appID: String, platform: Platform) async throws -> AppStoreConnectReviewSubmission
    func createReviewSubmissionItem(submissionID: String, versionID: String) async throws -> AppStoreConnectReviewSubmissionItem
    func submitReviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission
    func reviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission
    func webhooks(appID: String) async throws -> [AppStoreConnectWebhook]
    func createWebhook(appID: String, webhook: DesiredWebhook, secret: String) async throws -> AppStoreConnectWebhook
    func updateWebhook(id: String, webhook: DesiredWebhook, secret: String?) async throws -> AppStoreConnectWebhook
    func deleteWebhook(id: String) async throws
}

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

public struct AppStoreConnectVersion: Sendable, Hashable {
    public var id: String
    public var versionString: String?
    public var state: String?
    public var platform: Platform?

    public init(id: String, versionString: String? = nil, state: String? = nil, platform: Platform? = nil) {
        self.id = id
        self.versionString = versionString
        self.state = state
        self.platform = platform
    }
}

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

public struct AppStoreConnectReviewSubmission: Sendable, Hashable {
    public var id: String
    public var state: String?
    public var platform: Platform?

    public init(id: String, state: String? = nil, platform: Platform? = nil) {
        self.id = id
        self.state = state
        self.platform = platform
    }
}

public struct AppStoreConnectReviewSubmissionItem: Sendable, Hashable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

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
