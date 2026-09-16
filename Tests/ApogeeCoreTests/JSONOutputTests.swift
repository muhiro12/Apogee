import ApogeeCore
@testable import apogee
import Foundation
import Testing

@Test
func metadataCommandJSONDistinguishesPlanningApplyingAndFreshNoChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let locale = directory.appendingPathComponent("ja")
    try FileManager.default.createDirectory(at: locale, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let text = "更新内容 ✨\nSecond line with \"quotes\"\tand \u{001B} control"
    try Data(text.utf8).write(to: locale.appendingPathComponent("release_notes.txt"))
    let arguments = ["--bundle-id", "com.example.app", "--version", "1.2.3", "--metadata-path", directory.path]
    let api = FakeAppStoreConnectAPI()
    let automation = ReleaseAutomation(api: api)
    let command = try UpdateReleaseNotes.parse(arguments + ["--output", "json"])
    let dryRun = try jsonObject(await command.renderedOutput(automation: automation, configuration: .init()))
    #expect(dryRun["schemaVersion"] as? Int == 1)
    #expect(dryRun["command"] as? String == "update-release-notes")
    #expect(dryRun["mode"] as? String == "dry-run")
    let target = try dictionary(dryRun, "target")
    #expect(try dictionary(target, "app")["id"] as? String == "app-1")
    #expect(try dictionary(target, "version")["id"] as? String == "version-1")
    #expect(Set(try dictionary(target, "version").keys) == ["id", "versionString", "platform"])
    let plan = try dictionary(dryRun, "plan")
    #expect(plan["hasChanges"] as? Bool == true)
    #expect(plan["plannedMutationCount"] as? Int == 1)
    let actions = try #require(plan["actions"] as? [[String: Any]])
    let action = try #require(actions.first)
    #expect(action["field"] as? String == "release_notes")
    #expect(action["locale"] as? String == "ja")
    #expect(action["resource"] as? String == "appStoreVersionLocalization/loc-ja")
    #expect(action["currentValue"] as? String == "Old Japanese release notes")
    #expect(action["desiredValue"] as? String == text)
    #expect(try dictionary(dryRun, "verification")["status"] as? String == "not-performed")
    #expect(await api.updatedLocalizationIDs.isEmpty)

    let original = try await automation.updateReleaseNotes(
        appLookup: .bundleID("com.example.app"), version: "1.2.3", metadataPath: directory.path, options: .init(mode: .dryRun)
    )
    let legacy = ReleasePlan(title: original.title, actions: original.actions.map { action in
        .init(kind: action.kind, resource: action.resource, locale: action.locale, field: action.field,
              currentValue: action.currentValue, desiredValue: action.desiredValue, isDestructive: action.isDestructive)
    })
    #expect(original == legacy)
    #expect(Set([original, legacy]).count == 1)
    #expect(original.token == legacy.token)
    #expect(plan["token"] as? String == legacy.token)
    let human = try UpdateReleaseNotes.parse(arguments)
    #expect(try await human.renderedOutput(automation: automation, configuration: .init()) == PlanRenderer().render(legacy))

    let apply = try UpdateReleaseNotes.parse(arguments + ["--output", "json", "--apply"])
    let applied = try jsonObject(await apply.renderedOutput(automation: automation, configuration: .init()))
    #expect(applied["mode"] as? String == "apply")
    #expect(try dictionary(applied, "plan")["plannedMutationCount"] as? Int == 1)
    #expect(try dictionary(applied, "verification")["status"] as? String == "performed")
    let fresh = try jsonObject(await command.renderedOutput(automation: automation, configuration: .init()))
    #expect(try dictionary(fresh, "plan")["hasChanges"] as? Bool == false)
    #expect(try dictionary(fresh, "plan")["plannedMutationCount"] as? Int == 0)
}

@Test
func statusJSONPreservesUnknownAttributesSeparatelyFromTheRequestedTarget() async throws {
    let transport = StubTransport { request, _, _ in
        let path = request.path ?? ""
        if path.contains("reviewSubmissions") {
            return try jsonResponse(["data": [], "links": ["self": "unused"]])
        }
        if path.contains("/apps/app-1/appStoreVersions") {
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version-1"]], "links": ["self": "unused"]])
        }
        if path.contains("/appStoreVersions/version-1") {
            return try jsonResponse([
                "data": ["type": "appStoreVersions", "id": "version-1", "relationships": ["build": ["data": NSNull()]]],
                "links": ["self": "unused"],
            ])
        }
        return try jsonResponse(["data": ["type": "apps", "id": "app-1"], "links": ["self": "unused"]])
    }
    let command = try ReleaseStatusCommand.parse(["--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--output", "json"])
    let output = try jsonObject(await command.renderedOutput(
        automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
    ))
    #expect(output["kind"] as? String == "release-status")
    #expect(output["mode"] as? String == "read-only")
    let requested = try dictionary(output, "requestedTarget")
    #expect(requested["version"] as? String == "2.0")
    #expect(requested["platform"] as? String == "MAC_OS")
    let target = try dictionary(output, "target")
    #expect(try dictionary(target, "app")["bundleID"] is NSNull)
    let version = try dictionary(target, "version")
    for key in ["versionString", "platform", "state", "releaseType", "earliestReleaseDate"] {
        #expect(version[key] is NSNull)
    }
    #expect(try dictionary(output, "status")["build"] is NSNull)
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}

@Test
func statusJSONKeepsUnknownReviewItemsDistinctFromAnEmptyList() async throws {
    let api = FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "unknown", appStoreVersionID: "version-1"),
        .init(id: "empty", appStoreVersionID: "version-1", itemIDs: []),
    ])
    let command = try ReleaseStatusCommand.parse(["--app-id", "app-1", "--version", "1.2.3", "--output", "json"])
    let output = try jsonObject(await command.renderedOutput(automation: ReleaseAutomation(api: api), configuration: .init()))
    let status = try dictionary(output, "status")
    let submissions = try #require(status["reviewSubmissions"] as? [[String: Any]])
    #expect(submissions[0]["itemIDs"] as? [String] == [])
    #expect(submissions[1]["itemIDs"] is NSNull)
    #expect(try dictionary(status, "build")["id"] as? String == "build-123")
}

@Test
func noOpApplyDoesNotInventVerification() async throws {
    let automation = ReleaseAutomation(api: FakeAppStoreConnectAPI())
    let command = try AttachBuild.parse([
        "--app-id", "app-1", "--version", "1.2.3", "--build-version", "123", "--apply", "--output", "json",
    ])
    let output = try jsonObject(await command.renderedOutput(automation: automation, configuration: .init()))
    #expect(output["mode"] as? String == "apply")
    #expect(try dictionary(output, "plan")["plannedMutationCount"] as? Int == 0)
    #expect(try dictionary(output, "verification")["status"] as? String == "not-performed")
}

@Test
func remainingPlanCommandsExposeJSONWithoutParsingHumanText() async throws {
    let automation = ReleaseAutomation(api: FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "review-1", state: "WAITING_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1", itemIDs: ["item-1"]),
    ]))
    let arguments = ["--app-id", "app-1", "--version", "1.2.3", "--output", "json"]
    let metadata = try UpdateMetadata.parse(arguments + ["--metadata-path", jsonFixture("Metadata")])
    let metadataOutput = try jsonObject(await metadata.renderedOutput(automation: automation, configuration: .init()))
    #expect(metadataOutput["command"] as? String == "update-metadata")
    let screenshots = try UpdateScreenshots.parse(arguments + ["--screenshots-path", jsonFixture("Screenshots")])
    let screenshotOutput = try jsonObject(await screenshots.renderedOutput(automation: automation, configuration: .init()))
    #expect(try dictionary(screenshotOutput, "plan")["hasChanges"] as? Bool == false)
    #expect(try dictionary(screenshotOutput, "plan")["hasUnsupportedActions"] as? Bool == true)
    let review = try SubmitForReview.parse(arguments + ["--apply"])
    let reviewOutput = try jsonObject(await review.renderedOutput(automation: automation, configuration: .init()))
    #expect(try dictionary(reviewOutput, "plan")["hasChanges"] as? Bool == false)
    #expect(try dictionary(reviewOutput, "verification")["status"] as? String == "performed")
}

@Test
func webhookJSONTokenStillAuthorizesOnlyAMatchingDestructivePlan() async throws {
    let automation = ReleaseAutomation(api: FakeAppStoreConnectAPI(), secretEnvironment: .init(values: ["WEBHOOK_SECRET": "secret-sentinel"]))
    let arguments = ["--app-id", "app-1", "--config", jsonFixture("webhooks.json"), "--output", "json"]
    let command = try SyncWebhooks.parse(arguments)
    let text = try await command.renderedOutput(automation: automation, configuration: .init())
    #expect(!text.contains("secret-sentinel"))
    let output = try jsonObject(text)
    #expect(try dictionary(output, "target")["version"] is NSNull)
    let plan = try dictionary(output, "plan")
    #expect(plan["hasDestructiveActions"] as? Bool == true)
    let token = try #require(plan["token"] as? String)
    let rejected = try SyncWebhooks.parse(arguments + ["--apply", "--allow-destructive", "--plan-token", "stale"])
    await #expect(throws: ApogeeError.applyRequiresPlanToken) {
        _ = try await rejected.renderedOutput(automation: automation, configuration: .init())
    }
    let apply = try SyncWebhooks.parse(arguments + ["--apply", "--allow-destructive", "--plan-token", token])
    let applied = try jsonObject(await apply.renderedOutput(automation: automation, configuration: .init()))
    #expect(try dictionary(applied, "verification")["status"] as? String == "performed")
}

@Test
func aPartialMetadataWriteNeverReturnsSuccessJSON() async throws {
    let transport = StubTransport { request, _, index in
        if request.method == .patch {
            if index == 4 {
                return try jsonResponse(["errors": [["status": "403", "code": "FORBIDDEN", "title": "response-secret-sentinel"]]], status: 403)
            }
            #expect(index == 3)
            return try jsonResponse(["data": ["type": "appStoreVersionLocalizations", "id": "loc-en-US"], "links": ["self": "unused"]])
        }
        if index == 0 {
            return try jsonResponse(["data": ["type": "apps", "id": "app-1"], "links": ["self": "unused"]])
        }
        if index == 1 {
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version-1"]], "links": ["self": "unused"]])
        }
        return try jsonResponse([
            "data": ["en-US", "ja"].map { locale in
                ["type": "appStoreVersionLocalizations", "id": "loc-\(locale)", "attributes": ["locale": locale, "whatsNew": "old"]] as [String: Any]
            }, "links": ["self": "unused"],
        ])
    }
    let command = try UpdateReleaseNotes.parse([
        "--app-id", "app-1", "--version", "1.2.3", "--metadata-path", jsonFixture("Metadata"), "--apply", "--output", "json",
    ])
    var output: String?
    do {
        output = try await command.renderedOutput(automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init())
        Issue.record("Expected a partial write to fail.")
    } catch {
        #expect(error as? ApogeeError == .appStoreConnectHTTPError(operation: "appStoreVersionLocalizations_updateInstance", statusCode: 403))
        #expect(!String(reflecting: error).contains("response-secret-sentinel"))
    }
    #expect(output == nil)
    #expect(await transport.requests.filter { $0.method == .patch }.count == 2)
}

@Test
func cancelledStatusDoesNotBecomeAJSONSuccess() async throws {
    let transport = StubTransport { _, _, _ in
        throw CancellationError()
    }
    let command = try ReleaseStatusCommand.parse(["--app-id", "app-1", "--version", "2.0", "--output", "json"])
    await #expect(throws: CancellationError.self) {
        _ = try await command.renderedOutput(automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init())
    }
}

@Test
func statusJSONPreservesReleaseTimingWithFractionalSeconds() throws {
    let output = try OutputOptions.parse(["--output", "json"])
    let status = ReleaseStatus(
        app: .init(id: "app-1"),
        version: .init(id: "version-1", releaseType: "SCHEDULED", earliestReleaseDate: Date(timeIntervalSince1970: 1_800_000_000.125)),
        build: nil, reviewSubmissions: []
    )
    let object = try jsonObject(output.render(status, requestedTarget: .init(lookup: .appID("app-1"))))
    let version = try dictionary(dictionary(object, "target"), "version")
    #expect(version["releaseType"] as? String == "SCHEDULED")
    #expect(version["earliestReleaseDate"] as? String == "2027-01-15T08:00:00.125Z")
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func dictionary(_ object: [String: Any], _ key: String) throws -> [String: Any] {
    try #require(object[key] as? [String: Any])
}

private func jsonFixture(_ name: String) -> String {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/AppStore/\(name)").path
}
