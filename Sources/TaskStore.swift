import Foundation

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var addedOn: Date
    /// Most recent completion. For a daily task it only counts as done if this is today.
    var doneAt: Date?
    /// Daily tasks come back unchecked every morning.
    var repeatsDaily = false
    /// The completion before `doneAt`, so un-ticking a daily task doesn't lose its history.
    var previousDoneAt: Date?

    init(title: String, addedOn: Date, repeatsDaily: Bool) {
        self.title = title
        self.addedOn = addedOn
        self.repeatsDaily = repeatsDaily
    }

    // Written by hand so task files from before daily tasks existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        addedOn = try c.decode(Date.self, forKey: .addedOn)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        repeatsDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatsDaily) ?? false
        previousDoneAt = try c.decodeIfPresent(Date.self, forKey: .previousDoneAt)
    }
}

/// One ticked-off task, kept after the task itself is gone so the week view can show it.
struct Completion: Codable, Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var title: String
    var doneAt: Date
    var repeatsDaily: Bool
    /// Which day the task had been waiting when it was finished (1 = done the day it was due).
    var dayNumber: Int
}

/// How pressing a task is, based on how many days it has been waiting.
enum Urgency {
    case normal   // day 1
    case warning  // day 2 — orange
    case overdue  // day 3 or later — red
}

/// Holds the task list, saves it to disk and keeps track of what "today" is.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var completions: [Completion] = []
    @Published private(set) var today = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current
    private let fileURL: URL
    private let historyURL: URL
    private var timer: Timer?

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DayList", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("tasks.json")
        historyURL = folder.appendingPathComponent("history.json")
        load()
        loadHistory()
        pruneOldDoneTasks()

        // Catch midnight so tasks age (and daily ones reset) without a restart.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rollOverIfNeeded() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rollOverIfNeeded() }
        }
    }

    // MARK: - What to show

    func isDone(_ task: TaskItem) -> Bool {
        guard let doneAt = task.doneAt else { return false }
        return task.repeatsDaily ? calendar.isDate(doneAt, inSameDayAs: today) : true
    }

    /// Unfinished tasks and daily tasks, plus anything ticked off today.
    /// Most urgent first, finished ones at the bottom.
    var visibleTasks: [TaskItem] {
        tasks.enumerated()
            .filter { _, task in
                guard !task.repeatsDaily, let doneAt = task.doneAt else { return true }
                return calendar.isDate(doneAt, inSameDayAs: today)
            }
            .sorted { a, b in
                let aDone = isDone(a.element), bDone = isDone(b.element)
                if aDone != bDone { return !aDone }
                let aDay = dayNumber(of: a.element), bDay = dayNumber(of: b.element)
                if !aDone && aDay != bDay { return aDay > bDay }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Which day the task has been waiting for, starting at 1.
    /// One-off tasks count from the day they were added. Daily tasks count from the
    /// day after they were last done, so missing one day makes the next day "day 2".
    func dayNumber(of task: TaskItem) -> Int {
        var start = calendar.startOfDay(for: task.addedOn)
        if task.repeatsDaily, let last = lastCompletionBeforeToday(task),
           let dayAfter = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) {
            start = max(start, dayAfter)
        }
        return max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }

    func urgency(of task: TaskItem) -> Urgency {
        if isDone(task) { return .normal }
        switch dayNumber(of: task) {
        case 1: return .normal
        case 2: return .warning
        default: return .overdue
        }
    }

    var overdueCount: Int { visibleTasks.filter { urgency(of: $0) == .overdue }.count }
    var remainingCount: Int { visibleTasks.filter { !isDone($0) }.count }

    private func lastCompletionBeforeToday(_ task: TaskItem) -> Date? {
        [task.doneAt, task.previousDoneAt]
            .compactMap { $0 }
            .filter { $0 < today }
            .max()
    }

    // MARK: - Editing

    func add(_ title: String, repeatsDaily: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed, addedOn: .now, repeatsDaily: repeatsDaily))
        save()
    }

    func toggle(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if isDone(tasks[i]) {
            let undone = tasks[i].doneAt
            completions.removeAll { $0.taskID == task.id && $0.doneAt == undone }
            // Un-ticking a daily task brings back its previous completion.
            tasks[i].doneAt = tasks[i].repeatsDaily ? tasks[i].previousDoneAt : nil
            tasks[i].previousDoneAt = nil
        } else {
            tasks[i].previousDoneAt = tasks[i].repeatsDaily ? tasks[i].doneAt : nil
            let now = Date.now
            completions.append(Completion(taskID: task.id, title: tasks[i].title, doneAt: now,
                                          repeatsDaily: tasks[i].repeatsDaily, dayNumber: dayNumber(of: tasks[i])))
            tasks[i].doneAt = now
        }
        save()
        saveHistory()
    }

    func setRepeatsDaily(_ task: TaskItem, _ repeats: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].repeatsDaily = repeats
        tasks[i].previousDoneAt = nil
        // Switching a long-done one-off to daily shouldn't make it instantly red.
        if repeats, let doneAt = tasks[i].doneAt, doneAt < today { tasks[i].addedOn = .now }
        save()
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    /// Restarts the day count, which clears the orange/red warning.
    func moveToToday(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].addedOn = .now
        if tasks[i].repeatsDaily {
            tasks[i].doneAt = nil
            tasks[i].previousDoneAt = nil
        }
        save()
    }

    func rollOverIfNeeded() {
        let start = calendar.startOfDay(for: .now)
        guard start != today else { return }
        today = start
        pruneOldDoneTasks()
    }

    // MARK: - Persistence

    /// Finished one-off tasks are hidden after their day; drop them from the file after 30 days.
    private func pruneOldDoneTasks() {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: today) else { return }
        let before = tasks.count
        tasks.removeAll { !$0.repeatsDaily && ($0.doneAt ?? .distantFuture) < cutoff }
        if tasks.count != before { save() }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode([TaskItem].self, from: data) else { return }
        tasks = saved
    }

    /// The first time the log is created, fill it from the completions tasks still remember.
    private func loadHistory() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: historyURL),
           let saved = try? decoder.decode([Completion].self, from: data) {
            let cutoff = calendar.date(byAdding: .day, value: -180, to: today) ?? .distantPast
            completions = saved.filter { $0.doneAt >= cutoff }
            return
        }
        for task in tasks {
            for doneAt in [task.previousDoneAt, task.doneAt].compactMap({ $0 }) {
                let waited = calendar.dateComponents([.day], from: calendar.startOfDay(for: task.addedOn),
                                                     to: calendar.startOfDay(for: doneAt)).day ?? 0
                completions.append(Completion(taskID: task.id, title: task.title, doneAt: doneAt,
                                              repeatsDaily: task.repeatsDaily,
                                              dayNumber: task.repeatsDaily ? 1 : max(1, waited + 1)))
            }
        }
        saveHistory()
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(completions) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
