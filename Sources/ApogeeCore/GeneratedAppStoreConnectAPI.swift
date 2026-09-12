import AppStoreConnectGenerated
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public struct GeneratedAppStoreConnectAPI: AppStoreConnectAPI {
    private let serverURL: URL
    private let transport: any ClientTransport
    private let tokenProvider: AppStoreConnectTokenProvider

    public init(
        credentials: AppStoreConnectCredentials,
        serverURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!,
        transport: any ClientTransport = URLSessionTransport()
    ) {
        self.serverURL = serverURL
        self.transport = transport
        tokenProvider = .init(signer: .init(credentials: credentials))
    }

    private func client(nextPageURL: String? = nil) -> Client {
        .init(
            serverURL: serverURL,
            configuration: .init(dateTranscoder: AppStoreConnectDateTranscoder()),
            transport: transport,
            middlewares: [
                AppStoreConnectPageMiddleware(nextPageURL: nextPageURL),
                AppStoreConnectAuthorizationMiddleware(tokenProvider: tokenProvider),
            ]
        )
    }

    public func app(id: String) async throws -> AppStoreConnectApp {
        try await perform(operation: "app") {
            let output = try await client().apps_getInstance(.init(
                path: .init(id: id),
                query: .init()
            ))
            return try mapApp(output.ok.body.json.data)
        }
    }

    public func apps(bundleID: String) async throws -> [AppStoreConnectApp] {
        try await perform(operation: "apps") {
            try await allPages { pageClient in
                let output = try await pageClient.apps_getCollection(.init(query: .init(
                    filter_lbrack_bundleId_rbrack_: [bundleID],
                    limit: 200
                )))
                let response = try output.ok.body.json
                return (response.data.map(mapApp), response.links.next)
            }
        }
    }

    public func appStoreVersions(appID: String, version: String, platform: Platform) async throws -> [AppStoreConnectVersion] {
        try await perform(operation: "appStoreVersions") {
            try await allPages { pageClient in
                let output = try await pageClient.apps_appStoreVersions_getToManyRelated(.init(
                    path: .init(id: appID),
                    query: .init(
                        filter_lbrack_platform_rbrack_: [platform.appStoreVersionsQuery],
                        filter_lbrack_versionString_rbrack_: [version],
                        limit: 200
                    )
                ))
                let response = try output.ok.body.json
                return (response.data.map(mapVersion), response.links.next)
            }
        }
    }

    public func appStoreVersionLocalizations(versionID: String) async throws -> [AppStoreConnectLocalization] {
        try await perform(operation: "appStoreVersionLocalizations") {
            try await allPages { pageClient in
                let output = try await pageClient.appStoreVersions_appStoreVersionLocalizations_getToManyRelated(.init(
                    path: .init(id: versionID),
                    query: .init(limit: 200)
                ))
                let response = try output.ok.body.json
                return (response.data.map(mapLocalization), response.links.next)
            }
        }
    }

    public func updateLocalization(id: String, patch: MetadataPatch) async throws -> AppStoreConnectLocalization {
        try await perform(operation: "updateLocalization") {
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
            let output = try await client().appStoreVersionLocalizations_updateInstance(.init(
                path: .init(id: id),
                body: .json(request)
            ))
            return try mapLocalization(output.ok.body.json.data)
        }
    }

    public func builds(appID: String, buildVersion: String, appStoreVersion: String, platform: Platform) async throws -> [AppStoreConnectBuild] {
        try await perform(operation: "builds") {
            try await allPages { pageClient in
                let output = try await pageClient.builds_getCollection(.init(query: .init(
                    filter_lbrack_version_rbrack_: [buildVersion],
                    filter_lbrack_preReleaseVersion_period_version_rbrack_: [appStoreVersion],
                    filter_lbrack_preReleaseVersion_period_platform_rbrack_: [platform.buildsQuery],
                    filter_lbrack_app_rbrack_: [appID],
                    limit: 200
                )))
                let response = try output.ok.body.json
                return (response.data.map(mapBuild), response.links.next)
            }
        }
    }

    public func build(versionID: String) async throws -> AppStoreConnectBuild? {
        try await perform(operation: "build") {
            let output = try await client().appStoreVersions_getInstance(.init(
                path: .init(id: versionID),
                query: .init(fields_lbrack_appStoreVersions_rbrack_: [.build], include: [.build])
            ))
            guard let relationship = try output.ok.body.json.data.relationships?.build else {
                throw ApogeeError.unexpectedAPIResponse("The version response omitted its build relationship.")
            }
            guard let buildID = relationship.data?.id else {
                return nil
            }
            let buildOutput = try await client().builds_getInstance(.init(path: .init(id: buildID)))
            return try mapBuild(buildOutput.ok.body.json.data)
        }
    }

    public func attachBuild(versionID: String, buildID: String) async throws {
        try await perform(operation: "attachBuild") {
            let request = Components.Schemas.AppStoreVersionBuildLinkageRequest(data: .init(
                id: buildID,
                _type: .builds
            ))
            let output = try await client().appStoreVersions_build_updateToOneRelationship(.init(
                path: .init(id: versionID),
                body: .json(request)
            ))
            _ = try output.noContent
        }
    }

    public func reviewSubmissions(appID: String, platform: Platform) async throws -> [AppStoreConnectReviewSubmission] {
        try await perform(operation: "reviewSubmissions") {
            try await allPages { pageClient in
                let output = try await pageClient.reviewSubmissions_getCollection(.init(query: .init(
                    filter_lbrack_platform_rbrack_: [platform.reviewSubmissionsQuery],
                    filter_lbrack_app_rbrack_: [appID],
                    limit: 200,
                    include: [.appStoreVersionForReview, .items],
                    limit_lbrack_items_rbrack_: 50
                )))
                let response = try output.ok.body.json
                return (response.data.map(mapReviewSubmission), response.links.next)
            }
        }
    }

    public func createReviewSubmission(appID: String, platform: Platform) async throws -> AppStoreConnectReviewSubmission {
        try await perform(operation: "createReviewSubmission") {
            let request = Components.Schemas.ReviewSubmissionCreateRequest(data: .init(
                attributes: .init(platform: platform.generated),
                relationships: .init(app: .init(data: .init(id: appID, _type: .apps))),
                _type: .reviewSubmissions
            ))
            let output = try await client().reviewSubmissions_createInstance(.init(body: .json(request)))
            return try mapReviewSubmission(output.created.body.json.data)
        }
    }

    public func createReviewSubmissionItem(submissionID: String, versionID: String) async throws -> AppStoreConnectReviewSubmissionItem {
        try await perform(operation: "createReviewSubmissionItem") {
            let request = Components.Schemas.ReviewSubmissionItemCreateRequest(data: .init(
                relationships: .init(
                    appStoreVersion: .init(data: .init(id: versionID, _type: .appStoreVersions)),
                    reviewSubmission: .init(data: .init(id: submissionID, _type: .reviewSubmissions))
                ),
                _type: .reviewSubmissionItems
            ))
            let output = try await client().reviewSubmissionItems_createInstance(.init(body: .json(request)))
            return try .init(id: output.created.body.json.data.id)
        }
    }

    public func submitReviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        try await perform(operation: "submitReviewSubmission") {
            let request = Components.Schemas.ReviewSubmissionUpdateRequest(data: .init(
                attributes: .init(submitted: true),
                id: id,
                _type: .reviewSubmissions
            ))
            let output = try await client().reviewSubmissions_updateInstance(.init(
                path: .init(id: id),
                body: .json(request)
            ))
            return try mapReviewSubmission(output.ok.body.json.data)
        }
    }

    public func reviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        try await perform(operation: "reviewSubmission") {
            let output = try await client().reviewSubmissions_getInstance(.init(
                path: .init(id: id),
                query: .init(include: [.appStoreVersionForReview, .items], limit_lbrack_items_rbrack_: 50)
            ))
            return try mapReviewSubmission(output.ok.body.json.data)
        }
    }

    public func webhooks(appID: String) async throws -> [AppStoreConnectWebhook] {
        try await perform(operation: "webhooks") {
            try await allPages { pageClient in
                let output = try await pageClient.apps_webhooks_getToManyRelated(.init(
                    path: .init(id: appID),
                    query: .init(limit: 200)
                ))
                let response = try output.ok.body.json
                return (response.data.map(mapWebhook), response.links.next)
            }
        }
    }

    public func createWebhook(appID: String, webhook: DesiredWebhook, secret: String) async throws -> AppStoreConnectWebhook {
        try await perform(operation: "create a webhook") {
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
            let output = try await client().webhooks_createInstance(.init(body: .json(request)))
            return try mapWebhook(output.created.body.json.data)
        }
    }

    public func updateWebhook(id: String, webhook: DesiredWebhook, secret: String?) async throws -> AppStoreConnectWebhook {
        try await perform(operation: "update a webhook") {
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
            let output = try await client().webhooks_updateInstance(.init(
                path: .init(id: id),
                body: .json(request)
            ))
            return try mapWebhook(output.ok.body.json.data)
        }
    }

    public func deleteWebhook(id: String) async throws {
        try await perform(operation: "deleteWebhook") {
            let output = try await client().webhooks_deleteInstance(.init(path: .init(id: id)))
            _ = try output.noContent
        }
    }

    private func allPages<Value>(
        _ load: (Client) async throws -> ([Value], String?)
    ) async throws -> [Value] {
        var values: [Value] = []
        var nextPageURL: String?
        var visitedLinks: Set<String> = []

        for _ in 0..<100 {
            try Task.checkCancellation()
            let (page, next) = try await load(client(nextPageURL: nextPageURL))
            values.append(contentsOf: page)
            guard let next else {
                return values
            }
            guard visitedLinks.insert(next).inserted else {
                throw ApogeeError.unexpectedAPIResponse("A collection repeated its next-page link.")
            }
            nextPageURL = next
        }

        throw ApogeeError.unexpectedAPIResponse("A collection exceeded the 100-page safety limit.")
    }

    private func perform<Value>(operation: String, _ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch let error as ApogeeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ClientError {
            if let underlying = error.underlyingError as? ApogeeError {
                throw underlying
            }
            if error.underlyingError is CancellationError || (error.underlyingError as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if error.underlyingError is AppStoreConnectTransportError || error.underlyingError is URLError {
                throw ApogeeError.appStoreConnectTransportFailed(operation: operation)
            }
            if let response = error.response {
                if error.underlyingError is AppStoreConnectDateDecodingError {
                    throw ApogeeError.appStoreConnectDateDecodingFailed(operation: operation, statusCode: response.status.code)
                }
                if error.underlyingError is DecodingError {
                    throw ApogeeError.appStoreConnectResponseDecodingFailed(operation: operation, statusCode: response.status.code)
                }
            }
            throw ApogeeError.appStoreConnectRequestFailed(operation: operation)
        } catch {
            throw ApogeeError.appStoreConnectRequestFailed(operation: operation)
        }
    }

    private func mapApp(_ app: Components.Schemas.App) -> AppStoreConnectApp {
        .init(id: app.id, bundleID: app.attributes?.bundleId, name: app.attributes?.name)
    }

    private func mapVersion(_ version: Components.Schemas.AppStoreVersion) -> AppStoreConnectVersion {
        .init(
            id: version.id,
            versionString: version.attributes?.versionString,
            state: version.attributes?.appVersionState?.rawValue,
            platform: version.attributes?.platform.flatMap(Platform.init(generated:)),
            releaseType: version.attributes?.releaseType?.rawValue,
            earliestReleaseDate: version.attributes?.earliestReleaseDate
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
        let items = submission.relationships?.items
        let itemIDs: [String]?
        if let data = items?.data,
           items?.meta?.paging.nextCursor == nil,
           items?.meta?.paging.total.map({ $0 == data.count }) ?? (data.count < 50) {
            itemIDs = data.map(\.id)
        } else {
            itemIDs = nil
        }
        return .init(
            id: submission.id,
            state: submission.attributes?.state?.rawValue,
            platform: submission.attributes?.platform.flatMap(Platform.init(generated:)),
            appStoreVersionID: submission.relationships?.appStoreVersionForReview?.data?.id,
            itemIDs: itemIDs
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
}

private struct AppStoreConnectTransportError: Error {}

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
        let response: (HTTPResponse, HTTPBody?)
        do {
            response = try await next(request, body, baseURL)
        } catch let error as ClientError {
            if let underlying = error.underlyingError as? ApogeeError {
                throw underlying
            }
            if error.underlyingError is CancellationError || (error.underlyingError as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            // Classify at the transport boundary without retaining request data.
            throw AppStoreConnectTransportError()
        }
        guard (200..<300).contains(response.0.status.code) else {
            throw ApogeeError.appStoreConnectHTTPError(operation: operationID, statusCode: response.0.status.code)
        }
        return response
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
