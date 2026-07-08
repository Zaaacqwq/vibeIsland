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

/// Music setup page: choose the media source. Reuses `ControllerOptionView`
/// inside the shared onboarding scaffold.
struct MusicFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @Default(.mediaController) private var mediaController
    @State private var selection: MediaControllerType = Defaults[.mediaController]

    private var availableControllers: [MediaControllerType] {
        MusicManager.shared.isNowPlayingDeprecated
            ? MediaControllerType.allCases.filter { $0 != .nowPlaying }
            : MediaControllerType.allCases
    }

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.music.symbol,
            gradient: OnboardingFeature.music.gradient,
            title: String(localized: "Choose a music source"),
            subtitle: String(localized: "Pick where VibeIsland reads now-playing from."),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: applyAndContinue
        ) {
            VStack(spacing: 12) {
                ForEach(availableControllers) { controller in
                    ControllerOptionView(controller: controller, isSelected: selection == controller)
                        .onTapGesture { selection = controller }
                }
            }
        }
    }

    private func applyAndContinue() {
        mediaController = selection
        NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
        onContinue()
    }
}
