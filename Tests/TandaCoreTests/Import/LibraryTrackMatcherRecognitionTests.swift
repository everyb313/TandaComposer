import XCTest
import Foundation

/// A recognized orchestra or singer is a HARD constraint in
/// `LibraryTrackMatcher`: candidates from another orchestra/singer are not
/// shown. Free-form text that is not in the reference list is ignored.
///
/// NEEDS the test seam in `TracklibImportReferenceStore`
/// (`overrideEntriesForTesting`, see README_TESTS.md). All names are invented.
@MainActor
final class LibraryTrackMatcherRecognitionTests: XCTestCase {

    private func entry(_ name: String, _ aliases: [String] = []) -> TracklibImportReferenceEntry {
        TracklibImportReferenceEntry(name: name, aliases: [name] + aliases)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        TracklibImportReferenceStore.overrideEntriesForTesting = (
            orchestras: [entry("Alpha Trio", ["Carlos Alpha"]), entry("Beta Band")],
            singers: [entry("Singer X"), entry("Roberto Voz")]
        )
    }

    override func tearDownWithError() throws {
        TracklibImportReferenceStore.overrideEntriesForTesting = nil
        try super.tearDownWithError()
    }

    private func song(
        _ id: Int64?,
        artist: String? = nil,
        albumArtist: String? = nil,
        path: String? = nil
    ) -> Song {
        makeSong(
            id: id,
            path: path ?? "/Library/\(id ?? 0)/\(id ?? 0).flac",
            title: "Poema",
            artist: artist,
            albumArtist: albumArtist
        )
    }

    private func ids(_ result: LibraryTrackMatcher.Result) -> [Int64?] {
        result.candidates.map(\.song.id)
    }

    private func match(_ track: ImportedTrack, _ songs: [Song]) -> LibraryTrackMatcher.Result {
        LibraryTrackMatcher(songs: songs).match(track)
    }

    // MARK: - Orchestra

    func testARecognizedOrchestraExcludesOtherOrchestras() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        let result = match(track, songs)

        XCTAssertEqual(ids(result), [1])
        XCTAssertEqual(result.status, .confident)
    }

    func testAnAliasIsRecognizedAsTheSameOrchestra() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Carlos Alpha")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    func testRecognitionIgnoresCase() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "ALPHA TRIO")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    func testTheLibrarySideIsRecognizedByAliasToo() {
        let songs = [song(1, artist: "Carlos Alpha"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    func testFreeFormTextThatIsNotInTheReferenceListIsIgnored() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Unknown Quartet")

        XCTAssertEqual(Set(ids(match(track, songs)).compactMap { $0 }), [1, 2])
    }

    func testARecognizedOrchestraWithoutAnyMatchingSongGivesNothing() {
        let songs = [song(1, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        let result = match(track, songs)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.status, .unmatched)
    }

    func testALibrarySongWithAnUnknownOrchestraIsExcludedWhenTheImportNamesAKnownOne() {
        let songs = [song(1, artist: "Unknown Quartet"), song(2, artist: "Alpha Trio")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        XCTAssertEqual(ids(match(track, songs)), [2])
    }

    // MARK: - Singer

    func testARecognizedSingerExcludesOtherSingers() {
        let songs = [song(1, albumArtist: "Singer X"), song(2, albumArtist: "Roberto Voz")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", albumArtist: "Singer X")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    func testOrchestraAndSingerMustBothAgree() {
        let songs = [
            song(1, artist: "Alpha Trio", albumArtist: "Singer X"),
            song(2, artist: "Alpha Trio", albumArtist: "Roberto Voz"),
            song(3, artist: "Beta Band", albumArtist: "Singer X")
        ]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio", albumArtist: "Singer X")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    // MARK: - Where the filter applies

    func testTheFilterAlsoAppliesToFileNameCandidates() {
        let songs = [
            song(1, artist: "Alpha Trio", path: "/Library/1/Poema.flac"),
            song(2, artist: "Beta Band", path: "/Library/2/Poema.flac")
        ]
        let track = ImportedTrack(sourceIndex: 0, filename: "Poema.flac", artist: "Alpha Trio")

        XCTAssertEqual(ids(match(track, songs)), [1])
    }

    func testFilterCandidatesIsAvailableForFallbackSearches() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let matcher = LibraryTrackMatcher(songs: songs)

        let recognized = matcher.filterCandidates(
            songs,
            for: ImportedTrack(sourceIndex: 0, artist: "Alpha Trio")
        )
        let unrecognized = matcher.filterCandidates(
            songs,
            for: ImportedTrack(sourceIndex: 0, artist: "Unknown Quartet")
        )

        XCTAssertEqual(recognized.map(\.id), [1])
        XCTAssertEqual(unrecognized.map(\.id), [1, 2])
    }

    func testSongsWithoutAnIDAreFilteredToo() {
        let songs = [
            song(nil, artist: "Alpha Trio", path: "/Library/a.flac"),
            song(nil, artist: "Beta Band", path: "/Library/b.flac")
        ]
        let matcher = LibraryTrackMatcher(songs: songs)

        let kept = matcher.filterCandidates(
            songs,
            for: ImportedTrack(sourceIndex: 0, artist: "Alpha Trio")
        )

        XCTAssertEqual(kept.map(\.path), ["/Library/a.flac"])
    }

    func testTheSameMatcherFiltersRepeatedLinesConsistently() {
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let matcher = LibraryTrackMatcher(songs: songs)

        for _ in 0..<3 {
            let first = matcher.match(ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio"))
            let second = matcher.match(ImportedTrack(sourceIndex: 1, title: "Poema", artist: "Beta Band"))

            XCTAssertEqual(first.candidates.map(\.song.id), [1])
            XCTAssertEqual(second.candidates.map(\.song.id), [2])
        }
    }

    func testWithoutAnyReferenceDataNothingIsFiltered() {
        TracklibImportReferenceStore.overrideEntriesForTesting = nil
        let songs = [song(1, artist: "Alpha Trio"), song(2, artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        XCTAssertEqual(Set(ids(match(track, songs)).compactMap { $0 }), [1, 2])
    }
}
