import XCTest
@testable import VibeIsland

final class AudioTapTests: XCTestCase {
    private let nominal = RealTimeAudioSpectrum.nominalAmplitude
    private var rangeDb: Double { Double(AudioBridge.normalizationRangeDb) }

    func testRealTimeWaveformSupportsAdaptedChineseMusicApps() {
        XCTAssertTrue(
            AudioTap.supportedBundleIdentifiers.contains("com.netease.163music")
        )
        XCTAssertTrue(
            AudioTap.supportedBundleIdentifiers.contains("com.tencent.QQMusicMac")
        )
    }

    // MARK: - Volume offset

    func testVolumeOffsetIsWeightedBelowItsElectricalValue() {
        // 18% on the slider is −14.9 dB electrically. Applying that in full put
        // every band under the normalisation floor and froze the waveform.
        let full = 20 * log10f(0.18)
        let applied = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.18)

        XCTAssertGreaterThan(applied, full)
        XCTAssertEqual(applied, full * SystemVolumeController.volumeOffsetWeight, accuracy: 0.01)
    }

    func testFullVolumeAppliesNoOffset() {
        XCTAssertEqual(SystemVolumeController.visualizerOffsetDb(volumeScalar: 1), 0, accuracy: 0.001)
    }

    func testVolumeOffsetIsMonotonic() {
        XCTAssertLessThan(
            SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.2),
            SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.6)
        )
    }

    func testSilentAndOutOfRangeVolumesClamp() {
        XCTAssertEqual(
            SystemVolumeController.visualizerOffsetDb(volumeScalar: 0),
            SystemVolumeController.silencedOffsetDb
        )
        XCTAssertEqual(
            SystemVolumeController.visualizerOffsetDb(volumeScalar: -0.5),
            SystemVolumeController.silencedOffsetDb
        )
        XCTAssertEqual(SystemVolumeController.visualizerOffsetDb(volumeScalar: 1.5), 0, accuracy: 0.001)
    }

    // MARK: - Decibel-domain bar mapping

    /// The whole point of the dB window: a level difference between two apps
    /// must compress into a modest height difference. An 8 dB gap is routine
    /// between a loudness-normalised app and a hot master; under the old linear
    /// mapping it scaled the live portion of the bar by 2.5×.
    func testEightDecibelSourceDifferenceCompressesIntoAFifthOfBarTravel() {
        let loud: Float = 0.55
        let quiet = loud - Float(8 / rangeDb)

        let loudBar = RealTimeAudioSpectrum.barScale(magnitude: loud, amplitude: nominal)
        let quietBar = RealTimeAudioSpectrum.barScale(magnitude: quiet, amplitude: nominal)

        XCTAssertLessThan(quietBar, loudBar)

        // Share of the bar's full travel above the idle floor, which is what
        // the eye reads. Linear mapping spent ~30% of the travel on the same
        // 8 dB; ratio of the live portion drops from 2.5× to about 1.6×.
        let travel = 1 - RealTimeAudioSpectrum.idleScale
        XCTAssertLessThan((loudBar - quietBar) / travel, 0.21)

        let liveRatio = (loudBar - RealTimeAudioSpectrum.idleScale)
            / (quietBar - RealTimeAudioSpectrum.idleScale)
        XCTAssertLessThan(liveRatio, 1.7)
    }

    /// The old window saturated at −20 dBFS post-gain, which a hot master hits
    /// constantly — that is what made one app sit pinned at full height.
    func testLoudSourcesHaveHeadroomInsteadOfPinning() {
        let hotMaster: Float = 0.75
        XCTAssertLessThan(
            RealTimeAudioSpectrum.barScale(magnitude: hotMaster, amplitude: nominal),
            1.0
        )
    }

    func testLouderBandsStillProduceTallerBars() {
        XCTAssertLessThan(
            RealTimeAudioSpectrum.barScale(magnitude: 0.3, amplitude: nominal),
            RealTimeAudioSpectrum.barScale(magnitude: 0.7, amplitude: nominal)
        )
    }

    func testTypicalPlaybackStaysWellAboveTheIdleFloor() {
        let bar = RealTimeAudioSpectrum.barScale(magnitude: 0.5, amplitude: nominal)
        XCTAssertGreaterThan(bar, 0.4, "Bars must visibly move at a normal listening level")
    }

    /// A positive amplitude or device trim must not make a silent band glow.
    func testSilentBandStaysAtTheIdleFloorEvenWhenBoosted() {
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(magnitude: 0, amplitude: 4),
            RealTimeAudioSpectrum.idleScale,
            accuracy: 0.0001
        )
    }

    func testNominalAmplitudeAppliesNoShift() {
        let magnitude: Float = 0.5
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(magnitude: magnitude, amplitude: nominal),
            RealTimeAudioSpectrum.idleScale + Double(magnitude) * (1 - RealTimeAudioSpectrum.idleScale),
            accuracy: 0.001
        )
    }

    func testAmplitudeShiftsRatherThanScales() {
        // A decibel shift moves quiet and loud passages by the same amount,
        // unlike the old multiplier which only stretched the loud ones.
        let quiet: Float = 0.3
        let loud: Float = 0.6
        let boosted = 4.0

        let quietDelta = RealTimeAudioSpectrum.barScale(magnitude: quiet, amplitude: boosted)
            - RealTimeAudioSpectrum.barScale(magnitude: quiet, amplitude: nominal)
        let loudDelta = RealTimeAudioSpectrum.barScale(magnitude: loud, amplitude: boosted)
            - RealTimeAudioSpectrum.barScale(magnitude: loud, amplitude: nominal)

        XCTAssertGreaterThan(quietDelta, 0)
        XCTAssertEqual(quietDelta, loudDelta, accuracy: 0.001)
    }

    func testWaveformAmplitudeIsClampedToSupportedRange() {
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(magnitude: 0.4, amplitude: 0),
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.4,
                amplitude: RealTimeAudioSpectrum.amplitudeRange.lowerBound
            ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            RealTimeAudioSpectrum.barScale(magnitude: 0.4, amplitude: 10),
            RealTimeAudioSpectrum.barScale(
                magnitude: 0.4,
                amplitude: RealTimeAudioSpectrum.amplitudeRange.upperBound
            ),
            accuracy: 0.001
        )
    }

    func testFormerTwoHundredPercentGainIsTheNominalAmplitude() {
        XCTAssertEqual(RealTimeAudioSpectrum.nominalAmplitude, 2)
    }
}
