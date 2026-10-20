import SwiftUI

/// A Monday-to-Sunday timeline: calendar events as blocks, finished tasks as ticks at the time
/// they were done, and a row of the week's achievements on top.
struct WeekView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarStore: CalendarStore

    // `State(...)` instead of `@State`: the @State macro needs full Xcode to compile.
    private let offsetState = State(initialValue: 0)
    /// 0 is this week, -1 last week, and so on.
    private var weekOffset: Int {
        get { offsetState.wrappedValue }
        nonmutating set { offsetState.wrappedValue = newValue }
    }

    private let cal = Calendar.current
    private let hourHeight: CGFloat = 46
    private let gutter: CGFloat = 52

    private var days: [Date] {
        let base = cal.date(byAdding: .weekOfYear, value: weekOffset, to: store.today) ?? store.today
        let start = cal.dateInterval(of: .weekOfYear, for: base)?.start ?? cal.startOfDay(for: base)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let days = self.days
        let weekStart = days[0]
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let events = calendarStore.events(from: weekStart, to: weekEnd)
        let done = store.completions.filter { $0.doneAt >= weekStart && $0.doneAt < weekEnd }
        let hours = hourRange(events: events, done: done)

        VStack(alignment: .leading, spacing: 14) {
            toolbar(weekStart: weekStart, weekEnd: weekEnd)
            if calendarStore.access != .granted {
                accessBanner
            }
            summary(days: days, events: events, done: done, weekStart: weekStart)

            VStack(spacing: 0) {
                dayHeaders(days: days, done: done)
                allDayStrip(days: days, events: events)
                Divider().opacity(0.5)
                ScrollView(showsIndicators: false) {
                    timeline(days: days, events: events, done: done, hours: hours)
                        .padding(.vertical, 10)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.035)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(minWidth: 760, minHeight: 520)
        // A near-solid backdrop: the widget's see-through glass washes out coloured text here.
        .background(GlassBackground(material: .windowBackground))
    }

    // MARK: - Top

    private func toolbar(weekStart: Date, weekEnd: Date) -> some View {
        let lastDay = cal.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
        let title = switch weekOffset {
        case 0: "This Week"
        case -1: "Last Week"
        case 1: "Next Week"
        default: "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("\(weekStart.formatted(.dateTime.month(.wide).day())) – \(lastDay.formatted(.dateTime.month(.wide).day()))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                navButton("chevron.left", help: "Previous week") { weekOffset -= 1 }
                Button { weekOffset = 0 } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(weekOffset == 0)
                navButton("chevron.right", help: "Next week") { weekOffset += 1 }
            }
        }
    }

    private func navButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var accessBanner: some View {
        let asked = calendarStore.access == .denied
        return HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(Palette.amberInk)
            VStack(alignment: .leading, spacing: 1) {
                Text(asked ? "DayList can't see your calendar" : "Show your Google Calendar here")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(asked ? "Turn DayList on under Privacy & Security → Calendars."
                           : "Add Google under System Settings → Internet Accounts, then connect.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(asked ? "Open Settings" : "Connect") {
                if asked { calendarStore.openPrivacySettings() } else { calendarStore.requestAccess() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.amber.opacity(0.1)))
    }

    // MARK: - Achievements

    private func summary(days: [Date], events: [CalendarEvent], done: [Completion], weekStart: Date) -> some View {
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let lastWeekCount = store.completions.filter { $0.doneAt >= lastWeekStart && $0.doneAt < weekStart }.count
        let diff = done.count - lastWeekCount
        let compare = diff == 0 ? "Same as last week" : diff > 0 ? "\(diff) more than last week" : "\(-diff) fewer than last week"

        let perDay = days.map { day in (day, done.filter { cal.isDate($0.doneAt, inSameDayAs: day) }.count) }
        let best = perDay.max { $0.1 < $1.1 }
        let carried = done.filter { !$0.repeatsDaily && $0.dayNumber >= 2 }.count

        let streak = longestStreak()
        let timed = events.filter { !$0.isAllDay }
        let booked = timed.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600

        return HStack(spacing: 10) {
            StatCard(icon: "checkmark.circle.fill", title: "Done", value: "\(done.count)",
                     detail: compare, tint: Palette.sage)
            StatCard(icon: "star.fill", title: "Best day",
                     value: (best?.1 ?? 0) > 0 ? best!.0.formatted(.dateTime.weekday(.wide)) : "—",
                     detail: (best?.1 ?? 0) > 0 ? "\(best!.1) tasks done" : "Nothing finished yet", tint: Palette.amber)
            StatCard(icon: "arrow.uturn.forward.circle.fill", title: "Caught up", value: "\(carried)",
                     detail: "Carried-over tasks finished", tint: Palette.rose)
            StatCard(icon: "flame.fill", title: "Streak",
                     value: streak.map { "\($0.days) day\($0.days == 1 ? "" : "s")" } ?? "—",
                     detail: streak?.title ?? "No daily streak yet", tint: .orange)
            StatCard(icon: "calendar", title: "Calendar", value: "\(timed.count) events",
                     detail: String(format: "%.1f h booked", booked), tint: .blue)
        }
    }

    /// The daily task with the longest run of days done in a row, ending today or yesterday.
    private func longestStreak() -> (title: String, days: Int)? {
        var best: (title: String, days: Int)?
        for task in store.tasks where task.repeatsDaily {
            let doneDays = Set(store.completions.filter { $0.taskID == task.id }.map { cal.startOfDay(for: $0.doneAt) })
            var day = store.today
            if !doneDays.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
            var count = 0
            while doneDays.contains(day) {
                count += 1
                guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            }
            if count > 0, count > (best?.days ?? 0) { best = (task.title, count) }
        }
        return best
    }

    // MARK: - Timeline

    private func dayHeaders(days: [Date], done: [Completion]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDate(day, inSameDayAs: store.today)
                let count = done.filter { cal.isDate($0.doneAt, inSameDayAs: day) }.count
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? AnyShapeStyle(Palette.sageInk) : AnyShapeStyle(.secondary))
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(isToday ? Palette.sage : .clear))
                    Text(count > 0 ? "✓ \(count)" : " ")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.sageInk)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func allDayStrip(days: [Date], events: [CalendarEvent]) -> some View {
        if events.contains(where: \.isAllDay) {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: gutter - 8, alignment: .trailing)
                    .padding(.trailing, 8)
                ForEach(days, id: \.self) { day in
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
                    let allDay = events.filter { $0.isAllDay && $0.start < dayEnd && $0.end > day }
                    VStack(spacing: 2) {
                        ForEach(allDay.prefix(2)) { event in
                            Text(event.title)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(event.color.opacity(0.25)))
                                .help(event.title)
                        }
                        if allDay.count > 2 {
                            Text("+\(allDay.count - 2)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func timeline(days: [Date], events: [CalendarEvent], done: [Completion], hours: Range<Int>) -> some View {
        let height = CGFloat(hours.count) * hourHeight
        return HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach(Array(hours), id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 8)
                        .offset(y: CGFloat(hour - hours.lowerBound) * hourHeight - 6)
                }
            }
            .frame(width: gutter, height: height, alignment: .topTrailing)

            ForEach(days, id: \.self) { day in
                let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
                DayColumn(
                    day: day,
                    events: events.filter { !$0.isAllDay && $0.start < dayEnd && $0.end > day },
                    done: done.filter { cal.isDate($0.doneAt, inSameDayAs: day) }.sorted { $0.doneAt < $1.doneAt },
                    startHour: hours.lowerBound,
                    hourHeight: hourHeight,
                    isToday: cal.isDate(day, inSameDayAs: store.today)
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
                }
            }
        }
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(hours), id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: hourHeight)
                }
            }
            .padding(.leading, gutter)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: store.today) ?? store.today
        return date.formatted(.dateTime.hour())
    }

    /// 7am to 9pm, stretched to fit anything earlier or later this week.
    private func hourRange(events: [CalendarEvent], done: [Completion]) -> Range<Int> {
        var low = 7, high = 21
        for event in events where !event.isAllDay {
            low = min(low, cal.component(.hour, from: event.start))
            let length = cal.dateComponents([.hour, .minute], from: cal.startOfDay(for: event.start), to: event.end)
            high = max(high, (length.hour ?? 0) + ((length.minute ?? 0) > 0 ? 1 : 0))
        }
        for completion in done {
            let hour = cal.component(.hour, from: completion.doneAt)
            low = min(low, hour)
            high = max(high, hour + 1)
        }
        return low..<min(24, max(high, low + 1))
    }
}

/// One day of the timeline.
struct DayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let done: [Completion]
    let startHour: Int
    let hourHeight: CGFloat
    let isToday: Bool

    private struct Placed: Identifiable {
        let event: CalendarEvent
        let start: Date
        let end: Date
        var lane: Int
        var lanes = 1
        var id: String { event.id }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 6
            let maxY = geo.size.height
            ZStack(alignment: .topLeading) {
                if isToday {
                    Rectangle().fill(Palette.sage.opacity(0.05))
                }

                ForEach(placedEvents()) { placed in
                    let top = y(for: placed.start)
                    let laneWidth = width / CGFloat(placed.lanes)
                    EventBlock(event: placed.event, height: max(18, min(maxY, y(for: placed.end)) - top - 1))
                        .frame(width: laneWidth - 2, height: max(18, min(maxY, y(for: placed.end)) - top - 1))
                        .offset(x: 3 + CGFloat(placed.lane) * laneWidth, y: top)
                }

                ForEach(Array(doneOffsets().enumerated()), id: \.element.0.id) { _, item in
                    HStack(spacing: 0) {
                        Spacer(minLength: width * 0.12)
                        DoneChip(completion: item.0)
                    }
                    .frame(width: width)
                    .offset(x: 3, y: min(item.1, maxY - 20))
                }

                if isToday {
                    let nowY = y(for: .now)
                    if nowY > 0 && nowY < maxY {
                        HStack(spacing: 0) {
                            Circle().fill(Palette.rose).frame(width: 7, height: 7)
                            Rectangle().fill(Palette.rose).frame(height: 1.5)
                        }
                        .offset(x: -3, y: nowY - 3.5)
                    }
                }
            }
        }
    }

    private func y(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(day) / 60 - Double(startHour * 60)
        return max(0, CGFloat(minutes / 60) * hourHeight)
    }

    /// Side-by-side lanes for overlapping events.
    private func placedEvents() -> [Placed] {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        var result: [Placed] = []
        var group: [Placed] = []
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast

        func closeGroup() {
            let lanes = max(1, laneEnds.count)
            result += group.map { var p = $0; p.lanes = lanes; return p }
            group = []
            laneEnds = []
        }

        for event in events {
            let start = max(event.start, day), end = min(event.end, dayEnd)
            if start >= groupEnd { closeGroup() }
            if let lane = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[lane] = end
                group.append(Placed(event: event, start: start, end: end, lane: lane))
            } else {
                laneEnds.append(end)
                group.append(Placed(event: event, start: start, end: end, lane: laneEnds.count - 1))
            }
            groupEnd = max(groupEnd, end)
        }
        closeGroup()
        return result
    }

    /// Finished tasks at the time they were done, nudged down so they don't sit on top of each other.
    private func doneOffsets() -> [(Completion, CGFloat)] {
        var lastY = -CGFloat.infinity
        return done.map { completion in
            let top = max(y(for: completion.doneAt) - 9, lastY + 21)
            lastY = top
            return (completion, top)
        }
    }
}

struct EventBlock: View {
    let event: CalendarEvent
    let height: CGFloat

    var body: some View {
        let past = event.end < .now
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(height > 44 ? 2 : 1)
            if height > 32 {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(event.color.opacity(0.22)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3).padding(.vertical, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(past ? 0.6 : 1)
        .help("\(event.title)\n\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
    }
}

struct DoneChip: View {
    let completion: Completion

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Palette.sage))
            Text(completion.title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 7)
        .frame(height: 19)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Palette.sage.opacity(0.5), lineWidth: 1))
        .help("\(completion.title) — done at \(completion.doneAt.formatted(date: .omitted, time: .shortened))"
              + (completion.dayNumber >= 2 && !completion.repeatsDaily ? " (day \(completion.dayNumber))" : ""))
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(tint))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
