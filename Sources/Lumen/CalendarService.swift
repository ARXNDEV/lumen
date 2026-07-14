import AppKit
import EventKit

/// Wraps EventKit: calendar events + reminders. Google Calendar works through
/// this too — the user adds their Google account in System Settings →
/// Internet Accounts and its calendars appear in EventKit automatically.
final class CalendarService {
    static let shared = CalendarService()

    let store = EKEventStore()
    private(set) var eventsGranted = false
    private(set) var remindersGranted = false
    private var requested = false

    func requestAccessIfNeeded(completion: @escaping () -> Void) {
        if requested {
            completion()
            return
        }
        requested = true

        let group = DispatchGroup()
        group.enter()
        group.enter()

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                self.eventsGranted = granted
                group.leave()
            }
            store.requestFullAccessToReminders { granted, _ in
                self.remindersGranted = granted
                group.leave()
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                self.eventsGranted = granted
                group.leave()
            }
            store.requestAccess(to: .reminder) { granted, _ in
                self.remindersGranted = granted
                group.leave()
            }
        }
        group.notify(queue: .main) { completion() }
    }

    func upcomingEvents(days: Int = 7, limit: Int = 6) -> [EKEvent] {
        guard eventsGranted else { return [] }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return Array(
            store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .prefix(limit)
        )
    }

    /// Incomplete reminders due today or overdue.
    func fetchDueReminders(completion: @escaping ([EKReminder]) -> Void) {
        guard remindersGranted else {
            completion([])
            return
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil
        )
        store.fetchReminders(matching: predicate) { reminders in
            completion(reminders ?? [])
        }
    }

    func createReminder(title: String, due: Date?) -> Bool {
        guard remindersGranted else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    static func eventTimeString(_ event: EKEvent) -> String {
        let df = DateFormatter()
        if Calendar.current.isDateInToday(event.startDate) {
            df.dateFormat = "h:mm a"
            return "Today \(df.string(from: event.startDate))"
        }
        if Calendar.current.isDateInTomorrow(event.startDate) {
            df.dateFormat = "h:mm a"
            return "Tomorrow \(df.string(from: event.startDate))"
        }
        df.dateFormat = "EEE d MMM, h:mm a"
        return df.string(from: event.startDate)
    }

    /// Parses "remind me to call john at 5pm" → ("call john", 5pm today).
    static func parseReminder(_ q: String) -> (title: String, date: Date?)? {
        let lower = q.lowercased()
        var text: String
        if lower.hasPrefix("remind me to ") {
            text = String(q.dropFirst(13))
        } else if lower.hasPrefix("remind me ") {
            text = String(q.dropFirst(10))
        } else if lower.hasPrefix("remind ") {
            text = String(q.dropFirst(7))
        } else {
            return nil
        }

        var date: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let d = match.date {
            date = d
            if let r = Range(match.range, in: text) {
                text.removeSubrange(r)
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)
        for suffix in [" at", " on", " by", " in"] where text.lowercased().hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (text, date)
    }
}

// MARK: - Calendar events in search

enum CalendarProvider {
    static func results(for q: String) -> [SearchResult] {
        let keywords = ["calendar", "schedule", "today", "meetings", "events", "agenda"]
        guard keywords.contains(where: { Fuzzy.score(q, $0) != nil }) else { return [] }

        let events = CalendarService.shared.upcomingEvents()
        guard !events.isEmpty else {
            guard CalendarService.shared.eventsGranted else { return [] }
            return [SearchResult(
                id: "cal:none", kind: .calendar,
                title: "No upcoming events",
                subtitle: "Next 7 days are clear",
                icon: nil, symbolName: "calendar", score: 0.7,
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
            )]
        }
        return events.enumerated().map { i, event in
            SearchResult(
                id: "cal:\(event.eventIdentifier ?? UUID().uuidString)",
                kind: .calendar,
                title: event.title ?? "Untitled event",
                subtitle: CalendarService.eventTimeString(event)
                    + (event.location.map { " · \($0)" } ?? ""),
                icon: nil,
                symbolName: "calendar",
                score: 0.85 - Double(i) * 0.01,
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
            )
        }
    }
}

// MARK: - Reminders in search

enum ReminderProvider {
    static func results(for q: String) -> [SearchResult] {
        var out: [SearchResult] = []

        // "remind me to X at 5pm" → create a reminder
        if let parsed = CalendarService.parseReminder(q) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            let when = parsed.date.map { df.string(from: $0) } ?? "no due date"
            out.append(SearchResult(
                id: "rem:create",
                kind: .reminder,
                title: "Create Reminder: \(parsed.title)",
                subtitle: when + " · saved to Apple Reminders",
                icon: nil,
                symbolName: "plus.circle.fill",
                score: 9,
                action: {
                    CalendarService.shared.requestAccessIfNeeded {
                        _ = CalendarService.shared.createReminder(title: parsed.title, due: parsed.date)
                        WidgetDataStore.shared.refresh()
                    }
                }
            ))
        }

        // Due reminders (cached by the widget store)
        let due = WidgetDataStore.shared.dueReminders
        let listKeyword = Fuzzy.score(q, "reminders") != nil
        for (i, reminder) in due.enumerated() {
            let titleMatch = Fuzzy.score(q, reminder.title ?? "") != nil
            guard listKeyword || titleMatch else { continue }
            let dueStr: String
            if let comps = reminder.dueDateComponents,
               let date = Calendar.current.date(from: comps) {
                dueStr = date < Date() ? "Overdue" : "Due today"
            } else {
                dueStr = "Reminder"
            }
            out.append(SearchResult(
                id: "rem:\(reminder.calendarItemIdentifier)",
                kind: .reminder,
                title: reminder.title ?? "Untitled",
                subtitle: dueStr + " · ⏎ opens Reminders",
                icon: nil,
                symbolName: "checklist",
                score: 0.8 - Double(i) * 0.01,
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }
            ))
        }
        return out
    }
}
