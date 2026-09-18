import Foundation

/// Keeps artifact requests isolated from API authorization and refuses redirects.
private final class BuildFeedbackArtifactDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Downloads feedback artifacts without App Store Connect authorization.
///
/// Artifact URLs are Apple-hosted, time limited, and already carry their own access
/// grant, so no bearer token, cookie, or stored credential is attached to the request.
enum BuildFeedbackArtifactTransport {
    static let byteLimit = 32 * 1_024 * 1_024

    static func validate(_ artifact: BuildFeedbackArtifact, now: Date = .now) throws {
        guard artifact.url.utf8.count < 16_384,
              let url = URLComponents(string: artifact.url), url.scheme == "https",
              let host = url.host?.lowercased(),
              host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com"),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else {
            throw BuildFeedbackError.unsafeArtifact
        }
        if let expirationDate = artifact.expirationDate, expirationDate <= now {
            throw BuildFeedbackError.unsafeArtifact
        }
    }

    /// Returns the downloaded bytes and the file extension proven by their signature.
    static func imageExtension(_ data: Data) throws -> String {
        let prefix = [UInt8](data.prefix(8))
        if prefix.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if prefix.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        throw BuildFeedbackError.unsafeArtifact
    }

    static func download(_ artifact: BuildFeedbackArtifact) async throws -> Data {
        try Task.checkCancellation()
        try validate(artifact)
        guard let url = URL(string: artifact.url) else {
            throw BuildFeedbackError.unsafeArtifact
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: BuildFeedbackArtifactDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  !data.isEmpty, data.count <= byteLimit else {
                throw BuildFeedbackError.unsafeArtifact
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw BuildFeedbackError.unsafeArtifact
        }
    }
}

/// Writes downloaded artifacts below one explicit private destination directory.
///
/// Files are laid out as `<kind>/<submission id>/<index>.<extension>` and are written
/// without overwriting, so a destination reused after a partial export fails loudly
/// instead of replacing earlier evidence.
struct BuildFeedbackExporter {
    let root: URL

    init(export: BuildFeedbackExport) throws {
        guard !export.directory.isEmpty else {
            throw BuildFeedbackError.invalidExportDestination
        }
        root = URL(fileURLWithPath: export.directory).standardizedFileURL
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try ScreenshotFiles.requireRegular(root, directory: true)
            } else {
                try ScreenshotFiles.requireRegular(root.deletingLastPathComponent(), directory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
            }
        } catch {
            throw BuildFeedbackError.invalidExportDestination
        }
    }

    /// Downloads and stores every artifact of one feedback collection.
    ///
    /// Summaries are returned with the written relative paths recorded. Artifact
    /// locations stay in the result for the caller; they are never written to disk.
    func export(_ entries: [BuildFeedbackSummary], kind: String,
                download: (BuildFeedbackArtifact) async throws -> Data) async throws -> [BuildFeedbackSummary] {
        var exported: [BuildFeedbackSummary] = []
        for var entry in entries {
            guard !entry.artifacts.isEmpty else {
                exported.append(entry)
                continue
            }
            try Task.checkCancellation()
            let relative = try relativePath(kind: kind, submissionID: entry.id)
            // The directory is created only once a download succeeds, so a refused or failed
            // artifact leaves no empty evidence tree behind.
            var directory: URL?
            var files: [String] = []
            for (index, artifact) in entry.artifacts.enumerated() {
                try Task.checkCancellation()
                let data = try await download(artifact)
                let name = String(format: "%02d", index + 1) + "." + (try BuildFeedbackArtifactTransport.imageExtension(data))
                let created = try directory ?? makeDirectory(relative)
                directory = created
                let file = created.appendingPathComponent(name)
                do {
                    try data.write(to: file, options: [.withoutOverwriting])
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    throw BuildFeedbackError.exportConflict
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                files.append("\(relative)/\(name)")
            }
            entry.exportedFiles = files
            exported.append(entry)
        }
        return exported
    }

    private func relativePath(kind: String, submissionID: String) throws -> String {
        let safe = !submissionID.isEmpty && submissionID.utf8.count <= 128
            && submissionID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard safe else {
            throw BuildFeedbackError.unsafeArtifact
        }
        return "\(kind)/\(submissionID)"
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let directory = relative.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try ScreenshotFiles.requireRegular(directory, directory: true)
        } catch {
            throw BuildFeedbackError.invalidExportDestination
        }
        return directory
    }
}
