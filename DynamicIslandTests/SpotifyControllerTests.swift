import XCTest
@testable import VibeIsland

final class SpotifyControllerTests: XCTestCase {
    func testPositionSampleAppliesExternalSeekToSameTrack() throws {
        let trackID = "0123456789ABCDEFGHIJKL"
        var state = PlaybackState(
            bundleIdentifier: SpotifyController.bundleIdentifier,
            isPlaying: true,
            title: "Track",
            artist: "Artist",
            contentIdentifier: "spotify:track:\(trackID)",
            currentTime: 12,
            duration: 180,
            lastUpdated: .distantPast
        )
        state.contentURL = "https://open.spotify.com/track/\(trackID)"
        let observedAt = Date()

        let updated = try XCTUnwrap(
            SpotifyController.reconciledPlaybackState(
                state,
                currentTime: 93.5,
                isPlaying: true,
                contentIdentifier: trackID,
                contentURL: state.contentURL ?? "",
                observedAt: observedAt
            )
        )

        XCTAssertEqual(updated.currentTime, 93.5, accuracy: 0.001)
        XCTAssertEqual(updated.lastUpdated, observedAt)
        XCTAssertTrue(updated.isPlaying)
    }

    func testPositionSampleRejectsDifferentTrack() {
        let state = PlaybackState(
            bundleIdentifier: SpotifyController.bundleIdentifier,
            contentIdentifier: "spotify:track:0123456789ABCDEFGHIJKL",
            currentTime: 12,
            duration: 180
        )

        let updated = SpotifyController.reconciledPlaybackState(
            state,
            currentTime: 30,
            isPlaying: true,
            contentIdentifier: "spotify:track:ZYXWVUTSRQPONMLKJIHGFE",
            contentURL: "",
            observedAt: Date()
        )

        XCTAssertNil(updated)
    }

    func testPositionSampleClampsToTrackBounds() throws {
        let state = PlaybackState(
            bundleIdentifier: SpotifyController.bundleIdentifier,
            currentTime: 12,
            duration: 180
        )

        let beforeStart = try XCTUnwrap(
            SpotifyController.reconciledPlaybackState(
                state,
                currentTime: -10,
                isPlaying: false,
                contentIdentifier: "",
                contentURL: "",
                observedAt: Date()
            )
        )
        let afterEnd = try XCTUnwrap(
            SpotifyController.reconciledPlaybackState(
                state,
                currentTime: 250,
                isPlaying: false,
                contentIdentifier: "",
                contentURL: "",
                observedAt: Date()
            )
        )

        XCTAssertEqual(beforeStart.currentTime, 0)
        XCTAssertEqual(afterEnd.currentTime, 180)
    }
}
