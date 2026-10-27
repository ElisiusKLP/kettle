import Foundation

/// Everything Kettle stores, as one JSON document for Settings → Data → Export and Import.
public struct KettleExport: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var settings: AppSettings
    public var labels: [Label]
    /// Oldest first.
    public var plans: [DayPlan]
    /// Oldest first.
    public var sessions: [Session]
}

public enum DataTransferError: Error, Equatable {
    case newerFormat(found: Int, supported: Int)
}

/// Export to JSON and CSV, and import (merge) from JSON.
public enum DataTransfer {
    public struct ImportSummary: Equatable, Sendable {
        public var labels = 0
        public var plans = 0
        /// Sessions that weren't already there.
        public var newSessions = 0
    }

    /// Reads every file in the store. Only used for export, so the full history is in memory
    /// only briefly.
    public static func export(from store: Store, exportedAt: Date) throws -> KettleExport {
        var sessions: [Session] = []
        for month in try store.sessionMonths() {
            sessions += try store.loadSessions(monthOf: month)
        }
        return try KettleExport(
            formatVersion: KettleExport.currentFormatVersion,
            exportedAt: exportedAt,
            settings: store.loadSettings(),
            labels: store.loadLabels(),
            plans: store.planDates().map(store.loadPlan(for:)),
            sessions: sessions.sorted { $0.start < $1.start }
        )
    }

    public static func encode(_ export: KettleExport) throws -> Data {
        var data = try KettleJSON.makeEncoder().encode(export)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> KettleExport {
        let export = try KettleJSON.makeDecoder().decode(KettleExport.self, from: data)
        guard export.formatVersion <= KettleExport.currentFormatVersion else {
            throw DataTransferError.newerFormat(
                found: export.formatVersion,
                supported: KettleExport.currentFormatVersion
            )
        }
        return export
    }

    /// Merges an export into the store without deleting anything: labels are matched by ID (the
    /// imported version wins), an imported day's plan replaces that day's plan, sessions are
    /// added unless already there, and settings are replaced. The stats cache is rebuilt.
    @discardableResult
    public static func merge(_ export: KettleExport, into store: Store, calendar: Calendar) throws -> ImportSummary {
        var summary = ImportSummary()

        store.saveSettings(export.settings)

        var labels = try store.loadLabels()
        for label in export.labels {
            if let index = labels.firstIndex(where: { $0.id == label.id }) {
                labels[index] = label
            } else {
                labels.append(label)
            }
            summary.labels += 1
        }
        store.saveLabels(labels)

        for plan in export.plans {
            store.savePlan(plan)
            summary.plans += 1
        }

        let byMonth = Dictionary(grouping: export.sessions) { LocalDate($0.start, in: calendar).startOfMonth }
        for (month, imported) in byMonth {
            var sessions = try store.loadSessions(monthOf: month)
            let known = Set(sessions.map(\.id))
            let new = imported.filter { !known.contains($0.id) }
            guard !new.isEmpty else { continue }
            sessions = (sessions + new).sorted { $0.start < $1.start }
            store.saveSessions(sessions, monthOf: month)
            summary.newSessions += new.count
        }

        try DailyTotalsCache(store: store, calendar: calendar).rebuild()
        return summary
    }

    /// One row per session, for spreadsheets: local date and times, minutes, label and task.
    public static func csv(_ export: KettleExport, calendar: Calendar) -> String {
        let titles = Dictionary(export.plans.flatMap(\.tasks).map { ($0.id, $0.title) }) { first, _ in first }
        let labelNames = Dictionary(export.labels.map { ($0.id, $0.name) }) { first, _ in first }
        var lines = ["date,start,end,minutes,label,task,extension_minutes"]
        for session in export.sessions {
            let fields = [
                LocalDate(session.start, in: calendar).description,
                clockTime(session.start, calendar: calendar),
                clockTime(session.end, calendar: calendar),
                String(format: "%.1f", session.duration / 60),
                session.labelID.flatMap { labelNames[$0] } ?? "",
                titles[session.taskID] ?? "",
                String(session.extensionsMinutes),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func clockTime(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// RFC 4180: quote fields containing commas, quotes or line breaks; double inner quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
