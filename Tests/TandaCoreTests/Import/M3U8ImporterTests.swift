import XCTest
import Foundation

@MainActor
final class M3U8ImporterTests: XCTestCase {

    private func importText(_ text: String) throws -> [ImportedTrack] {
        let dir = try makeTemporaryDirectory()
        let file = try writeText(text, in: dir, named: "set.m3u8")
        return try M3U8Importer.importTracks(from: file)
    }

    func testReadsPathAndExtendedInfo() throws {
        let tracks = try importText("#EXTM3U\n#EXTINF:215,Alpha Trio - Song One\n/Music/A/one.flac\n")

        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.sourceIndex, 0)
        XCTAssertEqual(track.path, "/Music/A/one.flac")
        XCTAssertEqual(track.filename, "one.flac")
        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
        XCTAssertEqual(track.duration, 215)
        XCTAssertEqual(track.sourceDisplayName, "Alpha Trio - Song One")
    }

    func testEXTINFWithoutDashIsTitleOnly() throws {
        let tracks = try importText("#EXTINF:120,Just A Title\n/Music/a.flac\n")

        let track = try XCTUnwrap(tracks.first)
        XCTAssertNil(track.artist)
        XCTAssertEqual(track.title, "Just A Title")
        XCTAssertEqual(track.duration, 120)
    }

    func testUnknownDurationMinusOneIsKept() throws {
        let tracks = try importText("#EXTINF:-1,Alpha Trio - Song One\n/Music/a.flac\n")

        XCTAssertEqual(tracks.first?.duration, -1)
    }

    func testPathWithoutEXTINFHasNoTags() throws {
        let tracks = try importText("/Music/a.flac\n")

        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.path, "/Music/a.flac")
        XCTAssertNil(track.title)
        XCTAssertNil(track.artist)
        XCTAssertNil(track.duration)
        XCTAssertNil(track.sourceDisplayName)
    }

    func testCommentsAndBlankLinesAreIgnored() throws {
        let tracks = try importText("#EXTM3U\n# some comment\n\n   \n/Music/a.flac\n\n/Music/b.flac\n")

        XCTAssertEqual(tracks.map(\.path), ["/Music/a.flac", "/Music/b.flac"])
        XCTAssertEqual(tracks.map(\.sourceIndex), [0, 1])
    }

    func testWindowsLineEndingsAreHandled() throws {
        let tracks = try importText("#EXTM3U\r\n/Music/a.flac\r\n/Music/b.flac\r\n")

        XCTAssertEqual(tracks.map(\.path), ["/Music/a.flac", "/Music/b.flac"])
    }

    func testURILinesAreSkippedAndDropTheirEXTINF() throws {
        let tracks = try importText(
            "#EXTINF:100,Stream - Radio\nhttp://example.com/a.mp3\n/Music/b.flac\n"
        )

        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.path, "/Music/b.flac")
        XCTAssertNil(track.title, "the EXTINF of the skipped stream must not leak into the next track")
        XCTAssertNil(track.duration)
    }

    func testRelativePathsAreResolvedAgainstTheListFolder() throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("sub/two.flac\n../other/three.flac\n", in: dir, named: "set.m3u8")

        let tracks = try M3U8Importer.importTracks(from: file)

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(
            tracks[0].path,
            dir.appendingPathComponent("sub/two.flac").standardizedFileURL.path
        )
        XCTAssertEqual(
            tracks[1].path,
            dir.deletingLastPathComponent()
                .appendingPathComponent("other/three.flac")
                .standardizedFileURL.path
        )
        XCTAssertEqual(tracks[0].filename, "two.flac")
        XCTAssertEqual(tracks[1].filename, "three.flac")
    }

    func testUTF8BOMDoesNotBecomeATrack() throws {
        let dir = try makeTemporaryDirectory()
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let data = Data(bom + Array("#EXTM3U\n/Music/a.flac\n".utf8))
        let file = try writeData(data, in: dir, named: "set.m3u8")

        let tracks = try M3U8Importer.importTracks(from: file)

        XCTAssertEqual(tracks.map(\.path), ["/Music/a.flac"])
    }

    func testLatin1FileIsDecodedAsFallback() throws {
        let dir = try makeTemporaryDirectory()
        let data = try XCTUnwrap("/Music/Caf\u{00E9}.flac\n".data(using: .isoLatin1))
        let file = try writeData(data, in: dir, named: "set.m3u8")

        let tracks = try M3U8Importer.importTracks(from: file)

        XCTAssertEqual(tracks.first?.path, "/Music/Caf\u{00E9}.flac")
    }

    func testMissingFileThrows() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try M3U8Importer.importTracks(from: dir.appendingPathComponent("nope.m3u8"))
        )
    }

    // MARK: - Round trip with the exporter

    func testExportedExtendedListCanBeReadBack() throws {
        let songs = [
            makeSong(path: "/Music/A/one.flac", title: "Song One", artist: "Alpha Trio", duration: 215),
            makeSong(path: "/Music/B/two.flac", title: "Song Two", artist: "Beta Band", duration: 180)
        ]
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("set.m3u8")
        try M3U8Exporter.export(songs: songs, to: file, pathStyle: .absolute, extended: true)

        let tracks = try M3U8Importer.importTracks(from: file)

        XCTAssertEqual(tracks.map(\.path), ["/Music/A/one.flac", "/Music/B/two.flac"])
        XCTAssertEqual(tracks.map(\.artist), ["Alpha Trio", "Beta Band"])
        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two"])
        XCTAssertEqual(tracks.map(\.duration), [215, 180])
    }

    func testExportedRelativeListResolvesToTheOriginalPaths() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Lists/set.m3u8")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let songPath = dir.appendingPathComponent("Album/one.flac").path
        let song = makeSong(path: songPath)

        try M3U8Exporter.export(songs: [song], to: file, pathStyle: .relative(to: file), extended: false)
        let tracks = try M3U8Importer.importTracks(from: file)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(
            tracks.first.map { PathNormalizer.normalize($0.path ?? "") },
            PathNormalizer.normalize(URL(fileURLWithPath: songPath).standardizedFileURL.path)
        )
    }

    // MARK: - importSongs (exact-path matching)

    func testImportSongsSplitsKnownAndUnknownPaths() throws {
        let known = makeSong(path: "/Music/A/one.flac")
        let dir = try makeTemporaryDirectory()
        let file = try writeText(
            "/Music/A/one.flac\n/Music/other.flac\n",
            in: dir,
            named: "set.m3u8"
        )

        let result = try M3U8Importer.importSongs(
            from: file,
            songsByNormalizedPath: [PathNormalizer.normalize("/Music/A/one.flac"): known]
        )

        XCTAssertEqual(result.resolvedSongs.map(\.filename), ["one.flac"])
        XCTAssertEqual(result.notInLibraryPaths, ["/Music/other.flac"])
        XCTAssertTrue(result.unreadableLines.isEmpty)
    }

    func testImportSongsMatchesDecomposedAndPrecomposedPaths() throws {
        // Library stores the precomposed form; the list uses the decomposed one.
        let known = makeSong(path: "/Music/M\u{00FC}ller.flac")
        let dir = try makeTemporaryDirectory()
        let file = try writeText("/Music/Mu\u{0308}ller.flac\n", in: dir, named: "set.m3u8")

        let result = try M3U8Importer.importSongs(
            from: file,
            songsByNormalizedPath: [known.normalizedPath: known]
        )

        XCTAssertEqual(result.resolvedSongs.count, 1)
        XCTAssertTrue(result.notInLibraryPaths.isEmpty)
    }

    func testImportSongsKeepsListOrderAndDuplicates() throws {
        let one = makeSong(path: "/Music/A/one.flac")
        let two = makeSong(path: "/Music/B/two.flac")
        let dir = try makeTemporaryDirectory()
        let file = try writeText(
            "/Music/B/two.flac\n/Music/A/one.flac\n/Music/B/two.flac\n",
            in: dir,
            named: "set.m3u8"
        )

        let result = try M3U8Importer.importSongs(
            from: file,
            songsByNormalizedPath: [one.normalizedPath: one, two.normalizedPath: two]
        )

        XCTAssertEqual(result.resolvedSongs.map(\.filename), ["two.flac", "one.flac", "two.flac"])
    }
}
