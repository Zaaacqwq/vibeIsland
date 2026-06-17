/*
 * VibeIsland
 * Copyright (C) 2026 Zaaacqwq and VibeIsland contributors.
 *
 * The agent status "halo" visual is inspired by and adapted from Claude Halo
 * (https://github.com/Houyusu/claude-halo), MIT License — Copyright (C) Houyu.
 * Reimplemented natively in SwiftUI. See NOTICE.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version. See the GNU General Public License
 * for more details.
 */

import SwiftUI

/// A glowing, animated three-layer ring that reflects a `HaloState`.
///
/// Layers (outer → inner): a soft blurred glow, a gradient mid-stroke, and a
/// crisp inner arc. The ring rotates continuously (speed per state) while a
/// secondary motion — breathe, pulse, or radius-pulse — adds life. Driven by a
/// single `TimelineView(.animation)` clock so state changes are seamless.
struct HaloRingView: View {
    let state: HaloState
    var size: CGFloat = 16

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                draw(
                    in: &context,
                    canvasSize: canvasSize,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel(state.label)
    }

    private func draw(in context: inout GraphicsContext, canvasSize: CGSize, time: TimeInterval) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let baseRadius = min(canvasSize.width, canvasSize.height) / 2 - canvasSize.width * 0.14
        let color = state.color

        // Secondary motion factors.
        var radius = baseRadius
        var glowOpacity = 0.55
        var coreOpacity = 1.0
        switch state.motion {
        case .steady:
            break
        case .breathe:
            let b = (sin(time * 2.2) + 1) / 2 // 0…1
            glowOpacity = 0.35 + 0.4 * b
            coreOpacity = 0.75 + 0.25 * b
        case .pulse:
            let p = (sin(time * 6.0) + 1) / 2
            glowOpacity = 0.2 + 0.7 * p
            coreOpacity = 0.55 + 0.45 * p
        case .radiusPulse:
            let r = (sin(time * 4.0) + 1) / 2
            radius = baseRadius * (0.86 + 0.14 * r)
            glowOpacity = 0.4 + 0.35 * r
        }

        // Rotation: an arc with a gap, rotating over time.
        let rotation = time * state.rotationSpeed
        let gap = 0.62 // radians of missing arc
        let start = Angle(radians: rotation)
        let end = Angle(radians: rotation + (2 * .pi - gap))

        func arcPath(_ r: CGFloat) -> Path {
            var path = Path()
            path.addArc(center: center, radius: r, startAngle: start, endAngle: end, clockwise: false)
            return path
        }

        let outerWidth = max(1.4, canvasSize.width * 0.16)
        let midWidth = max(1.0, canvasSize.width * 0.10)
        let coreWidth = max(0.8, canvasSize.width * 0.055)

        // Layer 1 — soft outer glow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: canvasSize.width * 0.10))
            layer.stroke(
                arcPath(radius),
                with: .color(color.opacity(glowOpacity)),
                style: StrokeStyle(lineWidth: outerWidth, lineCap: .round)
            )
        }

        // Layer 2 — gradient mid-stroke (fades along the arc for a comet feel).
        let gradient = GraphicsContext.Shading.conicGradient(
            Gradient(colors: [color.opacity(0.15), color.opacity(0.95), color.opacity(0.15)]),
            center: center,
            angle: start
        )
        context.stroke(
            arcPath(radius),
            with: gradient,
            style: StrokeStyle(lineWidth: midWidth, lineCap: .round)
        )

        // Layer 3 — crisp inner core line.
        context.stroke(
            arcPath(radius),
            with: .color(color.opacity(coreOpacity)),
            style: StrokeStyle(lineWidth: coreWidth, lineCap: .round)
        )
    }
}
