import Foundation

/// A screenshot set observed under one existing App Store localization.
public struct RemoteScreenshotSet: Sendable, Hashable, Codable {
    public var id: String
    public var displayType: String

    public init(id: String, displayType: String) {
        self.id = id
        self.displayType = displayType
    }
}

/// A remote screenshot. Upload URLs are intentionally excluded from persisted recovery records.
public struct RemoteScreenshot: Sendable, Hashable, Codable {
    public var id: String
    public var fileName: String
    public var byteCount: Int
    public var checksum: String?
    public var state: String

    public init(id: String, fileName: String, byteCount: Int, checksum: String?, state: String) {
        self.id = id
        self.fileName = fileName
        self.byteCount = byteCount
        self.checksum = checksum
        self.state = state
    }
}

/// A time-limited asset upload instruction, never an App Store API request.
public struct ScreenshotUploadOperation: Sendable {
    public var method: String
    public var url: String
    public var offset: Int
    public var length: Int
    public var headers: [String: String]

    public init(method: String, url: String, offset: Int, length: Int, headers: [String: String]) {
        self.method = method
        self.url = url
        self.offset = offset
        self.length = length
        self.headers = headers
    }
}

/// Opt-in adapter boundary for screenshot operations. Mutation methods write immediately.
/// Collections must be complete, ordered, and scoped to the requested parent resource.
public protocol ScreenshotAPI: Sendable {
    func screenshotSets(localizationID: String) async throws -> [RemoteScreenshotSet]
    func screenshots(setID: String) async throws -> [RemoteScreenshot]
    func createScreenshotSet(localizationID: String, displayType: String) async throws -> RemoteScreenshotSet
    func reserveScreenshot(setID: String, fileName: String, byteCount: Int) async throws -> (RemoteScreenshot, [ScreenshotUploadOperation])
    func uploadScreenshotPart(_ data: Data, operation: ScreenshotUploadOperation) async throws
    func commitScreenshot(id: String, checksum: String) async throws
    func screenshot(id: String) async throws -> RemoteScreenshot
    func deleteScreenshot(id: String) async throws
    func orderScreenshots(setID: String, ids: [String]) async throws
}

/// Explicit private storage for interrupted-run recovery.
///
/// Asset Library operations retain placement identities and shared remote images.
/// `originalsPath` is used only by legacy custom `ScreenshotAPI` adapters.
public struct ScreenshotRecovery: Sendable {
    public var directory: String
    public var originalsPath: String?

    public init(directory: String, originalsPath: String? = nil) {
        self.directory = directory
        self.originalsPath = originalsPath
    }
}

/// Screenshot-specific failures; remote writes may already have occurred.
public enum ScreenshotError: Error, Sendable, Equatable, LocalizedError {
    case invalidInput
    /// The display class is unknown or unavailable in Apple's current reference data.
    case unsupportedDisplayType
    case incompleteInventory
    case recoveryRequired
    case recoveryMismatch
    case originalsMissing
    case unrecoverableReplacementRequiresConfirmation
    case setCapacityExceeded
    case unsafeUpload
    case processingFailed
    case processingTimedOut
    case remoteChanged

    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            "Invalid screenshot input: use regular PNG/JPEG images, valid display types, and 1–10 files per selected set."
        case .unsupportedDisplayType:
            "Unsupported screenshot display: use an App Asset Library display class such as IPHONE_DUO. Legacy APP_* screenshot directories must be migrated to display classes. The class must be available for this platform in Apple's current reference data. See docs/screenshots.md."
        case .incompleteInventory:
            "Screenshot inventory is incomplete, ambiguous, or contains unrelated unfinished assets."
        case .recoveryRequired:
            "Screenshot apply requires an explicit private recovery directory."
        case .recoveryMismatch:
            "The recovery directory does not match this target or contains invalid recovery files."
        case .originalsMissing:
            "Verified original files are required before deleting existing screenshots. Supply originals matching their size and checksum."
        case .unrecoverableReplacementRequiresConfirmation:
            "This set can be replaced by uploading before deleting, but its previous composition could not be restored afterwards. Confirm the unrecoverable replacement explicitly, or supply verified originals."
        case .setCapacityExceeded:
            "The screenshots exceed the target's current capacity. Reduce the selected image count. Legacy custom adapters may require verified originals when existing and replacement images cannot fit together."
        case .unsafeUpload:
            "Screenshot upload instructions are invalid, expired, or the asset transfer failed. Inspect the recovery directory before retrying."
        case .processingFailed:
            "Apple rejected screenshot processing or the asset did not match its verification contract. Recovery files are retained; no rollback is claimed."
        case .processingTimedOut:
            "Screenshot processing is still incomplete. Recovery files are retained; inspect remote state and obtain a fresh plan before retrying."
        case .remoteChanged:
            "Remote screenshot state changed or failed read-back. Stop other writers and obtain a fresh plan before retrying."
        }
    }
}
