import XCTest
import Foundation

/// `LibraryStore.listInternalLibraries()`: the TrackLibraries on disk.
@MainActor
final class LibraryStoreInternalListTests: XCTestCase {

    private func makeStore() throws -> LibraryStore {
        LibraryStore(db: try DatabaseManager())
    }

    func testWithoutAnyFolderTheListIsEmpty() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertEqual(try makeStore().listInternalLibraries(), [])
        }
    }

    func testEveryLibraryFolderIsListedNaturallySorted() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            try store.newLibrary(named: "Tango 10")
            try store.newLibrary(named: "Tango 2")
            try store.newLibrary(named: "Milonga")

            XCTAssertEqual(try store.listInternalLibraries(), ["Milonga", "Tango 2", "Tango 10"])
        }
    }

    func testFilesInTheRootAreNotLibraries() throws {
        try withTemporaryAppRoot { root in
            let store = try makeStore()
            try store.newLibrary(named: "Tango")
            try Data("{}".utf8).write(to: root.appendingPathComponent("AppSettings.json"))

            XCTAssertEqual(try store.listInternalLibraries(), ["Tango"])
        }
    }
}
