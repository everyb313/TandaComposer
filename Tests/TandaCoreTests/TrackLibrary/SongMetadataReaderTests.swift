import XCTest
import Foundation

/// Reads small hand-built FLAC files (see `makeFLACData`). Year, BPM and
/// replay gain parsing are private helpers of `SongMetadataReader`, so they
/// are tested through `readSong`.
@MainActor
final class SongMetadataReaderTests: XCTestCase {

    private func read(
        tags: [String: String] = [:],
        seconds: Int = 200,
        extraSamples: Int = 0,
        sampleRate: Int = 44_100,
        name: String = "song.flac"
    ) async throws -> Song {
        let dir = try makeTemporaryDirectory()
        let file = try writeData(
            makeFLACData(tags: tags, seconds: seconds, extraSamples: extraSamples, sampleRate: sampleRate),
            in: dir,
            named: name
        )
        return try await SongMetadataReader.readSong(at: file)
    }

    // MARK: - Tags and file facts

    func testReadsTagsFromTheVorbisComments() async throws {
        let song = try await read(tags: [
            "TITLE": "Poema",
            "ARTIST": "Alpha Trio",
            "ALBUMARTIST": "Singer X",
            "ALBUM": "Album One",
            "GENRE": "Tango",
            "GROUPING": "Group A",
            "COMMENT": "remark",
            "DATE": "1940-05-01"
        ])

        XCTAssertEqual(song.title, "Poema")
        XCTAssertEqual(song.artist, "Alpha Trio")
        XCTAssertEqual(song.albumArtist, "Singer X")
        XCTAssertEqual(song.album, "Album One")
        XCTAssertEqual(song.genre, "Tango")
        XCTAssertEqual(song.grouping, "Group A")
        XCTAssertEqual(song.comment, "remark")
        XCTAssertEqual(song.year, 1940)
    }

    func testFileFactsComeFromTheFile() async throws {
        let dir = try makeTemporaryDirectory().resolvingSymlinksInPath()
        let data = makeFLACData(tags: ["TITLE": "T"], seconds: 200, audioBytes: 1000)
        let file = try writeData(data, in: dir, named: "Poema.FLAC")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modified = try XCTUnwrap(attributes[.modificationDate] as? Date)

        let expectedHash = try await FileHasher.sha256(fileURL: file)

        let song = try await SongMetadataReader.readSong(at: file)

        XCTAssertEqual(song.filename, "Poema.FLAC")
        XCTAssertEqual(song.path, file.path)
        XCTAssertEqual(song.normalizedPath, PathNormalizer.normalize(file))
        XCTAssertEqual(song.fileType, "FLAC", "upper-cased extension")
        XCTAssertEqual(song.fileSize, Int64(data.count))
        XCTAssertEqual(song.fileSizeAtScan, Int64(data.count))
        XCTAssertEqual(song.lastModified, Int(modified.timeIntervalSince1970))
        XCTAssertEqual(song.fileModificationDateAtScan.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(song.fileHash, expectedHash)
        XCTAssertNil(song.id)
        XCTAssertNil(song.key, "the key is deliberately never read from the file")
    }

    func testDurationAndSampleRate() async throws {
        let song = try await read(seconds: 200, sampleRate: 48_000)

        XCTAssertEqual(song.duration, 200)
        XCTAssertEqual(song.sampleRate, 48_000)
    }

    func testDurationIsRoundedToTheNearestSecond() async throws {
        let up = try await read(seconds: 10, extraSamples: 22_050)      // 10.5 s
        XCTAssertEqual(up.duration, 11)

        let down = try await read(seconds: 10, extraSamples: 11_025)    // 10.25 s
        XCTAssertEqual(down.duration, 10)
    }

    func testFileWithoutTagsStillReads() async throws {
        let song = try await read(tags: [:])

        XCTAssertNil(song.title)
        XCTAssertNil(song.artist)
        XCTAssertNil(song.year)
        XCTAssertNil(song.bpm)
        XCTAssertNil(song.replayGain)
        XCTAssertEqual(song.duration, 200)
    }

    func testAlbumArtistAlsoAcceptsTheOtherSpellings() async throws {
        let spaced = try await read(tags: ["ALBUM ARTIST": "Singer A"])
        XCTAssertEqual(spaced.albumArtist, "Singer A")

        let underscored = try await read(tags: ["ALBUM_ARTIST": "Singer B"])
        XCTAssertEqual(underscored.albumArtist, "Singer B")
    }

    // MARK: - Year

    func testYearParsing() async throws {
        let cases: [(String, Int?)] = [
            ("1940", 1940),
            ("1940-05-01", 1940),
            ("2024-xx", 2024),
            ("1861", 1861),
            ("2100", 2100),
            ("1860", nil),
            ("2101", nil),
            ("40", nil),
            ("abcd", nil),
            ("19x0", nil),
            (" 1940", nil),
            ("", nil)
        ]

        for (raw, expected) in cases {
            let song = try await read(tags: ["DATE": raw])
            XCTAssertEqual(song.year, expected, "DATE=\"\(raw)\"")
        }
    }

    func testYearFallsBackToTheYearTag() async throws {
        let song = try await read(tags: ["YEAR": "1950"])

        XCTAssertEqual(song.year, 1950)
    }

    func testDateWinsOverYear() async throws {
        let song = try await read(tags: ["DATE": "1940", "YEAR": "1950"])

        XCTAssertEqual(song.year, 1940)
    }

    // MARK: - BPM and replay gain

    func testBPM() async throws {
        let valid = try await read(tags: ["BPM": "111.5"])
        XCTAssertEqual(valid.bpm, 111.5)

        let whole = try await read(tags: ["BPM": "120"])
        XCTAssertEqual(whole.bpm, 120)

        let invalid = try await read(tags: ["BPM": "fast"])
        XCTAssertNil(invalid.bpm)
    }

    func testReplayGainWithAndWithoutUnit() async throws {
        let cases: [(String, Double?)] = [
            ("-7.25 dB", -7.25),
            ("-7.25dB", -7.25),
            ("-7.25 db", -7.25),
            ("+3.1 dB", 3.1),
            ("0", 0),
            ("loud", nil)
        ]

        for (raw, expected) in cases {
            let song = try await read(tags: ["REPLAYGAIN_TRACK_GAIN": raw])
            XCTAssertEqual(song.replayGain, expected, "REPLAYGAIN_TRACK_GAIN=\"\(raw)\"")
        }
    }

    // MARK: - Errors

    func testAFileThatIsNotReallyFLACThrows() async throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("this is not audio", in: dir, named: "fake.flac")

        do {
            _ = try await SongMetadataReader.readSong(at: file)
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }

    func testAMissingFileThrows() async throws {
        let dir = try makeTemporaryDirectory()

        do {
            _ = try await SongMetadataReader.readSong(at: dir.appendingPathComponent("nope.flac"))
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }
}
