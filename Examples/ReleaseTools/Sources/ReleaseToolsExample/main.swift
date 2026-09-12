import ApogeeCore
import Foundation

// A public-library consumer smoke check. This example never contacts App Store Connect.
let metadata = try MetadataLoader().load(from: CommandLine.arguments.dropFirst().first ?? "AppStore/Metadata")
let plan = ReleasePlan(title: "Example local release metadata", actions: metadata.map { metadata in
    .init(kind: .verify, resource: "metadata", locale: metadata.locale, desiredValue: "Readable UTF-8 files")
})
print(PlanRenderer().render(plan))

// Compiled against the public library, but only called after an adopter supplies
// credentials and chooses actual remote resources. The smoke check stays offline.
func planReleaseNotes() async throws -> ReleasePlan {
    let credentials = try AppStoreConnectCredentials.load()
    let automation = ReleaseAutomation(
        api: GeneratedAppStoreConnectAPI(credentials: credentials)
    )
    return try await automation.updateReleaseNotes(
        appLookup: .bundleID("com.example.app"),
        version: "1.2.3",
        metadataPath: "AppStore/Metadata",
        options: .init(mode: .dryRun)
    )
}
