import Foundation
import FoldHarnessV1

public enum Discovered<Value: Sendable>: Sendable {
    case available(Value)
    case unavailable(String)
    case unsupported(String?)

    public var value: Value? {
        if case let .available(value) = self { return value }
        return nil
    }

    public var message: String? {
        switch self {
        case .available: return nil
        case let .unavailable(text): return text
        case let .unsupported(text): return text ?? "This engine does not report it."
        }
    }
}

public struct EngineOption: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let unavailableReason: String?
}

public struct EngineControl: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case toggle(Bool)
        case select([EngineOption], String?)
        case number(Double?, Double?, Double?)
    }

    public let id: String
    public let label: String
    public let description: String?
    public let kind: Kind
    public let unavailableReason: String?
}

public struct EngineModel: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let unavailableReason: String?
    public let efforts: [EngineOption]
    public let defaultEffortId: String?
    public let controls: [EngineControl]
}

public struct EngineCatalog: Sendable {
    public let models: [EngineModel]
    public let defaultModelId: String?
}

public struct EngineLimit: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let unit: String
    public let used: Double?
    public let limit: Double?
    public let usedPercent: Double?
    public let resetsAt: Date?
}

public struct EngineLimits: Sendable {
    public let planLabel: String?
    public let lines: [EngineLimit]
}

public struct Engine: Sendable, Identifiable {
    public let id: String
    public var label: String
    public var permissionSummary: String
    public var controls: [EngineControl]
    public var catalog: Discovered<EngineCatalog>
    public var limits: Discovered<EngineLimits>
    public var profileMessage: String?

    public var isUsable: Bool { catalog.value != nil }
}

enum EngineMapper {
    static func engine(id: String, profile: FHEngineProfileDiscovery) -> Engine {
        let value = profile.value
        return Engine(
            id: id,
            label: value?.label ?? id,
            permissionSummary: value.map(permissionSummary) ?? "",
            controls: (value?.controls ?? []).map(control),
            catalog: .unsupported(nil),
            limits: .unsupported(nil),
            profileMessage: profile.status == .available ? nil : (profile.message ?? "This engine is not available.")
        )
    }

    static func permissionSummary(_ profile: FHEngineProfile) -> String {
        let mode = profile.permissions.modes.first { $0.id == profile.permissions.defaultModeID }
        return mode?.label ?? profile.permissions.defaultModeID
    }

    static func catalog(_ discovery: FHModelCatalogDiscovery) -> Discovered<EngineCatalog> {
        switch discovery.status {
        case .available:
            guard let value = discovery.value else {
                return .unavailable("The engine returned no model catalog.")
            }
            let models = value.models
                .filter { $0.hidden != true }
                .map { model in
                    EngineModel(
                        id: model.id,
                        label: model.label,
                        description: model.description,
                        unavailableReason: model.unavailableReason
                            ?? (model.availability == .unavailable ? "The provider does not offer this model." : nil),
                        efforts: (model.effort?.options ?? []).map(option),
                        defaultEffortId: model.effort?.defaultOptionID,
                        controls: (model.controls ?? []).map(control)
                    )
                }
            return .available(EngineCatalog(models: models, defaultModelId: value.defaultModelID))
        case .unavailable:
            return .unavailable(discovery.message ?? "The model list is not available.")
        case .unsupported:
            return .unsupported(discovery.message)
        }
    }

    static func limits(_ discovery: FHLimitSnapshotDiscovery) -> Discovered<EngineLimits> {
        switch discovery.status {
        case .available:
            guard let value = discovery.value else { return .unavailable("The engine returned no limits.") }
            let lines = value.limits.map { limit in
                EngineLimit(
                    id: limit.id,
                    label: limit.label,
                    unit: limit.unit,
                    used: limit.used,
                    limit: limit.limit,
                    usedPercent: limit.usedPercent,
                    resetsAt: limit.resetsAt.flatMap(date)
                )
            }
            return .available(EngineLimits(planLabel: value.planLabel, lines: lines))
        case .unavailable:
            return .unavailable(discovery.message ?? "The limits are not available.")
        case .unsupported:
            return .unsupported(discovery.message)
        }
    }

    /// The sidecar writes JavaScript's ISO form, which carries milliseconds.
    static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func option(_ value: FHOptionElement) -> EngineOption {
        EngineOption(
            id: value.id,
            label: value.label,
            description: value.description,
            unavailableReason: value.unavailableReason
        )
    }

    static func control(_ value: FHControlElement) -> EngineControl {
        let kind: EngineControl.Kind
        switch value.kind {
        case .toggle:
            kind = .toggle(value.defaultValue?.boolValue ?? false)
        case .select:
            kind = .select((value.options ?? []).map(option), value.defaultValue?.stringValue)
        case .number:
            kind = .number(value.min, value.max, value.defaultValue?.doubleValue)
        }
        return EngineControl(
            id: value.id,
            label: value.label,
            description: value.description,
            kind: kind,
            unavailableReason: value.unavailableReason
        )
    }
}
