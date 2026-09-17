import ApogeeCore
@testable import apogee
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@Test(arguments: ["text", "json"])
func feedbackCommandReadsExactBuildAndRedactsPrivateFields(format: String) async throws {
    let transport = feedbackTransport()
    let command = try BuildFeedbackCommand.parse([
        "--app-id", "app-1", "--version", "2.0", "--build-version", "42", "--platform", "MAC_OS", "--output", format,
    ])
    let output = try await command.renderedOutput(automation: .init(api: testAPI(transport: transport)), configuration: .init())
    #expect(!output.contains("private-sentinel"))
    #expect(!output.contains("download.example"))
    if format == "json" {
        let root = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(root["schemaVersion"] as? Int == 1)
        #expect(root["kind"] as? String == "build-feedback")
        #expect(root["mode"] as? String == "read-only")
        let requested = try #require(root["requestedTarget"] as? [String: Any])
        #expect(requested["buildVersion"] as? String == "42")
        #expect(requested["version"] as? String == "2.0")
        let feedback = try #require(root["feedback"] as? [String: Any])
        #expect(feedback["crashCount"] as? Int == 2)
        #expect(feedback["screenshotCount"] as? Int == 2)
        let crashes = try #require(feedback["crashes"] as? [[String: Any]])
        #expect(crashes[0]["buildID"] as? String == "build-42")
        #expect(crashes[0]["hasComment"] as? Bool == true)
        #expect(crashes[1]["hasComment"] is NSNull)
        #expect(crashes[1]["deviceModel"] is NSNull)
    } else {
        #expect(output.contains("Crash feedback: 2"))
        #expect(output.contains("Screenshot feedback: 2"))
        #expect(output.contains("build-42"))
    }
    #expect(await transport.requests.count == 6)
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}

@Test(arguments: ["missing-build", "ambiguous-build", "invalid-build", "wrong-build", "missing-attributes", "missing-linkage", "duplicate", "unauthorized", "second-page-failure", "cancelled", "cycle"])
func feedbackFailuresNeverReturnSuccessOrZeroFeedback(scenario: String) async throws {
    let transport = feedbackTransport(scenario: scenario)
    let command = try BuildFeedbackCommand.parse([
        "--app-id", "app-1", "--version", "2.0", "--build-version", "42", "--output", "json", "--platform", "MAC_OS",
    ])
    var output: String?
    do {
        output = try await command.renderedOutput(automation: .init(api: testAPI(transport: transport)), configuration: .init())
        Issue.record("Incomplete feedback must fail.")
    } catch {
        #expect(!String(reflecting: error).contains("private-sentinel"))
        if scenario == "cancelled" { #expect(error is CancellationError) }
    }
    #expect(output == nil)
    let requests = await transport.requests
    if ["missing-build", "ambiguous-build", "invalid-build"].contains(scenario) {
        #expect(requests.count == 2)
    } else {
        #expect(requests.count >= 3)
    }
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}

@Test
func confirmedEmptyFeedbackAndUnsupportedAdaptersRemainDistinct() async throws {
    let feedback = try await ReleaseAutomation(api: testAPI(transport: feedbackTransport(scenario: "empty"))).buildFeedback(
        appLookup: .appID("app-1"), version: "2.0", buildVersion: "42", platform: .macOS
    )
    #expect(feedback.crashes.isEmpty)
    #expect(feedback.screenshots.isEmpty)
    await #expect(throws: BuildFeedbackError.unsupportedAdapter) {
        _ = try await FakeAppStoreConnectAPI().crashFeedback(appID: "app-1", buildID: "build-42")
    }
}

private func feedbackTransport(scenario: String = "success") -> StubTransport {
    StubTransport { request, _, _ in
        try feedbackResponse(request: request, scenario: scenario)
    }
}

private func feedbackResponse(request: HTTPRequest, scenario: String) throws -> (HTTPResponse, HTTPBody?) {
        #expect(request.method == .get)
        let path = (request.path ?? "").removingPercentEncoding ?? ""
        if path == "/v1/apps/app-1" {
            return try jsonResponse(["data": ["type": "apps", "id": "app-1", "attributes": ["bundleId": "com.example.app"]], "links": ["self": "unused"]])
        }
        if path.hasPrefix("/v1/builds?") {
            #expect(path.contains("filter[app]=app-1"))
            #expect(path.contains("filter[version]=42"))
            #expect(path.contains("filter[preReleaseVersion.version]=2.0"))
            #expect(path.contains("MAC_OS"))
            let build: [String: Any] = ["type": "builds", "id": "build-42", "attributes": [
                "version": "42", "processingState": scenario == "invalid-build" ? "PROCESSING" : "VALID",
            ]]
            return try jsonResponse(["data": scenario == "missing-build" ? [] : (scenario == "ambiguous-build" ? [build, build] : [build]), "links": ["self": "unused"]])
        }
        #expect(path.contains("/v1/apps/app-1/betaFeedback"))
        #expect(path.contains("filter[build]=build-42"))
        #expect(!path.contains("email"))
        #expect(!path.contains("tester"))
        let screenshot = path.contains("Screenshot")
        let resource = screenshot ? "betaFeedbackScreenshotSubmissions" : "betaFeedbackCrashSubmissions"
        let second = path.contains("cursor=second")
        if scenario == "cancelled" { throw CancellationError() }
        if scenario == "unauthorized" || (scenario == "second-page-failure" && second) {
            return try jsonResponse(["errors": [["status": "403", "title": "private-sentinel"]]], status: 403)
        }
        var attributes: [String: Any] = ["osVersion": "27.0"]
        if !second {
            attributes["createdDate"] = "2026-09-16T10:20:30.125Z"
            attributes["deviceModel"] = "Example Device"
            attributes["comment"] = "private-sentinel"
            attributes["email"] = "private-sentinel@example.invalid"
            attributes["screenshots"] = [["url": "https://download.example/private-sentinel"]]
        }
        let buildID = scenario == "wrong-build" ? "another-build" : "build-42"
        let suffix = second && scenario != "duplicate" ? 2 : 1
        var entry: [String: Any] = [
            "type": resource, "id": "\(resource)-\(suffix)", "attributes": attributes,
            "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
        ]
        if scenario == "missing-attributes" { entry.removeValue(forKey: "attributes") }
        if scenario == "missing-linkage" { entry.removeValue(forKey: "relationships") }
        let next = "https://api.appstoreconnect.apple.com/v1/apps/app-1/\(resource)?filter%5Bbuild%5D=build-42&cursor=second"
        return try jsonResponse([
            "data": scenario == "empty" ? [] : [entry],
            "links": (second && scenario != "cycle") || scenario == "empty" ? ["self": "unused"] : ["self": "unused", "next": next],
        ])
    }
