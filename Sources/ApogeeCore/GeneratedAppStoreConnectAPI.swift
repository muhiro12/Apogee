import AppStoreConnectGenerated
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public struct GeneratedAppStoreConnectAPI: AppStoreConnectAPI {
    private let client: Client

    public init(credentials: AppStoreConnectCredentials, serverURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!) {
        let tokenProvider = AppStoreConnectTokenProvider(signer: .init(credentials: credentials))
        client = Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [
                AppStoreConnectAuthorizationMiddleware(tokenProvider: tokenProvider),
            ]
        )
    }

    public func app(id: String) async throws -> AppStoreConnectApp {
        let output = try await client.apps_getInstance(.init(
            path: .init(id: id),
            query: .init()
        ))
        return try mapApp(output.ok.body.json.data)
    }

    public func apps(bundleID: String) async throws -> [AppStoreConnectApp] {
        let output = try await client.apps_getCollection(.init(query: .init(
            filter_lbrack_bundleId_rbrack_: [bundleID],
            limit: 200
        )))
        return try output.ok.body.json.data.map(mapApp)
    }

    public func appStoreVersions(appID: String, version: String, platform: Platform) async throws -> [AppStoreConnectVersion] {
        let output = try await client.apps_appStoreVersions_getToManyRelated(.init(
            path: .init(id: appID),
            query: .init(
                filter_lbrack_platform_rbrack_: [platform.appStoreVersionsQuery],
                filter_lbrack_versionString_rbrack_: [version],
                limit: 200
            )
        ))
        return try output.ok.body.json.data.map(mapVersion)
    }

    public func appStoreVersionLocalizations(versionID: String) async throws -> [AppStoreConnectLocalization] {
        let output = try await client.appStoreVersions_appStoreVersionLocalizations_getToManyRelated(.init(
            path: .init(id: versionID),
            query: .init(limit: 200)
        ))
        return try output.ok.body.json.data.map(mapLocalization)
    }

    public func updateLocalization(id: String, patch: MetadataPatch) async throws -> AppStoreConnectLocalization {
        let request = Components.Schemas.AppStoreVersionLocalizationUpdateRequest(data: .init(
            attributes: .init(
                description: patch.description,
                keywords: patch.keywords,
                promotionalText: patch.promotionalText,
                whatsNew: patch.releaseNotes
            ),
            id: id,
            _type: .appStoreVersionLocalizations
        ))
        let output = try await client.appStoreVersionLocalizations_updateInstance(.init(
            path: .init(id: id),
            body: .json(request)
        ))
        return try mapLocalization(output.ok.body.json.data)
    }

    public func builds(appID: String, buildVersion: String, appStoreVersion: String, platform: Platform) async throws -> [AppStoreConnectBuild] {
        let output = try await client.builds_getCollection(.init(query: .init(
            filter_lbrack_version_rbrack_: [buildVersion],
            filter_lbrack_preReleaseVersion_period_version_rbrack_: [appStoreVersion],
            filter_lbrack_preReleaseVersion_period_platform_rbrack_: [platform.buildsQuery],
            filter_lbrack_app_rbrack_: [appID],
            limit: 200
        )))
        return try output.ok.body.json.data.map(mapBuild)
    }

    public func build(versionID: String) async throws -> AppStoreConnectBuild? {
        let output = try await client.appStoreVersions_build_getToOneRelated(.init(
            path: .init(id: versionID),
            query: .init()
        ))

        switch output {
        case let .ok(response):
            return try mapBuild(response.body.json.data)
        case .notFound:
            return nil
        default:
            throw ApogeeError.unexpectedAPIResponse("Unexpected build relationship response for version \(versionID).")
        }
    }

    public func attachBuild(versionID: String, buildID: String) async throws {
        let request = Components.Schemas.AppStoreVersionBuildLinkageRequest(data: .init(
            id: buildID,
            _type: .builds
        ))
        let output = try await client.appStoreVersions_build_updateToOneRelationship(.init(
            path: .init(id: versionID),
            body: .json(request)
        ))
        _ = try output.noContent
    }

    public func reviewSubmissions(appID: String, platform: Platform) async throws -> [AppStoreConnectReviewSubmission] {
        let output = try await client.reviewSubmissions_getCollection(.init(query: .init(
            filter_lbrack_platform_rbrack_: [platform.reviewSubmissionsQuery],
            filter_lbrack_app_rbrack_: [appID],
            limit: 200,
            include: [.appStoreVersionForReview]
        )))
        return try output.ok.body.json.data.map(mapReviewSubmission)
    }

    public func createReviewSubmission(appID: String, platform: Platform) async throws -> AppStoreConnectReviewSubmission {
        let request = Components.Schemas.ReviewSubmissionCreateRequest(data: .init(
            attributes: .init(platform: platform.generated),
            relationships: .init(app: .init(data: .init(id: appID, _type: .apps))),
            _type: .reviewSubmissions
        ))
        let output = try await client.reviewSubmissions_createInstance(.init(body: .json(request)))
        return try mapReviewSubmission(output.created.body.json.data)
    }

    public func createReviewSubmissionItem(submissionID: String, versionID: String) async throws -> AppStoreConnectReviewSubmissionItem {
        let request = Components.Schemas.ReviewSubmissionItemCreateRequest(data: .init(
            relationships: .init(
                appStoreVersion: .init(data: .init(id: versionID, _type: .appStoreVersions)),
                reviewSubmission: .init(data: .init(id: submissionID, _type: .reviewSubmissions))
            ),
            _type: .reviewSubmissionItems
        ))
        let output = try await client.reviewSubmissionItems_createInstance(.init(body: .json(request)))
        return try .init(id: output.created.body.json.data.id)
    }

    public func submitReviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        let request = Components.Schemas.ReviewSubmissionUpdateRequest(data: .init(
            attributes: .init(submitted: true),
            id: id,
            _type: .reviewSubmissions
        ))
        let output = try await client.reviewSubmissions_updateInstance(.init(
            path: .init(id: id),
            body: .json(request)
        ))
        return try mapReviewSubmission(output.ok.body.json.data)
    }

    public func reviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        let output = try await client.reviewSubmissions_getInstance(.init(
            path: .init(id: id),
            query: .init(include: [.appStoreVersionForReview])
        ))
        return try mapReviewSubmission(output.ok.body.json.data)
    }

    public func webhooks(appID: String) async throws -> [AppStoreConnectWebhook] {
        let output = try await client.apps_webhooks_getToManyRelated(.init(
            path: .init(id: appID),
            query: .init(limit: 200)
        ))
        return try output.ok.body.json.data.map(mapWebhook)
    }

    public func createWebhook(appID: String, webhook: DesiredWebhook, secret: String) async throws -> AppStoreConnectWebhook {
        let request = Components.Schemas.WebhookCreateRequest(data: .init(
            attributes: .init(
                enabled: webhook.enabled,
                eventTypes: try webhook.eventTypes.map(generatedWebhookEventType),
                name: webhook.name,
                secret: secret,
                url: webhook.url
            ),
            relationships: .init(app: .init(data: .init(id: appID, _type: .apps))),
            _type: .webhooks
        ))
        let output: Operations.webhooks_createInstance.Output
        do {
            output = try await client.webhooks_createInstance(.init(body: .json(request)))
        } catch let error as ClientError {
            throw sanitizedWebhookError(error, operation: "create a webhook")
        }
        return try mapWebhook(output.created.body.json.data)
    }

    public func updateWebhook(id: String, webhook: DesiredWebhook, secret: String?) async throws -> AppStoreConnectWebhook {
        let request = Components.Schemas.WebhookUpdateRequest(data: .init(
            attributes: .init(
                enabled: webhook.enabled,
                eventTypes: try webhook.eventTypes.map(generatedWebhookEventType),
                name: webhook.name,
                secret: secret,
                url: webhook.url
            ),
            id: id,
            _type: .webhooks
        ))
        let output: Operations.webhooks_updateInstance.Output
        do {
            output = try await client.webhooks_updateInstance(.init(
                path: .init(id: id),
                body: .json(request)
            ))
        } catch let error as ClientError {
            throw sanitizedWebhookError(error, operation: "update a webhook")
        }
        return try mapWebhook(output.ok.body.json.data)
    }

    public func deleteWebhook(id: String) async throws {
        let output = try await client.webhooks_deleteInstance(.init(path: .init(id: id)))
        _ = try output.noContent
    }

    private func mapApp(_ app: Components.Schemas.App) -> AppStoreConnectApp {
        .init(id: app.id, bundleID: app.attributes?.bundleId, name: app.attributes?.name)
    }

    private func mapVersion(_ version: Components.Schemas.AppStoreVersion) -> AppStoreConnectVersion {
        .init(
            id: version.id,
            versionString: version.attributes?.versionString,
            state: version.attributes?.appVersionState?.rawValue,
            platform: version.attributes?.platform.flatMap(Platform.init(generated:))
        )
    }

    private func mapLocalization(_ localization: Components.Schemas.AppStoreVersionLocalization) -> AppStoreConnectLocalization {
        let attributes = localization.attributes
        let locale = attributes?.locale ?? ""
        return .init(
            id: localization.id,
            locale: locale,
            metadata: .init(
                locale: locale,
                releaseNotes: attributes?.whatsNew,
                description: attributes?.description,
                keywords: attributes?.keywords,
                promotionalText: attributes?.promotionalText
            )
        )
    }

    private func mapBuild(_ build: Components.Schemas.Build) -> AppStoreConnectBuild {
        .init(
            id: build.id,
            version: build.attributes?.version,
            processingState: build.attributes?.processingState?.rawValue
        )
    }

    private func mapReviewSubmission(_ submission: Components.Schemas.ReviewSubmission) -> AppStoreConnectReviewSubmission {
        .init(
            id: submission.id,
            state: submission.attributes?.state?.rawValue,
            platform: submission.attributes?.platform.flatMap(Platform.init(generated:)),
            appStoreVersionID: submission.relationships?.appStoreVersionForReview?.data?.id
        )
    }

    private func mapWebhook(_ webhook: Components.Schemas.Webhook) -> AppStoreConnectWebhook {
        let attributes = webhook.attributes
        return .init(
            id: webhook.id,
            name: attributes?.name ?? "",
            url: attributes?.url ?? "",
            eventTypes: attributes?.eventTypes?.map(\.rawValue) ?? [],
            enabled: attributes?.enabled ?? false
        )
    }

    private func generatedWebhookEventType(_ rawValue: String) throws -> Components.Schemas.WebhookEventType {
        guard let eventType = Components.Schemas.WebhookEventType(rawValue: rawValue) else {
            throw ApogeeError.invalidWebhookEventType(rawValue)
        }

        return eventType
    }

    private func sanitizedWebhookError(_ error: ClientError, operation: String) -> any Error {
        if let apogeeError = error.underlyingError as? ApogeeError {
            return apogeeError
        }

        if error.underlyingError is CancellationError {
            return CancellationError()
        }

        return ApogeeError.appStoreConnectRequestFailed(operation: operation)
    }
}

private struct AppStoreConnectAuthorizationMiddleware: ClientMiddleware {
    var tokenProvider: AppStoreConnectTokenProvider

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(try await tokenProvider.token())"
        return try await next(request, body, baseURL)
    }
}

extension Platform {
    fileprivate var generated: Components.Schemas.Platform {
        switch self {
        case .iOS:
            .IOS
        case .macOS:
            .MAC_OS
        case .tvOS:
            .TV_OS
        case .visionOS:
            .VISION_OS
        }
    }

    fileprivate var appStoreVersionsQuery: Operations.apps_appStoreVersions_getToManyRelated.Input.Query.filter_lbrack_platform_rbrack_PayloadPayload {
        switch self {
        case .iOS:
            .IOS
        case .macOS:
            .MAC_OS
        case .tvOS:
            .TV_OS
        case .visionOS:
            .VISION_OS
        }
    }

    fileprivate var buildsQuery: Operations.builds_getCollection.Input.Query.filter_lbrack_preReleaseVersion_period_platform_rbrack_PayloadPayload {
        switch self {
        case .iOS:
            .IOS
        case .macOS:
            .MAC_OS
        case .tvOS:
            .TV_OS
        case .visionOS:
            .VISION_OS
        }
    }

    fileprivate var reviewSubmissionsQuery: Operations.reviewSubmissions_getCollection.Input.Query.filter_lbrack_platform_rbrack_PayloadPayload {
        switch self {
        case .iOS:
            .IOS
        case .macOS:
            .MAC_OS
        case .tvOS:
            .TV_OS
        case .visionOS:
            .VISION_OS
        }
    }

    fileprivate init?(generated: Components.Schemas.Platform) {
        switch generated {
        case .IOS:
            self = .iOS
        case .MAC_OS:
            self = .macOS
        case .TV_OS:
            self = .tvOS
        case .VISION_OS:
            self = .visionOS
        }
    }
}
