import XCTest
@testable import VibeIsland

final class AudioTapTests: XCTestCase {
    func testRealTimeWaveformSupportsAdaptedChineseMusicApps() {
        XCTAssertTrue(
            AudioTap.supportedBundleIdentifiers.contains("com.netease.163music")
        )
        XCTAssertTrue(
            AudioTap.supportedBundleIdentifiers.contains("com.tencent.QQMusicMac")
        )
    }

    func testVisualizerGainTracksVolumeWithoutFlatteningIt() {
        XCTAssertEqual(SystemVolumeController.visualizerGain(volumeScalar: 1), 1, accuracy: 0.001)
        XCTAssertEqual(SystemVolumeController.visualizerGain(volumeScalar: 0), 0, accuracy: 0.001)
        // Monotonic: quieter output must still read as quieter.
        XCTAssertLessThan(
            SystemVolumeController.visualizerGain(volumeScalar: 0.25),
            SystemVolumeController.visualizerGain(volumeScalar: 0.75)
        )
    }

    /// Regression: scaling by the device's decibel amplitude instead of its slider
    /// scalar made 18% volume a gain of 0.015, which pinned every bar to the idle
    /// floor and the waveform looked frozen while music played.
    func testTypicalPlaybackStaysWellAboveTheIdleFloorAtLowVolume() {
        let gain = SystemVolumeController.visualizerGain(volumeScalar: 0.18)
        let typicalMagnitude: Float = 0.2

        let bar = RealTimeAudioSpectrum.barScale(
            magnitude: typicalMagnitude * gain,
            amplitude: 1
        )

        XCTAssertGreaterThan(bar, 0.4, "Bars must visibly move at a normal listening volume")
    }

    func testVisualizerGainClampsOutOfRangeInput() {
        XCTAssertEqual(SystemVolumeController.visualizerGain(volumeScalar: 1.5), 1, accuracy: 0.001)
        XCTAssertEqual(SystemVolumeController.visualizerGain(volumeScalar: -0.5), 0, accuracy: 0.001)
    }

    func testWaveformAmplitudeScalesLiveBarHeight() {
        let magnitude: Float = 0.1

        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(
                magnitude: magnitude,
                amplitude: 0.25
            ),
            0.3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(
                magnitude: magnitude,
                amplitude: 1
            ),
            0.6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(
                magnitude: magnitude,
                amplitude: 2
            ),
            1,
            accuracy: 0.001
        )
    }

    func testWaveformAmplitudeIsClampedToSupportedRange() {
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.1,
                amplitude: 0
            ),
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.1,
                amplitude: RealTimeAudioSpectrum.amplitudeRange.lowerBound
            ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.1,
                amplitude: 10
            ),
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.1,
                amplitude: RealTimeAudioSpectrum.amplitudeRange.upperBound
            ),
            accuracy: 0.001
        )
    }
}
