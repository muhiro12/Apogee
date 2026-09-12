import Foundation

/// A read-only snapshot; review submission and App Store publication are separate states.
public struct ReleaseStatus: Sendable, Hashable {
    public var app: AppStoreConnectApp
    public var version: AppStoreConnectVersion
    public var build: AppStoreConnectBuild?
    public var reviewSubmissions: [AppStoreConnectReviewSubmission]

    public init(
        app: AppStoreConnectApp,
        version: AppStoreConnectVersion,
        build: AppStoreConnectBuild?,
        reviewSubmissions: [AppStoreConnectReviewSubmission]
    ) {
        self.app = app
        self.version = version
        self.build = build
        self.reviewSubmissions = reviewSubmissions
    }
}
