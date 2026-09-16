import ApogeeCore
import ArgumentParser
import Foundation

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
}

enum OutputMode: String {
    case readOnly = "read-only"
    case dryRun = "dry-run"
    case apply
    case local

    init(_ mode: OperationMode) {
        self = mode == .apply ? .apply : .dryRun
    }
}

struct RequestedTarget {
    let lookup: AppLookup
    var version: String?
    var platform: Platform?

    var object: [String: Any] {
        let appID: String?
        let bundleID: String?
        switch lookup {
        case let .appID(value):
            appID = value
            bundleID = nil
        case let .bundleID(value):
            appID = nil
            bundleID = value
        }
        return [
            "appID": nullable(appID), "bundleID": nullable(bundleID),
            "version": nullable(version), "platform": nullable(platform?.rawValue),
        ]
    }
}

struct OutputOptions: ParsableArguments {
    @Option(help: "Output format: text or json. JSON is emitted only after success.")
    var output: OutputFormat = .text

    func render(
        _ plan: ReleasePlan,
        command: String,
        mode: OutputMode,
        requestedTarget: RequestedTarget? = nil
    ) throws -> String {
        try Task.checkCancellation()
        guard output == .json else {
            return PlanRenderer().render(plan)
        }
        let mutations = plan.actions.filter { action in
            switch action.kind {
            case .create, .update, .delete, .attach:
                true
            case .verify, .unchanged, .unsupported:
                false
            }
        }
        let checks: [[String: Any]] = plan.actions.filter { $0.kind == .verify }.map { action in
            [
                "resource": action.resource,
                "locale": nullable(action.locale),
                "status": "passed",
                "scope": mode == .local ? "local-validation" : "read-back",
                "details": nullable(action.desiredValue),
            ]
        }
        return try json([
            "schemaVersion": 1, "kind": "release-plan", "command": command, "mode": mode.rawValue,
            "requestedTarget": nullable(requestedTarget?.object),
            "target": nullable(plan.target.map { target in
                ["app": appObject(target.app), "version": nullable(target.version.map(versionIdentityObject))]
            }),
            "plan": [
                "title": plan.title, "token": plan.token,
                "hasChanges": plan.hasChanges, "plannedMutationCount": mutations.count,
                "hasDestructiveActions": plan.hasDestructiveActions,
                "hasUnsupportedActions": plan.actions.contains { $0.kind == .unsupported },
                "actions": plan.actions.map { action -> [String: Any] in
                    [
                        "kind": action.kind.rawValue, "resource": action.resource,
                        "locale": nullable(action.locale), "field": nullable(action.fieldIdentifier),
                        "fieldLabel": nullable(action.field),
                        "currentValue": nullable(action.currentValue), "desiredValue": nullable(action.desiredValue),
                        "isDestructive": action.isDestructive,
                    ]
                },
            ],
            "verification": ["status": checks.isEmpty ? "not-performed" : "performed", "checks": checks],
        ])
    }

    func render(_ status: ReleaseStatus, requestedTarget: RequestedTarget) throws -> String {
        try Task.checkCancellation()
        guard output == .json else {
            return PlanRenderer().render(status)
        }
        return try json([
            "schemaVersion": 1, "kind": "release-status", "command": "release-status", "mode": "read-only",
            "requestedTarget": requestedTarget.object,
            "target": ["app": appObject(status.app), "version": versionObject(status.version)],
            "status": [
                "build": nullable(status.build.map { build in
                    ["id": build.id, "version": nullable(build.version), "processingState": nullable(build.processingState)]
                }),
                "reviewSubmissions": status.reviewSubmissions.sorted { $0.id < $1.id }.map { submission -> [String: Any] in
                    [
                        "id": submission.id, "state": nullable(submission.state),
                        "platform": nullable(submission.platform?.rawValue),
                        "appStoreVersionID": nullable(submission.appStoreVersionID),
                        "itemIDs": nullable(submission.itemIDs),
                    ]
                },
            ],
        ])
    }
}

private func appObject(_ app: AppStoreConnectApp) -> [String: Any] {
    ["id": app.id, "bundleID": nullable(app.bundleID), "name": nullable(app.name)]
}

private func versionIdentityObject(_ version: AppStoreConnectVersion) -> [String: Any] {
    [
        "id": version.id, "versionString": nullable(version.versionString),
        "platform": nullable(version.platform?.rawValue),
    ]
}

private func versionObject(_ version: AppStoreConnectVersion) -> [String: Any] {
    var object = versionIdentityObject(version)
    object["state"] = nullable(version.state)
    object["releaseType"] = nullable(version.releaseType)
    object["earliestReleaseDate"] = nullable(version.earliestReleaseDate?.ISO8601Format(.init(includingFractionalSeconds: true)))
    return object
}

private func nullable<T>(_ value: T?) -> Any {
    value as Any? ?? NSNull()
}

private func json(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
