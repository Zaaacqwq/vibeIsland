/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import OpenIslandCore

/// Compact "Token Usage" summary for the Agents tab's right column: four stat
/// tiles (Token / Cost / Active / Cache) over an In/Out/Reasoning/Cache legend
/// and a proportional stacked bar. Rendered bare (no title/box) so it fits the
/// notch height; Token excludes cache so Claude and Codex stay comparable.
struct NotchTokenUsageCard: View {
    let usage: TokenUsageSummary
    var isRefreshing: Bool = false
    var onRefresh: () -> Void = {}

    private enum Palette {
        static let input = NotchDesign.Colors.info
        static let output = NotchDesign.Colors.success
        static let reasoning = Color(nsColor: NSColor(geistHex: "#A78BFA"))
        static let cache = Color(nsColor: NSColor(geistHex: "#5FB3B3"))
    }

    private struct Segment: Identifiable {
        // Stable identity keyed on the label ("In"/"Out"/"Reasoning"/"Cache").
        // A `UUID()` id here regenerates on every re-render, so the legend/bar
        // ForEach would see fresh identities each time the tab mounts or token
        // data arrives — triggering an independent opacity fade instead of the
        // whole card sliding in with the tab transition.
        var id: String { label }
        let label: String
        let color: Color
        let value: Int
    }

    private var segments: [Segment] {
        let b = usage.breakdown
        return [
            Segment(label: "In", color: Palette.input, value: b.input),
            Segment(label: "Out", color: Palette.output, value: b.output),
            Segment(label: "Reasoning", color: Palette.reasoning, value: b.reasoning),
            Segment(label: "Cache", color: Palette.cache, value: b.cacheTokens),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statTiles
            VStack(alignment: .leading, spacing: 6) {
                legend
                stackedBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statTiles: some View {
        HStack(spacing: 7) {
            statTile("Token", TokenUsageFormat.compactCount(usage.breakdown.nonCacheTokens), NotchDesign.Colors.textPrimary)
            statTile("Cost", TokenUsageFormat.cost(usage.costUSD), NotchDesign.Colors.success)
            statTile("Active", TokenUsageFormat.activeDuration(usage.activeSeconds), NotchDesign.Colors.info)
            statTile("Cache", TokenUsageFormat.compactCount(usage.breakdown.cacheTokens), Palette.cache)
        }
    }

    private func statTile(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(NotchDesign.Typography.mono(9))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Text(value)
                .font(NotchDesign.Typography.mono(16, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(NotchDesign.Colors.cardFillRaised, in: RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous)
                .strokeBorder(NotchDesign.Colors.hairline, lineWidth: 1)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(segments) { legendItem($0) }
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ segment: Segment) -> some View {
        HStack(spacing: 5) {
            Circle().fill(segment.color).frame(width: 7, height: 7)
            Text(segment.label)
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let visible = segments.filter { $0.value > 0 }
            let gap: CGFloat = 2
            let minWidth: CGFloat = 3
            let totalGap = gap * CGFloat(max(0, visible.count - 1))
            // Reserve each visible segment's minimum width up front, then split
            // the LEFTOVER width proportionally. Clamping each segment to a floor
            // independently used to overflow the bar (and poke past the card's
            // right edge) when one segment dominated: the tiny segments' floors
            // stacked on top of the dominant segment's near-full width. This way
            // the widths always sum to exactly the available width.
            let reserved = totalGap + minWidth * CGFloat(visible.count)
            let flexible = max(0, geo.size.width - reserved)
            let sumValues = Double(visible.reduce(0) { $0 + $1.value })
            HStack(spacing: gap) {
                if sumValues > 0 {
                    ForEach(visible) { segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: minWidth + flexible * CGFloat(Double(segment.value) / sumValues))
                    }
                } else {
                    Capsule().fill(NotchDesign.Colors.hairline)
                }
            }
        }
        .frame(height: 8)
    }
}
