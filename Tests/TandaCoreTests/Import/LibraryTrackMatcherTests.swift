import XCTest
import Foundation

/// Name recognition (known orchestras/singers from `tracklib_import_reference.json`)
/// has no reference data in the test bundle, so the "recognized role is a hard
/// filter" step passes everything through here. These tests cover the matching
/// order and the scoring. All names are invented on purpose.
@MainActor
final class LibraryTrackMatcherTests: XCTestCase {

    // MARK: - Helpers

    private func librarySong(
        _ id: Int64,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        duration: Int? = nil,
        bpm: Double? = nil,
        key: String? = nil,
        hash: String? = nil,
        path: String? = nil
    ) -> Song {
        var song = makeSong(
            id: id,
            path: path ?? "/Library/\(id).flac",
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            duration: duration,
            album: album
        )
        song.bpm = bpm
        song.key = key
        song.fileHash = hash
        return song
    }

    private func candidateIDs(_ result: LibraryTrackMatcher.Result) -> [Int64?] {
        result.candidates.map(\.song.id)
    }

    private func match(
        _ track: ImportedTrack,
        in songs: [Song],
        trustLibraryID: Bool = false
    ) -> LibraryTrackMatcher.Result {
        LibraryTrackMatcher(songs: songs, trustLibraryID: trustLibraryID).match(track)
    }

    // MARK: - Library ID

    func testTrustedLibraryIDWinsImmediately() {
        let songs = [librarySong(5, title: "Anything")]
        let track = ImportedTrack(sourceIndex: 0, title: "Something else", libraryID: 5)

        let result = match(track, in: songs, trustLibraryID: true)

        XCTAssertEqual(result.status, .exact)
        XCTAssertEqual(candidateIDs(result), [5])
        XCTAssertEqual(result.bestCandidate?.score, 10_000)
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.libraryID])
    }

    func testLibraryIDIsIgnoredUnlessTheCallerTrustsIt() {
        let songs = [librarySong(5, title: "Anything")]
        let track = ImportedTrack(sourceIndex: 0, title: "Something else", libraryID: 5)

        let result = match(track, in: songs, trustLibraryID: false)

        XCTAssertEqual(result.status, .unmatched)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testUnknownLibraryIDFallsThroughToTheOtherRules() {
        let songs = [librarySong(1, title: "Poema")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", libraryID: 999)

        let result = match(track, in: songs, trustLibraryID: true)

        XCTAssertEqual(candidateIDs(result), [1])
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.title])
    }

    // MARK: - File hash

    func testSingleHashMatchIsExact() {
        let songs = [librarySong(1, title: "A", hash: "abc123"), librarySong(2, title: "B", hash: "zzz")]
        let track = ImportedTrack(sourceIndex: 0, fileHash: "abc123")

        let result = match(track, in: songs)

        XCTAssertEqual(result.status, .exact)
        XCTAssertEqual(candidateIDs(result), [1])
        XCTAssertEqual(result.bestCandidate?.score, 9_000)
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.fileHash])
    }

    func testHashComparisonIgnoresCase() {
        let songs = [librarySong(1, hash: "abc123")]

        XCTAssertEqual(match(ImportedTrack(sourceIndex: 0, fileHash: "ABC123"), in: songs).status, .exact)
    }

    func testSeveralSongsWithTheSameHashAreAmbiguousAndKeepLibraryOrder() {
        let songs = [librarySong(7, hash: "same"), librarySong(2, hash: "same"), librarySong(3, hash: "other")]

        let result = match(ImportedTrack(sourceIndex: 0, fileHash: "same"), in: songs)

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(candidateIDs(result), [7, 2])
        XCTAssertTrue(result.candidates.allSatisfy { $0.score == 9_000 })
    }

    func testUnknownHashFallsThroughToMetadata() {
        let songs = [librarySong(1, title: "Poema", hash: "known")]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", fileHash: "unknown")

        XCTAssertEqual(candidateIDs(match(track, in: songs)), [1])
    }

    // MARK: - Path

    func testExactPathIsExact() {
        let songs = [librarySong(1, path: "/Music/a.flac"), librarySong(2, path: "/Music/b.flac")]
        let track = ImportedTrack(sourceIndex: 0, path: "/Music/b.flac")

        let result = match(track, in: songs)

        XCTAssertEqual(result.status, .exact)
        XCTAssertEqual(candidateIDs(result), [2])
        XCTAssertEqual(result.bestCandidate?.score, 8_000)
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.path])
    }

    func testPathMatchIgnoresUnicodeNormalization() {
        let songs = [librarySong(1, path: "/Music/M\u{00FC}ller.flac")]
        let track = ImportedTrack(sourceIndex: 0, path: "/Music/Mu\u{0308}ller.flac")

        XCTAssertEqual(match(track, in: songs).status, .exact)
    }

    // MARK: - Precedence

    func testRulesAreTriedInOrderIDHashPathMetadata() {
        let byID = librarySong(1, title: "X", path: "/Music/id.flac")
        let byHash = librarySong(2, title: "X", hash: "h", path: "/Music/hash.flac")
        let byPath = librarySong(3, title: "X", path: "/Music/path.flac")
        let byTitle = librarySong(4, title: "Poema", path: "/Music/title.flac")
        let songs = [byID, byHash, byPath, byTitle]

        var track = ImportedTrack(
            sourceIndex: 0,
            path: "/Music/path.flac",
            title: "Poema",
            fileHash: "h",
            libraryID: 1
        )
        XCTAssertEqual(candidateIDs(match(track, in: songs, trustLibraryID: true)), [1], "library id first")

        track = ImportedTrack(sourceIndex: 0, path: "/Music/path.flac", title: "Poema", fileHash: "h")
        XCTAssertEqual(candidateIDs(match(track, in: songs)), [2], "then the hash")

        track = ImportedTrack(sourceIndex: 0, path: "/Music/path.flac", title: "Poema")
        XCTAssertEqual(candidateIDs(match(track, in: songs)), [3], "then the path")

        track = ImportedTrack(sourceIndex: 0, title: "Poema")
        XCTAssertEqual(candidateIDs(match(track, in: songs)), [4], "metadata last")
    }

    // MARK: - Metadata: title

    func testTitleMatchIgnoresCaseAccentsAndApostrophes() {
        let songs = [librarySong(1, title: "Coraz\u{00F3}n de oro"), librarySong(2, title: "D'Arienzo's Waltz")]

        XCTAssertEqual(candidateIDs(match(ImportedTrack(sourceIndex: 0, title: " CORAZON de ORO "), in: songs)), [1])
        XCTAssertEqual(candidateIDs(match(ImportedTrack(sourceIndex: 0, title: "D\u{2019}Arienzo\u{2019}s Waltz"), in: songs)), [2])
    }

    func testATitleAloneIsOnlyAmbiguous() {
        let songs = [librarySong(1, title: "Poema")]

        let result = match(ImportedTrack(sourceIndex: 0, title: "Poema"), in: songs)

        XCTAssertEqual(result.status, .ambiguous, "400 points are below the confidence threshold of 500")
        XCTAssertEqual(result.bestCandidate?.score, 400)
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.title])
    }

    func testNothingMatchingIsUnmatched() {
        let songs = [librarySong(1, title: "Poema")]

        let result = match(ImportedTrack(sourceIndex: 0, title: "Unknown"), in: songs)

        XCTAssertEqual(result.status, .unmatched)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertNil(result.bestCandidate)
    }

    func testATrackWithoutAnyDataIsUnmatched() {
        let songs = [librarySong(1, title: "Poema")]

        XCTAssertEqual(match(ImportedTrack(sourceIndex: 0), in: songs).status, .unmatched)
    }

    func testEmptyLibraryMatchesNothing() {
        XCTAssertEqual(match(ImportedTrack(sourceIndex: 0, title: "Poema"), in: []).status, .unmatched)
    }

    // MARK: - Metadata: filename fallback

    func testFileNameIsUsedWhenThereIsNoTitle() {
        let songs = [librarySong(1, title: "Something", path: "/Library/one.flac")]
        let track = ImportedTrack(sourceIndex: 0, filename: "ONE.mp3")

        let result = match(track, in: songs)

        XCTAssertEqual(candidateIDs(result), [1])
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(result.bestCandidate?.score, 0, "same base name, but not the same file name")
    }

    func testFileNameIsAlsoUsedWhenTheTitleIsUnknown() {
        let songs = [librarySong(1, title: "Something", path: "/Library/one.flac")]
        let track = ImportedTrack(sourceIndex: 0, filename: "one.flac", title: "Not in library")

        let result = match(track, in: songs)

        XCTAssertEqual(candidateIDs(result), [1])
        XCTAssertEqual(result.bestCandidate?.matchedFields, [.filename])
        XCTAssertEqual(result.bestCandidate?.score, 35)
    }

    func testFileNameIsNotUsedWhenTheTitleAlreadyFoundCandidates() {
        let songs = [
            librarySong(1, title: "Poema", path: "/Library/a.flac"),
            librarySong(2, title: "Other", path: "/Library/one.flac")
        ]
        let track = ImportedTrack(sourceIndex: 0, filename: "one.flac", title: "Poema")

        XCTAssertEqual(candidateIDs(match(track, in: songs)), [1])
    }

    // MARK: - Scoring components (title 400 + one more field)

    private func score(
        library: Song,
        imported: ImportedTrack
    ) -> LibraryTrackMatcher.Candidate? {
        LibraryTrackMatcher(songs: [library]).match(imported).bestCandidate
    }

    func testDurationScoreDependsOnTheDifference() {
        let library = librarySong(1, title: "Poema", duration: 200)
        let cases: [(Int, Int, Bool)] = [
            (200, 490, true), (201, 465, true), (199, 465, true),
            (203, 430, true), (197, 430, true), (204, 400, false), (150, 400, false)
        ]

        for (seconds, expected, hasField) in cases {
            let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", duration: seconds))
            XCTAssertEqual(candidate?.score, expected, "duration \(seconds)")
            XCTAssertEqual(candidate?.matchedFields.contains(.duration), hasField, "duration \(seconds)")
        }
    }

    func testBPMScoreDependsOnTheDifference() {
        let library = librarySong(1, title: "Poema", bpm: 111.0)
        let cases: [(Double, Int)] = [(111.0, 445), (111.005, 445), (111.5, 425), (112.0, 425), (112.5, 400)]

        for (bpm, expected) in cases {
            let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", bpm: bpm))
            XCTAssertEqual(candidate?.score, expected, "bpm \(bpm)")
        }
    }

    func testKeyAddsTwentyFivePointsIgnoringCase() {
        let library = librarySong(1, title: "Poema", key: "Am")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", key: "am"))

        XCTAssertEqual(candidate?.score, 425)
        XCTAssertEqual(candidate?.matchedFields, [.title, .key])
    }

    func testAlbumAddsSeventyPoints() {
        let library = librarySong(1, title: "Poema", album: "Album One")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", album: "ALBUM one"))

        XCTAssertEqual(candidate?.score, 470)
        XCTAssertEqual(candidate?.matchedFields, [.title, .album])
    }

    func testFileNameAddsThirtyFivePointsIgnoringCase() {
        let library = librarySong(1, title: "Poema", path: "/Library/one.flac")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, filename: "ONE.FLAC", title: "Poema"))

        XCTAssertEqual(candidate?.score, 435)
        XCTAssertEqual(candidate?.matchedFields, [.title, .filename])
    }

    func testFileNameOfTheImportedPathAddsTwentyMore() {
        let library = librarySong(1, title: "Poema", path: "/Library/one.flac")

        let onlyPath = score(library: library, imported: ImportedTrack(sourceIndex: 0, path: "/Elsewhere/one.flac", title: "Poema"))
        XCTAssertEqual(onlyPath?.score, 420)
        XCTAssertEqual(onlyPath?.matchedFields, [.title, .filename])

        let both = score(
            library: library,
            imported: ImportedTrack(sourceIndex: 0, path: "/Elsewhere/one.flac", filename: "one.flac", title: "Poema")
        )
        XCTAssertEqual(both?.score, 455)
        XCTAssertEqual(both?.matchedFields, [.title, .filename], "the field is listed once")
    }

    func testAllComponentsAddUp() {
        let library = librarySong(
            1, title: "Poema", album: "Album One", duration: 200, bpm: 111, key: "Am",
            path: "/Library/one.flac"
        )
        let imported = ImportedTrack(
            sourceIndex: 0,
            path: "/Elsewhere/one.flac",
            filename: "one.flac",
            title: "Poema",
            album: "Album One",
            duration: 200,
            bpm: 111,
            key: "Am"
        )

        let candidate = score(library: library, imported: imported)

        XCTAssertEqual(candidate?.score, 400 + 70 + 90 + 45 + 25 + 35 + 20)
        XCTAssertEqual(candidate?.matchedFields, [.title, .album, .duration, .bpm, .key, .filename])
    }

    /// Orchestra and singer are looked up in ALL three tag fields (see
    /// `TrackMetadataProfile`), so a shared tag value counts for both roles.
    /// This pins the current behavior: 400 title + 260 orchestra + 220 singer.
    func testASharedTagValueCountsForBothRoles() {
        let library = librarySong(1, title: "Poema", artist: "Alpha Trio")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", artist: "alpha trio"))

        XCTAssertEqual(candidate?.score, 880)
        XCTAssertEqual(candidate?.matchedFields, [.title, .orchestra, .singer])
    }

    func testTagsInSwappedFieldsStillMatch() {
        let library = librarySong(1, title: "Poema", artist: "Singer Q", albumArtist: "Alpha Trio")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio"))

        XCTAssertEqual(candidate?.matchedFields.contains(.orchestra), true)
    }

    func testDifferentTagsGiveNoRolePoints() {
        let library = librarySong(1, title: "Poema", artist: "Alpha Trio")

        let candidate = score(library: library, imported: ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Beta Band"))

        XCTAssertEqual(candidate?.score, 400)
    }

    // MARK: - Status and ordering

    func testClearWinnerWithEnoughPointsIsConfident() {
        let songs = [
            librarySong(1, title: "Poema", artist: "Beta Band"),
            librarySong(2, title: "Poema", artist: "Alpha Trio")
        ]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        let result = match(track, in: songs)

        XCTAssertEqual(result.status, .confident)
        XCTAssertEqual(candidateIDs(result), [2, 1], "best first")
        XCTAssertEqual(result.candidates.map(\.score), [880, 400])
    }

    func testAGapBelowOneHundredTwentyIsAmbiguous() {
        let imported = ImportedTrack(sourceIndex: 0, title: "Poema", duration: 200, bpm: 111)
        let best = librarySong(1, title: "Poema", duration: 200, bpm: 111)          // 535

        let farBehind = librarySong(2, title: "Poema")                              // 400, gap 135
        XCTAssertEqual(match(imported, in: [best, farBehind]).status, .confident)

        let closeBehind = librarySong(3, title: "Poema", duration: 201)             // 465, gap 70
        XCTAssertEqual(match(imported, in: [best, closeBehind]).status, .ambiguous)
    }

    func testEqualScoresAreOrderedByLibraryID() {
        let songs = [
            librarySong(7, title: "Poema", artist: "Alpha Trio"),
            librarySong(2, title: "Poema", artist: "Alpha Trio")
        ]
        let track = ImportedTrack(sourceIndex: 0, title: "Poema", artist: "Alpha Trio")

        let result = match(track, in: songs)

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertEqual(candidateIDs(result), [2, 7])
    }

    func testBestCandidateIsTheFirstOne() {
        let songs = [librarySong(1, title: "Poema"), librarySong(2, title: "Poema", duration: 200)]

        let result = match(ImportedTrack(sourceIndex: 0, title: "Poema", duration: 200), in: songs)

        XCTAssertEqual(result.bestCandidate?.song.id, result.candidates.first?.song.id)
        XCTAssertEqual(result.bestCandidate?.song.id, 2)
    }

    // MARK: - matchAll and filterCandidates

    func testMatchAllKeepsOrderAndCount() {
        let songs = [librarySong(1, title: "Poema"), librarySong(2, title: "Corazon")]
        let tracks = [
            ImportedTrack(sourceIndex: 0, title: "Corazon"),
            ImportedTrack(sourceIndex: 1, title: "Unknown"),
            ImportedTrack(sourceIndex: 2, title: "Poema")
        ]

        let results = LibraryTrackMatcher(songs: songs).matchAll(tracks)

        XCTAssertEqual(results.map(\.importedTrack.sourceIndex), [0, 1, 2])
        XCTAssertEqual(results.map(\.status), [.ambiguous, .unmatched, .ambiguous])
        XCTAssertEqual(results.map { $0.bestCandidate?.song.id }, [2, nil, 1])
    }

    func testMatchAllOfNothingIsEmpty() {
        XCTAssertTrue(LibraryTrackMatcher(songs: []).matchAll([]).isEmpty)
    }

    func testFilterCandidatesKeepsEverythingWhenNoRoleIsRecognized() {
        let songs = [librarySong(1, title: "A", artist: "Alpha Trio"), librarySong(2, title: "B", artist: "Beta Band")]
        let track = ImportedTrack(sourceIndex: 0, artist: "Invented Quartet")

        let filtered = LibraryTrackMatcher(songs: songs).filterCandidates(songs, for: track)

        XCTAssertEqual(filtered.map(\.id), [1, 2])
    }

    func testSongsWithoutIDsAreStillMatchedByMetadata() {
        let song = makeSong(path: "/Library/x.flac", title: "Poema")

        let result = match(ImportedTrack(sourceIndex: 0, title: "Poema"), in: [song])

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertNil(result.bestCandidate?.song.id)
    }
}
