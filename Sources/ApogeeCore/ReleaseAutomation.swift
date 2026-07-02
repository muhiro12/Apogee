import Foundation

public struct ReleaseExecutionOptions: Sendable, Hashable {
    public var mode: OperationMode
    public var allowDestructive: Bool
    public var planToken: String?

    public init(mode: OperationMode, allowDestructive: Bool = false, planToken: String? = nil) {
        self.mode = mode
        self.allowDestructive = allowDestructive
        self.planToken = planToken
    }
}

public struct ReleaseAutomation: Sendable {
    private static let readyReviewState = "READY_FOR_REVIEW"
    private static let submittedReviewStates = ["WAITING_FOR_REVIEW", "IN_REVIEW", "COMPLETE"]

    private let api: any AppStoreConnectAPI
    private let metadataLoader: MetadataLoader
    private let screenshotLoader: ScreenshotLoader
    private let webhookLoader: WebhookConfigurationLoader
    private let secretEnvironment: SecretEnvironment

    public init(
        api: any AppStoreConnectAPI,
        metadataLoader: MetadataLoader = .init(),
        screenshotLoader: ScreenshotLoader = .init(),
        webhookLoader: WebhookConfigurationLoader = .init(),
        secretEnvironment: SecretEnvironment = .init()
    ) {
        self.api = api
        self.metadataLoader = metadataLoader
        self.screenshotLoader = screenshotLoader
        self.webhookLoader = webhookLoader
        self.secretEnvironment = secretEnvironment
    }

    public func updateReleaseNotes(
        appLookup: AppLookup,
        version: String,
        metadataPath: String,
        platform: Platform = .iOS,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        try await updateMetadata(
            appLookup: appLookup,
            version: version,
            metadataPath: metadataPath,
            fields: [.releaseNotes],
            platform: platform,
            options: options
        )
    }

    public func updateMetadata(
        appLookup: AppLookup,
        version: String,
        metadataPath: String,
        fields: Set<MetadataField> = Set(MetadataField.allCases),
        platform: Platform = .iOS,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        let localMetadata = try metadataLoader.load(from: metadataPath)
            .map { metadata in
                metadata.filtered(fields: fields)
            }
            .filter { metadata in
                metadata.releaseNotes != nil
                    || metadata.description != nil
                    || metadata.keywords != nil
                    || metadata.promotionalText != nil
            }

        let context = try await releaseContext(appLookup: appLookup, version: version, platform: platform)
        let remoteLocalizations = try await api.appStoreVersionLocalizations(versionID: context.version.id)
        let localizationsByLocale = Dictionary(uniqueKeysWithValues: remoteLocalizations.map { ($0.locale, $0) })
        var actions: [PlannedAction] = []
        var patches: [(remote: AppStoreConnectLocalization, patch: MetadataPatch)] = []

        for metadata in localMetadata {
            guard let remote = localizationsByLocale[metadata.locale] else {
                throw ApogeeError.localizationMissing(locale: metadata.locale)
            }

            let patch = metadataPatch(local: metadata, remote: remote.metadata, fields: fields)
            if patch.isEmpty {
                actions.append(.init(
                    kind: .unchanged,
                    resource: "appStoreVersionLocalization/\(remote.id)",
                    locale: metadata.locale
                ))
            } else {
                actions.append(contentsOf: metadataActions(
                    remoteID: remote.id,
                    locale: metadata.locale,
                    local: metadata,
                    remote: remote.metadata,
                    fields: fields
                ))
                patches.append((remote: remote, patch: patch))
            }
        }

        var plan = ReleasePlan(title: "Update metadata for \(context.app.id) \(version)", actions: actions)
        guard options.mode == .apply else {
            return plan
        }

        for item in patches {
            _ = try await api.updateLocalization(id: item.remote.id, patch: item.patch)
        }

        let readBackLocalizations = try await api.appStoreVersionLocalizations(versionID: context.version.id)
        try verifyMetadataPatches(patches, readBack: readBackLocalizations)
        plan.actions.append(.init(kind: .verify, resource: "appStoreVersion/\(context.version.id)", desiredValue: "metadata read-back matched"))
        return plan
    }

    public func attachBuild(
        appLookup: AppLookup,
        version: String,
        buildVersion: String,
        platform: Platform = .iOS,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        let context = try await releaseContext(appLookup: appLookup, version: version, platform: platform)
        let builds = try await api.builds(
            appID: context.app.id,
            buildVersion: buildVersion,
            appStoreVersion: version,
            platform: platform
        )
        let build = try exactlyOneBuild(builds, appID: context.app.id, buildVersion: buildVersion)
        let currentBuild = try await api.build(versionID: context.version.id)
        var plan = ReleasePlan(
            title: "Attach build \(buildVersion) to \(context.app.id) \(version)",
            actions: [
                .init(
                    kind: currentBuild?.id == build.id ? .unchanged : .attach,
                    resource: "appStoreVersion/\(context.version.id)/build",
                    currentValue: currentBuild?.version ?? currentBuild?.id,
                    desiredValue: build.version ?? build.id
                ),
            ]
        )

        guard options.mode == .apply, currentBuild?.id != build.id else {
            return plan
        }

        try await api.attachBuild(versionID: context.version.id, buildID: build.id)
        let readBackBuild = try await api.build(versionID: context.version.id)
        guard readBackBuild?.id == build.id else {
            throw ApogeeError.unexpectedAPIResponse("Build read-back did not match \(build.id).")
        }

        plan.actions.append(.init(kind: .verify, resource: "appStoreVersion/\(context.version.id)/build", desiredValue: build.id))
        return plan
    }

    public func updateScreenshots(
        appLookup: AppLookup,
        version: String,
        screenshotsPath: String,
        platform: Platform = .iOS,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        let screenshotSets = try screenshotLoader.load(from: screenshotsPath)
        let context = try await releaseContext(appLookup: appLookup, version: version, platform: platform)
        let localizations = try await api.appStoreVersionLocalizations(versionID: context.version.id)
        let locales = Set(localizations.map(\.locale))

        for screenshotSet in screenshotSets where !locales.contains(screenshotSet.locale) {
            throw ApogeeError.localizationMissing(locale: screenshotSet.locale)
        }

        let plan = ReleasePlan(
            title: "Update screenshots for \(context.app.id) \(version)",
            actions: screenshotSets.map { screenshotSet in
                .init(
                    kind: .unsupported,
                    resource: "screenshots/\(screenshotSet.displayType)",
                    locale: screenshotSet.locale,
                    desiredValue: "\(screenshotSet.files.count) file(s)"
                )
            }
        )

        if options.mode == .apply {
            throw ApogeeError.unsupported(.screenshotUpload)
        }

        return plan
    }

    public func submitForReview(
        appLookup: AppLookup,
        version: String,
        platform: Platform = .iOS,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        let context = try await releaseContext(appLookup: appLookup, version: version, platform: platform)
        let existingSubmissions = try await api.reviewSubmissions(appID: context.app.id, platform: platform)
        let existingSubmission = try existingReviewSubmission(
            in: existingSubmissions,
            versionID: context.version.id
        )

        if let existingSubmission {
            if isSubmittedReviewState(existingSubmission.state) {
                var plan = ReleasePlan(
                    title: "Submit \(context.app.id) \(version) for review",
                    actions: [
                        .init(
                            kind: .unchanged,
                            resource: "reviewSubmission/\(existingSubmission.id)",
                            currentValue: existingSubmission.state,
                            desiredValue: existingSubmission.state
                        ),
                    ]
                )

                if options.mode == .apply {
                    let readBack = try await api.reviewSubmission(id: existingSubmission.id)
                    try verifySubmittedReviewSubmission(readBack, versionID: context.version.id)
                    plan.actions.append(.init(
                        kind: .verify,
                        resource: "reviewSubmission/\(readBack.id)",
                        desiredValue: readBack.state
                    ))
                }

                return plan
            }

            guard existingSubmission.state == Self.readyReviewState else {
                throw ApogeeError.reviewSubmissionStateUnexpected(
                    id: existingSubmission.id,
                    state: existingSubmission.state,
                    expected: [Self.readyReviewState] + Self.submittedReviewStates
                )
            }

            var plan = ReleasePlan(
                title: "Submit \(context.app.id) \(version) for review",
                actions: [
                    .init(
                        kind: .update,
                        resource: "reviewSubmission/\(existingSubmission.id).submitted",
                        currentValue: "false",
                        desiredValue: "true"
                    ),
                ]
            )

            guard options.mode == .apply else {
                return plan
            }

            let submitted = try await api.submitReviewSubmission(id: existingSubmission.id)
            let readBack = try await api.reviewSubmission(id: submitted.id)
            try verifySubmittedReviewSubmission(readBack, versionID: context.version.id)
            plan.actions.append(.init(
                kind: .verify,
                resource: "reviewSubmission/\(readBack.id)",
                desiredValue: readBack.state
            ))
            return plan
        }

        var plan = ReleasePlan(
            title: "Submit \(context.app.id) \(version) for review",
            actions: [
                .init(kind: .create, resource: "reviewSubmission", desiredValue: platform.rawValue),
                .init(kind: .create, resource: "reviewSubmissionItem", desiredValue: "appStoreVersion/\(context.version.id)"),
                .init(kind: .update, resource: "reviewSubmission.submitted", desiredValue: "true"),
            ]
        )

        guard options.mode == .apply else {
            return plan
        }

        let submission = try await api.createReviewSubmission(appID: context.app.id, platform: platform)
        _ = try await api.createReviewSubmissionItem(submissionID: submission.id, versionID: context.version.id)
        let submitted = try await api.submitReviewSubmission(id: submission.id)
        let readBack = try await api.reviewSubmission(id: submitted.id)
        try verifySubmittedReviewSubmission(readBack, versionID: context.version.id)
        plan.actions.append(.init(kind: .verify, resource: "reviewSubmission/\(readBack.id)", desiredValue: readBack.state))
        return plan
    }

    public func syncWebhooks(
        appLookup: AppLookup,
        configPath: String,
        options: ReleaseExecutionOptions
    ) async throws -> ReleasePlan {
        let configuration = try webhookLoader.load(from: configPath)
        let app = try await resolveApp(appLookup)
        let remoteWebhooks = try await api.webhooks(appID: app.id)
        let remoteByName = try uniqueWebhooksByName(remoteWebhooks, source: "App Store Connect")
        let desiredByName = try uniqueWebhooksByName(configuration.webhooks, source: "desired configuration")
        var actions: [PlannedAction] = []

        for desired in configuration.webhooks {
            if let remote = remoteByName[desired.name] {
                if webhookNeedsUpdate(remote: remote, desired: desired) {
                    actions.append(.init(
                        kind: .update,
                        resource: "webhook/\(remote.id)",
                        currentValue: webhookSummary(remote),
                        desiredValue: webhookSummary(desired)
                    ))
                } else {
                    actions.append(.init(kind: .unchanged, resource: "webhook/\(remote.id)", desiredValue: desired.name))
                }
            } else {
                actions.append(.init(kind: .create, resource: "webhook", desiredValue: webhookSummary(desired)))
            }
        }

        for remote in remoteWebhooks where desiredByName[remote.name] == nil {
            actions.append(.init(
                kind: .delete,
                resource: "webhook/\(remote.id)",
                currentValue: webhookSummary(remote),
                isDestructive: true
            ))
        }

        let plan = ReleasePlan(title: "Sync webhooks for \(app.id)", actions: actions)
        try validateDestructiveGate(plan: plan, options: options)

        guard options.mode == .apply else {
            return plan
        }

        for desired in configuration.webhooks {
            if let remote = remoteByName[desired.name] {
                if webhookNeedsUpdate(remote: remote, desired: desired) {
                    let secret = desired.rotateSecret ? try secretEnvironment.secret(named: desired.secretEnvironmentVariable) : nil
                    _ = try await api.updateWebhook(id: remote.id, webhook: desired, secret: secret)
                }
            } else {
                let secret = try secretEnvironment.secret(named: desired.secretEnvironmentVariable)
                _ = try await api.createWebhook(appID: app.id, webhook: desired, secret: secret)
            }
        }

        for remote in remoteWebhooks where desiredByName[remote.name] == nil {
            try await api.deleteWebhook(id: remote.id)
        }

        let readBackWebhooks = try await api.webhooks(appID: app.id)
        try verifyWebhookSync(configuration: configuration, readBack: readBackWebhooks)
        var verifiedPlan = plan
        verifiedPlan.actions.append(.init(kind: .verify, resource: "app/\(app.id)/webhooks", desiredValue: "webhooks read-back matched"))
        return verifiedPlan
    }

    private func releaseContext(appLookup: AppLookup, version: String, platform: Platform) async throws -> ReleaseContext {
        let app = try await resolveApp(appLookup)
        let versions = try await api.appStoreVersions(appID: app.id, version: version, platform: platform)
        let appStoreVersion = try exactlyOneVersion(versions, appID: app.id, version: version)
        return .init(app: app, version: appStoreVersion)
    }

    private func resolveApp(_ appLookup: AppLookup) async throws -> AppStoreConnectApp {
        switch appLookup {
        case let .appID(appID):
            return try await api.app(id: appID)
        case let .bundleID(bundleID):
            let apps = try await api.apps(bundleID: bundleID)
            if apps.isEmpty {
                throw ApogeeError.appNotFound(bundleID: bundleID)
            }

            if apps.count > 1 {
                throw ApogeeError.appAmbiguous(bundleID: bundleID, matches: apps.count)
            }

            return apps[0]
        }
    }

    private func exactlyOneVersion(_ versions: [AppStoreConnectVersion], appID: String, version: String) throws -> AppStoreConnectVersion {
        if versions.isEmpty {
            throw ApogeeError.appStoreVersionNotFound(appID: appID, version: version)
        }

        if versions.count > 1 {
            throw ApogeeError.appStoreVersionAmbiguous(appID: appID, version: version, matches: versions.count)
        }

        return versions[0]
    }

    private func exactlyOneBuild(_ builds: [AppStoreConnectBuild], appID: String, buildVersion: String) throws -> AppStoreConnectBuild {
        if builds.isEmpty {
            throw ApogeeError.buildNotFound(appID: appID, buildVersion: buildVersion)
        }

        if builds.count > 1 {
            throw ApogeeError.buildAmbiguous(appID: appID, buildVersion: buildVersion, matches: builds.count)
        }

        return builds[0]
    }

    private func existingReviewSubmission(
        in submissions: [AppStoreConnectReviewSubmission],
        versionID: String
    ) throws -> AppStoreConnectReviewSubmission? {
        let matches = submissions.filter { submission in
            submission.appStoreVersionID == versionID
        }

        if matches.count > 1 {
            throw ApogeeError.reviewSubmissionAmbiguous(versionID: versionID, matches: matches.count)
        }

        return matches.first
    }

    private func isSubmittedReviewState(_ state: String?) -> Bool {
        guard let state else {
            return false
        }

        return Self.submittedReviewStates.contains(state)
    }

    private func verifySubmittedReviewSubmission(
        _ submission: AppStoreConnectReviewSubmission,
        versionID: String
    ) throws {
        guard submission.appStoreVersionID == versionID else {
            throw ApogeeError.reviewSubmissionVersionMismatch(
                id: submission.id,
                expectedVersionID: versionID,
                actualVersionID: submission.appStoreVersionID
            )
        }

        guard isSubmittedReviewState(submission.state) else {
            throw ApogeeError.reviewSubmissionStateUnexpected(
                id: submission.id,
                state: submission.state,
                expected: Self.submittedReviewStates
            )
        }
    }

    private func metadataPatch(local: LocalizedMetadata, remote: LocalizedMetadata, fields: Set<MetadataField>) -> MetadataPatch {
        .init(
            releaseNotes: changed(local.releaseNotes, remote.releaseNotes, field: .releaseNotes, fields: fields),
            description: changed(local.description, remote.description, field: .description, fields: fields),
            keywords: changed(local.keywords, remote.keywords, field: .keywords, fields: fields),
            promotionalText: changed(local.promotionalText, remote.promotionalText, field: .promotionalText, fields: fields)
        )
    }

    private func changed(_ local: String?, _ remote: String?, field: MetadataField, fields: Set<MetadataField>) -> String? {
        guard fields.contains(field), let local, local != remote else {
            return nil
        }

        return local
    }

    private func metadataActions(
        remoteID: String,
        locale: String,
        local: LocalizedMetadata,
        remote: LocalizedMetadata,
        fields: Set<MetadataField>
    ) -> [PlannedAction] {
        MetadataField.allCases.compactMap { field in
            guard fields.contains(field) else {
                return nil
            }

            let current = value(field, in: remote)
            let desired = value(field, in: local)
            guard let desired, desired != current else {
                return nil
            }

            return .init(
                kind: .update,
                resource: "appStoreVersionLocalization/\(remoteID)",
                locale: locale,
                field: field.displayName,
                currentValue: current,
                desiredValue: desired
            )
        }
    }

    private func value(_ field: MetadataField, in metadata: LocalizedMetadata) -> String? {
        switch field {
        case .releaseNotes:
            metadata.releaseNotes
        case .description:
            metadata.description
        case .keywords:
            metadata.keywords
        case .promotionalText:
            metadata.promotionalText
        }
    }

    private func verifyMetadataPatches(
        _ patches: [(remote: AppStoreConnectLocalization, patch: MetadataPatch)],
        readBack: [AppStoreConnectLocalization]
    ) throws {
        let readBackByID = Dictionary(uniqueKeysWithValues: readBack.map { ($0.id, $0) })

        for item in patches {
            guard let readBackLocalization = readBackByID[item.remote.id] else {
                throw ApogeeError.unexpectedAPIResponse("Localization \(item.remote.id) was missing during read-back.")
            }

            if let releaseNotes = item.patch.releaseNotes, readBackLocalization.metadata.releaseNotes != releaseNotes {
                throw ApogeeError.unexpectedAPIResponse("What's New read-back mismatch for \(item.remote.locale).")
            }

            if let description = item.patch.description, readBackLocalization.metadata.description != description {
                throw ApogeeError.unexpectedAPIResponse("Description read-back mismatch for \(item.remote.locale).")
            }

            if let keywords = item.patch.keywords, readBackLocalization.metadata.keywords != keywords {
                throw ApogeeError.unexpectedAPIResponse("Keywords read-back mismatch for \(item.remote.locale).")
            }

            if let promotionalText = item.patch.promotionalText, readBackLocalization.metadata.promotionalText != promotionalText {
                throw ApogeeError.unexpectedAPIResponse("Promotional text read-back mismatch for \(item.remote.locale).")
            }
        }
    }

    private func validateDestructiveGate(plan: ReleasePlan, options: ReleaseExecutionOptions) throws {
        guard options.mode == .apply, plan.hasDestructiveActions else {
            return
        }

        guard options.allowDestructive else {
            throw ApogeeError.destructiveApplyRequiresConfirmation
        }

        guard options.planToken == plan.token else {
            throw ApogeeError.applyRequiresPlanToken(expected: plan.token)
        }
    }

    private func uniqueWebhooksByName(
        _ webhooks: [AppStoreConnectWebhook],
        source: String
    ) throws -> [String: AppStoreConnectWebhook] {
        var result: [String: AppStoreConnectWebhook] = [:]
        for webhook in webhooks {
            guard result[webhook.name] == nil else {
                throw ApogeeError.duplicateWebhookName(webhook.name, source: source)
            }

            result[webhook.name] = webhook
        }

        return result
    }

    private func uniqueWebhooksByName(
        _ webhooks: [DesiredWebhook],
        source: String
    ) throws -> [String: DesiredWebhook] {
        var result: [String: DesiredWebhook] = [:]
        for webhook in webhooks {
            guard result[webhook.name] == nil else {
                throw ApogeeError.duplicateWebhookName(webhook.name, source: source)
            }

            result[webhook.name] = webhook
        }

        return result
    }

    private func verifyWebhookSync(
        configuration: WebhookSyncConfiguration,
        readBack: [AppStoreConnectWebhook]
    ) throws {
        let readBackByName = try uniqueWebhooksByName(readBack, source: "App Store Connect read-back")
        let desiredByName = try uniqueWebhooksByName(configuration.webhooks, source: "desired configuration")

        for desired in configuration.webhooks {
            guard let actual = readBackByName[desired.name] else {
                throw ApogeeError.unexpectedAPIResponse("Webhook \(desired.name) was missing during read-back.")
            }

            guard webhookMatches(remote: actual, desired: desired) else {
                throw ApogeeError.unexpectedAPIResponse("Webhook \(desired.name) read-back did not match desired configuration.")
            }
        }

        for actual in readBack where desiredByName[actual.name] == nil {
            throw ApogeeError.unexpectedAPIResponse("Webhook \(actual.name) still existed during read-back.")
        }
    }

    private func webhookNeedsUpdate(remote: AppStoreConnectWebhook, desired: DesiredWebhook) -> Bool {
        !webhookMatches(remote: remote, desired: desired)
            || desired.rotateSecret
    }

    private func webhookMatches(remote: AppStoreConnectWebhook, desired: DesiredWebhook) -> Bool {
        remote.url == desired.url
            && remote.enabled == desired.enabled
            && Set(remote.eventTypes) == Set(desired.eventTypes)
    }

    private func webhookSummary(_ webhook: AppStoreConnectWebhook) -> String {
        "\(webhook.name) \(webhook.url) enabled=\(webhook.enabled) events=\(webhook.eventTypes.sorted().joined(separator: ","))"
    }

    private func webhookSummary(_ webhook: DesiredWebhook) -> String {
        "\(webhook.name) \(webhook.url) enabled=\(webhook.enabled) events=\(webhook.eventTypes.sorted().joined(separator: ",")) secretEnv=\(webhook.secretEnvironmentVariable) rotateSecret=\(webhook.rotateSecret)"
    }
}

private struct ReleaseContext: Sendable, Hashable {
    var app: AppStoreConnectApp
    var version: AppStoreConnectVersion
}
