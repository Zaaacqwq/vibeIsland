/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import OpenIslandCore
import SwiftUI

/// Compact Claude + Codex rate-limit usage badges (e.g. `5h 42%`, `7d 18%`).
/// Shared between the Agents Home-embed header and the open-notch header
/// context widget so both render identically. Extracted from `NotchAgentsView`.
struct AgentUsageBadges: View {
    let claude: ClaudeUsageSnapshot?
    let codex: CodexUsageSnapshot?

    var hasClaude: Bool { claude.map { !$0.isEmpty } ?? false }
    var hasCodex: Bool { codex.map { !$0.isEmpty } ?? false }
    var hasAny: Bool { hasClaude || hasCodex }

    var body: some View {
        HStack(spacing: 5) {
            if let claude, hasClaude {
                claudeBadges(claude)
            }
            if let codex, hasCodex {
                codexBadges(codex)
            }
        }
    }

    @ViewBuilder
    private func claudeBadges(_ usage: ClaudeUsageSnapshot) -> some View {
        HStack(spacing: 3) {
            Image("claude-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .help("Claude usage")
            if let five = usage.fiveHour {
                badge(
                    title: "5h",
                    percent: five.roundedUsedPercentage,
                    warn: five.usedPercentage >= 80,
                    help: String(localized: "Claude 5-hour limit used")
                )
            }
            if let week = usage.sevenDay {
                badge(
                    title: "7d",
                    percent: week.roundedUsedPercentage,
                    warn: week.usedPercentage >= 80,
                    help: String(localized: "Claude 7-day limit used")
                )
            }
        }
    }

    @ViewBuilder
    private func codexBadges(_ usage: CodexUsageSnapshot) -> some View {
        HStack(spacing: 3) {
            Image("codex-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .help("Codex usage")
            ForEach(usage.windows) { window in
                badge(
                    title: window.label,
                    percent: window.roundedUsedPercentage,
                    warn: window.usedPercentage >= 80,
                    help: String(
                        format: String(localized: "Codex %@ limit used"),
                        notchLocalized(window.label)
                    )
                )
            }
        }
    }

    private func badge(title: String, percent: Int, warn: Bool, help: String) -> some View {
        // Debug override: preview the capped "MAX" styling on every badge.
        let effectivePercent = Defaults[.debugForceUsageMax] ? 100 : percent
        let effectiveWarn = warn || Defaults[.debugForceUsageMax]
        // At the cap, show "MAX" instead of "100%" — three chars fit the pill
        // without the four-char "100%" getting compressed/truncated.
        let localizedTitle = notchLocalized(title)
        let value = effectivePercent >= 100
            ? "\(localizedTitle) \(notchLocalized("MAX"))"
            : "\(localizedTitle) \(effectivePercent)%"
        return Text(verbatim: value)
            .font(NotchDesign.Typography.mono(10, weight: .medium))
            .foregroundStyle(effectiveWarn ? NotchDesign.Colors.warning : NotchDesign.Colors.textSecondary)
            // Keep the pill on one line — without this, a wider value (two digits
            // or 100%) gets compressed by the parent HStack and wraps to two rows,
            // making the badge taller than its neighbours.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Capsule().fill(warn ? NotchDesign.Colors.warning.opacity(0.1) : Color.white.opacity(0.06)))
            .help(notchLocalized(help))
    }
}
