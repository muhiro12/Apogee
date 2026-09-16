import ApogeeCore
import ArgumentParser
import Foundation

struct ReadMetadata: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read-metadata",
        abstract: "Read all localized metadata as JSON and optionally save a new snapshot file."
    )

    @OptionGroup var lookup: AppLookupOptions
    @OptionGroup var configurationOptions: ConfigurationOptions
    @Option(help: "Target App Store version string.")
    var version: String
    @Option(help: "App Store platform.")
    var platform: PlatformArgument?
    @Option(help: "Save the JSON snapshot to a new file; existing paths are never overwritten.")
    var saveTo: String?

    func run() async throws {
        let configuration = try configurationOptions.configuration()
        let credentials = try AppStoreConnectCredentials.load(credentialEnvironment: configuration.credentials)
        let automation = ReleaseAutomation(api: GeneratedAppStoreConnectAPI(credentials: credentials))
        let data = try await snapshotData(automation: automation, configuration: configuration)
        FileHandle.standardOutput.write(data)
    }

    func snapshotData(automation: ReleaseAutomation, configuration: ApogeeConfiguration) async throws -> Data {
        let snapshot = try await automation.readMetadata(
            appLookup: try lookup.appLookup(configuration: configuration),
            version: version,
            platform: platform?.platform ?? configuration.defaultPlatform ?? .iOS
        )
        try Task.checkCancellation()
        let data = try MetadataSnapshotOutput.data(for: snapshot)
        if let saveTo {
            try data.write(to: URL(fileURLWithPath: saveTo), options: .withoutOverwriting)
        }
        return data
    }
}

enum MetadataSnapshotOutput {
    static func data(for snapshot: MetadataSnapshot) throws -> Data {
        func nullable(_ value: String?) -> Any {
            value as Any? ?? NSNull()
        }

        let object: [String: Any] = [
            "schemaVersion": 1,
            "kind": "metadata-snapshot",
            "app": [
                "id": snapshot.app.id,
                "bundleID": nullable(snapshot.app.bundleID),
                "name": nullable(snapshot.app.name),
            ],
            "version": [
                "id": snapshot.version.id,
                "versionString": nullable(snapshot.version.versionString),
                "platform": nullable(snapshot.version.platform?.rawValue),
            ],
            "localizations": snapshot.localizations.map { localization -> [String: Any] in
                [
                    "id": localization.id,
                    "locale": localization.locale,
                    "releaseNotes": nullable(localization.metadata.releaseNotes),
                    "description": nullable(localization.metadata.description),
                    "keywords": nullable(localization.metadata.keywords),
                    "promotionalText": nullable(localization.metadata.promotionalText),
                ]
            },
        ]
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        return data
    }
}
