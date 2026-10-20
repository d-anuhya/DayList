import AppKit
import EventKit
import SwiftUI

/// An event from the Mac's Calendar app (which includes Google calendars added in Internet Accounts).
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

/// Reads events through EventKit, so no Google sign-in is needed inside DayList.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access { case notAsked, granted, denied }

    @Published private(set) var access: Access
    /// Bumped when calendars change and once a minute, so views showing "now" stay current.
    @Published private(set) var revision = 0

    private let store = EKEventStore()
    private var timer: Timer?

    init() {
        access = Self.currentAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func requestAccess() {
        guard access == .notAsked else { return }
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            revision += 1
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Events overlapping the given range, earliest first.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    // Repeating events share an identifier, so add the start time.
                    id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar?.color ?? .systemBlue)
                )
            }
    }

    /// Today's events that haven't finished yet, all-day ones first.
    func upcomingToday() -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let now = Date.now
        return events(from: start, to: end)
            .filter { $0.isAllDay || $0.end > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }
}
