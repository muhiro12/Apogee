import Foundation

/// Read-only metadata for one resolved app version, preserving complete remote values.
///
/// Nil fields mean unavailable or unset; empty strings remain distinct. A snapshot
/// may contain unpublished text and is neither an import plan nor a remote lock.
public struct MetadataSnapshot: Sendable, Hashable {
    public var app: AppStoreConnectApp
    public var version: AppStoreConnectVersion
    public var localizations: [AppStoreConnectLocalization]

    public init(
        app: AppStoreConnectApp,
        version: AppStoreConnectVersion,
        localizations: [AppStoreConnectLocalization]
    ) {
        self.app = app
        self.version = version
        self.localizations = localizations
    }
}
