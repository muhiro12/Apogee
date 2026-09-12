import AppStoreConnectGenerated
import Foundation

public struct WebhookSyncConfiguration: Codable, Sendable, Hashable {
    public var webhooks: [DesiredWebhook]

    public init(webhooks: [DesiredWebhook]) {
        self.webhooks = webhooks
    }
}

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

public struct WebhookConfigurationLoader: Sendable {
    public init() {}

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

    public func secret(named name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable(name)
        }

        return value
    }
}
