import XCTest
import Foundation

/// `TandaSaver.save(...)`: validation, the order of the checks, the file that
/// is written, and the `.tandaSaved` notification. Where a Tanda's folder and
/// file name come from is covered in `TandaSaverLocationTests` and
/// `TandaSaverNamingTests`.
@MainActor
final class TandaSaverSaveTests: XCTestCase {

    // MARK: - Helpers

    private func song(
        _ id: Int64,
        title: String? = nil,
        artist: String? = "Alpha Trio",
        albumArtist: String? = "Singer X",
        genre: String? = "Tango",
        grouping: String? = nil,
        withID: Bool = true
    ) -> Song {
        makeSong(
            id: withID ? id : nil,
            path: "/Music/\(id).flac",
            title: title ?? "T\(id)",
            artist: artist,
            albumArtist: albumArtist,
            genre: genre,
            grouping: grouping
        )
    }

    private func songs(_ count: Int) -> [Song] {
        (0..<count).map { song(Int64($0 + 1)) }
    }

    private func existingTanda(name: String, songs: [Song]) -> Tanda {
        Tanda(
            name: name,
            songs: songs,
            comment: "",
            sourceFolder: "",
            sourceURL: URL(fileURLWithPath: "/tmp/\(name).json"),
            savedAgainstLibraryName: nil
        )
    }

    /// The error `save` throws, or nil when it succeeds.
    private func saveError(
        _ songs: [Song],
        existing: [Tanda] = [],
        missing: Set<Int64> = [],
        settings: AppSettings? = nil
    ) -> TandaSaveError? {
        do {
            try TandaSaver.save(
                songs: songs,
                existingTandas: existing,
                missingSongIDs: missing,
                settings: settings ?? AppSettings()
            )
            return nil
        } catch let error as TandaSaveError {
            return error
        } catch {
            XCTFail("unexpected error type: \(error)")
            return nil
        }
    }

    private func tandaFolderIsUntouched() -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            atPath: AppPaths.tandasFolder.path
        )) ?? []

        return entries.isEmpty
    }

    // MARK: - Track count

    func testFewerThanThreeTracksAreRejected() throws {
        try withTemporaryAppRoot { _ in
            for count in 0...2 {
                guard case .tooFewTracks(let reported)? = saveError(songs(count)) else {
                    return XCTFail("\(count) tracks should be too few")
                }

                XCTAssertEqual(reported, count)
            }
        }
    }

    func testMoreThanEightTracksAreRejected() throws {
        try withTemporaryAppRoot { _ in
            guard case .tooManyTracks(let reported)? = saveError(songs(9)) else {
                return XCTFail("9 tracks should be too many")
            }

            XCTAssertEqual(reported, 9)
        }
    }

    func testThreeAndEightTracksAreTheAcceptedLimits() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertNil(saveError(songs(3)))
            XCTAssertNil(saveError(songs(8)), "same fields, so the second file gets its own number")
        }
    }

    // MARK: - Missing tracks

    func testATrackMissingOnDiskIsRejectedByTitle() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)

            guard case .containsMissingTracks(let titles)? = saveError(tracks, missing: [2]) else {
                return XCTFail("expected containsMissingTracks")
            }

            XCTAssertEqual(titles, ["T2"])
        }
    }

    func testAllMissingTracksAreListedInTandaOrder() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(4)

            guard case .containsMissingTracks(let titles)? = saveError(tracks, missing: [4, 1]) else {
                return XCTFail("expected containsMissingTracks")
            }

            XCTAssertEqual(titles, ["T1", "T4"])
        }
    }

    func testMissingTrackWithoutTitleIsListedByFileName() throws {
        try withTemporaryAppRoot { _ in
            var tracks = songs(3)
            tracks[1].title = nil

            guard case .containsMissingTracks(let titles)? = saveError(tracks, missing: [2]) else {
                return XCTFail("expected containsMissingTracks")
            }

            XCTAssertEqual(titles, ["2.flac"])
        }
    }

    func testSongsWithoutAnIDCannotBeMissing() throws {
        try withTemporaryAppRoot { _ in
            let tracks = [song(1, withID: false), song(2, withID: false), song(3, withID: false)]

            XCTAssertNil(saveError(tracks, missing: [1, 2, 3]))
        }
    }

    func testMissingIDsOfOtherSongsAreIgnored() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertNil(saveError(songs(3), missing: [99, 100]))
        }
    }

    // MARK: - Duplicates

    func testTheSameTracksAlreadySavedAreRejectedWhateverTheOrder() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)
            let existing = existingTanda(name: "Alpha Trio 1", songs: Array(tracks.reversed()))

            guard case .duplicateTanda(let name)? = saveError(tracks, existing: [existing]) else {
                return XCTFail("expected duplicateTanda")
            }

            XCTAssertEqual(name, "Alpha Trio 1")
        }
    }

    func testDuplicateIsDecidedByPathNotByDatabaseID() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)
            // Same files, different IDs (as in another library).
            let otherIDs = tracks.map { original -> Song in
                var copy = original
                copy.id = (original.id ?? 0) + 100
                return copy
            }

            guard case .duplicateTanda? = saveError(tracks, existing: [existingTanda(name: "Other", songs: otherIDs)]) else {
                return XCTFail("expected duplicateTanda")
            }
        }
    }

    func testADifferentSetOfTracksIsNoDuplicate() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)
            var others = songs(3)
            others[2] = song(4)

            XCTAssertNil(saveError(tracks, existing: [existingTanda(name: "Other", songs: others)]))
        }
    }

    func testASubsetOrSupersetIsNoDuplicate() throws {
        try withTemporaryAppRoot { _ in
            let five = songs(5)
            let existing = existingTanda(name: "Three", songs: Array(five.prefix(3)))

            XCTAssertNil(saveError(Array(five.prefix(4)), existing: [existing]))
        }
    }

    func testTheDuplicateIsFoundAmongSeveralExistingTandas() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)
            let existing = [
                existingTanda(name: "A", songs: songs(4)),
                existingTanda(name: "B", songs: tracks),
                existingTanda(name: "C", songs: songs(5))
            ]

            guard case .duplicateTanda(let name)? = saveError(tracks, existing: existing) else {
                return XCTFail("expected duplicateTanda")
            }

            XCTAssertEqual(name, "B")
        }
    }

    // MARK: - Order of the checks

    func testTrackCountIsCheckedBeforeMissingTracks() throws {
        try withTemporaryAppRoot { _ in
            guard case .tooFewTracks? = saveError(songs(2), missing: [1]) else {
                return XCTFail("expected tooFewTracks")
            }
        }
    }

    func testMissingTracksAreCheckedBeforeDuplicates() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)

            guard case .containsMissingTracks? = saveError(
                tracks,
                existing: [existingTanda(name: "A", songs: tracks)],
                missing: [1]
            ) else {
                return XCTFail("expected containsMissingTracks")
            }
        }
    }

    // MARK: - Nothing is written on failure

    func testRejectedTandasCreateNoFoldersAndPostNoNotification() throws {
        try withTemporaryAppRoot { _ in
            let notExpected = XCTNSNotificationExpectation(name: AppNotification.tandaSaved)
            notExpected.isInverted = true

            XCTAssertNotNil(saveError(songs(2)))
            XCTAssertNotNil(saveError(songs(9)))
            XCTAssertNotNil(saveError(songs(3), missing: [1]))
            XCTAssertNotNil(saveError(songs(3), existing: [existingTanda(name: "A", songs: songs(3))]))

            wait(for: [notExpected], timeout: 0.2)
            XCTAssertTrue(tandaFolderIsUntouched())
        }
    }

    // MARK: - Successful save

    func testSaveWritesTheTandaFileIntoOrchestraAndSingerFolder() throws {
        try withTemporaryAppRoot { root in
            let tracks = songs(3)

            let url = try TandaSaver.save(songs: tracks, settings: AppSettings())

            let expectedFolder = root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X")
            XCTAssertTrue(samePath(url.deletingLastPathComponent(), expectedFolder))
            XCTAssertEqual(url.lastPathComponent, "Alpha Trio_Tango_Singer X.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testSavedFileHoldsNameSongsInOrderAndTheLibraryName() throws {
        try withTemporaryAppRoot { _ in
            let tracks = [song(3), song(1), song(2)]

            let url = try TandaSaver.save(songs: tracks, settings: AppSettings())
            let loaded = try TandaMetadataExporter.load(from: url)

            XCTAssertEqual(loaded.tandaName, "Alpha Trio_Tango_Singer X")
            XCTAssertEqual(loaded.songs.map(\.id), [3, 1, 2])
            XCTAssertEqual(loaded.songs.map(\.path), tracks.map(\.path))
            XCTAssertEqual(loaded.savedAgainstLibraryName, AppPaths.defaultLibraryName)
            XCTAssertNil(loaded.comment)
        }
    }

    func testMixedTandaIsSavedInTheVariousFolders() throws {
        try withTemporaryAppRoot { root in
            let tracks = [
                song(1, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango"),
                song(2, artist: "Beta Band", albumArtist: "Singer Y", genre: "Vals"),
                song(3, artist: "Gamma Sextet", albumArtist: "Singer Z", genre: "Milonga")
            ]

            let url = try TandaSaver.save(songs: tracks, settings: AppSettings())

            XCTAssertTrue(samePath(
                url.deletingLastPathComponent(),
                root.appendingPathComponent("Default/Tandas/VariousOrchestras/VariousSingers")
            ))
            XCTAssertEqual(url.lastPathComponent, "VariousOrchestras_VariousGenres_VariousSingers.json")
        }
    }

    func testSavingTheSameTracksTwiceWithoutTheExistingListNumbersTheSecondFile() throws {
        try withTemporaryAppRoot { _ in
            let tracks = songs(3)

            let first = try TandaSaver.save(songs: tracks, settings: AppSettings())
            let second = try TandaSaver.save(songs: tracks, settings: AppSettings())

            XCTAssertEqual(first.lastPathComponent, "Alpha Trio_Tango_Singer X.json")
            XCTAssertEqual(second.lastPathComponent, "Alpha Trio_Tango_Singer X_2.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        }
    }

    func testFolderFollowsTheConfiguredOrchestraAndSingerSource() throws {
        try withTemporaryAppRoot { root in
            let settings = AppSettings()
            settings.orchestraSource = .grouping
            settings.singerSource = .artist

            let tracks = (1...3).map {
                song(Int64($0), artist: "Singer X", albumArtist: "ignored", grouping: "Alpha Trio")
            }

            let url = try TandaSaver.save(songs: tracks, settings: settings)

            XCTAssertTrue(samePath(
                url.deletingLastPathComponent(),
                root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X")
            ))
        }
    }

    func testSaveReturnsTheURLOfTheFileItWrote() throws {
        try withTemporaryAppRoot { _ in
            let url = try TandaSaver.save(songs: songs(3), settings: AppSettings())

            XCTAssertEqual(url.pathExtension, "json")
            XCTAssertNoThrow(try TandaMetadataExporter.load(from: url))
        }
    }

    func testSuccessfulSavePostsTandaSaved() throws {
        try withTemporaryAppRoot { _ in
            let posted = XCTNSNotificationExpectation(name: AppNotification.tandaSaved)

            try TandaSaver.save(songs: songs(3), settings: AppSettings())

            wait(for: [posted], timeout: 1)
        }
    }

    // MARK: - commaTruncated

    func testCommaTruncatedKeepsOnlyThePartBeforeTheFirstComma() {
        XCTAssertEqual(TandaSaver.commaTruncated("Biagi, Rodolfo"), "Biagi")
        XCTAssertEqual(TandaSaver.commaTruncated("Biagi,Rodolfo"), "Biagi")
        XCTAssertEqual(TandaSaver.commaTruncated("A, B, C"), "A")
        XCTAssertEqual(TandaSaver.commaTruncated("  Biagi  , Rodolfo"), "Biagi")
    }

    func testCommaTruncatedLeavesValuesWithoutACommaUntouched() {
        XCTAssertEqual(TandaSaver.commaTruncated("Biagi"), "Biagi")
        XCTAssertEqual(TandaSaver.commaTruncated(""), "")
        XCTAssertEqual(TandaSaver.commaTruncated(" Biagi "), " Biagi ")
    }
}
