import XCTest
@testable import VibeIsland

final class AudioOutputLevelCalibrationTests: XCTestCase {
    private typealias Calibration = AudioOutputLevelCalibration

    /// A device seen for the first time must be usable immediately rather than
    /// drifting into calibration over ten minutes of playback.
    func testFirstSampleSeedsTheMeanDirectly() {
        let mean = Calibration.updatedMeanOffsetDb(
            previous: nil,
            sample: -7.5,
            factor: Calibration.smoothingFactor()
        )
        XCTAssertEqual(mean, -7.5, accuracy: 0.0001)
    }

    func testMeanTracksHabitsSlowly() {
        let factor = Calibration.smoothingFactor()
        let moved = Calibration.updatedMeanOffsetDb(previous: -4, sample: -12, factor: factor)

        XCTAssertLessThan(moved, -4)
        XCTAssertGreaterThan(moved, -4.1, "One sample must barely move a learned habit")
    }

    func testMeanReachesHalfwayAfterOneHalfLifeOfPlayback() {
        let factor = Calibration.smoothingFactor()
        let sampleCount = Int(Calibration.halfLifeSeconds / Calibration.sampleInterval)

        var mean: Float = 0
        for _ in 0 ..< sampleCount {
            mean = Calibration.updatedMeanOffsetDb(previous: mean, sample: -10, factor: factor)
        }

        XCTAssertEqual(mean, -5, accuracy: 0.15)
    }

    func testTrimCancelsTheHabitualListeningLevel() {
        // Speakers listened at 40%, headphones at 15%. Both feel equally loud
        // to the listener, so both must animate identically.
        let speakers = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.4)
        let headphones = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.15)
        XCTAssertNotEqual(speakers, headphones, accuracy: 0.5)

        let speakerNet = speakers + Calibration.trimDb(forMeanOffsetDb: speakers)
        let headphoneNet = headphones + Calibration.trimDb(forMeanOffsetDb: headphones)

        XCTAssertEqual(speakerNet, headphoneNet, accuracy: 0.001)
        XCTAssertEqual(speakerNet, 0, accuracy: 0.001)
    }

    /// Calibration equalises habits, not the slider itself — moving above your
    /// usual level on a device must still make the bars taller.
    func testMovingAboveTheLearnedHabitStillRaisesTheLevel() {
        let habit = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.3)
        let trim = Calibration.trimDb(forMeanOffsetDb: habit)

        let atHabit = habit + trim
        let louder = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.6) + trim
        let quieter = SystemVolumeController.visualizerOffsetDb(volumeScalar: 0.1) + trim

        XCTAssertGreaterThan(louder, atHabit)
        XCTAssertLessThan(quieter, atHabit)
    }

    func testTrimIsBounded() {
        XCTAssertEqual(
            Calibration.trimDb(forMeanOffsetDb: -60),
            Calibration.trimLimitDb,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            Calibration.trimDb(forMeanOffsetDb: 60),
            -Calibration.trimLimitDb,
            accuracy: 0.0001
        )
    }

    func testSmoothingFactorIsBoundedForDegenerateInput() {
        XCTAssertEqual(Calibration.smoothingFactor(sampleInterval: 0, halfLife: 600), 1)
        XCTAssertEqual(Calibration.smoothingFactor(sampleInterval: 2, halfLife: 0), 1)
        XCTAssertGreaterThan(Calibration.smoothingFactor(), 0)
        XCTAssertLessThan(Calibration.smoothingFactor(), 1)
    }
}
