/// Whether release automation only plans changes or also performs verified writes.
public enum OperationMode: Sendable, Hashable {
    case dryRun
    case apply
}

/// An App Store Connect platform; raw values match the API and configuration JSON.
public enum Platform: String, Sendable, Hashable, Codable {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"
}

/// An explicit app resource ID or a bundle ID that must resolve to exactly one app.
public enum AppLookup: Sendable, Hashable {
    case appID(String)
    case bundleID(String)
}

/// A capability that cannot yet execute through Apogee safely.
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
