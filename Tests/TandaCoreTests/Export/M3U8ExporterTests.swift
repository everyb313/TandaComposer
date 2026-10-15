import XCTest
import Foundation

@MainActor
final class M3U8ExporterTests: XCTestCase {

    private func render(
        _ songs: [Song],
        style: M3U8PathStyle = .absolute,
        extended: Bool
    ) -> String {
        let data = M3U8Exporter.render(songs: songs, pathStyle: style, extended: extended)
        return String(decoding: data, as: UTF8.self)
    }

    private var sampleSongs: [Song] {
        [
            makeSong(path: "/Music/A/one.flac", title: "Song One", artist: "Alpha Trio", duration: 215),
            makeSong(path: "/Music/B/two.flac", title: "Song Two", artist: "Beta Band", duration: 180)
        ]
    }

    func testExtendedAbsoluteOutput() {
        XCTAssertEqual(
            render(sampleSongs, extended: true),
            "#EXTM3U\n"
            + "#EXTINF:215,Alpha Trio - Song One\n/Music/A/one.flac\n"
            + "#EXTINF:180,Beta Band - Song Two\n/Music/B/two.flac\n"
        )
    }

    func testPlainOutputHasOnlyPaths() {
        XCTAssertEqual(
            render(sampleSongs, extended: false),
            "/Music/A/one.flac\n/Music/B/two.flac\n"
        )
    }

    func testEmptyExtendedListHasHeaderOnly() {
        XCTAssertEqual(render([], extended: true), "#EXTM3U\n")
    }

    func testSongOrderIsPreserved() {
        let songs = Array(sampleSongs.reversed())
        let lines = render(songs, extended: false).split(separator: "\n").map(String.init)

        XCTAssertEqual(lines, ["/Music/B/two.flac", "/Music/A/one.flac"])
    }

    func testUnknownDurationIsWrittenAsMinusOne() {
        let song = makeSong(path: "/Music/A/one.flac", title: "Song One", artist: "Alpha Trio")

        XCTAssertTrue(render([song], extended: true).contains("#EXTINF:-1,Alpha Trio - Song One\n"))
    }

    func testMissingTagsFallBackToFileName() {
        let song = makeSong(path: "/Music/A/one.flac", duration: 100)

        XCTAssertTrue(render([song], extended: true).contains("#EXTINF:100,one.flac\n"))
    }

    func testOnlyTitleIsWrittenWithoutDash() {
        let song = makeSong(path: "/Music/A/one.flac", title: "Song One", duration: 100)

        XCTAssertTrue(render([song], extended: true).contains("#EXTINF:100,Song One\n"))
    }

    func testOnlyArtistIsWrittenWithoutDash() {
        let song = makeSong(path: "/Music/A/one.flac", artist: "Alpha Trio", duration: 100)

        XCTAssertTrue(render([song], extended: true).contains("#EXTINF:100,Alpha Trio\n"))
    }

    func testRelativePathsWalkUpWithDotDot() {
        let base = URL(fileURLWithPath: "/Music/Lists/set.m3u8")
        let song = makeSong(path: "/Music/Album/one.flac")

        XCTAssertEqual(
            render([song], style: .relative(to: base), extended: false),
            "../Album/one.flac\n"
        )
    }

    func testRelativePathInSameFolderHasNoPrefix() {
        let base = URL(fileURLWithPath: "/Music/Lists/set.m3u8")
        let song = makeSong(path: "/Music/Lists/one.flac")

        XCTAssertEqual(
            render([song], style: .relative(to: base), extended: false),
            "one.flac\n"
        )
    }

    func testRelativePathIntoSubfolder() {
        let base = URL(fileURLWithPath: "/Music/Lists/set.m3u8")
        let song = makeSong(path: "/Music/Lists/Tango/one.flac")

        XCTAssertEqual(
            render([song], style: .relative(to: base), extended: false),
            "Tango/one.flac\n"
        )
    }

    func testExportWritesTheRenderedBytes() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("set.m3u8")

        try M3U8Exporter.export(songs: sampleSongs, to: file, pathStyle: .absolute, extended: true)

        let expected = M3U8Exporter.render(songs: sampleSongs, pathStyle: .absolute, extended: true)
        XCTAssertEqual(try Data(contentsOf: file), expected)
    }
}
