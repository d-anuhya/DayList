import SwiftUI

enum Palette {
    static let sage = Color(red: 0.45, green: 0.72, blue: 0.58)
    static let amber = Color(red: 0.95, green: 0.58, blue: 0.22)
    static let rose = Color(red: 0.93, green: 0.33, blue: 0.36)

    static func tint(for urgency: Urgency) -> Color? {
        switch urgency {
        case .normal: nil
        case .warning: amber
        case .overdue: rose
        }
    }
}

struct DayListView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var calendarStore: CalendarStore
    let onOpenWeek: () -> Void
    // `State(...)` instead of `@State`: the @State macro needs full Xcode to compile.
    private let draftState = State(initialValue: "")
    private var draft: String {
        get { draftState.wrappedValue }
        nonmutating set { draftState.wrappedValue = newValue }
    }
    private let repeatState = State(initialValue: false)
    private var draftRepeats: Bool {
        get { repeatState.wrappedValue }
        nonmutating set { repeatState.wrappedValue = newValue }
    }

    var body: some View {
        let tasks = store.visibleTasks

        VStack(alignment: .leading, spacing: 14) {
            header(tasks)

            if store.overdueCount > 0 {
                overdueBanner
            }

            let events = calendarStore.upcomingToday()
            if !events.isEmpty {
                UpNextList(events: events)
            }

            if tasks.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(tasks) { task in
                            TaskRow(
                                task: task,
                                done: store.isDone(task),
                                day: store.dayNumber(of: task),
                                urgency: store.urgency(of: task),
                                onToggle: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.toggle(task) } },
                                onDelete: { withAnimation(.easeOut(duration: 0.2)) { store.delete(task) } },
                                onMoveToToday: { withAnimation { store.moveToToday(task) } },
                                onSetRepeats: { repeats in withAnimation { store.setRepeatsDaily(task, repeats) } }
                            )
                        }
                    }
                }
            }

            addField
        }
        .padding(20)
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity, alignment: .top)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func header(_ tasks: [TaskItem]) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.today, format: .dateTime.weekday(.wide))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(store.today, format: .dateTime.month(.wide).day())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenWeek) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Show this week")
            ProgressRing(done: tasks.filter(store.isDone).count, total: tasks.count)
        }
    }

    private var overdueBanner: some View {
        let n = store.overdueCount
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(n == 1 ? "1 task has to be done today" : "\(n) tasks have to be done today")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Palette.rose)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.rose.opacity(0.14)))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 28, weight: .light))
            Text("A clear day")
                .font(.system(size: 14, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Add a task", text: draftState.projectedValue)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .rounded))
                .onSubmit {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.add(draft, repeatsDaily: draftRepeats) }
                    draft = ""
                    draftRepeats = false
                }
            Button { draftRepeats.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(draftRepeats ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tertiary))
                    .frame(width: 24, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(draftRepeats ? Palette.sage : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(draftRepeats ? "Repeats every day" : "Make this a daily task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// Today's remaining calendar events, shown above the tasks.
struct UpNextList: View {
    let events: [CalendarEvent]
    private let maxShown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(events.prefix(maxShown)) { event in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3, height: 16)
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeLabel(event))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(event.start <= .now && !event.isAllDay ? AnyShapeStyle(event.color) : AnyShapeStyle(.secondary))
                }
            }
            if events.count > maxShown {
                Text("+\(events.count - maxShown) more today")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 11)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func timeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        if event.start <= .now { return "Now" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

struct TaskRow: View {
    let task: TaskItem
    let done: Bool
    let day: Int
    let urgency: Urgency
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onMoveToToday: () -> Void
    let onSetRepeats: (Bool) -> Void

    private var caption: String? {
        switch (urgency, task.repeatsDaily) {
        case (.normal, _): nil
        case (.warning, false): "Day 2 · carried over"
        case (.overdue, false): "Day \(day) · finish today"
        case (.warning, true): "Missed yesterday"
        case (.overdue, true): "Missed \(day - 1) days · do it today"
        }
    }

    private let hoverState = State(initialValue: false)
    private var hovering: Bool {
        get { hoverState.wrappedValue }
        nonmutating set { hoverState.wrappedValue = newValue }
    }

    private var tint: Color? { Palette.tint(for: urgency) }

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(done: done, tint: tint ?? Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? AnyShapeStyle(.secondary) : urgency == .overdue ? AnyShapeStyle(Palette.rose) : AnyShapeStyle(.primary))
                    if task.repeatsDaily {
                        Image(systemName: "repeat")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .help("Repeats every day")
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle((tint ?? .secondary).opacity(0.9))
                }
            }

            Spacer(minLength: 4)

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.map { $0.opacity(hovering ? 0.2 : 0.14) } ?? Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            Button(done ? "Mark as Not Done" : "Mark as Done", action: onToggle)
            if urgency != .normal {
                Button(task.repeatsDaily ? "Reset Missed Days" : "Move to Today", action: onMoveToToday)
            }
            Button(task.repeatsDaily ? "Stop Repeating Daily" : "Repeat Daily") { onSetRepeats(!task.repeatsDaily) }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct CheckCircle: View {
    let done: Bool
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(done ? 0 : 0.7), lineWidth: 1.5)
            Circle()
                .fill(Palette.sage)
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .opacity(done ? 1 : 0)
        }
        .frame(width: 18, height: 18)
    }
}

struct ProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.sage, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
            Text("\(done)/\(total)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 40, height: 40)
    }
}

/// Frosted-glass backdrop that blurs whatever sits behind the window.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
