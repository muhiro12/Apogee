import ApogeeCore
import Foundation

// A public-library consumer smoke check. This example never contacts App Store Connect.
let metadata = try MetadataLoader().load(from: CommandLine.arguments.dropFirst().first ?? "AppStore/Metadata")
let plan = ReleasePlan(title: "Example local release metadata", actions: metadata.map { metadata in
    .init(kind: .verify, resource: "metadata", locale: metadata.locale, desiredValue: "Readable UTF-8 files")
})
print(PlanRenderer().render(plan))
