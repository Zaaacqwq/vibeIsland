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

/// A trend line for one `MonitorHistory` series, drawn as a plain `Path`.
///
/// Deliberately dependency-free and animation-free: this redraws on every
/// 2-second tick inside up to eight tiles at once, and an implicit animation on
/// a 60-point path is exactly the kind of per-frame commit work that stalls the
/// notch. The line is a static snapshot of the series; motion comes from the
/// data advancing, not from SwiftUI interpolating it.
struct MonitorSparkline: View {
    /// Samples already mapped into 0...1.
    let normalized: [Double]
    var tint: Color
    var lineWidth: CGFloat = 1.5
    /// Fills the area under the curve with a fading gradient. Off for the dense
    /// two-series charts, where two fills would muddy each other.
    var fills = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if normalized.count >= 2, size.width > 0, size.height > 0 {
                let points = points(in: size)
                if fills {
                    areaPath(points, in: size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                linePath(points)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            } else {
                // Fewer than two samples has no shape to draw — hold a flat
                // baseline so the tile's height doesn't jump on the first tick.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                }
                .stroke(tint.opacity(0.3), lineWidth: lineWidth)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    /// Maps the series across the full width, newest sample on the right. A
    /// half-`lineWidth` inset top and bottom keeps a 100% reading from being
    /// clipped by the frame.
    private func points(in size: CGSize) -> [CGPoint] {
        let inset = lineWidth / 2
        let usableHeight = max(size.height - lineWidth, 0)
        let step = size.width / CGFloat(max(normalized.count - 1, 1))
        return normalized.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: inset + usableHeight * (1 - CGFloat(min(max(value, 0), 1)))
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(_ points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

/// Two series overlaid on one baseline — used for the network (down/up) and
/// storage (read/write) charts, which only make sense read together.
struct MonitorDualSparkline: View {
    let primary: [Double]
    let secondary: [Double]
    var primaryTint: Color
    var secondaryTint: Color

    var body: some View {
        ZStack {
            MonitorSparkline(normalized: primary, tint: primaryTint, lineWidth: 1.5, fills: true)
            MonitorSparkline(normalized: secondary, tint: secondaryTint, lineWidth: 1.5, fills: false)
        }
    }
}
