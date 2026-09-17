import ApogeeCore
import ArgumentParser
import Foundation

struct BuildFeedbackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-feedback",
        abstract: "Read TestFlight crash and screenshot feedback summaries for a candidate build."
    )

    @OptionGroup var outputOptions: OutputOptions
    @OptionGroup var lookup: AppLookupOptions
    @OptionGroup var configurationOptions: ConfigurationOptions
    @Option(help: "Target marketing version string.") var version: String
    @Option(help: "Candidate build number.") var buildVersion: String
    @Option(help: "App Store platform.") var platform: PlatformArgument?

    func run() async throws {
        let configuration = try configurationOptions.configuration()
        let credentials = try AppStoreConnectCredentials.load(credentialEnvironment: configuration.credentials)
        let automation = ReleaseAutomation(api: GeneratedAppStoreConnectAPI(credentials: credentials))
        print(try await renderedOutput(automation: automation, configuration: configuration))
    }

    func renderedOutput(automation: ReleaseAutomation, configuration: ApogeeConfiguration) async throws -> String {
        let appLookup = try lookup.appLookup(configuration: configuration)
        let platform = platform?.platform ?? configuration.defaultPlatform ?? .iOS
        let feedback = try await automation.buildFeedback(
            appLookup: appLookup, version: version, buildVersion: buildVersion, platform: platform
        )
        return try outputOptions.render(feedback, requestedTarget: .init(lookup: appLookup, version: version, platform: platform))
    }
}
