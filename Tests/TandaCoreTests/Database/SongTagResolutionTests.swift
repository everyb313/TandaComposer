import XCTest
import Foundation

/// "Orchestra" and "Singer" are a configurable view onto the raw tag fields
/// (Artist / AlbumArtist / Grouping), because tango collections tag them
/// differently. `Song.resolvedOrchestra/resolvedSinger` apply that setting.
@MainActor
final class SongTagResolutionTests: XCTestCase {

    private func song(
        artist: String? = "Alpha Trio",
        albumArtist: String? = "Singer X",
        grouping: String? = "Group A"
    ) -> Song {
        makeSong(
            id: 1,
            path: "/Music/1.flac",
            title: "Poema",
            artist: artist,
            albumArtist: albumArtist,
            grouping: grouping
        )
    }

    // MARK: - rawTagValue

    func testRawTagValueReturnsTheDesignatedField() {
        let song = song()

        XCTAssertEqual(song.rawTagValue(for: .artist), "Alpha Trio")
        XCTAssertEqual(song.rawTagValue(for: .albumArtist), "Singer X")
        XCTAssertEqual(song.rawTagValue(for: .grouping), "Group A")
    }

    func testRawTagValueOfAnUnsetFieldIsNil() {
        let song = song(artist: nil, albumArtist: nil, grouping: nil)

        for source in TagSource.allCases {
            XCTAssertNil(song.rawTagValue(for: source), source.rawValue)
        }
    }

    // MARK: - resolved Orchestra / Singer

    func testDefaultSettingsTakeOrchestraFromArtistAndSingerFromAlbumArtist() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = song()

            XCTAssertEqual(song.resolvedOrchestra(using: settings), "Alpha Trio")
            XCTAssertEqual(song.resolvedSinger(using: settings), "Singer X")
        }
    }

    func testEveryCombinationOfSourcesIsHonored() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = song()

            for orchestra in TagSource.allCases {
                for singer in TagSource.allCases {
                    settings.orchestraSource = orchestra
                    settings.singerSource = singer

                    XCTAssertEqual(
                        song.resolvedOrchestra(using: settings),
                        song.rawTagValue(for: orchestra),
                        "orchestra from \(orchestra.rawValue)"
                    )
                    XCTAssertEqual(
                        song.resolvedSinger(using: settings),
                        song.rawTagValue(for: singer),
                        "singer from \(singer.rawValue)"
                    )
                }
            }
        }
    }

    func testOrchestraInGroupingAndSingerInArtist() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            settings.orchestraSource = .grouping
            settings.singerSource = .artist
            let song = song(artist: "Singer X", albumArtist: "ignored", grouping: "Alpha Trio")

            XCTAssertEqual(song.resolvedOrchestra(using: settings), "Alpha Trio")
            XCTAssertEqual(song.resolvedSinger(using: settings), "Singer X")
        }
    }

    func testOrchestraAndSingerMayShareOneSource() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            settings.orchestraSource = .artist
            settings.singerSource = .artist

            XCTAssertEqual(song().resolvedOrchestra(using: settings), "Alpha Trio")
            XCTAssertEqual(song().resolvedSinger(using: settings), "Alpha Trio")
        }
    }

    func testAMissingFieldDoesNotFallBackToAnotherField() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = song(artist: nil, albumArtist: nil, grouping: "Group A")

            XCTAssertNil(song.resolvedOrchestra(using: settings))
            XCTAssertNil(song.resolvedSinger(using: settings))
        }
    }

    func testAnEmptyFieldStaysEmptyAndIsNotReplaced() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = song(artist: "", albumArtist: "")

            XCTAssertEqual(song.resolvedOrchestra(using: settings), "")
            XCTAssertEqual(song.resolvedSinger(using: settings), "")
        }
    }

    func testChangingTheSettingChangesTheResultImmediately() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = song()

            XCTAssertEqual(song.resolvedOrchestra(using: settings), "Alpha Trio")

            settings.orchestraSource = .albumArtist

            XCTAssertEqual(song.resolvedOrchestra(using: settings), "Singer X")
        }
    }
}
