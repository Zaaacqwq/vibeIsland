import Foundation
import OpenIslandCore

/// Single source of truth for the Agents usage-panel provider cards: their
/// default display order and per-provider icons. Shared by the pager (which
/// renders the cards) and the settings reorder page (which edits the order).
///
/// The Summary card is pinned first and is not part of this list.
enum AgentUsageProviderCatalog {
    /// Reorderable providers, in default display order.
    static let defaultOrder: [AgentUsageProviderID] = [
        .claude, .codex, .antigravity, .opencode, .cursor, .copilot, .gemini,
    ]

    static var defaultOrderRawValues: [String] { defaultOrder.map(\.rawValue) }

    /// How many providers the *notch header* may show at once.
    ///
    /// The header strip shares its row with the tab buttons and the
    /// timer/settings controls, and each provider contributes an icon plus two
    /// or more percentage cells. Past two groups the cells start truncating, so
    /// the header selection is capped here. The Agents panel has no such cap —
    /// it pages through cards instead.
    static let headerProviderLimit = 2

    /// Providers the header should render, from the persisted raw-value list.
    /// Applies the same drop-unknown/de-duplicate rules as `normalizedOrder`,
    /// then clamps to `headerProviderLimit`. Unlike the panel order this does
    /// **not** append missing providers — the header shows only what was picked.
    static func normalizedHeaderProviders(_ raw: [String]) -> [AgentUsageProviderID] {
        var seen = Set<AgentUsageProviderID>()
        var result: [AgentUsageProviderID] = []
        for rawValue in raw {
            guard let id = AgentUsageProviderID(rawValue: rawValue),
                  defaultOrder.contains(id),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
            if result.count == headerProviderLimit { break }
        }
        return result
    }

    /// Reconciles a persisted raw-value list against the known providers: drops
    /// unknown/duplicate ids and appends any provider missing from the stored
    /// order, so a newly added provider still appears without a manual reset.
    static func normalizedOrder(_ raw: [String]) -> [AgentUsageProviderID] {
        var seen = Set<AgentUsageProviderID>()
        var result: [AgentUsageProviderID] = []
        for rawValue in raw {
            guard let id = AgentUsageProviderID(rawValue: rawValue),
                  defaultOrder.contains(id),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        for id in defaultOrder where !seen.contains(id) {
            result.append(id)
        }
        return result
    }

    /// Notch card icon: an asset-catalog name (nil → use the SF Symbol fallback)
    /// plus the SF Symbol name. These marks are `template`-rendered so they show
    /// as a tint (white) on the dark notch.
    static func icon(for id: AgentUsageProviderID) -> (asset: String?, system: String) {
        switch id {
        case .claude: return ("claude-icon", "sparkles")
        case .codex: return ("codex-icon", "terminal")
        case .opencode: return ("opencode-icon", "chevron.left.forwardslash.chevron.right")
        case .gemini: return ("gemini-icon", "sparkle")
        case .antigravity: return ("antigravity-icon", "triangle")
        case .copilot: return ("copilot-icon", "chevron.left.slash.chevron.right")
        case .cursor: return ("cursor-icon", "cursorarrow.rays")
        case .summary: return (nil, "sparkles")
        }
    }

    /// Full-color brand mark for use in Settings, which follows the system
    /// light/dark appearance (the template notch marks would read as flat gray in
    /// light mode). Returns nil for providers without a bundled brand image.
    static func settingsIconAsset(for id: AgentUsageProviderID) -> String? {
        switch id {
        case .claude: return "claude-brand"
        case .codex: return "codex-brand"
        case .opencode: return "opencode-brand"
        case .gemini: return "gemini-brand"
        case .antigravity: return "antigravity-brand"
        case .copilot: return "copilot-brand"
        case .cursor: return "cursor-brand"
        case .summary: return nil
        }
    }
}
