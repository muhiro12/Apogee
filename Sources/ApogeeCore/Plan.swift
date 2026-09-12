import Crypto
import Foundation

public struct ReleasePlan: Sendable, Hashable {
    public var title: String
    public var actions: [PlannedAction]

    public init(title: String, actions: [PlannedAction]) {
        self.title = title
        self.actions = actions
    }

    public var hasChanges: Bool {
        actions.contains { action in
            switch action.kind {
            case .create, .update, .delete, .attach:
                true
            case .verify, .unchanged, .unsupported:
                false
            }
        }
    }

    public var hasDestructiveActions: Bool {
        actions.contains { action in
            action.isDestructive
        }
    }

    public var token: String {
        let planParts = [
            Self.tokenPart("ReleasePlanTokenV2"),
            Self.tokenPart(title),
        ] + actions.map(Self.tokenText(for:)).sorted()
        let stableText = planParts.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(stableText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static func fingerprint(of value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private static func tokenText(for action: PlannedAction) -> String {
        [
            Self.tokenPart(action.kind.rawValue),
            Self.tokenPart(action.resource),
            Self.tokenPart(action.locale),
            Self.tokenPart(action.field),
            Self.tokenPart(action.currentValue),
            Self.tokenPart(action.desiredValue),
            Self.tokenPart(action.isDestructive.description),
        ].joined(separator: "\n")
    }

    private static func tokenPart(_ value: String?) -> String {
        let value = value ?? ""
        return "\(value.utf8.count):\(value)"
    }
}

public struct PlannedAction: Sendable, Hashable {
    public var kind: PlannedActionKind
    public var resource: String
    public var locale: String?
    public var field: String?
    public var currentValue: String?
    public var desiredValue: String?
    public var isDestructive: Bool

    public init(
        kind: PlannedActionKind,
        resource: String,
        locale: String? = nil,
        field: String? = nil,
        currentValue: String? = nil,
        desiredValue: String? = nil,
        isDestructive: Bool = false
    ) {
        self.kind = kind
        self.resource = resource
        self.locale = locale
        self.field = field
        self.currentValue = currentValue
        self.desiredValue = desiredValue
        self.isDestructive = isDestructive
    }
}

public enum PlannedActionKind: String, Sendable, Hashable {
    case create
    case update
    case delete
    case attach
    case verify
    case unchanged
    case unsupported
}

public struct PlanRenderer: Sendable {
    public init() {}

    public func render(_ status: ReleaseStatus) -> String {
        var lines = [
            "App: \(status.app.id) (\(status.app.bundleID ?? "unknown bundle ID"))",
            "Version: \(status.version.versionString ?? "unknown") [\(status.version.platform?.rawValue ?? "unknown platform")]",
            "App Store state: \(status.version.state ?? "unknown")",
            "Release type: \(status.version.releaseType ?? "unknown")",
            "Earliest release date (UTC): \(status.version.earliestReleaseDate?.ISO8601Format() ?? "not set")",
            "Build: \(status.build?.version ?? status.build?.id ?? "not attached")",
            "Build processing state: \(status.build?.processingState ?? "unknown")",
        ]
        if status.reviewSubmissions.isEmpty {
            lines.append("Review submission: none for this version")
        }
        for submission in status.reviewSubmissions.sorted(by: { $0.id < $1.id }) {
            lines.append("Review submission: \(submission.id) [\(submission.state ?? "unknown")]")
        }
        return lines.map { oneLine($0) }.joined(separator: "\n")
    }

    public func render(_ plan: ReleasePlan) -> String {
        var lines = [oneLine(plan.title), "Plan token: \(plan.token)"]

        if plan.actions.isEmpty {
            lines.append("No actions.")
            return lines.joined(separator: "\n")
        }

        for action in plan.actions {
            var parts = ["- \(action.kind.rawValue.uppercased())", oneLine(action.resource)]

            if let locale = action.locale {
                parts.append("[\(oneLine(locale))]")
            }

            if let field = action.field {
                parts.append(oneLine(field))
            }

            if action.isDestructive {
                parts.append("(destructive)")
            }

            lines.append(parts.joined(separator: " "))

            if action.currentValue != action.desiredValue {
                if let currentValue = action.currentValue {
                    lines.append("  current: \(oneLine(currentValue, truncate: false))")
                }

                if let desiredValue = action.desiredValue {
                    lines.append("  desired: \(oneLine(desiredValue, truncate: false))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func oneLine(_ text: String, truncate: Bool = true) -> String {
        let collapsed = text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x08:
                "\\b"
            case 0x09:
                "\\t"
            case 0x0A:
                "\\n"
            case 0x0D:
                "\\r"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                default:
                    String(scalar)
                }
            }
        }
        .joined()

        if truncate && collapsed.count > 160 {
            return "\(collapsed.prefix(157))..."
        }

        return collapsed
    }
}
