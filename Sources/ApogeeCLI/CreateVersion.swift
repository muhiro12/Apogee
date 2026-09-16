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
        let plan = try await createVersion(automation: automation, configuration: configuration)
        print(PlanRenderer().render(plan))
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
