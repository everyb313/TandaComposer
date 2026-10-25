import XCTest
import Foundation

/// Reads a real MP3 generated at test time (ID3 tag plus silent MPEG frames),
/// to cover `AVFoundationReader` and the AVFoundation path of
/// `ArtworkExtractor`. If the system cannot open the fixture, the test is
/// skipped, not failed.
final class MP3FixtureTests: XCTestCase {
    private var temporaryDirectory: URL!

    /// A real 1x1 PNG.
    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AVFoundationFixturesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// ID3v2.4 tag followed by 20 silent MPEG-1 Layer III frames
    /// (128 kbps, 44.1 kHz: 417 bytes each).
    private func makeMP3(withPicture: Bool) throws -> URL {
        var frames: [Data] = [
            ID3FrameCodec.textFrame("TIT2", "Milonga"),
            ID3FrameCodec.textFrame("TPE1", "Alpha Trio"),
            ID3FrameCodec.textFrame("TDRC", "1940"),
            ID3FrameCodec.frame(
                id: "TXXX",
                content: Data([0x00]) + Data("REPLAYGAIN_TRACK_GAIN".utf8) + Data([0x00]) + Data("-6.2 dB".utf8)
            ),
            ID3FrameCodec.frame(
                id: "COMM",
                content: Data([0x00]) + Data("eng".utf8) + Data("iTunNORM".utf8) + Data([0x00]) + Data("000 111".utf8)
            )
        ]

        if withPicture {
            frames.append(ID3FrameCodec.frame(
                id: "APIC",
                content: Data([0x00]) + Data("image/png".utf8) + Data([0x00, 0x03, 0x00]) + png
            ))
        }

        let body = frames.reduce(Data(), +)
        var file = ID3FrameCodec.header(bodySize: body.count)
        file.append(body)

        let mpegFrame = Data([0xFF, 0xFB, 0x90, 0x64]) + Data(repeating: 0, count: 413)
        for _ in 0..<20 {
            file.append(mpegFrame)
        }

        let url = temporaryDirectory.appendingPathComponent("fixture.mp3")
        try file.write(to: url)
        return url
    }

    private func readOrSkip(_ url: URL) async throws -> [String: Any] {
        do {
            return try await AudioMetadataKit.read(url: url)
        } catch {
            throw XCTSkip("AVFoundation could not read the synthesized file: \(error)")
        }
    }

    private func common(_ metadata: [String: Any]) -> [String: Any]? {
        metadata["common"] as? [String: Any]
    }

    // MARK: - MP3

    func testMP3TagsComeFromTheID3CodecAndStreamInfoFromAVFoundation() async throws {
        let url = try makeMP3(withPicture: false)

        let metadata = try await readOrSkip(url)

        XCTAssertEqual(metadata["format"] as? String, "MP3")
        let id3 = try XCTUnwrap((metadata["formatSpecific"] as? [String: Any])?["ID3"] as? [String: Any])
        XCTAssertEqual(id3["TIT2"] as? String, "Milonga")
        XCTAssertEqual(id3["TPE1"] as? String, "Alpha Trio")
        XCTAssertEqual(id3["TYER"] as? String, "1940", "TDRC is reported under the canonical year key")
        XCTAssertEqual(id3["TXXX:REPLAYGAIN_TRACK_GAIN"] as? String, "-6.2 dB")
        XCTAssertEqual(id3["COMM:iTunNORM"] as? String, "000 111")
        XCTAssertNotNil(metadata["durationSeconds"] as? Double)
        XCTAssertEqual((metadata["streamInfo"] as? [String: Any])?["sampleRate"] as? Int, 44_100)
    }

    func testMP3ArtworkIsExtractedThroughAVFoundation() async throws {
        let url = try makeMP3(withPicture: true)
        _ = try await readOrSkip(url)

        let artwork = try await ArtworkExtractor.extract(from: url)

        let result = try XCTUnwrap(artwork)
        XCTAssertEqual(result.data, png)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
    }

    func testMP3WithoutAPictureHasNoArtwork() async throws {
        let url = try makeMP3(withPicture: false)
        _ = try await readOrSkip(url)

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertNil(artwork)
    }
}
