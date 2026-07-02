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
            action.kind != .unchanged
        }
    }

    public var hasDestructiveActions: Bool {
        actions.contains { action in
            action.isDestructive
        }
    }

    public var token: String {
        let stableText = actions
            .map { "\($0.kind.rawValue)|\($0.resource)|\($0.field ?? "")|\($0.locale ?? "")|\($0.isDestructive)" }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(stableText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
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

    public func render(_ plan: ReleasePlan) -> String {
        var lines = [plan.title, "Plan token: \(plan.token)"]

        if plan.actions.isEmpty {
            lines.append("No actions.")
            return lines.joined(separator: "\n")
        }

        for action in plan.actions {
            var parts = ["- \(action.kind.rawValue.uppercased())", action.resource]

            if let locale = action.locale {
                parts.append("[\(locale)]")
            }

            if let field = action.field {
                parts.append(field)
            }

            if action.isDestructive {
                parts.append("(destructive)")
            }

            lines.append(parts.joined(separator: " "))

            if action.currentValue != action.desiredValue {
                if let currentValue = action.currentValue {
                    lines.append("  current: \(oneLine(currentValue))")
                }

                if let desiredValue = action.desiredValue {
                    lines.append("  desired: \(oneLine(desiredValue))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func oneLine(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        if collapsed.count > 160 {
            return "\(collapsed.prefix(157))..."
        }

        return collapsed
    }
}
