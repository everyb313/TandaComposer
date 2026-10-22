import XCTest
import Foundation

/// The wording of `TandaSaveError` is what the user sees in the alert.
@MainActor
final class TandaSaveErrorTests: XCTestCase {

    func testTooFewTracksNamesTheLimitAndTheCurrentCount() {
        XCTAssertEqual(
            TandaSaveError.tooFewTracks(2).errorDescription,
            "Please mark at least 3 tracks in the setlist for the Tanda (currently 2)."
        )
    }

    func testTooManyTracksNamesTheLimitAndTheCurrentCount() {
        XCTAssertEqual(
            TandaSaveError.tooManyTracks(9).errorDescription,
            "Please mark at most 8 tracks in the setlist for the Tanda (currently 9)."
        )
    }

    func testDuplicateTandaNamesTheExistingTanda() {
        XCTAssertEqual(
            TandaSaveError.duplicateTanda(existingName: "Alpha Trio 1").errorDescription,
            "This Tanda (same tracks) already exists as \"Alpha Trio 1\"."
        )
    }

    func testMissingTracksAreListedSeparatedByCommas() {
        XCTAssertEqual(
            TandaSaveError.containsMissingTracks(titles: ["T1", "T4"]).errorDescription,
            "Can't save a Tanda with track(s) missing on disk: T1, T4. Fix or remove them first."
        )
    }

    func testDroppingBelowTheMinimumPointsAtDeletingTheTanda() {
        XCTAssertEqual(
            TandaSaveError.wouldDropBelowMinimum(2).errorDescription,
            "A Tanda needs at least 3 tracks (currently 2). Delete the whole Tanda instead if you want to remove it entirely."
        )
    }

    func testLocalizedDescriptionUsesTheErrorDescription() {
        let error: Error = TandaSaveError.tooFewTracks(1)

        XCTAssertEqual(error.localizedDescription, TandaSaveError.tooFewTracks(1).errorDescription)
    }
}
