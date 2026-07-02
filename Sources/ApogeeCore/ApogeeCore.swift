public enum ApogeeCore {
    public static let version = "0.1.0"
}

public enum OperationMode: Sendable, Hashable {
    case dryRun
    case apply
}

public enum Platform: String, Sendable, Hashable, Codable {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"
}

public enum AppLookup: Sendable, Hashable {
    case appID(String)
    case bundleID(String)
}

public enum UnsupportedCapability: String, Error, Sendable, CustomStringConvertible {
    case screenshotUpload
    case ciWorkflowSync

    public var description: String {
        switch self {
        case .screenshotUpload:
            "Screenshot upload is not enabled because it requires a proven asset reservation, binary upload, checksum commit, and async verification adapter."
        case .ciWorkflowSync:
            "Xcode Cloud workflow sync is visible in OpenAPI but is not implemented until Apogee has a dedicated workflow configuration model."
        }
    }
}
