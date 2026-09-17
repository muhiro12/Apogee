import AppStoreConnectGenerated
import Crypto
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotImage: Sendable {
    let fileName: String
    let data: Data
    let checksum: String
    let digest: String

    init(url: URL) throws {
        try ScreenshotFiles.requireRegular(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64 * 1_024 * 1_024 else {
            throw ScreenshotError.invalidInput
        }
        let data = try Data(contentsOf: url)
        guard data.count == size,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 10_000, height <= 10_000,
              width * height <= 40_000_000,
              (properties[kCGImagePropertyHasAlpha] as? Bool) != true,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ScreenshotError.invalidInput
        }
        self.data = data
        checksum = Self.md5(data)
        digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        fileName = url.lastPathComponent
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ScreenshotFiles {
    static func requireRegular(_ url: URL, directory: Bool = false) throws {
        var current = url.standardizedFileURL
        while current.path != "/" {
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let allowedAliases = ["/var": "private/var", "/tmp": "private/tmp"]
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: current.path)
                guard let expected = allowedAliases[current.path], destination == expected || destination == "/" + expected else {
                    throw ScreenshotError.invalidInput
                }
            }
            current.deleteLastPathComponent()
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        guard directory ? values.isDirectory == true : values.isRegularFile == true else {
            throw ScreenshotError.invalidInput
        }
    }

    static func children(_ url: URL) throws -> [URL] {
        try requireRegular(url, directory: true)
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func load(_ path: String, platform: Platform) throws -> [(String, String, [ScreenshotImage])] {
        var result: [(String, String, [ScreenshotImage])] = []
        for locale in try children(URL(fileURLWithPath: path)) {
            for display in try children(locale) {
                let name = display.lastPathComponent
                guard Components.Schemas.ScreenshotDisplayType(rawValue: name) != nil else {
                    throw ScreenshotError.invalidInput
                }
                let validPlatform: Bool
                switch platform {
                case .iOS:
                    validPlatform = name.contains("IPHONE") || name.contains("IPAD") || name.contains("WATCH")
                case .macOS:
                    validPlatform = name == "APP_DESKTOP"
                case .tvOS:
                    validPlatform = name == "APP_APPLE_TV"
                case .visionOS:
                    validPlatform = name == "APP_APPLE_VISION_PRO"
                }
                guard validPlatform else {
                    throw ScreenshotError.invalidInput
                }
                let urls = try children(display)
                guard (1...10).contains(urls.count), result.count < 100 else {
                    throw ScreenshotError.invalidInput
                }
                let images = try urls.map { try ScreenshotImage(url: $0) }
                guard Set(images.map(\.checksum)).count == images.count else {
                    throw ScreenshotError.invalidInput
                }
                let totalBytes = result.flatMap { $0.2 }.reduce(0) { $0 + $1.data.count } + images.reduce(0) { $0 + $1.data.count }
                guard totalBytes <= 512 * 1_024 * 1_024 else {
                    throw ScreenshotError.invalidInput
                }
                result.append((locale.lastPathComponent, name, images))
            }
        }
        guard !result.isEmpty else {
            throw ScreenshotError.invalidInput
        }
        return result
    }
}
