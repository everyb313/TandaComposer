import XCTest
import Foundation

/// The pure lookups `SongMetadataReader` runs over the raw metadata
/// dictionary a format reader returns: BPM, sample rate and track gain.
///
/// NEEDS `extractBPM`, `extractSampleRate` and `extractReplayGain` to lose
/// their `private` (see README_TESTS.md).
@MainActor
final class SongMetadataExtractorTests: XCTestCase {

    // MARK: - extractBPM

    func testBPMFromVorbisComments() {
        XCTAssertEqual(SongMetadataReader.extractBPM(from: ["vorbisComments": ["BPM": "128"]]), 128)
        XCTAssertEqual(SongMetadataReader.extractBPM(from: ["vorbisComments": ["BPM": "127.5"]]), 127.5)
    }

    func testBPMFromAnyFormatSpecificContainer() {
        let metadata: [String: Any] = ["formatSpecific": ["ID3": ["TBPM": "120"]]]

        XCTAssertEqual(SongMetadataReader.extractBPM(from: metadata), 120)
    }

    func testVorbisBPMWinsOverFormatSpecific() {
        let metadata: [String: Any] = [
            "vorbisComments": ["BPM": "100"],
            "formatSpecific": ["ID3": ["TBPM": "120"]]
        ]

        XCTAssertEqual(SongMetadataReader.extractBPM(from: metadata), 100)
    }

    func testAnUnparsableVorbisBPMIsNilAndDoesNotFallBack() {
        let metadata: [String: Any] = [
            "vorbisComments": ["BPM": "fast"],
            "formatSpecific": ["ID3": ["TBPM": "120"]]
        ]

        XCTAssertNil(SongMetadataReader.extractBPM(from: metadata))
    }

    func testAnUnparsableOrNonTextTBPMIsSkipped() {
        XCTAssertNil(SongMetadataReader.extractBPM(from: ["formatSpecific": ["ID3": ["TBPM": "fast"]]]))
        XCTAssertNil(SongMetadataReader.extractBPM(from: ["formatSpecific": ["ID3": ["TBPM": 120]]]))
    }

    func testBPMIsNilWithoutAnySource() {
        XCTAssertNil(SongMetadataReader.extractBPM(from: [:]))
        XCTAssertNil(SongMetadataReader.extractBPM(from: ["vorbisComments": ["TITLE": "x"]]))
        XCTAssertNil(SongMetadataReader.extractBPM(from: ["formatSpecific": ["ID3": ["TIT2": "x"]]]))
    }

    // MARK: - extractSampleRate

    func testSampleRateFromStreamInfo() {
        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: ["streamInfo": ["sampleRate": 44_100]]), 44_100)
    }

    func testSampleRateGivenAsADoubleIsRounded() {
        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: ["streamInfo": ["sampleRate": 44_099.6]]), 44_100)
        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: ["sampleRate": 48_000.4]), 48_000)
    }

    func testTopLevelSampleRate() {
        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: ["sampleRate": 96_000]), 96_000)
    }

    func testSampleRateFromFormatSpecific() {
        XCTAssertEqual(
            SongMetadataReader.extractSampleRate(from: ["formatSpecific": ["AIFF": ["sampleRate": 48_000]]]),
            48_000
        )
        XCTAssertEqual(
            SongMetadataReader.extractSampleRate(from: ["formatSpecific": ["AIFF": ["sampleRate": 44_100.0]]]),
            44_100
        )
    }

    func testSampleRatePrefersStreamInfoThenTopLevelThenFormatSpecific() {
        let all: [String: Any] = [
            "streamInfo": ["sampleRate": 1],
            "sampleRate": 2,
            "formatSpecific": ["X": ["sampleRate": 3]]
        ]
        let noStream: [String: Any] = [
            "sampleRate": 2,
            "formatSpecific": ["X": ["sampleRate": 3]]
        ]

        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: all), 1)
        XCTAssertEqual(SongMetadataReader.extractSampleRate(from: noStream), 2)
    }

    func testSampleRateIsNilWhenMissingOrNotANumber() {
        XCTAssertNil(SongMetadataReader.extractSampleRate(from: [:]))
        XCTAssertNil(SongMetadataReader.extractSampleRate(from: ["streamInfo": ["sampleRate": "44100"]]))
        XCTAssertNil(SongMetadataReader.extractSampleRate(from: ["sampleRate": "44100"]))
        XCTAssertNil(SongMetadataReader.extractSampleRate(from: ["streamInfo": ["bitsPerSample": 16]]))
    }

    // MARK: - extractReplayGain

    func testReplayGainFromVorbisComments() {
        XCTAssertEqual(
            SongMetadataReader.extractReplayGain(from: ["vorbisComments": ["REPLAYGAIN_TRACK_GAIN": "-7.5 dB"]]),
            -7.5
        )
        XCTAssertEqual(
            SongMetadataReader.extractReplayGain(from: ["vorbisComments": ["R128_TRACK_GAIN": "-3"]]),
            -3
        )
    }

    func testR128WinsOverReplayGainInVorbisComments() {
        let metadata: [String: Any] = [
            "vorbisComments": ["REPLAYGAIN_TRACK_GAIN": "-7.5 dB", "R128_TRACK_GAIN": "-3"]
        ]

        XCTAssertEqual(SongMetadataReader.extractReplayGain(from: metadata), -3)
    }

    func testReplayGainTextIsTolerant() {
        for (text, expected) in [("  -2.0 DB ", -2.0), ("+1.5 dB", 1.5), ("-4.25dB", -4.25), ("0", 0.0)] {
            XCTAssertEqual(
                SongMetadataReader.extractReplayGain(from: ["vorbisComments": ["REPLAYGAIN_TRACK_GAIN": text]]),
                expected,
                text
            )
        }
    }

    func testReplayGainFromID3UserTextFrame() {
        let metadata: [String: Any] = ["formatSpecific": ["ID3": ["TXXX:REPLAYGAIN_TRACK_GAIN": "-6.2 dB"]]]

        XCTAssertEqual(SongMetadataReader.extractReplayGain(from: metadata), -6.2)
    }

    func testReplayGainKeyMatchIgnoresCaseAndPrefix() {
        let metadata: [String: Any] = ["formatSpecific": ["ID3": ["txxx:replaygain_track_gain": "-1.0 dB"]]]

        XCTAssertEqual(SongMetadataReader.extractReplayGain(from: metadata), -1.0)
    }

    func testAnUnparsableVorbisValueFallsThroughToFormatSpecific() {
        let metadata: [String: Any] = [
            "vorbisComments": ["REPLAYGAIN_TRACK_GAIN": "loud"],
            "formatSpecific": ["ID3": ["TXXX:REPLAYGAIN_TRACK_GAIN": "-5.0 dB"]]
        ]

        XCTAssertEqual(SongMetadataReader.extractReplayGain(from: metadata), -5.0)
    }

    func testAlbumGainIsNotTrackGain() {
        let metadata: [String: Any] = [
            "vorbisComments": ["REPLAYGAIN_ALBUM_GAIN": "-9 dB"],
            "formatSpecific": ["ID3": ["TXXX:REPLAYGAIN_ALBUM_GAIN": "-9 dB"]]
        ]

        XCTAssertNil(SongMetadataReader.extractReplayGain(from: metadata))
    }

    func testNonTextAndUnparsableFormatSpecificValuesAreSkipped() {
        XCTAssertNil(SongMetadataReader.extractReplayGain(from: ["formatSpecific": ["ID3": ["TXXX:REPLAYGAIN_TRACK_GAIN": -6.2]]]))
        XCTAssertNil(SongMetadataReader.extractReplayGain(from: ["formatSpecific": ["ID3": ["TXXX:REPLAYGAIN_TRACK_GAIN": "n/a"]]]))
    }

    func testReplayGainIsNilWithoutAnySource() {
        XCTAssertNil(SongMetadataReader.extractReplayGain(from: [:]))
    }
}
