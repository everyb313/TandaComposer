import XCTest
import Foundation

/// Resolving a Setlist against the live Library, the rescan of single
/// entries, and reloading after data changed behind the store's back.
@MainActor
final class SetlistStoreResolveTests: XCTestCase {

    // MARK: - Helpers

    /// `trusted == true`: a Setlist that belongs to the current Library
    /// (after `newSetlist`). `false`: a fresh store, whose library name is
    /// still unknown, so ids are not trusted.
    private func makeStore(trusted: Bool) throws -> SetlistStore {
        let store = SetlistStore(db: try DatabaseManager())
        if trusted {
            store.newSetlist(named: "Resolve Test")
        }
        return store
    }

    private func song(_ id: Int64, _ path: String, title: String? = nil) -> Song {
        makeSong(id: id, path: path, title: title ?? "T\(id)")
    }

    private func tables(_ songs: [Song]) -> (byID: [Int64: Song], byPath: [String: Song]) {
        var byID: [Int64: Song] = [:]
        var byPath: [String: Song] = [:]
        for song in songs {
            if let id = song.id {
                byID[id] = song
            }
            byPath[song.normalizedPath] = song
        }
        return (byID, byPath)
    }

    private func resolve(_ store: SetlistStore, live: [Song], missing: Set<Int64> = []) {
        let lookup = tables(live)
        store.resolveAgainstLibrary(byID: lookup.byID, byPath: lookup.byPath, missingSongIDs: missing)
    }

    private func preview(_ store: SetlistStore, live: [Song], missing: Set<Int64> = []) -> [SetlistStore.RescanFix] {
        let lookup = tables(live)
        return store.previewRescan(byID: lookup.byID, byPath: lookup.byPath, missingSongIDs: missing)
    }

    private var recoveryFile: URL {
        SetlistStore.fileURLOnDisk(forName: "Recovery (autosaved)")
    }

    // MARK: - resolveAgainstLibrary

    func testResolveSetsStatusAndReplacesSongsWithTheLiveOnes() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.add([
                song(1, "/Music/1.flac"),
                song(2, "/Old/2.flac"),
                song(3, "/Music/3.flac"),
                song(4, "/Music/4.flac")
            ])
            let entryIDs = store.entries.map(\.id)
            let live = [
                song(1, "/Music/1.flac", title: "Live 1"),
                song(2, "/New/2.flac"),
                song(3, "/Music/3.flac")
            ]

            resolve(store, live: live, missing: [3])

            XCTAssertEqual(store.entries.map(\.status), [.resolved, .resolved, .fileMissing, .notInLibrary])
            XCTAssertEqual(store.songs.map(\.title), ["Live 1", "T2", "T3", "T4"])
            XCTAssertEqual(store.songs[1].path, "/New/2.flac", "moved file: the entry now points to the new path")
            XCTAssertEqual(store.songs[3].path, "/Music/4.flac", "unknown songs stay as they were")
            XCTAssertEqual(store.entries.map(\.id), entryIDs, "entry identities do not change")
        }
    }

    func testResolveOfAnEmptyLibraryMarksEverythingAsNotInLibrary() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.add([song(1, "/Music/1.flac"), song(2, "/Music/2.flac")])

            resolve(store, live: [])

            XCTAssertEqual(store.entries.map(\.status), [.notInLibrary, .notInLibrary])
        }
    }

    func testResolveOfAnEmptySetlistDoesNothing() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)

            resolve(store, live: [song(1, "/Music/1.flac")])

            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    func testIDsAreNotTrustedWhileTheLibraryNameIsUnknown() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: false)
            XCTAssertNil(store.savedAgainstLibraryName)
            store.add([song(2, "/Old/2.flac"), song(5, "/Music/x.flac")])
            let live = [
                song(2, "/New/2.flac"),         // same id, other path: not found by path
                song(5, "/Other/y.flac"),       // same id as entry 2, a different file
                song(6, "/Music/x.flac")        // the file the entry really points to
            ]

            resolve(store, live: live)

            XCTAssertEqual(store.entries.map(\.status), [.notInLibrary, .resolved])
            XCTAssertEqual(store.songs[1].id, 6, "matched by path, not by the untrusted id 5")
        }
    }

    func testResolveDoesNotCountAsAnEdit() throws {
        try withTemporaryAppRoot { _ in
            let writer = try makeStore(trusted: true)
            writer.name = "Friday"
            writer.add([song(1, "/Music/1.flac"), song(2, "/Music/2.flac")])
            try writer.save()

            let reader = try makeStore(trusted: false)
            try reader.load(setlistName: "Friday")
            resolve(reader, live: [song(1, "/Moved/1.flac")])

            XCTAssertFalse(reader.hasUnsavedChanges)
            XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryFile.path))
        }
    }

    func testALoadedSetlistTrustsTheIDsOfTheLibraryItWasSavedAgainst() throws {
        try withTemporaryAppRoot { _ in
            let writer = try makeStore(trusted: true)
            writer.name = "Friday"
            writer.add([song(7, "/Music/x.flac")])
            try writer.save()

            let reader = try makeStore(trusted: false)
            try reader.load(setlistName: "Friday")
            XCTAssertEqual(reader.savedAgainstLibraryName, "Default")
            resolve(reader, live: [song(7, "/Elsewhere/y.flac")])

            XCTAssertEqual(reader.songs.first?.path, "/Elsewhere/y.flac", "resolved by id")
        }
    }

    // MARK: - previewRescan / applyRescan

    private func storeWithUnresolvedEntries() throws -> SetlistStore {
        let store = try makeStore(trusted: true)
        store.add([song(1, "/Music/1.flac"), song(2, "/Old/2.flac"), song(3, "/Music/3.flac")])
        resolve(store, live: [])
        XCTAssertEqual(store.entries.map(\.status), [.notInLibrary, .notInLibrary, .notInLibrary])
        return store
    }

    func testPreviewOffersFixesForEntriesThatAreNowFound() throws {
        try withTemporaryAppRoot { _ in
            let store = try storeWithUnresolvedEntries()
            let live = [song(1, "/Music/1.flac"), song(2, "/New/2.flac"), song(3, "/Music/3.flac")]

            let fixes = preview(store, live: live, missing: [3])

            XCTAssertEqual(fixes.map(\.newStatus), [.resolved, .resolved, .fileMissing])
            XCTAssertEqual(fixes.map(\.oldPath), ["/Music/1.flac", "/Old/2.flac", "/Music/3.flac"])
            XCTAssertEqual(fixes.map(\.song.path), ["/Music/1.flac", "/New/2.flac", "/Music/3.flac"])
            XCTAssertEqual(fixes.map(\.entryID), store.entries.map(\.id))
        }
    }

    func testPreviewSkipsResolvedEntriesAndUnknownSongs() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.add([song(1, "/Old/1.flac"), song(2, "/Music/2.flac")])
            // Entry 1 is .resolved (the default), even though its path is stale.

            XCTAssertTrue(preview(store, live: [song(1, "/New/1.flac")]).isEmpty, "resolved entries are left alone")

            resolve(store, live: [])        // both become .notInLibrary
            XCTAssertTrue(preview(store, live: [song(9, "/Music/9.flac")]).isEmpty, "nothing found, nothing to fix")
        }
    }

    func testPreviewIgnoresEntriesWhoseStatusAndPathAreAlreadyRight() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.add([song(3, "/Music/3.flac")])
            resolve(store, live: [song(3, "/Music/3.flac")], missing: [3])
            XCTAssertEqual(store.entries.first?.status, .fileMissing)

            let fixes = preview(store, live: [song(3, "/Music/3.flac")], missing: [3])

            XCTAssertTrue(fixes.isEmpty, "still missing, same path: nothing changes")
        }
    }

    func testAMissingEntryThatCameBackIsFixed() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.add([song(3, "/Music/3.flac")])
            resolve(store, live: [song(3, "/Music/3.flac")], missing: [3])

            let fixes = preview(store, live: [song(3, "/Music/3.flac")], missing: [])

            XCTAssertEqual(fixes.map(\.newStatus), [.resolved])
        }
    }

    func testApplyRescanUpdatesEntriesAndSavesTheSetlist() throws {
        try withTemporaryAppRoot { _ in
            let store = try storeWithUnresolvedEntries()
            store.name = "Friday"
            let live = [song(1, "/Music/1.flac"), song(2, "/New/2.flac"), song(3, "/Music/3.flac")]

            let applied = store.applyRescan(preview(store, live: live, missing: [3]))

            XCTAssertTrue(applied)
            XCTAssertEqual(store.entries.map(\.status), [.resolved, .resolved, .fileMissing])
            XCTAssertEqual(store.songs.map(\.path), ["/Music/1.flac", "/New/2.flac", "/Music/3.flac"])
            XCTAssertFalse(store.hasUnsavedChanges)
            let saved = try SetlistMetadataExporter.load(from: SetlistStore.fileURLOnDisk(forName: "Friday"))
            XCTAssertEqual(saved.songs.map(\.path), ["/Music/1.flac", "/New/2.flac", "/Music/3.flac"])
            XCTAssertTrue(preview(store, live: live, missing: [3]).isEmpty, "nothing left to fix")
        }
    }

    func testApplyingNoFixesIsASuccessWithoutSaving() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.name = "Friday"
            store.add([song(1, "/Music/1.flac")])

            XCTAssertTrue(store.applyRescan([]))

            XCTAssertFalse(FileManager.default.fileExists(atPath: SetlistStore.fileURLOnDisk(forName: "Friday").path))
            XCTAssertTrue(store.hasUnsavedChanges, "untouched")
        }
    }

    func testApplyRescanKeepsTheChangesInMemoryWhenSavingFails() throws {
        try withTemporaryAppRoot { _ in
            let store = try storeWithUnresolvedEntries()
            let live = [song(1, "/Music/1.flac"), song(2, "/New/2.flac"), song(3, "/Music/3.flac")]
            let fixes = preview(store, live: live)
            store.name = "   "            // saving under this name throws

            let applied = store.applyRescan(fixes)

            XCTAssertFalse(applied)
            XCTAssertEqual(store.entries.map(\.status), [.resolved, .resolved, .resolved])
            XCTAssertTrue(store.hasUnsavedChanges)
            XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryFile.path), "recovery file protects the changes")
        }
    }

    // MARK: - refreshAfterExternalDataChange

    func testRefreshReloadsTheOpenSetlistFromDisk() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.name = "Friday"
            store.add([song(1, "/Music/1.flac")])
            try store.save()

            // Another process rewrites the file.
            try SetlistMetadataExporter.export(
                songs: [song(1, "/Music/1.flac"), song(2, "/Music/2.flac"), song(3, "/Music/3.flac")],
                setlistName: "Friday",
                to: SetlistStore.fileURLOnDisk(forName: "Friday"),
                savedAgainstLibraryName: "Other"
            )

            store.refreshAfterExternalDataChange()

            XCTAssertEqual(store.songs.map(\.title), ["T1", "T2", "T3"])
            XCTAssertEqual(store.savedAgainstLibraryName, "Other")
            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertTrue(store.selectedRowIndexes.isEmpty)
        }
    }

    func testRefreshStartsOverWhenTheFileIsGone() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            store.name = "Friday"
            store.add([song(1, "/Music/1.flac")])
            try store.save()
            try FileManager.default.removeItem(at: SetlistStore.fileURLOnDisk(forName: "Friday"))

            store.refreshAfterExternalDataChange()

            XCTAssertEqual(store.name, "Untitled Set")
            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertTrue(store.savedSetlistNamesList.isEmpty)
        }
    }

    func testRefreshUpdatesTheListOfSavedNames() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: true)
            XCTAssertTrue(store.savedSetlistNamesList.isEmpty)
            try FileManager.default.createDirectory(at: AppPaths.setlistsFolder, withIntermediateDirectories: true)
            try SetlistMetadataExporter.export(
                songs: [],
                setlistName: "Elsewhere",
                to: SetlistStore.fileURLOnDisk(forName: "Elsewhere")
            )

            store.refreshAfterExternalDataChange()

            XCTAssertEqual(store.savedSetlistNamesList, ["Elsewhere"])
        }
    }

    // MARK: - Library name after saving

    /// KNOWN ISSUE (low priority): `saveAs` stamps the FILE with the current
    /// library name but never updates the store's own `savedAgainstLibraryName`.
    /// A store that has not been through `newSetlist`/`load` keeps `nil` after
    /// saving, i.e. it does not trust its own ids until the next load, so
    /// rescans resolve by path only.
    ///
    /// `XCTExpectFailure` keeps the suite green; once `saveAs` updates the
    /// property this test fails with "expected failure not seen": remove the
    /// wrapper then.
    func testSavingShouldRecordTheLibraryTheFileWasSavedAgainst() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore(trusted: false)
            store.name = "Friday"
            store.add([song(1, "/Music/1.flac")])

            try store.save()

            let onDisk = try SetlistMetadataExporter.load(from: SetlistStore.fileURLOnDisk(forName: "Friday"))
            XCTAssertEqual(onDisk.savedAgainstLibraryName, "Default")
            XCTExpectFailure("saveAs does not update savedAgainstLibraryName in memory") {
                XCTAssertEqual(store.savedAgainstLibraryName, "Default")
            }
        }
    }
}
