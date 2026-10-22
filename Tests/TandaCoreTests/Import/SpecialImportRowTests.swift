import XCTest
import Foundation

/// The decisions a user can make on one row of "Import Setlist (Pick Tracks)":
/// choose, clear, skip, and what each state contributes to the new Setlist.
@MainActor
final class SpecialImportRowTests: XCTestCase {

    private func song(_ id: Int64, title: String = "Poema") -> Song {
        makeSong(id: id, path: "/Library/\(id).flac", title: title)
    }

    private func track(
        title: String? = "Poema",
        artist: String? = nil,
        displayName: String? = nil,
        filename: String? = nil
    ) -> ImportedTrack {
        ImportedTrack(
            sourceIndex: 0,
            filename: filename,
            title: title,
            artist: artist,
            sourceDisplayName: displayName
        )
    }

    private func openRow(candidates: [Song] = []) -> SpecialImportRow {
        SpecialImportRow(
            track: track(),
            candidates: candidates,
            autoMatched: false,
            chosenSong: nil
        )
    }

    // MARK: - States

    func testRowWithoutChoiceIsOpenAndAdoptsNothing() {
        let row = openRow(candidates: [song(1)])

        XCTAssertEqual(row.state, .open)
        XCTAssertNil(row.adoptedSong)
    }

    func testChoosingASongMakesTheRowChosen() {
        var row = openRow(candidates: [song(1), song(2)])

        row.choose(song(2))

        XCTAssertEqual(row.state, .chosen)
        XCTAssertEqual(row.adoptedSong?.id, 2)
    }

    func testAutoMatchedRowIsMatched() {
        let row = SpecialImportRow(
            track: track(),
            candidates: [],
            autoMatched: true,
            chosenSong: song(7)
        )

        XCTAssertEqual(row.state, .matched)
        XCTAssertEqual(row.adoptedSong?.id, 7)
        XCTAssertTrue(row.candidates.isEmpty)
    }

    func testAutoPickedRowIsMarkedAsSuggestion() {
        let row = SpecialImportRow(
            track: track(),
            candidates: [song(1), song(2)],
            autoMatched: false,
            chosenSong: song(1),
            autoPicked: true
        )

        XCTAssertEqual(row.state, .autoPicked)
        XCTAssertTrue(row.isAutoPicked)
        XCTAssertEqual(row.adoptedSong?.id, 1)
    }

    func testAutoPickedFlagWithoutASongIsIgnored() {
        let row = SpecialImportRow(
            track: track(),
            candidates: [song(1)],
            autoMatched: false,
            chosenSong: nil,
            autoPicked: true
        )

        XCTAssertFalse(row.isAutoPicked)
        XCTAssertEqual(row.state, .open)
    }

    func testConfirmingTheSuggestedSongTurnsItIntoAUserChoice() {
        var row = SpecialImportRow(
            track: track(),
            candidates: [song(1), song(2)],
            autoMatched: false,
            chosenSong: song(1),
            autoPicked: true
        )

        row.choose(song(1))

        XCTAssertEqual(row.state, .chosen)
        XCTAssertFalse(row.isAutoPicked)
    }

    // MARK: - Clearing

    func testClearChoiceReopensAManualRow() {
        var row = openRow(candidates: [song(1)])
        row.choose(song(1))

        row.clearChoice()

        XCTAssertEqual(row.state, .open)
        XCTAssertNil(row.adoptedSong)
    }

    func testClearChoiceRemovesAnAutoPickedSuggestion() {
        var row = SpecialImportRow(
            track: track(),
            candidates: [song(1), song(2)],
            autoMatched: false,
            chosenSong: song(1),
            autoPicked: true
        )

        row.clearChoice()

        XCTAssertEqual(row.state, .open)
        XCTAssertFalse(row.isAutoPicked)
    }

    func testClearChoiceKeepsTheMatchOfAnAutoMatchedRow() {
        var row = SpecialImportRow(
            track: track(),
            candidates: [],
            autoMatched: true,
            chosenSong: song(7)
        )

        row.clearChoice()

        XCTAssertEqual(row.state, .matched)
        XCTAssertEqual(row.adoptedSong?.id, 7)
    }

    // MARK: - Skipping

    func testSkippedRowAdoptsNothingButRemembersTheChoice() {
        var row = openRow(candidates: [song(1)])
        row.choose(song(1))

        row.setSkipped(true)

        XCTAssertEqual(row.state, .skipped)
        XCTAssertNil(row.adoptedSong)
        XCTAssertEqual(row.chosenSong?.id, 1)

        row.setSkipped(false)

        XCTAssertEqual(row.state, .chosen)
        XCTAssertEqual(row.adoptedSong?.id, 1)
    }

    func testSkippingAnAutoMatchedRowRemovesItFromTheSetlist() {
        var row = SpecialImportRow(
            track: track(),
            candidates: [],
            autoMatched: true,
            chosenSong: song(7)
        )

        row.setSkipped(true)

        XCTAssertEqual(row.state, .skipped)
        XCTAssertNil(row.adoptedSong)
    }

    func testChoosingASongUnskipsTheRow() {
        var row = openRow(candidates: [song(1)])
        row.setSkipped(true)

        row.choose(song(1))

        XCTAssertEqual(row.state, .chosen)
    }

    // MARK: - adoptedSongs

    func testAdoptedSongsKeepSourceOrderAndLeaveOutOpenAndSkippedRows() {
        let matched = SpecialImportRow(
            track: track(),
            candidates: [],
            autoMatched: true,
            chosenSong: song(1)
        )
        let open = openRow(candidates: [song(2)])
        var chosen = openRow(candidates: [song(3)])
        chosen.choose(song(3))
        var skipped = openRow(candidates: [song(4)])
        skipped.choose(song(4))
        skipped.setSkipped(true)

        let songs = SpecialImportPlanner.adoptedSongs(
            from: [matched, open, chosen, skipped]
        )

        XCTAssertEqual(songs.map(\.id), [1, 3])
    }

    func testAdoptedSongsOfNoRowsIsEmpty() {
        XCTAssertTrue(SpecialImportPlanner.adoptedSongs(from: []).isEmpty)
    }

    // MARK: - Identity and description

    func testRowIDIsTheTrackID() {
        let imported = track()
        let row = SpecialImportRow(
            track: imported,
            candidates: [],
            autoMatched: false,
            chosenSong: nil
        )

        XCTAssertEqual(row.id, imported.id)
    }

    func testSourceTitleShowsArtistAndTitle() {
        let row = SpecialImportRow(
            track: track(title: "Poema", artist: "Alpha Trio"),
            candidates: [],
            autoMatched: false,
            chosenSong: nil
        )

        XCTAssertEqual(row.sourceTitle, "Alpha Trio \u{2013} Poema")
    }

    func testSourceTitleWithoutArtistIsTheTitle() {
        for artist in [nil, ""] as [String?] {
            let row = SpecialImportRow(
                track: track(title: "Poema", artist: artist),
                candidates: [],
                autoMatched: false,
                chosenSong: nil
            )

            XCTAssertEqual(row.sourceTitle, "Poema")
        }
    }

    func testSourceTitleFallsBackToDisplayNameThenFilenameThenPlaceholder() {
        let withDisplayName = SpecialImportRow(
            track: track(title: nil, displayName: "Line as written", filename: "x.flac"),
            candidates: [], autoMatched: false, chosenSong: nil
        )
        XCTAssertEqual(withDisplayName.sourceTitle, "Line as written")

        let withFilename = SpecialImportRow(
            track: track(title: "", filename: "x.flac"),
            candidates: [], autoMatched: false, chosenSong: nil
        )
        XCTAssertEqual(withFilename.sourceTitle, "x.flac")

        let nothing = SpecialImportRow(
            track: track(title: nil),
            candidates: [], autoMatched: false, chosenSong: nil
        )
        XCTAssertEqual(nothing.sourceTitle, "(unnamed)")
    }
}
