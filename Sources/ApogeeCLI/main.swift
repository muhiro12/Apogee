import ArgumentParser
import Foundation
import ApogeeCore

@main
struct ApogeeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apogee",
        abstract: "Automate App Store Connect release operations with dry-run plans by default.",
        subcommands: [
            ReleaseStatusCommand.self,
            ValidateMetadata.self,
            UpdateReleaseNotes.self,
            UpdateMetadata.self,
            AttachBuild.self,
            UpdateScreenshots.self,
            SubmitForReview.self,
            SyncWebhooks.self,
        ]
    )
}

struct ReleaseStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-status",
        abstract: "Read version state, release timing, the attached build, and review status."
    )

    @OptionGroup var lookup: AppLookupOptions
    @OptionGroup var configurationOptions: ConfigurationOptions
    @Option(help: "Target App Store version string.")
    var version: String
    @Option(help: "App Store platform.")
    var platform: PlatformArgument?

    func run() async throws {
        let configuration = try configurationOptions.configuration()
        let status = try await makeAutomation(configuration: configuration).releaseStatus(
            appLookup: try lookup.appLookup(configuration: configuration), version: version,
            platform: platform?.platform ?? configuration.defaultPlatform ?? .iOS
        )
        print(PlanRenderer().render(status))
    }
}

struct ValidateMetadata: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate-metadata",
        abstract: "Validate local metadata files without credentials or network access."
    )

    @OptionGroup var configurationOptions: ConfigurationOptions
    @Option(name: .customLong("metadata-path"), help: "Path to AppStore/Metadata.")
    var metadataPath: String?
    @Flag(help: "Validate only release_notes.txt files.")
    var releaseNotesOnly = false

    func run() throws {
        let configuration = try configurationOptions.configuration()
        let metadata = try MetadataLoader().load(
            from: metadataPath ?? configuration.resolvedMetadataPath,
            fields: releaseNotesOnly ? [.releaseNotes] : Set(MetadataField.allCases)
        )
        let plan = ReleasePlan(title: "Local metadata validation", actions: metadata.map { metadata in
            .init(kind: .verify, resource: "metadata", locale: metadata.locale, desiredValue: "UTF-8 files are readable")
        })
        print(PlanRenderer().render(plan))
    }
}

struct UpdateReleaseNotes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-release-notes",
        abstract: "Update localized What's New text for an existing App Store version."
    )

    @OptionGroup var release: ReleaseOptions

    @Option(name: .customLong("metadata-path"), help: "Path to AppStore/Metadata.")
    var metadataPath: String?

    func run() async throws {
        let configuration = try release.configuration()
        let plan = try await makeAutomation(configuration: configuration).updateReleaseNotes(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            metadataPath: release.metadataPath(metadataPath, configuration: configuration),
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
        print(PlanRenderer().render(plan))
    }
}

struct UpdateMetadata: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-metadata",
        abstract: "Update localized description, keywords, promotional text, and What's New text."
    )

    @OptionGroup var release: ReleaseOptions

    @Option(name: .customLong("metadata-path"), help: "Path to AppStore/Metadata.")
    var metadataPath: String?

    func run() async throws {
        let configuration = try release.configuration()
        let plan = try await makeAutomation(configuration: configuration).updateMetadata(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            metadataPath: release.metadataPath(metadataPath, configuration: configuration),
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
        print(PlanRenderer().render(plan))
    }
}

struct AttachBuild: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach-build",
        abstract: "Attach an existing build to an App Store version."
    )

    @OptionGroup var release: ReleaseOptions

    @Option(name: .customLong("build-version"), help: "Build train version to attach.")
    var buildVersion: String

    func run() async throws {
        let configuration = try release.configuration()
        let plan = try await makeAutomation(configuration: configuration).attachBuild(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            buildVersion: buildVersion,
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
        print(PlanRenderer().render(plan))
    }
}

struct UpdateScreenshots: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-screenshots",
        abstract: "Plan localized screenshot updates. Apply is currently unsupported."
    )

    @OptionGroup var release: ReleaseOptions

    @Option(name: .customLong("screenshots-path"), help: "Path to AppStore/Screenshots.")
    var screenshotsPath: String?

    func run() async throws {
        let configuration = try release.configuration()
        let plan = try await makeAutomation(configuration: configuration).updateScreenshots(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            screenshotsPath: release.screenshotsPath(screenshotsPath, configuration: configuration),
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
        print(PlanRenderer().render(plan))
    }
}

struct SubmitForReview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit-for-review",
        abstract: "Create and submit an App Store review submission for an existing version."
    )

    @OptionGroup var release: ReleaseOptions

    func run() async throws {
        let configuration = try release.configuration()
        let plan = try await makeAutomation(configuration: configuration).submitForReview(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
        print(PlanRenderer().render(plan))
    }
}

struct SyncWebhooks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync-webhooks",
        abstract: "Sync App Store Connect webhooks for an app."
    )

    @OptionGroup var lookup: AppLookupOptions
    @OptionGroup var mode: ExecutionModeOptions
    @OptionGroup var configurationOptions: ConfigurationOptions

    @Option(help: "Path to a webhooks JSON configuration file.")
    var config: String?

    @Flag(name: .customLong("allow-destructive"), help: "Allow destructive webhook deletions when used with --apply and --plan-token.")
    var allowDestructive = false

    @Option(name: .customLong("plan-token"), help: "Plan token printed by the previous dry-run for destructive apply operations.")
    var planToken: String?

    func run() async throws {
        let configuration = try configurationOptions.configuration()
        let plan = try await makeAutomation(configuration: configuration).syncWebhooks(
            appLookup: try lookup.appLookup(configuration: configuration),
            configPath: config.nonEmpty ?? configuration.resolvedWebhooksPath,
            options: try mode.executionOptions(
                allowDestructive: allowDestructive,
                planToken: planToken
            )
        )
        print(PlanRenderer().render(plan))
    }
}

struct ReleaseOptions: ParsableArguments {
    @OptionGroup var lookup: AppLookupOptions
    @OptionGroup var mode: ExecutionModeOptions
    @OptionGroup var configurationOptions: ConfigurationOptions

    @Option(help: "Target App Store version string.")
    var version: String

    @Option(help: "App Store platform.")
    var platform: PlatformArgument?

    func configuration() throws -> ApogeeConfiguration {
        try configurationOptions.configuration()
    }

    func appLookup(configuration: ApogeeConfiguration) throws -> AppLookup {
        try lookup.appLookup(configuration: configuration)
    }

    func platform(configuration: ApogeeConfiguration) -> Platform {
        platform?.platform ?? configuration.defaultPlatform ?? .iOS
    }

    func executionOptions() throws -> ReleaseExecutionOptions {
        try mode.executionOptions()
    }

    func metadataPath(_ path: String?, configuration: ApogeeConfiguration) -> String {
        path.nonEmpty ?? configuration.resolvedMetadataPath
    }

    func screenshotsPath(_ path: String?, configuration: ApogeeConfiguration) -> String {
        path.nonEmpty ?? configuration.resolvedScreenshotsPath
    }
}

struct AppLookupOptions: ParsableArguments {
    @Option(name: .customLong("app-id"), help: "App Store Connect app resource ID. Takes priority over --bundle-id.")
    var appID: String?

    @Option(name: .customLong("bundle-id"), help: "Bundle ID used to resolve the app when --app-id is omitted.")
    var bundleID: String?

    func appLookup(configuration: ApogeeConfiguration = .init()) throws -> AppLookup {
        if let appID = appID.nonEmpty {
            return .appID(appID)
        }

        if let bundleID = bundleID.nonEmpty {
            return .bundleID(bundleID)
        }

        if let appID = configuration.appID.nonEmpty {
            return .appID(appID)
        }

        if let bundleID = configuration.bundleID.nonEmpty {
            return .bundleID(bundleID)
        }

        throw ValidationError("Provide --app-id, --bundle-id, or appID/bundleID in Apogee configuration.")
    }
}

struct ConfigurationOptions: ParsableArguments {
    @Option(name: .customLong("apogee-config"), help: "Path to Apogee JSON configuration. Defaults to apogee.json when present.")
    var apogeeConfigPath: String?

    func configuration() throws -> ApogeeConfiguration {
        try ApogeeConfiguration.loadIfPresent(path: apogeeConfigPath)
    }
}

struct ExecutionModeOptions: ParsableArguments {
    @Flag(help: "Print the plan without writing to App Store Connect. This is the default.")
    var dryRun = false

    @Flag(help: "Apply the plan to App Store Connect.")
    var apply = false

    func validate() throws {
        if dryRun && apply {
            throw ValidationError("Use either --dry-run or --apply, not both.")
        }
    }

    func executionOptions(allowDestructive: Bool = false, planToken: String? = nil) throws -> ReleaseExecutionOptions {
        if dryRun && apply {
            throw ValidationError("Use either --dry-run or --apply, not both.")
        }

        return .init(
            mode: apply ? .apply : .dryRun,
            allowDestructive: allowDestructive,
            planToken: planToken
        )
    }
}

enum PlatformArgument: String, ExpressibleByArgument {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"

    var platform: Platform {
        switch self {
        case .iOS:
            .iOS
        case .macOS:
            .macOS
        case .tvOS:
            .tvOS
        case .visionOS:
            .visionOS
        }
    }
}

private func makeAutomation(configuration: ApogeeConfiguration) throws -> ReleaseAutomation {
    let credentials = try AppStoreConnectCredentials.load(credentialEnvironment: configuration.credentials)
    let api = GeneratedAppStoreConnectAPI(credentials: credentials)
    return ReleaseAutomation(api: api)
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
