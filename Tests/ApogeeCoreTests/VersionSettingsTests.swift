import ApogeeCore
@testable import apogee
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

private let scheduledDate = Date(timeIntervalSince1970: 4_102_444_800)

@Test(arguments: ["MANUAL", "AFTER_APPROVAL", "SCHEDULED"])
func versionSettingsApplyOnlyRequestedFieldsAndVerifyFreshPlans(policy: String) async throws {
    let transport = VersionSettingsTransport(releaseType: policy == "MANUAL" ? "SCHEDULED" : "MANUAL")
    let automation = ReleaseAutomation(api: testAPI(transport: transport))
    var arguments = ["--app-id", "app", "--version", "2.0", "--platform", "MAC_OS", "--copyright", "2100 Example", "--release-type", policy, "--output", "json"]
    if policy == "SCHEDULED" {
        arguments += ["--earliest-release-date", "2100-01-01T09:00:00+09:00"]
    }
    let command = try UpdateVersionSettings.parse(arguments)
    let planned = try await command.renderedOutput(automation: automation, configuration: .init())
    let object = try settingsJSONObject(planned)
    #expect(object["schemaVersion"] as? Int == 1)
    #expect(object["command"] as? String == "update-version-settings")
    #expect(object["mode"] as? String == "dry-run")
    #expect(await transport.patches.isEmpty)
    if policy == "SCHEDULED" {
        #expect(planned.contains("2100-01-01T00:00:00Z"))
    }
    let applied = try await UpdateVersionSettings.parse(arguments + ["--apply"]).renderedOutput(automation: automation, configuration: .init())
    #expect(try settingsJSONObject(applied)["mode"] as? String == "apply")
    let patches = await transport.patches
    #expect(patches.count == 1)
    #expect(Set(patches[0].keys) == (policy == "SCHEDULED" ? ["copyright", "releaseType", "earliestReleaseDate"] : ["copyright", "releaseType"]))
    let fresh = try settingsJSONObject(await command.renderedOutput(automation: automation, configuration: .init()))
    let plan = try #require(fresh["plan"] as? [String: Any])
    #expect(plan["hasChanges"] as? Bool == false)
    #expect(await transport.patches.count == 1)
}

@Test
func versionSettingsCopyrightPreservesPolicyAndEmptyPatchReadsOnly() async throws {
    let transport = VersionSettingsTransport(releaseType: "SCHEDULED")
    let automation = ReleaseAutomation(api: testAPI(transport: transport))
    let read = try await automation.updateVersionSettings(appLookup: .appID("app"), version: "2.0", platform: .macOS, options: .init(mode: .dryRun))
    #expect(read.actions.count == 3)
    #expect(!read.hasChanges)
    #expect(read.actions.first?.currentValue == "2099 Example")
    _ = try await automation.updateVersionSettings(appLookup: .appID("app"), version: "2.0", platform: .macOS,
                                                  patch: .init(copyright: "2100 Example"), options: .init(mode: .apply))
    let patches = await transport.patches
    #expect(Set(patches[0].keys) == ["copyright"])
    let versions = try await testAPI(transport: transport).appStoreVersions(appID: "app", version: "2.0", platform: .macOS)
    #expect(versions.first?.releaseType == "SCHEDULED")
    #expect(versions.first?.earliestReleaseDate == scheduledDate)
}

@Test(arguments: ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"])
func versionSettingsAllowPreparationStates(state: String) async throws {
    let transport = VersionSettingsTransport(state: state)
    let plan = try await ReleaseAutomation(api: testAPI(transport: transport)).updateVersionSettings(
        appLookup: .appID("app"), version: "2.0", platform: .macOS,
        patch: .init(releasePolicy: .afterApproval), options: .init(mode: .dryRun)
    )
    #expect(plan.hasChanges)
    #expect(await transport.patches.isEmpty)
}

@Test(arguments: [nil, "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_DISTRIBUTION"] as [String?])
func versionSettingsRefuseUnknownAndPostSubmissionStates(state: String?) async throws {
    let transport = VersionSettingsTransport(state: state)
    await #expect(throws: (any Error).self) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).updateVersionSettings(
            appLookup: .appID("app"), version: "2.0", platform: .macOS,
            patch: .init(releasePolicy: .afterApproval), options: .init(mode: .apply)
        )
    }
    #expect(await transport.patches.isEmpty)
}

@Test(arguments: ["changed", "copyright", "policy", "date", "identity", "state", "failure", "cancelled"])
func versionSettingsChangesAndWriteFailuresNeverReturnSuccess(scenario: String) async throws {
    let transport = VersionSettingsTransport(scenario: scenario)
    let command = try UpdateVersionSettings.parse([
        "--app-id", "app", "--version", "2.0", "--platform", "MAC_OS", "--copyright", "2100 Example",
        "--release-type", "SCHEDULED", "--earliest-release-date", "2100-01-01T00:00:00Z", "--apply", "--output", "json",
    ])
    do {
        _ = try await command.renderedOutput(automation: ReleaseAutomation(api: testAPI(transport: transport)), configuration: .init())
        Issue.record("Failed version settings must not produce success JSON.")
    } catch {
        if scenario == "cancelled" {
            #expect(error is CancellationError)
        }
    }
    #expect(await transport.patches.count == (scenario == "changed" ? 0 : 1))
}

@Test(arguments: [
    ["--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "MANUAL", "--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "AFTER_APPROVAL", "--earliest-release-date", "2100-01-01T00:00:00Z"],
    ["--release-type", "SCHEDULED"], ["--release-type", "UNKNOWN"],
])
func versionSettingsRejectInvalidCombinations(arguments: [String]) throws {
    let command = try UpdateVersionSettings.parse(["--version", "2.0"] + arguments)
    #expect(throws: VersionSettingsError.invalidReleasePolicy) {
        _ = try command.settingsPatch()
    }
}

@Test(arguments: ["2100-01-01", "2100-01-01T00:00:00", "2100-02-30T00:00:00Z", "2100-01-01T24:00:00Z", "2100-01-01T00:00:00-00:00", "2100-01-01T00:00:00+09:60", "2100-01-01T00:00:00.500Z", "2000-01-01T00:00:00Z", "2100-01-01T00:00:00+19:00"])
func versionSettingsRejectInvalidDates(value: String) throws {
    let command = try UpdateVersionSettings.parse(["--version", "2.0", "--release-type", "SCHEDULED", "--earliest-release-date", value])
    #expect(throws: VersionSettingsError.invalidDate) {
        _ = try command.settingsPatch()
    }
}

@Test
func versionSettingsCoreValidatesBeforeAccessAndOldAdaptersFailClosed() async throws {
    let transport = VersionSettingsTransport()
    let automation = ReleaseAutomation(api: testAPI(transport: transport))
    for patch in [VersionSettingsPatch(copyright: "\n"), .init(releasePolicy: .scheduled(.distantPast)), .init(releasePolicy: .scheduled(Date(timeIntervalSince1970: .infinity))), .init(releasePolicy: .scheduled(scheduledDate.addingTimeInterval(0.5)))] {
        await #expect(throws: VersionSettingsError.self) {
            _ = try await automation.updateVersionSettings(appLookup: .appID("app"), version: "2.0", patch: patch, options: .init(mode: .apply))
        }
    }
    #expect(await transport.requests == 0)
    await #expect(throws: VersionSettingsError.unsupportedAdapter) {
        _ = try await FakeAppStoreConnectAPI().updateVersionSettings(id: "version", patch: .init(copyright: "2100 Example"))
    }
}

@Test
func versionSettingsRejectIncompleteScheduledStateBeforeMutation() async throws {
    let transport = VersionSettingsTransport(releaseType: "SCHEDULED", date: nil)
    await #expect(throws: VersionSettingsError.unknownState) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).updateVersionSettings(
            appLookup: .appID("app"), version: "2.0", platform: .macOS,
            patch: .init(releasePolicy: .manual), options: .init(mode: .apply)
        )
    }
    #expect(await transport.patches.isEmpty)
}

private func settingsJSONObject(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private actor VersionSettingsTransport: ClientTransport {
    var state: String?
    var releaseType: String
    var copyright = "2099 Example"
    var date: Date?
    let scenario: String
    var requests = 0
    var reads = 0
    var patches: [[String: String]] = []

    init(state: String? = "PREPARE_FOR_SUBMISSION", releaseType: String = "MANUAL", scenario: String = "", date: Date? = scheduledDate) {
        self.date = date
        self.state = state
        self.releaseType = releaseType
        self.scenario = scenario
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        requests += 1
        let path = request.path ?? ""
        if request.method == .patch {
            #expect(path == "/v1/appStoreVersions/version")
            let text = try await String(collecting: #require(body), upTo: 100_000)
            let object = try settingsJSONObject(text)
            let data = try #require(object["data"] as? [String: Any])
            #expect(Set(data.keys) == ["id", "type", "attributes"])
            let attributes = try #require(data["attributes"] as? [String: String])
            patches.append(attributes)
            if scenario == "failure" {
                return try jsonResponse(["errors": [["status": "403", "code": "FORBIDDEN", "title": "Private response"]]], status: 403)
            }
            if let value = attributes["copyright"], scenario != "copyright" {
                copyright = value
            }
            if let value = attributes["releaseType"], scenario != "policy" {
                releaseType = value
            }
            if let value = attributes["earliestReleaseDate"] {
                date = try Date(value, strategy: .iso8601)
                if scenario == "date" {
                    date?.addTimeInterval(60)
                }
            }
            if scenario == "cancelled" {
                throw CancellationError()
            }
            if scenario == "state" {
                state = "WAITING_FOR_REVIEW"
            }
            return try jsonResponse(["data": versionResource(), "links": ["self": "unused"]])
        }
        #expect(request.method == .get)
        if path.contains("appStoreVersions") {
            reads += 1
            if scenario == "changed", reads == 2 {
                copyright = "Concurrent change"
            }
            return try jsonResponse(["data": [versionResource()], "links": ["self": "unused"]])
        }
        #expect(path == "/v1/apps/app")
        return try jsonResponse(["data": ["type": "apps", "id": "app"], "links": ["self": "unused"]])
    }

    private func versionResource() -> [String: Any] {
        ["type": "appStoreVersions", "id": scenario == "identity" && !patches.isEmpty ? "changed" : "version",
         "attributes": ["versionString": "2.0", "platform": "MAC_OS", "appVersionState": state as Any? ?? NSNull(),
                        "copyright": copyright, "releaseType": releaseType, "earliestReleaseDate": date?.ISO8601Format() as Any? ?? NSNull()]]
    }
}
