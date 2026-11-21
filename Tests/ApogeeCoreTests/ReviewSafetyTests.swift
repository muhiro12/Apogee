import ApogeeCore
import Testing

@Test(arguments: ["PROCESSING", "FAILED", "INVALID", nil])
func unprocessedBuildCannotBeAttached(state: String?) async throws {
    let api = FakeAppStoreConnectAPI(availableBuildState: state)
    await #expect(throws: ApogeeError.buildNotReady(id: "build-123", state: state)) {
        _ = try await ReleaseAutomation(api: api).attachBuild(
            appLookup: .appID("app-1"), version: "1.2.3", buildVersion: "123", options: .init(mode: .apply)
        )
    }
    #expect(await api.attachedBuildIDs.isEmpty)
}

@Test
func reviewRequiresAnAttachedBuildBeforeCreatingResources() async throws {
    let api = FakeAppStoreConnectAPI(attachedBuild: nil)
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: api).submitForReview(
            appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
        )
    }
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test
func reviewResumesAfterItemCreationFails() async throws {
    let api = FakeAppStoreConnectAPI(failItemCreationOnce: true)
    let automation = ReleaseAutomation(api: api)
    await #expect(throws: ApogeeError.self) {
        _ = try await automation.submitForReview(
            appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
        )
    }
    #expect(await api.createdReviewSubmissionIDs == ["review-1"])
    let plan = try await automation.submitForReview(
        appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
    )
    #expect(await api.createdReviewSubmissionIDs == ["review-1"])
    #expect(await api.submittedReviewSubmissionIDs == ["review-1"])
    #expect(plan.actions.contains { $0.kind == .verify })
}

@Test(arguments: [["item-1", "unrelated-item"], nil])
func reviewRejectsAdditionalOrUnknownItems(itemIDs: [String]?) async throws {
    let api = FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "review-1", state: "READY_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1", itemIDs: itemIDs),
    ])
    await #expect(throws: ApogeeError.reviewSubmissionContentsUnsafe(id: "review-1")) {
        _ = try await ReleaseAutomation(api: api).submitForReview(
            appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
        )
    }
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test
func reviewRejectsContentsChangedSincePlanning() async throws {
    let api = FakeAppStoreConnectAPI(
        reviewSubmissions: [
            .init(id: "review-1", state: "READY_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1", itemIDs: ["item-1"]),
        ],
        reviewReadBackOverride: .init(id: "review-1", state: "READY_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1", itemIDs: ["item-1", "other"])
    )
    await #expect(throws: ApogeeError.self) {
        _ = try await ReleaseAutomation(api: api).submitForReview(
            appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
        )
    }
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test
func reviewDryRunDoesNotCreateOrSubmit() async throws {
    let api = FakeAppStoreConnectAPI()
    _ = try await ReleaseAutomation(api: api).submitForReview(
        appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .dryRun)
    )
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test
func submittedReviewIsNotSubmittedAgain() async throws {
    let api = FakeAppStoreConnectAPI(reviewSubmissions: [
        .init(id: "review-1", state: "WAITING_FOR_REVIEW", platform: .iOS, appStoreVersionID: "version-1", itemIDs: ["item-1"]),
    ])
    _ = try await ReleaseAutomation(api: api).submitForReview(
        appLookup: .appID("app-1"), version: "1.2.3", options: .init(mode: .apply)
    )
    #expect(await api.createdReviewSubmissionIDs.isEmpty)
    #expect(await api.submittedReviewSubmissionIDs.isEmpty)
}

@Test(arguments: ["missing-linkage", "wrong-version", "empty-linked-id", "wrong-build"])
func attachedBuildRequiresExplicitLinkageToTheReturnedResource(scenario: String) async throws {
    let transport = StubTransport { _, _, index in
        if index > 0 {
            return try jsonResponse(["data": ["id": "other", "type": "builds"], "links": ["self": "unused"]])
        }
        let build: [String: Any] = scenario == "missing-linkage" ? ["links": ["related": "unused"]] :
            ["data": ["type": "builds", "id": scenario == "empty-linked-id" ? "" : "build"]]
        return try jsonResponse([
            "data": ["id": scenario == "wrong-version" ? "other" : "version-1", "type": "appStoreVersions",
                     "relationships": ["build": build]],
            "links": ["self": "unused"],
        ])
    }
    await #expect(throws: ApogeeError.self) {
        _ = try await testAPI(transport: transport).build(versionID: "version-1")
    }
    #expect(await transport.requests.count == (scenario == "wrong-build" ? 2 : 1))
}
