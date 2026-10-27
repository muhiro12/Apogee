import Foundation

struct AssetLibraryScreenshotWorkflow {
    struct Group {
        var locale: String
        var displayClass: String
        var localizationID: String
        var group: String
        var images: [ScreenshotImage]
        var specs: [[String]]
        var placements: [LibraryPlacement]
        var remote: [LibraryImage]

        var key: String { "\(localizationID)/\(group)" }
    }

    let api: any AssetLibraryAPI
    var validateVersion: @Sendable () async throws -> Void = {}
    var progress: (@Sendable (ScreenshotProgress) -> Void)?
    var pollAttempts = 30
    var pollDelay: Duration = .seconds(2)

    func run(app: AppStoreConnectApp, version: AppStoreConnectVersion, platform: Platform,
             localizations: [AppStoreConnectLocalization], path: String,
             options: ReleaseExecutionOptions, recovery: ScreenshotRecovery?) async throws -> ReleasePlan {
        let started = ContinuousClock.now
        let local = try ScreenshotFiles.load(path, platform: platform, assetLibrary: true)
        let reference = try await api.libraryReferenceData()
        let total = local.reduce(0) { $0 + $1.2.count }
        var completed = 0
        func report(_ stage: ScreenshotProgress.Stage, _ group: Group, attempt: Int? = nil) {
            guard let progress else {
                return
            }
            let elapsed = started.duration(to: .now).components
            progress(.init(stage: stage, locale: group.locale, displayType: group.displayClass,
                           completedImages: completed, totalImages: total,
                           elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                           processingAttempt: attempt, processingLimit: attempt == nil ? nil : pollAttempts))
        }
        guard Set(localizations.map(\.locale)).count == localizations.count,
              Set(localizations.map(\.id)).count == localizations.count else {
            throw ScreenshotError.incompleteInventory
        }
        var groups: [Group] = []
        var actions: [PlannedAction] = []
        for (locale, displayClass, images) in local {
            guard let localization = localizations.first(where: { $0.locale == locale }), !localization.id.isEmpty else {
                throw ApogeeError.localizationMissing(locale: locale)
            }
            for (target, selectedImages, specs) in try reference.targets(displayClass: displayClass, platform: platform, images: images) {
                let placements = try await api.libraryPlacements(localizationID: localization.id, group: target)
                try validate(placements, localizationID: localization.id, group: target)
                var remote: [LibraryImage] = []
                for placement in placements {
                    let image = try await api.libraryImage(id: placement.imageID)
                    guard image.id == placement.imageID, image.isProcessed else {
                        throw ScreenshotError.incompleteInventory
                    }
                    remote.append(image)
                }
                let group = Group(locale: locale, displayClass: displayClass, localizationID: localization.id,
                                  group: target, images: selectedImages, specs: specs, placements: placements, remote: remote)
                guard !groups.contains(where: { $0.key == group.key }) else {
                    throw ScreenshotError.invalidInput
                }
                groups.append(group)
                report(.planning, group)
                var desired: [String] = []
                var retained: Set<String> = []
                for (index, image) in selectedImages.enumerated() {
                    let matchingPlacements = zip(placements, remote).filter {
                        matches($0.1, image: image, specs: specs[index])
                    }
                    guard matchingPlacements.count <= 1 else {
                        throw ScreenshotError.incompleteInventory
                    }
                    if let match = matchingPlacements.first {
                        desired.append(match.0.id)
                        retained.insert(match.0.id)
                    } else {
                        desired.append("new:\(image.digest)")
                        actions.append(.init(kind: .create, resource: "placements/\(group.key)", locale: locale,
                                             desiredValue: "\(image.fileName) \(image.data.count) bytes local SHA256=\(image.digest) specs=\(specs[index].joined(separator: ","))"))
                    }
                }
                for placement in placements where !retained.contains(placement.id) {
                    actions.append(.init(kind: .delete, resource: "appAssetLibraryPlacement/\(placement.id)", locale: locale,
                                         currentValue: "image=\(placement.imageID)", isDestructive: true))
                }
                let unchanged = desired == placements.map(\.id)
                actions.append(.init(kind: unchanged ? .unchanged : .update, resource: "placements/\(group.key)", locale: locale,
                                     field: "order", currentValue: try encoded(placements),
                                     desiredValue: try encoded(desired), isDestructive: !unchanged && !placements.isEmpty))
            }
        }
        var plan = ReleasePlan(title: "Update asset-library screenshots for \(app.id)/\(version.id)/\(platform.rawValue)", actions: actions)
            .targeting(app: app, version: version)
        guard options.mode == .apply, plan.hasChanges else {
            return plan
        }
        if plan.hasDestructiveActions {
            guard options.allowDestructive else {
                throw ApogeeError.destructiveApplyRequiresConfirmation
            }
            guard options.planToken == plan.token else {
                throw ApogeeError.applyRequiresPlanToken
            }
        }
        guard let recovery else {
            throw ScreenshotError.recoveryRequired
        }
        let inputPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let recoveryPath = URL(fileURLWithPath: recovery.directory).standardizedFileURL.path
        guard recoveryPath != inputPath, !recoveryPath.hasPrefix(inputPath + "/") else {
            throw ScreenshotError.recoveryMismatch
        }
        let libraryID = try await api.libraryID(appID: app.id)
        let journal = try AssetLibraryJournal(recovery: recovery,
                                             target: "\(app.id)/\(version.id)/\(platform.rawValue)/\(libraryID)", applying: true)
        try await validateVersion()
        for group in groups {
            guard try await api.libraryPlacements(localizationID: group.localizationID, group: group.group) == group.placements else {
                throw ScreenshotError.remoteChanged
            }
            report(.preparingRecovery, group)
            if journal.state.originals[group.key] == nil {
                journal.state.originals[group.key] = group.placements
            }
        }
        try journal.persist()

        // Verify every replacement across every selected group before removing any placement.
        var desiredImages: [String: [LibraryImage]] = [:]
        var uploaded: [String: LibraryImage] = [:]
        for group in groups {
            var images: [LibraryImage] = []
            for (index, image) in group.images.enumerated() {
                let allowed = group.specs[index]
                let existing = group.remote.first { matches($0, image: image, specs: allowed) }
                    ?? uploaded[image.digest]
                let verified: LibraryImage
                if let existing {
                    verified = try await verifiedImage(id: existing.id, image: image, specs: allowed)
                } else {
                    var reserved: LibraryImage
                    if let owned = journal.state.uploads[image.digest], owned.committed {
                        reserved = try await api.libraryImage(id: owned.image.id)
                        guard owned.digest == image.digest, reserved.id == owned.image.id,
                              reserved.byteCount == image.data.count,
                              reserved.referenceName == Self.reference(image) else {
                            throw ScreenshotError.recoveryMismatch
                        }
                        if reserved.state == "AWAITING_UPLOAD" {
                            report(.committing, group)
                            try await api.commitLibraryImage(id: reserved.id)
                        }
                    } else {
                        report(.uploading, group)
                        let (item, operations) = try await api.reserveLibraryImage(
                            libraryID: libraryID, image: image, reference: Self.reference(image)
                        )
                        guard !item.id.isEmpty, item.state == "AWAITING_UPLOAD",
                              item.byteCount == image.data.count, item.fileName == image.fileName,
                              item.referenceName == Self.reference(image) else {
                            throw ScreenshotError.incompleteInventory
                        }
                        reserved = item
                        journal.state.uploads[image.digest] = .init(image: item, digest: image.digest, committed: false)
                        try journal.persist()
                        try ScreenshotUploadValidation.validate(operations, byteCount: image.data.count)
                        for operation in operations {
                            try Task.checkCancellation()
                            try await api.uploadScreenshotPart(image.data.subdata(in: operation.offset..<(operation.offset + operation.length)), operation: operation)
                        }
                        journal.state.uploads[image.digest]?.committed = true
                        try journal.persist()
                        report(.committing, group)
                        try await api.commitLibraryImage(id: reserved.id)
                    }
                    var processed: LibraryImage?
                    for attempt in 1...pollAttempts {
                        try Task.checkCancellation()
                        report(.processing, group, attempt: attempt)
                        let observed = try await api.libraryImage(id: reserved.id)
                        guard observed.id == reserved.id, observed.byteCount == image.data.count,
                              observed.referenceName == Self.reference(image) else {
                            throw ScreenshotError.processingFailed
                        }
                        if observed.isProcessed {
                            guard matches(observed, image: image, specs: allowed) else {
                                throw ScreenshotError.processingFailed
                            }
                            processed = observed
                            break
                        }
                        guard ["AWAITING_UPLOAD", "UPLOAD_COMPLETE"].contains(observed.state) else {
                            throw ScreenshotError.processingFailed
                        }
                        if attempt < pollAttempts {
                            try await Task.sleep(for: pollDelay)
                        }
                    }
                    guard let processed else {
                        throw ScreenshotError.processingTimedOut
                    }
                    verified = processed
                    journal.state.uploads[image.digest]?.image = processed
                    try journal.persist()
                }
                uploaded[image.digest] = verified
                images.append(verified)
                completed += 1
            }
            desiredImages[group.key] = images
            report(.verifyingReplacements, group)
        }
        for group in groups {
            try await validateVersion()
            guard try await api.libraryPlacements(localizationID: group.localizationID, group: group.group) == group.placements,
                  let desired = desiredImages[group.key] else {
                throw ScreenshotError.remoteChanged
            }
            for (index, image) in desired.enumerated() {
                _ = try await verifiedImage(id: image.id, image: group.images[index], specs: group.specs[index])
            }
            let desiredIDs = Set(desired.map(\.id))
            report(.deletingObsolete, group)
            for placement in group.placements where !desiredIDs.contains(placement.imageID) {
                try await api.deleteLibraryPlacement(id: placement.id)
            }
            var ordered: [String] = []
            for image in desired {
                if let retained = group.placements.first(where: { $0.imageID == image.id }) {
                    ordered.append(retained.id)
                } else {
                    let created = try await api.createLibraryPlacement(imageID: image.id, localizationID: group.localizationID, group: group.group)
                    try validate([created], localizationID: group.localizationID, group: group.group, allowProcessing: true)
                    guard created.imageID == image.id else {
                        throw ScreenshotError.remoteChanged
                    }
                    ordered.append(created.id)
                }
            }
            report(.ordering, group)
            try await api.orderLibraryPlacements(localizationID: group.localizationID, group: group.group, ids: ordered)
            report(.verifying, group)
            var ready = false
            for attempt in 1...pollAttempts {
                let observed = try await api.libraryPlacements(localizationID: group.localizationID, group: group.group)
                try validate(observed, localizationID: group.localizationID, group: group.group, allowProcessing: true)
                guard observed.map(\.id) == ordered, observed.map(\.imageID) == desired.map(\.id) else {
                    throw ScreenshotError.remoteChanged
                }
                if observed.allSatisfy(\.isReady) {
                    ready = true
                    break
                }
                if attempt < pollAttempts {
                    try await Task.sleep(for: pollDelay)
                }
            }
            guard ready else {
                throw ScreenshotError.processingTimedOut
            }
            for (index, image) in desired.enumerated() {
                _ = try await verifiedImage(id: image.id, image: group.images[index], specs: group.specs[index])
            }
            plan.actions.append(.init(kind: .verify, resource: "placements/\(group.key)", locale: group.locale,
                                      desiredValue: "Processed assets, specification IDs, byte counts, placement identities and order matched; no source checksum is exposed by Apple."))
            report(.completed, group)
        }
        return plan
    }

    static func reference(_ image: ScreenshotImage) -> String {
        "apogee-sha256:\(image.digest)"
    }

    private func matches(_ remote: LibraryImage, image: ScreenshotImage, specs: [String]) -> Bool {
        remote.isProcessed && remote.byteCount == image.data.count
            && remote.referenceName == Self.reference(image) && remote.specID.map(specs.contains) == true
    }

    private func verifiedImage(id: String, image: ScreenshotImage, specs: [String]) async throws -> LibraryImage {
        let observed = try await api.libraryImage(id: id)
        guard observed.id == id, matches(observed, image: image, specs: specs) else {
            throw ScreenshotError.processingFailed
        }
        return observed
    }

    private func validate(_ placements: [LibraryPlacement], localizationID: String, group: String,
                          allowProcessing: Bool = false) throws {
        guard Set(placements.map(\.id)).count == placements.count,
              Set(placements.map(\.imageID)).count == placements.count,
              placements.allSatisfy({
                  !$0.id.isEmpty && !$0.imageID.isEmpty && $0.localizationID == localizationID
                      && $0.group == group && $0.placementType == "APP_SCREENSHOT"
              }) else {
            throw ScreenshotError.incompleteInventory
        }
        for placement in placements where !placement.isReady && !(allowProcessing && placement.state == "ASSET_PROCESSING") {
            // Only bounded state identifiers belong in diagnostics, never arbitrary server text.
            let state = placement.state.range(of: #"\A[A-Z][A-Z0-9_]{0,79}\z"#, options: .regularExpression) != nil
                ? placement.state : "<unrecognized>"
            throw ApogeeError.unexpectedAPIResponse(
                "Unsupported appAssetLibraryPlacements state \(state). Inspect the placement and obtain a fresh dry-run before retrying."
            )
        }
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
