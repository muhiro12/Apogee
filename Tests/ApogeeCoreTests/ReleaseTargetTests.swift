import ApogeeCore
import Foundation
import HTTPTypes
import Testing

@Test(arguments: ["app-id", "bundle-id", "version", "platform", "build-number", "missing-build-number"])
func attachmentRejectsMismatchedReleaseTargetsBeforeWriting(scenario: String) async throws {
    let lookup: AppLookup = scenario == "bundle-id" ? .bundleID("com.example.app") : .appID("app")
    let transport = StubTransport { request, _, _ in
        let path = request.path ?? ""
        if request.method == .patch {
            return (.init(status: .noContent), nil)
        }
        if path.contains("/builds?") {
            var attributes = ["version": scenario == "build-number" ? "99" : "12", "processingState": "VALID"]
            if scenario == "missing-build-number" {
                attributes.removeValue(forKey: "version")
            }
            return try jsonResponse(["data": [["type": "builds", "id": "build", "attributes": attributes]], "links": ["self": "unused"]])
        }
        if path.contains("/appStoreVersions?") {
            let attributes = ["versionString": scenario == "version" ? "3.0" : "2.0",
                              "platform": scenario == "platform" ? "MAC_OS" : "IOS"]
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version", "attributes": attributes]],
                                     "links": ["self": "unused"]])
        }
        if path.contains("/appStoreVersions/version") {
            return try jsonResponse(["data": ["type": "appStoreVersions", "id": "version",
                                              "relationships": ["build": ["data": NSNull()]]], "links": ["self": "unused"]])
        }
        let app: [String: Any] = ["type": "apps", "id": scenario == "app-id" ? "other" : "app",
                                  "attributes": ["bundleId": scenario == "bundle-id" ? "com.example.other" : "com.example.app"]]
        if path.contains("/apps?") {
            return try jsonResponse(["data": [app], "links": ["self": "unused"]])
        }
        return try jsonResponse(["data": app, "links": ["self": "unused"]])
    }
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).attachBuild(
            appLookup: lookup, version: "2.0", buildVersion: "12", options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}
