import XCTest
import Foundation

/// Tandas are plain JSON files below `AppPaths.tandasFolder`. All tests run
/// inside `withTemporaryAppRoot`, so they only ever see the temporary folder.
@MainActor
final class TandaStoreTests: XCTestCase {

    // MARK: - Helpers

    private func folder(_ subfolder: String? = nil) -> URL {
        guard let subfolder else {
            return AppPaths.tandasFolder
        }
        return AppPaths.tandasFolder.appendingPathComponent(subfolder, isDirectory: true)
    }

    @discardableResult
    private func writeTanda(
        _ name: String,
        in subfolder: String? = nil,
        songs: [Song],
        comment: String? = nil,
        savedAgainst: String? = "Default"
    ) throws -> URL {
        let directory = folder(subfolder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension("json")
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: name,
            to: url,
            comment: comment,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    private func tanda(_ name: String, in store: TandaStore) throws -> Tanda {
        try XCTUnwrap(store.tandas.first { $0.name == name }, "no Tanda named \(name)")
    }

    private func titles(_ tanda: Tanda) -> [String?] {
        tanda.songs.map(\.title)
    }

    private func reloadedTitles(_ name: String) throws -> [String?] {
        let fresh = TandaStore()
        return titles(try tanda(name, in: fresh))
    }

    // MARK: - Loading

    func testEmptyWhenThereIsNoTandasFolder() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertTrue(TandaStore().tandas.isEmpty)
        }
    }

    func testLoadsTandasFromAllSubfoldersAndRemembersTheFolder() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set A", songs: makeSongs(3))
            try writeTanda("Set B", in: "Di Sarli", songs: makeSongs(3))
            try writeTanda("Set C", in: "Di Sarli/1940s", songs: makeSongs(3))

            let store = TandaStore()

            XCTAssertEqual(Set(store.tandas.map(\.name)), ["Set A", "Set B", "Set C"])
            XCTAssertEqual(try tanda("Set A", in: store).sourceFolder, "")
            XCTAssertEqual(try tanda("Set B", in: store).sourceFolder, "Di Sarli")
            XCTAssertEqual(try tanda("Set C", in: store).sourceFolder, "Di Sarli/1940s")
        }
    }

    func testOnlyJSONFilesWithAValidTandaAreLoaded() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Good", songs: makeSongs(3))
            try FileManager.default.createDirectory(at: folder(), withIntermediateDirectories: true)
            try "notes".write(to: folder().appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            try "garbage".write(to: folder().appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
            try "{}".write(to: folder().appendingPathComponent("empty-object.json"), atomically: true, encoding: .utf8)

            let store = TandaStore()

            XCTAssertEqual(store.tandas.map(\.name), ["Good"])
        }
    }

    func testUppercaseJSONExtensionIsAccepted() throws {
        try withTemporaryAppRoot { _ in
            try FileManager.default.createDirectory(at: folder(), withIntermediateDirectories: true)
            let url = folder().appendingPathComponent("Upper.JSON")
            try TandaMetadataExporter.export(songs: makeSongs(3), tandaName: "Upper", to: url)

            XCTAssertEqual(TandaStore().tandas.map(\.name), ["Upper"])
        }
    }

    func testTandaCarriesSongsCommentAndLibraryName() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Commented", songs: makeSongs(3), comment: "Fast ones", savedAgainst: "Other")
            try writeTanda("Plain", songs: makeSongs(4), comment: nil, savedAgainst: nil)

            let store = TandaStore()

            let commented = try tanda("Commented", in: store)
            XCTAssertEqual(commented.comment, "Fast ones")
            XCTAssertEqual(commented.savedAgainstLibraryName, "Other")
            XCTAssertEqual(titles(commented), ["T1", "T2", "T3"])

            let plain = try tanda("Plain", in: store)
            XCTAssertEqual(plain.comment, "", "no comment is an empty string, not nil")
            XCTAssertNil(plain.savedAgainstLibraryName)
            XCTAssertEqual(plain.songs.count, 4)
        }
    }

    func testReloadPicksUpFilesAddedAndRemovedBehindTheStoresBack() throws {
        try withTemporaryAppRoot { _ in
            let first = try writeTanda("First", songs: makeSongs(3))
            let store = TandaStore()
            XCTAssertEqual(store.tandas.count, 1)

            try writeTanda("Second", songs: makeSongs(3))
            try FileManager.default.removeItem(at: first)
            store.reload()

            XCTAssertEqual(store.tandas.map(\.name), ["Second"])
        }
    }

    // MARK: - Replace Song

    func testReplaceSongChangesOnlyTheRequestedSlotAndPersistsIt() throws {
        try withTemporaryAppRoot { _ in
            let originalSongs = makeSongs(4)
            try writeTanda("Replaceable", songs: originalSongs, comment: "keep this")
            let store = TandaStore()
            let originalTanda = try tanda("Replaceable", in: store)
            let replacement = makeSong(
                id: 99,
                path: "/Music/alternate-T2.flac",
                title: "T2",
                artist: "Alternate Orchestra"
            )

            try store.replaceSong(
                at: 1,
                in: originalTanda,
                expectedOriginalPath: originalSongs[1].normalizedPath,
                with: replacement,
                librarySongs: originalSongs + [replacement]
            )

            let updated = try tanda("Replaceable", in: store)
            XCTAssertEqual(updated.songs.map(\.normalizedPath), [
                originalSongs[0].normalizedPath,
                replacement.normalizedPath,
                originalSongs[2].normalizedPath,
                originalSongs[3].normalizedPath
            ])
            XCTAssertEqual(updated.comment, "keep this")
            XCTAssertEqual(
                try tanda("Replaceable", in: TandaStore()).songs.map(\.normalizedPath),
                updated.songs.map(\.normalizedPath),
                "The replacement must be persisted to the Tanda JSON file."
            )
        }
    }

    // MARK: - Delete and comment

    func testDeleteRemovesTheFileAndTheEntry() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Gone", songs: makeSongs(3))
            try writeTanda("Stays", songs: makeSongs(3))
            let store = TandaStore()

            try store.delete(try tanda("Gone", in: store))

            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(store.tandas.map(\.name), ["Stays"])
        }
    }

    func testUpdateCommentIsStoredInMemoryAndOnDisk() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(3), comment: "old")
            let store = TandaStore()

            try store.updateComment(for: try tanda("Set", in: store), to: "new comment")

            XCTAssertEqual(try tanda("Set", in: store).comment, "new comment")
            XCTAssertEqual(try tanda("Set", in: TandaStore()).comment, "new comment")
        }
    }

    func testUpdateCommentKeepsTheSongs() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(4))
            let store = TandaStore()

            try store.updateComment(for: try tanda("Set", in: store), to: "x")

            XCTAssertEqual(try reloadedTitles("Set"), ["T1", "T2", "T3", "T4"])
        }
    }

    // MARK: - Adding songs

    private func extra(_ number: Int) -> Song {
        makeSong(id: Int64(number), path: "/Music/\(number).flac", title: "T\(number)", artist: "A\(number)")
    }

    func testAddSongsAppendsAndPersists() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(3))
            let store = TandaStore()

            try store.addSongs([extra(4), extra(5)], to: try tanda("Set", in: store))

            XCTAssertEqual(titles(try tanda("Set", in: store)), ["T1", "T2", "T3", "T4", "T5"])
            XCTAssertEqual(try reloadedTitles("Set"), ["T1", "T2", "T3", "T4", "T5"])
        }
    }

    func testAddSongsSkipsSongsThatAreAlreadyInTheTanda() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(3))
            let store = TandaStore()

            try store.addSongs([extra(1), extra(4)], to: try tanda("Set", in: store))

            XCTAssertEqual(titles(try tanda("Set", in: store)), ["T1", "T2", "T3", "T4"])
        }
    }

    func testAddingOnlyDuplicatesChangesNothing() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Set", songs: makeSongs(3))
            let before = try Data(contentsOf: url)
            let store = TandaStore()

            try store.addSongs([extra(2)], to: try tanda("Set", in: store))

            XCTAssertEqual(try Data(contentsOf: url), before, "file must not even be rewritten")
        }
    }

    func testAddSongsRefusesTracksThatAreMissingOnDisk() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Set", songs: makeSongs(3))
            let before = try Data(contentsOf: url)
            let store = TandaStore()

            do {
                try store.addSongs([extra(4), extra(5)], to: try tanda("Set", in: store), missingSongIDs: [5])
                XCTFail("expected containsMissingTracks")
            } catch TandaSaveError.containsMissingTracks(let titles) {
                XCTAssertEqual(titles, ["T5"])
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(try Data(contentsOf: url), before)
            XCTAssertEqual(try tanda("Set", in: store).songs.count, 3)
        }
    }

    func testMissingFlagOfAnAlreadyContainedSongIsIgnored() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(3))
            let store = TandaStore()

            XCTAssertNoThrow(
                try store.addSongs([extra(1), extra(4)], to: try tanda("Set", in: store), missingSongIDs: [1])
            )
            XCTAssertEqual(try tanda("Set", in: store).songs.count, 4)
        }
    }

    func testAddSongsAllowsExactlyEightTracks() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(6))
            let store = TandaStore()

            try store.addSongs([extra(7), extra(8)], to: try tanda("Set", in: store))

            XCTAssertEqual(try tanda("Set", in: store).songs.count, 8)
        }
    }

    func testAddSongsRefusesMoreThanEightTracks() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Set", songs: makeSongs(7))
            let before = try Data(contentsOf: url)
            let store = TandaStore()

            do {
                try store.addSongs([extra(8), extra(9)], to: try tanda("Set", in: store))
                XCTFail("expected tooManyTracks")
            } catch TandaSaveError.tooManyTracks(let count) {
                XCTAssertEqual(count, 9)
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testAddSongsKeepsCommentAndFolder() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", in: "Di Sarli", songs: makeSongs(3), comment: "keep me")
            let store = TandaStore()

            try store.addSongs([extra(4)], to: try tanda("Set", in: store))

            let updated = try tanda("Set", in: store)
            XCTAssertEqual(updated.comment, "keep me")
            XCTAssertEqual(updated.sourceFolder, "Di Sarli")
            XCTAssertEqual(try tanda("Set", in: TandaStore()).comment, "keep me")
        }
    }

    // MARK: - Removing songs

    func testRemoveSongDropsThatTrackAndPersists() throws {
        try withTemporaryAppRoot { _ in
            try writeTanda("Set", songs: makeSongs(4))
            let store = TandaStore()

            try store.removeSong(at: 1, from: try tanda("Set", in: store))

            XCTAssertEqual(titles(try tanda("Set", in: store)), ["T1", "T3", "T4"])
            XCTAssertEqual(try reloadedTitles("Set"), ["T1", "T3", "T4"])
        }
    }

    func testRemoveSongRefusesToGoBelowThreeTracks() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Set", songs: makeSongs(3))
            let before = try Data(contentsOf: url)
            let store = TandaStore()

            do {
                try store.removeSong(at: 0, from: try tanda("Set", in: store))
                XCTFail("expected wouldDropBelowMinimum")
            } catch TandaSaveError.wouldDropBelowMinimum(let count) {
                XCTAssertEqual(count, 3)
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testRemoveSongWithAnInvalidIndexDoesNothing() throws {
        try withTemporaryAppRoot { _ in
            let url = try writeTanda("Set", songs: makeSongs(4))
            let before = try Data(contentsOf: url)
            let store = TandaStore()
            let target = try tanda("Set", in: store)

            XCTAssertNoThrow(try store.removeSong(at: 9, from: target))
            XCTAssertNoThrow(try store.removeSong(at: -1, from: target))

            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    // MARK: - Errors

    func testSaveErrorDescriptionsAreHelpful() {
        XCTAssertTrue(TandaSaveError.tooFewTracks(2).errorDescription?.contains("2") == true)
        XCTAssertTrue(TandaSaveError.tooManyTracks(9).errorDescription?.contains("9") == true)
        XCTAssertTrue(TandaSaveError.duplicateTanda(existingName: "Set A").errorDescription?.contains("Set A") == true)
        XCTAssertTrue(TandaSaveError.containsMissingTracks(titles: ["X", "Y"]).errorDescription?.contains("X, Y") == true)
        XCTAssertNotNil(TandaSaveError.wouldDropBelowMinimum(3).errorDescription)
    }
}
