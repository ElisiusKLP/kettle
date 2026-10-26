import KettleCore
import os

/// Unified logging only; no log files (SPEC section 2). Stream with `make logs`.
enum Log {
    static let app = Logger(subsystem: Kettle.subsystem, category: "app")
    static let storage = Logger(subsystem: Kettle.subsystem, category: "storage")
}
