import XCTest
import Foundation

@MainActor
final class AudioFileSuffixTests: XCTestCase {

    func testKnownSuffixIsStripped() {
        let result = AudioFileSuffix.strip("Song.flac")

        XCTAssertEqual(result.stem, "Song")
        XCTAssertTrue(result.hadSuffix)
    }

    func testSuffixMatchingIsCaseInsensitive() {
        let result = AudioFileSuffix.strip("Song.FLAC")

        XCTAssertEqual(result.stem, "Song")
        XCTAssertTrue(result.hadSuffix)
    }

    func testOnlyTheLastSuffixIsStripped() {
        let result = AudioFileSuffix.strip("Alpha Trio - Song One.mp3")

        XCTAssertEqual(result.stem, "Alpha Trio - Song One")
        XCTAssertTrue(result.hadSuffix)
    }

    func testNameWithoutDotIsUnchanged() {
        let result = AudioFileSuffix.strip("Alpha Trio - Song One")

        XCTAssertEqual(result.stem, "Alpha Trio - Song One")
        XCTAssertFalse(result.hadSuffix)
    }

    func testDotInsideTitleIsNotASuffix() {
        for name in ["Alpha - Vol. 2", "A. Pugliese - Poema", "Song One.remastered"] {
            let result = AudioFileSuffix.strip(name)

            XCTAssertEqual(result.stem, name, name)
            XCTAssertFalse(result.hadSuffix, name)
        }
    }

    func testAllCommonAudioSuffixesAreKnown() {
        for ext in ["flac", "mp3", "m4a", "aiff", "aif", "wav", "ogg"] {
            XCTAssertTrue(AudioFileSuffix.known.contains(ext), ext)
        }
    }
}
