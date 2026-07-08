/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for VibeIsland (DynamicIsland)
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
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

/// Coarse phase of onboarding. The middle "feature setup" phase iterates a
/// queue of per-feature pages derived from the user's bubble selection.
private enum OnboardingPhase {
    case welcome
    case featureSelection
    case featurePages
    case finished
}

struct OnboardingView: View {
    @State private var phase: OnboardingPhase = .welcome
    @State private var pageQueue: [OnboardingFeature] = []
    @State private var pageIndex = 0
    @State private var showFocusMonitoringChoice = false
    @State private var didPresentFocusMonitoringChoice = false
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch phase {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) { phase = .featureSelection }
                }
                .transition(.opacity)

            case .featureSelection:
                FeatureSelectionView(
                    onContinue: { selected in
                        OnboardingFeature.applySelection(selected)
                        pageQueue = OnboardingFeature.configPages(for: selected)
                        pageIndex = 0
                        withAnimation(.easeInOut(duration: 0.6)) {
                            phase = pageQueue.isEmpty ? .finished : .featurePages
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.6)) { phase = .welcome }
                    }
                )
                .transition(.opacity)

            case .featurePages:
                featurePage(pageQueue[pageIndex])
                    .id(pageIndex)
                    .transition(.opacity)
                    .overlay(alignment: .top) { progressPill }

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            guard !didPresentFocusMonitoringChoice else { return }
            didPresentFocusMonitoringChoice = true
            showFocusMonitoringChoice = true
        }
        .confirmationDialog(
            "Focus detection mode",
            isPresented: $showFocusMonitoringChoice,
            titleVisibility: .visible
        ) {
            Button("Use DevTools") { Defaults[.focusMonitoringMode] = .useDevTools }
            Button("Use without DevTools") { Defaults[.focusMonitoringMode] = .withoutDevTools }
            Button("Later", role: .cancel) {}
        } message: {
            Text("This is optional. You can change it any time from the menu bar.")
        }
    }

    // MARK: - Feature pages

    @ViewBuilder
    private func featurePage(_ feature: OnboardingFeature) -> some View {
        switch feature {
        case .agent:
            AgentFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .calendar:
            CalendarFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .timer:
            TimerFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .stats:
            StatsFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .notification:
            NotificationFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .music:
            MusicFeatureView(onContinue: advance, onSkip: advance, onBack: goBack)
        case .weather, .shelf:
            // Page-less features are never queued; render nothing defensively.
            Color.clear.onAppear(perform: advance)
        }
    }

    private var progressPill: some View {
        Text("\(pageIndex + 1) of \(pageQueue.count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.thinMaterial))
            .padding(.top, 10)
    }

    private func advance() {
        if pageIndex + 1 < pageQueue.count {
            withAnimation(.easeInOut(duration: 0.5)) { pageIndex += 1 }
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { phase = .finished }
        }
    }

    /// Back navigation: step to the previous feature page, or return to the
    /// feature picker from the first page.
    private func goBack() {
        if pageIndex > 0 {
            withAnimation(.easeInOut(duration: 0.5)) { pageIndex -= 1 }
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { phase = .featureSelection }
        }
    }
}
