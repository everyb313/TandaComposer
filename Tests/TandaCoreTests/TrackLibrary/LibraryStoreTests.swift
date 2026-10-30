import XCTest
import Foundation
import GRDB

/// Only the parts of `LibraryStore` that work on the database are tested
/// here: reload, delete, tag updates and import sources.
///
/// Deliberately NOT called: `loadLibrary`, `newLibrary`, `renameCurrentLibrary`,
/// `deleteInternalLibrary`, `resetToFactoryState`, `setCurrentLibraryName`.
/// They read or write `~/.TandaComposer` (via `AppPaths`) and would touch real
/// user data until `AppPaths` can be redirected to a temporary folder.
/// (`reload()` only lists that folder, read-only.)
@MainActor
final class LibraryStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> (store: LibraryStore, manager: DatabaseManager) {
        let manager = try DatabaseManager()
        return (LibraryStore(db: manager), manager)
    }

    @discardableResult
    private func insert(_ song: Song, into manager: DatabaseManager) throws -> Song {
        // GRDB 7: `insert` does not update the id of a `PersistableRecord`;
        // `inserted` returns the copy with the new row id.
        try manager.dbQueue.write { db in
            try song.inserted(db)
        }
    }

    private func insertSource(
        path: String,
        at seconds: TimeInterval,
        into manager: DatabaseManager
    ) throws -> ImportSource {
        try manager.dbQueue.write { db in
            try ImportSource(
                path: path,
                volumeUUID: nil,
                volumeName: nil,
                importedAt: Date(timeIntervalSince1970: seconds)
            ).inserted(db)
        }
    }

    // MARK: - Reload and caches

    func testEmptyLibraryHasNoSongs() throws {
        let (store, _) = try makeStore()

        try store.reload()

        XCTAssertTrue(store.songs.isEmpty)
        XCTAssertTrue(store.songsByID.isEmpty)
    }

    func testReloadSortsByArtist() throws {
        let (store, manager) = try makeStore()
        try insert(makeSong(path: "/Music/3.flac", title: "T3", artist: "Gamma"), into: manager)
        try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "Alpha"), into: manager)
        try insert(makeSong(path: "/Music/2.flac", title: "T2", artist: "Beta"), into: manager)

        try store.reload()

        XCTAssertEqual(store.songs.map(\.artist), ["Alpha", "Beta", "Gamma"])
    }

    func testLookupCachesAreFilled() throws {
        let (store, manager) = try makeStore()
        let first = try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "Alpha"), into: manager)
        let second = try insert(makeSong(path: "/Music/2.flac", title: "T2", artist: "Beta"), into: manager)

        try store.reload()

        let firstID = try XCTUnwrap(first.id)
        let secondID = try XCTUnwrap(second.id)
        XCTAssertEqual(store.songsByID[firstID]?.title, "T1")
        XCTAssertEqual(store.songsByID[secondID]?.title, "T2")
        XCTAssertEqual(store.songsByNormalizedPath[first.normalizedPath]?.title, "T1")
        XCTAssertEqual(store.songsByNormalizedPath[second.normalizedPath]?.title, "T2")
    }

    func testReloadPicksUpChangesMadeBehindTheStoresBack() throws {
        let (store, manager) = try makeStore()
        try store.reload()
        XCTAssertTrue(store.songs.isEmpty)

        try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "Alpha"), into: manager)
        try store.reload()

        XCTAssertEqual(store.songs.count, 1)
    }

    // MARK: - Search never shrinks the Library
    //
    // The title search (TrackTitleSearch) is a DISPLAY filter applied by
    // the views on top of `songs`. The store itself must always expose the
    // whole Library: Setlist/Tanda resolving, Rescans, the Duplicate Finder,
    // imports etc. read `songs` / `songsByID` / `songsByNormalizedPath` as
    // "everything".

    private func storeForSearch() throws -> LibraryStore {
        let (store, manager) = try makeStore()
        try insert(makeSong(path: "/Music/poema.flac", title: "Poema", artist: "Alpha Trio", genre: "Tango", album: "Album One"), into: manager)
        try insert(makeSong(path: "/Music/Valsecito.mp3", title: "Valsecito", artist: "Beta Band", genre: "Vals", album: "Album Two"), into: manager)
        try store.reload()
        return store
    }

    func testLookupCachesShouldCoverTheWholeLibraryWhileSearching() throws {
        let store = try storeForSearch()

        // What a view does for an active search.
        let hits = TrackTitleSearch.filter(store.songs, query: "poema")

        XCTAssertEqual(hits.map(\.title), ["Poema"])
        XCTAssertEqual(store.songs.count, 2)
        XCTAssertEqual(store.songsByID.count, 2)
        XCTAssertEqual(store.songsByNormalizedPath.count, 2)
    }

    // MARK: - Delete

    func testDeleteSongsRemovesOnlyTheGivenIDs() throws {
        let (store, manager) = try makeStore()
        let first = try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "A"), into: manager)
        try insert(makeSong(path: "/Music/2.flac", title: "T2", artist: "B"), into: manager)
        try store.reload()

        let firstID = try XCTUnwrap(first.id)
        try store.deleteSongs(ids: [firstID])

        XCTAssertEqual(store.songs.map(\.title), ["T2"])
    }

    func testDeleteSongsWithEmptySetOrUnknownIDsChangesNothing() throws {
        let (store, manager) = try makeStore()
        try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "A"), into: manager)
        try store.reload()

        try store.deleteSongs(ids: [])
        try store.deleteSongs(ids: [999_999])

        XCTAssertEqual(store.songs.count, 1)
    }

    // MARK: - Tag updates

    func testUpdateSongTagsChangesOnlyTheGivenFieldsOfTheGivenSongs() throws {
        let (store, manager) = try makeStore()
        let target = try insert(
            makeSong(path: "/Music/1.flac", title: "Old", artist: "Alpha", albumArtist: "Singer", genre: "Tango", year: 1930),
            into: manager
        )
        let bystander = try insert(
            makeSong(path: "/Music/2.flac", title: "Other", artist: "Beta", genre: "Vals", year: 1950),
            into: manager
        )
        try store.reload()

        let targetID = try XCTUnwrap(target.id)
        let bystanderID = try XCTUnwrap(bystander.id)
        try store.updateSongTags(
            ids: [targetID],
            title: "New",
            artist: nil,
            albumArtist: nil,
            genre: nil,
            year: 1940,
            comment: "note"
        )

        let changed = try XCTUnwrap(store.songsByID[targetID])
        XCTAssertEqual(changed.title, "New")
        XCTAssertEqual(changed.year, 1940)
        XCTAssertEqual(changed.comment, "note")
        XCTAssertEqual(changed.artist, "Alpha", "nil means untouched")
        XCTAssertEqual(changed.albumArtist, "Singer")
        XCTAssertEqual(changed.genre, "Tango")

        let untouched = try XCTUnwrap(store.songsByID[bystanderID])
        XCTAssertEqual(untouched.title, "Other")
        XCTAssertEqual(untouched.year, 1950)
    }

    func testUpdateSongTagsCanChangeSeveralSongsAtOnce() throws {
        let (store, manager) = try makeStore()
        let first = try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "A", genre: "Tango"), into: manager)
        let second = try insert(makeSong(path: "/Music/2.flac", title: "T2", artist: "B", genre: "Tango"), into: manager)
        try store.reload()

        let firstID = try XCTUnwrap(first.id)
        let secondID = try XCTUnwrap(second.id)
        try store.updateSongTags(
            ids: [firstID, secondID],
            title: nil, artist: nil, albumArtist: nil, genre: "Milonga", year: nil, comment: nil
        )

        XCTAssertEqual(store.songs.map(\.genre), ["Milonga", "Milonga"])
        XCTAssertEqual(Set(store.songs.map(\.title)), ["T1", "T2"])
    }

    func testUpdateSongTagsWithoutAnyValueIsANoOp() throws {
        let (store, manager) = try makeStore()
        let song = try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "A"), into: manager)
        try store.reload()

        let songID = try XCTUnwrap(song.id)
        try store.updateSongTags(
            ids: [songID],
            title: nil, artist: nil, albumArtist: nil, genre: nil, year: nil, comment: nil
        )

        XCTAssertEqual(store.songs.first?.title, "T1")
    }

    func testUpdateSongTagsWithoutIDsIsANoOp() throws {
        let (store, manager) = try makeStore()
        try insert(makeSong(path: "/Music/1.flac", title: "T1", artist: "A"), into: manager)
        try store.reload()

        try store.updateSongTags(
            ids: [],
            title: "Changed", artist: nil, albumArtist: nil, genre: nil, year: nil, comment: nil
        )

        XCTAssertEqual(store.songs.first?.title, "T1")
    }

    // MARK: - Import sources

    func testImportSourcesAreListedNewestFirst() throws {
        let (store, manager) = try makeStore()
        _ = try insertSource(path: "/Music/Old", at: 1_000, into: manager)
        _ = try insertSource(path: "/Music/New", at: 3_000, into: manager)
        _ = try insertSource(path: "/Music/Mid", at: 2_000, into: manager)

        let sources = try store.fetchImportSources()

        XCTAssertEqual(sources.map(\.path), ["/Music/New", "/Music/Mid", "/Music/Old"])
    }

    func testSongCountUnderImportSourceMatchesWholeFolderNamesOnly() throws {
        let (store, manager) = try makeStore()
        try insert(makeSong(path: "/Music/Tango/a.flac", title: "A", artist: "A"), into: manager)
        try insert(makeSong(path: "/Music/Tango/Sub/b.flac", title: "B", artist: "B"), into: manager)
        try insert(makeSong(path: "/Music/Tango2/c.flac", title: "C", artist: "C"), into: manager)
        try insert(makeSong(path: "/Music/Vals/d.flac", title: "D", artist: "D"), into: manager)
        try store.reload()

        XCTAssertEqual(store.songCount(underImportSourcePath: "/Music/Tango"), 2)
        XCTAssertEqual(store.songCount(underImportSourcePath: "/Music/Tango/"), 2, "trailing slash is the same folder")
        XCTAssertEqual(store.songCount(underImportSourcePath: "/Music"), 4)
        XCTAssertEqual(store.songCount(underImportSourcePath: "/Music/Milonga"), 0)
    }

    func testDeleteImportSourceIsRefusedWhileSongsStillUseIt() throws {
        let (store, manager) = try makeStore()
        let source = try insertSource(path: "/Music/Tango", at: 1_000, into: manager)
        try insert(makeSong(path: "/Music/Tango/a.flac", title: "A", artist: "A"), into: manager)
        try store.reload()

        let sourceID = try XCTUnwrap(source.id)
        do {
            try store.deleteImportSource(id: sourceID, path: source.path)
            XCTFail("expected importSourceStillInUse")
        } catch LibraryStoreError.importSourceStillInUse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try store.fetchImportSources().count, 1)
    }

    func testDeleteImportSourceRemovesOnlyThatRow() throws {
        let (store, manager) = try makeStore()
        let unused = try insertSource(path: "/Music/Unused", at: 1_000, into: manager)
        _ = try insertSource(path: "/Music/Other", at: 2_000, into: manager)
        try store.reload()

        let unusedID = try XCTUnwrap(unused.id)
        try store.deleteImportSource(id: unusedID, path: unused.path)

        XCTAssertEqual(try store.fetchImportSources().map(\.path), ["/Music/Other"])
    }

    func testDeletingAnImportSourceNeverDeletesSongs() throws {
        let (store, manager) = try makeStore()
        let source = try insertSource(path: "/Music/Empty", at: 1_000, into: manager)
        try insert(makeSong(path: "/Music/Tango/a.flac", title: "A", artist: "A"), into: manager)
        try store.reload()

        let sourceID = try XCTUnwrap(source.id)
        try store.deleteImportSource(id: sourceID, path: source.path)
        try store.reload()

        XCTAssertEqual(store.songs.count, 1)
    }

    // MARK: - Missing files

    func testSongsWhoseFileIsGoneAreReportedAsMissing() async throws {
        let dir = try makeTemporaryDirectory()
        let existingFile = try writeData(Data("x".utf8), in: dir, named: "exists.flac")
        let (store, manager) = try makeStore()
        let present = try insert(
            makeSong(path: existingFile.path, title: "Here", artist: "A"),
            into: manager
        )
        let gone = try insert(
            makeSong(path: dir.appendingPathComponent("gone.flac").path, title: "Gone", artist: "B"),
            into: manager
        )
        let goneID = try XCTUnwrap(gone.id)
        let presentID = try XCTUnwrap(present.id)

        try store.reload()

        let found = await waitUntil { store.missingSongIDs.contains(goneID) }
        XCTAssertTrue(found, "the sweep runs in the background and must report the missing file")
        XCTAssertFalse(store.missingSongIDs.contains(presentID))
    }

    // MARK: - Errors

    func testEveryLibraryStoreErrorHasADescription() {
        let errors: [LibraryStoreError] = [
            .destinationAlreadyExists,
            .cannotWriteOntoActiveLibrary,
            .cannotDeleteActiveLibrary,
            .importSourceStillInUse,
            .invalidLibraryName
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}
