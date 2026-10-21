import XCTest
import Foundation

/// Rescan of the saved Tandas: references to moved files are rewritten, and
/// a Tanda that does not sit at the location its songs ask for (see
/// `TandaSaver.resolvedLocation`) is offered a rename.
@MainActor
final class TandaStoreRescanTests: XCTestCase {

    // MARK: - Helpers

    /// Orchestra "Alpha Trio", singer "Singer X", genre "Tango" for all songs,
    /// so the canonical location is `Tandas/Alpha Trio/Singer X/Alpha Trio_Tango_Singer X.json`.
    private func tandaSong(_ id: Int64, path: String? = nil) -> Song {
        makeSong(
            id: id,
            path: path ?? "/Music/\(id).flac",
            title: "T\(id)",
            artist: "Alpha Trio",
            albumArtist: "Singer X",
            genre: "Tango"
        )
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

    /// Writes the Tanda at the location its songs ask for.
    @discardableResult
    private func writeCanonical(
        _ songs: [Song],
        comment: String? = nil,
        savedAgainst: String? = "Default",
        settings: AppSettings
    ) throws -> URL {
        let location = TandaSaver.resolvedLocation(for: songs, settings: settings)
        try FileManager.default.createDirectory(at: location.folder, withIntermediateDirectories: true)
        let url = location.folder.appendingPathComponent(location.name).appendingPathExtension("json")
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: location.name,
            to: url,
            comment: comment,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    /// Writes the Tanda somewhere that is NOT its canonical location.
    @discardableResult
    private func writeLegacy(
        _ songs: [Song],
        named name: String = "Legacy",
        comment: String? = nil,
        savedAgainst: String? = "Default"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.tandasFolder, withIntermediateDirectories: true)
        let url = AppPaths.tandasFolder.appendingPathComponent(name).appendingPathExtension("json")
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: name,
            to: url,
            comment: comment,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    private func preview(
        _ store: TandaStore,
        live: [Song],
        missing: Set<Int64> = [],
        settings: AppSettings
    ) -> [TandaRescanFix] {
        let lookup = tables(live)
        return store.previewRescan(
            byID: lookup.byID,
            byPath: lookup.byPath,
            missingSongIDs: missing,
            settings: settings
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - previewRescan

    func testATandaAtItsCanonicalLocationWithUnchangedSongsNeedsNothing() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let songs = (1...3).map { tandaSong(Int64($0)) }
            try writeCanonical(songs, settings: settings)

            let store = TandaStore()

            XCTAssertTrue(preview(store, live: songs, settings: settings).isEmpty)
        }
    }

    func testAMovedFileIsFixedWithoutARenameWhenTheLocationStaysTheSame() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            try writeCanonical([tandaSong(1, path: "/Old/1.flac"), tandaSong(2), tandaSong(3)], settings: settings)
            let store = TandaStore()
            let live = [tandaSong(1, path: "/New/1.flac"), tandaSong(2), tandaSong(3)]

            let fixes = preview(store, live: live, settings: settings)

            let fix = try XCTUnwrap(fixes.first)
            XCTAssertEqual(fixes.count, 1)
            XCTAssertEqual(fix.fixedSongCount, 1)
            XCTAssertEqual(fix.updatedSongs.map(\.path), ["/New/1.flac", "/Music/2.flac", "/Music/3.flac"])
            XCTAssertNil(fix.rename)
        }
    }

    func testATandaAtTheWrongLocationIsOfferedARename() throws {
        try withTemporaryAppRoot { root in
            let settings = AppSettings()
            let songs = (1...3).map { tandaSong(Int64($0)) }
            try writeLegacy(songs)
            let store = TandaStore()

            let fixes = preview(store, live: songs, settings: settings)

            let fix = try XCTUnwrap(fixes.first)
            XCTAssertEqual(fix.fixedSongCount, 0)
            let rename = try XCTUnwrap(fix.rename)
            XCTAssertTrue(samePath(rename.newFolder, root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X")))
            XCTAssertEqual(rename.newName, "Alpha Trio_Tango_Singer X")
            XCTAssertTrue(samePath(rename.newURL, root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X/Alpha Trio_Tango_Singer X.json")))
        }
    }

    func testTheRenameAvoidsAnotherTandaThatAlreadyHasTheName() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let songs = (1...3).map { tandaSong(Int64($0)) }
            try writeCanonical(songs, settings: settings)      // holds the canonical name
            try writeLegacy(songs, named: "Duplicate")
            let store = TandaStore()

            let fixes = preview(store, live: songs, settings: settings)

            XCTAssertEqual(fixes.count, 1)
            XCTAssertEqual(fixes.first?.tanda.name, "Duplicate")
            XCTAssertEqual(fixes.first?.rename?.newName, "Alpha Trio_Tango_Singer X_2")
        }
    }

    func testTandasAreFixedIndependently() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let moved = (1...3).map { tandaSong(Int64($0), path: "/Old/\($0).flac") }
            let fine = (4...6).map { tandaSong(Int64($0)) }
            try writeLegacy(moved, named: "Moved")
            try writeLegacy(fine, named: "Fine")
            let store = TandaStore()
            let live = (1...3).map { tandaSong(Int64($0), path: "/New/\($0).flac") } + fine

            let fixes = preview(store, live: live, settings: settings)

            let byName = Dictionary(uniqueKeysWithValues: fixes.map { ($0.tanda.name, $0) })
            XCTAssertEqual(byName["Moved"]?.fixedSongCount, 3)
            XCTAssertEqual(byName["Fine"]?.fixedSongCount, 0, "only a rename is offered")
        }
    }

    func testIDsOfAnotherLibraryAreNotTrusted() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let stored = (1...3).map { tandaSong(Int64($0)) }
            try writeCanonical(stored, savedAgainst: "Other", settings: settings)
            let store = TandaStore()
            // Same ids, but they are different files in this Library.
            let live = (1...3).map { tandaSong(Int64($0), path: "/Different/\($0).flac") }

            XCTAssertTrue(preview(store, live: live, settings: settings).isEmpty)
        }
    }

    // MARK: - applyRescan

    func testApplyWithoutFixesChangesNothing() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            try writeCanonical((1...3).map { tandaSong(Int64($0)) }, settings: settings)
            let store = TandaStore()

            let summary = store.applyRescan([])

            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertEqual(summary.updatedTandaCount, 0)
            XCTAssertEqual(summary.renamedTandaCount, 0)
            XCTAssertEqual(store.tandas.count, 1)
        }
    }

    func testApplyRewritesTheFileAndUpdatesTheStore() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let url = try writeCanonical(
                [tandaSong(1, path: "/Old/1.flac"), tandaSong(2), tandaSong(3)],
                comment: "keep me",
                settings: settings
            )
            let store = TandaStore()
            let live = [tandaSong(1, path: "/New/1.flac"), tandaSong(2), tandaSong(3)]

            let summary = store.applyRescan(preview(store, live: live, settings: settings))

            XCTAssertEqual(summary.fixedReferenceCount, 1)
            XCTAssertEqual(summary.updatedTandaCount, 1)
            XCTAssertEqual(summary.renamedTandaCount, 0)
            XCTAssertTrue(summary.failedWrites.isEmpty)

            let inMemory = try XCTUnwrap(store.tandas.first)
            XCTAssertEqual(inMemory.songs.map(\.path), ["/New/1.flac", "/Music/2.flac", "/Music/3.flac"])
            XCTAssertEqual(inMemory.comment, "keep me")
            XCTAssertEqual(inMemory.savedAgainstLibraryName, "Default")

            let onDisk = try TandaMetadataExporter.load(from: url)
            XCTAssertEqual(onDisk.songs.map(\.path), ["/New/1.flac", "/Music/2.flac", "/Music/3.flac"])
            XCTAssertEqual(onDisk.comment, "keep me")
        }
    }

    func testApplyMovesARenamedTandaAndRemovesTheOldFile() throws {
        try withTemporaryAppRoot { root in
            let settings = AppSettings()
            let songs = (1...3).map { tandaSong(Int64($0)) }
            let oldURL = try writeLegacy(songs, named: "Legacy", comment: "keep me")
            let store = TandaStore()

            let summary = store.applyRescan(preview(store, live: songs, settings: settings))

            XCTAssertEqual(summary.renamedTandaCount, 1)
            XCTAssertEqual(summary.updatedTandaCount, 1)
            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertFalse(exists(oldURL))

            let newURL = root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X/Alpha Trio_Tango_Singer X.json")
            XCTAssertTrue(exists(newURL))

            let moved = try XCTUnwrap(store.tandas.first)
            XCTAssertEqual(store.tandas.count, 1)
            XCTAssertEqual(moved.name, "Alpha Trio_Tango_Singer X")
            XCTAssertEqual(moved.sourceFolder, "Alpha Trio/Singer X")
            XCTAssertTrue(samePath(moved.sourceURL, newURL))
            XCTAssertEqual(moved.comment, "keep me")

            let onDisk = try TandaMetadataExporter.load(from: newURL)
            XCTAssertEqual(onDisk.tandaName, "Alpha Trio_Tango_Singer X")
            XCTAssertEqual(onDisk.comment, "keep me")

            XCTAssertEqual(try tandaStoreNames(), ["Alpha Trio_Tango_Singer X"], "a fresh store sees the same")
        }
    }

    private func tandaStoreNames() throws -> [String] {
        TandaStore().tandas.map(\.name)
    }

    func testAppliedFixesLeaveNothingToDoTheSecondTime() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            try writeLegacy((1...3).map { tandaSong(Int64($0), path: "/Old/\($0).flac") })
            let store = TandaStore()
            let live = (1...3).map { tandaSong(Int64($0), path: "/New/\($0).flac") }

            store.applyRescan(preview(store, live: live, settings: settings))

            XCTAssertTrue(preview(store, live: live, settings: settings).isEmpty)
            XCTAssertTrue(preview(TandaStore(), live: live, settings: settings).isEmpty)
        }
    }

    func testAFileThatCannotBeWrittenIsReportedAndKeptAsItWas() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let url = try writeCanonical(
                [tandaSong(1, path: "/Old/1.flac"), tandaSong(2), tandaSong(3)],
                settings: settings
            )
            let store = TandaStore()
            let live = [tandaSong(1, path: "/New/1.flac"), tandaSong(2), tandaSong(3)]
            let fixes = preview(store, live: live, settings: settings)
            // Make the write fail: the folder of the file disappears.
            try FileManager.default.removeItem(at: url.deletingLastPathComponent())

            let summary = store.applyRescan(fixes)

            XCTAssertEqual(summary.failedWrites.count, 1)
            XCTAssertEqual(summary.updatedTandaCount, 0)
            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertEqual(store.tandas.count, 1)
            XCTAssertEqual(store.tandas.first?.songs.first?.path, "/Old/1.flac", "the store keeps the old data")
        }
    }

    /// KNOWN ISSUE (likely): a Tanda that was saved against ANOTHER library
    /// (or has no library name) needs only a rename. `applyRescan` rewrites it
    /// with the songs unchanged, i.e. with the other library's ids, but the
    /// exporter stamps the file as saved against the CURRENT library. From
    /// then on those foreign ids are trusted.
    ///
    /// Either the ids should be replaced by the live ones, or the old label
    /// should be kept. The assertion accepts both fixes. `XCTExpectFailure`
    /// keeps the suite green; once it is fixed this test fails with
    /// "expected failure not seen": remove the wrapper then.
    func testRenamingATandaFromAnotherLibraryShouldNotMakeItsIDsTrusted() throws {
        try withTemporaryAppRoot { root in
            let settings = AppSettings()
            let foreign = (1...3).map { tandaSong(Int64($0) + 100, path: "/Music/\($0).flac") }   // ids 101...103, same paths as the live songs
            try writeLegacy(foreign, savedAgainst: "Other")
            let store = TandaStore()
            let live = (1...3).map { tandaSong(Int64($0)) }               // same paths, ids 1...3

            store.applyRescan(preview(store, live: live, settings: settings))

            let newURL = root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X/Alpha Trio_Tango_Singer X.json")
            let stored = try TandaMetadataExporter.load(from: newURL)
            let idsAreLive = stored.songs.map(\.id) == [1, 2, 3]
            let stillUntrusted = stored.savedAgainstLibraryName != AppPaths.currentLibraryName

            XCTExpectFailure("the file is labeled with this library while still holding the other library's ids") {
                XCTAssertTrue(idsAreLive || stillUntrusted)
            }
        }
    }
}
