import Foundation

struct ScreenshotWorkflow {
    struct Group {
        var locale: String
        var localizationID: String
        var displayType: String
        var set: RemoteScreenshotSet?
        var remote: [RemoteScreenshot]
        var images: [ScreenshotImage]
    }

    let api: any ScreenshotAPI
    var validateVersion: @Sendable () async throws -> Void = {}
    var pollAttempts = 30
    var pollDelay: Duration = .seconds(2)

    func run(
        app: AppStoreConnectApp, version: AppStoreConnectVersion, platform: Platform,
        localizations: [AppStoreConnectLocalization], path: String,
        options: ReleaseExecutionOptions, recovery: ScreenshotRecovery?
    ) async throws -> ReleasePlan {
        let local = try ScreenshotFiles.load(path, platform: platform)
        if let recovery {
            let inputPath = URL(fileURLWithPath: path).standardizedFileURL.path
            let recoveryPath = URL(fileURLWithPath: recovery.directory).standardizedFileURL.path
            guard recoveryPath != inputPath, !recoveryPath.hasPrefix(inputPath + "/") else {
                throw ScreenshotError.recoveryMismatch
            }
        }
        let target = "\(app.id)/\(version.id)/\(platform.rawValue)"
        let journal = try recovery.map { try ScreenshotJournal(recovery: $0, target: target, applying: options.mode == .apply) }
        let localeIDs = localizations.map(\.locale)
        guard Set(localeIDs).count == localeIDs.count, Set(localizations.map(\.id)).count == localizations.count else {
            throw ScreenshotError.incompleteInventory
        }
        var groups: [Group] = []
        var actions: [PlannedAction] = []
        for (locale, displayType, images) in local {
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
            let group = Group(locale: locale, localizationID: localization.id, displayType: displayType, set: set, remote: remote, images: images)
            groups.append(group)
            let resource = "screenshots/\(localization.id)/\(displayType)"
            let desiredChecksums = Set(images.map(\.checksum))
            let retained = remote.filter { $0.state == "COMPLETE" && desiredChecksums.contains($0.checksum ?? "") }
            guard Set(retained.compactMap(\.checksum)).count == retained.count else {
                throw ScreenshotError.incompleteInventory
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
        let candidates = try ScreenshotJournal.originals(recovery?.originalsPath) + groups.flatMap(\.images)
        // Finish and re-read every backup before the first remote mutation, across all groups.
        for group in groups {
            if let set = group.set {
                try journal.backup(group.remote, setID: set.id, candidates: candidates)
                try journal.writeRestoreLayout(setID: set.id, locale: group.locale, displayType: group.displayType)
            }
        }
        for group in groups {
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
            for item in group.remote where item.state != "COMPLETE" || !desiredChecksums.contains(item.checksum ?? "") {
                try await assertCurrent(set.id, expected)
                if item.state == "COMPLETE", try journal.originalData(item) == nil {
                    throw ScreenshotError.originalsMissing
                }
                try Task.checkCancellation()
                try await validateVersion()
                try await api.deleteScreenshot(id: item.id)
                expected.removeAll { $0.id == item.id }
                try await assertCurrent(set.id, expected)
            }
            var desiredIDs: [String] = []
            for image in group.images {
                if let retained = expected.first(where: { $0.state == "COMPLETE" && $0.checksum == image.checksum }) {
                    desiredIDs.append(retained.id)
                    continue
                }
                try await assertCurrent(set.id, expected)
                try Task.checkCancellation()
                try await validateVersion()
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
                    try await api.uploadScreenshotPart(image.data.subdata(in: operation.offset..<(operation.offset + operation.length)), operation: operation)
                }
                try Task.checkCancellation()
                try await validateVersion()
                try await api.commitScreenshot(id: reserved.id, checksum: image.checksum)
                let complete = try await waitForProcessing(id: reserved.id, image: image)
                expected[expected.count - 1] = complete
                desiredIDs.append(complete.id)
            }
            try await assertCurrent(set.id, expected)
            if expected.map(\.id) != desiredIDs {
                try Task.checkCancellation()
                try await validateVersion()
                try await api.orderScreenshots(setID: set.id, ids: desiredIDs)
            }
            let final = try await api.screenshots(setID: set.id)
            guard final.map(\.id) == desiredIDs, final.count == group.images.count,
                  zip(final, group.images).allSatisfy({ $0.state == "COMPLETE" && $0.checksum == $1.checksum && $0.byteCount == $1.data.count }) else {
                throw ScreenshotError.remoteChanged
            }
            plan.actions.append(.init(kind: .verify, resource: "appScreenshotSet/\(set.id)", locale: group.locale,
                                      desiredValue: "Ordered screenshot checksums and COMPLETE processing states matched"))
        }
        return plan
    }

    private func validate(_ items: [RemoteScreenshot], setID: String?, journal: ScreenshotJournal?) throws {
        let complete = items.filter { $0.state == "COMPLETE" }
        guard items.count <= 10, Set(items.map(\.id)).count == items.count,
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

    private func waitForProcessing(id: String, image: ScreenshotImage) async throws -> RemoteScreenshot {
        for attempt in 0..<pollAttempts {
            try Task.checkCancellation()
            try await validateVersion()
            let item = try await api.screenshot(id: id)
            guard item.id == id, item.fileName == image.fileName, item.byteCount == image.data.count else {
                throw ScreenshotError.remoteChanged
            }
            if item.state == "COMPLETE" {
                guard item.checksum == image.checksum else {
                    throw ScreenshotError.processingFailed
                }
                return item
            }
            guard item.state == "UPLOAD_COMPLETE" || item.state == "AWAITING_UPLOAD" else {
                throw ScreenshotError.processingFailed
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
