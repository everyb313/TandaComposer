import XCTest
import Foundation

/// Swift compares Strings by canonical equivalence ("e" + U+0301 == "é"),
/// so these tests compare the UTF-8 bytes to see what was really stored.
@MainActor
final class PathNormalizerTests: XCTestCase {

    private func bytes(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }

    func testDecomposedAccentsBecomePrecomposed() {
        let decomposed = "Cafe\u{0301}"      // "e" + combining acute
        let composed = "Caf\u{00E9}"         // precomposed "é"

        XCTAssertNotEqual(bytes(decomposed), bytes(composed), "fixture must really differ in bytes")
        XCTAssertEqual(bytes(PathNormalizer.normalize(decomposed)), bytes(composed))
    }

    func testPrecomposedStringStaysUnchanged() {
        let composed = "/Music/M\u{00FC}ller - Tango.flac"
        XCTAssertEqual(bytes(PathNormalizer.normalize(composed)), bytes(composed))
    }

    func testDecomposedAndPrecomposedPathsGetIdenticalKeys() {
        let fromDecomposed = PathNormalizer.normalize("/Music/Mu\u{0308}ller - Tango.flac")
        let fromComposed = PathNormalizer.normalize("/Music/M\u{00FC}ller - Tango.flac")

        XCTAssertEqual(bytes(fromDecomposed), bytes(fromComposed))
    }

    func testNormalizationIsIdempotent() {
        let once = PathNormalizer.normalize("/Music/Pugliese - La Yumba \u{00E9}\u{0301}.flac")
        let twice = PathNormalizer.normalize(once)

        XCTAssertEqual(bytes(once), bytes(twice))
    }

    func testPlainASCIIPathIsUnchanged() {
        XCTAssertEqual(PathNormalizer.normalize("/Music/a.flac"), "/Music/a.flac")
    }

    func testURLNormalizationRemovesDotDotComponents() {
        let url = URL(fileURLWithPath: "/Music/Album/../Album/song.flac")
        XCTAssertEqual(PathNormalizer.normalize(url), "/Music/Album/song.flac")
    }

    func testURLNormalizationComposesAccents() {
        let url = URL(fileURLWithPath: "/Music/Mu\u{0308}ller.flac")
        XCTAssertEqual(
            bytes(PathNormalizer.normalize(url)),
            bytes("/Music/M\u{00FC}ller.flac")
        )
    }
}
