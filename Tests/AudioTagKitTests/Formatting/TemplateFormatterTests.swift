import XCTest
import Foundation

final class TemplateFormatterP2Tests: XCTestCase {
    func testSubstitutesTokensCaseInsensitively() {
        let rows = [MetadataRow(group: "Common", key: "title", value: "Blue Train")]
        XCTAssertEqual(TemplateFormatter.apply("{TITLE} — {title}", to: rows), "Blue Train — Blue Train")
    }

    func testMissingTokenBecomesEmptyString() {
        XCTAssertEqual(TemplateFormatter.apply("{title}/{missing}", to: [
            MetadataRow(group: "Common", key: "title", value: "Song")
        ]), "Song/")
    }

    func testPreservesUnclosedOpeningBraceAndRemainder() {
        XCTAssertEqual(TemplateFormatter.apply("track-{title}-{unfinished", to: [
            MetadataRow(group: "Common", key: "title", value: "Song")
        ]), "track-Song-{unfinished")
    }

    func testRepeatedTokensAreSubstituted() {
        let rows = [MetadataRow(group: "ID3", key: "artist", value: "Artist")]
        XCTAssertEqual(TemplateFormatter.apply("{artist}/{artist}/{ARTIST}", to: rows), "Artist/Artist/Artist")
    }

    func testFirstMatchingKeyWinsAcrossGroups() {
        let rows = [
            MetadataRow(group: "VorbisComment", key: "title", value: "First"),
            MetadataRow(group: "Common", key: "TITLE", value: "Second")
        ]
        XCTAssertEqual(TemplateFormatter.apply("{title}", to: rows), "First")
    }
}
