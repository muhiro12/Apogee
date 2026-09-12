import Foundation

/// A provisional local screenshot group, identified by locale and display directory.
public struct ScreenshotSet: Sendable, Hashable {
    public var locale: String
    public var displayType: String
    public var files: [ScreenshotFile]

    public init(locale: String, displayType: String, files: [ScreenshotFile]) {
        self.locale = locale
        self.displayType = displayType
        self.files = files
    }
}

/// Provisional file inventory information, not a validated or uploaded screenshot.
public struct ScreenshotFile: Sendable, Hashable {
    public var path: String
    public var fileName: String
    public var byteCount: Int

    public init(path: String, fileName: String, byteCount: Int) {
        self.path = path
        self.fileName = fileName
        self.byteCount = byteCount
    }
}

/// Inventories local screenshot files for planning only.
///
/// This provisional loader does not validate image content, dimensions, or upload readiness.
public struct ScreenshotLoader: Sendable {
    public init() {}

    /// Lists PNG and JPEG paths under locale/display-type directories in sorted order.
    ///
    /// This provisional inventory reads file sizes only and cannot prove upload readiness.
    public func load(from path: String) throws -> [ScreenshotSet] {
        let rootURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ApogeeError.invalidPath(path)
        }

        let localeURLs = try directoryChildren(of: rootURL)
        var sets: [ScreenshotSet] = []

        for localeURL in localeURLs {
            for displayTypeURL in try directoryChildren(of: localeURL) {
                let files = try FileManager.default.contentsOfDirectory(
                    at: displayTypeURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                .filter { url in
                    ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { url in
                    let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    return ScreenshotFile(path: url.path, fileName: url.lastPathComponent, byteCount: byteCount)
                }

                sets.append(.init(
                    locale: localeURL.lastPathComponent,
                    displayType: displayTypeURL.lastPathComponent,
                    files: files
                ))
            }
        }

        return sets
    }

    private func directoryChildren(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { childURL in
            ((try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
