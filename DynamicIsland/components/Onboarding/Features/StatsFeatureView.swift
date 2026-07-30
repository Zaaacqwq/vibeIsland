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
import SwiftUI

/// Stats setup page: choose which system monitors show in the Home header.
struct StatsFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var selected: Set<HeaderStatKind> = Set(
        HeaderStatKind.normalizedHeaderStats(Defaults[.homeHeaderStats])
    )

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private func symbol(for kind: HeaderStatKind) -> String {
        switch kind {
        case .cpu: return "cpu.fill"
        case .gpu: return "memorychip.fill"
        case .ram: return "memorychip"
        case .disk: return "internaldrive.fill"
        case .network: return "network"
        }
    }

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.stats.symbol,
            gradient: OnboardingFeature.stats.gradient,
            title: String(localized: "Which monitors?"),
            subtitle: String(localized: "Pick the system metrics for the notch header — up to \(HeaderStatKind.headerLimit)."),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: applyAndContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(HeaderStatKind.allCases) { kind in
                    SelectBubble(
                        title: kind.settingsTitle,
                        icon: .symbol(symbol(for: kind)),
                        isSelected: selected.contains(kind),
                        gradient: OnboardingFeature.stats.gradient,
                        onTap: { toggle(kind) }
                    )
                }
            }
        }
    }

    /// Hard cap shared with Settings — see `HeaderStatKind.headerLimit`.
    private static let recommendedMax = HeaderStatKind.headerLimit

    private func toggle(_ kind: HeaderStatKind) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selected.contains(kind) {
                selected.remove(kind)
            } else if selected.count < Self.recommendedMax {
                selected.insert(kind)
            }
        }
    }

    private func applyAndContinue() {
        Defaults[.showHeaderContextWidgets] = true
        // Preserve canonical ordering (allCases) regardless of tap order.
        Defaults[.homeHeaderStats] = HeaderStatKind.allCases.filter { selected.contains($0) }
        onContinue()
    }
}
