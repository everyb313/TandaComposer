import XCTest
import Foundation

/// What the list in "Tandas from ZIP" shows for lines with candidates, and
/// when it offers them for a choice.
@MainActor
final class TandaImportLineCandidatesTests: XCTestCase {

    private func song(_ id: Int64) -> Song {
        makeSong(id: id, path: "/Library/\(id).flac", title: "Poema")
    }

    private func line(
        song chosen: Song? = nil,
        note: String,
        candidates: [Song],
        chosenByUser: Bool = false
    ) -> TandaImportLine {
        var line = TandaImportLine(
            number: 1,
            text: "Alpha Trio - Poema",
            song: chosen,
            note: note,
            candidates: candidates
        )
        line.chosenByUser = chosenByUser
        return line
    }

    // MARK: - candidateSummary

    func testAnOpenLineShowsHowManyCandidatesThereAre() {
        XCTAssertEqual(
            line(note: "2 different candidates", candidates: [song(1), song(2)]).candidateSummary,
            "2 candidates"
        )
        XCTAssertEqual(
            line(note: "the only match differs in title, orchestra or singer", candidates: [song(1)]).candidateSummary,
            "1 candidate"
        )
        XCTAssertEqual(
            line(note: "3 different candidates", candidates: [song(1), song(2), song(3)]).candidateSummary,
            "3 candidates"
        )
    }

    func testTheOnlyMatchIsShownAsOneMatchedCandidate() {
        let only = line(song: song(1), note: TandaImportResolver.onlyMatchNote, candidates: [song(1)])

        XCTAssertEqual(only.candidateSummary, "1 candidate (matched)")
    }

    func testALineWithoutCandidatesHasNoSummary() {
        XCTAssertNil(line(note: "not in your TrackLibrary", candidates: []).candidateSummary)
    }

    func testOtherResolvedLinesHaveNoSummary() {
        let exact = line(song: song(1), note: "exact path", candidates: [])
        let best = line(
            song: song(1),
            note: TandaImportResolver.bestOfSeveralFilesNote,
            candidates: [song(1), song(2)]
        )
        let byHand = line(
            song: song(1),
            note: "chosen by you",
            candidates: [song(1), song(2)],
            chosenByUser: true
        )

        XCTAssertNil(exact.candidateSummary)
        XCTAssertNil(best.candidateSummary)
        XCTAssertNil(byHand.candidateSummary)
    }

    // MARK: - offersCandidateList

    func testTheOnlyMatchOffersItsCandidateLikeEveryOtherLine() {
        let only = line(song: song(1), note: TandaImportResolver.onlyMatchNote, candidates: [song(1)])

        XCTAssertTrue(only.offersCandidateList(isEditable: true))
    }

    func testNothingIsOfferedOnceTheTandaIsImported() {
        let only = line(song: song(1), note: TandaImportResolver.onlyMatchNote, candidates: [song(1)])
        let open = line(note: "2 different candidates", candidates: [song(1), song(2)])

        XCTAssertFalse(only.offersCandidateList(isEditable: false))
        XCTAssertFalse(open.offersCandidateList(isEditable: false))
    }

    func testOpenLinesAndSeveralFilesOfferTheirCandidates() {
        let open = line(note: "2 different candidates", candidates: [song(1), song(2)])
        let best = line(
            song: song(1),
            note: TandaImportResolver.bestOfSeveralFilesNote,
            candidates: [song(1), song(2)]
        )

        XCTAssertTrue(open.offersCandidateList(isEditable: true))
        XCTAssertTrue(best.offersCandidateList(isEditable: true))
    }

    func testAChoiceMadeByHandCanBeTakenBack() {
        let byHand = line(
            song: song(1),
            note: "chosen by you",
            candidates: [song(1)],
            chosenByUser: true
        )

        XCTAssertTrue(byHand.offersCandidateList(isEditable: true))
    }

    func testLinesWithoutCandidatesOfferNothing() {
        let exact = line(song: song(1), note: "exact path", candidates: [])
        let missing = line(note: "not in your TrackLibrary", candidates: [])

        XCTAssertFalse(exact.offersCandidateList(isEditable: true))
        XCTAssertFalse(missing.offersCandidateList(isEditable: true))
    }

    func testAResolvedSingleCandidateOfAnotherKindStaysHidden() {
        let other = line(song: song(1), note: "something else", candidates: [song(1)])

        XCTAssertFalse(other.offersCandidateList(isEditable: true))
    }

    func testTheOnlyMatchNoteKeepsItsWording() {
        XCTAssertEqual(TandaImportResolver.onlyMatchNote, "only match")
    }
}
