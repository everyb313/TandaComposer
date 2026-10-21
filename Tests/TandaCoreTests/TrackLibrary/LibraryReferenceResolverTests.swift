import XCTest
import Foundation

/// `LibraryReferenceResolver` decides how a song stored in a Setlist or Tanda
/// file is matched with the live Library: by id (only if the file was saved
/// against this very Library) or by normalized path.
@MainActor
final class LibraryReferenceResolverTests: XCTestCase {

    private func song(_ id: Int64?, path: String, title: String? = nil) -> Song {
        makeSong(id: id, path: path, title: title ?? "T\(id ?? 0)")
    }

    private func tables(_ songs: [Song]) -> (byID: [Int64: Song], byPath: [String: Song]) {
        var byID: [Int64: Song] = [:]
        var byPath: [String: Song] = [:]
        for song in songs {
            if let id = song.id {
                byID[id] = song
            }
            byPath[song.normalizedPath] = song
        }
        return (byID, byPath)
    }

    private func resolve(
        _ saved: Song,
        live: [Song],
        missing: Set<Int64> = [],
        trustID: Bool = true
    ) -> LibraryReferenceResolver.Resolution {
        let lookup = tables(live)
        return LibraryReferenceResolver.resolve(
            saved,
            byID: lookup.byID,
            byPath: lookup.byPath,
            missingSongIDs: missing,
            trustID: trustID
        )
    }

    // MARK: - identity

    func testIdentityPrefersTheIDWhenTrusted() {
        let saved = song(7, path: "/Music/a.flac")

        XCTAssertEqual(LibraryReferenceResolver.identity(for: saved), .id(7))
    }

    func testIdentityFallsBackToThePathWithoutAnID() {
        let saved = song(nil, path: "/Music/a.flac")

        XCTAssertEqual(
            LibraryReferenceResolver.identity(for: saved),
            .normalizedPath(saved.normalizedPath)
        )
    }

    func testIdentityIgnoresTheIDWhenNotTrusted() {
        let saved = song(7, path: "/Music/a.flac")

        XCTAssertEqual(
            LibraryReferenceResolver.identity(for: saved, trustID: false),
            .normalizedPath(saved.normalizedPath)
        )
    }

    func testIdentityOfASongWithoutIDAndPathIsNil() {
        var saved = song(nil, path: "/Music/a.flac")
        saved.normalizedPath = ""

        XCTAssertNil(LibraryReferenceResolver.identity(for: saved))
    }

    func testIdentitiesAreHashable() {
        let ids: Set<LibraryReferenceResolver.TrackIdentity> = [.id(1), .id(1), .id(2), .normalizedPath("/a"), .normalizedPath("/a")]

        XCTAssertEqual(ids.count, 3)
    }

    // MARK: - resolve

    func testResolvesByIDEvenWhenThePathChanged() {
        let saved = song(1, path: "/Old/a.flac")
        let live = song(1, path: "/New/a.flac")

        let result = resolve(saved, live: [live])

        XCTAssertEqual(result.live?.path, "/New/a.flac")
        XCTAssertTrue(result.pathChanged)
        XCTAssertFalse(result.isMissing)
    }

    func testResolvesByPathWhenTheIDIsUnknown() {
        let saved = song(99, path: "/Music/a.flac")
        let live = song(1, path: "/Music/a.flac")

        let result = resolve(saved, live: [live])

        XCTAssertEqual(result.live?.id, 1)
        XCTAssertFalse(result.pathChanged)
    }

    func testTheIDWinsOverThePath() {
        let saved = song(1, path: "/Music/b.flac")
        let byID = song(1, path: "/Elsewhere/a.flac")
        let byPath = song(2, path: "/Music/b.flac")

        let result = resolve(saved, live: [byID, byPath])

        XCTAssertEqual(result.live?.id, 1)
    }

    func testAnUntrustedIDIsIgnored() {
        let saved = song(1, path: "/Music/b.flac")
        let sameID = song(1, path: "/Elsewhere/a.flac")
        let samePath = song(2, path: "/Music/b.flac")

        let result = resolve(saved, live: [sameID, samePath], trustID: false)

        XCTAssertEqual(result.live?.id, 2)
        XCTAssertFalse(result.pathChanged)
    }

    func testNothingFoundGivesNoLiveSong() {
        let saved = song(1, path: "/Music/a.flac")

        let result = resolve(saved, live: [song(2, path: "/Music/other.flac")])

        XCTAssertNil(result.live)
        XCTAssertFalse(result.pathChanged)
        XCTAssertFalse(result.isMissing)
    }

    func testNormalizedPathsMatchDecomposedAndPrecomposedNames() {
        let saved = song(nil, path: "/Music/Mu\u{0308}ller.flac")
        let live = song(1, path: "/Music/M\u{00FC}ller.flac")

        let result = resolve(saved, live: [live])

        XCTAssertEqual(result.live?.id, 1)
        // Swift compares Strings by canonical equivalence, so the two spellings
        // count as the same path and are not reported as a change.
        XCTAssertFalse(result.pathChanged)
    }

    // MARK: - isMissing

    func testMissingIsDecidedByTheLiveSongID() {
        let saved = song(1, path: "/Music/a.flac")
        let live = song(1, path: "/Music/a.flac")

        XCTAssertTrue(resolve(saved, live: [live], missing: [1]).isMissing)
        XCTAssertFalse(resolve(saved, live: [live], missing: [2]).isMissing)
    }

    func testMissingFlagBelongsToTheLiveSongNotToTheSavedID() {
        // Saved id 5 is "missing" in this Library, but resolves by path to id 1.
        let saved = song(5, path: "/Music/a.flac")
        let live = song(1, path: "/Music/a.flac")

        XCTAssertFalse(resolve(saved, live: [live], missing: [5], trustID: false).isMissing)
        XCTAssertTrue(resolve(saved, live: [live], missing: [1], trustID: false).isMissing)
    }

    func testAMovedAndMissingFileIsBothChangedAndMissing() {
        let saved = song(1, path: "/Old/a.flac")
        let live = song(1, path: "/New/a.flac")

        let result = resolve(saved, live: [live], missing: [1])

        XCTAssertTrue(result.pathChanged)
        XCTAssertTrue(result.isMissing)
    }
}
