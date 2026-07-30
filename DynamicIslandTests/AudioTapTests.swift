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

    func testSystemOutputDecibelsConvertToLinearWaveformGain() {
        XCTAssertEqual(
            SystemVolumeController.linearGain(decibels: 0),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SystemVolumeController.linearGain(decibels: -20),
            0.1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SystemVolumeController.linearGain(decibels: -Float.infinity),
            0,
            accuracy: 0.001
        )
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
