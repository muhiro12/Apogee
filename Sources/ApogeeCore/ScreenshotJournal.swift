import Crypto
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotJournalState: Codable {
    struct Original: Codable {
        var screenshot: RemoteScreenshot
        var blob: String
    }
    var schemaVersion = 1
    var target: String
    var originals: [String: Original] = [:]
    var orders: [String: [String]] = [:]
    var sets: [String: String] = [:]
    var owned: [String: String] = [:]
}

final class ScreenshotJournal {
    let root: URL
    var state: ScreenshotJournalState
    private var lockDescriptor: Int32 = -1

    init(recovery: ScreenshotRecovery, target: String, applying: Bool) throws {
        root = URL(fileURLWithPath: recovery.directory).standardizedFileURL
        if FileManager.default.fileExists(atPath: root.path) {
            try ScreenshotFiles.requireRegular(root, directory: true)
        } else if applying {
            try ScreenshotFiles.requireRegular(root.deletingLastPathComponent(), directory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        state = .init(target: target)
        if applying {
            let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
            guard let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o077 == 0 else {
                throw ScreenshotError.recoveryMismatch
            }
            lockDescriptor = open(root.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                if lockDescriptor >= 0 {
                    close(lockDescriptor)
                }
                lockDescriptor = -1
                throw ScreenshotError.recoveryMismatch
            }
        }
        let file = root.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try ScreenshotFiles.requireRegular(file)
            guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 4 * 1_024 * 1_024 else {
                throw ScreenshotError.recoveryMismatch
            }
            state = try JSONDecoder().decode(ScreenshotJournalState.self, from: Data(contentsOf: file))
            guard state.schemaVersion == 1, state.target == target else {
                throw ScreenshotError.recoveryMismatch
            }
        } else if applying {
            let existing = try ScreenshotFiles.children(root).map(\.lastPathComponent)
            guard existing.allSatisfy({ $0 == "lock" }) else {
                throw ScreenshotError.recoveryMismatch
            }
            try persist()
        }
    }

    deinit {
        if lockDescriptor >= 0 {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
        }
    }

    func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: root.appendingPathComponent("state.json"), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent("state.json").path)
    }

    func originalData(_ screenshot: RemoteScreenshot) throws -> Data? {
        guard let original = state.originals[screenshot.id] else {
            return nil
        }
        guard original.screenshot.checksum == screenshot.checksum,
              original.screenshot.byteCount == screenshot.byteCount,
              original.blob.count == 64,
              original.blob.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw ScreenshotError.recoveryMismatch
        }
        let path = root.appendingPathComponent(original.blob)
        try ScreenshotFiles.requireRegular(path)
        guard (try path.resourceValues(forKeys: [.fileSizeKey])).fileSize == screenshot.byteCount else {
            throw ScreenshotError.recoveryMismatch
        }
        let data = try Data(contentsOf: path)
        guard data.count == screenshot.byteCount, ScreenshotImage.md5(data) == screenshot.checksum,
              Self.digest(data) == original.blob else {
            throw ScreenshotError.recoveryMismatch
        }
        return data
    }

    func backup(_ screenshots: [RemoteScreenshot], setID: String, candidates: [ScreenshotImage]) throws {
        for screenshot in screenshots where screenshot.state == "COMPLETE" {
            if try originalData(screenshot) != nil {
                continue
            }
            guard let image = candidates.first(where: { $0.checksum == screenshot.checksum && $0.data.count == screenshot.byteCount }) else {
                throw ScreenshotError.originalsMissing
            }
            let path = root.appendingPathComponent(image.digest)
            if FileManager.default.fileExists(atPath: path.path) {
                try ScreenshotFiles.requireRegular(path)
                guard try Data(contentsOf: path) == image.data else {
                    throw ScreenshotError.recoveryMismatch
                }
            } else {
                try image.data.write(to: path, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            state.originals[screenshot.id] = .init(screenshot: screenshot, blob: image.digest)
            try persist()
            guard try originalData(screenshot) != nil else {
                throw ScreenshotError.recoveryMismatch
            }
        }
        if state.orders[setID] == nil {
            state.orders[setID] = screenshots.map(\.id)
        }
        try persist()
    }

    func writeRestoreLayout(setID: String, locale: String, displayType: String) throws {
        let key = "\(locale)/\(displayType)"
        if let previous = state.sets[setID], previous != key {
            throw ScreenshotError.recoveryMismatch
        }
        state.sets[setID] = key
        try persist()
        var directory = root
        for component in ["restore", locale, displayType] {
            guard !component.isEmpty, component != ".", component != "..", !component.contains("/") else {
                throw ScreenshotError.recoveryMismatch
            }
            directory.appendPathComponent(component)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            try ScreenshotFiles.requireRegular(directory, directory: true)
        }
        for (index, id) in (state.orders[setID] ?? []).enumerated() {
            guard let original = state.originals[id], let data = try originalData(original.screenshot),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String? else {
                // Unfinished owned reservations never had recoverable original bytes.
                if state.owned[id] != nil {
                    continue
                }
                throw ScreenshotError.recoveryMismatch
            }
            let suffix = type == UTType.jpeg.identifier ? "jpg" : "png"
            let destination = directory.appendingPathComponent(String(format: "%03d.%@", index + 1, suffix))
            if FileManager.default.fileExists(atPath: destination.path) {
                try ScreenshotFiles.requireRegular(destination)
                guard try Data(contentsOf: destination) == data else {
                    throw ScreenshotError.recoveryMismatch
                }
            } else {
                try data.write(to: destination, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func originals(_ path: String?) throws -> [ScreenshotImage] {
        guard let path else {
            return []
        }
        var files: [ScreenshotImage] = []
        func visit(_ url: URL, depth: Int) throws {
            guard depth < 8, files.count < 1_000 else {
                throw ScreenshotError.invalidInput
            }
            for child in try ScreenshotFiles.children(url) {
                try ScreenshotFiles.requireRegular(child, directory: (try child.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true)
                if (try child.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                    try visit(child, depth: depth + 1)
                } else if ["png", "jpg", "jpeg"].contains(child.pathExtension.lowercased()) {
                    files.append(try ScreenshotImage(url: child))
                    guard files.reduce(0, { $0 + $1.data.count }) <= 512 * 1_024 * 1_024 else {
                        throw ScreenshotError.invalidInput
                    }
                }
            }
        }
        try visit(URL(fileURLWithPath: path), depth: 0)
        return files
    }
}
