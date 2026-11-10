import Foundation

package struct GeneratedSourceInstaller {
    package init() {}

    package func install(from sourceDirectory: URL, to outputDirectory: URL) throws {
        let fileManager = FileManager.default
        let sourceFiles = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
            .filter(Self.isClientSource)
            .sorted()
        for requiredFile in ["Client.swift", "Types.swift"] where !sourceFiles.contains(requiredFile) {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: sourceDirectory.appendingPathComponent(requiredFile).path])
        }

        // Read every generated fragment before replacing the committed output.
        let sources = try sourceFiles.map { name in
            (name: name, data: try Data(contentsOf: sourceDirectory.appendingPathComponent(name)))
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for source in sources {
            try source.data.write(to: outputDirectory.appendingPathComponent(source.name), options: .atomic)
        }
        for name in try fileManager.contentsOfDirectory(atPath: outputDirectory.path) {
            if (Self.isClientSource(name) && !sourceFiles.contains(name)) || name == "Server.swift" {
                try fileManager.removeItem(at: outputDirectory.appendingPathComponent(name))
            }
        }
    }

    private static func isClientSource(_ name: String) -> Bool {
        name == "Client.swift" || name == "Types.swift"
            || (name.hasPrefix("Types+") && name.hasSuffix(".swift"))
    }
}
