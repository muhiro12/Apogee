import Foundation
import PackagePlugin

@main
struct ApogeeCommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try apogeeTool(context: context)
        let process = Process()
        process.executableURL = tool.url
        process.currentDirectoryURL = context.package.directoryURL
        process.arguments = forwardedArguments(arguments)

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ApogeeCommandPluginError.commandFailed(process.terminationStatus)
        }
    }

    private func apogeeTool(context: PluginContext) throws -> PluginContext.Tool {
        try context.tool(named: "apogee")
    }

    private func forwardedArguments(_ arguments: [String]) -> [String] {
        guard arguments.first == "--" else {
            return arguments
        }

        return Array(arguments.dropFirst())
    }
}

enum ApogeeCommandPluginError: Error, CustomStringConvertible {
    case commandFailed(Int32)

    var description: String {
        switch self {
        case let .commandFailed(status):
            "apogee exited with status \(status)."
        }
    }
}
