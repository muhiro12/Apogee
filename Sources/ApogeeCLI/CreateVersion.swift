import ApogeeCore
import ArgumentParser
import Foundation

struct CreateVersion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-version",
        abstract: "Create an App Store version for manual release. Defaults to a read-only plan."
    )

    @OptionGroup var release: ReleaseOptions

    func run() async throws {
        let configuration = try release.configuration()
        let credentials = try AppStoreConnectCredentials.load(credentialEnvironment: configuration.credentials)
        let automation = ReleaseAutomation(api: GeneratedAppStoreConnectAPI(credentials: credentials))
        print(try await renderedOutput(automation: automation, configuration: configuration))
    }

    func renderedOutput(automation: ReleaseAutomation, configuration: ApogeeConfiguration) async throws -> String {
        let plan = try await createVersion(automation: automation, configuration: configuration)
        return try release.render(plan, command: "create-version", configuration: configuration)
    }

    func createVersion(automation: ReleaseAutomation, configuration: ApogeeConfiguration) async throws -> ReleasePlan {
        try await automation.createVersion(
            appLookup: try release.appLookup(configuration: configuration),
            version: release.version,
            platform: release.platform(configuration: configuration),
            options: try release.executionOptions()
        )
    }
}
