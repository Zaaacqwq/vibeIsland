import Defaults
import XCTest
@testable import VibeIsland

/// The user-defined tab order. Repair-on-read matters most here: the stored list
/// predates any tab a future version adds, and three separate places used to
/// derive tab order independently.
@MainActor
final class NotchTabOrderTests: XCTestCase {
    private var savedOrder: [NotchViews] = []

    override func setUp() {
        super.setUp()
        savedOrder = Defaults[.notchTabOrder]
    }

    override func tearDown() {
        Defaults[.notchTabOrder] = savedOrder
        super.tearDown()
    }

    func testDefaultOrderCoversEveryTabExactlyOnce() throws {
        XCTAssertEqual(
            Set(NotchTabOrder.defaultOrder),
            Set(NotchViews.allCases),
            "A tab missing from the default order would never appear for a fresh install"
        )
        XCTAssertEqual(NotchTabOrder.defaultOrder.count, NotchViews.allCases.count)
    }

    func testNormalizationAppendsTabsMissingFromAStoredOrder() throws {
        // What an order saved by a version that predates the newest tabs looks like.
        let legacy: [NotchViews] = [.home, .shelf, .timer]

        let normalized = NotchTabOrder.normalized(legacy)

        XCTAssertEqual(Array(normalized.prefix(3)), legacy, "The user's order is preserved")
        XCTAssertEqual(Set(normalized), Set(NotchViews.allCases), "Newer tabs are appended, not dropped")
    }

    func testNormalizationRemovesDuplicates() throws {
        let normalized = NotchTabOrder.normalized([.weather, .home, .weather])

        XCTAssertEqual(Array(normalized.prefix(2)), [.weather, .home])
        XCTAssertEqual(normalized.count, NotchViews.allCases.count)
    }

    func testReorderingVisibleTabsLeavesHiddenOnesInPlace() throws {
        Defaults[.notchTabOrder] = [.home, .shelf, .timer, .agents, .calendar,
                                    .notifications, .weather, .monitor, .colorPicker, .clipboard]

        // Pretend Shelf and Timer are switched off and the user drags Agents in
        // front of Home.
        let reorderedVisible: [NotchViews] = [.agents, .home, .calendar]
        let full = NotchTabOrder.applyingVisibleOrder(reorderedVisible)

        XCTAssertEqual(Array(full.prefix(5)), [.agents, .shelf, .timer, .home, .calendar])
        XCTAssertEqual(
            full.firstIndex(of: .shelf),
            1,
            "A switched-off tab keeps its slot so turning it back on returns it where it was"
        )
        XCTAssertEqual(Set(full), Set(NotchViews.allCases))
    }

    func testPersistThenReadRoundTrips() throws {
        let visible = NotchTabOrder.visibleTabs()
        guard visible.count > 1 else {
            throw XCTSkip("Needs at least two visible tabs")
        }

        var swapped = visible
        swapped.swapAt(0, 1)
        NotchTabOrder.persist(visibleOrder: swapped)

        XCTAssertEqual(
            NotchTabOrder.visibleTabs(),
            swapped,
            "A committed drag has to survive being read back"
        )
    }

    func testResetRestoresTheDefaultOrder() throws {
        Defaults[.notchTabOrder] = [.clipboard, .weather, .home]
        XCTAssertFalse(NotchTabOrder.isDefaultOrder)

        NotchTabOrder.resetToDefault()

        XCTAssertTrue(NotchTabOrder.isDefaultOrder)
        XCTAssertEqual(NotchTabOrder.current, NotchTabOrder.defaultOrder)
    }

    func testMinimalisticModeCollapsesToHome() throws {
        let saved = Defaults[.enableMinimalisticUI]
        defer { Defaults[.enableMinimalisticUI] = saved }

        Defaults[.enableMinimalisticUI] = true
        XCTAssertEqual(NotchTabOrder.visibleTabs(), [.home])
    }

    func testVisibleTabsFollowTheStoredOrder() throws {
        let saved = (
            calendar: Defaults[.showCalendar],
            reminders: Defaults[.showReminders],
            media: Defaults[.showStandardMediaControls],
            minimal: Defaults[.enableMinimalisticUI]
        )
        defer {
            Defaults[.showCalendar] = saved.calendar
            Defaults[.showReminders] = saved.reminders
            Defaults[.showStandardMediaControls] = saved.media
            Defaults[.enableMinimalisticUI] = saved.minimal
        }

        Defaults[.enableMinimalisticUI] = false
        Defaults[.showStandardMediaControls] = true
        Defaults[.showCalendar] = true
        Defaults[.showReminders] = false
        Defaults[.notchTabOrder] = [.calendar, .home] + NotchTabOrder.defaultOrder

        let visible = NotchTabOrder.visibleTabs()
        let calendarIndex = try XCTUnwrap(visible.firstIndex(of: .calendar))
        let homeIndex = try XCTUnwrap(visible.firstIndex(of: .home))

        XCTAssertLessThan(calendarIndex, homeIndex, "Visibility filtering must not re-sort the row")
    }
}
