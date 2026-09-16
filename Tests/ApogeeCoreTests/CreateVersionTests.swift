import ApogeeCore
@testable import apogee
import Foundation
import Testing

@Test(arguments: [false, true])
func createVersionCommandDefaultsToPlanningAndAppliesExplicitly(apply: Bool) async throws {
    let transport = versionCreationTransport()
    let command = try CreateVersion.parse(
        ["--bundle-id", "com.example.app", "--version", "2.0", "--platform", "MAC_OS"]
        + (apply ? ["--apply"] : [])
    )
    let plan = try await command.createVersion(
        automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
    )
    #expect(plan.actions.map(\.kind) == (apply ? [.create, .verify] : [.create]))
    #expect(plan.hasChanges)
    #expect(!plan.hasDestructiveActions)
    #expect(PlanRenderer().render(plan).contains("MANUAL"))
    let requests = await transport.requests
    #expect(requests.count == (apply ? 4 : 2))
    #expect(requests.filter { $0.method == .post }.count == (apply ? 1 : 0))
}

@Test(arguments: [Platform.iOS, .macOS, .tvOS, .visionOS])
func versionCreationScopesRequestsToTheSelectedPlatform(platform: Platform) async throws {
    let transport = versionCreationTransport(platform: platform)
    let plan = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
        appLookup: .appID("app-1"), version: "2.0", platform: platform, options: .init(mode: .apply)
    )
    #expect(plan.actions.last?.resource == "appStoreVersion/version-new")
}

@Test(arguments: ["existing", "ambiguous", "existing-next"])
func versionCreationRefusesExistingVersionsBeforeWriting(scenario: String) async throws {
    let transport = versionCreationTransport(scenario: scenario)
    do {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
            appLookup: .appID("app-1"), version: "2.0", platform: .macOS, options: .init(mode: .apply)
        )
        Issue.record("Existing versions must not be created again.")
    } catch {
        if scenario == "ambiguous" {
            #expect(error as? ApogeeError == .appStoreVersionAmbiguous(appID: "app-1", version: "2.0", matches: 2))
        } else {
            #expect(error as? VersionCreationError == .versionAlreadyExists(appID: "app-1", version: "2.0"))
        }
    }
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}

@Test(arguments: ["id", "version", "platform", "release", "state", "unknown", "missing", "duplicate"])
func versionCreationRejectsReadBackMismatch(scenario: String) async throws {
    let transport = versionCreationTransport(scenario: scenario)
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
            appLookup: .appID("app-1"), version: "2.0", platform: .macOS, options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.count == 4)
    #expect(await transport.requests.filter { $0.method == .post }.count == 1)
}

@Test(arguments: ["403", "409", "timeout", "cancelled"])
func versionCreationDoesNotRetryFailedWritesOrExposeRawErrors(scenario: String) async throws {
    let transport = versionCreationTransport(scenario: scenario)
    do {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
            appLookup: .appID("app-1"), version: "2.0", platform: .macOS, options: .init(mode: .apply)
        )
        Issue.record("Expected a creation failure.")
    } catch {
        if scenario == "cancelled" {
            #expect(error is CancellationError)
        } else if scenario == "timeout" {
            #expect(error as? ApogeeError == .appStoreConnectTransportFailed(operation: "createAppStoreVersion"))
        } else {
            #expect(error as? ApogeeError == .appStoreConnectHTTPError(
                operation: "appStoreVersions_createInstance", statusCode: Int(scenario)!
            ))
        }
        #expect(!String(reflecting: error).contains("response-secret-sentinel"))
        #expect(!String(reflecting: error).contains("Bearer"))
    }
    #expect(await transport.requests.count == 3)
}

@Test(arguments: ["", " ", " 2.0", "2.0\n"])
func versionCreationRejectsEmptyOrPaddedVersionStrings(version: String) async throws {
    let transport = versionCreationTransport()
    await #expect(throws: VersionCreationError.invalidVersion(version)) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
            appLookup: .appID("app-1"), version: version, options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.isEmpty)
}

@Test
func existingAdaptersFailClosedForVersionCreation() async throws {
    let api = FakeAppStoreConnectAPI()
    await #expect(throws: VersionCreationError.unsupportedAdapter) {
        _ = try await ReleaseAutomation(api: api).createVersion(
            appLookup: .appID("app-1"), version: "2.0", options: .init(mode: .apply)
        )
    }
    #expect(await api.updatedLocalizationIDs.isEmpty)
    #expect(await api.attachedBuildIDs.isEmpty)
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
}

private func versionCreationTransport(scenario: String = "success", platform: Platform = .macOS) -> StubTransport {
    StubTransport { request, body, index in
        let path = request.path ?? ""
        if request.method == .post {
            #expect(path == "/v1/appStoreVersions")
            #expect(index == 2)
            let payload = try #require(body)
            let object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
            let data = try #require(object["data"] as? [String: Any])
            #expect(data["type"] as? String == "appStoreVersions")
            let attributes = try #require(data["attributes"] as? [String: String])
            #expect(attributes == ["platform": platform.rawValue, "versionString": "2.0", "releaseType": "MANUAL"])
            let relationships = try #require(data["relationships"] as? [String: Any])
            #expect(Set(relationships.keys) == ["app"])
            let app = try #require(relationships["app"] as? [String: Any])
            #expect(app["data"] as? [String: String] == ["type": "apps", "id": "app-1"])
            if scenario == "cancelled" {
                throw CancellationError()
            }
            if scenario == "timeout" {
                throw URLError(.timedOut)
            }
            if let status = Int(scenario) {
                return try jsonResponse([
                    "errors": [["status": scenario, "code": "REJECTED", "title": "response-secret-sentinel"]],
                ], status: status)
            }
            return try jsonResponse([
                "data": ["type": "appStoreVersions", "id": "version-new"], "links": ["self": "unused"],
            ], status: 201)
        }
        #expect(request.method == .get)
        if path.contains("appStoreVersions") {
            #expect(path.contains("/apps/app-1/"))
            #expect(path.contains("2.0"))
            #expect(path.contains(platform.rawValue))
            let nextPage = path.contains("cursor=second")
            let existing = ["existing", "ambiguous"].contains(scenario) || nextPage
            let readBack = index > 2
            let attributes: [String: Any] = scenario == "unknown" ? [:] : [
                "versionString": scenario == "version" ? "3.0" : "2.0",
                "platform": scenario == "platform" ? "IOS" : platform.rawValue,
                "releaseType": scenario == "release" ? "AFTER_APPROVAL" : "MANUAL",
                "appVersionState": scenario == "state" ? "WAITING_FOR_REVIEW" : "PREPARE_FOR_SUBMISSION",
            ]
            let version: [String: Any] = [
                "type": "appStoreVersions", "id": scenario == "id" ? "different" : "version-new",
                "attributes": attributes,
            ]
            var versions: [[String: Any]] = []
            if existing || (readBack && scenario != "missing") {
                versions = [version]
            }
            if scenario == "ambiguous" || (readBack && scenario == "duplicate") {
                versions.append(version)
            }
            let next = "https://api.appstoreconnect.apple.com" + path + "&cursor=second"
            return try jsonResponse([
                "data": versions,
                "links": scenario == "existing-next" && !nextPage
                    ? ["self": "unused", "next": next] : ["self": "unused"],
            ])
        }
        #expect(index == 0)
        let app: [String: Any] = ["type": "apps", "id": "app-1", "attributes": ["bundleId": "com.example.app"]]
        if path.contains("/apps?") {
            #expect(path.contains("com.example.app"))
            return try jsonResponse(["data": [app], "links": ["self": "unused"]])
        }
        #expect(path == "/v1/apps/app-1")
        return try jsonResponse(["data": app, "links": ["self": "unused"]])
    }
}
