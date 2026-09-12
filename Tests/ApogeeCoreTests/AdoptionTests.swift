import ApogeeCore
import Foundation
import Testing

@Test
func explicitConfigurationResolvesPathsBesideItsFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let path = directory.appendingPathComponent("apogee.json")
    try Data(#"{"metadataPath":"../Metadata","screenshotsPath":"/tmp/ExampleScreenshots"}"#.utf8).write(to: path)
    let configuration = try ApogeeConfiguration.load(from: path.path)
    #expect(configuration.resolvedMetadataPath == directory.deletingLastPathComponent().appendingPathComponent("Metadata").path)
    #expect(configuration.resolvedScreenshotsPath == "/tmp/ExampleScreenshots")
    #expect(configuration.resolvedWebhooksPath == directory.appendingPathComponent("AppStore/webhooks.json").path)
}

@Test
func releaseStatusSeparatesReviewFromPublicationWithoutWriting() async throws {
    let api = FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "review-1", state: "COMPLETE", platform: .iOS, appStoreVersionID: "version-1", itemIDs: ["item-1"]),
        .init(id: "older-review", state: "COMPLETE", platform: .iOS, appStoreVersionID: "older-version"),
    ])
    var status = try await ReleaseAutomation(api: api).releaseStatus(appLookup: .appID("app-1"), version: "1.2.3")
    status.version.state = "PENDING_DEVELOPER_RELEASE"
    status.version.releaseType = "SCHEDULED"
    status.version.earliestReleaseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let output = PlanRenderer().render(status)
    #expect(status.reviewSubmissions.map(\.id) == ["review-1"])
    #expect(output.contains("PENDING_DEVELOPER_RELEASE"))
    #expect(output.contains("SCHEDULED"))
    #expect(output.contains("2027-01-15T08:00:00Z"))
    #expect(output.contains("review-1 [COMPLETE]"))
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test
func metadataPlansKeepTheFullTextReviewable() {
    let text = String(repeating: "Long release notes ", count: 30) + "final change"
    let plan = ReleasePlan(title: "Metadata", actions: [
        .init(kind: .update, resource: "locale-1", currentValue: "old", desiredValue: text),
    ])
    #expect(PlanRenderer().render(plan).contains(text))
}

@Test
func verificationAndUnsupportedActionsAreNotMutations() {
    let plan = ReleasePlan(title: "Read-only", actions: [
        .init(kind: .verify, resource: "metadata"),
        .init(kind: .unsupported, resource: "screenshots"),
        .init(kind: .unchanged, resource: "review"),
    ])
    #expect(!plan.hasChanges)
}
