import Darwin
import Foundation

struct LibraryJournalState: Codable {
    struct Upload: Codable {
        var image: LibraryImage
        var digest: String
        var committed: Bool
    }
    var schemaVersion = 1
    var target: String
    var uploads: [String: Upload] = [:]
    var originals: [String: [LibraryPlacement]] = [:]
}

final class AssetLibraryJournal {
    let root: URL
    var state: LibraryJournalState
    private var lockDescriptor: Int32 = -1

    init(recovery: ScreenshotRecovery, target: String, applying: Bool) throws {
        root = URL(fileURLWithPath: recovery.directory).standardizedFileURL
        state = .init(target: target)
        if FileManager.default.fileExists(atPath: root.path) {
            try ScreenshotFiles.requireRegular(root, directory: true)
        } else if applying {
            try ScreenshotFiles.requireRegular(root.deletingLastPathComponent(), directory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
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
        let file = root.appendingPathComponent("asset-library-state.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try ScreenshotFiles.requireRegular(file)
            guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 4 * 1_024 * 1_024 else {
                throw ScreenshotError.recoveryMismatch
            }
            state = try JSONDecoder().decode(LibraryJournalState.self, from: Data(contentsOf: file))
            guard state.schemaVersion == 1, state.target == target else {
                throw ScreenshotError.recoveryMismatch
            }
        } else if FileManager.default.fileExists(atPath: root.path) {
            guard try ScreenshotFiles.children(root).allSatisfy({ $0.lastPathComponent == "lock" }) else {
                throw ScreenshotError.recoveryMismatch
            }
            if applying {
                try persist()
            }
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
        let file = root.appendingPathComponent("asset-library-state.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try ScreenshotFiles.requireRegular(file)
        }
        try encoder.encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
