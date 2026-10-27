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

@Test(arguments: ["MANUAL", "AFTER_APPROVAL", "SCHEDULED"], [false, true])
func versionCreationUsesExplicitPolicy(policy: String, apply: Bool) async throws {
    let date = policy == "SCHEDULED" ? "2100-01-01T00:00:00Z" : nil
    let transport = versionCreationTransport(releaseType: policy, earliestReleaseDate: date)
    let command = try CreateVersion.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--release-type", policy,
    ] + (date.map { ["--earliest-release-date", $0] } ?? []) + (apply ? ["--apply"] : []))
    let plan = try await command.createVersion(
        automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
    )
    #expect(plan.actions.first?.desiredValue?.contains(policy) == true)
    if let date {
        #expect(plan.actions.first?.desiredValue?.contains(date) == true)
    }
    #expect(plan.actions.map(\.kind) == (apply ? [.create, .verify] : [.create]))
    #expect(await transport.requests.filter { $0.method == .post }.count == (apply ? 1 : 0))
}

@Test(arguments: [
    ["--release-type", "UNKNOWN"], ["--release-type", "SCHEDULED"],
    ["--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "MANUAL", "--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "AFTER_APPROVAL", "--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "SCHEDULED", "--earliest-release-date", "2020-01-01T00:00:00Z"],
    ["--release-type", "SCHEDULED", "--earliest-release-date", "2100-02-30T00:00:00Z"],
])
func versionCreationRejectsInvalidPolicyBeforeRequests(arguments: [String]) async throws {
    let command = try CreateVersion.parse(["--app-id", "app-1", "--version", "2.0", "--apply"] + arguments)
    let transport = versionCreationTransport()
    await #expect(throws: VersionSettingsError.self) {
        _ = try await command.createVersion(
            automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
        )
    }
    #expect(await transport.requests.isEmpty)
}

@Test(arguments: [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: .infinity),
                  Date(timeIntervalSince1970: 4_102_444_800.5)])
func versionCreationValidatesLibraryScheduleBeforeRequests(date: Date) async throws {
    let transport = versionCreationTransport()
    await #expect(throws: VersionSettingsError.invalidDate) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).createVersion(
            appLookup: .appID("app-1"), version: "2.0", releasePolicy: .scheduled(date), options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.isEmpty)
}

@Test(arguments: ["release", "date"])
func versionCreationRejectsAutomaticPolicyReadBackMismatch(scenario: String) async throws {
    let command = try CreateVersion.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--apply",
        "--release-type", "SCHEDULED", "--earliest-release-date", "2100-01-01T00:00:00Z",
    ])
    let transport = versionCreationTransport(scenario: scenario, releaseType: "SCHEDULED", earliestReleaseDate: "2100-01-01T00:00:00Z")
    await #expect(throws: ApogeeError.self) {
        _ = try await command.createVersion(
            automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init()
        )
    }
    #expect(await transport.requests.filter { $0.method == .post }.count == 1)
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

@Test(arguments: [VersionReleasePolicy.manual, .afterApproval])
func existingAdaptersFailClosedForVersionCreation(policy: VersionReleasePolicy) async throws {
    let api = FakeAppStoreConnectAPI()
    await #expect(throws: VersionCreationError.unsupportedAdapter) {
        _ = try await ReleaseAutomation(api: api).createVersion(
            appLookup: .appID("app-1"), version: "2.0", releasePolicy: policy, options: .init(mode: .apply)
        )
    }
    #expect(await api.updatedLocalizationIDs.isEmpty)
    #expect(await api.attachedBuildIDs.isEmpty)
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
}

@Test
func manualOnlyAdaptersRetainCreationWithoutSilentlyAcceptingAutomaticRelease() async throws {
    let api = FakeAppStoreConnectAPI(supportsManualCreation: true)
    let automation = ReleaseAutomation(api: api)
    await #expect(throws: VersionCreationError.unsupportedAdapter) {
        _ = try await automation.createVersion(
            appLookup: .appID("app-1"), version: "2.0", releasePolicy: .afterApproval, options: .init(mode: .apply)
        )
    }
    #expect(try await api.appStoreVersions(appID: "app-1", version: "2.0", platform: .iOS).isEmpty)
    let plan = try await automation.createVersion(
        appLookup: .appID("app-1"), version: "2.0", options: .init(mode: .apply)
    )
    #expect(plan.actions.last?.kind == .verify)
    #expect(plan.target?.version?.releaseType == "MANUAL")
}

@Test(arguments: [false, true])
func creationJSONSeparatesRequestedAndObservedVersion(apply: Bool) async throws {
    let command = try CreateVersion.parse([
        "--app-id", "app-1", "--version", "2.0", "--platform", "MAC_OS", "--output", "json",
    ] + (apply ? ["--apply"] : []))
    let text = try await command.renderedOutput(
        automation: ReleaseAutomation(api: testAPI(transport: versionCreationTransport())), configuration: .init()
    )
    let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    let target = try #require(object["target"] as? [String: Any])
    if apply {
        let version = try #require(target["version"] as? [String: Any])
        #expect(version["id"] as? String == "version-new")
        #expect(version["versionString"] as? String == "2.0")
        #expect(version["platform"] as? String == "MAC_OS")
    } else {
        #expect(target["version"] is NSNull)
    }
    let requested = try #require(object["requestedTarget"] as? [String: Any])
    #expect(requested["version"] as? String == "2.0")
}

private func versionCreationTransport(
    scenario: String = "success", platform: Platform = .macOS,
    releaseType: String = "MANUAL", earliestReleaseDate: String? = nil
) -> StubTransport {
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
            var expectedAttributes = ["platform": platform.rawValue, "versionString": "2.0", "releaseType": releaseType]
            expectedAttributes["earliestReleaseDate"] = earliestReleaseDate
            #expect(attributes == expectedAttributes)
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
            var attributes: [String: Any] = scenario == "unknown" ? [:] : [
                "versionString": scenario == "version" ? "3.0" : "2.0",
                "platform": scenario == "platform" ? "IOS" : platform.rawValue,
                "releaseType": scenario == "release" ? (releaseType == "MANUAL" ? "AFTER_APPROVAL" : "MANUAL") : releaseType,
                "appVersionState": scenario == "state" ? "WAITING_FOR_REVIEW" : "PREPARE_FOR_SUBMISSION",
            ]
            if let earliestReleaseDate {
                attributes["earliestReleaseDate"] = scenario == "date" ? "2100-01-02T00:00:00Z" : earliestReleaseDate
            }
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
