import ApogeeCore
@testable import apogee
import Foundation
import Synchronization
import Testing

@Test
func screenshotCommandKeepsProgressOptInAndSeparateFromFinalJSON() async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (locale, seeds) in [("en-US", [UInt8(1)]), ("ja", [UInt8(2), UInt8(3)])] {
        let display = directory.appendingPathComponent("\(locale)/IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY")
        try FileManager.default.createDirectory(at: display, withIntermediateDirectories: true)
        for seed in seeds {
            try screenshotPNG(seed: seed).write(to: display.appendingPathComponent("\(seed).png"))
        }
    }
    let path = directory.path
    let arguments = ["--app-id", "app", "--version", "2.0", "--screenshots-path", path, "--output", "json"]
    let lines = Mutex<[String]>([])
    let sink: @Sendable (String) -> Void = { line in
        lines.withLock { $0.append(line) }
    }
    let quiet = try UpdateScreenshots.parse(arguments)
    let quietOutput = try await quiet.renderedOutput(
        automation: .init(api: testAPI(transport: progressPlanningTransport())), configuration: .init(), progressOutput: sink
    )
    #expect(lines.withLock { $0.isEmpty })
    let progress = try UpdateScreenshots.parse(arguments + ["--progress"])
    let progressOutput = try await progress.renderedOutput(
        automation: .init(api: testAPI(transport: progressPlanningTransport())), configuration: .init(), progressOutput: sink
    )
    #expect(progressOutput == quietOutput)
    let result = try #require(JSONSerialization.jsonObject(with: Data(progressOutput.utf8)) as? [String: Any])
    #expect(result["schemaVersion"] as? Int == 1)
    #expect(result["command"] as? String == "update-screenshots")
    let observed = lines.withLock { $0 }
    #expect(observed.count == 2)
    #expect(observed.contains { $0.contains("[en-US/IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY] planning verified=0/3") })
    #expect(observed.contains { $0.contains("[ja/IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY] planning verified=0/3") })
    #expect(observed.allSatisfy { !$0.contains(path) && !$0.contains("private-sentinel") })
}

@Test
func screenshotProgressRendererOmitsUntrustedLabelsAndShowsBoundedWaits() {
    let text = ScreenshotProgressOutput.render(.init(
        stage: .waitingForChecksum, locale: "en-US\n/private/secret", displayType: "https://host/path?token=secret",
        completedImages: 2, totalImages: 3, elapsedSeconds: 12.5, processingAttempt: 4, processingLimit: 30
    ))
    #expect(text == "screenshots [unknown/unknown] waitingForChecksum verified=2/3 elapsed=12.5s observation=4/30")
}

private func progressPlanningTransport() -> StubTransport {
    StubTransport { request, _, _ in
        #expect(request.method == .get)
        let path = request.path ?? ""
        if path == "/v1/apps/app" {
            return try jsonResponse(["data": ["type": "apps", "id": "app"], "links": ["self": "unused"]])
        }
        if path.contains("/apps/app/appStoreVersions") {
            return try jsonResponse([
                "data": [["type": "appStoreVersions", "id": "version", "attributes": [
                    "versionString": "2.0", "platform": "IOS", "appVersionState": "PREPARE_FOR_SUBMISSION",
                ]]], "links": ["self": "unused"],
            ])
        }
        if path.contains("/appStoreVersions/version/appStoreVersionLocalizations") {
            return try jsonResponse([
                "data": ["en-US", "ja"].map { locale in
                    ["type": "appStoreVersionLocalizations", "id": "localization-\(locale)", "attributes": ["locale": locale]] as [String: Any]
                }, "links": ["self": "unused"],
            ])
        }
        if path == "/v1/appAssetLibraryRefData" {
            return try jsonResponse(libraryReferenceFixture())
        }
        #expect(path.contains("/placements"))
        return try jsonResponse(["data": [], "links": ["self": "unused"]])
    }
}
