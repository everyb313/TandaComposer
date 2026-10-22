import XCTest
import Foundation

final class CanonicalTagsP2Tests: XCTestCase {
    func testExtractsVorbisCommentsAndCommonAliases() {
        let tags = CanonicalTags.extract(from: [
            "vorbisComments": [
                "TITLE": "Title", "ARTIST": "Artist", "ALBUM": "Album",
                "ALBUM ARTIST": "Album Artist", "GENRE": "Jazz",
                "TRACKNUMBER": "03", "DATE": "2024", "COMMENT": "Note",
                "GROUPING": "Set"
            ]
        ])
        XCTAssertEqual(tags.title, "Title")
        XCTAssertEqual(tags.artist, "Artist")
        XCTAssertEqual(tags.album, "Album")
        XCTAssertEqual(tags.albumArtist, "Album Artist")
        XCTAssertEqual(tags.genre, "Jazz")
        XCTAssertEqual(tags.track, "03")
        XCTAssertEqual(tags.year, "2024")
        XCTAssertEqual(tags.comment, "Note")
        XCTAssertEqual(tags.grouping, "Set")
    }

    func testYearFallsBackToVorbisYearWhenDateMissing() {
        let tags = CanonicalTags.extract(from: ["vorbisComments": ["YEAR": "1999"]])
        XCTAssertEqual(tags.year, "1999")
    }

    func testAlbumArtistRecognizesSupportedAlternativeSpellings() {
        XCTAssertEqual(CanonicalTags.extract(from: ["vorbisComments": ["ALBUMARTIST": "A"]]).albumArtist, "A")
        XCTAssertEqual(CanonicalTags.extract(from: ["vorbisComments": ["ALBUM_ARTIST": "B"]]).albumArtist, "B")
    }

    func testExtractsCommonAndFormatSpecificFields() {
        let tags = CanonicalTags.extract(from: [
            "common": ["title": "Title", "artist": "Artist", "albumName": "Album", "description": "Comment"],
            "formatSpecific": [
                "id3 ": ["TCON": "Rock", "TRCK": "4/10", "TYER": "2001", "TPE2": "Band", "TIT1": "Group"]
            ]
        ])
        XCTAssertEqual(tags.title, "Title")
        XCTAssertEqual(tags.artist, "Artist")
        XCTAssertEqual(tags.album, "Album")
        XCTAssertEqual(tags.comment, "Comment")
        XCTAssertEqual(tags.genre, "Rock")
        XCTAssertEqual(tags.track, "4/10")
        XCTAssertEqual(tags.year, "2001")
        XCTAssertEqual(tags.albumArtist, "Band")
        XCTAssertEqual(tags.grouping, "Group")
    }

    func testEmptyMetadataProducesNilFieldsAndEmptyChanges() {
        let tags = CanonicalTags.extract(from: [:])
        XCTAssertNil(tags.title)
        XCTAssertNil(tags.artist)
        XCTAssertTrue(tags.asTagChanges().isEmpty)
    }

    func testGroupingIsNotCopiedIntoWritableTagChanges() {
        let tags = CanonicalTags.extract(from: ["vorbisComments": ["GROUPING": "Live set", "TITLE": "Song"]])
        let changes = tags.asTagChanges()
        XCTAssertEqual(changes.title, "Song")
        XCTAssertFalse(changes.isEmpty)
        // CanonicalTags.grouping is intentionally read-only and is not
        // represented by TagChanges, so there is no grouping property to assert here.
    }
}
