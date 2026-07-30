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

/// A notch tab. Icon-only by default, with the selected state carried by the
/// capsule behind it (drawn by `TabSelectionView`).
///
/// The title is opt-in (`Defaults[.showNotchTabTitles]`) because rendering it on
/// the selected tab costs roughly 120pt of notch width — and since the header's
/// two sides split the notch evenly, that is 120pt the notch has to carry whether
/// the rest of the row needs it or not. It is always the tooltip.
struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var showsTitle: Bool = false
    let onClick: () -> Void

    /// Icon-only tabs are a touch wider than tall, so the selected capsule reads
    /// as a pill rather than a cramped square.
    static let iconOnlyWidth: CGFloat = 35
    static let height: CGFloat = 30

    private var showsLabel: Bool { selected && showsTitle }

    /// Deliberately **not** a `Button`.
    ///
    /// A `Button`'s own gesture recognizer competes with the ⌘-drag reorder in
    /// `TabSelectionView`: it swallows the drag and cancels it partway, so the row
    /// only jumped to its new order on mouse-up (and long drags landed short). A
    /// plain tap target composes with a `DragGesture` predictably.
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14))
            if showsLabel {
                Text(label)
                    .font(NotchDesign.Typography.voice(12, weight: .medium))
                    // Never compressed to zero — an icon-only "selected" tab in
                    // titles mode reads as a layout bug. The trailing context
                    // widget truncates instead.
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: showsLabel ? nil : Self.iconOnlyWidth, height: Self.height)
        .padding(.horizontal, showsLabel ? 12 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onClick() }
    }
}

#Preview {
    TabButton(label: "Home", icon: "house.fill", selected: true) {
        print("Tapped")
    }
}
