import ApogeeCore
import Foundation
import Testing

@Test(arguments: [
    "unknown-display-sentinel",
    "APP_IPHONE_67",
    "APP_IPAD_PRO_3GEN_129",
], [OperationMode.dryRun, .apply])
func unsupportedScreenshotDisplaysStopBeforeRemoteAccess(displayType: String, mode: OperationMode) async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let valid = directory.appendingPathComponent("input/en-US/IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY")
    let unsupported = directory.appendingPathComponent("input/ja/\(displayType)")
    try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unsupported, withIntermediateDirectories: true)
    try screenshotPNG(seed: 1).write(to: valid.appendingPathComponent("01.png"))
    try screenshotPNG(seed: 2).write(to: unsupported.appendingPathComponent("01.png"))

    let transport = StubTransport { _, _, _ in
        Issue.record("Unsupported displays must fail before any App Store Connect request.")
        return try jsonResponse(["data": [], "links": ["self": "unused"]])
    }
    let recovery = directory.appendingPathComponent("recovery")
    await #expect(throws: ScreenshotError.unsupportedDisplayType) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).updateScreenshots(
            appLookup: .appID("app"), version: "2.0",
            screenshotsPath: directory.appendingPathComponent("input").path,
            options: .init(mode: mode, allowDestructive: true, planToken: "unused",
                           allowUnrecoverableReplacement: true),
            recovery: .init(directory: recovery.path)
        )
    }
    #expect(await transport.requests.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: recovery.path))
}

@Test(arguments: ["IPHONE_DUO", "unknown-display-sentinel"])
func screenshotSetCreationRejectsUnsupportedDisplaysLocally(displayType: String) async throws {
    let transport = StubTransport { _, _, _ in
        Issue.record("Unsupported display types must not create screenshot sets.")
        return try jsonResponse(["data": [], "links": ["self": "unused"]])
    }
    await #expect(throws: ScreenshotError.unsupportedDisplayType) {
        _ = try await testAPI(transport: transport).createScreenshotSet(localizationID: "locale", displayType: displayType)
    }
    #expect(await transport.requests.isEmpty)
    let description = ScreenshotError.unsupportedDisplayType.localizedDescription
    #expect(description.contains("display class"))
    #expect(description.contains("Legacy APP_*"))
    #expect(description.contains("docs/screenshots.md"))
    #expect(!description.contains("unknown-display-sentinel"))
}
