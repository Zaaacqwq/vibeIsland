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

import Defaults
import SwiftUI

/// Calendar setup page: request access (folds in the old standalone
/// permission step) and let the user choose which calendars to surface.
struct CalendarFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @ObservedObject private var manager = CalendarManager.shared
    @State private var selectedIDs: Set<String> = []
    @State private var didRequestAccess = false

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.calendar.symbol,
            gradient: OnboardingFeature.calendar.gradient,
            title: String(localized: "Pick your calendars"),
            subtitle: String(localized: "Choose which calendars appear in the notch. You can change these later."),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: onContinue
        ) {
            if manager.allCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No calendars available yet.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Grant calendar access when prompted, or continue and enable it later in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(eventGroups, id: \.account) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(group.account)
                            ForEach(group.calendars) { calendarRow($0) }
                        }
                    }
                    if !reminderLists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(String(localized: "Reminders"))
                            ForEach(reminderLists) { calendarRow($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            guard !didRequestAccess else { return }
            didRequestAccess = true
            await manager.checkCalendarAuthorization()
            await manager.reloadCalendarAndReminderLists()
            selectedIDs = Set(manager.allCalendars.filter { manager.getCalendarSelected($0) }.map(\.id))
        }
    }

    /// Event calendars grouped by account (email), each group sorted by title,
    /// groups sorted by account name.
    private var eventGroups: [(account: String, calendars: [CalendarModel])] {
        let events = manager.allCalendars.filter { !$0.isReminder }
        return Dictionary(grouping: events, by: \.accountName)
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
    }

    /// Reminder lists, sorted by title — shown after the event calendars.
    private var reminderLists: [CalendarModel] {
        manager.allCalendars.filter(\.isReminder).sorted { $0.title < $1.title }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func calendarRow(_ calendar: CalendarModel) -> some View {
        let isSelected = selectedIDs.contains(calendar.id)

        Button {
            let newValue = !isSelected
            if newValue { selectedIDs.insert(calendar.id) } else { selectedIDs.remove(calendar.id) }
            Task { await manager.setCalendarSelected(calendar, isSelected: newValue) }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: calendar.color))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
