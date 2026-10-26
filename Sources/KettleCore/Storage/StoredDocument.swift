import Foundation

/// The kinds of file Kettle stores. Each has its own schema version.
public enum DocumentKind: String, Sendable, CaseIterable {
    case settings, labels, plan, sessions, dailyTotals
}

/// A type stored as one JSON object in one file. On disk the object also carries a
/// `schemaVersion` key, which `Migrator` reads and writes.
public protocol StoredDocument: Codable, Sendable {
    static var kind: DocumentKind { get }
}

/// Relative paths of the files inside the data folder.
public enum StorePath {
    public static let settings = "settings.json"
    public static let labels = "labels.json"
    public static let dailyTotals = "stats/daily-totals.json"

    public static func plan(for date: LocalDate) -> String {
        "plans/\(date).json"
    }

    public static func sessions(monthKey: String) -> String {
        "sessions/\(monthKey).json"
    }
}

enum KettleJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
