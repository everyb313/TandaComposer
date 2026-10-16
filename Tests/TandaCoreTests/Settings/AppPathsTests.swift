import XCTest
import Foundation

@MainActor
final class AppPathsTests: XCTestCase {

    func testWithoutOverrideTheRootIsTheHiddenFolderInTheHomeDirectory() {
        // Only reads paths; nothing is created or written.
        XCTAssertNil(AppPaths.rootOverride, "a test forgot to restore the override")

        XCTAssertEqual(AppPaths.internalRoot.lastPathComponent, ".TandaComposer")
        XCTAssertTrue(
            samePath(
                AppPaths.internalRoot.deletingLastPathComponent(),
                FileManager.default.homeDirectoryForCurrentUser
            )
        )
    }

    func testOverrideRedirectsEverythingBelowTheRoot() throws {
        try withTemporaryAppRoot { root in
            XCTAssertTrue(samePath(AppPaths.root, root))
            XCTAssertTrue(samePath(AppPaths.libraryRoot, root.appendingPathComponent("Default")))
            XCTAssertTrue(samePath(AppPaths.setlistsFolder, root.appendingPathComponent("Default/Setlists")))
            XCTAssertTrue(samePath(AppPaths.smartlistFolder, root.appendingPathComponent("Default/Smartlists")))
            XCTAssertTrue(samePath(AppPaths.tandasFolder, root.appendingPathComponent("Default/Tandas")))
            XCTAssertTrue(samePath(AppPaths.appSettingsFile, root.appendingPathComponent("AppSettings.json")))
            XCTAssertTrue(samePath(AppPaths.defaultLibraryFile, root.appendingPathComponent("Default/Default.sqlite")))
        }
    }

    func testOverrideAndLibraryNameAreRestoredAfterwards() throws {
        let before = AppPaths.currentLibraryName

        try withTemporaryAppRoot { _ in
            AppPaths.currentLibraryName = "Something Else"
        }

        XCTAssertNil(AppPaths.rootOverride)
        XCTAssertEqual(AppPaths.currentLibraryName, before)
    }

    func testSwitchingTheLibraryNameMovesLibraryFoldersButNotTheSettingsFile() throws {
        try withTemporaryAppRoot { root in
            AppPaths.currentLibraryName = "Milongas"

            XCTAssertTrue(samePath(AppPaths.libraryRoot, root.appendingPathComponent("Milongas")))
            XCTAssertTrue(samePath(AppPaths.setlistsFolder, root.appendingPathComponent("Milongas/Setlists")))
            XCTAssertTrue(samePath(AppPaths.tandasFolder, root.appendingPathComponent("Milongas/Tandas")))
            XCTAssertTrue(
                samePath(AppPaths.appSettingsFile, root.appendingPathComponent("AppSettings.json")),
                "settings are global, not per library"
            )
        }
    }

    func testLibraryFileLivesInAFolderOfTheSameName() throws {
        try withTemporaryAppRoot { root in
            XCTAssertTrue(
                samePath(
                    AppPaths.libraryFile(named: "Milongas"),
                    root.appendingPathComponent("Milongas/Milongas.sqlite")
                )
            )
        }
    }

    func testCreateFoldersCreatesTheWholeTree() throws {
        try withTemporaryAppRoot { root in
            AppPaths.rootOverride = root.appendingPathComponent("not/yet/there", isDirectory: true)

            try AppPaths.createFolders()

            for folder in [AppPaths.libraryRoot, AppPaths.setlistsFolder, AppPaths.smartlistFolder, AppPaths.tandasFolder] {
                var isDirectory: ObjCBool = false
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), folder.path)
                XCTAssertTrue(isDirectory.boolValue, folder.path)
            }
        }
    }

    func testInternalLibraryNamesListsOnlyFoldersInNaturalOrder() throws {
        try withTemporaryAppRoot { root in
            let fm = FileManager.default
            for name in ["Library 10", "Library 2", "Alpha"] {
                try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            fm.createFile(atPath: root.appendingPathComponent("AppSettings.json").path, contents: Data("{}".utf8))

            XCTAssertEqual(try AppPaths.internalLibraryNames(), ["Alpha", "Library 2", "Library 10"])
        }
    }

    func testInternalLibraryNamesOfAMissingRootIsEmpty() throws {
        try withTemporaryAppRoot { root in
            AppPaths.rootOverride = root.appendingPathComponent("does-not-exist", isDirectory: true)

            XCTAssertEqual(try AppPaths.internalLibraryNames(), [])
        }
    }
}
