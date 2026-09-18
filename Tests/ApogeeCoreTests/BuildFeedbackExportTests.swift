@testable import ApogeeCore
@testable import apogee
import Foundation
import Testing

@Test(arguments: ["scheme", "host", "suffix-host", "credentials", "fragment", "port", "expired"])
func feedbackArtifactLocationsFailClosed(scenario: String) throws {
    var artifact = BuildFeedbackArtifact(url: "https://is1-ssl.mzstatic.com/feedback/one")
    switch scenario {
    case "scheme": artifact.url = "http://is1-ssl.mzstatic.com/feedback/one"
    case "host": artifact.url = "https://example.invalid/feedback/one"
    case "suffix-host": artifact.url = "https://apple.com.example.invalid/feedback/one"
    case "credentials": artifact.url = "https://user:pass@is1-ssl.mzstatic.com/feedback/one"
    case "fragment": artifact.url = "https://is1-ssl.mzstatic.com/feedback/one#fragment"
    case "port": artifact.url = "https://is1-ssl.mzstatic.com:8443/feedback/one"
    default: artifact.expirationDate = .now.addingTimeInterval(-1)
    }
    #expect(throws: BuildFeedbackError.unsafeArtifact) {
        try BuildFeedbackArtifactTransport.validate(artifact)
    }
}

@Test
func feedbackArtifactLocationsAcceptAppleHostsAndFutureExpiry() throws {
    try BuildFeedbackArtifactTransport.validate(.init(url: "https://is1-ssl.mzstatic.com/feedback/one"))
    try BuildFeedbackArtifactTransport.validate(.init(url: "https://iosapps.itunes.apple.com/feedback/one",
                                                     expirationDate: .now.addingTimeInterval(600)))
}

@Test
func feedbackArtifactExportWritesPrivateFilesWithoutOverwriting() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0x02])
    let entries = [
        BuildFeedbackSummary(id: "feedback-1", buildID: "build-42", hasArtifact: true, artifacts: [
            .init(url: "https://is1-ssl.mzstatic.com/one"), .init(url: "https://is1-ssl.mzstatic.com/two"),
        ]),
        BuildFeedbackSummary(id: "feedback-2", buildID: "build-42", hasArtifact: false),
    ]
    let destination = root.appendingPathComponent("export")
    let exported = try await BuildFeedbackExporter(export: .init(directory: destination.path))
        .export(entries, kind: "screenshot") { $0.url.hasSuffix("one") ? png : jpeg }
    #expect(exported[0].exportedFiles == ["screenshot/feedback-1/01.png", "screenshot/feedback-1/02.jpg"])
    #expect(exported[1].exportedFiles.isEmpty)
    #expect(try Data(contentsOf: destination.appendingPathComponent("screenshot/feedback-1/01.png")) == png)
    #expect(try Data(contentsOf: destination.appendingPathComponent("screenshot/feedback-1/02.jpg")) == jpeg)
    for path in [destination.path, destination.appendingPathComponent("screenshot/feedback-1/01.png").path] {
        let permissions = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o077 == 0)
    }
    // Reusing a destination must never replace earlier evidence.
    await #expect(throws: BuildFeedbackError.exportConflict) {
        _ = try await BuildFeedbackExporter(export: .init(directory: destination.path))
            .export(entries, kind: "screenshot") { _ in png }
    }
}

@Test(arguments: ["empty-path", "missing-parent", "file-destination", "unsafe-id", "unknown-payload"])
func feedbackArtifactExportRefusesUnsafeDestinationsAndPayloads(scenario: String) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var destination = root.appendingPathComponent("export").path
    var entry = BuildFeedbackSummary(id: "feedback-1", buildID: "build-42", hasArtifact: true,
                                     artifacts: [.init(url: "https://is1-ssl.mzstatic.com/one")])
    var payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    var expected = BuildFeedbackError.invalidExportDestination
    switch scenario {
    case "empty-path":
        destination = ""
    case "missing-parent":
        destination = root.appendingPathComponent("absent/export").path
    case "file-destination":
        try Data().write(to: root.appendingPathComponent("export"))
    case "unsafe-id":
        entry.id = "../outside"
        expected = .unsafeArtifact
    default:
        payload = Data("<html>not an image</html>".utf8)
        expected = .unsafeArtifact
    }
    await #expect(throws: expected) {
        _ = try await BuildFeedbackExporter(export: .init(directory: destination)).export([entry], kind: "screenshot") { _ in payload }
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
}

/// The command must not contact a location outside Apple's asset hosts, even when asked to export.
@Test
func feedbackCommandExportRefusesNonAppleArtifactLocations() async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("export")
    let command = try BuildFeedbackCommand.parse([
        "--app-id", "app-1", "--version", "2.0", "--build-version", "42", "--platform", "MAC_OS",
        "--export-path", destination.path,
    ])
    await #expect(throws: BuildFeedbackError.unsafeArtifact) {
        _ = try await command.renderedOutput(automation: .init(api: testAPI(transport: exportFeedbackTransport())),
                                             configuration: .init())
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
}

private func exportFeedbackTransport() -> StubTransport {
    StubTransport { request, _, _ in
        let path = (request.path ?? "").removingPercentEncoding ?? ""
        if path == "/v1/apps/app-1" {
            return try jsonResponse(["data": ["type": "apps", "id": "app-1", "attributes": ["bundleId": "com.example.app"]],
                                     "links": ["self": "unused"]])
        }
        if path.hasPrefix("/v1/builds?") {
            return try jsonResponse(["data": [["type": "builds", "id": "build-42",
                                               "attributes": ["version": "42", "processingState": "VALID"]]],
                                     "links": ["self": "unused"]])
        }
        let screenshot = path.contains("Screenshot")
        let resource = screenshot ? "betaFeedbackScreenshotSubmissions" : "betaFeedbackCrashSubmissions"
        var attributes: [String: Any] = ["osVersion": "27.0"]
        if screenshot {
            attributes["screenshots"] = [["url": "https://download.example/private-sentinel"]]
        }
        return try jsonResponse([
            "data": [["type": resource, "id": "\(resource)-1", "attributes": attributes,
                      "relationships": ["build": ["data": ["type": "builds", "id": "build-42"]]]]],
            "links": ["self": "unused"],
        ])
    }
}
