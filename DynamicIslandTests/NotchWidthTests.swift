import Defaults
import XCTest
@testable import VibeIsland

/// The open-notch width has to budget for BOTH sides of the header. Turning tabs
/// off used to shrink the notch on the tab count alone, which pushed the trailing
/// stats widget under the physical notch cutout and collapsed the selected tab's
/// label. These tests pin the floor that prevents that.
@MainActor
final class NotchWidthTests: XCTestCase {
    /// Keys these tests write, snapshotted so a run cannot leave the app
    /// reconfigured.
    private var savedStats: [HeaderStatKind] = []
    private var savedContextWidgets = true
    private var savedSettingsIcon = true
    private var savedBattery = true
    private var savedTimerEnabled = true
    private var savedTimerMode: TimerDisplayMode = .tab
    private var savedColorPicker = false
    private var savedColorPickerMode: ToolDisplayMode = .popover
    private var savedClipboard = false
    private var savedClipboardMode: ToolDisplayMode = .popover
    private var savedAgents = false
    private var savedShelf = false
    private var savedCalendar = false
    private var savedReminders = false
    private var savedWeather = false
    private var savedMonitor = false

    override func setUp() {
        super.setUp()
        savedStats = Defaults[.homeHeaderStats]
        savedContextWidgets = Defaults[.showHeaderContextWidgets]
        savedSettingsIcon = Defaults[.settingsIconInNotch]
        savedBattery = Defaults[.showBatteryIndicator]
        savedTimerEnabled = Defaults[.enableTimerFeature]
        savedTimerMode = Defaults[.timerDisplayMode]
        savedColorPicker = Defaults[.enableColorPicker]
        savedColorPickerMode = Defaults[.colorPickerDisplayMode]
        savedClipboard = Defaults[.enableClipboardManager]
        savedClipboardMode = Defaults[.clipboardDisplayMode]
        savedAgents = Defaults[.enableAgentMonitoring]
        savedShelf = Defaults[.dynamicShelf]
        savedCalendar = Defaults[.showCalendar]
        savedReminders = Defaults[.showReminders]
        savedWeather = Defaults[.enableWeather]
        savedMonitor = Defaults[.enableSystemMonitor]
    }

    override func tearDown() {
        Defaults[.homeHeaderStats] = savedStats
        Defaults[.showHeaderContextWidgets] = savedContextWidgets
        Defaults[.settingsIconInNotch] = savedSettingsIcon
        Defaults[.showBatteryIndicator] = savedBattery
        Defaults[.enableTimerFeature] = savedTimerEnabled
        Defaults[.timerDisplayMode] = savedTimerMode
        Defaults[.enableColorPicker] = savedColorPicker
        Defaults[.colorPickerDisplayMode] = savedColorPickerMode
        Defaults[.enableClipboardManager] = savedClipboard
        Defaults[.clipboardDisplayMode] = savedClipboardMode
        Defaults[.enableAgentMonitoring] = savedAgents
        Defaults[.dynamicShelf] = savedShelf
        Defaults[.showCalendar] = savedCalendar
        Defaults[.showReminders] = savedReminders
        Defaults[.enableWeather] = savedWeather
        Defaults[.enableSystemMonitor] = savedMonitor
        super.tearDown()
    }

    /// Everything that contributes to the trailing side switched on, and every
    /// tab-producing feature off, so tab count is at its minimum.
    private func configureDenseHeaderWithFewTabs() {
        Defaults[.showHeaderContextWidgets] = true
        Defaults[.homeHeaderStats] = [.cpu, .gpu, .ram, .disk, .network]
        Defaults[.settingsIconInNotch] = true
        Defaults[.showBatteryIndicator] = true
        Defaults[.enableTimerFeature] = true
        Defaults[.timerDisplayMode] = .popover
        Defaults[.enableColorPicker] = true
        Defaults[.colorPickerDisplayMode] = .popover
        Defaults[.enableClipboardManager] = true
        Defaults[.clipboardDisplayMode] = .popover
        Defaults[.enableAgentMonitoring] = false
        Defaults[.dynamicShelf] = false
        Defaults[.showCalendar] = false
        Defaults[.showReminders] = false
        Defaults[.enableWeather] = false
        Defaults[.enableSystemMonitor] = false
    }

    private func emptyTheHeader() {
        Defaults[.showHeaderContextWidgets] = false
        Defaults[.homeHeaderStats] = []
        Defaults[.settingsIconInNotch] = false
        Defaults[.showBatteryIndicator] = false
        Defaults[.enableTimerFeature] = false
        Defaults[.enableColorPicker] = false
        Defaults[.enableClipboardManager] = false
    }

    func testDenseHeaderWidensASingleTabNotchBeyondTheContentFloor() throws {
        configureDenseHeaderWithFewTabs()

        XCTAssertGreaterThan(
            autoNotchWidth(forTabCount: 1),
            openNotchContentFloorWidth,
            "One tab plus a full header must not size the notch as if only the tab row mattered"
        )
    }

    func testAutoWidthNeverFallsBelowTheHeaderRequirement() throws {
        configureDenseHeaderWithFewTabs()

        for count in 0...10 {
            XCTAssertGreaterThanOrEqual(
                autoNotchWidth(forTabCount: count),
                headerRowMinimumWidth(forTabCount: count),
                "Tab count \(count) sized below what the header row needs"
            )
        }
    }

    func testManualMinimumNeverFallsBelowTheHeaderRequirement() throws {
        configureDenseHeaderWithFewTabs()

        for count in 0...10 {
            let requirement = min(headerRowMinimumWidth(forTabCount: count), maxAllowedNotchWidth())
            XCTAssertGreaterThanOrEqual(
                recommendedMinimumNotchWidth(forTabCount: count),
                requirement
            )
        }
    }

    /// Settings builds `min...max` slider ranges from this, and `ClosedRange` traps
    /// when the lower bound is the larger one — that crashed the Appearance page.
    func testManualMinimumNeverExceedsWhatTheScreenAllows() throws {
        configureDenseHeaderWithFewTabs()
        Defaults[.showNotchTabTitles] = true
        defer { Defaults[.showNotchTabTitles] = false }

        let ceiling = maxAllowedNotchWidth()
        for count in 0...20 {
            XCTAssertLessThanOrEqual(
                recommendedMinimumNotchWidth(forTabCount: count),
                ceiling,
                "Tab count \(count) produced a minimum above the screen's maximum"
            )
        }
    }

    func testEmptyingTheHeaderShrinksTheRequirement() throws {
        configureDenseHeaderWithFewTabs()
        let dense = headerRowMinimumWidth(forTabCount: 1)

        emptyTheHeader()
        let sparse = headerRowMinimumWidth(forTabCount: 1)

        XCTAssertLessThan(sparse, dense, "Removing header content should free width, not pin it")
    }

    func testAQuietHeaderSizesFromTheTabRowRatherThanAPaddedTable() throws {
        emptyTheHeader()

        let width = autoNotchWidth(forTabCount: 8)
        XCTAssertGreaterThanOrEqual(width, openNotchContentFloorWidth)
        XCTAssertLessThan(width, 960, "Eight icon-only tabs no longer justify the old table's 960pt")
    }

    /// The header's two sides split the window evenly (that centers the notch
    /// cover), so a wide trailing side has to be matched on the leading side too.
    /// Sizing from the sum instead would leave the trailing widgets drawn behind
    /// the notch cutout.
    func testWidthCoversTheWiderSideTwiceOverPlusTheCutout() throws {
        configureDenseHeaderWithFewTabs()

        let width = headerRowMinimumWidth(forTabCount: 1)
        let cutout = min(getClosedNotchSize().width, 300)
        let halfAvailable = (width - cutout) / 2

        // One tab needs almost nothing on the leading side, so the trailing side
        // is what sets the half — and it must fit in it.
        XCTAssertGreaterThanOrEqual(
            halfAvailable,
            46,
            "A single tab plus its padding must fit the leading half"
        )
        XCTAssertEqual(width, 2 * halfAvailable + cutout, accuracy: 0.5)
    }

    /// The reason the tables went away: labels are gone, so a 7-tab row no longer
    /// justifies 880pt of notch.
    func testIconOnlyTabsAreMuchNarrowerThanTheOldTableAssumed() throws {
        configureDenseHeaderWithFewTabs()
        Defaults[.homeHeaderStats] = [.cpu, .ram]
        Defaults[.colorPickerDisplayMode] = .popover
        Defaults[.clipboardDisplayMode] = .popover
        Defaults[.showBatteryIndicator] = false

        XCTAssertLessThan(
            autoNotchWidth(forTabCount: 7),
            880,
            "Seven icon-only tabs with a two-stat header used to be padded out to the old table's 880pt"
        )
    }

    func testEachAdditionalStatCellRaisesTheRequirement() throws {
        configureDenseHeaderWithFewTabs()

        Defaults[.homeHeaderStats] = [.cpu]
        let one = headerRowMinimumWidth(forTabCount: 3)
        Defaults[.homeHeaderStats] = [.cpu, .gpu, .ram]
        let three = headerRowMinimumWidth(forTabCount: 3)

        XCTAssertGreaterThan(three, one)
    }

    func testPopoverModeToolButtonsCountTowardTheRequirement() throws {
        configureDenseHeaderWithFewTabs()
        let withButtons = headerRowMinimumWidth(forTabCount: 1)

        // In tab mode the tools draw no header button — they become tabs instead,
        // which the caller accounts for via the tab count.
        Defaults[.colorPickerDisplayMode] = .tab
        Defaults[.clipboardDisplayMode] = .tab
        let withoutButtons = headerRowMinimumWidth(forTabCount: 1)

        XCTAssertGreaterThan(withButtons, withoutButtons)
    }

    // MARK: - Tab titles

    func testTabTitlesWidenTheRequirement() throws {
        configureDenseHeaderWithFewTabs()

        Defaults[.showNotchTabTitles] = false
        let iconsOnly = headerRowMinimumWidth(forTabCount: 8)
        Defaults[.showNotchTabTitles] = true
        let withTitles = headerRowMinimumWidth(forTabCount: 8)
        Defaults[.showNotchTabTitles] = false

        XCTAssertGreaterThan(withTitles, iconsOnly, "A title on the selected tab has to be budgeted for")
    }

    // MARK: - Header caps

    func testHomeHeaderStatsAreClampedToThree() throws {
        let normalized = HeaderStatKind.normalizedHeaderStats(HeaderStatKind.allCases)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(HeaderStatKind.headerLimit, 3)
        XCTAssertEqual(normalized, [.cpu, .gpu, .ram], "Clamping keeps canonical order, dropping from the end")
    }

    func testHomeHeaderStatsNormalizationDeduplicatesAndOrders() throws {
        let normalized = HeaderStatKind.normalizedHeaderStats([.network, .cpu, .cpu])

        XCTAssertEqual(normalized, [.cpu, .network])
    }

    /// A preference written before the cap existed must not overflow the row.
    func testAnOverstuffedStoredStatListDoesNotInflateTheWidth() throws {
        configureDenseHeaderWithFewTabs()
        Defaults[.homeHeaderStats] = [.cpu, .gpu, .ram]
        let atLimit = headerRowMinimumWidth(forTabCount: 3)

        Defaults[.homeHeaderStats] = HeaderStatKind.allCases  // five, i.e. legacy
        let overStuffed = headerRowMinimumWidth(forTabCount: 3)

        XCTAssertEqual(overStuffed, atLimit, "Stats beyond the cap are not drawn, so they must not be budgeted for")
    }

    func testAgentHeaderProvidersAreClampedToOne() throws {
        XCTAssertEqual(AgentUsageProviderCatalog.headerProviderLimit, 1)
        XCTAssertEqual(
            AgentUsageProviderCatalog.normalizedHeaderProviders(["claude", "codex", "cursor"]).count,
            1
        )
    }

    func testRequirementGrowsWithTabCount() throws {
        configureDenseHeaderWithFewTabs()

        let widths = (1...9).map { headerRowMinimumWidth(forTabCount: $0) }
        XCTAssertEqual(widths, widths.sorted(), "More tabs must never need less width")
    }
}
