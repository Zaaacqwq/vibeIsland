/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for VibeIsland (DynamicIsland)
 * See NOTICE for details.
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

import Foundation
import EventKit

protocol CalendarServiceProviding {
    func requestAccess() async -> Bool
    func requestAccess(to type: EKEntityType) async -> Bool
    func calendars() async -> [CalendarModel]
    func calendarEvents(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
    func reminders(calendars: [String]) async -> [EventModel]
    func defaultCalendarIdentifier(for type: EKEntityType) -> String?
    func createEvent(_ draft: CalendarEventDraft) async throws
    func createReminder(_ draft: ReminderDraft) async throws
    func setReminderCompleted(reminderID: String, completed: Bool) async
}

class CalendarService: CalendarServiceProviding {
    private let store = EKEventStore()
    
    @MainActor
    func requestAccess() async -> Bool {
        let eventsAccess = await requestAccess(to: .event)
        let remindersAccess = await requestAccess(to: .reminder)
        return eventsAccess || remindersAccess
    }

    @MainActor
    func requestAccess(to type: EKEntityType) async -> Bool {
        do {
            return try await performAccessRequest(for: type)
        } catch {
            print("Calendar access error: \(error)")
            return false
        }
    }

    private func performAccessRequest(for type: EKEntityType) async throws -> Bool {
        switch type {
        case .event:
            return try await store.requestFullAccessToEvents()
        case .reminder:
            return try await store.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }
    
    private func hasAccess(to entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        return status == .fullAccess
    }
    
    func calendars() async -> [CalendarModel] {
        var calendars: [EKCalendar] = []
        
        for type in [EKEntityType.event, .reminder] where hasAccess(to: type) {
            calendars.append(contentsOf: store.calendars(for: type))
        }
        
        return calendars.map { CalendarModel(from: $0) }
    }
    
    func calendarEvents(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        guard hasAccess(to: .event) else { return [] }
        guard !ids.isEmpty else { return [] }
        let available = store.calendars(for: .event)
        let selected = available.filter { ids.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        return store.events(matching: predicate)
            .compactMap { EventModel(from: $0) }
            .sorted { $0.start < $1.start }
    }

    func reminders(calendars ids: [String]) async -> [EventModel] {
        guard hasAccess(to: .reminder) else { return [] }
        guard !ids.isEmpty else { return [] }
        let available = store.calendars(for: .reminder)
        let selected = available.filter { ids.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForReminders(in: selected)
            store.fetchReminders(matching: predicate) { reminders in
                let models = (reminders ?? []).compactMap { EventModel(from: $0) }
                let sorted = models.sorted { lhs, rhs in
                    switch (lhs.reminderDueDate, rhs.reminderDueDate) {
                    case let (left?, right?): return left < right
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                }
                continuation.resume(returning: sorted)
            }
        }
    }

    func defaultCalendarIdentifier(for type: EKEntityType) -> String? {
        switch type {
        case .event:
            return store.defaultCalendarForNewEvents?.calendarIdentifier
        case .reminder:
            return store.defaultCalendarForNewReminders()?.calendarIdentifier
        @unknown default:
            return nil
        }
    }

    @MainActor
    func createEvent(_ draft: CalendarEventDraft) async throws {
        guard let calendar = store.calendar(withIdentifier: draft.calendarID),
              calendar.allowedEntityTypes.contains(.event),
              calendar.allowsContentModifications else {
            throw CalendarWriteError.calendarUnavailable
        }

        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.calendar = calendar
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        try store.save(event, span: .thisEvent, commit: true)
    }

    @MainActor
    func createReminder(_ draft: ReminderDraft) async throws {
        guard let calendar = store.calendar(withIdentifier: draft.calendarID),
              calendar.allowedEntityTypes.contains(.reminder),
              calendar.allowsContentModifications else {
            throw CalendarWriteError.calendarUnavailable
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.calendar = calendar
        reminder.notes = draft.notes
        reminder.priority = draft.priority.rawValue
        if let dueDate = draft.dueDate {
            let components: Set<Calendar.Component> = draft.includesTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
            reminder.timeZone = draft.includesTime ? .current : nil
        }
        try store.save(reminder, commit: true)
    }

    @MainActor
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            print("Failed to update reminder completion: \(error)")
        }
    }
}

enum CalendarWriteError: LocalizedError {
    case calendarUnavailable

    var errorDescription: String? {
        String(localized: "The selected calendar is no longer available for writing.")
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            accountName: calendar.accountTitle,
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            isReminder: calendar.allowedEntityTypes.contains(.reminder),
            isWritable: calendar.allowsContentModifications
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil,
            conferenceURL: event.extractConferenceURL(),
            reminderDueDate: nil
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar else { return nil }
        let dueDateComponents = reminder.dueDateComponents
        let date = dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let displayDate = date ?? .distantFuture
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: displayDate,
            end: date.map { Calendar.current.endOfDay(for: $0) } ?? displayDate,
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents?.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : reminder.timeZone,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority),
            conferenceURL: nil,
            reminderDueDate: date
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

extension Priority {
    init?(from p: Int) {
        switch p {
        case 1...4:
            self = .high
        case 5:
            self = .medium
        case 6...9:
            self = .low
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return String(localized: "Other")
        default:
            return source.title
        }
    }
    
    var isDelegate: Bool {
        return source.isDelegate
    }
}

private extension EKEvent {
    var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }
    
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
    
    /// Extract conference call URL from various sources
    func extractConferenceURL() -> URL? {
        // First try the URL field if it's a conference URL
        if let eventURL = url, isConferenceURL(eventURL) {
            return eventURL
        }
        
        // Then try to extract from location field
        if let location = location, let conferenceURL = extractURLFromText(location) {
            return conferenceURL
        }
        
        // Finally try to extract from notes
        if let notes = notes, let conferenceURL = extractURLFromText(notes) {
            return conferenceURL
        }
        
        return nil
    }
    
    /// Check if a URL is likely a conference URL
    private func isConferenceURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let conferenceHosts = [
            "zoom.us",
            "teams.microsoft.com",
            "meet.google.com",
            "webex.com",
            "gotomeeting.com",
            "bluejeans.com",
            "whereby.com",
            "meet.jit.si",
            "discord.gg",
            "discord.com",
            "facetime.apple.com"
        ]
        
        return conferenceHosts.contains { host.contains($0) }
    }
    
    /// Extract first valid conference URL from text
    private func extractURLFromText(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches ?? [] {
            if let url = match.url, isConferenceURL(url) {
                return url
            }
        }
        
        return nil
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
