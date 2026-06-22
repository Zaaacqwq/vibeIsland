/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Agent monitoring feature ported from Open Vibe Island (Open Island),
 * GPL v3 — Copyright (C) Octane0411 and Open Island contributors.
 * See NOTICE for details.
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
 */

import SwiftUI
import Defaults

/// Closed-pill live activity for AI coding-agent (Claude Code) sessions.
///
/// Follows Atoll's closed live-activity layout: a leading accessory left of the
/// physical notch, the black notch fill in the centre, and a trailing status
/// accessory on the right. Attention (permission/answer) is signalled with a
/// pulsing amber dot; otherwise a running-session count is shown.
struct AgentLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var agentMonitor = AgentMonitorManager.shared
    /// Driven by the notch's hover state so the pill scales/expands on hover.
    let isHovering: Bool
    @State private var isExpanded: Bool = false
    private let innerGap: CGFloat = 8

    // Claude brand orange (#d97742) and an attention amber (#ffb347).
    private let claudeColor = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 66.0 / 255.0)
    private let attentionColor = Color(red: 255.0 / 255.0, green: 179.0 / 255.0, blue: 71.0 / 255.0)

    private var accessoryHeight: CGFloat {
        vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
    }

    private var accessoryWidth: CGFloat {
        isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)) : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading — Claude glyph
            Color.clear
                .background {
                    if isExpanded {
                        leadingGlyph
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: accessoryWidth, height: accessoryHeight)

            Color.clear.frame(width: isExpanded ? innerGap : 0, height: accessoryHeight)

            // Centre — black notch fill
            Rectangle()
                .fill(.black)
                .frame(width: vm.physicalNotchWidth)

            Color.clear.frame(width: isExpanded ? innerGap : 0, height: accessoryHeight)

            // Trailing — status indicator
            Color.clear
                .background {
                    if isExpanded {
                        trailingStatus
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: accessoryWidth, height: accessoryHeight)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) { isExpanded = true }
        }
        .onChange(of: agentMonitor.hasClosedActivity) { _, hasActivity in
            withAnimation(.smooth(duration: 0.4)) { isExpanded = hasActivity }
        }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        let halo = agentMonitor.aggregateHaloState ?? .idle
        HaloRingView(state: halo, size: min(accessoryHeight, 18))
            .frame(width: accessoryHeight, height: accessoryHeight)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch agentMonitor.closedActivity {
        case .idle:
            EmptyView()
        case let .attention(count):
            HStack(spacing: 3) {
                Circle()
                    .fill(attentionColor)
                    .frame(width: 7, height: 7)
                    .modifier(PulsingModifier())
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(attentionColor)
                }
            }
            .frame(width: accessoryHeight, height: accessoryHeight)
        case let .running(count):
            HStack(spacing: 3) {
                Circle()
                    .fill(claudeColor)
                    .frame(width: 6, height: 6)
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: accessoryHeight, height: accessoryHeight)
        }
    }
}
