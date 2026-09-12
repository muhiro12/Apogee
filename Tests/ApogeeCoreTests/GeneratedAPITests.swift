import ApogeeCore
import Crypto
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@Test(arguments: ["apps", "versions", "localizations", "builds", "submissions", "webhooks"])
func generatedCollectionsFollowNextPage(kind: String) async throws {
    let transport = StubTransport { request, _, index in
        let resourceType = [
            "apps": "apps", "versions": "appStoreVersions",
            "localizations": "appStoreVersionLocalizations", "builds": "builds",
            "submissions": "reviewSubmissions", "webhooks": "webhooks",
        ][kind]!
        let next = "https://api.appstoreconnect.apple.com" + (request.path ?? "") + "&cursor=second"
        return try jsonResponse([
            "data": [["type": resourceType, "id": "resource-\(index)"]],
            "links": index == 0 ? ["self": "unused", "next": next] : ["self": "unused"],
        ])
    }
    let api = testAPI(transport: transport)
    let ids: [String]
    switch kind {
    case "apps":
        ids = try await api.apps(bundleID: "com.example.app").map(\.id)
    case "versions":
        ids = try await api.appStoreVersions(appID: "app-1", version: "1.2.3", platform: .iOS).map(\.id)
    case "localizations":
        ids = try await api.appStoreVersionLocalizations(versionID: "version-1").map(\.id)
    case "builds":
        ids = try await api.builds(appID: "app-1", buildVersion: "123", appStoreVersion: "1.2.3", platform: .iOS).map(\.id)
    case "submissions":
        ids = try await api.reviewSubmissions(appID: "app-1", platform: .iOS).map(\.id)
    default:
        ids = try await api.webhooks(appID: "app-1").map(\.id)
    }
    #expect(ids == ["resource-0", "resource-1"])
    #expect(await transport.requests.count == 2)
    #expect(await transport.requests.last?.path?.contains("cursor=second") == true)
}

@Test(arguments: [
    "https://untrusted.example/v1/apps?filter%5BbundleId%5D=com.example.app",
    "http://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.example.app",
    "https://api.appstoreconnect.apple.com/v1/webhooks",
    "https://api.appstoreconnect.apple.com/v1/apps?cursor=unfiltered",
])
func paginationRejectsUnsafeLinksBeforeSending(next: String) async throws {
    let transport = StubTransport { _, _, _ in
        try jsonResponse(["data": [], "links": ["self": "unused", "next": next]])
    }
    await #expect(throws: ApogeeError.self) {
        _ = try await testAPI(transport: transport).apps(bundleID: "com.example.app")
    }
    #expect(await transport.requests.count == 1)
}

@Test
func paginationRejectsRepeatingLinks() async throws {
    let transport = StubTransport { _, _, _ in
        try jsonResponse([
            "data": [],
            "links": ["self": "unused", "next": "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.example.app&cursor=repeated"],
        ])
    }
    await #expect(throws: ApogeeError.self) {
        _ = try await testAPI(transport: transport).apps(bundleID: "com.example.app")
    }
    #expect(await transport.requests.count == 2)
}

@Test
func unattachedBuildDecodesNullRelationship() async throws {
    let transport = StubTransport { request, _, _ in
        #expect(request.path?.contains("include=build") == true)
        return try jsonResponse([
            "data": ["id": "version-1", "type": "appStoreVersions", "relationships": ["build": ["data": NSNull()]]],
            "links": ["self": "unused"],
        ])
    }
    #expect(try await testAPI(transport: transport).build(versionID: "version-1") == nil)
    #expect(await transport.requests.count == 1)
}

@Test
func reviewSubmissionsDecodeMixedDatePrecisionAcrossPages() async throws {
    let transport = StubTransport { request, _, index in
        let submittedDate = index == 0 ? "2026-01-02T03:04:05.123Z" : "2026-01-02T12:04:05+09:00"
        let createdDate = index == 0 ? "2026-01-01T20:04:05-07:00" : "2026-01-02T03:04:05.123456Z"
        let next = "https://api.appstoreconnect.apple.com" + (request.path ?? "") + "&cursor=second"
        return try jsonResponse([
            "data": [[
                "id": "review-\(index)", "type": "reviewSubmissions",
                "attributes": ["platform": "IOS", "state": "COMPLETE", "submittedDate": submittedDate],
                "relationships": [
                    "appStoreVersionForReview": ["data": ["id": "version-\(index)", "type": "appStoreVersions"]],
                    "items": ["data": []],
                ],
            ]],
            "included": [[
                "id": "version-\(index)", "type": "appStoreVersions",
                "attributes": ["createdDate": createdDate],
            ]],
            "links": index == 0 ? ["self": "unused", "next": next] : ["self": "unused"],
        ])
    }
    let submissions = try await testAPI(transport: transport).reviewSubmissions(appID: "app-1", platform: .iOS)
    #expect(submissions == [
        .init(id: "review-0", state: "COMPLETE", platform: .iOS, appStoreVersionID: "version-0", itemIDs: []),
        .init(id: "review-1", state: "COMPLETE", platform: .iOS, appStoreVersionID: "version-1", itemIDs: []),
    ])
    #expect(await transport.requests.count == 2)
}

@Test(arguments: ["not-a-date-response-sentinel", "", "2026-01-02"])
func reviewSubmissionsRejectInvalidDatesWithoutExposingResponses(date: String) async throws {
    let transport = StubTransport { _, _, _ in
        try jsonResponse([
            "data": [[
                "id": "review-1", "type": "reviewSubmissions",
                "attributes": ["submittedDate": date],
            ]],
            "links": ["self": "unused"],
        ])
    }
    await #expect(throws: ApogeeError.appStoreConnectRequestFailed(operation: "reviewSubmissions")) {
        _ = try await testAPI(transport: transport).reviewSubmissions(appID: "app-1", platform: .iOS)
    }
    #expect(await transport.requests.count == 1)
}

@Test(arguments: [
    ("2027-01-15T08:00:00Z", 0.0),
    ("2027-01-15T08:00:00.1Z", 0.1),
    ("2027-01-15T08:00:00.12Z", 0.12),
    ("2027-01-15T08:00:00.123Z", 0.123),
    ("2027-01-15T08:00:00.123456Z", 0.123456),
    ("2027-01-15T17:00:00+09:00", 0.0),
    ("2027-01-15T01:00:00-07:00", 0.0),
    ("2027-01-15T17:00:00.123+09:00", 0.123),
    ("2027-01-15T01:00:00.123-07:00", 0.123),
])
func versionMappingIncludesReleaseTiming(date: String, fractionalSeconds: Double) async throws {
    let transport = StubTransport { _, _, _ in
        try jsonResponse([
            "data": [[
                "id": "version-1", "type": "appStoreVersions",
                "attributes": [
                    "versionString": "1.2.3", "platform": "IOS",
                    "appVersionState": "PENDING_DEVELOPER_RELEASE",
                    "releaseType": "SCHEDULED", "earliestReleaseDate": date,
                ],
            ]],
            "links": ["self": "unused"],
        ])
    }
    let versions = try await testAPI(transport: transport).appStoreVersions(appID: "app-1", version: "1.2.3", platform: .iOS)
    #expect(versions.first?.releaseType == "SCHEDULED")
    let releaseDate = try #require(versions.first?.earliestReleaseDate)
    // Foundation's ISO8601DateFormatter supports millisecond precision.
    #expect(abs(releaseDate.timeIntervalSince1970 - (1_800_000_000 + fractionalSeconds)) < 0.001)
}

@Test
func attachedBuildReadsLinkedResource() async throws {
    let transport = StubTransport { request, _, index in
        if index == 0 {
            return try jsonResponse([
                "data": ["id": "version-1", "type": "appStoreVersions", "relationships": ["build": ["data": ["id": "build-1", "type": "builds"]]]],
                "links": ["self": "unused"],
            ])
        }
        #expect(request.path?.hasPrefix("/v1/builds/build-1") == true)
        return try jsonResponse([
            "data": ["id": "build-1", "type": "builds", "attributes": ["version": "123", "processingState": "VALID"]],
            "links": ["self": "unused"],
        ])
    }
    #expect(try await testAPI(transport: transport).build(versionID: "version-1")?.processingState == "VALID")
}

@Test(arguments: [401, 403, 404, 409, 429, 500])
func apiErrorsKeepStatusWithoutResponseSecrets(status: Int) async throws {
    let transport = StubTransport { _, _, _ in
        try jsonResponse(["errors": [["detail": "response-secret-sentinel"]]], status: status)
    }
    do {
        _ = try await testAPI(transport: transport).app(id: "app-1")
        Issue.record("Expected an HTTP error.")
    } catch {
        #expect(error as? ApogeeError == .appStoreConnectHTTPError(operation: "apps_getInstance", statusCode: status))
        #expect(!String(reflecting: error).contains("response-secret-sentinel"))
        #expect(!String(reflecting: error).contains("Bearer"))
    }
}

@Test
func metadataTransportErrorsDoNotExposeReleaseTextOrAuthorization() async throws {
    let transport = StubTransport { request, body, _ in
        #expect(request.headerFields[.authorization]?.hasPrefix("Bearer ") == true)
        #expect(body?.contains("unpublished-release-sentinel") == true)
        throw StubFailure()
    }
    do {
        _ = try await testAPI(transport: transport).updateLocalization(
            id: "locale-1", patch: .init(releaseNotes: "unpublished-release-sentinel")
        )
        Issue.record("Expected a transport error.")
    } catch {
        #expect(error as? ApogeeError == .appStoreConnectRequestFailed(operation: "updateLocalization"))
        #expect(!String(reflecting: error).contains("unpublished-release-sentinel"))
        #expect(!String(reflecting: error).contains("Bearer"))
    }
}

@Test
func generatedAPIPreservesCancellation() async throws {
    let transport = StubTransport { _, _, _ in
        throw CancellationError()
    }
    await #expect(throws: CancellationError.self) {
        _ = try await testAPI(transport: transport).app(id: "app-1")
    }
}

@Test(arguments: [0, 1, 2])
func reviewMappingRejectsTruncatedItemLinkage(total: Int) async throws {
    let transport = StubTransport { request, _, _ in
        #expect(request.path?.contains("items") == true)
        return try jsonResponse([
            "data": [
                "id": "review-1", "type": "reviewSubmissions",
                "relationships": ["items": [
                    "data": total == 0 ? [] : [["type": "reviewSubmissionItems", "id": "item-1"]],
                    "meta": ["paging": ["total": total, "limit": 50]],
                ]],
            ],
            "links": ["self": "unused"],
        ])
    }
    let submission = try await testAPI(transport: transport).reviewSubmission(id: "review-1")
    #expect(submission.itemIDs == (total == 0 ? [] : total == 1 ? ["item-1"] : nil))
}

private struct StubFailure: Error {}

func testAPI(transport: any ClientTransport) -> GeneratedAppStoreConnectAPI {
    .init(credentials: .init(
        keyID: "TEST_KEY", issuerID: "TEST_ISSUER",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
    ), transport: transport)
}

func jsonResponse(_ object: [String: Any], status: Int = 200) throws -> (HTTPResponse, HTTPBody?) {
    let data = try JSONSerialization.data(withJSONObject: object)
    return (.init(status: .init(code: status), headerFields: [.contentType: "application/json"]), .init(data))
}

actor StubTransport: ClientTransport {
    let respond: @Sendable (HTTPRequest, String?, Int) throws -> (HTTPResponse, HTTPBody?)
    private(set) var requests: [HTTPRequest] = []

    init(respond: @escaping @Sendable (HTTPRequest, String?, Int) throws -> (HTTPResponse, HTTPBody?)) {
        self.respond = respond
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let index = requests.count
        requests.append(request)
        let text = try await body.mapBodyToString()
        return try respond(request, text, index)
    }
}

private extension Optional where Wrapped == HTTPBody {
    func mapBodyToString() async throws -> String? {
        guard let body = self else {
            return nil
        }
        return try await String(collecting: body, upTo: 1_048_576)
    }
}
