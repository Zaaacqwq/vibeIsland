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
}
