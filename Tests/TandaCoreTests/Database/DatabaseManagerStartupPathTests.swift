import XCTest
import Foundation
import GRDB

/// Which TrackLibrary file the app opens at launch: the remembered one, the
/// Default one, or a freshly created empty Default on the very first start.
@MainActor
final class DatabaseManagerStartupPathTests: XCTestCase {

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func opens(_ path: String) -> Bool {
        (try? DatabaseQueue(path: path).read { _ in true }) ?? false
    }

    // MARK: - defaultStorePath

    func testTheFirstLaunchCreatesTheFoldersAndAnEmptyDefaultLibrary() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertFalse(exists(AppPaths.defaultLibraryFile))

            let path = try DatabaseManager.defaultStorePath()

            XCTAssertEqual(path, AppPaths.defaultLibraryFile.path)
            XCTAssertTrue(exists(AppPaths.defaultLibraryFile))
            XCTAssertTrue(opens(path))
            XCTAssertEqual(try AppPaths.internalLibraryNames(), [AppPaths.defaultLibraryName])
        }
    }

    func testAnExistingDefaultLibraryIsNotReplaced() throws {
        try withTemporaryAppRoot { _ in
            let first = try DatabaseManager.defaultStorePath()
            let before = try Data(contentsOf: URL(fileURLWithPath: first))

            let second = try DatabaseManager.defaultStorePath()

            XCTAssertEqual(second, first)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: second)), before)
        }
    }

    // MARK: - startupStorePath

    func testStartupOpensTheRememberedLibrary() throws {
        try withTemporaryAppRoot { _ in
            let tango = AppPaths.libraryFile(named: "Tango")
            try DatabaseManager.createEmptyLibrary(at: tango.path)
            AppPaths.currentLibraryName = "Tango"

            let path = try DatabaseManager.startupStorePath()

            XCTAssertEqual(path, tango.path)
            XCTAssertEqual(AppPaths.currentLibraryName, "Tango")
            XCTAssertFalse(exists(AppPaths.defaultLibraryFile), "Default is not created when another library is remembered")
        }
    }

    func testStartupFallsBackToDefaultWhenTheRememberedLibraryIsGone() throws {
        try withTemporaryAppRoot { _ in
            AppPaths.currentLibraryName = "Gone"

            let path = try DatabaseManager.startupStorePath()

            XCTAssertEqual(path, AppPaths.defaultLibraryFile.path)
            XCTAssertEqual(
                AppPaths.currentLibraryName,
                AppPaths.defaultLibraryName,
                "every other store must resolve against the same fallback"
            )
            XCTAssertTrue(exists(AppPaths.defaultLibraryFile))
            XCTAssertTrue(opens(path))
            XCTAssertFalse(exists(AppPaths.libraryFile(named: "Gone")))
        }
    }

    func testStartupWithoutAnyLibraryCreatesTheDefault() throws {
        try withTemporaryAppRoot { _ in
            let path = try DatabaseManager.startupStorePath()

            XCTAssertEqual(path, AppPaths.defaultLibraryFile.path)
            XCTAssertTrue(opens(path))
        }
    }

    func testStartupKeepsTheRememberedLibraryWhenDefaultAlsoExists() throws {
        try withTemporaryAppRoot { _ in
            _ = try DatabaseManager.defaultStorePath()
            let tango = AppPaths.libraryFile(named: "Tango")
            try DatabaseManager.createEmptyLibrary(at: tango.path)
            AppPaths.currentLibraryName = "Tango"

            XCTAssertEqual(try DatabaseManager.startupStorePath(), tango.path)
            XCTAssertEqual(AppPaths.currentLibraryName, "Tango")
        }
    }
}
