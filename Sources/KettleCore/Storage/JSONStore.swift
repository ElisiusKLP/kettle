import Foundation

/// Schedules the debounced flush. Injected so tests control time.
public protocol WriteScheduler {
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void)
}

public struct MainQueueScheduler: WriteScheduler {
    public init() {}

    public func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Stores each document as a human-readable JSON file in `directory`.
///
/// Not thread-safe: use it from the main thread. It keeps nothing in memory except
/// documents waiting for the debounced write.
public final class JSONStore: Store {
    public static let debounceInterval: TimeInterval = 0.5

    public let directory: URL
    /// Receives errors from debounced writes and blocked saves.
    public var onWriteError: ((Error) -> Void)?

    private let fileSystem: FileSystem
    private let scheduler: WriteScheduler
    private let migrator: Migrator
    private let calendar: Calendar
    private let encoder = KettleJSON.makeEncoder()
    private let decoder = KettleJSON.makeDecoder()

    /// Documents saved but not yet written, keyed by relative path.
    private var pending: [String: any StoredDocument] = [:]
    /// Files that exist but failed to load. Saving over them would lose data.
    private var blocked: Set<String> = []
    private var flushScheduled = false
    /// Identifies the latest scheduled flush, so a stale one (superseded by `flush()`) does nothing.
    private var flushGeneration = 0

    public init(
        directory: URL,
        fileSystem: FileSystem = LocalFileSystem(),
        scheduler: WriteScheduler = MainQueueScheduler(),
        migrator: Migrator = .standard,
        calendar: Calendar = .current
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.scheduler = scheduler
        self.migrator = migrator
        self.calendar = calendar
    }

    var hasPendingWrites: Bool {
        !pending.isEmpty
    }

    // MARK: Store

    public func loadSettings() throws -> AppSettings {
        try load(AppSettings.self, at: StorePath.settings) ?? AppSettings()
    }

    public func saveSettings(_ settings: AppSettings) {
        enqueue(settings, at: StorePath.settings)
    }

    public func loadLabels() throws -> [Label] {
        try load(LabelList.self, at: StorePath.labels)?.labels ?? []
    }

    public func saveLabels(_ labels: [Label]) {
        enqueue(LabelList(labels: labels), at: StorePath.labels)
    }

    public func loadPlan(for date: LocalDate) throws -> DayPlan {
        try load(DayPlan.self, at: StorePath.plan(for: date)) ?? DayPlan(date: date)
    }

    public func savePlan(_ plan: DayPlan) {
        enqueue(plan, at: StorePath.plan(for: plan.date))
    }

    public func loadSessions(monthOf date: LocalDate) throws -> [Session] {
        try load(SessionLog.self, at: StorePath.sessions(monthKey: date.monthKey))?.sessions ?? []
    }

    public func appendSession(_ session: Session) throws {
        let path = StorePath.sessions(monthKey: LocalDate(session.start, in: calendar).monthKey)
        var log = try load(SessionLog.self, at: path) ?? SessionLog()
        log.sessions.append(session)
        enqueue(log, at: path)
    }

    public func loadDailyTotals() throws -> DailyTotals {
        try load(DailyTotals.self, at: StorePath.dailyTotals) ?? DailyTotals()
    }

    public func saveDailyTotals(_ totals: DailyTotals) {
        enqueue(totals, at: StorePath.dailyTotals)
    }

    public func planDates() throws -> [LocalDate] {
        try datedFiles(in: "plans").compactMap(LocalDate.init)
    }

    public func sessionMonths() throws -> [LocalDate] {
        try datedFiles(in: "sessions").compactMap { LocalDate($0 + "-01") }
    }

    public func flush() throws {
        flushScheduled = false
        var firstError: Error?
        for path in pending.keys.sorted() {
            guard let document = pending[path] else { continue }
            do {
                var data = try migrator.encode(document, using: encoder)
                data.append(0x0A) // end with a newline, like any text file
                try fileSystem.writeAtomically(data, to: url(for: path))
                pending[path] = nil
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: Private

    private func url(for path: String) -> URL {
        directory.appendingPathComponent(path, isDirectory: false)
    }

    /// Base names of the `.json` files in `folder`, including ones not yet written, sorted.
    private func datedFiles(in folder: String) throws -> [String] {
        let onDisk = try fileSystem.fileNames(in: url(for: folder))
        let pendingNames = pending.keys.filter { $0.hasPrefix(folder + "/") }
            .map { String($0.dropFirst(folder.count + 1)) }
        let names = Set(onDisk + pendingNames).filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
        return names.sorted()
    }

    private func load<T: StoredDocument>(_: T.Type, at path: String) throws -> T? {
        if let document = pending[path] {
            return document as? T
        }
        guard let data = try fileSystem.contents(of: url(for: path)) else {
            return nil
        }
        do {
            let document = try migrator.decode(T.self, from: data, using: decoder)
            blocked.remove(path)
            return document
        } catch {
            blocked.insert(path)
            throw StoreError.unreadable(path: path, reason: String(describing: error))
        }
    }

    private func enqueue(_ document: some StoredDocument, at path: String) {
        guard !blocked.contains(path) else {
            onWriteError?(StoreError.writeBlocked(path: path))
            return
        }
        pending[path] = document
        guard !flushScheduled else { return }
        flushScheduled = true
        flushGeneration += 1
        let generation = flushGeneration
        scheduler.schedule(after: Self.debounceInterval) { [weak self] in
            guard let self, flushScheduled, generation == flushGeneration else { return }
            do {
                try flush()
            } catch {
                onWriteError?(error)
            }
        }
    }
}
