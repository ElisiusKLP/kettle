import Foundation
@testable import KettleCore

/// A unique folder under the system temp directory, removed when released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kettle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ string: String, to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(string.utf8).write(to: file)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    /// Relative paths of every file inside, including hidden ones.
    func allFiles() -> Set<String> {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        var paths = Set<String>()
        let base = url.resolvingSymlinksInPath().path + "/"
        while let file = enumerator?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            let path = file.resolvingSymlinksInPath().path
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                paths.insert(String(path.dropFirst(base.count)))
            }
        }
        return paths
    }
}

/// A clock tests move by hand.
final class FakeClock: Clock {
    var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_793_000_000)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
    }
}

/// Collects scheduled work instead of running it after a delay.
final class ManualScheduler: WriteScheduler {
    private(set) var scheduled: [(delay: TimeInterval, work: () -> Void)] = []

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        scheduled.append((delay, work))
    }

    func runAll() {
        let work = scheduled
        scheduled = []
        for item in work {
            item.work()
        }
    }
}

/// Records the files `JSONStore` touches, relative to `root`, and can fail writes on demand.
final class RecordingFileSystem: FileSystem {
    private let base = LocalFileSystem()
    private let root: URL
    private(set) var reads: [String] = []
    private(set) var writes: [String] = []
    var failWrites = false

    init(root: URL) {
        self.root = root
    }

    func contents(of url: URL) throws -> Data? {
        reads.append(relative(url))
        return try base.contents(of: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if failWrites {
            throw POSIXError(.ENOSPC)
        }
        writes.append(relative(url))
        try base.writeAtomically(data, to: url)
    }

    private func relative(_ url: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }
}

enum Fixtures {
    /// `Tests/Fixtures/data`: a complete sample data folder.
    static let dataFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // KettleCoreTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("Fixtures/data", isDirectory: true)

    static let files = ["settings.json", "labels.json", "plans/2026-10-26.json", "sessions/2026-10.json"]

    static func copy(to folder: TemporaryDirectory) throws {
        for file in files {
            try folder.write(String(contentsOf: dataFolder.appendingPathComponent(file), encoding: .utf8), to: file)
        }
    }
}

extension Calendar {
    static func gregorian(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }
}

extension Date {
    /// Parses an ISO 8601 timestamp such as `2026-10-26T09:00:00Z`.
    static func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

extension LocalDate {
    static func ymd(_ string: String) -> LocalDate {
        LocalDate(string)!
    }
}
