import ApogeeCore
import Foundation

enum ScreenshotProgressOutput {
    static func write(_ text: String) {
        // A closed progress stream must not abort a guarded release operation.
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }

    static func render(_ event: ScreenshotProgress) -> String {
        let elapsed = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), event.elapsedSeconds)
        var text = "screenshots [\(label(event.locale))/\(label(event.displayType))] \(event.stage.rawValue)"
            + " verified=\(event.completedImages)/\(event.totalImages) elapsed=\(elapsed)s"
        if let attempt = event.processingAttempt, let limit = event.processingLimit {
            text += " observation=\(attempt)/\(limit)"
        }
        return text
    }

    private static func label(_ value: String) -> String {
        guard !value.isEmpty, value.utf8.count <= 64,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return "unknown"
        }
        return value
    }
}
