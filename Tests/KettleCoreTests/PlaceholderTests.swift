@testable import KettleCore
import Testing

struct PlaceholderTests {
    @Test func bundleIdentifiersAreDistinct() {
        #expect(Kettle.bundleID != Kettle.devBundleID)
        #expect(Kettle.subsystem == Kettle.bundleID)
    }
}
