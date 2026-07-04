/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import EventKit

/// Shared visual tokens for the in-notch Calendar tab. Notch-native dark glass,
/// accent-driven — kept separate from the Geist settings design system.
enum CalendarStyle {
    static let surface = Color.white.opacity(0.05)
    static let surfaceHover = Color.white.opacity(0.10)
    static let hairline = NotchDesign.Colors.hairlineStrong
    static let hairlineFaint = Color.white.opacity(0.05)

    static let ink = NotchDesign.Colors.textPrimary
    static let body = Color(white: 0.72)
    static let muted = NotchDesign.Colors.textSecondary
    static let faint = NotchDesign.Colors.textTertiary
    /// Weekend / de-emphasized numerals — one notch dimmer than `faint`.
    static let dim = Color(nsColor: NSColor(geistHex: "#5A5A5A"))
    /// Near-black text/glyphs sitting on top of an accent fill (today cell,
    /// active toggle segment) — matches the mockup's `#0a0a0a` on accent.
    static let onAccent = Color(nsColor: NSColor(geistHex: "#0A0A0A"))

    static let cardRadius: CGFloat = 14
    static let chipRadius: CGFloat = 10
    static let cellSize: CGFloat = 28

    static var accent: Color { Color.effectiveAccent }
}

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2
}

struct WheelPicker: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum
                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation {
                                scrollPosition = index
                            }
                            if Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                dateCircle(date: date, isToday: isToday, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.effectiveAccentBackground : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .id(id)
    }

    private func dayText(date: String, isToday: Bool, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .white : Color(white: 0.65))
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.effectiveAccent : .clear)
                .frame(width: 20, height: 20)
            Text(date.date)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.65))
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        guard let newIndex = newValue else { return }
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
        let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    private func indexForDate(_ date: Date) -> Int {
        let spacerNum = config.offset
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        return spacerNum + stepIndex
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = index - spacerNum
        return cal.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

/// Compact week-view calendar embedded in the Home tab's right panel (shown when
/// agent monitoring is off and music is playing). Same notch-calendar language as
/// the full tab — month/year label, the shared `WeekDateSlider`, and the new
/// `CalendarAgendaList` — laid out for the narrower panel (label left, a wide
/// slider filling the rest, agenda below). The Home embed's `.notchCard` wrapper
/// provides the gray surface, so this view adds no card of its own.
struct CalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.showFullEventTitles) private var showFullEventTitles

    private let calendar = Calendar.current

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                        .font(NotchDesign.Typography.voice(13, weight: .semibold))
                        .foregroundStyle(CalendarStyle.ink)
                    Text(selectedDate.formatted(.dateTime.year()))
                        .font(NotchDesign.Typography.voice(13, weight: .light))
                        .foregroundStyle(CalendarStyle.muted)
                }
                .fixedSize()

                // Tighter cells + fade into the card fill (this sits inside the
                // Home embed's gray notchCard, not the black panel). Pin the
                // height so the horizontal ScrollView doesn't greedily expand
                // vertically (the tab constrains this via its control-row height)
                // and leave a big gap above the agenda.
                WeekDateSlider(
                    selectedDate: $selectedDate,
                    cellWidth: 36,
                    cellSpacing: 2,
                    fadeColor: NotchDesign.Colors.cardFill
                )
                .frame(height: 34)
            }

            agenda
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedDate) {
            Task { await calendarManager.updateCurrentDate(selectedDate) }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }

    @ViewBuilder
    private var agenda: some View {
        if filteredEvents.isEmpty {
            EmptyEventsView(selectedDate: selectedDate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CalendarAgendaList(
                events: filteredEvents,
                showFullEventTitles: showFullEventTitles,
                onToggleReminder: { reminderID, completed in
                    Task { await calendarManager.setReminderCompleted(reminderID: reminderID, completed: completed) }
                }
            )
            .id(calendar.startOfDay(for: selectedDate))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Full open-notch Calendar tab. Single-column, mode-toggled surface following
/// the notch UI redesign: a header control row (month label + nav + Week/Month
/// toggle), then either a week strip over a flat agenda list, or a static paged
/// month grid over a compact selected-day summary. The "Calendar" tab pill
/// itself lives in the shared `DynamicIslandHeader`, so this body starts with
/// the mode controls rather than repeating the pill.
/// Reusable horizontal date slider in the notch calendar style: a continuous,
/// snap-to-center strip of days. Scrolling pages days and selects the centered
/// one; changing `selectedDate` elsewhere recenters the strip. Registers scroll +
/// tab-switch suppression while hovered so a sideways scroll pages days instead of
/// closing the notch / switching tabs. Shared by the full Calendar tab header and
/// the compact Home embed.
struct WeekDateSlider: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    var cellWidth: CGFloat = 44
    var cellSpacing: CGFloat = 3
    /// Color the day cells fade into at both ends — black on the tab's flat black
    /// header, the card fill when embedded inside a `notchCard` (Home).
    var fadeColor: Color = .black

    @State private var scrollID: Date?
    @State private var programmatic = false
    @State private var suppressionToken = UUID()

    private let calendar = Calendar.current
    private static let pastDays = 120
    private static let futureDays = 240

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -Self.pastDays, to: today) else { return [] }
        let count = Self.pastDays + Self.futureDays + 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cellSpacing) {
                ForEach(days, id: \.self) { day in
                    cell(day)
                        .frame(width: cellWidth)
                        .id(calendar.startOfDay(for: day))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .overlay(alignment: .leading) { edgeFade(leading: true) }
        .overlay(alignment: .trailing) { edgeFade(leading: false) }
        .onHover { hovering in
            vm.setScrollGestureSuppression(hovering, token: suppressionToken)
            vm.setTabSwitchSuppression(hovering, token: suppressionToken)
        }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: suppressionToken)
            vm.setTabSwitchSuppression(false, token: suppressionToken)
        }
        .onAppear {
            programmatic = true
            scrollID = calendar.startOfDay(for: selectedDate)
        }
        // User scroll settled on a new centered day → select it.
        .onChange(of: scrollID) { _, newID in
            guard let newID else { return }
            if programmatic { programmatic = false; return }
            if !calendar.isDate(newID, inSameDayAs: selectedDate) { select(newID) }
        }
        // Selection changed elsewhere (tap, nav arrows) → recenter the slider.
        .onChange(of: selectedDate) { _, newDate in
            let target = calendar.startOfDay(for: newDate)
            guard scrollID == nil || !calendar.isDate(scrollID ?? target, inSameDayAs: target) else { return }
            programmatic = true
            withAnimation(.smooth(duration: 0.2)) { scrollID = target }
        }
    }

    private func select(_ day: Date) {
        withAnimation(.smooth(duration: 0.18)) { selectedDate = day }
    }

    private func edgeFade(leading: Bool) -> some View {
        LinearGradient(
            colors: leading ? [fadeColor, .clear] : [.clear, fadeColor],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 18)
        .allowsHitTesting(false)
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let isWeekend = calendar.isDateInWeekend(day)
        let dow = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()

        return Button { select(day) } label: {
            VStack(spacing: 1) {
                Text(dow)
                    .font(NotchDesign.Typography.mono(7, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CalendarStyle.onAccent.opacity(0.7)
                                     : (isWeekend ? CalendarStyle.dim : CalendarStyle.faint))
                Text(day.formatted(.dateTime.day()))
                    .font(NotchDesign.Typography.voice(12, weight: isSelected || isToday ? .semibold : .medium))
                    .foregroundStyle(numeralColor(isSelected: isSelected, isToday: isToday, isWeekend: isWeekend))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? CalendarStyle.accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CalendarStyle.accent, lineWidth: (!isSelected && isToday) ? 1.5 : 0)
                    )
                    // Inset the highlight so its rounded top/bottom (and today's
                    // ring) clear the slider's clip edges instead of being cropped.
                    .padding(.vertical, 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func numeralColor(isSelected: Bool, isToday: Bool, isWeekend: Bool) -> Color {
        if isSelected { return CalendarStyle.onAccent }
        if isToday { return CalendarStyle.accent }
        if isWeekend { return NotchDesign.Colors.textFaint }
        return CalendarStyle.ink
    }
}

struct StandaloneCalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.calendarTabLayout) private var layout

    private let calendar = Calendar.current
    private let weekColumns: [GridItem] = Array(repeating: GridItem(.flexible(minimum: 14), spacing: 4), count: 7)

    private var isWeek: Bool { layout == .week }

    private var headerHeight: CGFloat { max(24, vm.effectiveClosedNotchHeight) }

    /// Shared content-height budget (open-notch height minus header and the
    /// uniform tab insets), identical to every other tab via
    /// `NotchDesign.TabInset`. Used for internal splits (e.g. `weekStripHeight`);
    /// the root frame itself just fills the region the shared container provides.
    private var tabContentHeight: CGFloat {
        NotchDesign.TabInset.contentHeight(headerHeight: headerHeight)
    }

    // MARK: - Derived data

    /// Weekday columns ordered by the user's `firstWeekday`, each tagged with
    /// whether it is a weekend column (for the dimmer weekend styling).
    private var orderedWeekdays: [(symbol: String, isWeekend: Bool)] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols.map { ($0, false) } }
        let first = calendar.firstWeekday
        return (0..<7).map { offset in
            let weekday = ((first - 1 + offset) % 7) + 1 // 1 = Sunday ... 7 = Saturday
            return (symbols[weekday - 1], weekday == 1 || weekday == 7)
        }
    }

    private var monthLabel: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else { return [] }

        var days: [Date] = []
        var current = firstWeekInterval.start
        while current < lastWeekInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    private var currentWeekDays: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfMonth, for: selectedDate) else { return [] }
        var days: [Date] = []
        var current = interval.start
        for _ in 0..<7 {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlRow
                .padding(.bottom, 6)

            if isWeek {
                agenda
            } else {
                monthTwoPane
            }
        }
        // Same root frame every other tab uses (see NotchWeatherView): fill the
        // region ContentView bounds with `NotchDesign.TabInset`, top-aligned, and
        // let the notch stay content-driven. A fixed `height:` pin here forces the
        // full budget and makes the calendar taller than the content-driven tabs.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { resetToToday() }
        .onChange(of: selectedDate) { _, newDate in
            withAnimation(.smooth(duration: 0.22)) { displayedMonth = newDate.startOfMonth }
            Task { await calendarManager.updateCurrentDate(newDate) }
        }
        .onChange(of: displayedMonth) { _, newMonth in
            Task { await calendarManager.loadEventDates(forMonth: newMonth) }
        }
        .onChange(of: vm.notchState) { _, newState in
            guard newState == .open else { return }
            resetToToday()
        }
    }

    private func resetToToday() {
        selectedDate = Date.now
        displayedMonth = selectedDate.startOfMonth
        Task {
            await calendarManager.updateCurrentDate(selectedDate)
            await calendarManager.loadEventDates(forMonth: displayedMonth)
        }
    }

    // MARK: - Header control row

    private var controlRow: some View {
        HStack(spacing: 8) {
            // Both modes give their left half of the row to the weekday chrome —
            // the same width the grid/agenda occupy below — paired with the right
            // cluster, each greedily taking `maxWidth: .infinity` so they split the
            // row 50/50. Week mode puts the full weekday+date strip here; month
            // mode lifts just the weekday header up (its date grid stays in the
            // lower-left card), padded to line its columns up with that grid.
            if isWeek {
                WeekDateSlider(selectedDate: $selectedDate)
            } else {
                monthWeekdayHeader
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                navButton(icon: "chevron.left", action: showPrevious)
                Text(monthLabel.uppercased())
                    .font(NotchDesign.Typography.mono(10, weight: .medium))
                    .tracking(NotchDesign.eyebrowTracking)
                    .foregroundStyle(CalendarStyle.muted)
                    .fixedSize()
                navButton(icon: "chevron.right", action: showNext)
                modeToggle
                    .padding(.leading, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: isWeek ? 30 : 22)
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CalendarStyle.faint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeToggle: some View {
        HStack(spacing: 3) {
            toggleSegment(title: "Week", active: isWeek) { setLayout(.week) }
            toggleSegment(title: "Month", active: !isWeek) { setLayout(.scrollingMonth) }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }

    private func toggleSegment(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NotchDesign.Typography.voice(10, weight: .medium))
                .foregroundStyle(active ? CalendarStyle.onAccent : CalendarStyle.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? NotchDesign.Colors.textPrimary : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Week mode

    private var agenda: some View {
        Group {
            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarAgendaList(
                    events: filteredEvents,
                    showFullEventTitles: showFullEventTitles,
                    onToggleReminder: { reminderID, completed in
                        Task { await calendarManager.setReminderCompleted(reminderID: reminderID, completed: completed) }
                    }
                )
                // Rebuild the list when the selected day changes so its scroll
                // position resets to the top; otherwise scrolling one day's list to
                // the bottom leaves the next day's events showing from the bottom.
                .id(calendar.startOfDay(for: selectedDate))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .notchCard(radius: NotchDesign.Radius.md)
    }

    // MARK: - Month mode

    /// Month mode is a two-pane surface: a scrollable calendar grid on the left,
    /// the selected day's agenda (or empty state) on the right — mirroring the
    /// week agenda so both modes share the same event surface.
    private var monthTwoPane: some View {
        HStack(alignment: .top, spacing: 10) {
            monthLeftPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            agenda
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var monthLeftPane: some View {
        // Weekday header now lives in the control row; this pane is just the
        // scrollable date grid.
        monthGrid
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .notchCard(radius: NotchDesign.Radius.md)
    }

    private var monthWeekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(orderedWeekdays.enumerated()), id: \.offset) { _, entry in
                Text(entry.symbol.prefix(1).uppercased())
                    .font(NotchDesign.Typography.mono(10, weight: .medium))
                    .foregroundStyle(entry.isWeekend ? CalendarStyle.dim : CalendarStyle.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Per-week row height. The full month (5–6 rows) is taller than the notch
    /// budget, so the grid scrolls vertically inside the left pane.
    private static let monthRowHeight: CGFloat = 38

    private var monthGrid: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: weekColumns, spacing: 2) {
                        ForEach(monthDays, id: \.self) { day in
                            monthCell(day)
                                .id(calendar.startOfDay(for: day))
                        }
                    }
                    .padding(.vertical, 2)
                }
                monthEdgeFade(top: true)
                monthEdgeFade(top: false)
            }
            .onAppear { scrollMonth(to: selectedDate, proxy: proxy, animated: false) }
            .onChange(of: displayedMonth) { _, _ in
                scrollMonth(to: selectedDate, proxy: proxy, animated: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollMonth(to date: Date, proxy: ScrollViewProxy, animated: Bool) {
        let target = calendar.startOfDay(for: date)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo(target, anchor: .center) }
            } else {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func monthEdgeFade(top: Bool) -> some View {
        // Fade into the card fill (the grid sits in a `#141414` notchCard), not
        // pure black, so the gradient dissolves cleanly instead of smudging dark.
        let fade = NotchDesign.Colors.cardFill
        return LinearGradient(
            colors: top ? [fade.opacity(0.95), .clear] : [.clear, fade.opacity(0.95)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 14)
        .allowsHitTesting(false)
        .frame(maxHeight: .infinity, alignment: top ? .top : .bottom)
    }

    private func monthCell(_ day: Date) -> some View {
        let isCurrentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let hasEvent = calendarManager.eventDates.contains(calendar.startOfDay(for: day))

        return Button { select(day) } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8).fill(CalendarStyle.accent).frame(width: 30, height: 26)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 8).stroke(CalendarStyle.accent, lineWidth: 1.5).frame(width: 30, height: 26)
                    }
                    Text(day.formatted(.dateTime.day()))
                        .font(NotchDesign.Typography.voice(13, weight: isSelected || isToday ? .semibold : .medium))
                        .foregroundStyle(monthNumeralColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
                }
                .frame(width: 30, height: 26)

                Circle()
                    .fill(CalendarStyle.accent)
                    .frame(width: 4, height: 4)
                    .opacity(hasEvent && !isSelected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.monthRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthNumeralColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return CalendarStyle.dim }
        if isToday { return CalendarStyle.accent }
        return CalendarStyle.ink
    }

    // MARK: - Navigation

    private func select(_ day: Date) {
        withAnimation(.smooth(duration: 0.18)) { selectedDate = day }
    }

    private func setLayout(_ newLayout: CalendarTabLayout) {
        guard layout != newLayout else { return }
        withAnimation(.smooth(duration: 0.2)) { layout = newLayout }
    }

    private func showPrevious() {
        isWeek ? shiftWeek(by: -1) : shiftMonth(by: -1)
    }

    private func showNext() {
        isWeek ? shiftWeek(by: 1) : shiftMonth(by: 1)
    }

    private func shiftMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = newMonth.startOfMonth
            selectedDate = newMonth.startOfMonth
        }
    }

    private func shiftWeek(by value: Int) {
        guard let newDate = calendar.date(byAdding: .weekOfMonth, value: value, to: selectedDate) else { return }
        withAnimation(.smooth(duration: 0.22)) { selectedDate = newDate }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(CalendarStyle.muted)
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundStyle(CalendarStyle.body)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundStyle(CalendarStyle.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
}

/// Flat agenda list for the Calendar tab's Week mode. Each row follows the
/// redesign's event grammar — a mono time column, a thin category-color bar,
/// then the Geist title + subtitle — separated by hairlines rather than sitting
/// in filled cards. Reminders swap the color bar for a completion toggle.
private struct CalendarAgendaList: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]
    let showFullEventTitles: Bool
    let onToggleReminder: (String, Bool) -> Void

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        row(event)
                        if index < events.count - 1 {
                            Rectangle()
                                .fill(CalendarStyle.hairlineFaint)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .clipped()

            // Fade into the card fill — the agenda sits in a `#141414` notchCard,
            // so a black fade would smudge dark against the card.
            LinearGradient(colors: [NotchDesign.Colors.cardFill.opacity(0.95), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .top)

            LinearGradient(colors: [.clear, NotchDesign.Colors.cardFill.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipped()
    }

    @ViewBuilder
    private func row(_ event: EventModel) -> some View {
        if event.type.isReminder {
            reminderRow(event)
        } else {
            eventRow(event)
        }
    }

    // MARK: - Rows

    private func eventRow(_ event: EventModel) -> some View {
        HStack(spacing: 14) {
            timeColumn(event)

            RoundedRectangle(cornerRadius: 100)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(NotchDesign.Typography.voice(13, weight: .medium))
                    .foregroundStyle(CalendarStyle.ink)
                    .lineLimit(showFullEventTitles ? nil : 1)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(NotchDesign.Typography.voice(11))
                        .foregroundStyle(CalendarStyle.muted)
                        .lineLimit(1)
                }

                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(event) }
        .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1)
    }

    private func reminderRow(_ event: EventModel) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }

        return HStack(spacing: 14) {
            timeColumn(event)

            ReminderToggle(
                isOn: Binding(
                    get: { isCompleted },
                    set: { newValue in onToggleReminder(event.id, newValue) }
                ),
                color: Color(nsColor: event.calendar.color)
            )
            .frame(width: 14)

            Text(event.title)
                .font(NotchDesign.Typography.voice(13, weight: .medium))
                .foregroundStyle(CalendarStyle.ink)
                .lineLimit(showFullEventTitles ? nil : 1)
                .strikethrough(isCompleted, color: CalendarStyle.muted)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(event) }
        .opacity(isCompleted ? 0.55 : 1)
    }

    // MARK: - Time column

    /// Width sized so a 12-hour "12:30 PM" time fits on one line — otherwise the
    /// AM/PM wraps and each agenda row balloons to three lines, shrinking how
    /// many events are visible.
    private static let timeColumnWidth: CGFloat = 62

    @ViewBuilder
    private func timeColumn(_ event: EventModel) -> some View {
        if event.isAllDay {
            Text("ALL-DAY")
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(CalendarStyle.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: Self.timeColumnWidth, alignment: .trailing)
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                Text(event.start, style: .time)
                    .font(NotchDesign.Typography.mono(12, weight: .medium))
                    .foregroundStyle(CalendarStyle.ink)
                Text(event.end, style: .time)
                    .font(NotchDesign.Typography.mono(10))
                    .foregroundStyle(CalendarStyle.faint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Self.timeColumnWidth, alignment: .trailing)
        }
    }

    private func open(_ event: EventModel) {
        if let url = event.calendarAppURL() {
            openURL(url)
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    static func filteredEvents(
        events: [EventModel],
        hideCompletedReminders: Bool,
        hideAllDayEvents: Bool
    ) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !hideCompletedReminders
                }
            }
            if event.isAllDay && hideAllDayEvents {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(
            events: events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let now = Date()
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                List {
                    ForEach(filteredEvents) { event in
                        Button(action: {
                            if let url = event.calendarAppURL() {
                                openURL(url)
                            }
                        }) {
                            eventRow(event)
                        }
                        .id(event.id)
                        .padding(.leading, -5)
                        .buttonStyle(PlainButtonStyle())
                        .listRowSeparator(.automatic)
                        .listRowSeparatorTint(.gray.opacity(0.2))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.never)
                .scrollContentBackground(.hidden)
                .background(Color.clear)

                LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)
                    .alignmentGuide(.top) { d in d[.top] }
                    .frame(maxHeight: .infinity, alignment: .top)

                LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                        
                        // Show Join button if conference URL is available
                        if let conferenceURL = event.conferenceURL {
                            ConferenceJoinButton(url: conferenceURL, event: event)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Conference Provider

enum ConferenceProvider: CaseIterable {
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord, generic
    
    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .generic: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: return Color(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: return Color(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .gotomeeting: return Color(red: 0.95, green: 0.5, blue: 0.13)
        case .bluejeans: return Color(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: return Color(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: return Color(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: return Color(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: return Color.accentColor
        }
    }
    
    private var hostIdentifiers: [String] {
        switch self {
        case .zoom: return ["zoom.us"]
        case .teams: return ["teams.microsoft.com"]
        case .meet: return ["meet.google.com"]
        case .webex: return ["webex.com"]
        case .facetime: return ["facetime.apple.com"]
        case .gotomeeting: return ["gotomeeting.com"]
        case .bluejeans: return ["bluejeans.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si", "jitsi"]
        case .discord: return ["discord.gg", "discord.com"]
        case .generic: return []
        }
    }
    
    var nativeURLScheme: String? {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .facetime: return "facetime"
        case .discord: return "discord"
        default: return nil
        }
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        return allCases.first { provider in
            provider.hostIdentifiers.contains { host.contains($0) }
        } ?? .generic
    }
}

// MARK: - Conference Join Button

struct ConferenceJoinButton: View {
    let url: URL
    let event: EventModel
    @Environment(\.openURL) private var openURL
    
    private var provider: ConferenceProvider { .detect(from: url) }
    private var isJoinable: Bool {
        event.start.addingTimeInterval(-15 * 60) <= Date()
    }
    
    private var buttonText: String {
        event.eventStatus == .inProgress ? "Rejoin" : "Join"
    }
    
    var body: some View {
        Button(action: {
            if let scheme = provider.nativeURLScheme,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = scheme
                if let nativeURL = components.url {
                    openURL(nativeURL)
                    return
                }
            }
            openURL(url)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.name.isEmpty ? buttonText : "\(buttonText) \(provider.name)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isJoinable ? .white : Color(white: 0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isJoinable ? provider.color.opacity(0.85) : Color.gray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isJoinable)
        .help(isJoinable ? "Join the meeting" : "Meeting starts at \(event.start.formatted(date: .omitted, time: .shortened))")
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(DynamicIslandViewModel.init())
}
