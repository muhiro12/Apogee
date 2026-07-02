import Crypto
import Foundation
import ApogeeCore
import Testing

@Test
func metadataLoaderReadsFixtureLayout() throws {
    let metadata = try MetadataLoader().load(from: fixturePath("AppStore/Metadata"))

    #expect(metadata.map(\.locale) == ["en-US", "ja"])
    #expect(metadata.first { $0.locale == "ja" }?.releaseNotes == "Japanese release notes")
    #expect(metadata.first { $0.locale == "en-US" }?.description == "English description")
}

@Test
func screenshotLoaderReadsFixtureLayout() throws {
    let screenshots = try ScreenshotLoader().load(from: fixturePath("AppStore/Screenshots"))

    #expect(screenshots.map { "\($0.locale)/\($0.displayType)" } == ["en-US/APP_IPHONE_67", "ja/APP_IPHONE_67"])
    #expect(screenshots.first { $0.locale == "ja" }?.files.map(\.fileName) == ["01.png", "02.png"])
}

@Test
func apogeeConfigurationReadsFixtureDefaults() throws {
    let configuration = try ApogeeConfiguration.load(from: fixturePath("apogee.json"))

    #expect(configuration.bundleID == "com.example.app")
    #expect(configuration.appID == nil)
    #expect(configuration.defaultPlatform == nil)
    #expect(configuration.resolvedMetadataPath == "AppStore/Metadata")
    #expect(configuration.resolvedScreenshotsPath == "AppStore/Screenshots")
    #expect(configuration.resolvedWebhooksPath == "AppStore/webhooks.json")
    #expect(configuration.credentials.keyIDEnvironment == "ASC_KEY_ID")
    #expect(configuration.credentials.privateKeyBase64Environment == "ASC_PRIVATE_KEY_BASE64")
}

@Test
func apogeeConfigurationAllowsPartialOverrides() throws {
    let data = Data("""
    {
      "bundleID": "com.example.other",
      "metadataPath": "Release/Metadata",
      "credentials": {
        "privateKeyBase64Environment": "CI_ASC_PRIVATE_KEY_BASE64"
      }
    }
    """.utf8)
    let configuration = try JSONDecoder().decode(ApogeeConfiguration.self, from: data)

    #expect(configuration.bundleID == "com.example.other")
    #expect(configuration.resolvedMetadataPath == "Release/Metadata")
    #expect(configuration.resolvedScreenshotsPath == "AppStore/Screenshots")
    #expect(configuration.resolvedWebhooksPath == "AppStore/webhooks.json")
    #expect(configuration.credentials.keyIDEnvironment == "ASC_KEY_ID")
    #expect(configuration.credentials.privateKeyBase64Environment == "CI_ASC_PRIVATE_KEY_BASE64")
}

@Test
func jwtSignerCreatesES256AppStoreConnectToken() throws {
    let privateKey = P256.Signing.PrivateKey()
    let keyURL = temporaryDirectory().appendingPathComponent("AuthKey_TEST.p8")
    try privateKey.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
    let credentials = AppStoreConnectCredentials(
        keyID: "KEY123",
        issuerID: "ISSUER456",
        privateKeyPath: keyURL.path
    )

    let token = try JSONWebTokenSigner(credentials: credentials).signedToken(now: Date(timeIntervalSince1970: 1_700_000_000))
    let parts = token.value.split(separator: ".").map(String.init)

    #expect(parts.count == 3)

    let header = try decodedJSONObject(parts[0])
    let payload = try decodedJSONObject(parts[1])

    #expect(header["alg"] as? String == "ES256")
    #expect(header["kid"] as? String == "KEY123")
    #expect(header["typ"] as? String == "JWT")
    #expect(payload["iss"] as? String == "ISSUER456")
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["iat"] as? Int == 1_700_000_000)
    #expect(payload["exp"] as? Int == 1_700_001_140)

    let signingInput = "\(parts[0]).\(parts[1])"
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: base64URLDecoded(parts[2]))
    #expect(privateKey.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
}

@Test
func credentialsLoadPrivateKeyBase64FromConfiguredEnvironment() throws {
    let privateKey = P256.Signing.PrivateKey()
    let privateKeyBase64 = Data(privateKey.pemRepresentation.utf8).base64EncodedString()
    let credentialEnvironment = AppStoreConnectCredentialEnvironment(
        keyIDEnvironment: "TEST_ASC_KEY_ID",
        issuerIDEnvironment: "TEST_ASC_ISSUER_ID",
        privateKeyPathEnvironment: "TEST_ASC_PRIVATE_KEY_PATH",
        privateKeyBase64Environment: "TEST_ASC_PRIVATE_KEY_BASE64"
    )
    let credentials = try AppStoreConnectCredentials.load(
        environment: [
            "TEST_ASC_KEY_ID": "KEY123",
            "TEST_ASC_ISSUER_ID": "ISSUER456",
            "TEST_ASC_PRIVATE_KEY_BASE64": privateKeyBase64,
        ],
        credentialEnvironment: credentialEnvironment
    )

    let token = try JSONWebTokenSigner(credentials: credentials).signedToken(now: Date(timeIntervalSince1970: 1_700_000_000))
    let parts = token.value.split(separator: ".").map(String.init)
    let signingInput = "\(parts[0]).\(parts[1])"
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: base64URLDecoded(parts[2]))

    #expect(credentials.privateKeyPath == nil)
    #expect(privateKey.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
}

@Test
func updateReleaseNotesDryRunPlansFixtureDiffWithoutWriting() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)
    let plan = try await automation.updateReleaseNotes(
        appLookup: .bundleID("com.example.app"),
        version: "1.2.3",
        metadataPath: fixturePath("AppStore/Metadata"),
        options: .init(mode: .dryRun)
    )

    #expect(plan.actions.contains { $0.kind == .update && $0.locale == "ja" && $0.field == "What's New" })
    #expect(plan.actions.contains { $0.kind == .unchanged && $0.locale == "en-US" })
    #expect(await api.updatedLocalizationIDs.isEmpty)
}

@Test
func updateMetadataApplyWritesAndReadBackVerifies() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)
    let plan = try await automation.updateMetadata(
        appLookup: .appID("app-1"),
        version: "1.2.3",
        metadataPath: fixturePath("AppStore/Metadata"),
        options: .init(mode: .apply)
    )

    #expect(plan.actions.contains { $0.kind == .verify })
    #expect(await api.updatedLocalizationIDs == ["loc-en", "loc-ja"])
    let localizations = try await api.appStoreVersionLocalizations(versionID: "version-1")
    #expect(localizations.first { $0.locale == "ja" }?.metadata.description == "Japanese description")
    #expect(localizations.first { $0.locale == "en-US" }?.metadata.promotionalText == "English promotional text")
}

@Test
func updateMetadataRejectsMissingLocale() async throws {
    let api = FakeAppStoreConnectAPI(locales: ["en-US"])
    let automation = ReleaseAutomation(api: api)

    do {
        _ = try await automation.updateMetadata(
            appLookup: .appID("app-1"),
            version: "1.2.3",
            metadataPath: fixturePath("AppStore/Metadata"),
            options: .init(mode: .dryRun)
        )
        Issue.record("Expected missing locale error.")
    } catch let error as ApogeeError {
        #expect(error == .localizationMissing(locale: "ja"))
    }
}

@Test
func attachBuildPassesAppStoreVersionToBuildLookup() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)

    _ = try await automation.attachBuild(
        appLookup: .appID("app-1"),
        version: "1.2.3",
        buildVersion: "123",
        options: .init(mode: .dryRun)
    )

    #expect(await api.buildLookupRequests == [
        .init(appID: "app-1", buildVersion: "123", appStoreVersion: "1.2.3", platform: .iOS),
    ])
}

@Test
func submitForReviewRejectsUnexpectedReadBackState() async throws {
    let api = FakeAppStoreConnectAPI(submittedReviewState: "UNRESOLVED_ISSUES")
    let automation = ReleaseAutomation(api: api)

    do {
        _ = try await automation.submitForReview(
            appLookup: .appID("app-1"),
            version: "1.2.3",
            options: .init(mode: .apply)
        )
        Issue.record("Expected review submission state error.")
    } catch let error as ApogeeError {
        #expect(error == .reviewSubmissionStateUnexpected(
            id: "review-1",
            state: "UNRESOLVED_ISSUES",
            expected: ["WAITING_FOR_REVIEW", "IN_REVIEW", "COMPLETE"]
        ))
    }
}

@Test
func submitForReviewReusesExistingReadySubmission() async throws {
    let api = FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "review-existing", state: "READY_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1"),
    ])
    let automation = ReleaseAutomation(api: api)

    let plan = try await automation.submitForReview(
        appLookup: .appID("app-1"),
        version: "1.2.3",
        options: .init(mode: .apply)
    )

    #expect(await api.createdReviewSubmissionIDs.isEmpty)
    #expect(plan.actions.contains { $0.kind == .verify && $0.resource == "reviewSubmission/review-existing" })
    let submissions = try await api.reviewSubmissions(appID: "app-1", platform: .iOS)
    #expect(submissions.first?.state == "WAITING_FOR_REVIEW")
}

@Test
func webhookApplyRequiresDryRunTokenForDeletion() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(
        api: api,
        secretEnvironment: .init(values: ["WEBHOOK_SECRET": "secret-value"])
    )
    let configPath = fixturePath("AppStore/webhooks.json")
    let dryRun = try await automation.syncWebhooks(
        appLookup: .appID("app-1"),
        configPath: configPath,
        options: .init(mode: .dryRun)
    )

    #expect(dryRun.hasDestructiveActions)

    do {
        _ = try await automation.syncWebhooks(
            appLookup: .appID("app-1"),
            configPath: configPath,
            options: .init(mode: .apply, allowDestructive: true, planToken: "wrong-token")
        )
        Issue.record("Expected destructive plan token error.")
    } catch let error as ApogeeError {
        #expect(error == .applyRequiresPlanToken(expected: dryRun.token))
    }

    let applyPlan = try await automation.syncWebhooks(
        appLookup: .appID("app-1"),
        configPath: configPath,
        options: .init(mode: .apply, allowDestructive: true, planToken: dryRun.token)
    )
    let webhooks = try await api.webhooks(appID: "app-1")
    #expect(webhooks.map(\.name) == ["release"])
    #expect(applyPlan.actions.contains { $0.kind == .verify && $0.resource == "app/app-1/webhooks" })
}

@Test
func destructivePlanTokenIncludesActionValues() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)
    let firstConfigPath = try writeWebhookConfig(url: "https://example.com/one")
    let secondConfigPath = try writeWebhookConfig(url: "https://example.com/two")

    let firstPlan = try await automation.syncWebhooks(
        appLookup: .appID("app-1"),
        configPath: firstConfigPath,
        options: .init(mode: .dryRun)
    )
    let secondPlan = try await automation.syncWebhooks(
        appLookup: .appID("app-1"),
        configPath: secondConfigPath,
        options: .init(mode: .dryRun)
    )

    #expect(firstPlan.hasDestructiveActions)
    #expect(secondPlan.hasDestructiveActions)
    #expect(firstPlan.actions.map(actionShape) == secondPlan.actions.map(actionShape))
    #expect(firstPlan.token != secondPlan.token)
}

@Test
func webhookPlanRendersSecretEnvironmentNameWithoutSecretValue() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(
        api: api,
        secretEnvironment: .init(values: ["WEBHOOK_SECRET": "secret-value"])
    )
    let configURL = temporaryDirectory().appendingPathComponent("webhooks.json")
    try """
    {
      "webhooks": [
        {
          "name": "release",
          "url": "https://example.com/release",
          "eventTypes": ["BUILD_STATE_CHANGED"],
          "secretEnvironmentVariable": "WEBHOOK_SECRET",
          "rotateSecret": true
        },
        {
          "name": "obsolete",
          "url": "https://example.com/obsolete",
          "eventTypes": ["BUILD_STATE_CHANGED"],
          "secretEnvironmentVariable": "WEBHOOK_SECRET"
        }
      ]
    }
    """.write(to: configURL, atomically: true, encoding: .utf8)

    let plan = try await automation.syncWebhooks(
        appLookup: .appID("app-1"),
        configPath: configURL.path,
        options: .init(mode: .dryRun)
    )
    let renderedPlan = PlanRenderer().render(plan)

    #expect(plan.actions.contains { $0.kind == .update && $0.resource == "webhook/webhook-1" })
    #expect(renderedPlan.contains("secretEnv=WEBHOOK_SECRET"))
    #expect(renderedPlan.contains("rotateSecret=true"))
    #expect(!renderedPlan.contains("secret-value"))
}

@Test
func webhookSyncRejectsDuplicateDesiredNames() async throws {
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(
        api: api,
        secretEnvironment: .init(values: ["WEBHOOK_SECRET": "secret-value"])
    )
    let configURL = temporaryDirectory().appendingPathComponent("webhooks.json")
    try """
    {
      "webhooks": [
        {
          "name": "release",
          "url": "https://example.com/one",
          "eventTypes": ["BUILD_STATE_CHANGED"],
          "secretEnvironmentVariable": "WEBHOOK_SECRET"
        },
        {
          "name": "release",
          "url": "https://example.com/two",
          "eventTypes": ["BUILD_STATE_CHANGED"],
          "secretEnvironmentVariable": "WEBHOOK_SECRET"
        }
      ]
    }
    """.write(to: configURL, atomically: true, encoding: .utf8)

    do {
        _ = try await automation.syncWebhooks(
            appLookup: .appID("app-1"),
            configPath: configURL.path,
            options: .init(mode: .dryRun)
        )
        Issue.record("Expected duplicate webhook name error.")
    } catch let error as ApogeeError {
        #expect(error == .duplicateWebhookName("release", source: "desired configuration"))
    }
}

private func fixturePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(relativePath)
        .path
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("apogee-tests")
        .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeWebhookConfig(url: String) throws -> String {
    let configURL = temporaryDirectory().appendingPathComponent("webhooks.json")
    try """
    {
      "webhooks": [
        {
          "name": "release",
          "url": "\(url)",
          "eventTypes": ["BUILD_STATE_CHANGED"],
          "secretEnvironmentVariable": "WEBHOOK_SECRET"
        }
      ]
    }
    """.write(to: configURL, atomically: true, encoding: .utf8)
    return configURL.path
}

private func actionShape(_ action: PlannedAction) -> String {
    [
        action.kind.rawValue,
        action.resource,
        action.locale ?? "",
        action.field ?? "",
        action.isDestructive.description,
    ].joined(separator: "|")
}

private func decodedJSONObject(_ text: String) throws -> [String: Any] {
    let data = try base64URLDecoded(text)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func base64URLDecoded(_ text: String) throws -> Data {
    var base64 = text
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }

    return try #require(Data(base64Encoded: base64))
}

actor FakeAppStoreConnectAPI: AppStoreConnectAPI {
    private var localizationsByVersionID: [String: [AppStoreConnectLocalization]]
    private var webhooksByAppID: [String: [AppStoreConnectWebhook]]
    private var reviewSubmissionsByAppID: [String: [AppStoreConnectReviewSubmission]]
    private let submittedReviewState: String
    private var attachedBuildByVersionID: [String: AppStoreConnectBuild?] = ["version-1": nil]
    private(set) var updatedLocalizationIDs: [String] = []
    private(set) var buildLookupRequests: [BuildLookupRequest] = []
    private(set) var createdReviewSubmissionIDs: [String] = []

    init(
        locales: [String] = ["en-US", "ja"],
        reviewSubmissions: [AppStoreConnectReviewSubmission] = [],
        submittedReviewState: String = "WAITING_FOR_REVIEW"
    ) {
        self.submittedReviewState = submittedReviewState
        localizationsByVersionID = [
            "version-1": locales.map { locale in
                .init(
                    id: locale == "en-US" ? "loc-en" : "loc-\(locale)",
                    locale: locale,
                    metadata: .init(
                        locale: locale,
                        releaseNotes: locale == "en-US" ? "English release notes" : "Old Japanese release notes",
                        description: "Old \(locale) description",
                        keywords: "old,\(locale)",
                        promotionalText: "Old \(locale) promotional text"
                    )
                )
            },
        ]
        webhooksByAppID = [
            "app-1": [
                .init(id: "webhook-1", name: "release", url: "https://example.com/release", eventTypes: ["BUILD_STATE_CHANGED"], enabled: true),
                .init(id: "webhook-2", name: "obsolete", url: "https://example.com/obsolete", eventTypes: ["BUILD_STATE_CHANGED"], enabled: true),
            ],
        ]
        reviewSubmissionsByAppID = [
            "app-1": reviewSubmissions,
        ]
    }

    func app(id: String) async throws -> AppStoreConnectApp {
        .init(id: id, bundleID: "com.example.app", name: "Example")
    }

    func apps(bundleID: String) async throws -> [AppStoreConnectApp] {
        bundleID == "com.example.app" ? [.init(id: "app-1", bundleID: bundleID, name: "Example")] : []
    }

    func appStoreVersions(appID: String, version: String, platform: Platform) async throws -> [AppStoreConnectVersion] {
        appID == "app-1" && version == "1.2.3" ? [.init(id: "version-1", versionString: version, state: "PREPARE_FOR_SUBMISSION", platform: platform)] : []
    }

    func appStoreVersionLocalizations(versionID: String) async throws -> [AppStoreConnectLocalization] {
        localizationsByVersionID[versionID] ?? []
    }

    func updateLocalization(id: String, patch: MetadataPatch) async throws -> AppStoreConnectLocalization {
        for (versionID, localizations) in localizationsByVersionID {
            guard let index = localizations.firstIndex(where: { $0.id == id }) else {
                continue
            }

            var updated = localizations[index]
            updated.metadata.releaseNotes = patch.releaseNotes ?? updated.metadata.releaseNotes
            updated.metadata.description = patch.description ?? updated.metadata.description
            updated.metadata.keywords = patch.keywords ?? updated.metadata.keywords
            updated.metadata.promotionalText = patch.promotionalText ?? updated.metadata.promotionalText
            localizationsByVersionID[versionID]?[index] = updated
            updatedLocalizationIDs.append(id)
            return updated
        }

        throw ApogeeError.unexpectedAPIResponse("Missing localization \(id).")
    }

    func builds(appID: String, buildVersion: String, appStoreVersion: String, platform: Platform) async throws -> [AppStoreConnectBuild] {
        buildLookupRequests.append(.init(
            appID: appID,
            buildVersion: buildVersion,
            appStoreVersion: appStoreVersion,
            platform: platform
        ))
        return appID == "app-1" && buildVersion == "123" && appStoreVersion == "1.2.3" ? [.init(id: "build-123", version: buildVersion, processingState: "VALID")] : []
    }

    func build(versionID: String) async throws -> AppStoreConnectBuild? {
        attachedBuildByVersionID[versionID] ?? nil
    }

    func attachBuild(versionID: String, buildID: String) async throws {
        attachedBuildByVersionID[versionID] = .init(id: buildID, version: "123", processingState: "VALID")
    }

    func reviewSubmissions(appID: String, platform: Platform) async throws -> [AppStoreConnectReviewSubmission] {
        reviewSubmissionsByAppID[appID] ?? []
    }

    func createReviewSubmission(appID: String, platform: Platform) async throws -> AppStoreConnectReviewSubmission {
        let id = "review-\((reviewSubmissionsByAppID[appID] ?? []).count + 1)"
        let submission = AppStoreConnectReviewSubmission(id: id, state: "READY_FOR_REVIEW", platform: platform)
        reviewSubmissionsByAppID[appID, default: []].append(submission)
        createdReviewSubmissionIDs.append(id)
        return submission
    }

    func createReviewSubmissionItem(submissionID: String, versionID: String) async throws -> AppStoreConnectReviewSubmissionItem {
        for appID in reviewSubmissionsByAppID.keys {
            guard let index = reviewSubmissionsByAppID[appID]?.firstIndex(where: { $0.id == submissionID }) else {
                continue
            }

            reviewSubmissionsByAppID[appID]?[index].appStoreVersionID = versionID
        }

        return .init(id: "review-item-1")
    }

    func submitReviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        for appID in reviewSubmissionsByAppID.keys {
            guard let index = reviewSubmissionsByAppID[appID]?.firstIndex(where: { $0.id == id }) else {
                continue
            }

            reviewSubmissionsByAppID[appID]?[index].state = submittedReviewState
            return reviewSubmissionsByAppID[appID]?[index] ?? .init(id: id, state: submittedReviewState, platform: .iOS)
        }

        throw ApogeeError.unexpectedAPIResponse("Missing review submission \(id).")
    }

    func reviewSubmission(id: String) async throws -> AppStoreConnectReviewSubmission {
        for submissions in reviewSubmissionsByAppID.values {
            if let submission = submissions.first(where: { $0.id == id }) {
                return submission
            }
        }

        throw ApogeeError.unexpectedAPIResponse("Missing review submission \(id).")
    }

    func webhooks(appID: String) async throws -> [AppStoreConnectWebhook] {
        webhooksByAppID[appID] ?? []
    }

    func createWebhook(appID: String, webhook: DesiredWebhook, secret: String) async throws -> AppStoreConnectWebhook {
        let created = AppStoreConnectWebhook(
            id: "webhook-\((webhooksByAppID[appID] ?? []).count + 1)",
            name: webhook.name,
            url: webhook.url,
            eventTypes: webhook.eventTypes,
            enabled: webhook.enabled
        )
        webhooksByAppID[appID, default: []].append(created)
        return created
    }

    func updateWebhook(id: String, webhook: DesiredWebhook, secret: String?) async throws -> AppStoreConnectWebhook {
        for (appID, webhooks) in webhooksByAppID {
            guard let index = webhooks.firstIndex(where: { $0.id == id }) else {
                continue
            }

            let updated = AppStoreConnectWebhook(
                id: id,
                name: webhook.name,
                url: webhook.url,
                eventTypes: webhook.eventTypes,
                enabled: webhook.enabled
            )
            webhooksByAppID[appID]?[index] = updated
            return updated
        }

        throw ApogeeError.unexpectedAPIResponse("Missing webhook \(id).")
    }

    func deleteWebhook(id: String) async throws {
        for appID in webhooksByAppID.keys {
            webhooksByAppID[appID]?.removeAll { $0.id == id }
        }
    }
}

struct BuildLookupRequest: Sendable, Hashable {
    var appID: String
    var buildVersion: String
    var appStoreVersion: String
    var platform: Platform
}
