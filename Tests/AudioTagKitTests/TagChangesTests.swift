
import XCTest
//@testable import TandaComposer

final class TagChangesTests: XCTestCase {

    func testDefaultChangesAreEmpty() {
        let changes = TagChanges()

        XCTAssertTrue(changes.isEmpty)
    }

    func testEachIndividualFieldMakesChangesNonEmpty() {
        let cases: [(String, TagChanges)] = [
            ("title", TagChanges(title: "Title")),
            ("artist", TagChanges(artist: "Artist")),
            ("albumArtist", TagChanges(albumArtist: "Album Artist")),
            ("album", TagChanges(album: "Album")),
            ("genre", TagChanges(genre: "Jazz")),
            ("track", TagChanges(track: "3")),
            ("year", TagChanges(year: "2026")),
            ("comment", TagChanges(comment: "Test comment"))
        ]

        for (field, changes) in cases {
            XCTAssertFalse(
                changes.isEmpty,
                "Setting \(field) should make TagChanges non-empty."
            )
        }
    }

    func testAllFieldsCanBeSetTogether() {
        let changes = TagChanges(
            title: "Test Title",
            artist: "Test Artist",
            albumArtist: "Test Album Artist",
            album: "Test Album",
            genre: "Jazz",
            track: "3",
            year: "2026",
            comment: "Test Comment"
        )

        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(changes.title, "Test Title")
        XCTAssertEqual(changes.artist, "Test Artist")
        XCTAssertEqual(changes.albumArtist, "Test Album Artist")
        XCTAssertEqual(changes.album, "Test Album")
        XCTAssertEqual(changes.genre, "Jazz")
        XCTAssertEqual(changes.track, "3")
        XCTAssertEqual(changes.year, "2026")
        XCTAssertEqual(changes.comment, "Test Comment")
    }

    func testEmptyStringsStillCountAsSpecifiedChanges() {
        let changes = TagChanges(title: "")

        XCTAssertFalse(
            changes.isEmpty,
            "An empty string is still a specified value; only nil means unchanged."
        )
    }
}
