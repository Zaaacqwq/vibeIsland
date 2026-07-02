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

/// The repeated card shell every notch surface uses: `#141114`/`#151515`
/// fill, 1pt hairline border, radius per the handoff's size ladder.
struct NotchCardBackground: ViewModifier {
    var radius: CGFloat = NotchDesign.Radius.md
    var fill: Color = NotchDesign.Colors.cardFill

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NotchDesign.Colors.hairline, lineWidth: NotchDesign.hairlineWidth)
            }
    }
}

extension View {
    func notchCard(radius: CGFloat = NotchDesign.Radius.md, fill: Color = NotchDesign.Colors.cardFill) -> some View {
        modifier(NotchCardBackground(radius: radius, fill: fill))
    }
}

/// The mono, uppercase, letter-spaced label every card opens with
/// (e.g. "RUNNING", "CPU", "Recent · 30").
struct NotchMonoEyebrow: View {
    let text: String
    var color: Color = NotchDesign.Colors.textTertiary

    var body: some View {
        Text(text.uppercased())
            .font(NotchDesign.Typography.eyebrow)
            .tracking(NotchDesign.eyebrowTracking)
            .foregroundStyle(color)
    }
}

/// Pill-shaped tab/status indicator background, e.g. the active tab pill in
/// the header row or an "Running" status badge.
struct NotchPillBackground: ViewModifier {
    var fill: Color = Color.white.opacity(0.09)

    func body(content: Content) -> some View {
        content.background(fill, in: Capsule())
    }
}

extension View {
    func notchPill(fill: Color = Color.white.opacity(0.09)) -> some View {
        modifier(NotchPillBackground(fill: fill))
    }
}

/// Simple opacity keyframe loop for "needs permission" / "Live" pulsing dots,
/// ~1.6s ease-in-out, 1 ↔ 0.35, per the handoff's interaction spec.
struct NotchPulsingDot: View {
    var color: Color
    var size: CGFloat = 6
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(isDim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
    }
}
