import Foundation
@testable import KettleCore
import Testing

struct DataLocationTests {
    let support = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)

    @Test func environmentOverrideWins() {
        let url = DataLocation.resolve(
            environment: ["KETTLE_DATA_DIR": "/tmp/kettle-scratch"],
            bundleIdentifier: Kettle.devBundleID,
            applicationSupport: support
        )
        #expect(url.path == "/tmp/kettle-scratch")
    }

    @Test func environmentOverrideExpandsTilde() {
        let url = DataLocation.resolve(
            environment: ["KETTLE_DATA_DIR": "~/scratch/../kettle"], bundleIdentifier: nil, applicationSupport: support
        )
        #expect(url.path == NSHomeDirectory() + "/kettle")
    }

    @Test func emptyOverrideIsIgnored() {
        let url = DataLocation.resolve(
            environment: ["KETTLE_DATA_DIR": ""], bundleIdentifier: Kettle.bundleID, applicationSupport: support
        )
        #expect(url.path == "/Users/test/Library/Application Support/Kettle")
    }

    @Test func devBundleUsesItsOwnFolder() {
        let url = DataLocation.resolve(
            environment: [:],
            bundleIdentifier: Kettle.devBundleID,
            applicationSupport: support
        )
        #expect(url.path == "/Users/test/Library/Application Support/Kettle-Dev")
    }

    @Test(arguments: [Kettle.bundleID, nil, "com.example.other"])
    func everythingElseUsesTheDefaultFolder(bundleIdentifier: String?) {
        let url = DataLocation.resolve(
            environment: [:],
            bundleIdentifier: bundleIdentifier,
            applicationSupport: support
        )
        #expect(url.path == "/Users/test/Library/Application Support/Kettle")
    }

    @Test func resolvesForTheRunningProcess() throws {
        let url = try DataLocation.resolve()
        #expect(url.hasDirectoryPath)
    }
}
