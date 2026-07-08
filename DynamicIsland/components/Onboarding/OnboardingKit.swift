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

/// Icon source for an onboarding bubble — either an SF Symbol or an asset image.
enum BubbleIcon {
    case symbol(String)
    case asset(String)

    @ViewBuilder
    func view(gradient: [Color], isSelected: Bool) -> some View {
        switch self {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(.white)
                        : AnyShapeStyle(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                )
        case let .asset(name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
    }
}

/// A selectable pill ("bubble"): icon + label with a gradient selected state.
/// Reused by the feature picker, agent-provider picker, and stats picker.
struct SelectBubble: View {
    let title: String
    let icon: BubbleIcon
    let isSelected: Bool
    var gradient: [Color] = [.blue, .purple]
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                icon.view(gradient: gradient, isSelected: isSelected)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.gray.opacity(isHovering ? 0.16 : 0.1))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.white.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// A circular back affordance shown top-leading on onboarding pages.
struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.top, 12)
    }
}

/// Shared scaffold for feature setup pages: gradient icon + title + subtitle,
/// scrollable content, a "change later in Settings" note, and a Skip/Continue
/// bottom bar. Matches the existing onboarding visual language.
struct OnboardingScaffold<Content: View>: View {
    let symbol: String
    var gradient: [Color] = [.blue, .purple]
    let title: String
    let subtitle: String
    var continueTitle: String = String(localized: "Continue")
    var continueEnabled: Bool = true
    var onBack: (() -> Void)? = nil
    let onSkip: () -> Void
    let onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.top, 28)
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .mask(OnboardingEdgeFade())

            VStack(spacing: 12) {
                Label(String(localized: "You can change this anytime in Settings."), systemImage: "gearshape")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button(String(localized: "Skip"), action: onSkip)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button(continueTitle, action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!continueEnabled)
                }
            }
            .padding(.bottom, 22)
            .padding(.top, 8)
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
}

/// A vertical fade applied as a `.mask` to onboarding scroll regions so
/// content softly fades at both the top and bottom edges. Used as a shared
/// gradient so every page fades identically.
struct OnboardingEdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
