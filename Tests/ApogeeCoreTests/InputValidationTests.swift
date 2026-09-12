import ApogeeCore
import Foundation
import Testing

@Test
func metadataRejectsEmptySelectedInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("en-US"), withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    try "Description".write(to: directory.appendingPathComponent("en-US/description.txt"), atomically: true, encoding: .utf8)
    #expect(throws: ApogeeError.emptyMetadata) {
        _ = try MetadataLoader().load(from: directory.path, fields: [.releaseNotes])
    }
    #expect(try MetadataLoader().load(from: directory.path).count == 1)
}

@Test
func metadataRejectsDuplicateRemoteLocalesBeforeWriting() async throws {
    let api = FakeAppStoreConnectAPI(locales: ["en-US", "en-US", "ja"])
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/AppStore/Metadata")
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: api).updateMetadata(
            appLookup: .appID("app-1"), version: "1.2.3", metadataPath: fixture.path, options: .init(mode: .apply)
        )
    }
    #expect(await api.updatedLocalizationIDs.isEmpty)
}

@Test
func webhookSecretsAreCheckedBeforeAnyWrite() async throws {
    let api = FakeAppStoreConnectAPI()
    let before = try await api.webhooks(appID: "app-1")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let config = WebhookSyncConfiguration(webhooks: before.map { webhook in
        .init(
            name: webhook.name, url: webhook.url, eventTypes: webhook.eventTypes,
            secretEnvironmentVariable: webhook.name == "obsolete" ? "PRESENT" : "MISSING",
            rotateSecret: true
        )
    })
    let path = directory.appendingPathComponent("webhooks.json")
    try JSONEncoder().encode(config).write(to: path)
    await #expect(throws: ApogeeError.missingEnvironmentVariable("MISSING")) {
        _ = try await ReleaseAutomation(api: api, secretEnvironment: .init(values: ["PRESENT": "test-secret"])).syncWebhooks(
            appLookup: .appID("app-1"), configPath: path.path, options: .init(mode: .apply)
        )
    }
    #expect(await api.updatedWebhookIDs.isEmpty)
}

@Test
func webhookLoaderRejectsUnknownEventsDuringPlanning() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let config = WebhookSyncConfiguration(webhooks: [
        .init(name: "release", url: "https://example.com/hook", eventTypes: ["INVALID_EVENT"], secretEnvironmentVariable: "SECRET"),
    ])
    let path = directory.appendingPathComponent("webhooks.json")
    try JSONEncoder().encode(config).write(to: path)
    #expect(throws: ApogeeError.invalidWebhookEventType("INVALID_EVENT")) {
        _ = try WebhookConfigurationLoader().load(from: path.path)
    }
}
