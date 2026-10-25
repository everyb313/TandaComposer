import XCTest
import Foundation

/// Complete versus incomplete matches in "Import Setlist (Pick Tracks)".
///
/// When a line names an orchestra and/or a singer (including "Instrumental"):
/// - candidates that agree with all of it are complete matches, and only
///   those are listed when there are any;
/// - without any, the same-named tracks are still offered, but as incomplete
///   suggestions: flagged, headed "No candidate (...)", never auto-picked.
@MainActor
final class SpecialImportIncompleteMatchTests: XCTestCase {

    // MARK: - Helpers

    private func lib(
        _ id: Int64,
        artist: String? = nil,
        albumArtist: String? = nil,
        fileType: String? = nil,
        duration: Int? = nil,
        year: Int? = nil
    ) -> Song {
        var song = makeSong(
            id: id,
            path: "/Library/\(id)/\(id).flac",
            title: "Poema",
            artist: artist,
            albumArtist: albumArtist,
            year: year,
            duration: duration
        )
        song.fileType = fileType
        song.sampleRate = 44_100
        return song
    }

    private func row(
        _ track: ImportedTrack,
        _ songs: [Song],
        autoPick: Bool = false
    ) throws -> SpecialImportRow {
        let rows = SpecialImportPlanner.makeRows(
            tracks: [track],
            songs: songs,
            orchestraSource: .artist,
            singerSource: .albumArtist,
            autoPickBestFile: autoPick
        )

        return try XCTUnwrap(rows.first)
    }

    private func line(artist: String? = nil, singer: String? = nil) -> ImportedTrack {
        ImportedTrack(sourceIndex: 0, title: "Poema", artist: artist, singer: singer)
    }

    private func ids(_ row: SpecialImportRow) -> [Int64?] {
        row.candidates.map(\.id)
    }

    // MARK: - Complete matches

    func testACandidateThatAgreesWithOrchestraAndSingerIsACompleteMatch() throws {
        let result = try row(
            line(artist: "Alpha Trio", singer: "Singer X"),
            [
                lib(1, artist: "Alpha Trio", albumArtist: "Singer X"),
                lib(2, artist: "Alpha Trio", albumArtist: "Singer Y")
            ]
        )

        XCTAssertEqual(ids(result), [1])
        XCTAssertFalse(result.isIncompleteMatch)
        XCTAssertNil(result.incompleteHeading)
        XCTAssertEqual(result.state, .open, "still a manual choice")
    }

    func testOrchestraNamesAreComparedIgnoringCaseAccentsAndExtraWords() throws {
        let result = try row(
            line(artist: "Calo"),
            [
                lib(1, artist: "Cal\u{00F3}"),
                lib(2, artist: "Orquesta Calo"),
                lib(3, artist: "Beta Band")
            ]
        )

        XCTAssertEqual(ids(result), [1, 2])
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testALineWithoutOrchestraAndSingerNeverProducesIncompleteSuggestions() throws {
        let result = try row(
            line(),
            [lib(1, artist: "Alpha Trio"), lib(2, artist: "Beta Band", albumArtist: "Singer Y")]
        )

        XCTAssertEqual(Set(ids(result).compactMap { $0 }), [1, 2])
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testAnExactPathMatchStaysAutomaticWhateverTheMetadataSays() throws {
        let track = ImportedTrack(
            sourceIndex: 0,
            path: "/Library/1/1.flac",
            title: "Poema",
            artist: "Beta Band",
            singer: "Singer Y"
        )

        let result = try row(track, [lib(1, artist: "Alpha Trio", albumArtist: "Singer X")])

        XCTAssertEqual(result.state, .matched)
        XCTAssertFalse(result.isIncompleteMatch)
        XCTAssertNil(result.incompleteHeading)
    }

    // MARK: - Incomplete suggestions

    func testWithoutACandidateOfTheNamedOrchestraTheOthersAreIncompleteSuggestions() throws {
        let result = try row(
            line(artist: "Alpha Trio"),
            [lib(1, artist: "Beta Band"), lib(2, artist: "Gamma Sextet")]
        )

        XCTAssertEqual(Set(ids(result).compactMap { $0 }), [1, 2])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.incompleteHeading, "No candidate (Orchestra)")
        XCTAssertEqual(result.state, .open)
        XCTAssertNil(result.chosenSong)
    }

    func testWithoutACandidateOfTheNamedSingerTheOthersAreIncompleteSuggestions() throws {
        let result = try row(
            line(singer: "Singer X"),
            [lib(1, albumArtist: "Singer Y")]
        )

        XCTAssertEqual(ids(result), [1])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.incompleteHeading, "No candidate (Singer)")
    }

    func testNamingBothButMatchingOnlyOneEachIsIncomplete() throws {
        let result = try row(
            line(artist: "Alpha Trio", singer: "Singer X"),
            [
                lib(1, artist: "Alpha Trio", albumArtist: "Singer Y"),
                lib(2, artist: "Beta Band", albumArtist: "Singer X")
            ]
        )

        XCTAssertEqual(Set(ids(result).compactMap { $0 }), [1, 2])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.incompleteHeading, "No candidate (Orchestra & Singer)")
    }

    func testAnEmptySingerTagCannotSatisfyANamedSinger() throws {
        let result = try row(line(singer: "Singer X"), [lib(1, albumArtist: nil)])

        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(ids(result), [1])
    }

    func testAnEmptyOrchestraTagCannotSatisfyANamedOrchestra() throws {
        let result = try row(line(artist: "Alpha Trio"), [lib(1, artist: nil)])

        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(ids(result), [1])
    }

    func testIncompleteSuggestionsStayAvailableForManualChoice() throws {
        var result = try row(line(artist: "Alpha Trio"), [lib(1, artist: "Beta Band")])
        let suggestion = try XCTUnwrap(result.candidates.first)

        result.choose(suggestion)

        XCTAssertEqual(result.state, .chosen)
        XCTAssertEqual(result.adoptedSong?.id, 1)
        XCTAssertTrue(result.isIncompleteMatch, "choosing does not turn it into a complete match")
    }

    func testAnIncompleteSuggestionIsNeverAutoPicked() throws {
        let copies = [
            lib(1, artist: "Alpha Trio", albumArtist: "Singer X", fileType: "AIFF", duration: 180, year: 1936),
            lib(2, artist: "Alpha Trio", albumArtist: "Singer X", fileType: "FLAC", duration: 181, year: 1936)
        ]

        let complete = try row(line(artist: "Alpha Trio"), copies, autoPick: true)
        let incomplete = try row(line(artist: "Beta Band"), copies, autoPick: true)

        XCTAssertEqual(complete.state, .autoPicked, "control: the same copies are picked when they match")
        XCTAssertEqual(incomplete.state, .open)
        XCTAssertNil(incomplete.chosenSong)
        XCTAssertEqual(ids(incomplete).count, 2)
        XCTAssertTrue(incomplete.isIncompleteMatch)
    }

    func testALineReadAsArtistDashTitleIsJudgedByTheReadArtist() throws {
        let track = ImportedTrack(sourceIndex: 0, title: "Alpha Trio - Poema")

        let result = try row(track, [lib(1, artist: "Beta Band")])

        XCTAssertEqual(result.track.artist, "Alpha Trio")
        XCTAssertEqual(ids(result), [1])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.incompleteHeading, "No candidate (Orchestra)")
    }

    // MARK: - Instrumental

    func testInstrumentalPrefersInstrumentalCandidatesAndHidesTheRest() throws {
        let result = try row(
            line(singer: "Instrumental"),
            [lib(1, albumArtist: "Singer X"), lib(2, albumArtist: nil), lib(3, albumArtist: "Instr.")]
        )

        XCTAssertEqual(ids(result), [3])
        XCTAssertFalse(result.isIncompleteMatch)
    }

    func testInstrumentalWithOnlyNamedOrEmptySingersGivesIncompleteSuggestions() throws {
        let result = try row(
            line(singer: "Instrumental"),
            [lib(1, albumArtist: "Singer X"), lib(2, albumArtist: nil)]
        )

        XCTAssertEqual(Set(ids(result).compactMap { $0 }), [1, 2])
        XCTAssertTrue(result.isIncompleteMatch)
        XCTAssertEqual(result.incompleteHeading, "No candidate (Singer)")
    }

    // MARK: - Nothing to suggest

    func testNoTitleMatchMeansNoCandidatesAndNoIncompleteFlag() throws {
        let track = ImportedTrack(sourceIndex: 0, title: "Unrelated", artist: "Alpha Trio")

        let result = try row(track, [lib(1, artist: "Alpha Trio")])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.isIncompleteMatch)
        XCTAssertNil(result.incompleteHeading)
    }

    // MARK: - The row itself

    func testTheFlagDefaultsToFalse() {
        let row = SpecialImportRow(track: line(), candidates: [], autoMatched: false, chosenSong: nil)

        XCTAssertFalse(row.isIncompleteMatch)
        XCTAssertNil(row.incompleteHeading)
    }

    func testAnAutoMatchedRowCannotBeIncomplete() {
        let song = lib(1)

        let row = SpecialImportRow(
            track: line(artist: "Alpha Trio"),
            candidates: [],
            autoMatched: true,
            chosenSong: song,
            incompleteMatch: true
        )

        XCTAssertFalse(row.isIncompleteMatch)
        XCTAssertNil(row.incompleteHeading)
    }

    func testTheHeadingNamesTheCriteriaTheLineGives() {
        func heading(artist: String?, singer: String?) -> String? {
            SpecialImportRow(
                track: line(artist: artist, singer: singer),
                candidates: [],
                autoMatched: false,
                chosenSong: nil,
                incompleteMatch: true
            ).incompleteHeading
        }

        XCTAssertEqual(heading(artist: "A", singer: "S"), "No candidate (Orchestra & Singer)")
        XCTAssertEqual(heading(artist: "A", singer: nil), "No candidate (Orchestra)")
        XCTAssertEqual(heading(artist: nil, singer: "S"), "No candidate (Singer)")
        XCTAssertEqual(heading(artist: "", singer: ""), "No candidate")
    }
}
