/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import Foundation

/// Per-output-device calibration for the music visualiser.
///
/// Headphones and speakers at the same slider position are not equally loud —
/// transducer sensitivity and amplifier gain differ by more than ten decibels,
/// and macOS exposes no way to read actual output level. The one thing that
/// *is* observable is where you habitually leave the volume slider on each
/// device, and that position already encodes the correction: you turn the
/// slider to wherever the device sounds right to you.
///
/// So each device learns the mean slider offset it is listened at, and the
/// visualiser subtracts it. At your habitual level every device animates
/// identically; moving above or below that level still shortens or lengthens
/// the bars, which is the behaviour the slider should have.
enum AudioOutputLevelCalibration {
    /// Bound on the learned correction. Beyond this a device is more likely
    /// misreporting its scalar than genuinely being listened to that quietly.
    static let trimLimitDb: Float = 12

    /// Spacing between learning samples while audio plays.
    static let sampleInterval: TimeInterval = 2

    /// Playback time for a new listening level to move the mean halfway.
    /// Deliberately long: this should track habits, not a momentary nudge.
    static let halfLifeSeconds: TimeInterval = 600

    static func smoothingFactor(
        sampleInterval: TimeInterval = sampleInterval,
        halfLife: TimeInterval = halfLifeSeconds
    ) -> Float {
        guard sampleInterval > 0, halfLife > 0 else { return 1 }
        return Float(1 - exp(-log(2) * sampleInterval / halfLife))
    }

    /// A device seen for the first time adopts its current level immediately,
    /// so it starts calibrated instead of drifting there over ten minutes.
    static func updatedMeanOffsetDb(
        previous: Float?,
        sample: Float,
        factor: Float
    ) -> Float {
        guard let previous else { return sample }
        return previous + (sample - previous) * min(1, max(0, factor))
    }

    static func trimDb(forMeanOffsetDb mean: Float) -> Float {
        min(trimLimitDb, max(-trimLimitDb, -mean))
    }
}

/// Learns and applies ``AudioOutputLevelCalibration`` for the active route.
///
/// Accessed from the visualiser's render timer and from CoreAudio route
/// notifications, so all mutable state is behind a lock.
final class AudioOutputLevelCalibrator {
    static let shared = AudioOutputLevelCalibrator()

    private let lock = NSLock()
    private var lastSampleDate: Date?
    private var cachedUID: String?
    private var cachedTrimDb: Float = 0

    private init() {}

    /// Combined shift for the current route: what the volume slider says, plus
    /// what this device has learned about how it is listened to.
    func currentOffsetDb() -> Float {
        let controller = SystemVolumeController.shared
        let volumeOffset = controller.currentOutputOffsetDb
        // A muted route is already below the normalisation floor; adding a
        // learned trim to it would be meaningless.
        guard volumeOffset > SystemVolumeController.silencedOffsetDb else {
            return volumeOffset
        }
        return volumeOffset + trimDb(for: controller.currentOutputDeviceUID)
    }

    /// Called while audio is audibly playing. Rate-limits itself, so callers on
    /// the render path can invoke it every frame.
    ///
    /// Returns `true` when a sample was taken and the trim may have moved, so
    /// the caller can push the refreshed offset to the processor instead of
    /// re-reading CoreAudio every frame.
    @discardableResult
    func noteAudioActive(now: Date = Date()) -> Bool {
        let controller = SystemVolumeController.shared
        guard !controller.isMuted else { return false }
        guard let uid = controller.currentOutputDeviceUID else { return false }

        let shouldSample: Bool = lock.withLock {
            guard let last = lastSampleDate else {
                lastSampleDate = now
                return true
            }
            guard now.timeIntervalSince(last) >= AudioOutputLevelCalibration.sampleInterval else {
                return false
            }
            lastSampleDate = now
            return true
        }
        guard shouldSample else { return false }

        let sample = controller.currentOutputOffsetDb
        guard sample > SystemVolumeController.silencedOffsetDb else { return false }

        var stored = Defaults[.audioOutputLevelCalibration]
        let previous = stored[uid].map(Float.init)
        let mean = AudioOutputLevelCalibration.updatedMeanOffsetDb(
            previous: previous,
            sample: sample,
            factor: AudioOutputLevelCalibration.smoothingFactor()
        )
        stored[uid] = Double(mean)
        Defaults[.audioOutputLevelCalibration] = stored

        lock.withLock {
            cachedUID = uid
            cachedTrimDb = AudioOutputLevelCalibration.trimDb(forMeanOffsetDb: mean)
        }
        return true
    }

    /// Drops the cached trim so the next read picks up the new route.
    func invalidate() {
        lock.withLock {
            cachedUID = nil
            lastSampleDate = nil
        }
    }

    private func trimDb(for uid: String?) -> Float {
        guard let uid else { return 0 }

        let cached: Float? = lock.withLock {
            cachedUID == uid ? cachedTrimDb : nil
        }
        if let cached { return cached }

        guard let mean = Defaults[.audioOutputLevelCalibration][uid] else {
            lock.withLock {
                cachedUID = uid
                cachedTrimDb = 0
            }
            return 0
        }
        let trim = AudioOutputLevelCalibration.trimDb(forMeanOffsetDb: Float(mean))
        lock.withLock {
            cachedUID = uid
            cachedTrimDb = trim
        }
        return trim
    }
}
