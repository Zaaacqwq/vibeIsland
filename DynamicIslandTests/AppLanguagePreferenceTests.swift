import XCTest
@testable import VibeIsland

final class AppLanguagePreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEnglishWritesAppleLanguagesOverride() {
        AppLanguageController.apply(.english, defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguageController.appleLanguagesKey), ["en"])
    }

    func testSimplifiedChineseWritesAppleLanguagesOverride() {
        AppLanguageController.apply(.simplifiedChinese, defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguageController.appleLanguagesKey), ["zh-Hans"])
    }

    func testSystemRemovesAppleLanguagesOverride() {
        defaults.set(["zh-Hans"], forKey: AppLanguageController.appleLanguagesKey)
        AppLanguageController.apply(.system, defaults: defaults)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?[
                AppLanguageController.appleLanguagesKey
            ]
        )
    }
}
