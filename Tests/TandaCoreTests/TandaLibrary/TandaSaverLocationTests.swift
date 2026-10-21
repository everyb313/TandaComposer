import XCTest
import Foundation

/// How a Tanda's songs decide its folder and file name:
/// `Tandas/<orchestra>/<singer>/<orchestra>_<genre>_<singer>.json`.
@MainActor
final class TandaSaverLocationTests: XCTestCase {

    private func song(
        _ id: Int64,
        artist: String?,
        albumArtist: String? = nil,
        genre: String? = nil,
        grouping: String? = nil
    ) -> Song {
        makeSong(
            id: id,
            path: "/Music/\(id).flac",
            title: "T\(id)",
            artist: artist,
            albumArtist: albumArtist,
            genre: genre,
            grouping: grouping
        )
    }

    private func fields(_ songs: [Song], settings: AppSettings) -> TandaSaver.ResolvedFields {
        TandaSaver.resolvedFields(for: songs, settings: settings)
    }

    // MARK: - resolvedFields

    func testSharedValuesAreUsed() throws {
        try withTemporaryAppRoot { _ in
            let songs = [
                song(1, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango"),
                song(2, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango"),
                song(3, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango")
            ]

            let resolved = fields(songs, settings: AppSettings())

            XCTAssertEqual(resolved.artist, "Alpha Trio")
            XCTAssertEqual(resolved.albumArtist, "Singer X")
            XCTAssertEqual(resolved.genre, "Tango")
        }
    }

    func testValuesThatDifferOnlyInCaseOrAccentsCountAsTheSame() throws {
        try withTemporaryAppRoot { _ in
            let songs = [
                song(1, artist: "Enrique Rodr\u{00ED}guez"),
                song(2, artist: "enrique rodriguez"),
                song(3, artist: "ENRIQUE RODR\u{00CD}GUEZ")
            ]

            XCTAssertEqual(fields(songs, settings: AppSettings()).artist, "Enrique Rodr\u{00ED}guez", "the first spelling is kept")
        }
    }

    func testDifferentValuesFallBackToTheVariousNames() throws {
        try withTemporaryAppRoot { _ in
            let songs = [
                song(1, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango"),
                song(2, artist: "Beta Band", albumArtist: "Singer Y", genre: "Vals"),
                song(3, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango")
            ]

            let resolved = fields(songs, settings: AppSettings())

            XCTAssertEqual(resolved.artist, "VariousOrchestras")
            XCTAssertEqual(resolved.albumArtist, "VariousSingers")
            XCTAssertEqual(resolved.genre, "VariousGenres")
        }
    }

    func testMissingValuesFallBackToTheUnknownNames() throws {
        try withTemporaryAppRoot { _ in
            let songs = [song(1, artist: nil), song(2, artist: "  "), song(3, artist: "")]

            let resolved = fields(songs, settings: AppSettings())

            XCTAssertEqual(resolved.artist, "Unknown Orchestra")
            XCTAssertEqual(resolved.genre, "Unknown Genre")
            XCTAssertEqual(resolved.albumArtist, "unknownOrchestra", "name of the unknown-singer folder as it is today")
        }
    }

    func testSongsWithoutAValueDoNotCountAgainstTheOthers() throws {
        try withTemporaryAppRoot { _ in
            let songs = [
                song(1, artist: "Alpha Trio", genre: "Tango"),
                song(2, artist: nil, genre: nil),
                song(3, artist: "alpha trio", genre: "tango")
            ]

            let resolved = fields(songs, settings: AppSettings())

            XCTAssertEqual(resolved.artist, "Alpha Trio")
            XCTAssertEqual(resolved.genre, "Tango")
        }
    }

    func testTheSettingsDecideWhichTagIsOrchestraAndSinger() throws {
        try withTemporaryAppRoot { _ in
            let songs = [
                song(1, artist: "Artist One", albumArtist: "Album One", grouping: "Group One"),
                song(2, artist: "Artist One", albumArtist: "Album One", grouping: "Group One"),
                song(3, artist: "Artist One", albumArtist: "Album One", grouping: "Group One")
            ]
            let settings = AppSettings()
            settings.orchestraSource = .grouping
            settings.singerSource = .artist

            let resolved = fields(songs, settings: settings)

            XCTAssertEqual(resolved.artist, "Group One")
            XCTAssertEqual(resolved.albumArtist, "Artist One")
        }
    }

    // MARK: - resolvedLocation

    func testLocationIsOrchestraFolderThenSingerFolderThenTheName() throws {
        try withTemporaryAppRoot { root in
            let songs = (1...3).map { song(Int64($0), artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango") }

            let location = TandaSaver.resolvedLocation(for: songs, settings: AppSettings())

            XCTAssertTrue(samePath(location.folder, root.appendingPathComponent("Default/Tandas/Alpha Trio/Singer X")))
            XCTAssertEqual(location.name, "Alpha Trio_Tango_Singer X")
        }
    }

    func testFolderNamesAreMadeFileSystemSafe() throws {
        try withTemporaryAppRoot { root in
            let songs = (1...3).map { song(Int64($0), artist: "Rodr\u{00ED}guez, Enrique", albumArtist: "AC/DC", genre: "Tango") }

            let location = TandaSaver.resolvedLocation(for: songs, settings: AppSettings())

            XCTAssertTrue(samePath(location.folder, root.appendingPathComponent("Default/Tandas/Rodriguez/AC-DC")))
            XCTAssertEqual(location.name, "Rodriguez_Tango_AC-DC")
        }
    }

    func testMixedTandasGoIntoTheVariousFolders() throws {
        try withTemporaryAppRoot { root in
            let songs = [
                song(1, artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango"),
                song(2, artist: "Beta Band", albumArtist: "Singer Y", genre: "Vals"),
                song(3, artist: "Gamma Sextet", albumArtist: "Singer Z", genre: "Milonga")
            ]

            let location = TandaSaver.resolvedLocation(for: songs, settings: AppSettings())

            XCTAssertTrue(samePath(location.folder, root.appendingPathComponent("Default/Tandas/VariousOrchestras/VariousSingers")))
            XCTAssertEqual(location.name, "VariousOrchestras_VariousGenres_VariousSingers")
        }
    }

    func testAnExistingFileMakesTheNameGetAnOrdinal() throws {
        try withTemporaryAppRoot { _ in
            let songs = (1...3).map { song(Int64($0), artist: "Alpha Trio", albumArtist: "Singer X", genre: "Tango") }
            let settings = AppSettings()
            let first = TandaSaver.resolvedLocation(for: songs, settings: settings)
            try FileManager.default.createDirectory(at: first.folder, withIntermediateDirectories: true)
            let existing = first.folder.appendingPathComponent(first.name).appendingPathExtension("json")
            try Data("{}".utf8).write(to: existing)

            XCTAssertEqual(TandaSaver.resolvedLocation(for: songs, settings: settings).name, "Alpha Trio_Tango_Singer X_2")
            XCTAssertEqual(
                TandaSaver.resolvedLocation(for: songs, settings: settings, excluding: existing).name,
                "Alpha Trio_Tango_Singer X",
                "a Tanda does not collide with its own file"
            )
        }
    }
}
