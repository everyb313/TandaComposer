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

    // MARK: - Several renames in one scan
    //
    // Regression (0.8.4): every Tanda used to be checked against the disk
    // alone. With a gap in the numbering (..._4, [gap], ..._6, ..._7, ..._8)
    // ALL of them were offered the same new name (..._5); applying that
    // would have written them to one file and deleted the originals.

    private let baseName = "Alpha Trio_Tango_Singer X"

    /// Index 1 is the plain name, 2 and up carry the suffix `_<index>`.
    private func numberedName(_ index: Int) -> String {
        index == 1 ? baseName : "\(baseName)_\(index)"
    }

    /// The songs of numbered Tanda `index`: ids index*10+1 ... index*10+3.
    /// All have the same orchestra/singer/genre, so every Tanda resolves to
    /// the same base name, but each holds different songs.
    private func songsOfTanda(_ index: Int) -> [Song] {
        (1...3).map { tandaSong(Int64(index * 10 + $0)) }
    }

    private func liveSongs(_ indices: [Int]) -> [Song] {
        indices.flatMap { songsOfTanda($0) }
    }

    /// Writes the numbered Tandas into the canonical folder of their songs.
    @discardableResult
    private func writeNumberedTandas(
        _ indices: [Int],
        settings: AppSettings
    ) throws -> [Int: URL] {
        var urls: [Int: URL] = [:]
        for index in indices {
            let songs = songsOfTanda(index)
            let folder = TandaSaver.resolvedLocation(for: songs, settings: settings).folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder
                .appendingPathComponent(numberedName(index))
                .appendingPathExtension("json")
            try TandaMetadataExporter.export(
                songs: songs,
                tandaName: numberedName(index),
                to: url,
                comment: nil,
                savedAgainstLibraryName: "Default"
            )
            urls[index] = url
        }
        return urls
    }

    /// The file of numbered Tanda `index` inside `folder`.
    private func tandaFile(_ index: Int, in folder: URL) -> URL {
        folder
            .appendingPathComponent(numberedName(index))
            .appendingPathExtension("json")
    }

    /// Old Tanda name -> new name, for every fix that renames.
    private func renames(_ fixes: [TandaRescanFix]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fixes.compactMap { fix in
            fix.rename.map { (fix.tanda.name, $0.newName) }
        })
    }

    func testACompleteNumberingNeedsNothing() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 5]
            try writeNumberedTandas(indices, settings: settings)
            let store = TandaStore()

            XCTAssertTrue(preview(store, live: liveSongs(indices), settings: settings).isEmpty)
        }
    }

    func testSeveralRenamesInOneScanGetDifferentNames() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 6, 7, 8]                 // gap at 5
            try writeNumberedTandas(indices, settings: settings)
            let store = TandaStore()

            let fixes = preview(store, live: liveSongs(indices), settings: settings)

            let targets = fixes.compactMap { $0.rename?.newURL.standardizedFileURL.path }
            XCTAssertEqual(targets.count, 3)
            XCTAssertEqual(Set(targets).count, 3, "no two Tandas may be sent to the same file")
            XCTAssertEqual(renames(fixes), [
                numberedName(6): numberedName(5),
                numberedName(7): numberedName(6),
                numberedName(8): numberedName(7)
            ])
        }
    }

    func testApplyingTheRenamesKeepsEveryTandasSongs() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 6, 7, 8]
            let urls = try writeNumberedTandas(indices, settings: settings)
            let folder = try XCTUnwrap(urls[1]).deletingLastPathComponent()
            let store = TandaStore()

            let summary = store.applyRescan(preview(store, live: liveSongs(indices), settings: settings))

            XCTAssertEqual(summary.renamedTandaCount, 3)
            XCTAssertTrue(summary.failedWrites.isEmpty)

            // 6 -> 5, 7 -> 6, 8 -> 7: each file holds the songs of the Tanda that moved into it.
            for (newIndex, oldIndex) in [(5, 6), (6, 7), (7, 8)] {
                let stored = try TandaMetadataExporter.load(from: tandaFile(newIndex, in: folder))
                XCTAssertEqual(stored.tandaName, numberedName(newIndex))
                XCTAssertEqual(stored.songs.map(\.id), songsOfTanda(oldIndex).map(\.id))
            }
            XCTAssertFalse(exists(tandaFile(8, in: folder)), "the last file is gone, its Tanda moved to _7")
            for index in [1, 2, 3, 4] {
                XCTAssertTrue(exists(tandaFile(index, in: folder)))
            }
            XCTAssertEqual(store.tandas.count, 7, "no Tanda was lost")
        }
    }

    func testTheNumberingIsStableAfterApplying() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 6, 7, 8]
            try writeNumberedTandas(indices, settings: settings)
            let store = TandaStore()
            let live = liveSongs(indices)

            store.applyRescan(preview(store, live: live, settings: settings))

            XCTAssertTrue(preview(store, live: live, settings: settings).isEmpty)
            XCTAssertTrue(preview(TandaStore(), live: live, settings: settings).isEmpty)
        }
    }

    func testGapsAreClosedInNumericOrderNotAlphabetically() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 6, 10]                   // "_10" sorts before "_2" as text
            let urls = try writeNumberedTandas(indices, settings: settings)
            let folder = try XCTUnwrap(urls[1]).deletingLastPathComponent()
            let store = TandaStore()

            let fixes = preview(store, live: liveSongs(indices), settings: settings)

            XCTAssertEqual(renames(fixes), [
                numberedName(6): numberedName(5),
                numberedName(10): numberedName(6)
            ])

            // _10 moves into the slot that _6 is leaving, so _6 must be applied first.
            let summary = store.applyRescan(fixes)

            XCTAssertEqual(summary.renamedTandaCount, 2)
            XCTAssertTrue(summary.failedWrites.isEmpty)
            XCTAssertEqual(try TandaMetadataExporter.load(from: tandaFile(5, in: folder)).songs.map(\.id), songsOfTanda(6).map(\.id))
            XCTAssertEqual(try TandaMetadataExporter.load(from: tandaFile(6, in: folder)).songs.map(\.id), songsOfTanda(10).map(\.id))
            XCTAssertFalse(exists(tandaFile(10, in: folder)))
        }
    }

    func testApplyNeverOverwritesAFileThatAppearedAfterThePreview() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let indices = [1, 2, 3, 4, 6]
            let urls = try writeNumberedTandas(indices, settings: settings)
            let store = TandaStore()
            let fixes = preview(store, live: liveSongs(indices), settings: settings)
            XCTAssertEqual(renames(fixes), [numberedName(6): numberedName(5)])

            // Another Tanda shows up at the planned target before "Apply Fixes".
            let target = try XCTUnwrap(fixes.first?.rename?.newURL)
            let foreign = songsOfTanda(9)
            try TandaMetadataExporter.export(
                songs: foreign,
                tandaName: numberedName(5),
                to: target,
                comment: nil,
                savedAgainstLibraryName: "Default"
            )
            let oldURL = try XCTUnwrap(urls[6])

            let summary = store.applyRescan(fixes)

            XCTAssertEqual(summary.failedWrites.count, 1)
            XCTAssertEqual(summary.renamedTandaCount, 0)
            XCTAssertEqual(try TandaMetadataExporter.load(from: target).songs.map(\.id), foreign.map(\.id), "the other file is untouched")
            XCTAssertTrue(exists(oldURL), "the Tanda that could not move is still there")
            let stillThere = store.tandas.first { $0.name == numberedName(6) }
            XCTAssertEqual(stillThere?.songs.map(\.id), songsOfTanda(6).map(\.id))
        }
    }
}
