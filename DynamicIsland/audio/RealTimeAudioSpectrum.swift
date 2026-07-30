/*
 * VibeIsland (DynamicIsland)
 * Original work Copyright (C) 2026 ZephyrCodesStuff (https://github.com/ZephyrCodesStuff/rtaudio)
 * Modified work Copyright (C) 2026 VibeIsland Contributors
 *
 * Real-time audio spectrum visualization using CoreAudio tap data.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Cocoa
import SwiftUI
import simd

/// NSView-based real-time audio spectrum visualizer
class RealTimeAudioSpectrum: NSView {
    static let amplitudeRange = 0.25...2.0

    private var barLayers: [CAShapeLayer] = []
    private var isPlaying: Bool = true
    private var amplitude: Double = 1
    private var animationTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    deinit {
        stopAnimating()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 18
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            
            barLayers.append(barLayer)
            layer?.addSublayer(barLayer)
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        } else if isPlaying {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        // 20fps is visually indistinguishable for 2pt bars but cuts the
        // window's CA commit rate by a third versus the old 30fps timer —
        // every commit forces a synchronous round-trip to WindowServer.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.updateBarsFromAudio()
        }
        timer.tolerance = 0.01
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private var lastScales = SIMD4<Double>(repeating: -1)

    private func updateBarsFromAudio() {
        guard isPlaying else {
            resetBars()
            return
        }

        // Nothing on screen can change while the notch window is occluded
        // (fullscreen app, display asleep) — skip the layer commits entirely.
        guard let window, window.occlusionState.contains(.visible) else { return }

        // Get real-time magnitudes from AudioTap
        let magnitudes = AudioTap.shared.getSmoothedMagnitudes()

        // Map magnitude (0-1) to scale (0.2 - 1.0) for visual appeal.
        // The user amplitude scales only the live portion; 100% preserves the
        // original multiplier and the 0.2 idle floor remains unchanged.
        var scales = SIMD4<Double>()
        for index in 0 ..< 4 {
            scales[index] = Self.barScale(
                magnitude: magnitudes[index],
                amplitude: amplitude
            )
        }

        // Quiet or steady audio produces near-identical frames; dropping
        // sub-pixel deltas (< ~0.1pt on an 18pt bar) avoids waking
        // WindowServer for invisible changes.
        let maxDelta = simd_reduce_max(simd_abs(scales - lastScales))
        guard maxDelta > 0.005 else { return }
        lastScales = scales

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.transform = CATransform3DMakeScale(1, CGFloat(scales[index]), 1)
        }
        CATransaction.commit()
    }

    private func resetBars() {
        lastScales = SIMD4<Double>(repeating: -1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for barLayer in barLayers {
            barLayer.transform = CATransform3DMakeScale(1, 0.2, 1)
        }
        CATransaction.commit()
    }
    
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    func setAmplitude(_ value: Double) {
        let clamped = min(
            Self.amplitudeRange.upperBound,
            max(Self.amplitudeRange.lowerBound, value)
        )
        guard clamped != amplitude else { return }
        amplitude = clamped
        // Force the next audio frame to commit even if its magnitude is steady.
        lastScales = SIMD4<Double>(repeating: -1)
    }

    static func barScale(magnitude: Float, amplitude: Double) -> Double {
        let clampedAmplitude = min(
            amplitudeRange.upperBound,
            max(amplitudeRange.lowerBound, amplitude)
        )
        return max(
            0.2,
            min(1, Double(magnitude) * 4 * clampedAmplitude + 0.2)
        )
    }
}

/// SwiftUI wrapper for RealTimeAudioSpectrum
struct RealTimeAudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    let amplitude: Double
    
    func makeNSView(context: Context) -> RealTimeAudioSpectrum {
        let spectrum = RealTimeAudioSpectrum()
        spectrum.setAmplitude(amplitude)
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: RealTimeAudioSpectrum, context: Context) {
        nsView.setAmplitude(amplitude)
        nsView.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ nsView: RealTimeAudioSpectrum, coordinator: ()) {
        nsView.setPlaying(false)
    }
}

#Preview {
    RealTimeAudioSpectrumView(
        isPlaying: .constant(true),
        amplitude: 1
    )
        .frame(width: 16, height: 20)
        .padding()
}
