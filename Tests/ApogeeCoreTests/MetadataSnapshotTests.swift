import ApogeeCore
@testable import apogee
import Foundation
import Testing

@Test
func metadataSnapshotReadsEveryPageAndPreservesValues() async throws {
    let transport = metadataSnapshotTransport()
    let snapshot = try await ReleaseAutomation(api: testAPI(transport: transport)).readMetadata(
        appLookup: .bundleID("com.example.app"), version: "2.0", platform: .macOS
    )
    #expect(snapshot.app.id == "app-1")
    #expect(snapshot.version.id == "version-2")
    #expect(snapshot.version.platform == .macOS)
    #expect(snapshot.localizations.map(\.locale) == ["en-US", "ja"])
    #expect(snapshot.localizations.map(\.id) == ["locale-en-US", "locale-ja"])
    let metadata = try #require(snapshot.localizations.last?.metadata)
    #expect(metadata.releaseNotes == "\n更新内容\nSecond line\n")
    #expect(metadata.description == nil)
    #expect(metadata.keywords == "")
    #expect(metadata.promotionalText == "紹介文 ✨")
    #expect(metadata.supportURL == nil)
    #expect(metadata.marketingURL == "")
    #expect(await transport.requests.count == 4)
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}

@Test
func readMetadataCommandSavesLosslessJSONAndRefusesExistingFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let destination = directory.appendingPathComponent("snapshot.json")
    let command = try ReadMetadata.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--save-to", destination.path,
    ])
    let automation = ReleaseAutomation(api: testAPI(transport: metadataSnapshotTransport()))
    let data = try await command.snapshotData(automation: automation, configuration: .init(metadataPath: "missing-inputs"))
    #expect(try Data(contentsOf: destination) == data)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 1)
    #expect(object["kind"] as? String == "metadata-snapshot")
    let app = try #require(object["app"] as? [String: Any])
    #expect(app["id"] as? String == "app-1")
    #expect(app["name"] is NSNull)
    let version = try #require(object["version"] as? [String: Any])
    #expect(version["platform"] as? String == "MAC_OS")
    let localizations = try #require(object["localizations"] as? [[String: Any]])
    let japanese = try #require(localizations.last)
    #expect(japanese["releaseNotes"] as? String == "\n更新内容\nSecond line\n")
    #expect(japanese["description"] is NSNull)
    #expect(japanese["keywords"] as? String == "")
    #expect(japanese["promotionalText"] as? String == "紹介文 ✨")
    #expect(japanese["supportURL"] is NSNull)
    #expect(japanese["marketingURL"] as? String == "")
    #expect(localizations.first?["supportURL"] as? String == "https://example.com/ヘルプ")
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("TEST_KEY"))
    #expect(!text.contains("Bearer"))
    #expect(!text.contains("PRIVATE KEY"))

    let existing = Data("Existing release input".utf8)
    try existing.write(to: destination)
    await #expect(throws: (any Error).self) {
        _ = try await command.snapshotData(automation: automation, configuration: .init())
    }
    #expect(try Data(contentsOf: destination) == existing)

    let link = directory.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    let linkedCommand = try ReadMetadata.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--save-to", link.path,
    ])
    await #expect(throws: (any Error).self) {
        _ = try await linkedCommand.snapshotData(automation: automation, configuration: .init())
    }
    #expect(try Data(contentsOf: destination) == existing)
}

@Test(arguments: [0, 2])
func metadataSnapshotRequiresOneVersion(count: Int) async throws {
    let transport = metadataSnapshotTransport(versionCount: count)
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).readMetadata(
            appLookup: .appID("app-1"), version: "2.0", platform: .macOS
        )
    }
    #expect(await transport.requests.count == 2)
}

@Test(arguments: ["duplicate", "missing"])
func metadataSnapshotRejectsAmbiguousOrMissingLocales(mode: String) async throws {
    let transport = metadataSnapshotTransport(localeMode: mode)
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).readMetadata(
            appLookup: .appID("app-1"), version: "2.0", platform: .macOS
        )
    }
}

@Test(arguments: [false, true])
func metadataSnapshotFailureDoesNotCreateAFile(cancelled: Bool) async throws {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: destination)
    }
    let command = try ReadMetadata.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--save-to", destination.path,
    ])
    let transport = cancelled ? StubTransport { _, _, _ in
        throw CancellationError()
    } : metadataSnapshotTransport(localeMode: "failure")
    do {
        _ = try await command.snapshotData(
            automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
        )
        Issue.record("Expected a failed read to reject the snapshot.")
    } catch {
        if cancelled {
            #expect(error is CancellationError)
        } else {
            #expect(error as? ApogeeError == .appStoreConnectHTTPError(
                operation: "appStoreVersions_appStoreVersionLocalizations_getToManyRelated", statusCode: 403
            ))
            #expect(!String(reflecting: error).contains("response-secret-sentinel"))
        }
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test
func metadataSnapshotCanContainNoLocalizations() async throws {
    let transport = metadataSnapshotTransport(localeMode: "empty")
    let snapshot = try await ReleaseAutomation(api: testAPI(transport: transport)).readMetadata(
        appLookup: .appID("app-1"), version: "2.0", platform: .macOS
    )
    #expect(snapshot.localizations.isEmpty)
}

private func metadataSnapshotTransport(versionCount: Int = 1, localeMode: String = "normal") -> StubTransport {
    StubTransport { request, _, _ in
        #expect(request.method == .get)
        let path = request.path ?? ""
        if path.contains("appStoreVersionLocalizations") {
            let secondPage = path.contains("cursor=second")
            if secondPage && localeMode == "failure" {
                return try jsonResponse([
                    "errors": [["status": "403", "code": "FORBIDDEN", "title": "response-secret-sentinel"]],
                ], status: 403)
            }
            let locale = localeMode == "missing" ? "" : (secondPage && localeMode != "duplicate" ? "en-US" : "ja")
            let next = "https://api.appstoreconnect.apple.com" + path + "&cursor=second"
            return try jsonResponse([
                "data": localeMode == "empty" ? [] : [[
                    "type": "appStoreVersionLocalizations", "id": "locale-\(locale)",
                    "attributes": [
                        "locale": locale, "whatsNew": "\n更新内容\nSecond line\n",
                        "description": NSNull(), "keywords": "", "promotionalText": "紹介文 ✨",
                        "supportUrl": locale == "ja" ? NSNull() : "https://example.com/ヘルプ", "marketingUrl": "",
                    ],
                ]],
                "links": secondPage || localeMode == "empty" ? ["self": "unused"] : ["self": "unused", "next": next],
            ])
        }
        if path.contains("appStoreVersions") {
            #expect(path.contains("MAC_OS"))
            #expect(path.contains("2.0"))
            return try jsonResponse([
                "data": (0..<versionCount).map { index in
                    ["type": "appStoreVersions", "id": "version-\(index + 2)",
                     "attributes": ["versionString": "2.0", "platform": "MAC_OS"]] as [String: Any]
                },
                "links": ["self": "unused"],
            ])
        }
        let app: [String: Any] = [
            "type": "apps", "id": "app-1", "attributes": ["bundleId": "com.example.app"],
        ]
        if path.contains("/apps?") {
            #expect(path.contains("com.example.app"))
            return try jsonResponse(["data": [app], "links": ["self": "unused"]])
        }
        #expect(path == "/v1/apps/app-1")
        return try jsonResponse(["data": app, "links": ["self": "unused"]])
    }
}
