/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import EventKit
import SwiftUI

private enum CalendarCreatePopoverStyle {
    static let surface = Color(nsColor: NSColor(geistHex: "#161618"))
    static let fieldFill = Color.white.opacity(0.05)
    static let fieldStroke = Color.white.opacity(0.07)
    static let title = Color(nsColor: NSColor(geistHex: "#F2F2F2"))
    static let bright = Color(nsColor: NSColor(geistHex: "#CFCFCF"))
    static let muted = Color(nsColor: NSColor(geistHex: "#8A8A8A"))
    static let radius: CGFloat = 14
}

private struct CalendarPopoverFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(CalendarCreatePopoverStyle.title)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CalendarCreatePopoverStyle.fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(CalendarCreatePopoverStyle.fieldStroke, lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func calendarPopoverField() -> some View {
        modifier(CalendarPopoverFieldModifier())
    }
}

struct CalendarPermissionStateView: View {
    let mode: CalendarContentMode
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: mode == .events ? "calendar.badge.exclamationmark" : "checklist")
                .font(.title2)
                .foregroundStyle(CalendarStyle.muted)
            Text(mode == .events ? "Calendar access is required" : "Reminders access is required")
                .font(NotchDesign.Typography.voice(13, weight: .medium))
                .foregroundStyle(CalendarStyle.body)
            HStack(spacing: 6) {
                Button("Request Access", action: onRequestAccess)
                    .buttonStyle(.borderedProminent)
                Button("Open Settings") {
                    let pane = mode == .events ? "Privacy_Calendars" : "Privacy_Reminders"
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReminderGroupsList: View {
    @Environment(\.openURL) private var openURL

    let reminders: [EventModel]
    let hideCompleted: Bool
    let onToggle: (String, Bool) -> Void

    private let calendar = Calendar.current

    private struct SectionModel: Identifiable {
        let id: String
        let title: String
        let reminders: [EventModel]
    }

    private var sections: [SectionModel] {
        let active = reminders.filter { !isCompleted($0) }
        let completed = reminders.filter(isCompleted)
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        var result: [SectionModel] = []
        appendSection("overdue", title: String(localized: "Overdue"), items: active.filter {
            guard let due = $0.reminderDueDate else { return false }
            return due < startOfToday
        }, to: &result)
        appendSection("today", title: String(localized: "Today"), items: active.filter {
            guard let due = $0.reminderDueDate else { return false }
            return due >= startOfToday && due < startOfTomorrow
        }, to: &result)
        appendSection("upcoming", title: String(localized: "Upcoming"), items: active.filter {
            guard let due = $0.reminderDueDate else { return false }
            return due >= startOfTomorrow
        }, to: &result)
        appendSection("no-date", title: String(localized: "No Date"), items: active.filter {
            $0.reminderDueDate == nil
        }, to: &result)
        if !hideCompleted {
            appendSection("completed", title: String(localized: "Completed"), items: completed, to: &result)
        }
        return result
    }

    var body: some View {
        if sections.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(CalendarStyle.muted)
                Text("No reminders")
                    .font(.subheadline)
                    .foregroundStyle(CalendarStyle.body)
                Text("Everything is up to date.")
                    .font(.caption)
                    .foregroundStyle(CalendarStyle.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            NotchMonoEyebrow(text: "\(section.title) · \(section.reminders.count)")
                                .padding(.horizontal, 4)
                                .padding(.bottom, 2)

                            ForEach(Array(section.reminders.enumerated()), id: \.element.id) { index, reminder in
                                reminderRow(reminder)
                                if index < section.reminders.count - 1 {
                                    Rectangle()
                                        .fill(CalendarStyle.hairlineFaint)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .notchListEdgeFade(color: NotchDesign.Colors.cardFill)
        }
    }

    private func appendSection(_ id: String, title: String, items: [EventModel], to result: inout [SectionModel]) {
        guard !items.isEmpty else { return }
        result.append(.init(id: id, title: title, reminders: items))
    }

    private func isCompleted(_ reminder: EventModel) -> Bool {
        if case .reminder(let completed) = reminder.type { return completed }
        return false
    }

    private func reminderRow(_ reminder: EventModel) -> some View {
        let completed = isCompleted(reminder)
        return HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { completed },
                    set: { onToggle(reminder.id, $0) }
                ),
                color: Color(nsColor: reminder.calendar.color)
            )
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(NotchDesign.Typography.voice(13, weight: .medium))
                    .foregroundStyle(CalendarStyle.ink)
                    .lineLimit(1)
                    .strikethrough(completed, color: CalendarStyle.muted)

                if let due = reminder.reminderDueDate {
                    Text(dueLabel(due, isAllDay: reminder.isAllDay))
                        .font(NotchDesign.Typography.mono(9))
                        .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && !completed ? NotchDesign.Colors.danger : CalendarStyle.faint)
                }
            }

            Spacer(minLength: 0)

            if let priority = reminder.priority {
                Image(systemName: priorityIcon(priority))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(priority == .high ? NotchDesign.Colors.danger : CalendarStyle.faint)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = reminder.calendarAppURL() { openURL(url) }
        }
        .opacity(completed ? 0.55 : 1)
    }

    private func dueLabel(_ date: Date, isAllDay: Bool) -> String {
        if Calendar.current.isDateInToday(date) {
            return isAllDay ? String(localized: "Today") : date.formatted(date: .omitted, time: .shortened)
        }
        return isAllDay
            ? date.formatted(date: .abbreviated, time: .omitted)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private func priorityIcon(_ priority: Priority) -> String {
        switch priority {
        case .high: return "exclamationmark.3"
        case .medium: return "exclamationmark.2"
        case .low: return "exclamationmark"
        }
    }
}

struct CalendarCreatePopover: View {
    @ObservedObject private var manager = CalendarManager.shared

    let mode: CalendarContentMode
    let selectedDate: Date
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var selectedCalendarID = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var includesDueTime = false
    @State private var reminderPriority: ReminderDraftPriority = .none
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: CalendarContentMode, selectedDate: Date, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.selectedDate = selectedDate
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let rounded = calendar.date(byAdding: .minute, value: 30 - (minute % 30), to: now) ?? now
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let time = calendar.dateComponents([.hour, .minute], from: rounded)
        let initialStart = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: selectedDay) ?? selectedDate
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: calendar.date(byAdding: .hour, value: 1, to: initialStart) ?? initialStart)
    }

    private var availableCalendars: [CalendarModel] {
        mode == .events ? manager.writableEventCalendars : manager.writableReminderLists
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mode == .events ? "New Event" : "New Reminder")
                    .font(.headline)
                    .foregroundStyle(CalendarCreatePopoverStyle.title)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CalendarCreatePopoverStyle.muted)
                }
                .buttonStyle(.plain)
            }

            TextField(mode == .events ? "Event title" : "Reminder title", text: $title)
                .calendarPopoverField()

            Picker(mode == .events ? "Calendar" : "List", selection: $selectedCalendarID) {
                ForEach(availableCalendars) { calendar in
                    HStack {
                        Circle().fill(Color(nsColor: calendar.color)).frame(width: 7, height: 7)
                        Text(calendar.title)
                    }
                    .tag(calendar.id)
                }
            }
            .foregroundStyle(CalendarCreatePopoverStyle.bright)
            .tint(CalendarCreatePopoverStyle.bright)

            if mode == .events {
                eventFields
            } else {
                reminderFields
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedTitle.isEmpty || selectedCalendarID.isEmpty || isSaving)
            }
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(CalendarCreatePopoverStyle.bright)
        .tint(CalendarStyle.accent)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                CalendarCreatePopoverStyle.surface.opacity(0.92)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: CalendarCreatePopoverStyle.radius,
                    style: .continuous
                )
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: CalendarCreatePopoverStyle.radius,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .onAppear(perform: selectDefaultCalendar)
        .onChange(of: availableCalendars.map(\.id)) { _, _ in selectDefaultCalendar() }
    }

    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("All-day", isOn: $isAllDay)
                .toggleStyle(.switch)
            DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
            if !isAllDay {
                DatePicker("Ends", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
            }
            TextField("Location (optional)", text: $location)
                .calendarPopoverField()
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...3)
                .calendarPopoverField()
        }
    }

    private var reminderFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Due date", isOn: $hasDueDate)
                .toggleStyle(.switch)
            if hasDueDate {
                DatePicker("Due", selection: $startDate, displayedComponents: includesDueTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Include time", isOn: $includesDueTime)
                    .toggleStyle(.switch)
            }
            Picker("Priority", selection: $reminderPriority) {
                ForEach(ReminderDraftPriority.allCases) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...3)
                .calendarPopoverField()
        }
    }

    private func selectDefaultCalendar() {
        guard !availableCalendars.contains(where: { $0.id == selectedCalendarID }) else { return }
        selectedCalendarID = (mode == .events ? manager.defaultEventCalendarID : manager.defaultReminderListID)
            ?? availableCalendars.first?.id
            ?? ""
    }

    private func save() {
        errorMessage = nil
        guard !trimmedTitle.isEmpty else { return }

        if mode == .events, !isAllDay, endDate <= startDate {
            errorMessage = String(localized: "The end time must be after the start time.")
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                if mode == .events {
                    let calendar = Calendar.current
                    let eventStart = isAllDay ? calendar.startOfDay(for: startDate) : startDate
                    let eventEnd = isAllDay
                        ? (calendar.date(byAdding: .day, value: 1, to: eventStart) ?? eventStart)
                        : endDate
                    try await manager.createEvent(.init(
                        title: trimmedTitle,
                        calendarID: selectedCalendarID,
                        startDate: eventStart,
                        endDate: eventEnd,
                        isAllDay: isAllDay,
                        location: optional(location),
                        notes: optional(notes)
                    ))
                } else {
                    try await manager.createReminder(.init(
                        title: trimmedTitle,
                        calendarID: selectedCalendarID,
                        dueDate: hasDueDate ? startDate : nil,
                        includesTime: hasDueDate && includesDueTime,
                        priority: reminderPriority,
                        notes: optional(notes)
                    ))
                }
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
