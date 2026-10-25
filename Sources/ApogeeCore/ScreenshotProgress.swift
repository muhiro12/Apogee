import Foundation

/// A privacy-reduced observation of screenshot work, separate from its final plan.
///
/// Counts describe desired images checked during apply across the selected sets,
/// including reused images verified against the active API's contract. The Asset
/// Library reports processed metadata and spec IDs, not source checksums.
/// Reaching the total does not mean
/// deletion, ordering, or final verification has finished. Only the final set's
/// `completed` event confirms that.
public struct ScreenshotProgress: Sendable, Equatable {
    /// Work being attempted; processing and checksum waits have bounded observations.
    public enum Stage: String, Sendable {
        case planning
        case preparingRecovery
        case uploading
        case committing
        case processing
        case waitingForChecksum
        case verifyingReplacements
        case deletingObsolete
        case ordering
        case verifying
        case completed
    }

    public let stage: Stage
    public let locale: String
    public let displayType: String
    public let completedImages: Int
    public let totalImages: Int
    /// Monotonic elapsed time since the screenshot workflow began.
    public let elapsedSeconds: Double
    public let processingAttempt: Int?
    public let processingLimit: Int?

    public init(stage: Stage, locale: String, displayType: String,
                completedImages: Int, totalImages: Int, elapsedSeconds: Double,
                processingAttempt: Int? = nil, processingLimit: Int? = nil) {
        self.stage = stage
        self.locale = locale
        self.displayType = displayType
        self.completedImages = completedImages
        self.totalImages = totalImages
        self.elapsedSeconds = elapsedSeconds
        self.processingAttempt = processingAttempt
        self.processingLimit = processingLimit
    }
}
