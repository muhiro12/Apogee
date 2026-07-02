import CryptoKit
import Darwin
import Foundation

let defaultSpecURL = "https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip"
let defaultGeneratorVersion = "1.12.2"

@main
enum UpdateAppStoreConnectClient {
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showsHelp {
                print(Options.help)
                return
            }

            try Updater(options: options).run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Darwin.exit(1)
        }
    }
}

struct Options {
    var repositoryRoot: String?
    var specURL: String = defaultSpecURL
    var generatorVersion: String = ProcessInfo.processInfo.environment["APOGEE_OPENAPI_GENERATOR_VERSION"] ?? defaultGeneratorVersion
    var showsHelp = false

    init(arguments: [String]) throws {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                showsHelp = true
            case "--repository-root":
                repositoryRoot = try Self.nextValue(from: &iterator, for: argument)
            case "--spec-url":
                specURL = try Self.nextValue(from: &iterator, for: argument)
            case "--generator-version":
                generatorVersion = try Self.nextValue(from: &iterator, for: argument)
            default:
                throw UpdateError.unknownArgument(argument)
            }
        }
    }

    static let help = """
    OVERVIEW: Update Apogee's committed App Store Connect generated client sources.

    USAGE: update-app-store-connect-client [--repository-root <path>] [--spec-url <url>] [--generator-version <version>]

    OPTIONS:
      --repository-root <path>   Apogee repository root. Defaults to the current directory or an ancestor.
      --spec-url <url>           App Store Connect OpenAPI zip URL.
      --generator-version <ver>  Swift OpenAPI Generator version. Defaults to APOGEE_OPENAPI_GENERATOR_VERSION or 1.12.2.
      -h, --help                 Show help information.
    """

    private static func nextValue(
        from iterator: inout IndexingIterator<[String]>,
        for argument: String
    ) throws -> String {
        guard let value = iterator.next() else {
            throw UpdateError.missingValue(argument)
        }
        return value
    }
}

struct Updater {
    let options: Options
    let fileManager = FileManager.default
    let processRunner = ProcessRunner()

    func run() throws {
        let repositoryRoot = try resolvedRepositoryRoot()
        let workDirectory = repositoryRoot.appendingPath("/.build/apogee-openapi-generation")
        let generatorPackageDirectory = workDirectory.appendingPath("/GeneratorPackage")
        let generatorInputDirectory = generatorPackageDirectory.appendingPath("/Inputs")
        let generatedDirectory = generatorPackageDirectory.appendingPath("/GeneratedSources")
        let outputDirectory = repositoryRoot.appendingPath("/Sources/AppStoreConnectGenerated/GeneratedSources")
        let specJSON = workDirectory.appendingPath("/openapi.oas.json")
        let trimmedJSON = generatorInputDirectory.appendingPath("/openapi.json")
        let configURL = generatorInputDirectory.appendingPath("/openapi-generator-config.yaml")
        let sourceConfigURL = repositoryRoot.appendingPath("/Scripts/OpenAPIGeneration/openapi-generator-config.yaml")
        let trimScriptURL = repositoryRoot.appendingPath("/Scripts/trim-app-store-connect-openapi.swift")
        let specZipURL = fileManager.temporaryDirectory.appendingPathComponent(
            "apogee-app-store-connect-openapi-\(UUID().uuidString).zip"
        )

        try fileManager.createDirectory(at: generatorInputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: specZipURL) }

        try processRunner.run("curl", arguments: ["-fL", options.specURL, "-o", specZipURL.path])

        let openAPIData = try processRunner.capture(
            "unzip",
            arguments: ["-p", specZipURL.path, "openapi.oas.json"]
        )
        try openAPIData.write(to: specJSON)

        try processRunner.run(
            "swift",
            arguments: [trimScriptURL.path, specJSON.path, trimmedJSON.path],
            currentDirectory: repositoryRoot
        )
        try fileManager.copyReplacingItem(at: sourceConfigURL, to: configURL)
        try writeGeneratorPackageManifest(to: generatorPackageDirectory)

        try processRunner.run(
            "swift",
            arguments: [
                "run",
                "swift-openapi-generator",
                "generate",
                trimmedJSON.path,
                "--config",
                configURL.path,
                "--output-directory",
                generatedDirectory.path,
            ],
            currentDirectory: generatorPackageDirectory
        )

        try fileManager.copyReplacingItem(
            at: generatedDirectory.appendingPathComponent("Client.swift"),
            to: outputDirectory.appendingPathComponent("Client.swift")
        )
        try fileManager.copyReplacingItem(
            at: generatedDirectory.appendingPathComponent("Types.swift"),
            to: outputDirectory.appendingPathComponent("Types.swift")
        )

        let serverURL = outputDirectory.appendingPathComponent("Server.swift")
        if fileManager.fileExists(atPath: serverURL.path) {
            try fileManager.removeItem(at: serverURL)
        }

        print("Updated generated App Store Connect client sources.")
        print("Spec SHA-256: \(Self.sha256Hex(openAPIData))")
    }

    private func resolvedRepositoryRoot() throws -> URL {
        if let repositoryRoot = options.repositoryRoot {
            return URL(fileURLWithPath: repositoryRoot, isDirectory: true).standardizedFileURL
        }

        var candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
        while true {
            let hasGenerationConfig = fileManager.fileExists(
                atPath: candidate.appendingPath("/Scripts/OpenAPIGeneration/openapi-generator-config.yaml").path
            )
            let hasGeneratedTarget = fileManager.fileExists(
                atPath: candidate.appendingPath("/Sources/AppStoreConnectGenerated").path
            )
            if hasGenerationConfig, hasGeneratedTarget {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                throw UpdateError.repositoryRootNotFound
            }
            candidate = parent
        }
    }

    private func writeGeneratorPackageManifest(to packageDirectory: URL) throws {
        let manifest = """
        // swift-tools-version: 6.4

        import PackageDescription

        let package = Package(
            name: "ApogeeOpenAPIGeneration",
            platforms: [
                .macOS(.v15),
            ],
            dependencies: [
                .package(url: "https://github.com/apple/swift-openapi-generator", exact: "\(options.generatorVersion)"),
            ],
            targets: [
                .executableTarget(
                    name: "GenerationHost",
                    path: "Sources/GenerationHost"
                ),
            ]
        )
        """

        let hostSourceURL = packageDirectory.appendingPath("/Sources/GenerationHost/main.swift")
        try fileManager.createDirectory(at: hostSourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"Apogee OpenAPI generation host\")\n".write(to: hostSourceURL, atomically: true, encoding: .utf8)
        try manifest.write(to: packageDirectory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ProcessRunner {
    func run(
        _ command: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = currentDirectory
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(command: command, status: process.terminationStatus)
        }
    }

    func capture(
        _ command: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(command: command, status: process.terminationStatus)
        }
        return data
    }
}

enum UpdateError: Error, CustomStringConvertible {
    case commandFailed(command: String, status: Int32)
    case missingValue(String)
    case repositoryRootNotFound
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .commandFailed(command, status):
            "\(command) exited with status \(status)."
        case let .missingValue(argument):
            "Missing value for \(argument)."
        case .repositoryRootNotFound:
            "Could not find the Apogee repository root."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)."
        }
    }
}

extension FileManager {
    func copyReplacingItem(at sourceURL: URL, to destinationURL: URL) throws {
        if fileExists(atPath: destinationURL.path) {
            try removeItem(at: destinationURL)
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }
}

extension URL {
    func appendingPath(_ path: String) -> URL {
        path.split(separator: "/").reduce(self) { partialResult, component in
            partialResult.appendingPathComponent(String(component))
        }
    }
}
