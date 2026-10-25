import XCTest
import Foundation

/// `SpecialImportPlanner` turns imported tracks into rows for the manual
/// "Import Setlist (Pick Tracks)" window.
///
/// Rules covered here:
/// - exact path (or file hash) match is adopted automatically,
/// - everything else lists the same-named Library tracks and is NEVER
///   preselected, not even when there is only one candidate,
/// - a Library ID in the imported file is not trusted,
/// - candidates are ordered by year and singer hints from the source line,
/// - fallback readings of a line (number prefix, brackets, "A - B" both ways),
/// - "Auto-pick best file" (same recording in several files).
///
/// All names are invented on purpose. Name recognition has no reference data
/// in the test bundle (see `TracklibImportReferenceTests`), so it passes
/// everything through here.
@MainActor
final class SpecialImportPlannerTests: XCTestCase {

    // MARK: - Helpers

    private func lib(
        _ id: Int64,
        title: String? = "Poema",
        artist: String? = nil,
        albumArtist: String? = nil,
        grouping: String? = nil,
        year: Int? = nil,
        duration: Int? = nil,
        fileType: String? = nil,
        sampleRate: Int? = nil,
        filename: String? = nil,
        hash: String? = nil
    ) -> Song {
        var song = makeSong(
            id: id,
            path: "/Library/\(id)/\(filename ?? "\(id).flac")",
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            grouping: grouping,
            year: year,
            duration: duration
        )
        song.fileType = fileType
        song.sampleRate = sampleRate
        song.fileHash = hash
        return song
    }

    private func imported(
        _ index: Int = 0,
        path: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        fileHash: String? = nil,
        libraryID: Int64? = nil,
        year: Int? = nil,
        singer: String? = nil
    ) -> ImportedTrack {
        ImportedTrack(
            sourceIndex: index,
            path: path,
            title: title,
            artist: artist,
            fileHash: fileHash,
            libraryID: libraryID,
            year: year,
            singer: singer
        )
    }

    private func rows(
        _ tracks: [ImportedTrack],
        _ songs: [Song],
        autoPick: Bool = false
    ) -> [SpecialImportRow] {
        SpecialImportPlanner.makeRows(
            tracks: tracks,
            songs: songs,
            orchestraSource: .artist,
            singerSource: .albumArtist,
            autoPickBestFile: autoPick
        )
    }

    private func row(
        _ track: ImportedTrack,
        _ songs: [Song],
        autoPick: Bool = false
    ) throws -> SpecialImportRow {
        try XCTUnwrap(rows([track], songs, autoPick: autoPick).first)
    }

    private func ids(_ songs: [Song]) -> [Int64?] {
        songs.map(\.id)
    }

    // MARK: - makeRows: automatic matches

    func testNoTracksGiveNoRows() {
        XCTAssertTrue(rows([], [lib(1)]).isEmpty)
    }

    func testExactPathIsAdoptedAutomatically() throws {
        let result = try row(
            imported(path: "/Library/1/1.flac", title: "Something else"),
            [lib(1, title: "Poema")]
        )

        XCTAssertEqual(result.state, .matched)
        XCTAssertTrue(result.autoMatched)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.adoptedSong?.id, 1)
    }

    func testExactPathWinsOverASongWithTheSameTitle() throws {
        let result = try row(
            imported(path: "/Library/1/1.flac", title: "Poema"),
            [lib(2, title: "Poema"), lib(1, title: "Other title")]
        )

        XCTAssertEqual(result.state, .matched)
        XCTAssertEqual(result.adoptedSong?.id, 1)
    }

    func testPathsThatDifferOnlyInUnicodeFormAreTheSameFile() throws {
        let decomposed = "/Library/Rodrigue\u{0301}z/Poema.flac"
        let precomposed = "/Library/Rodrigu\u{00E9}z/Poema.flac"
        let song = makeSong(id: 1, path: precomposed, title: "Poema")

        let result = try row(imported(path: decomposed, title: "Poema"), [song])

        XCTAssertEqual(result.state, .matched)
    }

    func testFileHashMatchIsAdoptedAutomatically() throws {
        let result = try row(
            imported(title: "Unrelated", fileHash: "abc123"),
            [lib(1, hash: "abc123"), lib(2, hash: "other")]
        )

        XCTAssertEqual(result.state, .matched)
        XCTAssertEqual(result.adoptedSong?.id, 1)
    }

    func testTheSameHashInTwoFilesStaysAManualChoice() throws {
        let result = try row(
            imported(title: "Poema", fileHash: "abc123"),
            [lib(1, hash: "abc123"), lib(2, hash: "abc123")]
        )

        XCTAssertEqual(result.state, .open)
        XCTAssertFalse(result.autoMatched)
        XCTAssertEqual(ids(result.candidates), [1, 2])
    }

    // MARK: - makeRows: manual rows

    func testSingleSameNamedCandidateIsListedButNotPreselected() throws {
        let result = try row(
            imported(path: "/Elsewhere/Poema.flac", title: "Poema"),
            [lib(1, title: "Poema")]
        )

        XCTAssertEqual(result.state, .open)
        XCTAssertNil(result.chosenSong)
        XCTAssertNil(result.adoptedSong)
        XCTAssertEqual(ids(result.candidates), [1])
    }

    func testEvenAConfidentSingleCandidateIsNotPreselected() throws {
        // Title and orchestra agree: the matcher is "confident", the
        // planner still leaves the decision to the user.
        let result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            [lib(1, title: "Poema", artist: "Alpha Trio")]
        )

        XCTAssertEqual(result.state, .open)
        XCTAssertNil(result.chosenSong)
        XCTAssertEqual(ids(result.candidates), [1])
    }

    func testOnlyCandidatesOfTheNamedOrchestraAreListed() throws {
        let result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            [
                lib(1, title: "Poema", artist: "Beta Band"),
                lib(2, title: "Poema", artist: "Alpha Trio")
            ]
        )

        XCTAssertEqual(ids(result.candidates), [2])
        XCTAssertEqual(result.state, .open)
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testTrackWithoutAnyCandidateIsOpenWithAnEmptyList() throws {
        let track = imported(title: "Unrelated")

        let result = try row(track, [lib(1, title: "Poema")])

        XCTAssertEqual(result.state, .open)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.track, track, "an unmatched line is shown as it was read")
    }

    func testEmptyLibraryLeavesEveryRowOpen() {
        let result = rows(
            [imported(0, title: "A"), imported(1, title: "B")],
            []
        )

        XCTAssertEqual(result.map(\.state), [.open, .open])
    }

    func testRowsKeepSourceOrderAndTrackIdentity() {
        let tracks = [
            imported(0, title: "Zeta"),
            imported(1, path: "/Library/1/1.flac"),
            imported(2, title: "Poema")
        ]

        let result = rows(tracks, [lib(1, title: "Poema")])

        XCTAssertEqual(result.map(\.id), tracks.map(\.id))
        XCTAssertEqual(result.map(\.track.sourceIndex), [0, 1, 2])
        XCTAssertEqual(result.map(\.state), [.open, .matched, .open])
    }

    func testLibraryIDFromTheImportedFileIsNotTrusted() throws {
        // Song IDs are per database: ID 1 in another library is a
        // coincidence, not the same song.
        let result = try row(
            imported(title: "Unrelated", libraryID: 1),
            [lib(1, title: "Poema")]
        )

        XCTAssertEqual(result.state, .open)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertNil(result.adoptedSong)
    }

    // MARK: - makeRows: ordering hints

    func testRecordingYearOrdersTheCandidates() throws {
        let result = try row(
            imported(title: "Poema", year: 1936),
            [
                lib(1, year: 1938),
                lib(2, year: 1937),
                lib(3, year: 1936)
            ]
        )

        XCTAssertEqual(ids(result.candidates), [3, 2, 1], "same year first, one year off second")
    }

    func testYearHintOnlyChangesTheOrderNeverTheContent() throws {
        let result = try row(
            imported(title: "Poema", year: 1936),
            [lib(1, year: 1950), lib(2, year: nil), lib(3, year: 1936)]
        )

        XCTAssertEqual(Set(ids(result.candidates).compactMap { $0 }), [1, 2, 3])
        XCTAssertEqual(result.candidates.first?.id, 3)
    }

    func testOnlyCandidatesOfTheNamedSingerAreListed() throws {
        let result = try row(
            imported(title: "Poema", singer: "Singer X"),
            [
                lib(1, albumArtist: "Singer Y"),
                lib(2, albumArtist: "Singer X")
            ]
        )

        XCTAssertEqual(ids(result.candidates), [2])
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testInstrumentalListsOnlyInstrumentalCandidates() throws {
        // "Instrumental" is a singer category of its own: it matches other
        // instrumental spellings, never an empty or a named singer.
        let result = try row(
            imported(title: "Poema", singer: "Instrumental"),
            [
                lib(1, albumArtist: "Singer X"),
                lib(2, albumArtist: nil),
                lib(3, albumArtist: "Instrumental"),
                lib(4, albumArtist: "Instr.")
            ]
        )

        XCTAssertEqual(ids(result.candidates), [3, 4])
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testInstrumentalWithoutAnyInstrumentalCandidateOffersIncompleteSuggestions() throws {
        let result = try row(
            imported(title: "Poema", singer: "Instrumental"),
            [lib(1, albumArtist: nil), lib(2, albumArtist: "Singer X")]
        )

        XCTAssertEqual(ids(result.candidates), [1, 2])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.state, .open)
    }

    // MARK: - makeRows: fallback readings of a line

    func testArtistDashTitleReadAsOneTitleIsFoundAndShownCorrected() throws {
        let result = try row(
            imported(title: "Alpha Trio - Poema"),
            [lib(1, title: "Poema", artist: "Alpha Trio")]
        )

        XCTAssertEqual(ids(result.candidates), [1])
        XCTAssertEqual(result.track.title, "Poema")
        XCTAssertEqual(result.track.artist, "Alpha Trio")
        XCTAssertEqual(result.sourceTitle, "Alpha Trio \u{2013} Poema")
        XCTAssertEqual(result.state, .open)
    }

    func testTitleDashArtistIsFoundAsWell() throws {
        let result = try row(
            imported(title: "Poema - Alpha Trio"),
            [lib(1, title: "Poema", artist: "Alpha Trio")]
        )

        XCTAssertEqual(ids(result.candidates), [1])
        XCTAssertEqual(result.track.title, "Poema")
        XCTAssertEqual(result.track.artist, "Alpha Trio")
    }

    func testNumberedLineWithArtistAndTitleIsFound() throws {
        let result = try row(
            imported(title: "01 - Alpha Trio - Poema"),
            [lib(1, title: "Poema", artist: "Alpha Trio")]
        )

        XCTAssertEqual(ids(result.candidates), [1])
        XCTAssertEqual(result.track.title, "Poema")
        XCTAssertEqual(result.track.artist, "Alpha Trio")
    }

    func testLeadingTrackNumberIsIgnored() throws {
        for line in ["01 - Poema", "7. Poema", "12) Poema"] {
            let result = try row(imported(title: line), [lib(1, title: "Poema")])

            XCTAssertEqual(ids(result.candidates), [1], line)
        }
    }

    func testTrailingBracketsAreIgnored() throws {
        let line = "Poema (1936) (Gesang: Singer X)"

        let result = try row(imported(title: line), [lib(1, title: "Poema")])

        XCTAssertEqual(ids(result.candidates), [1])
    }

    func testSquareBracketsAreIgnoredToo() throws {
        let result = try row(imported(title: "Poema [remastered]"), [lib(1, title: "Poema")])

        XCTAssertEqual(ids(result.candidates), [1])
    }

    func testFileNameWithoutSuffixIsComparedAgainstTheTitleText() throws {
        let song = lib(1, title: "Different title", artist: "Alpha Trio", filename: "Alpha Trio - Poema.flac")

        for line in ["Alpha Trio - Poema", "alpha trio - poema"] {
            let result = try row(imported(title: line), [song])

            XCTAssertEqual(ids(result.candidates), [1], line)
            XCTAssertEqual(result.track.title, line, "found by file name: the line stays as written")
        }
    }

    func testFallbackDoesNotInventCandidates() throws {
        let result = try row(
            imported(title: "Alpha Trio - Unrelated"),
            [lib(1, title: "Poema", artist: "Alpha Trio")]
        )

        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testCandidatesAreNeverListedTwice() throws {
        // Found by file name AND by title.
        let song = lib(1, title: "Poema", filename: "Poema.flac")

        let result = try row(imported(title: "01 - Poema"), [song])

        XCTAssertEqual(ids(result.candidates), [1])
    }

    // MARK: - makeRows: auto-pick best file

    private func twoCopies(
        secondType: String = "FLAC",
        secondYear: Int? = 1936
    ) -> [Song] {
        [
            lib(1, artist: "Alpha Trio", albumArtist: "Singer X", year: 1936, duration: 180, fileType: "AIFF", sampleRate: 44_100),
            lib(2, artist: "Alpha Trio", albumArtist: "Singer X", year: secondYear, duration: 181, fileType: secondType, sampleRate: 44_100)
        ]
    }

    func testAutoPickSuggestsTheBestFileOfOneRecording() throws {
        let result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            twoCopies(),
            autoPick: true
        )

        XCTAssertEqual(result.state, .autoPicked)
        XCTAssertEqual(result.chosenSong?.id, 2, "FLAC beats AIFF")
        XCTAssertEqual(ids(result.candidates).count, 2, "all candidates stay listed")
    }

    func testWithoutAutoPickNothingIsSuggested() throws {
        let result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            twoCopies(),
            autoPick: false
        )

        XCTAssertEqual(result.state, .open)
        XCTAssertNil(result.chosenSong)
    }

    func testAutoPickIsSkippedWhenTheYearsDiffer() throws {
        let result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            twoCopies(secondYear: 1950),
            autoPick: true
        )

        XCTAssertEqual(result.state, .open)
    }

    func testAutoPickNeverOverridesAnExactMatch() throws {
        var songs = twoCopies()
        songs[0].fileHash = "same"

        let result = try row(
            imported(title: "Poema", fileHash: "same"),
            songs,
            autoPick: true
        )

        XCTAssertEqual(result.state, .matched)
        XCTAssertEqual(result.adoptedSong?.id, 1)
    }

    func testAutoPickedSuggestionCanBeRemovedAgain() throws {
        var result = try row(
            imported(title: "Poema", artist: "Alpha Trio"),
            twoCopies(),
            autoPick: true
        )

        result.clearChoice()

        XCTAssertEqual(result.state, .open)
    }

    // MARK: - bestFile

    private func rec(
        _ id: Int64,
        _ fileType: String?,
        _ rate: Int? = 44_100,
        title: String? = "Poema",
        artist: String? = "Alpha Trio",
        albumArtist: String? = "Singer X",
        grouping: String? = nil,
        duration: Int? = 180,
        year: Int? = 1936
    ) -> Song {
        lib(
            id,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            grouping: grouping,
            year: year,
            duration: duration,
            fileType: fileType,
            sampleRate: rate
        )
    }

    private func best(
        _ songs: [Song],
        orchestra: TagSource = .artist,
        singer: TagSource = .albumArtist
    ) -> Int64? {
        SpecialImportPlanner.bestFile(
            among: songs,
            orchestraSource: orchestra,
            singerSource: singer
        )?.id
    }

    func testFlacBeatsAiffAndOtherFormats() {
        XCTAssertEqual(best([rec(1, "MP3"), rec(2, "AIFF", 96_000), rec(3, "FLAC", 44_100)]), 3)
    }

    func testHigherSampleRateWinsAmongFlacFiles() {
        XCTAssertEqual(best([rec(1, "FLAC", 44_100), rec(2, "FLAC", 96_000), rec(3, "FLAC", 48_000)]), 2)
    }

    func testAiffPreferenceIs96Then48Then44ThenOther() {
        XCTAssertEqual(best([rec(1, "AIFF", 22_050), rec(2, "AIFF", 44_100)]), 2)
        XCTAssertEqual(best([rec(1, "AIFF", 44_100), rec(2, "AIFF", 48_000)]), 2)
        XCTAssertEqual(best([rec(1, "AIFF", 48_000), rec(2, "AIFF", 96_000)]), 2)
        XCTAssertEqual(best([rec(1, "AIFF", 96_000), rec(2, "AIFF", 44_100), rec(3, "AIFF", 48_000)]), 1)
    }

    func testAifAndLowercaseTypesAreRecognized() {
        XCTAssertEqual(best([rec(1, "MP3"), rec(2, "aif", 44_100)]), 2)
        XCTAssertEqual(best([rec(1, "mp3"), rec(2, "flac", 44_100)]), 2)
    }

    func testAnyAiffBeatsOtherFormats() {
        XCTAssertEqual(best([rec(1, "MP3"), rec(2, "AIFF", 22_050)]), 2)
        XCTAssertEqual(best([rec(1, "M4A"), rec(2, "AIFF", nil)]), 2)
    }

    func testTwoEquallyGoodFilesGiveNoSuggestion() {
        XCTAssertNil(best([rec(1, "FLAC", 44_100), rec(2, "FLAC", 44_100)]))
        XCTAssertNil(best([rec(1, "AIFF", 48_000), rec(2, "AIFF", 48_000)]))
        XCTAssertNil(best([rec(1, "MP3"), rec(2, "M4A")]))
        XCTAssertNil(best([rec(1, nil), rec(2, nil)]))
    }

    func testTiedLeadersGiveNoSuggestionEvenWithAWorseThirdFile() {
        XCTAssertNil(best([rec(1, "FLAC", 96_000), rec(2, "FLAC", 96_000), rec(3, "MP3")]))
    }

    func testNeedsAtLeastTwoCandidates() {
        XCTAssertNil(best([]))
        XCTAssertNil(best([rec(1, "FLAC")]))
    }

    func testDifferentTitlesAreDifferentRecordings() {
        XCTAssertNil(best([rec(1, "FLAC"), rec(2, "AIFF", title: "Other")]))
        XCTAssertNil(best([rec(1, "FLAC"), rec(2, "AIFF", title: nil)]))
    }

    func testCaseAndAccentsDoNotMakeADifferentRecording() {
        XCTAssertEqual(
            best([
                rec(1, "AIFF", title: "Poema", artist: "Cal\u{00F3}"),
                rec(2, "FLAC", title: "POEMA", artist: "calo")
            ]),
            2
        )
    }

    func testDifferentOrchestraIsADifferentRecording() {
        XCTAssertNil(best([rec(1, "FLAC"), rec(2, "AIFF", artist: "Beta Band")]))
    }

    func testDifferentSingerIsADifferentRecording() {
        XCTAssertNil(best([rec(1, "FLAC"), rec(2, "AIFF", albumArtist: "Singer Y")]))
        XCTAssertNil(best([rec(1, "FLAC"), rec(2, "AIFF", albumArtist: nil)]))
    }

    func testDifferentInstrumentalSpellingsAreTheSameRecording() {
        XCTAssertEqual(best([rec(1, "AIFF", albumArtist: "Instrumental"), rec(2, "FLAC", albumArtist: "instr.")]), 2)
        XCTAssertEqual(best([rec(1, "AIFF", albumArtist: "Inst"), rec(2, "FLAC", albumArtist: "Instrumentale")]), 2)
    }

    func testInstrumentalIsNotTheSameRecordingAsOneWithoutASinger() {
        XCTAssertNil(best([rec(1, "AIFF", albumArtist: "Instrumental"), rec(2, "FLAC", albumArtist: nil)]))
        XCTAssertNil(best([rec(1, "AIFF", albumArtist: "instr."), rec(2, "FLAC", albumArtist: "")]))
    }

    func testInstrumentalIsNotTheSameAsANamedSinger() {
        XCTAssertNil(best([rec(1, "AIFF", albumArtist: "Instrumental"), rec(2, "FLAC", albumArtist: "Singer X")]))
    }

    func testLengthsMayDifferByAtMostElevenSeconds() {
        XCTAssertEqual(best([rec(1, "AIFF", duration: 180), rec(2, "FLAC", duration: 191)]), 2)
        XCTAssertNil(best([rec(1, "AIFF", duration: 180), rec(2, "FLAC", duration: 192)]))
    }

    func testTheSpreadIsMeasuredAcrossAllCopies() {
        XCTAssertNil(best([
            rec(1, "AIFF", duration: 180),
            rec(2, "FLAC", duration: 186),
            rec(3, "MP3", duration: 192)
        ]))
    }

    func testEveryCopyNeedsALength() {
        XCTAssertNil(best([rec(1, "AIFF", duration: nil), rec(2, "FLAC", duration: 180)]))
        XCTAssertNil(best([rec(1, "AIFF", duration: nil), rec(2, "FLAC", duration: nil)]))
    }

    func testDifferentYearsAreDifferentRecordings() {
        XCTAssertNil(best([rec(1, "AIFF", year: 1936), rec(2, "FLAC", year: 1937)]))
    }

    func testAMissingYearSaysNothing() {
        XCTAssertEqual(best([rec(1, "AIFF", year: 1936), rec(2, "FLAC", year: nil)]), 2)
        XCTAssertEqual(best([rec(1, "AIFF", year: nil), rec(2, "FLAC", year: nil)]), 2)
    }

    func testOneDifferingCopyAmongThreeSpoilsTheSuggestion() {
        XCTAssertNil(best([
            rec(1, "AIFF"),
            rec(2, "FLAC"),
            rec(3, "MP3", title: "Other")
        ]))
    }

    func testOrchestraAndSingerFollowTheConfiguredTagSources() {
        // Orchestra in Grouping, singer in Artist: Artist now holds the singer.
        let first = rec(1, "AIFF", artist: "Singer X", albumArtist: "ignored A", grouping: "Alpha Trio")
        let second = rec(2, "FLAC", artist: "Singer X", albumArtist: "ignored B", grouping: "Alpha Trio")

        XCTAssertEqual(best([first, second], orchestra: .grouping, singer: .artist), 2)
        XCTAssertNil(
            best([first, second], orchestra: .albumArtist, singer: .artist),
            "AlbumArtist differs, so with it as the orchestra these are different recordings"
        )
    }

    // MARK: - singerKey

    func testSingerKeyOfNoSingerIsNil() {
        XCTAssertNil(SpecialImportPlanner.singerKey(nil))
        XCTAssertNil(SpecialImportPlanner.singerKey(""))
        XCTAssertNil(SpecialImportPlanner.singerKey("   "))
    }

    func testSingerKeyOfInstrumentalMarkersIsTheCanonicalWord() {
        for marker in ["Instrumental", "INSTRUMENTAL", "instr.", "Instr", "inst", "Inst.", "Instrumentale", "instrumentales", "  Instrumental  "] {
            XCTAssertEqual(SpecialImportPlanner.singerKey(marker), "instrumental", marker)
        }
    }

    func testSingerKeyIsNormalized() {
        XCTAssertEqual(SpecialImportPlanner.singerKey("Singer X"), "singer x")
        XCTAssertEqual(SpecialImportPlanner.singerKey("  Cal\u{00F3}   Jr "), "calo jr")
    }

    func testSingerKeyKeepsNamesThatMerelyContainAMarker() {
        XCTAssertEqual(SpecialImportPlanner.singerKey("Instrumental Version"), "instrumental version")
        XCTAssertEqual(SpecialImportPlanner.singerKey("Inst Quartet"), "inst quartet")
    }
}
