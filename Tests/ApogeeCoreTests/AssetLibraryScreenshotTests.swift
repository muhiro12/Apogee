@testable import ApogeeCore
import Foundation
import Synchronization
import Testing

@Test(arguments: [0, 10], ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"])
func assetLibraryReplacesFullSetsAfterProcessingAndPreservesSharedImages(oldCount: Int, readyState: String) async throws {
    let fixture = try LibraryFixture(oldCount: oldCount, desiredCount: 10)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: oldCount, includeUnrelated: true, readyState: readyState)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    #expect(await api.writes.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.recovery.path))
    let applied = try await fixture.run(api: api, mode: .apply, token: plan.token)
    #expect(applied.actions.last?.kind == .verify)
    let writes = await api.writes
    if oldCount > 0 {
        let firstDelete = try #require(writes.firstIndex(of: "delete-placement"))
        let lastCommit = try #require(writes.lastIndex(of: "commit"))
        #expect(lastCommit < firstDelete)
    }
    #expect(await api.placements.filter { $0.group == "runtime-duo-group" }.count == 10)
    #expect(await api.placements.contains { $0.id == "unrelated-placement" })
    #expect(await api.images.count == oldCount + 11)
    #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
    let journal = try String(contentsOf: fixture.recovery.appendingPathComponent("asset-library-state.json"), encoding: .utf8)
    #expect(!journal.contains("blobstore"))
    #expect(!journal.contains("sourceFileChecksum"))
    #expect(journal.contains("originals"))
}

@Test(arguments: ["upload", "commit", "processing", "spec", "size", "timeout"])
func assetLibraryUploadFailuresPreserveEveryExistingPlacement(scenario: String) async throws {
    let fixture = try LibraryFixture(oldCount: 10, desiredCount: 2)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 10)
    await api.setFailure(scenario)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    do {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
        Issue.record("An invalid or incomplete asset must fail before placement deletion.")
    } catch {
        #expect(error is ScreenshotError)
    }
    #expect(await api.placements.count == 10)
    #expect(await !api.writes.contains("delete-placement"))
    #expect(await api.images.keys.contains("old-0"))
}

@Test(arguments: ["order", "create", "delete"])
func assetLibraryResumesPlacementFailuresWithoutDeletingImages(scenario: String) async throws {
    let fixture = try LibraryFixture(oldCount: 2, desiredCount: 2)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 2)
    await api.setFailure(scenario)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    await #expect(throws: ScreenshotError.self) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
    }
    #expect(await api.images.keys.contains("old-0"))
    #expect(await api.images.keys.contains("old-1"))
    await api.setFailure("")
    let fresh = try await fixture.run(api: api, mode: .dryRun)
    _ = try await fixture.run(api: api, mode: .apply, token: fresh.token)
    #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
}

@Test(arguments: [(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)])
func duoDimensionsUseRuntimeSpecifications(dimensions: (Int, Int)) async throws {
    let fixture = try LibraryFixture(oldCount: 0, desiredCount: 1, width: dimensions.0, height: dimensions.1)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 0, width: dimensions.0, height: dimensions.1)
    let applied = try await fixture.run(api: api, mode: .apply)
    #expect(applied.actions.last?.kind == .verify)
    #expect(await api.placements.map(\.group) == ["runtime-duo-group"])
}

@Test
func assetLibraryRejectsDimensionsAndStaleTokensBeforeWrites() async throws {
    let fixture = try LibraryFixture(oldCount: 1, desiredCount: 1)
    defer {
        fixture.remove()
    }
    let wrongSpec = LibraryTestAPI(oldCount: 1, width: 99, height: 99)
    await #expect(throws: ScreenshotError.invalidInput) {
        _ = try await fixture.run(api: wrongSpec, mode: .apply)
    }
    #expect(await wrongSpec.writes.isEmpty)
    let api = LibraryTestAPI(oldCount: 1)
    await #expect(throws: ApogeeError.applyRequiresPlanToken) {
        _ = try await fixture.run(api: api, mode: .apply, token: "stale")
    }
    #expect(await api.writes.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.recovery.path))
}

@Test(arguments: ["legacy", "target", "permissions", "symlink", "locked"])
func assetLibraryRejectsUnsafeOrIncompatibleRecoveryBeforeWrites(scenario: String) async throws {
    let fixture = try LibraryFixture(oldCount: 1, desiredCount: 1)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 1)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    let target = scenario == "symlink" ? fixture.root.appendingPathComponent("external") : fixture.recovery
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: scenario == "permissions" ? 0o755 : 0o700])
    var lock: AssetLibraryJournal?
    switch scenario {
    case "legacy":
        try Data("{}".utf8).write(to: target.appendingPathComponent("state.json"))
    case "target":
        try JSONEncoder().encode(LibraryJournalState(target: "another-app"))
            .write(to: target.appendingPathComponent("asset-library-state.json"))
    case "symlink":
        try FileManager.default.createSymbolicLink(at: fixture.recovery, withDestinationURL: target)
    case "locked":
        lock = try AssetLibraryJournal(recovery: .init(directory: target.path), target: "app/version/IOS/library", applying: true)
    default:
        break
    }
    await #expect(throws: ScreenshotError.self) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
    }
    #expect(await api.writes.isEmpty)
    if let lock {
        #expect(lock.state.target == "app/version/IOS/library")
    }
}

@Test(arguments: ["wrong-order", "placement-timeout"])
func assetLibraryFinalFailuresNeverReportCompletion(scenario: String) async throws {
    let fixture = try LibraryFixture(oldCount: 1, desiredCount: 2)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 1)
    await api.setFailure(scenario)
    let events = Mutex<[ScreenshotProgress]>([])
    let plan = try await fixture.run(api: api, mode: .dryRun)
    await #expect(throws: ScreenshotError.self) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token) { event in
            events.withLock { $0.append(event) }
        }
    }
    #expect(!events.withLock { $0.contains { $0.stage == .completed } })
    #expect(events.withLock { $0.last?.stage } == .verifying)
    #expect(await api.images.keys.contains("old-0"))
}

private struct LibraryFixture {
    let root: URL
    let input: URL
    let recovery: URL

    init(oldCount: Int, desiredCount: Int, width: Int = 2, height: Int = 2) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        input = root.appendingPathComponent("input")
        recovery = root.appendingPathComponent("recovery")
        let display = input.appendingPathComponent("en-US/IPHONE_DUO")
        try FileManager.default.createDirectory(at: display, withIntermediateDirectories: true)
        for index in 0..<desiredCount {
            try screenshotPNG(seed: UInt8(index + 1), width: width, height: height)
                .write(to: display.appendingPathComponent(String(format: "%02d.png", index)))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func run(api: LibraryTestAPI, mode: OperationMode, token: String? = nil,
             progress: (@Sendable (ScreenshotProgress) -> Void)? = nil) async throws -> ReleasePlan {
        try await AssetLibraryScreenshotWorkflow(api: api, progress: progress, pollAttempts: 2, pollDelay: .zero).run(
            app: .init(id: "app"), version: .init(id: "version"), platform: .iOS,
            localizations: [.init(id: "localization", locale: "en-US", metadata: .init(locale: "en-US"))],
            path: input.path, options: .init(mode: mode, allowDestructive: true, planToken: token),
            recovery: .init(directory: recovery.path)
        )
    }
}

private actor LibraryTestAPI: AssetLibraryAPI {
    var images: [String: LibraryImage] = [:]
    var placements: [LibraryPlacement] = []
    var writes: [String] = []
    var failure = ""
    let width: Int
    let height: Int
    var counter = 0
    let readyState: String
    var placementPolls = 0

    init(oldCount: Int, width: Int = 2, height: Int = 2, includeUnrelated: Bool = false, readyState: String = "ACTIVE") {
        self.width = width
        self.height = height
        self.readyState = readyState
        for index in 0..<oldCount {
            let id = "old-\(index)"
            images[id] = .init(id: id, fileName: "old.png", byteCount: 123, referenceName: nil, specID: "runtime-spec", state: "COMPLETE")
            placements.append(.init(id: "placement-\(index)", imageID: id, localizationID: "localization",
                                    placementType: "APP_SCREENSHOT", group: "runtime-duo-group", state: readyState))
        }
        if includeUnrelated {
            images["shared"] = .init(id: "shared", fileName: "shared.png", byteCount: 123, referenceName: nil, specID: "runtime-spec", state: "APPROVED")
            placements.append(.init(id: "unrelated-placement", imageID: "shared", localizationID: "localization",
                                    placementType: "APP_SCREENSHOT", group: "unrelated-group", state: "PARENT_APPROVED"))
        }
    }
    func setFailure(_ value: String) {
        failure = value
    }
    func libraryID(appID: String) async throws -> String {
        "library"
    }
    func libraryReferenceData() async throws -> LibraryReferenceData {
        .init(placementProfileGroups: [.init(placementProfileGroupId: "runtime-duo-group", platform: "IPHONE_APP_STORE", displayClassId: "IPHONE_DUO")],
              imageSpecs: [.init(specId: "runtime-spec", dimensions: .init(minWidth: width, maxWidth: width, minHeight: height, maxHeight: height),
                                 compatiblePlacementTypes: ["APP_SCREENSHOT"], fileExtensions: ["png"], maxFileSize: 64 * 1_024 * 1_024, mimeTypes: ["image/png"])],
              placementTypes: [.init(placementTypeId: "APP_SCREENSHOT", acceptsAssetCategories: ["APP_SCREENSHOTS_AND_PREVIEWS"], specMappings: [.init(placementGroupId: "runtime-duo-group", specs: ["runtime-spec"])])],
              features: [.init(featureId: "APP_STORE_VERSIONS", placementPolicies: [.init(placementType: "APP_SCREENSHOT", groupLimits: [.init(groupIds: ["runtime-duo-group"], maxCount: 10)])])])
    }
    func libraryPlacements(localizationID: String, group: String) async throws -> [LibraryPlacement] {
        if failure == "placement-processing", writes.contains("order") {
            placementPolls += 1
            if placementPolls > 1 {
                for index in placements.indices where placements[index].state == "ASSET_PROCESSING" {
                    placements[index].state = readyState
                }
            }
        }
        return placements.filter { $0.localizationID == localizationID && $0.group == group }
    }
    func libraryImage(id: String) async throws -> LibraryImage {
        try #require(images[id])
    }
    func reserveLibraryImage(libraryID: String, image: ScreenshotImage, reference: String) async throws -> (LibraryImage, [ScreenshotUploadOperation]) {
        counter += 1
        let item = LibraryImage(id: "new-\(counter)", fileName: image.fileName, byteCount: image.data.count,
                                referenceName: reference, specID: nil, state: "AWAITING_UPLOAD")
        images[item.id] = item
        writes.append("reserve")
        return (item, [.init(method: "PUT", url: "https://store.blobstore.apple.com/asset", offset: 0, length: image.data.count, headers: [:])])
    }
    func uploadScreenshotPart(_ data: Data, operation: ScreenshotUploadOperation) async throws {
        if failure == "upload" {
            throw ScreenshotError.unsafeUpload
        }
        #expect(data.count == operation.length)
        writes.append("upload")
    }
    func commitLibraryImage(id: String) async throws {
        if failure == "commit" {
            throw ScreenshotError.processingFailed
        }
        images[id]?.state = failure == "processing" ? "FAILED" : (failure == "timeout" ? "UPLOAD_COMPLETE" : "COMPLETE")
        images[id]?.specID = failure == "spec" ? "wrong-spec" : "runtime-spec"
        if failure == "size" {
            images[id]?.byteCount += 1
        }
        writes.append("commit")
    }
    func createLibraryPlacement(imageID: String, localizationID: String, group: String) async throws -> LibraryPlacement {
        if failure == "create" {
            throw ScreenshotError.remoteChanged
        }
        #expect(placements.filter { $0.group == group && $0.localizationID == localizationID }.count < 10)
        let state: String
        switch failure {
        case "placement-processing", "placement-timeout":
            state = "ASSET_PROCESSING"
        case "placement-failed":
            state = "FAILED"
        case "placement-unknown":
            state = "FUTURE_STATE"
        default:
            state = readyState
        }
        let placement = LibraryPlacement(id: "placement-\(imageID)", imageID: imageID, localizationID: localizationID,
                                         placementType: "APP_SCREENSHOT", group: group,
                                         state: state)
        placements.append(placement)
        writes.append("create-placement")
        return placement
    }
    func deleteLibraryPlacement(id: String) async throws {
        if failure == "delete" {
            throw ScreenshotError.remoteChanged
        }
        placements.removeAll { $0.id == id }
        writes.append("delete-placement")
    }
    func orderLibraryPlacements(localizationID: String, group: String, ids: [String]) async throws {
        if failure == "order" {
            throw ScreenshotError.remoteChanged
        }
        let selected = try ids.map { id in
            try #require(placements.first { $0.id == id })
        }
        let unrelated = placements.filter { $0.group != group || $0.localizationID != localizationID }
        placements = (failure == "wrong-order" ? Array(selected.reversed()) : selected) + unrelated
        if failure == "poll-failed" || failure == "poll-unknown" {
            for index in placements.indices where placements[index].localizationID == localizationID && placements[index].group == group {
                placements[index].state = failure == "poll-failed" ? "FAILED" : "FUTURE_STATE"
            }
        }
        writes.append("order")
    }
}

@Test
func assetLibraryPartitionsMultipleDisplayProfilesAndRejectsAmbiguity() async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    var images: [ScreenshotImage] = []
    for size in [2, 3] {
        let file = directory.appendingPathComponent("\(size).png")
        try screenshotPNG(seed: UInt8(size), width: size, height: size).write(to: file)
        images.append(try ScreenshotImage(url: file))
    }
    var reference = try await LibraryTestAPI(oldCount: 0).libraryReferenceData()
    reference.placementProfileGroups.append(.init(placementProfileGroupId: "second-group", platform: "IPHONE_APP_STORE", displayClassId: "IPHONE_DUO"))
    reference.imageSpecs.append(.init(specId: "second-spec", dimensions: .init(minWidth: 3, maxWidth: 3, minHeight: 3, maxHeight: 3),
                                     compatiblePlacementTypes: ["APP_SCREENSHOT"], fileExtensions: ["png"], maxFileSize: 100000, mimeTypes: ["image/png"]))
    reference.placementTypes[0].specMappings.append(.init(placementGroupId: "second-group", specs: ["second-spec"]))
    reference.features[0].placementPolicies[0].groupLimits.append(.init(groupIds: ["second-group"], maxCount: 10))
    let targets = try reference.targets(displayClass: "IPHONE_DUO", platform: .iOS, images: images)
    #expect(targets.map(\.group) == ["runtime-duo-group", "second-group"])
    #expect(targets.map { $0.images.map(\.width) } == [[2], [3]])
    reference.placementTypes[0].specMappings[1].specs = ["runtime-spec"]
    #expect(throws: ScreenshotError.unsupportedDisplayType) {
        _ = try reference.targets(displayClass: "IPHONE_DUO", platform: .iOS, images: images)
    }
}

@Test
func assetLibraryDoesNotCommitAnAssetFromAnInconsistentRecoveryRecord() async throws {
    let fixture = try LibraryFixture(oldCount: 1, desiredCount: 1)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 1)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    let image = try #require(ScreenshotFiles.load(fixture.input.path, platform: .iOS, assetLibrary: true).first?.2.first)
    var state = LibraryJournalState(target: "app/version/IOS/library")
    state.uploads[image.digest] = .init(image: try await api.libraryImage(id: "old-0"), digest: image.digest, committed: true)
    try FileManager.default.createDirectory(at: fixture.recovery, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(state).write(to: fixture.recovery.appendingPathComponent("asset-library-state.json"))
    await #expect(throws: ScreenshotError.recoveryMismatch) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
    }
    #expect(await api.writes.isEmpty)
}

@Test(arguments: ["placement-processing", "placement-timeout", "placement-failed", "placement-unknown", "poll-failed", "poll-unknown"])
func assetLibraryNewPlacementsWaitForReadinessAndRejectFailures(scenario: String) async throws {
    let fixture = try LibraryFixture(oldCount: 0, desiredCount: 1)
    defer {
        fixture.remove()
    }
    let api = LibraryTestAPI(oldCount: 0)
    await api.setFailure(scenario)
    let events = Mutex<[ScreenshotProgress]>([])
    do {
        let plan = try await fixture.run(api: api, mode: .apply) { event in
            events.withLock { $0.append(event) }
        }
        #expect(scenario == "placement-processing")
        #expect(plan.actions.last?.kind == .verify)
        #expect(await api.placementPolls == 2)
        #expect(await api.placements.allSatisfy(\.isReady))
    } catch {
        #expect(scenario != "placement-processing")
        if scenario == "placement-timeout" {
            #expect(error as? ScreenshotError == .processingTimedOut)
        } else {
            #expect(String(describing: error).contains(scenario.hasSuffix("failed") ? "FAILED" : "FUTURE_STATE"))
        }
    }
    #expect(events.withLock { $0.contains { $0.stage == .completed } } == (scenario == "placement-processing"))
    #expect(await api.writes.contains("create-placement"))
    #expect(await !api.writes.contains("delete-placement"))
}
