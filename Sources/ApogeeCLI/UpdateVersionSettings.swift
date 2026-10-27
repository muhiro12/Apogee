import ApogeeCore
import ArgumentParser
import Foundation

struct UpdateVersionSettings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-version-settings",
        abstract: "Read or update copyright and release policy. Defaults to a read-only plan."
    )

    @OptionGroup var release: ReleaseOptions
    @Option(help: "Copyright value; omit to preserve the current value.")
    var copyright: String?
    @OptionGroup var publication: ReleasePolicyOptions

    func run() async throws {
        _ = try settingsPatch()
        let configuration = try release.configuration()
        let credentials = try AppStoreConnectCredentials.load(credentialEnvironment: configuration.credentials)
        let automation = ReleaseAutomation(api: GeneratedAppStoreConnectAPI(credentials: credentials))
        print(try await renderedOutput(automation: automation, configuration: configuration))
    }

    func renderedOutput(automation: ReleaseAutomation, configuration: ApogeeConfiguration) async throws -> String {
        let plan = try await automation.updateVersionSettings(
            appLookup: try release.appLookup(configuration: configuration), version: release.version,
            platform: release.platform(configuration: configuration), patch: try settingsPatch(),
            options: try release.executionOptions()
        )
        return try release.render(plan, command: "update-version-settings", configuration: configuration)
    }

    func settingsPatch() throws -> VersionSettingsPatch {
        .init(copyright: copyright, releasePolicy: try publication.policy())
    }
}
