import Foundation

/// Resolves the folder Kettle keeps its data in.
public enum DataLocation {
    public static let environmentKey = "KETTLE_DATA_DIR"
    public static let folderName = "Kettle"
    public static let devFolderName = "Kettle-Dev"

    /// In priority order: `KETTLE_DATA_DIR`, then the dev bundle's `Kettle-Dev` folder, then `Kettle`.
    /// `applicationSupport` is the app's Application Support folder (inside the container when sandboxed).
    public static func resolve(
        environment: [String: String],
        bundleIdentifier: String?,
        applicationSupport: URL
    ) -> URL {
        if let override = environment[environmentKey], !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        let name = bundleIdentifier == Kettle.devBundleID ? devFolderName : folderName
        return applicationSupport.appendingPathComponent(name, isDirectory: true)
    }

    /// Resolves the folder for the running process.
    public static func resolve() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        return resolve(
            environment: ProcessInfo.processInfo.environment,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            applicationSupport: applicationSupport
        )
    }
}
