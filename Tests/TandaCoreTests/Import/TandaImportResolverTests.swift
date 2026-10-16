import XCTest
import Foundation

/// Name recognition has no reference data in the test bundle (see
/// `LibraryTrackMatcherTests`), so these tests use invented names and
/// exercise the resolving rules and the status logic.
@MainActor
final class TandaImportResolverTests: XCTestCase {

    private let emDash = "\u{2014}"

    // MARK: - Helpers

    private func librarySong(
        _ id: Int64,
        title: String? = nil,
        artist: String? = "Alpha Trio",
        albumArtist: String? = nil,
        fileType: String? = nil,
        sampleRate: Int? = nil,
        duration: Int? = nil,
        year: Int? = nil
    ) -> Song {
        var song = makeSong(
            id: id,
            path: "/Music/\(id).flac",
            title: title ?? "T\(id)",
            artist: artist,
            albumArtist: albumArtist,
            year: year,
            duration: duration
        )
        song.fileType = fileType
        song.sampleRate = sampleRate
        return song
    }

    private func library(_ count: Int) -> [Song] {
        (1...count).map { librarySong(Int64($0)) }
    }

    /// Tracks that point at the library songs by exact path.
    private func pathTracks(_ songs: [Song], startingAt start: Int = 0) -> [ImportedTrack] {
        songs.enumerated().map { offset, song in
            ImportedTrack(sourceIndex: start + offset, path: song.path)
        }
    }

    private func tanda(_ name: String = "Set", tracks: [ImportedTrack]) -> SharedTanda {
        SharedTanda(folder: "", subfolder: "", fileName: name, name: name, comment: nil, tracks: tracks)
    }

    private func evaluate(
        _ tandas: [SharedTanda],
        library: [Song],
        autoPick: Bool = false,
        missing: Set<Int64> = [],
        existing: [ExistingTanda] = []
    ) -> [TandaImportEntry] {
        TandaImportResolver.evaluate(
            tandas,
            library: library,
            orchestraSource: .artist,
            singerSource: .albumArtist,
            autoPickBestFile: autoPick,
            missingSongIDs: missing,
            existing: existing
        )
    }

    private func evaluateOne(
        tracks: [ImportedTrack],
        library: [Song],
        autoPick: Bool = false,
        missing: Set<Int64> = [],
        existing: [ExistingTanda] = []
    ) throws -> TandaImportEntry {
        let entries = evaluate([tanda(tracks: tracks)], library: library, autoPick: autoPick, missing: missing, existing: existing)
        return try XCTUnwrap(entries.first)
    }

    /// Library of three songs plus a track list: the given track at position 3.
    private func entry(forThirdTrack track: ImportedTrack, extra: [Song] = []) throws -> TandaImportEntry {
        let songs = library(2) + extra
        let tracks = pathTracks(Array(songs.prefix(2))) + [track]
        return try evaluateOne(tracks: tracks, library: songs)
    }

    // MARK: - Ready

    func testThreeExactPathsAreReady() throws {
        let songs = library(3)

        let result = try evaluateOne(tracks: pathTracks(songs), library: songs)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.songs.map(\.id), [1, 2, 3])
        XCTAssertEqual(result.lines.map(\.number), [1, 2, 3])
        XCTAssertEqual(result.lines.map(\.note), ["exact path", "exact path", "exact path"])
    }

    func testEntryKeepsTheSharedTandaAndUsesItsID() throws {
        let songs = library(3)
        let shared = tanda("Di Sarli 1", tracks: pathTracks(songs))

        let result = try XCTUnwrap(evaluate([shared], library: songs).first)

        XCTAssertEqual(result.id, shared.id)
        XCTAssertEqual(result.shared.name, "Di Sarli 1")
        XCTAssertNil(result.location)
    }

    func testNoTandasGiveNoEntries() {
        XCTAssertTrue(evaluate([], library: library(3)).isEmpty)
    }

    func testSeveralTandasAreSlicedCorrectlyFromOneMatchingRun() throws {
        let songs = library(7)
        let first = tanda("First", tracks: pathTracks(Array(songs[0..<3])))
        let second = tanda("Second", tracks: pathTracks(Array(songs[3..<7])))

        let entries = evaluate([first, second], library: songs)

        XCTAssertEqual(entries.map(\.shared.name), ["First", "Second"])
        XCTAssertEqual(entries[0].songs.map(\.id), [1, 2, 3])
        XCTAssertEqual(entries[1].songs.map(\.id), [4, 5, 6, 7])
        XCTAssertEqual(entries.map(\.status), [.ready, .ready])
    }

    // MARK: - Track count

    func testATandaNeedsThreeToEightTracks() throws {
        let songs = library(9)

        for count in 3...8 {
            let result = try evaluateOne(tracks: pathTracks(Array(songs.prefix(count))), library: songs)
            XCTAssertEqual(result.status, .ready, "\(count) tracks")
        }

        let two = try evaluateOne(tracks: pathTracks(Array(songs.prefix(2))), library: songs)
        XCTAssertEqual(two.status, .notPossible("2 tracks \(emDash) a Tanda has 3 to 8"))

        let nine = try evaluateOne(tracks: pathTracks(songs), library: songs)
        XCTAssertEqual(nine.status, .notPossible("9 tracks \(emDash) a Tanda has 3 to 8"))
    }

    func testTheCountRuleComesBeforeEverythingElse() throws {
        let unknown = ImportedTrack(sourceIndex: 0, title: "Unknown", artist: "Nobody")

        let result = try evaluateOne(tracks: [unknown, unknown], library: library(3))

        XCTAssertEqual(result.status, .notPossible("2 tracks \(emDash) a Tanda has 3 to 8"))
    }

    // MARK: - Unresolved lines

    func testATrackThatIsNotInTheLibraryNeedsHelp() throws {
        let unknown = ImportedTrack(sourceIndex: 2, title: "Unknown Tune", artist: "Nobody")

        let result = try entry(forThirdTrack: unknown)

        XCTAssertEqual(result.status, .needsHelp("Track 3: not in your TrackLibrary"))
        XCTAssertNil(result.lines[2].song)
        XCTAssertEqual(result.songs.count, 2)
    }

    func testSeveralOpenLinesReportTheFirstAndTheCount() throws {
        let songs = library(3)
        let tracks = [
            ImportedTrack(sourceIndex: 0, path: songs[0].path),
            ImportedTrack(sourceIndex: 1, title: "Unknown One", artist: "Nobody"),
            ImportedTrack(sourceIndex: 2, title: "Unknown Two", artist: "Nobody")
        ]

        let result = try evaluateOne(tracks: tracks, library: songs)

        XCTAssertEqual(result.status, .needsHelp("Track 2: not in your TrackLibrary (+1 more)"))
    }

    // MARK: - Only match

    func testASingleCandidateWithTheSameTitleAndOrchestraIsTaken() throws {
        let songs = library(3)
        let tracks = songs.enumerated().map { offset, song in
            ImportedTrack(sourceIndex: offset, title: song.title?.lowercased(), artist: "ALPHA TRIO")
        }

        let result = try evaluateOne(tracks: tracks, library: songs)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.lines.map(\.note), ["only match", "only match", "only match"])
        XCTAssertEqual(result.songs.map(\.id), [1, 2, 3])
    }

    func testAMissingOrchestraMakesTheSingleCandidateDisagree() throws {
        let track = ImportedTrack(sourceIndex: 2, title: "T3")

        let result = try entry(forThirdTrack: track, extra: [librarySong(3)])

        XCTAssertEqual(
            result.status,
            .needsHelp("Track 3: the only match differs in title, orchestra or singer")
        )
        XCTAssertEqual(result.lines[2].candidates.map(\.id), [3], "the candidate is still offered")
    }

    func testADifferentOrchestraMakesTheSingleCandidateDisagree() throws {
        let track = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Beta Band")

        let result = try entry(forThirdTrack: track, extra: [librarySong(3)])

        XCTAssertEqual(
            result.status,
            .needsHelp("Track 3: the only match differs in title, orchestra or singer")
        )
    }

    func testOrchestraNamesMatchWhenOneContainsAllWordsOfTheOther() throws {
        let song = librarySong(3, artist: "Alpha Trio y su Orquesta")
        let track = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio")

        let result = try entry(forThirdTrack: track, extra: [song])

        XCTAssertEqual(result.lines[2].song?.id, 3)
        XCTAssertEqual(result.lines[2].note, "only match")
    }

    func testANamedSingerHasToAgree() throws {
        let song = librarySong(3, albumArtist: "Singer B")

        let wrong = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio", singer: "Singer A")
        XCTAssertNil(try entry(forThirdTrack: wrong, extra: [song]).lines[2].song)

        let right = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio", singer: "singer b")
        XCTAssertEqual(try entry(forThirdTrack: right, extra: [song]).lines[2].song?.id, 3)
    }

    func testNoSingerOnTheTrackMeansTheSingerIsNotChecked() throws {
        let song = librarySong(3, albumArtist: "Singer B")

        let none = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio")
        XCTAssertEqual(try entry(forThirdTrack: none, extra: [song]).lines[2].song?.id, 3)

        let empty = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio", singer: "")
        XCTAssertEqual(try entry(forThirdTrack: empty, extra: [song]).lines[2].song?.id, 3)
    }

    func testInstrumentalOnlyAgreesWithASongWithoutSinger() throws {
        let withoutSinger = librarySong(3, albumArtist: nil)
        let track = ImportedTrack(sourceIndex: 2, title: "T3", artist: "Alpha Trio", singer: "Instrumental")
        XCTAssertEqual(try entry(forThirdTrack: track, extra: [withoutSinger]).lines[2].song?.id, 3)

        let withSinger = librarySong(3, albumArtist: "Singer B")
        XCTAssertNil(try entry(forThirdTrack: track, extra: [withSinger]).lines[2].song)
    }

    // MARK: - Several candidates

    private func twoFiles(
        first: (String?, Int?, Int?) = ("FLAC", 44_100, 200),
        second: (String?, Int?, Int?) = ("MP3", 44_100, 201),
        years: (Int?, Int?) = (nil, nil)
    ) -> [Song] {
        [
            librarySong(3, title: "Poema", fileType: first.0, sampleRate: first.1, duration: first.2, year: years.0),
            librarySong(4, title: "Poema", fileType: second.0, sampleRate: second.1, duration: second.2, year: years.1)
        ]
    }

    private func entryWithTwoFiles(_ files: [Song], autoPick: Bool) throws -> TandaImportEntry {
        let base = library(2)
        let tracks = pathTracks(base) + [ImportedTrack(sourceIndex: 2, title: "Poema", artist: "Alpha Trio")]
        return try evaluateOne(tracks: tracks, library: base + files, autoPick: autoPick)
    }

    func testSeveralCandidatesNeedHelpWithoutAutoPick() throws {
        let result = try entryWithTwoFiles(twoFiles(), autoPick: false)

        XCTAssertEqual(result.status, .needsHelp("Track 3: 2 different candidates"))
        XCTAssertEqual(Set(result.lines[2].candidates.compactMap(\.id)), [3, 4])
    }

    func testAutoPickTakesTheFLACOverAnMP3() throws {
        let result = try entryWithTwoFiles(twoFiles(), autoPick: true)

        XCTAssertEqual(result.lines[2].song?.id, 3)
        XCTAssertEqual(result.lines[2].note, "best of several files")
        XCTAssertEqual(result.status, .ready)
    }

    func testAutoPickPrefersTheHigherSampleRateAmongFLACFiles() throws {
        let files = twoFiles(first: ("FLAC", 44_100, 200), second: ("FLAC", 96_000, 200))

        let result = try entryWithTwoFiles(files, autoPick: true)

        XCTAssertEqual(result.lines[2].song?.id, 4)
    }

    func testAutoPickGivesUpOnATie() throws {
        let files = twoFiles(first: ("FLAC", 44_100, 200), second: ("FLAC", 44_100, 200))

        let result = try entryWithTwoFiles(files, autoPick: true)

        XCTAssertNil(result.lines[2].song)
        XCTAssertEqual(result.status, .needsHelp("Track 3: 2 different candidates"))
    }

    func testAutoPickGivesUpWhenTheLengthsDifferTooMuch() throws {
        let tooFar = try entryWithTwoFiles(twoFiles(first: ("FLAC", 44_100, 200), second: ("MP3", 0, 212)), autoPick: true)
        XCTAssertNil(tooFar.lines[2].song, "12 seconds apart")

        let close = try entryWithTwoFiles(twoFiles(first: ("FLAC", 44_100, 200), second: ("MP3", 0, 211)), autoPick: true)
        XCTAssertEqual(close.lines[2].song?.id, 3, "11 seconds apart is still the same recording")
    }

    func testAutoPickGivesUpWhenALengthIsMissing() throws {
        let files = twoFiles(first: ("FLAC", 44_100, 200), second: ("MP3", 44_100, nil))

        XCTAssertNil(try entryWithTwoFiles(files, autoPick: true).lines[2].song)
    }

    func testAutoPickGivesUpWhenTheYearsDiffer() throws {
        let files = twoFiles(years: (1940, 1941))

        XCTAssertNil(try entryWithTwoFiles(files, autoPick: true).lines[2].song)
    }

    func testAutoPickGivesUpWhenTheSingersDiffer() throws {
        var files = twoFiles()
        files[0].albumArtist = "Singer A"
        files[1].albumArtist = "Singer B"

        XCTAssertNil(try entryWithTwoFiles(files, autoPick: true).lines[2].song)
    }

    // MARK: - Missing files

    func testAFileMissingOnDiskMakesTheTandaNotPossible() throws {
        let songs = library(3)

        let result = try evaluateOne(tracks: pathTracks(songs), library: songs, missing: [2])

        XCTAssertEqual(result.status, .notPossible("File missing on disk: T2"))
    }

    func testMissingFilesAreReportedByFileNameWhenThereIsNoTitle() throws {
        var songs = library(3)
        songs[1].title = nil

        let result = try evaluateOne(tracks: pathTracks(songs), library: songs, missing: [2])

        XCTAssertEqual(result.status, .notPossible("File missing on disk: 2.flac"))
    }

    func testUnresolvedLinesAreReportedBeforeMissingFiles() throws {
        let unknown = ImportedTrack(sourceIndex: 2, title: "Unknown Tune", artist: "Nobody")

        let songs = library(2)
        let result = try evaluateOne(tracks: pathTracks(songs) + [unknown], library: songs, missing: [1])

        XCTAssertEqual(result.status, .needsHelp("Track 3: not in your TrackLibrary"))
    }

    // MARK: - Existing Tandas

    private func existing(_ name: String, _ songs: [Song]) -> ExistingTanda {
        ExistingTanda(name: name, paths: Set(songs.map(\.normalizedPath)))
    }

    func testATandaWithTheSameFilesAlreadyExists() throws {
        let songs = library(3)
        let known = existing("Old Set", Array(songs.reversed()))

        let result = try evaluateOne(tracks: pathTracks(songs), library: songs, existing: [known])

        XCTAssertEqual(result.status, .exists("Old Set"), "order does not matter")
    }

    func testOnlyAnIdenticalSetOfFilesCountsAsExisting() throws {
        let songs = library(4)
        let tracks = pathTracks(Array(songs.prefix(3)))

        let subset = existing("Two of them", Array(songs.prefix(2)))
        let superset = existing("All four", songs)

        let result = try evaluateOne(tracks: tracks, library: songs, existing: [subset, superset])

        XCTAssertEqual(result.status, .ready)
    }

    func testTheFirstExistingTandaWins() throws {
        let songs = library(3)

        let result = try evaluateOne(
            tracks: pathTracks(songs),
            library: songs,
            existing: [existing("First", songs), existing("Second", songs)]
        )

        XCTAssertEqual(result.status, .exists("First"))
    }

    // MARK: - Line text

    func testLineTextPrefersTheOriginalSourceText() throws {
        let songs = library(3)
        var tracks = pathTracks(songs)
        tracks[0] = ImportedTrack(sourceIndex: 0, path: songs[0].path, title: "A", artist: "B", sourceDisplayName: "Alpha Trio - Song One.flac")
        tracks[1] = ImportedTrack(sourceIndex: 1, path: songs[1].path, title: "Song Two", artist: "Alpha Trio")
        tracks[2] = ImportedTrack(sourceIndex: 2, path: songs[2].path, title: "Only Title")

        let result = try evaluateOne(tracks: tracks, library: songs)

        XCTAssertEqual(result.lines.map(\.text), ["Alpha Trio - Song One.flac", "Alpha Trio - Song Two", "Only Title"])
    }

    // MARK: - refreshed

    private func entryWithOneOpenLine() throws -> (entry: TandaImportEntry, songs: [Song]) {
        let songs = library(3)
        let unknown = ImportedTrack(sourceIndex: 2, title: "Unknown Tune", artist: "Nobody")
        let entry = try evaluateOne(tracks: pathTracks(Array(songs.prefix(2))) + [unknown], library: songs)
        XCTAssertEqual(entry.status, .needsHelp("Track 3: not in your TrackLibrary"))
        return (entry, songs)
    }

    func testRefreshedAfterTheUserChoseASong() throws {
        var (entry, songs) = try entryWithOneOpenLine()
        entry.lines[2].song = songs[2]
        entry.location = "somewhere"

        let result = TandaImportResolver.refreshed(entry, missingSongIDs: [], existing: [])

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.songs.map(\.id), [1, 2, 3])
        XCTAssertNil(result.location, "the target folder has to be chosen again")
    }

    func testRefreshedChecksMissingFilesAndExistingTandasAgain() throws {
        var (entry, songs) = try entryWithOneOpenLine()
        entry.lines[2].song = songs[2]

        XCTAssertEqual(
            TandaImportResolver.refreshed(entry, missingSongIDs: [3], existing: []).status,
            .notPossible("File missing on disk: T3")
        )
        XCTAssertEqual(
            TandaImportResolver.refreshed(entry, missingSongIDs: [], existing: [existing("Known", songs)]).status,
            .exists("Known")
        )
    }

    func testRefreshedWithoutAChoiceStaysOpen() throws {
        let (entry, _) = try entryWithOneOpenLine()

        let result = TandaImportResolver.refreshed(entry, missingSongIDs: [], existing: [])

        XCTAssertEqual(result.status, .needsHelp("Track 3: not in your TrackLibrary"))
    }

    // MARK: - loadExisting

    private func writeTandaFile(_ fileName: String, in subfolder: String? = nil, songs: [Song], tandaName: String = "Ignored") throws {
        var folder = AppPaths.tandasFolder
        if let subfolder {
            folder = folder.appendingPathComponent(subfolder, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: tandaName,
            to: folder.appendingPathComponent(fileName).appendingPathExtension("json")
        )
    }

    func testLoadExistingOfAMissingFolderIsEmpty() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertTrue(TandaImportResolver.loadExisting().isEmpty)
        }
    }

    func testLoadExistingReadsNamesFromFileNamesAndPathsFromTheSongs() throws {
        try withTemporaryAppRoot { _ in
            let songs = library(3)
            try writeTandaFile("File Name", songs: songs, tandaName: "Different Name")
            try writeTandaFile("Nested", in: "Di Sarli/1940s", songs: Array(songs.prefix(2)))

            let result = TandaImportResolver.loadExisting().sorted { $0.name < $1.name }

            XCTAssertEqual(result.map(\.name), ["File Name", "Nested"])
            XCTAssertEqual(result[0].paths, Set(songs.map(\.normalizedPath)))
            XCTAssertEqual(result[1].paths, Set(songs.prefix(2).map(\.normalizedPath)))
        }
    }

    func testLoadExistingSkipsBrokenAndForeignFiles() throws {
        try withTemporaryAppRoot { _ in
            try writeTandaFile("Good", songs: library(3))
            try "garbage".write(to: AppPaths.tandasFolder.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
            try "notes".write(to: AppPaths.tandasFolder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

            XCTAssertEqual(TandaImportResolver.loadExisting().map(\.name), ["Good"])
        }
    }

    func testLoadExistingFeedsTheStatusCheck() throws {
        try withTemporaryAppRoot { _ in
            let songs = library(3)
            try writeTandaFile("Already There", songs: songs)

            let result = try evaluateOne(
                tracks: pathTracks(songs),
                library: songs,
                existing: TandaImportResolver.loadExisting()
            )

            XCTAssertEqual(result.status, .exists("Already There"))
        }
    }
}
