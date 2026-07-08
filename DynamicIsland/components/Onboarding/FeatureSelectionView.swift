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

import SwiftUI

/// The first onboarding step: pick the features you'll use. Multi-select
/// bubbles; "Continue" applies the selection (enable chosen / disable the rest)
/// and hands the set back so the flow can queue per-feature setup pages.
/// Replaces the old fixed-profile `ProfileSelectionView`.
struct FeatureSelectionView: View {
    @State private var selected: Set<OnboardingFeature> = Set(OnboardingFeature.allCases)
    let onContinue: (Set<OnboardingFeature>) -> Void
    var onBack: (() -> Void)? = nil

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.top, 28)
                Text("Choose Your Features")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Pick what you want to use. We'll set each one up next.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingFeature.allCases) { feature in
                        FeatureCard(
                            feature: feature,
                            isSelected: selected.contains(feature),
                            onTap: { toggle(feature) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            // Soft fade on both the top and bottom edges of the scrolling grid.
            .mask(OnboardingEdgeFade())

            VStack(spacing: 12) {
                Label("You can enable more later in Settings.", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { onContinue(selected) }) {
                    Text(selected.isEmpty ? "Skip setup" : "Continue")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 22)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .overlay(alignment: .topLeading) {
            if let onBack {
                OnboardingBackButton(action: onBack)
            }
        }
    }

    private func toggle(_ feature: OnboardingFeature) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selected.contains(feature) {
                selected.remove(feature)
            } else {
                selected.insert(feature)
            }
        }
    }
}

/// A selectable feature tile: icon, title, one-line subtitle, gradient
/// selected state with a checkmark.
private struct FeatureCard: View {
    let feature: OnboardingFeature
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(.linearGradient(colors: feature.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.linearGradient(colors: feature.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(feature.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(height: 130, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(.linearGradient(colors: feature.gradient.map { $0.opacity(0.14) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.gray.opacity(isHovering ? 0.12 : 0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(.linearGradient(colors: feature.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear),
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
