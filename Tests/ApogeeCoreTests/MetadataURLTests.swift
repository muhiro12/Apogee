import ApogeeCore
@testable import apogee
import Foundation
import Testing

@Test(arguments: ["", "example.com/help", "javascript:alert(1)", "https://user:secret@example.com", "https://example.com/a b", "https://example.com/a\nb", "https://example.com/%GG", "https://example.com/%0d", "https:///help", "https://example.com:99999", "https://example.com\\bad"])
func invalidMetadataURLsFailBeforeRemoteAccess(value: String) async throws {
    let directory = try metadataURLDirectory(support: value, marketing: nil)
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = StubTransport { _, _, _ in
        Issue.record("Invalid local URLs must fail before remote access.")
        throw CancellationError()
    }
    await #expect(throws: MetadataValidationError.invalidURL(field: .supportURL)) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).updateMetadata(
            appLookup: .appID("app"), version: "1.2.3", metadataPath: directory.path, options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.isEmpty)
}

@Test(arguments: ["https://example.com/help", "http://example.com/help?q=a%20b", "https://例え.jp/ヘルプ?言語=日本語", "https://example.com:8443/help#contact"])
func metadataURLLoaderPreservesValidValuesAndSelectedFields(value: String) throws {
    let directory = try metadataURLDirectory(support: value + "\n", marketing: "")
    defer { try? FileManager.default.removeItem(at: directory) }
    let loaded = try #require(MetadataLoader().load(from: directory.path).first)
    #expect(loaded.supportURL == value)
    #expect(loaded.marketingURL == "")
    #expect(loaded.filtered(fields: [.marketingURL]).supportURL == nil)
    #expect(loaded.filtered(fields: [.marketingURL]).marketingURL == "")
    #expect(!MetadataPatch(supportURL: value).isEmpty)
    #expect(!MetadataPatch(marketingURL: "").isEmpty)
    try Data("invalid".utf8).write(to: directory.appendingPathComponent("ja/support_url.txt"))
    #expect(try MetadataLoader().load(from: directory.path, fields: [.marketingURL]).first?.supportURL == nil)
}

@Test
func metadataURLCommandPlansAppliesAndVerifiesOnlyPresentFiles() async throws {
    let value = "https://example.com/ヘルプ?言語=日本語"
    let directory = try metadataURLDirectory(support: value, marketing: "")
    defer { try? FileManager.default.removeItem(at: directory) }
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)
    let arguments = ["--app-id", "app-1", "--version", "1.2.3", "--metadata-path", directory.path, "--output", "json"]
    let command = try UpdateMetadata.parse(arguments)
    let text = try await command.renderedOutput(automation: automation, configuration: .init())
    let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 1)
    let plan = try #require(object["plan"] as? [String: Any])
    let actions = try #require(plan["actions"] as? [[String: Any]])
    #expect(Set(actions.compactMap { $0["field"] as? String }) == ["support_url", "marketing_url"])
    #expect(actions.first { $0["field"] as? String == "support_url" }?["desiredValue"] as? String == value)
    #expect(await api.updatedLocalizationIDs.isEmpty)
    let apply = try UpdateMetadata.parse(arguments + ["--apply"])
    _ = try await apply.renderedOutput(automation: automation, configuration: .init())
    let remote = try await automation.readMetadata(appLookup: .appID("app-1"), version: "1.2.3")
    let japanese = try #require(remote.localizations.first { $0.locale == "ja" })
    #expect(japanese.metadata.supportURL == value)
    #expect(japanese.metadata.marketingURL == "")
    #expect(japanese.metadata.description == "Old ja description")
    let fresh = try await automation.updateMetadata(appLookup: .appID("app-1"), version: "1.2.3", metadataPath: directory.path, options: .init(mode: .dryRun))
    #expect(!fresh.hasChanges)
    try FileManager.default.removeItem(at: directory.appendingPathComponent("ja/support_url.txt"))
    let missing = try MetadataLoader().load(from: directory.path)
    #expect(missing.first?.supportURL == nil)
}

@Test
func metadataURLAdapterEncodesOnlyRequestedValuesAndRejectsUnsafePatches() async throws {
    let transport = StubTransport { _, body, _ in
        let body = try #require(body)
        let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let data = try #require(object["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(Set(attributes.keys) == ["supportUrl", "marketingUrl"])
        #expect(attributes["supportUrl"] as? String == "https://example.com/ヘルプ")
        #expect(attributes["marketingUrl"] as? String == "")
        return try jsonResponse(["data": ["type": "appStoreVersionLocalizations", "id": "locale", "attributes": attributes], "links": ["self": "unused"]])
    }
    let api = testAPI(transport: transport)
    let result = try await api.updateLocalization(id: "locale", patch: .init(supportURL: "https://example.com/ヘルプ", marketingURL: ""))
    #expect(result.metadata.supportURL == "https://example.com/ヘルプ")
    #expect(result.metadata.marketingURL == "")
    await #expect(throws: MetadataValidationError.invalidURL(field: .marketingURL)) {
        _ = try await api.updateLocalization(id: "locale", patch: .init(marketingURL: "file:///private/input"))
    }
    #expect(await transport.requests.count == 1)
}

@Test(arguments: ["partial", "support-mismatch", "marketing-mismatch"])
func metadataURLFailuresNeverProduceSuccessJSON(scenario: String) async throws {
    let directory = try metadataURLDirectory(support: "https://example.com/new", marketing: "https://example.com/marketing")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.copyItem(at: directory.appendingPathComponent("ja"), to: directory.appendingPathComponent("en-US"))
    let transport = StubTransport { request, _, index in
        let path = request.path ?? ""
        if request.method == .patch {
            if scenario == "partial", index == 4 {
                return try jsonResponse(["errors": [["status": "403", "code": "FORBIDDEN", "title": "Private response"]]], status: 403)
            }
            return try jsonResponse(["data": ["type": "appStoreVersionLocalizations", "id": "locale", "attributes": ["locale": "ja"]], "links": ["self": "unused"]])
        }
        if path.contains("appStoreVersionLocalizations") {
            let afterWrites = index > 4
            let support = afterWrites && scenario != "support-mismatch" ? "https://example.com/new" : "https://example.com/old"
            let marketing = afterWrites && scenario != "marketing-mismatch" ? "https://example.com/marketing" : "https://example.com/old"
            return try jsonResponse(["data": ["en-US", "ja"].map { locale in
                ["type": "appStoreVersionLocalizations", "id": locale, "attributes": ["locale": locale, "supportUrl": support, "marketingUrl": marketing]] as [String: Any]
            }, "links": ["self": "unused"]])
        }
        if path.contains("appStoreVersions") {
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version", "attributes": ["versionString": "1.2.3", "platform": "IOS"]]], "links": ["self": "unused"]])
        }
        return try jsonResponse(["data": ["type": "apps", "id": "app"], "links": ["self": "unused"]])
    }
    let command = try UpdateMetadata.parse(["--app-id", "app", "--version", "1.2.3", "--metadata-path", directory.path, "--apply", "--output", "json"])
    await #expect(throws: ApogeeError.self) {
        _ = try await command.renderedOutput(automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init())
    }
    #expect(await transport.requests.filter { $0.method == .patch }.count == 2)
}

private func metadataURLDirectory(support: String?, marketing: String?) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let locale = directory.appendingPathComponent("ja")
    try FileManager.default.createDirectory(at: locale, withIntermediateDirectories: true)
    for (name, value) in [("support_url", support), ("marketing_url", marketing)] {
        if let value {
            try Data(value.utf8).write(to: locale.appendingPathComponent(name + ".txt"))
        }
    }
    return directory
}
