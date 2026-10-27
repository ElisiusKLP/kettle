import Foundation

/// The file operations `JSONStore` needs. Injected so tests can observe which files are read.
public protocol FileSystem {
    /// The file's contents, or nil if it doesn't exist.
    func contents(of url: URL) throws -> Data?
    /// Replaces the file atomically, creating parent folders as needed.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Names of the files in a folder, or an empty list if it doesn't exist.
    func fileNames(in folder: URL) throws -> [String]
    /// Removes a file or folder. Does nothing if it doesn't exist.
    func removeItem(at url: URL) throws
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func contents(of url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func fileNames(in folder: URL) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    public func removeItem(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Writes to a temporary file in the same folder, then renames it over the destination,
    /// so readers see either the old or the new contents, never a partial file.
    public func writeAtomically(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        guard rename(temporary.path, url.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? FileManager.default.removeItem(at: temporary)
            throw POSIXError(code)
        }
    }
}
