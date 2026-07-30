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

/// Tab-mode presentation of the clipboard history inside the open notch.
///
/// Uniform tab insets and the shared height budget come from the tab container
/// in `ContentView` (`NotchDesign.TabInset`); this fills the region it is given
/// and adds no root `.transition` of its own.
struct NotchClipboardView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableClipboardManager) private var enableClipboardManager

    var body: some View {
        Group {
            if enableClipboardManager {
                ClipboardListView(mode: .tab)
            } else {
                disabledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Text(String(localized: "Clipboard manager is turned off"))
                .font(NotchDesign.Typography.bodyStrong)
                .foregroundStyle(NotchDesign.Colors.textSecondary)
            Text(String(localized: "Enable it in Settings › Clipboard."))
                .font(NotchDesign.Typography.caption)
                .foregroundStyle(NotchDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
