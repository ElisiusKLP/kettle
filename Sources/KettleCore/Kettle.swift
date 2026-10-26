/// App-wide constants shared by every target.
public enum Kettle {
    /// `os.Logger` subsystem. Dev and release builds share it so `make logs` sees both.
    public static let subsystem = "io.github.kettle"
    public static let bundleID = "io.github.kettle"
    public static let devBundleID = "io.github.kettle.dev"
}
