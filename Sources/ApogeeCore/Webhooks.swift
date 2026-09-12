import AppStoreConnectGenerated
import Foundation

/// The complete desired webhook list for the selected app.
///
/// Remote webhooks absent from this list are planned for deletion.
public struct WebhookSyncConfiguration: Codable, Sendable, Hashable {
    public var webhooks: [DesiredWebhook]

    public init(webhooks: [DesiredWebhook]) {
        self.webhooks = webhooks
    }
}

/// Desired settings for a named webhook, including the name of its secret variable.
///
/// `rotateSecret` defaults to false. Set it only for an intended rotation and remove
/// it after success; the remote secret cannot be read back or compared.
public struct DesiredWebhook: Codable, Sendable, Hashable {
    public var name: String
    public var url: String
    public var eventTypes: [String]
    public var enabled: Bool
    public var secretEnvironmentVariable: String
    public var rotateSecret: Bool

    public init(
        name: String,
        url: String,
        eventTypes: [String],
        enabled: Bool = true,
        secretEnvironmentVariable: String,
        rotateSecret: Bool = false
    ) {
        self.name = name
        self.url = url
        self.eventTypes = eventTypes
        self.enabled = enabled
        self.secretEnvironmentVariable = secretEnvironmentVariable
        self.rotateSecret = rotateSecret
    }

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case eventTypes
        case enabled
        case secretEnvironmentVariable
        case rotateSecret
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        eventTypes = try container.decode([String].self, forKey: .eventTypes)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        secretEnvironmentVariable = try container.decode(String.self, forKey: .secretEnvironmentVariable)
        rotateSecret = try container.decodeIfPresent(Bool.self, forKey: .rotateSecret) ?? false
    }
}

/// Decodes webhook JSON and validates names, HTTPS endpoints, and known event types.
public struct WebhookConfigurationLoader: Sendable {
    public init() {}

    /// Loads a complete desired configuration and validates its basic shape.
    ///
    /// Duplicate names and remote differences are checked by release automation.
    /// Unreadable or malformed JSON can throw Foundation errors.
    public func load(from path: String) throws -> WebhookSyncConfiguration {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ApogeeError.invalidPath(path)
        }

        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(WebhookSyncConfiguration.self, from: data)
        for webhook in configuration.webhooks {
            guard !webhook.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !webhook.secretEnvironmentVariable.isEmpty,
                  !webhook.eventTypes.isEmpty,
                  let url = URLComponents(string: webhook.url),
                  url.scheme == "https", url.host?.isEmpty == false else {
                throw ApogeeError.invalidWebhookConfiguration
            }
            for eventType in webhook.eventTypes where Components.Schemas.WebhookEventType(rawValue: eventType) == nil {
                throw ApogeeError.invalidWebhookEventType(eventType)
            }
        }
        return configuration
    }
}

/// A captured environment used to resolve webhook secrets only when applying changes.
///
/// Descriptions redact values. The accessor returns the actual secret and must not be logged.
public struct SecretEnvironment: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private var values: [String: String]

    public var description: String {
        "SecretEnvironment(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    /// Returns a nonempty secret or throws for a missing environment variable.
    ///
    /// The returned string is sensitive even though this container's descriptions are redacted.
    public func secret(named name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable(name)
        }

        return value
    }
}
