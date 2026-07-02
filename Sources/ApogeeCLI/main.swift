import ArgumentParser
import Foundation
import ApogeeCore

@main
struct ApogeeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apogee",
        abstract: "Automate App Store Connect release operations with dry-run plans by default.",
        version: ApogeeCore.version,
        subcommands: [
            UpdateReleaseNotes.self,
            UpdateMetadata.self,
            AttachBuild.self,
            UpdateScreenshots.self,
            SubmitForReview.self,
            SyncWebhooks.self,
        ]
    )
}

struct UpdateReleaseNotes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-release-notes",
        abstract: "Update localized What's New text for an existing App Store version."
    )

    @OptionGroup var release: ReleaseOptions

    @Option(name: .customLong("metadata-path"), help: "Path to AppStore/Metadata.")
    var metadataPath: String

    func run() async throws {
        let plan = try await makeAutomation().updateReleaseNotes(
            appLookup: try release.appLookup(),
            version: release.version,
            metadataPath: metadataPath,
            platform: release.platform.platform,
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
    var metadataPath: String

    func run() async throws {
        let plan = try await makeAutomation().updateMetadata(
            appLookup: try release.appLookup(),
            version: release.version,
            metadataPath: metadataPath,
            platform: release.platform.platform,
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
        let plan = try await makeAutomation().attachBuild(
            appLookup: try release.appLookup(),
            version: release.version,
            buildVersion: buildVersion,
            platform: release.platform.platform,
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
    var screenshotsPath: String

    func run() async throws {
        let plan = try await makeAutomation().updateScreenshots(
            appLookup: try release.appLookup(),
            version: release.version,
            screenshotsPath: screenshotsPath,
            platform: release.platform.platform,
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
        let plan = try await makeAutomation().submitForReview(
            appLookup: try release.appLookup(),
            version: release.version,
            platform: release.platform.platform,
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

    @Option(help: "Path to a webhooks JSON configuration file.")
    var config: String

    @Flag(name: .customLong("allow-destructive"), help: "Allow destructive webhook deletions when used with --apply and --plan-token.")
    var allowDestructive = false

    @Option(name: .customLong("plan-token"), help: "Plan token printed by the previous dry-run for destructive apply operations.")
    var planToken: String?

    func run() async throws {
        let plan = try await makeAutomation().syncWebhooks(
            appLookup: try lookup.appLookup(),
            configPath: config,
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

    @Option(help: "Target App Store version string.")
    var version: String

    @Option(help: "App Store platform.")
    var platform: PlatformArgument = .iOS

    func appLookup() throws -> AppLookup {
        try lookup.appLookup()
    }

    func executionOptions() throws -> ReleaseExecutionOptions {
        try mode.executionOptions()
    }
}

struct AppLookupOptions: ParsableArguments {
    @Option(name: .customLong("app-id"), help: "App Store Connect app resource ID. Takes priority over --bundle-id.")
    var appID: String?

    @Option(name: .customLong("bundle-id"), help: "Bundle ID used to resolve the app when --app-id is omitted.")
    var bundleID: String?

    func appLookup() throws -> AppLookup {
        if let appID, !appID.isEmpty {
            return .appID(appID)
        }

        if let bundleID, !bundleID.isEmpty {
            return .bundleID(bundleID)
        }

        throw ValidationError("Provide --app-id or --bundle-id.")
    }
}

struct ExecutionModeOptions: ParsableArguments {
    @Flag(help: "Print the plan without writing to App Store Connect. This is the default.")
    var dryRun = false

    @Flag(help: "Apply the plan to App Store Connect.")
    var apply = false

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

private func makeAutomation() throws -> ReleaseAutomation {
    let credentials = try AppStoreConnectCredentials.load()
    let api = GeneratedAppStoreConnectAPI(credentials: credentials)
    return ReleaseAutomation(api: api)
}
