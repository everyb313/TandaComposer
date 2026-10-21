import XCTest
import Foundation
import GRDB

/// Creating, loading, renaming, exporting, deleting and resetting libraries.
/// These methods work below `AppPaths.root`, so every test runs inside
/// `withTemporaryAppRoot` and never touches `~/.TandaComposer`.
@MainActor
final class LibraryStoreSwitchingTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> (store: LibraryStore, manager: DatabaseManager) {
        let manager = try DatabaseManager()
        return (LibraryStore(db: manager), manager)
    }

    @discardableResult
    private func insert(_ song: Song, into manager: DatabaseManager) throws -> Song {
        try manager.dbQueue.write { db in
            try song.inserted(db)
        }
    }

    private func songCount(_ manager: DatabaseManager) throws -> Int {
        try manager.dbQueue.read { db in
            try Song.fetchCount(db)
        }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - newLibrary

    func testNewLibraryCreatesFolderDatabaseAndSubfoldersAndSwitches() throws {
        try withTemporaryAppRoot { root in
            let (store, _) = try makeStore()

            try store.newLibrary(named: "Milongas")

            XCTAssertEqual(store.currentLibraryName, "Milongas")
            XCTAssertEqual(AppPaths.currentLibraryName, "Milongas")
            XCTAssertTrue(samePath(URL(fileURLWithPath: store.currentLibraryPath), root.appendingPathComponent("Milongas/Milongas.sqlite")))
            XCTAssertTrue(exists(root.appendingPathComponent("Milongas/Milongas.sqlite")))
            for sub in ["Setlists", "Smartlists", "Tandas"] {
                XCTAssertTrue(exists(root.appendingPathComponent("Milongas/\(sub)")), sub)
            }
            XCTAssertTrue(store.songs.isEmpty)
            XCTAssertEqual(store.internalLibraryNames, ["Milongas"])
        }
    }

    func testNewLibraryStartsEmptyEvenWhenAnotherLibraryHasSongs() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/a.flac", title: "From A", artist: "X"), into: manager)
            try store.reload()
            XCTAssertEqual(store.songs.count, 1)

            try store.newLibrary(named: "B")

            XCTAssertTrue(store.songs.isEmpty)
            XCTAssertEqual(try songCount(manager), 0)
            XCTAssertEqual(store.internalLibraryNames, ["A", "B"])
        }
    }

    func testNewLibraryWithAnExistingNameThrowsAndKeepsTheCurrentLibrary() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/a.flac", title: "From A", artist: "X"), into: manager)

            do {
                try store.newLibrary(named: "A")
                XCTFail("expected destinationAlreadyExists")
            } catch DatabaseManagerError.destinationAlreadyExists {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(store.currentLibraryName, "A")
            XCTAssertEqual(AppPaths.currentLibraryName, "A")
            XCTAssertEqual(try songCount(manager), 1, "the open library is untouched")
        }
    }

    // MARK: - loadLibrary / loadInternalLibrary / clearLibrary

    func testLoadInternalLibrarySwitchesTheData() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/a.flac", title: "From A", artist: "X"), into: manager)
            try store.newLibrary(named: "B")
            XCTAssertTrue(store.songs.isEmpty)

            try store.loadInternalLibrary(named: "A")

            XCTAssertEqual(store.songs.map(\.title), ["From A"])
            XCTAssertEqual(store.currentLibraryName, "A")
            XCTAssertEqual(AppPaths.currentLibraryName, "A")
        }
    }

    func testLoadingAMissingLibraryThrowsAndKeepsTheCurrentOne() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/a.flac", title: "From A", artist: "X"), into: manager)
            try store.reload()

            do {
                try store.loadInternalLibrary(named: "Nope")
                XCTFail("expected fileNotFound")
            } catch DatabaseManagerError.fileNotFound {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(store.currentLibraryName, "A")
            XCTAssertEqual(AppPaths.currentLibraryName, "A")
            XCTAssertEqual(store.songs.count, 1)
        }
    }

    func testLoadLibraryFromAnyPathUsesTheFileNameAsLibraryName() throws {
        try withTemporaryAppRoot { _ in
            let outside = try makeTemporaryDirectory().appendingPathComponent("External.sqlite")
            try DatabaseManager.createEmptyLibrary(at: outside.path)
            do {
                let external = try DatabaseManager(path: outside.path)
                try insert(makeSong(path: "/Music/e.flac", title: "External Song", artist: "X"), into: external)
            }
            let (store, _) = try makeStore()

            try store.loadLibrary(from: outside.path)

            XCTAssertEqual(store.currentLibraryName, "External")
            XCTAssertEqual(AppPaths.currentLibraryName, "External")
            XCTAssertEqual(store.currentLibraryPath, outside.path)
            XCTAssertEqual(store.songs.map(\.title), ["External Song"])
        }
    }

    func testLoadingALibraryClearsTheSearchFilter() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/a.flac", title: "From A", artist: "X"), into: manager)
            try store.newLibrary(named: "B")
            store.searchText = "something"

            try store.loadInternalLibrary(named: "A")

            XCTAssertEqual(store.searchText, "")
            XCTAssertEqual(store.songs.count, 1)
        }
    }

    func testClearLibraryRemovesAllSongsAndTheFilter() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try insert(makeSong(path: "/Music/1.flac", title: "One", artist: "A"), into: manager)
            try insert(makeSong(path: "/Music/2.flac", title: "Two", artist: "B"), into: manager)
            try store.reload()
            store.searchText = "one"

            try store.clearLibrary()

            XCTAssertTrue(store.songs.isEmpty)
            XCTAssertEqual(store.searchText, "")
            XCTAssertTrue(store.songsByID.isEmpty)
            XCTAssertEqual(try songCount(manager), 0)
        }
    }

    // MARK: - renameCurrentLibrary

    private func libraryWithSavedFiles(_ store: LibraryStore, manager: DatabaseManager, root: URL) throws -> (setlist: URL, otherSetlist: URL, tanda: URL, notes: URL) {
        try store.newLibrary(named: "Old")
        try insert(makeSong(path: "/Music/a.flac", title: "From Old", artist: "X"), into: manager)

        let setlist = AppPaths.setlistsFolder.appendingPathComponent("Friday.json")
        try SetlistMetadataExporter.export(songs: [makeFullSong(id: 1)], setlistName: "Friday", to: setlist)

        let otherSetlist = AppPaths.setlistsFolder.appendingPathComponent("Imported.json")
        try SetlistMetadataExporter.export(
            songs: [makeFullSong(id: 2, path: "/Music/b.flac")],
            setlistName: "Imported",
            to: otherSetlist,
            savedAgainstLibraryName: "Other"
        )

        let tandaFolder = AppPaths.tandasFolder.appendingPathComponent("Alpha Trio/Singer X", isDirectory: true)
        try FileManager.default.createDirectory(at: tandaFolder, withIntermediateDirectories: true)
        let tanda = tandaFolder.appendingPathComponent("Set.json")
        try TandaMetadataExporter.export(songs: (1...3).map { makeFullSong(id: Int64($0), path: "/Music/\($0).flac") }, tandaName: "Set", to: tanda)

        let notes = AppPaths.libraryRoot.appendingPathComponent("notes.txt")
        try "Old is a nice name".write(to: notes, atomically: true, encoding: .utf8)

        return (setlist, otherSetlist, tanda, notes)
    }

    func testRenameMovesTheFolderAndTheDatabaseAndSwitchesToIt() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            _ = try libraryWithSavedFiles(store, manager: manager, root: root)

            try store.renameCurrentLibrary(to: "New")

            XCTAssertFalse(exists(root.appendingPathComponent("Old")))
            XCTAssertTrue(exists(root.appendingPathComponent("New/New.sqlite")))
            XCTAssertFalse(exists(root.appendingPathComponent("New/Old.sqlite")))
            XCTAssertEqual(store.currentLibraryName, "New")
            XCTAssertEqual(AppPaths.currentLibraryName, "New")
            XCTAssertTrue(samePath(URL(fileURLWithPath: store.currentLibraryPath), root.appendingPathComponent("New/New.sqlite")))
            XCTAssertEqual(store.songs.map(\.title), ["From Old"], "data survived the rename")
            XCTAssertEqual(store.internalLibraryNames, ["New"])
        }
    }

    func testRenameKeepsSubfoldersAndUnrelatedFiles() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            _ = try libraryWithSavedFiles(store, manager: manager, root: root)

            try store.renameCurrentLibrary(to: "New")

            XCTAssertTrue(exists(root.appendingPathComponent("New/Setlists/Friday.json")))
            XCTAssertTrue(exists(root.appendingPathComponent("New/Tandas/Alpha Trio/Singer X/Set.json")))
            XCTAssertEqual(
                try String(contentsOf: root.appendingPathComponent("New/notes.txt"), encoding: .utf8),
                "Old is a nice name"
            )
        }
    }

    func testRenameRelabelsOnlyFilesSavedAgainstTheOldName() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            let files = try libraryWithSavedFiles(store, manager: manager, root: root)
            let otherBefore = try Data(contentsOf: files.otherSetlist)

            try store.renameCurrentLibrary(to: "New")

            let setlist = try SetlistMetadataExporter.load(from: root.appendingPathComponent("New/Setlists/Friday.json"))
            XCTAssertEqual(setlist.savedAgainstLibraryName, "New")
            XCTAssertEqual(setlist.songs, [makeFullSong(id: 1)], "nothing else in the file changed")

            let tanda = try TandaMetadataExporter.load(from: root.appendingPathComponent("New/Tandas/Alpha Trio/Singer X/Set.json"))
            XCTAssertEqual(tanda.savedAgainstLibraryName, "New")

            let otherAfter = try Data(contentsOf: root.appendingPathComponent("New/Setlists/Imported.json"))
            XCTAssertEqual(otherAfter, otherBefore, "files of another library are not rewritten at all")
        }
    }

    func testRenameChangesOnlyTheLibraryNameInsideTheFile() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            let files = try libraryWithSavedFiles(store, manager: manager, root: root)
            let before = try String(contentsOf: files.setlist, encoding: .utf8)

            try store.renameCurrentLibrary(to: "New")

            let after = try String(contentsOf: root.appendingPathComponent("New/Setlists/Friday.json"), encoding: .utf8)
            XCTAssertEqual(
                after,
                before.replacingOccurrences(
                    of: "\"savedAgainstLibraryName\" : \"Old\"",
                    with: "\"savedAgainstLibraryName\" : \"New\""
                ),
                "formatting and key order stay exactly as they were"
            )
        }
    }

    func testRenameTrimsTheNewName() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            _ = try libraryWithSavedFiles(store, manager: manager, root: root)

            try store.renameCurrentLibrary(to: "  New \n")

            XCTAssertEqual(store.currentLibraryName, "New")
            XCTAssertTrue(exists(root.appendingPathComponent("New")))
        }
    }

    func testRenameToTheSameNameDoesNothing() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            _ = try libraryWithSavedFiles(store, manager: manager, root: root)

            XCTAssertNoThrow(try store.renameCurrentLibrary(to: "Old"))

            XCTAssertEqual(store.currentLibraryName, "Old")
            XCTAssertTrue(exists(root.appendingPathComponent("Old/Old.sqlite")))
        }
    }

    func testRenameRejectsInvalidNames() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            _ = try libraryWithSavedFiles(store, manager: manager, root: root)

            for bad in ["", "   ", ".", "..", "a/b", "a\\b", "a:b"] {
                do {
                    try store.renameCurrentLibrary(to: bad)
                    XCTFail("expected invalidLibraryName for \"\(bad)\"")
                } catch LibraryStoreError.invalidLibraryName {
                    // expected
                } catch {
                    XCTFail("unexpected error for \"\(bad)\": \(error)")
                }
            }

            XCTAssertEqual(store.currentLibraryName, "Old")
            XCTAssertTrue(exists(root.appendingPathComponent("Old/Old.sqlite")))
        }
    }

    func testRenameToAnExistingLibraryIsRefused() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "Taken")
            try store.newLibrary(named: "Old")
            try insert(makeSong(path: "/Music/a.flac", title: "From Old", artist: "X"), into: manager)

            do {
                try store.renameCurrentLibrary(to: "Taken")
                XCTFail("expected destinationAlreadyExists")
            } catch LibraryStoreError.destinationAlreadyExists {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(store.currentLibraryName, "Old")
            XCTAssertEqual(try songCount(manager), 1)
            XCTAssertTrue(exists(root.appendingPathComponent("Taken/Taken.sqlite")))
        }
    }

    func testRenameOfALibraryWithoutAFolderThrows() throws {
        try withTemporaryAppRoot { _ in
            let (store, _) = try makeStore()        // still named "Library", no folder

            do {
                try store.renameCurrentLibrary(to: "New")
                XCTFail("expected fileNotFound")
            } catch DatabaseManagerError.fileNotFound {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAFailedRenameRestoresFolderNamesAndFiles() throws {
        try withTemporaryAppRoot { root in
            let (store, _) = try makeStore()
            // A library folder WITHOUT its database file makes the rename fail
            // after the folder has already been moved.
            let broken = root.appendingPathComponent("Broken", isDirectory: true)
            try FileManager.default.createDirectory(at: broken.appendingPathComponent("Setlists"), withIntermediateDirectories: true)
            let setlist = broken.appendingPathComponent("Setlists/Friday.json")
            try SetlistMetadataExporter.export(songs: [makeFullSong(id: 1)], setlistName: "Friday", to: setlist, savedAgainstLibraryName: "Broken")
            let before = try Data(contentsOf: setlist)
            store.setCurrentLibraryName(from: AppPaths.libraryFile(named: "Broken").path)

            do {
                try store.renameCurrentLibrary(to: "Fixed")
                XCTFail("expected an error")
            } catch DatabaseManagerError.fileNotFound {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertTrue(exists(broken), "folder is back under its old name")
            XCTAssertFalse(exists(root.appendingPathComponent("Fixed")))
            XCTAssertEqual(store.currentLibraryName, "Broken")
            XCTAssertEqual(AppPaths.currentLibraryName, "Broken")
            XCTAssertEqual(try Data(contentsOf: setlist), before, "files are exactly as before")
        }
    }

    // MARK: - deleteInternalLibrary

    func testDeleteRemovesAnotherLibraryAndRefreshesTheList() throws {
        try withTemporaryAppRoot { root in
            let (store, _) = try makeStore()
            try store.newLibrary(named: "Old")
            try store.newLibrary(named: "Active")

            try store.deleteInternalLibrary(named: "Old")

            XCTAssertFalse(exists(root.appendingPathComponent("Old")))
            XCTAssertEqual(store.internalLibraryNames, ["Active"])
        }
    }

    func testTheActiveLibraryCannotBeDeleted() throws {
        try withTemporaryAppRoot { root in
            let (store, _) = try makeStore()
            try store.newLibrary(named: "Active")

            do {
                try store.deleteInternalLibrary(named: "Active")
                XCTFail("expected cannotDeleteActiveLibrary")
            } catch LibraryStoreError.cannotDeleteActiveLibrary {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertTrue(exists(root.appendingPathComponent("Active/Active.sqlite")))
        }
    }

    func testDeletingAnUnknownLibraryThrows() throws {
        try withTemporaryAppRoot { _ in
            let (store, _) = try makeStore()
            try store.newLibrary(named: "Active")

            XCTAssertThrowsError(try store.deleteInternalLibrary(named: "Nope"))
        }
    }

    // MARK: - exportLibrary

    func testExportWritesAnOpenableCopyOfTheCurrentLibrary() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/1.flac", title: "One", artist: "X"), into: manager)
            try insert(makeSong(path: "/Music/2.flac", title: "Two", artist: "Y"), into: manager)
            let target = try makeTemporaryDirectory().appendingPathComponent("backups/A-copy.sqlite")

            try store.exportLibrary(to: target.path)

            let copy = try DatabaseManager(path: target.path)
            let titles = try copy.dbQueue.read { db in try Song.fetchAll(db).compactMap(\.title) }
            XCTAssertEqual(Set(titles), ["One", "Two"])
            XCTAssertEqual(store.currentLibraryName, "A", "exporting does not switch libraries")
        }
    }

    func testExportReplacesAnExistingFile() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/1.flac", title: "One", artist: "X"), into: manager)
            let target = try makeTemporaryDirectory().appendingPathComponent("copy.sqlite")
            try Data("old content".utf8).write(to: target)

            try store.exportLibrary(to: target.path)

            let copy = try DatabaseManager(path: target.path)
            XCTAssertEqual(try songCount(copy), 1)
        }
    }

    func testExportOntoTheCurrentLibraryFileDoesNothing() throws {
        try withTemporaryAppRoot { _ in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/1.flac", title: "One", artist: "X"), into: manager)

            XCTAssertNoThrow(try store.exportLibrary(to: store.currentLibraryPath))

            XCTAssertEqual(try songCount(manager), 1)
        }
    }

    // MARK: - resetToFactoryState

    func testResetRemovesAllLibrariesAndStartsWithAnEmptyDefault() throws {
        try withTemporaryAppRoot { root in
            let (store, manager) = try makeStore()
            try store.newLibrary(named: "A")
            try insert(makeSong(path: "/Music/1.flac", title: "One", artist: "X"), into: manager)
            try store.newLibrary(named: "B")

            try store.resetToFactoryState()

            XCTAssertFalse(exists(root.appendingPathComponent("A")))
            XCTAssertFalse(exists(root.appendingPathComponent("B")))
            XCTAssertTrue(exists(root.appendingPathComponent("Default/Default.sqlite")))
            for sub in ["Setlists", "Smartlists", "Tandas"] {
                XCTAssertTrue(exists(root.appendingPathComponent("Default/\(sub)")), sub)
            }
            XCTAssertEqual(store.currentLibraryName, "Default")
            XCTAssertEqual(AppPaths.currentLibraryName, "Default")
            XCTAssertTrue(store.songs.isEmpty)
            XCTAssertEqual(try songCount(manager), 0)
            XCTAssertEqual(store.internalLibraryNames, ["Default"])
        }
    }

    func testResetForgetsTheRememberedSetlistAndLibraryLocations() throws {
        try withTemporaryAppRoot { _ in
            let defaults = UserDefaults.standard
            let keys = ["LastPlaylist", "LastPlaylistLibraryPath", "LastPlaylist.Internal", "LastPlaylist.External", "ExternalLibraryLocation", "ExternalLibraryBookmark", "LastLibraryPath"]
            for key in keys {
                defaults.set("remembered", forKey: key)
            }
            let (store, _) = try makeStore()

            try store.resetToFactoryState()

            for key in keys {
                XCTAssertNil(defaults.object(forKey: key), key)
            }
        }
    }

    // MARK: - compactCurrentLibrary

    // These two helpers are deliberately synchronous: inside an async test,
    // GRDB's `write` resolves to its async overload (needs `await` and a
    // @Sendable closure, which could not call `makeSong`).

    private func fillWithBulkySongs(_ manager: DatabaseManager, count: Int) throws {
        try manager.dbQueue.write { db in
            for number in 0..<count {
                var song = makeSong(path: "/Music/\(number).flac", title: "Title \(number)", artist: "Artist")
                song.comment = String(repeating: "x", count: 400)
                try song.insert(db)
            }
        }
    }

    private func deleteAllSongs(_ manager: DatabaseManager) throws {
        _ = try manager.dbQueue.write { db in
            try Song.deleteAll(db)
        }
    }

    func testCompactShrinksTheFileAfterManyDeletions() async throws {
        let root = try makeTemporaryDirectory().resolvingSymlinksInPath()
        let previousRoot = AppPaths.rootOverride
        let previousName = AppPaths.currentLibraryName
        AppPaths.rootOverride = root
        AppPaths.currentLibraryName = AppPaths.defaultLibraryName
        defer {
            AppPaths.rootOverride = previousRoot
            AppPaths.currentLibraryName = previousName
        }
        try XCTSkipUnless(samePath(AppPaths.root, root), "AppPaths.rootOverride has no effect; refusing to touch real data")

        let (store, manager) = try makeStore()
        try store.newLibrary(named: "Big")
        try fillWithBulkySongs(manager, count: 300)
        _ = try await store.compactCurrentLibrary()          // baseline without the deleted rows
        try deleteAllSongs(manager)

        let result = try await store.compactCurrentLibrary()

        XCTAssertGreaterThan(result.sizeBefore, 0)
        XCTAssertLessThanOrEqual(result.sizeAfter, result.sizeBefore)
    }
}
