import Foundation

struct ScreenshotWorkflow {
    struct Group {
        var locale: String
        var localizationID: String
        var displayType: String
        var set: RemoteScreenshotSet?
        var remote: [RemoteScreenshot]
        var images: [ScreenshotImage]
        /// Upload every replacement and verify it before deleting any existing image.
        var uploadFirst = false
    }

    static let setLimit = 10

    let api: any ScreenshotAPI
    var validateVersion: @Sendable () async throws -> Void = {}
    var progress: (@Sendable (ScreenshotProgress) -> Void)?
    var pollAttempts = 30
    var pollDelay: Duration = .seconds(2)

    func run(
        app: AppStoreConnectApp, version: AppStoreConnectVersion, platform: Platform,
        localizations: [AppStoreConnectLocalization], path: String,
        options: ReleaseExecutionOptions, recovery: ScreenshotRecovery?
    ) async throws -> ReleasePlan {
        let started = ContinuousClock.now
        let local = try ScreenshotFiles.load(path, platform: platform)
        let totalImages = local.reduce(0) { $0 + $1.2.count }
        var completedImages = 0
        func report(_ stage: ScreenshotProgress.Stage, locale: String, displayType: String, attempt: Int? = nil) {
            guard let progress else {
                return
            }
            let elapsed = started.duration(to: .now).components
            progress(.init(stage: stage, locale: locale, displayType: displayType,
                           completedImages: completedImages, totalImages: totalImages,
                           elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                           processingAttempt: attempt, processingLimit: attempt == nil ? nil : pollAttempts))
        }
        if let recovery {
            let inputPath = URL(fileURLWithPath: path).standardizedFileURL.path
            let recoveryPath = URL(fileURLWithPath: recovery.directory).standardizedFileURL.path
            guard recoveryPath != inputPath, !recoveryPath.hasPrefix(inputPath + "/") else {
                throw ScreenshotError.recoveryMismatch
            }
        }
        let target = "\(app.id)/\(version.id)/\(platform.rawValue)"
        let journal = try recovery.map { try ScreenshotJournal(recovery: $0, target: target, applying: options.mode == .apply) }
        // Originals decide the replacement strategy, so they are inspected while planning.
        let suppliedOriginals = try ScreenshotJournal.originals(recovery?.originalsPath)
        let localeIDs = localizations.map(\.locale)
        guard Set(localeIDs).count == localeIDs.count, Set(localizations.map(\.id)).count == localizations.count else {
            throw ScreenshotError.incompleteInventory
        }
        var groups: [Group] = []
        var actions: [PlannedAction] = []
        for (locale, displayType, images) in local {
            report(.planning, locale: locale, displayType: displayType)
            guard let localization = localizations.first(where: { $0.locale == locale }), !localization.id.isEmpty else {
                throw ApogeeError.localizationMissing(locale: locale)
            }
            let sets = try await api.screenshotSets(localizationID: localization.id)
            guard Set(sets.map(\.id)).count == sets.count, Set(sets.map(\.displayType)).count == sets.count else {
                throw ScreenshotError.incompleteInventory
            }
            let set = sets.first { $0.displayType == displayType }
            let remote: [RemoteScreenshot]
            if let set {
                remote = try await api.screenshots(setID: set.id)
            } else {
                remote = []
            }
            try validate(remote, setID: set?.id, journal: journal)
            let resource = "screenshots/\(localization.id)/\(displayType)"
            let desiredChecksums = Set(images.map(\.checksum))
            let retained = remote.filter { $0.state == "COMPLETE" && desiredChecksums.contains($0.checksum ?? "") }
            guard Set(retained.compactMap(\.checksum)).count == retained.count else {
                throw ScreenshotError.incompleteInventory
            }
            var unrecoverable: [RemoteScreenshot] = []
            for item in remote where item.state == "COMPLETE" && !retained.contains(item) {
                if try journal?.hasOriginal(item, candidates: suppliedOriginals + images) != true {
                    unrecoverable.append(item)
                }
            }
            let uploads = images.filter { image in !retained.contains { $0.checksum == image.checksum } }
            // Only finished images occupy a slot for the whole replacement; owned unfinished
            // reservations are cleaned up before the first upload.
            let existing = remote.filter { $0.state == "COMPLETE" }.count
            let uploadFirst = !unrecoverable.isEmpty && existing + uploads.count <= Self.setLimit
            let group = Group(locale: locale, localizationID: localization.id, displayType: displayType,
                              set: set, remote: remote, images: images, uploadFirst: uploadFirst)
            groups.append(group)
            if !unrecoverable.isEmpty {
                let desired = uploadFirst
                    ? "upload-first replacement keeps them until \(uploads.count) replacement(s) are verified (\(existing + uploads.count) of \(Self.setLimit) slots); the previous composition cannot be restored"
                    : "no upload-first replacement: \(existing) existing and \(uploads.count) replacement screenshot(s) exceed the \(Self.setLimit)-image limit; supply verified originals"
                actions.append(.init(kind: .unchanged, resource: resource, locale: locale, field: "replacement",
                                     currentValue: "\(unrecoverable.count) existing screenshot(s) without verified originals in the supplied recovery inputs",
                                     desiredValue: desired).identifyingField("replacementStrategy"))
            }
            for item in remote where !retained.contains(item) {
                actions.append(.init(kind: .delete, resource: "appScreenshot/\(item.id)", locale: locale,
                                     currentValue: "\(item.fileName) \(item.checksum ?? "uncommitted") \(item.state)", isDestructive: true))
            }
            for image in images where !retained.contains(where: { $0.checksum == image.checksum }) {
                actions.append(.init(kind: .create, resource: resource, locale: locale,
                                     desiredValue: "\(image.fileName) \(image.data.count) bytes SHA256=\(image.digest)"))
            }
            let unchanged = remote.count == images.count && zip(remote, images).allSatisfy { $0.state == "COMPLETE" && $0.checksum == $1.checksum }
            let current = try encoded(remote)
            let desired = try encoded(images.map { "\($0.fileName):\($0.digest)" })
            actions.append(.init(kind: unchanged ? .unchanged : .update, resource: resource, locale: locale,
                                 field: "order", currentValue: current, desiredValue: desired,
                                 isDestructive: !unchanged && !remote.isEmpty))
        }
        var plan = ReleasePlan(title: "Update screenshots for \(target)", actions: actions).targeting(app: app, version: version)
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
        guard let journal else {
            throw ScreenshotError.recoveryRequired
        }
        if groups.contains(where: \.uploadFirst), !options.allowUnrecoverableReplacement {
            throw ScreenshotError.unrecoverableReplacementRequiresConfirmation
        }
        let candidates = suppliedOriginals + groups.flatMap(\.images)
        // Finish and re-read every backup before the first remote mutation, across all groups.
        for group in groups {
            guard let set = group.set else {
                continue
            }
            report(.preparingRecovery, locale: group.locale, displayType: group.displayType)
            try journal.backup(group.remote, setID: set.id, candidates: candidates, requireOriginals: !group.uploadFirst)
            // A partial restore tree would misrepresent an unrecoverable composition.
            if !group.uploadFirst {
                try journal.writeRestoreLayout(setID: set.id, locale: group.locale, displayType: group.displayType)
            }
        }
        for group in groups {
            func reportGroup(_ stage: ScreenshotProgress.Stage, attempt: Int? = nil) {
                report(stage, locale: group.locale, displayType: group.displayType, attempt: attempt)
            }
            try Task.checkCancellation()
            try await validateVersion()
            var set: RemoteScreenshotSet
            if let existing = group.set {
                set = existing
            } else {
                let fresh = try await api.screenshotSets(localizationID: group.localizationID)
                guard !fresh.contains(where: { $0.displayType == group.displayType }) else {
                    throw ScreenshotError.remoteChanged
                }
                set = try await api.createScreenshotSet(localizationID: group.localizationID, displayType: group.displayType)
                let created = try await api.screenshotSets(localizationID: group.localizationID).filter { $0.displayType == group.displayType }
                guard created == [set], set.displayType == group.displayType, !set.id.isEmpty else {
                    throw ScreenshotError.remoteChanged
                }
            }
            var expected = group.remote
            let desiredChecksums = Set(group.images.map(\.checksum))
            let obsolete = group.remote.filter { $0.state != "COMPLETE" || !desiredChecksums.contains($0.checksum ?? "") }
            func deleteObsolete(_ items: [RemoteScreenshot]) async throws {
                for item in items where expected.contains(item) {
                    try await assertCurrent(set.id, expected)
                    if item.state == "COMPLETE", !group.uploadFirst, try journal.originalData(item) == nil {
                        throw ScreenshotError.originalsMissing
                    }
                    try Task.checkCancellation()
                    try await validateVersion()
                    reportGroup(.deletingObsolete)
                    try await api.deleteScreenshot(id: item.id)
                    expected.removeAll { $0.id == item.id }
                    try await assertCurrent(set.id, expected)
                }
            }
            if !group.uploadFirst {
                try await deleteObsolete(obsolete)
            } else {
                // Owned unfinished reservations hold no evidence, so they free their slots first.
                try await deleteObsolete(obsolete.filter { $0.state != "COMPLETE" })
                let uploads = group.images.filter { image in
                    !expected.contains { $0.state == "COMPLETE" && $0.checksum == image.checksum }
                }
                guard expected.count + uploads.count <= Self.setLimit else {
                    throw ScreenshotError.setCapacityExceeded
                }
            }
            var desiredIDs: [String] = []
            for image in group.images {
                if let retained = expected.first(where: { $0.state == "COMPLETE" && $0.checksum == image.checksum }) {
                    desiredIDs.append(retained.id)
                    completedImages += 1
                    continue
                }
                try await assertCurrent(set.id, expected)
                try Task.checkCancellation()
                try await validateVersion()
                reportGroup(.uploading)
                let (reserved, operations) = try await api.reserveScreenshot(setID: set.id, fileName: image.fileName, byteCount: image.data.count)
                guard !reserved.id.isEmpty, !expected.contains(where: { $0.id == reserved.id }),
                      reserved.fileName == image.fileName, reserved.byteCount == image.data.count,
                      reserved.state == "AWAITING_UPLOAD" else {
                    throw ScreenshotError.incompleteInventory
                }
                journal.state.owned[reserved.id] = "\(set.id):\(image.checksum)"
                try journal.persist()
                expected.append(reserved)
                try await assertCurrent(set.id, expected)
                try ScreenshotUploadValidation.validate(operations, byteCount: image.data.count)
                for operation in operations {
                    try Task.checkCancellation()
                    try await validateVersion()
                    try ScreenshotUploadValidation.validateExpiry(operation)
                    reportGroup(.uploading)
                    try await api.uploadScreenshotPart(image.data.subdata(in: operation.offset..<(operation.offset + operation.length)), operation: operation)
                }
                try Task.checkCancellation()
                try await validateVersion()
                reportGroup(.committing)
                try await api.commitScreenshot(id: reserved.id, checksum: image.checksum)
                let complete = try await waitForProcessing(id: reserved.id, image: image) { stage, attempt in
                    reportGroup(stage, attempt: attempt)
                }
                expected[expected.count - 1] = complete
                desiredIDs.append(complete.id)
                completedImages += 1
            }
            try await assertCurrent(set.id, expected)
            if group.uploadFirst {
                // Every replacement must be verified before the first deletion.
                reportGroup(.verifyingReplacements)
                let verified = try await api.screenshots(setID: set.id)
                guard verified == expected, desiredIDs.count == group.images.count else {
                    throw ScreenshotError.remoteChanged
                }
                guard zip(desiredIDs, group.images).allSatisfy({ id, image in
                    guard let item = verified.first(where: { $0.id == id }) else {
                        return false
                    }
                    return item.state == "COMPLETE" && item.checksum == image.checksum && item.byteCount == image.data.count
                }) else {
                    throw ScreenshotError.remoteChanged
                }
                try await deleteObsolete(obsolete.filter { $0.state == "COMPLETE" })
            }
            if expected.map(\.id) != desiredIDs {
                try Task.checkCancellation()
                try await validateVersion()
                reportGroup(.ordering)
                try await api.orderScreenshots(setID: set.id, ids: desiredIDs)
            }
            reportGroup(.verifying)
            let final = try await api.screenshots(setID: set.id)
            guard final.map(\.id) == desiredIDs, final.count == group.images.count,
                  zip(final, group.images).allSatisfy({ $0.state == "COMPLETE" && $0.checksum == $1.checksum && $0.byteCount == $1.data.count }) else {
                throw ScreenshotError.remoteChanged
            }
            plan.actions.append(.init(kind: .verify, resource: "appScreenshotSet/\(set.id)", locale: group.locale,
                                      desiredValue: "Ordered screenshot checksums and COMPLETE processing states matched"))
            reportGroup(.completed)
        }
        return plan
    }

    private func validate(_ items: [RemoteScreenshot], setID: String?, journal: ScreenshotJournal?) throws {
        let complete = items.filter { $0.state == "COMPLETE" }
        guard items.count <= Self.setLimit, Set(items.map(\.id)).count == items.count,
              Set(complete.compactMap(\.checksum)).count == complete.count else {
            throw ScreenshotError.incompleteInventory
        }
        for item in items {
            guard !item.id.isEmpty, !item.fileName.isEmpty, item.byteCount > 0, item.byteCount <= 64 * 1_024 * 1_024 else {
                throw ScreenshotError.incompleteInventory
            }
            if item.state == "COMPLETE" {
                guard let checksum = item.checksum, checksum.count == 32,
                      checksum.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                    throw ScreenshotError.incompleteInventory
                }
            } else {
                guard ["AWAITING_UPLOAD", "UPLOAD_COMPLETE", "FAILED"].contains(item.state),
                      let setID, journal?.state.owned[item.id]?.hasPrefix("\(setID):") == true else {
                    throw ScreenshotError.incompleteInventory
                }
            }
        }
    }

    private func assertCurrent(_ setID: String, _ expected: [RemoteScreenshot]) async throws {
        try Task.checkCancellation()
        try await validateVersion()
        guard try await api.screenshots(setID: setID) == expected else {
            throw ScreenshotError.remoteChanged
        }
    }

    private func waitForProcessing(id: String, image: ScreenshotImage,
                                   observe: (ScreenshotProgress.Stage, Int) -> Void) async throws -> RemoteScreenshot {
        for attempt in 0..<pollAttempts {
            try Task.checkCancellation()
            try await validateVersion()
            observe(.processing, attempt + 1)
            let item = try await api.screenshot(id: id)
            guard item.id == id, item.fileName == image.fileName, item.byteCount == image.data.count else {
                throw ScreenshotError.remoteChanged
            }
            if item.state == "COMPLETE" {
                if item.checksum == image.checksum {
                    return item
                }
                // App Store Connect can report COMPLETE before the source checksum is readable.
                // An unreadable checksum stays pending; a different one is a permanent mismatch.
                let pending = item.checksum?.isEmpty ?? true
                guard pending else {
                    throw ScreenshotError.processingFailed
                }
                observe(.waitingForChecksum, attempt + 1)
            } else {
                guard item.state == "UPLOAD_COMPLETE" || item.state == "AWAITING_UPLOAD" else {
                    throw ScreenshotError.processingFailed
                }
            }
            if attempt + 1 < pollAttempts {
                try await Task.sleep(for: pollDelay)
            }
        }
        throw ScreenshotError.processingTimedOut
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
