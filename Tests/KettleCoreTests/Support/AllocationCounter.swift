import Darwin

/// Counts heap allocations made by the current thread, using libmalloc's `malloc_logger`
/// hook (the one Instruments uses). Other threads, like parallel tests, are ignored.
enum AllocationCounter {
    private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    /// `MALLOC_LOG_TYPE_ALLOCATE` in `<malloc/malloc.h>`'s logging flags.
    private static let allocateFlag: UInt32 = 2

    private static let hook: UnsafeMutablePointer<Logger?>? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        return dlsym(defaultHandle, "malloc_logger")?.assumingMemoryBound(to: Logger?.self)
    }()

    static var isAvailable: Bool {
        hook != nil
    }

    /// Allocations `body` makes on this thread.
    static func count(_ body: () -> Void) -> Int {
        guard let hook else { return -1 }
        countedAllocations = 0
        countedThread = pthread_self()
        hook.pointee = { type, _, _, _, _, _ in
            guard let thread = countedThread, pthread_equal(pthread_self(), thread) != 0,
                  type & AllocationCounter.allocateFlag != 0
            else { return }
            countedAllocations += 1
        }
        body()
        hook.pointee = nil
        countedThread = nil
        return countedAllocations
    }
}

// Globals, because the C callback can't capture context. Only the counted thread writes them.
private var countedAllocations = 0
private var countedThread: pthread_t?
