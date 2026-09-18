@testable import ApogeeCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Test(arguments: [0, 10])
func screenshotsRegisterAndReplaceFullSetsWithVerifiedRecovery(oldCount: Int) async throws {
    let fixture = try ScreenshotFixture(oldCount: oldCount, desiredCount: 10)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    #expect(!FileManager.default.fileExists(atPath: fixture.recovery.path))
    #expect(await api.writes.isEmpty)
    #expect(plan.hasChanges)
    let applied = try await fixture.run(api: api, mode: .apply, token: plan.token)
    #expect(applied.actions.last?.kind == .verify)
    #expect(await api.maximumCount <= 10)
    #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
    if oldCount > 0 {
        let restored = try ScreenshotFiles.load(fixture.recovery.appendingPathComponent("restore").path, platform: .macOS)
        #expect(restored[0].2.map(\.checksum) == fixture.remote.compactMap(\.checksum))
        let journal = try String(contentsOf: fixture.recovery.appendingPathComponent("state.json"), encoding: .utf8)
        #expect(!journal.contains("Expires="))
    }
}

@Test
func screenshotsRequireOriginalsAndMatchingDestructiveTokenBeforeWrites() async throws {
    let fixture = try ScreenshotFixture(oldCount: 2, desiredCount: 2)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    await #expect(throws: ApogeeError.applyRequiresPlanToken) {
        _ = try await fixture.run(api: api, mode: .apply, token: "stale")
    }
    // Without originals this set can only be replaced by uploading first, which needs its own opt-in.
    let plan = try await fixture.run(api: api, mode: .dryRun, includeOriginals: false)
    await #expect(throws: ScreenshotError.unrecoverableReplacementRequiresConfirmation) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token, includeOriginals: false)
    }
    #expect(await api.writes.isEmpty)
}

/// A legacy set whose originals are gone can still be replaced when both fit at once.
@Test
func screenshotsReplaceUnrecoverableSetsByUploadingBeforeDeleting() async throws {
    let fixture = try ScreenshotFixture(oldCount: 3, desiredCount: 3)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    let plan = try await fixture.run(api: api, mode: .dryRun, includeOriginals: false)
    let strategy = try #require(plan.actions.first { $0.field == "replacement" })
    #expect(strategy.currentValue?.contains("3 existing screenshot(s) without verified originals") == true)
    #expect(strategy.desiredValue?.contains("upload-first replacement") == true)
    #expect(strategy.desiredValue?.contains("6 of 10 slots") == true)
    #expect(await api.writes.isEmpty)
    let applied = try await fixture.run(api: api, mode: .apply, token: plan.token,
                                        includeOriginals: false, allowUnrecoverable: true)
    #expect(applied.actions.last?.kind == .verify)
    let writes = await api.writes
    let lastCommit = try #require(writes.lastIndex(of: "commit"))
    let firstDelete = try #require(writes.firstIndex(of: "delete"))
    #expect(lastCommit < firstDelete)
    #expect(await api.maximumCount == 6)
    #expect(try await fixture.run(api: api, mode: .dryRun, includeOriginals: false).hasChanges == false)
    // No restore tree is written, because the previous composition was never recoverable.
    #expect(!FileManager.default.fileExists(atPath: fixture.recovery.appendingPathComponent("restore").path))
    let journal = try String(contentsOf: fixture.recovery.appendingPathComponent("state.json"), encoding: .utf8)
    #expect(journal.contains("unrecoverableSets"))
}

/// A failed upload-first replacement must keep every existing complete screenshot.
@Test
func screenshotsKeepExistingImagesWhenUploadFirstReplacementFails() async throws {
    let fixture = try ScreenshotFixture(oldCount: 3, desiredCount: 3)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    await api.setFailure("upload")
    let plan = try await fixture.run(api: api, mode: .dryRun, includeOriginals: false)
    await #expect(throws: ScreenshotError.unsafeUpload) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token,
                                  includeOriginals: false, allowUnrecoverable: true)
    }
    #expect(await !api.writes.contains("delete"))
    #expect(await api.items.filter { $0.state == "COMPLETE" } == fixture.remote)
    await api.setFailure("")
    let fresh = try await fixture.run(api: api, mode: .dryRun, includeOriginals: false)
    _ = try await fixture.run(api: api, mode: .apply, token: fresh.token,
                              includeOriginals: false, allowUnrecoverable: true)
    #expect(try await fixture.run(api: api, mode: .dryRun, includeOriginals: false).hasChanges == false)
}

/// Capacity that forces deletion before upload keeps the verified-originals requirement.
@Test
func screenshotsRequireOriginalsWhenCapacityForcesDeletionFirst() async throws {
    let fixture = try ScreenshotFixture(oldCount: 10, desiredCount: 10)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    let plan = try await fixture.run(api: api, mode: .dryRun, includeOriginals: false)
    let strategy = try #require(plan.actions.first { $0.field == "replacement" })
    #expect(strategy.desiredValue?.contains("no upload-first replacement") == true)
    await #expect(throws: ScreenshotError.originalsMissing) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token,
                                  includeOriginals: false, allowUnrecoverable: true)
    }
    #expect(await api.writes.isEmpty)
}

@Test(arguments: ["upload", "processing", "checksum", "cancelled", "timeout", "reservation-response"])
func screenshotsResumeOnlyOwnedInterruptedUploads(scenario: String) async throws {
    let fixture = try ScreenshotFixture(oldCount: 2, desiredCount: 2)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: fixture.remote)
    await api.setFailure(scenario)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    do {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
        Issue.record("A failed upload must not return success.")
    } catch {
        if scenario == "cancelled" {
            #expect(error is CancellationError)
        }
    }
    let original = try ScreenshotFiles.load(fixture.recovery.appendingPathComponent("restore").path, platform: .macOS)
    #expect(original[0].2.map(\.checksum) == fixture.remote.compactMap(\.checksum))
    await api.setFailure("")
    // A checksum mismatch in COMPLETE is not an unfinished upload, so removing it needs its own opt-in.
    if scenario == "checksum" {
        await #expect(throws: ScreenshotError.unrecoverableReplacementRequiresConfirmation) {
            let fresh = try await fixture.run(api: api, mode: .dryRun)
            _ = try await fixture.run(api: api, mode: .apply, token: fresh.token)
        }
    } else if scenario == "reservation-response" {
        let writes = await api.writes
        await #expect(throws: ScreenshotError.incompleteInventory) {
            _ = try await fixture.run(api: api, mode: .dryRun)
        }
        #expect(await api.writes == writes)
    } else {
        let fresh = try await fixture.run(api: api, mode: .dryRun)
        _ = try await fixture.run(api: api, mode: .apply, token: fresh.token)
        #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
    }
}

@Test
func screenshotsRefuseUnownedUploadsAndConcurrentRemoteChanges() async throws {
    let fixture = try ScreenshotFixture(oldCount: 1, desiredCount: 1)
    defer { fixture.remove() }
    var unfinished = fixture.remote[0]
    unfinished.state = "AWAITING_UPLOAD"
    unfinished.checksum = nil
    let unowned = ScreenshotTestAPI(items: [unfinished])
    await #expect(throws: ScreenshotError.incompleteInventory) {
        _ = try await fixture.run(api: unowned, mode: .dryRun)
    }
    #expect(await unowned.writes.isEmpty)
    let api = ScreenshotTestAPI(items: fixture.remote)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    await api.changeOnSecondRead()
    await #expect(throws: ScreenshotError.remoteChanged) {
        _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
    }
    #expect(await api.writes.isEmpty)
}

@Test
func screenshotOrderingChangesTokenAndReusesExistingBytes() async throws {
    let fixture = try ScreenshotFixture(oldCount: 2, desiredCount: 2)
    defer { fixture.remove() }
    let old = try ScreenshotJournal.originals(fixture.originals.path)
    let input = fixture.input.appendingPathComponent("en-US/APP_DESKTOP")
    try old[1].data.write(to: input.appendingPathComponent("01.png"))
    try old[0].data.write(to: input.appendingPathComponent("02.png"))
    let api = ScreenshotTestAPI(items: fixture.remote)
    let plan = try await fixture.run(api: api, mode: .dryRun)
    #expect(plan.actions.filter { $0.kind == .create || $0.kind == .delete }.isEmpty)
    _ = try await fixture.run(api: api, mode: .apply, token: plan.token)
    #expect(await api.writes == ["order"])
    #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
}

@Test(arguments: ["expired", "duplicate-expiry", "unreadable-expiry", "gap", "overlap", "host", "redirect-host",
                 "credentials", "header", "method"])
func screenshotUploadInstructionsFailClosed(scenario: String) throws {
    var operations = [ScreenshotTestAPI.operation(id: "one", byteCount: 10)]
    switch scenario {
    case "expired": operations[0].url = "https://store.blobstore.apple.com/one?Expires=1"
    case "duplicate-expiry": operations[0].url = "https://store.blobstore.apple.com/one?Expires=9999999999&Expires=1"
    case "unreadable-expiry": operations[0].url = "https://store.blobstore.apple.com/one?Expires="
    case "gap": operations[0].offset = 1
    case "overlap": operations.append(operations[0])
    case "host": operations[0].url = "https://example.invalid/one?Expires=9999999999"
    case "redirect-host": operations[0].url = "https://apple.com.example.invalid/one?Expires=9999999999"
    case "credentials": operations[0].url = "https://user:pass@store.blobstore.apple.com/one?Expires=9999999999"
    case "header": operations[0].headers["Authorization"] = "Bearer sentinel"
    default: operations[0].method = "POST"
    }
    #expect(throws: ScreenshotError.unsafeUpload) {
        try ScreenshotUploadValidation.validate(operations, byteCount: 10)
    }
}

/// Apple's current asset responses can omit `Expires`; the remaining safeguards still apply.
@Test
func screenshotUploadAcceptsAppleURLsWithoutAnExpiryParameter() throws {
    var operation = ScreenshotTestAPI.operation(id: "one", byteCount: 10)
    operation.url = "https://store.blobstore.apple.com/one"
    try ScreenshotUploadValidation.validate([operation], byteCount: 10)
    operation.url = "https://store.blobstore.apple.com/one?uploadId=abc&partNumber=1"
    try ScreenshotUploadValidation.validate([operation], byteCount: 10)
    operation.url = "https://store.blobstore.example.invalid/one"
    #expect(throws: ScreenshotError.unsafeUpload) {
        try ScreenshotUploadValidation.validate([operation], byteCount: 10)
    }
}

/// `COMPLETE` can precede a readable source checksum; that first read is not a mismatch.
@Test
func screenshotsWaitForDelayedChecksumReadBack() async throws {
    let fixture = try ScreenshotFixture(oldCount: 0, desiredCount: 1)
    defer { fixture.remove() }
    let api = ScreenshotTestAPI(items: [])
    await api.setFailure("delayed-checksum")
    let plan = try await fixture.run(api: api, mode: .dryRun)
    let applied = try await fixture.run(api: api, mode: .apply, token: plan.token)
    #expect(applied.actions.last?.kind == .verify)
    #expect(await api.checksumReadsBeforeMatch == 1)
    #expect(try await fixture.run(api: api, mode: .dryRun).hasChanges == false)
}

@Test
func screenshotRecoveryRejectsCorruptionSymlinksAndConcurrentWriters() throws {
    let fixture = try ScreenshotFixture(oldCount: 1, desiredCount: 1)
    defer { fixture.remove() }
    let recovery = ScreenshotRecovery(directory: fixture.recovery.path)
    let journal = try ScreenshotJournal(recovery: recovery, target: "target", applying: true)
    #expect(throws: ScreenshotError.recoveryMismatch) {
        _ = try ScreenshotJournal(recovery: recovery, target: "target", applying: true)
    }
    let originals = try ScreenshotJournal.originals(fixture.originals.path)
    try journal.backup(fixture.remote, setID: "set", candidates: originals)
    let external = fixture.root.appendingPathComponent("external")
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: fixture.recovery.appendingPathComponent("restore"), withDestinationURL: external)
    #expect(throws: ScreenshotError.invalidInput) {
        try journal.writeRestoreLayout(setID: "set", locale: "en-US", displayType: "APP_DESKTOP")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    let original = try #require(journal.state.originals[fixture.remote[0].id])
    try Data([0]).write(to: fixture.recovery.appendingPathComponent(original.blob))
    #expect(throws: ScreenshotError.recoveryMismatch) {
        _ = try journal.originalData(fixture.remote[0])
    }
}

private struct ScreenshotFixture {
    let root: URL
    let input: URL
    let originals: URL
    let recovery: URL
    let remote: [RemoteScreenshot]

    init(oldCount: Int, desiredCount: Int) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        input = root.appendingPathComponent("input")
        originals = root.appendingPathComponent("originals")
        recovery = root.appendingPathComponent("recovery")
        let display = input.appendingPathComponent("en-US/APP_DESKTOP")
        try FileManager.default.createDirectory(at: display, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        var resources: [RemoteScreenshot] = []
        for index in 0..<oldCount {
            let path = originals.appendingPathComponent(String(format: "%02d.png", index + 1))
            try screenshotPNG(seed: UInt8(index + 1)).write(to: path)
            let image = try ScreenshotImage(url: path)
            resources.append(.init(id: "old-\(index)", fileName: path.lastPathComponent, byteCount: image.data.count, checksum: image.checksum, state: "COMPLETE"))
        }
        for index in 0..<desiredCount {
            try screenshotPNG(seed: UInt8(index + 50)).write(to: display.appendingPathComponent(String(format: "%02d.png", index + 1)))
        }
        remote = resources
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func run(api: ScreenshotTestAPI, mode: OperationMode, token: String? = nil, includeOriginals: Bool = true,
             allowUnrecoverable: Bool = false) async throws -> ReleasePlan {
        try await ScreenshotWorkflow(api: api, pollAttempts: 2, pollDelay: .zero).run(
            app: .init(id: "app"), version: .init(id: "version"), platform: .macOS,
            localizations: [.init(id: "localization", locale: "en-US", metadata: .init(locale: "en-US"))],
            path: input.path,
            options: .init(mode: mode, allowDestructive: true, planToken: token,
                           allowUnrecoverableReplacement: allowUnrecoverable),
            recovery: .init(directory: recovery.path, originalsPath: includeOriginals ? originals.path : nil)
        )
    }
}

private func screenshotPNG(seed: UInt8) throws -> Data {
    let pixels = Data(repeating: seed, count: 12)
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 6,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [], provider: provider,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let result = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return result as Data
}

private actor ScreenshotTestAPI: ScreenshotAPI {
    var items: [RemoteScreenshot]
    var exists: Bool
    var writes: [String] = []
    var maximumCount: Int
    var failure = ""
    var counter = 0
    var reads = 0
    var mutateOnRead: Int?
    var uploaded: [String: Data] = [:]
    var deferredChecksums: [String: String] = [:]
    var checksumReadsBeforeMatch = 0

    init(items: [RemoteScreenshot]) {
        self.items = items
        exists = !items.isEmpty
        maximumCount = items.count
    }
    func setFailure(_ failure: String) {
        self.failure = failure
    }
    func changeOnSecondRead() {
        reads = 0
        mutateOnRead = 2
    }
    func screenshotSets(localizationID: String) async throws -> [RemoteScreenshotSet] {
        exists ? [.init(id: "set", displayType: "APP_DESKTOP")] : []
    }
    func screenshots(setID: String) async throws -> [RemoteScreenshot] {
        reads += 1
        if reads == mutateOnRead {
            items.reverse()
            items[0].fileName = "changed.png"
        }
        return items
    }
    func createScreenshotSet(localizationID: String, displayType: String) async throws -> RemoteScreenshotSet {
        writes.append("create-set")
        exists = true
        return .init(id: "set", displayType: displayType)
    }
    func reserveScreenshot(setID: String, fileName: String, byteCount: Int) async throws -> (RemoteScreenshot, [ScreenshotUploadOperation]) {
        #expect(items.count < 10)
        counter += 1
        let item = RemoteScreenshot(id: "new-\(counter)", fileName: fileName, byteCount: byteCount, checksum: nil, state: "AWAITING_UPLOAD")
        items.append(item)
        maximumCount = max(maximumCount, items.count)
        writes.append("reserve")
        if failure == "reservation-response" {
            throw ScreenshotError.incompleteInventory
        }
        return (item, [Self.operation(id: item.id, byteCount: byteCount)])
    }
    static func operation(id: String, byteCount: Int) -> ScreenshotUploadOperation {
        .init(method: "PUT", url: "https://store.blobstore.apple.com/\(id)?Expires=9999999999", offset: 0, length: byteCount, headers: [:])
    }
    func uploadScreenshotPart(_ data: Data, operation: ScreenshotUploadOperation) async throws {
        if failure == "cancelled" {
            throw CancellationError()
        }
        if failure == "upload" {
            throw ScreenshotError.unsafeUpload
        }
        let id = URL(string: operation.url)!.lastPathComponent
        uploaded[id] = data
        writes.append("upload")
    }
    func commitScreenshot(id: String, checksum: String) async throws {
        let index = try #require(items.firstIndex { $0.id == id })
        #expect(uploaded[id].map(ScreenshotImage.md5) == checksum)
        items[index].state = failure == "processing" ? "FAILED" : (failure == "timeout" ? "UPLOAD_COMPLETE" : "COMPLETE")
        items[index].checksum = failure == "checksum" ? String(repeating: "0", count: 32) : checksum
        if failure == "delayed-checksum" {
            deferredChecksums[id] = checksum
            items[index].checksum = nil
        }
        writes.append("commit")
    }
    func screenshot(id: String) async throws -> RemoteScreenshot {
        let item = try #require(items.first { $0.id == id })
        // Apple can report COMPLETE once before the source checksum becomes readable.
        if let deferred = deferredChecksums.removeValue(forKey: id) {
            checksumReadsBeforeMatch += 1
            let index = try #require(items.firstIndex { $0.id == id })
            items[index].checksum = deferred
        }
        return item
    }
    func deleteScreenshot(id: String) async throws {
        items.removeAll { $0.id == id }
        writes.append("delete")
    }
    func orderScreenshots(setID: String, ids: [String]) async throws {
        let previous = items
        items = try ids.map { id in try #require(previous.first { $0.id == id }) }
        writes.append("order")
    }
}
