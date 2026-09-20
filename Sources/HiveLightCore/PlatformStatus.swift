import Foundation

/// A Statuspage component state, as status.claude.com reports it. Unknown
/// values are kept verbatim — a state Statuspage adds later must still
/// surface rather than vanish.
public enum PlatformState: Equatable, Sendable {
    case operational, degraded, partialOutage, majorOutage, maintenance
    case other(String)

    init(raw: String) {
        switch raw {
        case "operational": self = .operational
        case "degraded_performance": self = .degraded
        case "partial_outage": self = .partialOutage
        case "major_outage": self = .majorOutage
        case "under_maintenance": self = .maintenance
        default: self = .other(raw)
        }
    }

    public var text: String {
        switch self {
        case .operational: return "operational"
        case .degraded: return "degraded performance"
        case .partialOutage: return "partial outage"
        case .majorOutage: return "major outage"
        case .maintenance: return "under maintenance"
        case .other(let raw): return raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    public var isHealthy: Bool { self == .operational }
}

/// One watched Claude product's current state.
public struct PlatformComponentStatus: Equatable, Sendable {
    public let label: String
    public let state: PlatformState

    public init(label: String, state: PlatformState) {
        self.label = label
        self.state = state
    }
}

/// The products a Claude Code user depends on, in display order. Matched by
/// Statuspage component id first (names get reworded — the API's carries its
/// hostname), then by name prefix in case a component is recreated.
private let watchedProducts: [(label: String, id: String, namePrefix: String)] = [
    ("Claude Code", "yyzkbfz2thpt", "Claude Code"),
    ("Claude API", "k8w3r06qmzrp", "Claude API"),
]

/// Decodes status.claude.com's `/api/v2/components.json` down to the watched
/// products. Tolerant like every other foreign payload here: anything
/// malformed or reshaped yields fewer rows or `[]`, never an error.
public func platformStatus(fromJSON data: Data) -> [PlatformComponentStatus] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let components = obj["components"] as? [[String: Any]] else { return [] }
    return watchedProducts.compactMap { product in
        let match = components.first { ($0["id"] as? String) == product.id }
            ?? components.first { ($0["name"] as? String)?.hasPrefix(product.namePrefix) == true }
        guard let raw = match?["status"] as? String else { return nil }
        return PlatformComponentStatus(label: product.label, state: PlatformState(raw: raw))
    }
}
