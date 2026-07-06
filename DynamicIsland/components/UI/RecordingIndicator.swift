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

struct RecordingIndicator: View {
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isPulsing = false
    
    // MARK: - Configuration
    private let indicatorSize: CGFloat = 6
    private let glowSize: CGFloat = 2
    private let animationDuration: Double = 0.8
    
    var body: some View {
        Group {
            if recordingManager.isRecording {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: indicatorSize + glowSize * 2, height: indicatorSize + glowSize * 2)
                        .blur(radius: glowSize)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                    
                    // Main indicator dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: indicatorSize, height: indicatorSize)
                        .opacity(isPulsing ? 1.0 : 0.6)
                }
                .onAppear {
                    startPulsingAnimation()
                }
                .onDisappear {
                    stopPulsingAnimation()
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isRecording)
    }
    
    // MARK: - Private Methods
    
    private func startPulsingAnimation() {
        isPulsing = false
        withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
    
    private func stopPulsingAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}

// MARK: - Preview

struct RecordingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Recording state preview
            VStack {
                Text("Recording Active")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = true
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Recording Active")
            
            // Non-recording state preview
            VStack {
                Text("Not Recording")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = false
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Not Recording")
        }
    }
}
