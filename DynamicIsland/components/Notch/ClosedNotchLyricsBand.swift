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

import AppKit
import Defaults
import SwiftUI

/// The current synced lyric line, rendered in a band that pops down beneath the
/// closed notch pill while music plays. Standard notch only; gated by
/// ``Defaults/showLyricsInClosedNotch``. Long lines marquee-scroll.
struct ClosedNotchLyricsBand: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.coloredLyrics) private var coloredLyrics

    /// Available width for the lyric text (the closed pill's center width).
    let width: CGFloat

    /// The band stays mounted (so its height can animate smoothly) but only
    /// renders lyric content — and runs the per-frame highlight clock — while
    /// active. When inactive it's transparent and cheap.
    var isActive: Bool = true

    private var textColor: Color {
        coloredLyrics ? Color(nsColor: musicManager.avgColor) : .gray
    }

    /// Small inset so text breathes off the notch's bottom rounded corners
    /// while still spanning essentially the whole dropdown width.
    private let horizontalInset: CGFloat = 2

    private static let lyricSwiftUIFont: Font = .system(size: 12, weight: .medium)

    /// Played (sung) portion color for the KTV-style highlight.
    private var highlightColor: Color {
        coloredLyrics ? Color(nsColor: musicManager.avgColor) : .white
    }

    /// Not-yet-sung portion color (dimmed).
    private var baseColor: Color {
        highlightColor.opacity(0.32)
    }

    var body: some View {
        if isActive {
            activeContent
        } else {
            // Mounted but transparent while retracted/inactive — no TimelineView.
            Color.clear
                .frame(width: max(0, width), height: closedLyricsBandHeight)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let textWidth = max(0, width - horizontalInset * 2)
        let isLoading = musicManager.isLoadingLyricLine

        Group {
            if isLoading {
                // Loading hint: dimmed, centered, no highlight/scroll.
                Text(line)
                    .font(Self.lyricSwiftUIFont)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .frame(width: textWidth, alignment: .center)
                    .opacity(0.55)
            } else {
                // Real lyric line: KTV highlight + (if too long) single-pass scroll.
                KaraokeLyricLine(
                    text: line,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    visibleWidth: textWidth,
                    displayDuration: musicManager.currentLyricDisplayDuration
                )
            }
        }
        .frame(width: textWidth, height: closedLyricsBandHeight, alignment: .center)
        .frame(width: max(0, width), alignment: .center)
    }
}

/// A single lyric line with a KTV-style left-to-right highlight: the played
/// portion (`currentLyricProgress`) is drawn in `highlightColor`, the rest in the
/// dimmer `baseColor`. Long lines also scroll (single pass — no looping copy, so
/// the start never reappears on the right) and the scroll is paced to finish
/// within the line's on-screen window.
private struct KaraokeLyricLine: View {
    @ObservedObject private var musicManager = MusicManager.shared

    let text: String
    let baseColor: Color
    let highlightColor: Color
    /// The visible window width; longer text overflows this and is clipped.
    let visibleWidth: CGFloat
    /// How long this line stays on screen (seconds); 0 if unknown.
    let displayDuration: TimeInterval

    @State private var offset: CGFloat = 0

    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let swiftUIFont: Font = .system(size: 12, weight: .medium)
    private static let fallbackSpeed: CGFloat = 40   // pts/sec when window unknown
    private static let maxScroll: Double = 9         // cap so long windows don't crawl
    private static let tailMargin: Double = 0.35     // leave the tail visible briefly

    private var fullTextWidth: CGFloat {
        (text as NSString).size(withAttributes: [.font: Self.font]).width
    }

    var body: some View {
        let overflow = max(0, fullTextWidth - visibleWidth)

        // Redraw on a display-linked clock so the highlight fill tracks live
        // playback (and self-corrects after a seek). Throttled to ~30fps.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let progress = musicManager.currentLyricProgress

            ZStack(alignment: .leading) {
                Text(text).foregroundColor(baseColor)
                Text(text)
                    .foregroundColor(highlightColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, fullTextWidth * progress))
                    }
            }
            .font(Self.swiftUIFont)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: fullTextWidth, alignment: .leading)
            .offset(x: offset)
            .frame(width: visibleWidth, alignment: overflow > 0 ? .leading : .center)
            .clipped()
        }
        .task(id: text) { await runScroll() }
    }

    private func runScroll() async {
        offset = 0
        let overflow = max(0, fullTextWidth - visibleWidth)
        guard overflow > 0 else { return }

        // Budget the whole reveal to finish within the line's on-screen window:
        // a short lead-in so the start is readable, scroll, then keep the tail
        // shown for the remainder. Single pass — the line changes before it
        // would need to loop.
        let leadIn: Double
        let scrollDuration: Double
        if displayDuration > 0 {
            leadIn = min(0.5, displayDuration * 0.12)
            scrollDuration = min(max(0.4, displayDuration - leadIn - Self.tailMargin), Self.maxScroll)
        } else {
            leadIn = 0.5
            scrollDuration = Double(overflow / Self.fallbackSpeed)
        }

        try? await Task.sleep(for: .seconds(leadIn))
        if Task.isCancelled { return }

        withAnimation(.linear(duration: scrollDuration)) { offset = -overflow }
        // Hold at the end; the line is replaced (task cancelled) when it changes.
    }
}
