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
import AppKit

private struct ShelfBackgroundClickCatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> BackgroundClickView {
        let view = BackgroundClickView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: BackgroundClickView, context: Context) {
        nsView.onClick = onClick
    }

    final class BackgroundClickView: NSView {
        var onClick: (() -> Void)?

        override func mouseUp(with event: NSEvent) {
            onClick?()
        }
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8
    private let quickShareWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: NotchDesign.Spacing.md) {
            FileShareView()
                .frame(width: quickShareWidth)
                .frame(maxHeight: .infinity)
                .environmentObject(vm)
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Uniform tab insets + height budget come from the shared tab container
        // in ContentView (`NotchDesign.TabInset`); fill the region top-aligned.
        // (The old `contentPadding` + negative drop-zone outset are gone so the
        // shelf respects the same margins as every other tab.)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: NotchDesign.Radius.xl, style: .continuous)
            .fill(NotchDesign.Colors.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: NotchDesign.Radius.xl, style: .continuous)
                    .stroke(
                        vm.dragDetectorTargeting
                            ? NotchDesign.Colors.accent.opacity(0.9)
                            : NotchDesign.Colors.hairlineStrong,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [8, 6])
                    )
            }
            .overlay {
                ZStack {
                    ShelfBackgroundClickCatcher {
                        guard !selection.isDragging else { return }
                        selection.clear()
                    }

                    content
                        .padding(12)
                }
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                NotchMonoEyebrow(text: "Drop Zone")
                Spacer()
                Text(itemSummary)
                    .font(NotchDesign.Typography.mono(10, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textFaint)
                if !tvm.isEmpty {
                    clearAllButton
                }
            }

            if tvm.isEmpty {
                emptyDropHint
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }

            hintRow
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }

    private var itemSummary: String {
        tvm.items.isEmpty ? "0 items" : "\(tvm.items.count) items"
    }

    private var clearAllButton: some View {
        Button {
            ShelfSelectionModel.shared.clear()
            tvm.removeAll()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 9, weight: .semibold))
                Text("Clear all")
                    .font(NotchDesign.Typography.mono(10, weight: .medium))
            }
            .foregroundStyle(NotchDesign.Colors.textFaint)
        }
        .buttonStyle(.plain)
        .help("Remove all files from the shelf")
    }

    private var emptyDropHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Text("Drop files to stash them here")
                .font(NotchDesign.Typography.voice(13, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
        }
    }

    private var hintRow: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.dragDetectorTargeting ? "plus.circle.fill" : "plus.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(vm.dragDetectorTargeting ? NotchDesign.Colors.accent : NotchDesign.Colors.textTertiary)
            Text("Drop files to stash them here")
                .font(NotchDesign.Typography.mono(10))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
            Spacer()
        }
    }
}
