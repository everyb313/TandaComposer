import XCTest
import Foundation

/// Rescan of the saved Setlist files: references to files that moved are
/// rewritten, references to missing files are only reported.
@MainActor
final class SavedSetlistsRescannerTests: XCTestCase {

    // MARK: - Helpers

    private func saved(_ id: Int64, _ path: String) -> Song {
        makeSong(id: id, path: path, title: "T\(id)", artist: "Alpha Trio")
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

    @discardableResult
    private func saveSetlist(
        _ name: String,
        songs: [Song],
        savedAgainst: String? = "Default"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.setlistsFolder, withIntermediateDirectories: true)
        let url = SetlistStore.fileURLOnDisk(forName: name)
        try SetlistMetadataExporter.export(
            songs: songs,
            setlistName: name,
            to: url,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    private func preview(live: [Song], missing: Set<Int64> = []) -> [SavedSetlistRescanFix] {
        let lookup = tables(live)
        return SavedSetlistsRescanner.previewRescan(
            byID: lookup.byID,
            byPath: lookup.byPath,
            missingSongIDs: missing
        )
    }

    // MARK: - previewRescan

    func testNoSetlistsNoFixes() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertTrue(preview(live: [saved(1, "/Music/1.flac")]).isEmpty)
        }
    }

    func testUnchangedSetlistsNeedNoFix() throws {
        try withTemporaryAppRoot { _ in
            let songs = [saved(1, "/Music/1.flac"), saved(2, "/Music/2.flac")]
            try saveSetlist("Friday", songs: songs)

            XCTAssertTrue(preview(live: songs).isEmpty)
        }
    }

    func testAMovedFileIsFixedAndTheOtherEntriesStayUntouched() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [saved(1, "/Old/1.flac"), saved(2, "/Same/2.flac")])
            let live = [saved(1, "/New/1.flac"), saved(2, "/Same/2.flac")]

            let fixes = preview(live: live)

            XCTAssertEqual(fixes.count, 1)
            let fix = try XCTUnwrap(fixes.first)
            XCTAssertEqual(fix.name, "Friday")
            XCTAssertTrue(samePath(fix.url, SetlistStore.fileURLOnDisk(forName: "Friday")))
            XCTAssertEqual(fix.fixedSongCount, 1)
            XCTAssertEqual(fix.updatedSongs.map(\.path), ["/New/1.flac", "/Same/2.flac"])
            XCTAssertTrue(fix.missingSongTitles.isEmpty)
        }
    }

    func testAMissingFileIsReportedButNotChanged() throws {
        try withTemporaryAppRoot { _ in
            let songs = [saved(1, "/Music/1.flac"), saved(2, "/Music/2.flac")]
            try saveSetlist("Friday", songs: songs)

            let fixes = preview(live: songs, missing: [2])

            let fix = try XCTUnwrap(fixes.first)
            XCTAssertEqual(fix.fixedSongCount, 0)
            XCTAssertEqual(fix.missingSongTitles, ["T2"])
            XCTAssertEqual(fix.updatedSongs.map(\.path), ["/Music/1.flac", "/Music/2.flac"])
        }
    }

    func testAMissingFileWithoutATitleIsReportedByItsFileName() throws {
        try withTemporaryAppRoot { _ in
            var untitled = saved(1, "/Music/1.flac")
            untitled.title = nil
            try saveSetlist("Friday", songs: [untitled])

            let fixes = preview(live: [untitled], missing: [1])

            XCTAssertEqual(fixes.first?.missingSongTitles, ["1.flac"])
        }
    }

    func testAMovedAndMissingFileCountsAsBoth() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [saved(1, "/Old/1.flac")])

            let fixes = preview(live: [saved(1, "/New/1.flac")], missing: [1])

            XCTAssertEqual(fixes.first?.fixedSongCount, 1)
            XCTAssertEqual(fixes.first?.missingSongTitles, ["T1"])
        }
    }

    func testSongsThatAreNotInTheLibraryAreLeftAlone() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [saved(1, "/Music/1.flac")])

            XCTAssertTrue(preview(live: [saved(2, "/Music/other.flac")]).isEmpty)
        }
    }

    func testOnlySetlistsThatNeedAFixAreListed() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Alpha", songs: [saved(1, "/Music/1.flac")])
            try saveSetlist("Beta", songs: [saved(2, "/Old/2.flac")])
            try saveSetlist("Gamma", songs: [saved(3, "/Music/3.flac")])
            let live = [saved(1, "/Music/1.flac"), saved(2, "/New/2.flac"), saved(3, "/Music/3.flac")]

            XCTAssertEqual(preview(live: live).map(\.name), ["Beta"])
        }
    }

    func testIDsOfAnotherLibraryAreNotTrusted() throws {
        try withTemporaryAppRoot { _ in
            // The file was saved against "Other"; id 7 means something else here.
            let stored = saved(7, "/Music/x.flac")
            try saveSetlist("Imported", songs: [stored], savedAgainst: "Other")
            let live = [saved(1, "/Music/x.flac"), saved(7, "/Elsewhere/y.flac")]

            XCTAssertTrue(
                preview(live: live).isEmpty,
                "resolved by path to id 1 (same path), not by id to the unrelated id 7"
            )
        }
    }

    func testTheSameFileSavedAgainstThisLibraryIsResolvedByID() throws {
        try withTemporaryAppRoot { _ in
            let stored = saved(7, "/Music/x.flac")
            try saveSetlist("Own", songs: [stored], savedAgainst: "Default")
            let live = [saved(1, "/Music/x.flac"), saved(7, "/Elsewhere/y.flac")]

            let fixes = preview(live: live)

            XCTAssertEqual(fixes.first?.updatedSongs.map(\.path), ["/Elsewhere/y.flac"])
        }
    }

    func testFilesWithoutALibraryNameAreNotTrustedEither() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Old Format", songs: [saved(7, "/Music/x.flac")], savedAgainst: nil)
            let live = [saved(1, "/Music/x.flac"), saved(7, "/Elsewhere/y.flac")]

            XCTAssertTrue(preview(live: live).isEmpty)
        }
    }

    func testBrokenAndForeignFilesAreSkipped() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Good", songs: [saved(1, "/Old/1.flac")])
            try "garbage".write(to: SetlistStore.fileURLOnDisk(forName: "Broken"), atomically: true, encoding: .utf8)
            try "notes".write(to: AppPaths.setlistsFolder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

            let fixes = preview(live: [saved(1, "/New/1.flac")])

            XCTAssertEqual(fixes.map(\.name), ["Good"])
        }
    }

    // MARK: - applyRescan

    func testApplyWritesTheFixedSongsAndCountsThem() throws {
        try withTemporaryAppRoot { _ in
            let url = try saveSetlist("Friday", songs: [saved(1, "/Old/1.flac"), saved(2, "/Same/2.flac")], savedAgainst: "Default")
            let fixes = preview(live: [saved(1, "/New/1.flac"), saved(2, "/Same/2.flac")])

            let summary = SavedSetlistsRescanner.applyRescan(fixes)

            XCTAssertEqual(summary.fixedReferenceCount, 1)
            XCTAssertEqual(summary.updatedSetlistCount, 1)
            XCTAssertEqual(summary.missingReferenceCount, 0)
            XCTAssertTrue(summary.failedWrites.isEmpty)

            let reloaded = try SetlistMetadataExporter.load(from: url)
            XCTAssertEqual(reloaded.setlistName, "Friday")
            XCTAssertEqual(reloaded.songs.map(\.path), ["/New/1.flac", "/Same/2.flac"])
            XCTAssertEqual(reloaded.savedAgainstLibraryName, "Default")
        }
    }

    func testApplyDoesNotRewriteSetlistsThatOnlyHaveMissingFiles() throws {
        try withTemporaryAppRoot { _ in
            let songs = [saved(1, "/Music/1.flac")]
            let url = try saveSetlist("Friday", songs: songs)
            let before = try Data(contentsOf: url)
            let fixes = preview(live: songs, missing: [1])

            let summary = SavedSetlistsRescanner.applyRescan(fixes)

            XCTAssertEqual(summary.missingReferenceCount, 1)
            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertEqual(summary.updatedSetlistCount, 0)
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testApplySumsUpSeveralSetlists() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Alpha", songs: [saved(1, "/Old/1.flac"), saved(2, "/Old/2.flac")])
            try saveSetlist("Beta", songs: [saved(1, "/Old/1.flac"), saved(3, "/Music/3.flac")])
            let live = [saved(1, "/New/1.flac"), saved(2, "/New/2.flac"), saved(3, "/Music/3.flac")]

            let summary = SavedSetlistsRescanner.applyRescan(preview(live: live, missing: [3]))

            XCTAssertEqual(summary.fixedReferenceCount, 3)
            XCTAssertEqual(summary.updatedSetlistCount, 2)
            XCTAssertEqual(summary.missingReferenceCount, 1)
        }
    }

    func testApplyOfNoFixesDoesNothing() throws {
        try withTemporaryAppRoot { _ in
            let summary = SavedSetlistsRescanner.applyRescan([])

            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertEqual(summary.updatedSetlistCount, 0)
            XCTAssertEqual(summary.missingReferenceCount, 0)
            XCTAssertTrue(summary.failedWrites.isEmpty)
        }
    }

    func testApplyReportsFilesThatCannotBeWritten() throws {
        try withTemporaryAppRoot { root in
            let unwritable = root.appendingPathComponent("no/such/folder/Friday.json")
            let fix = SavedSetlistRescanFix(
                name: "Friday",
                url: unwritable,
                updatedSongs: [saved(1, "/New/1.flac")],
                fixedSongCount: 1,
                missingSongTitles: []
            )

            let summary = SavedSetlistsRescanner.applyRescan([fix])

            XCTAssertEqual(summary.failedWrites.count, 1)
            XCTAssertEqual(summary.failedWrites.first?.url, unwritable)
            XCTAssertEqual(summary.fixedReferenceCount, 0)
            XCTAssertEqual(summary.updatedSetlistCount, 0)
        }
    }

    func testAnAppliedRescanLeavesNothingToFixTheSecondTime() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [saved(1, "/Old/1.flac"), saved(2, "/Old/2.flac")])
            let live = [saved(1, "/New/1.flac"), saved(2, "/New/2.flac")]

            SavedSetlistsRescanner.applyRescan(preview(live: live))

            XCTAssertTrue(preview(live: live).isEmpty)
        }
    }
}
