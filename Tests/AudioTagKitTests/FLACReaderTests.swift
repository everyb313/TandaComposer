import XCTest
import Foundation

final class FLACReaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testReadsVorbisCommentsAndFormat() async throws {
        let url = try makeFLAC(comments: [
            "TITLE": "Tango de prueba",
            "ARTIST": "Orquesta Ejemplo",
            "ALBUM": "En vivo",
            "TRACKNUMBER": "7"
        ])

        let metadata = try await FLACReader.read(url: url)
        let comments = try XCTUnwrap(metadata["vorbisComments"] as? [String: String])

        XCTAssertEqual(metadata["format"] as? String, "FLAC")
        XCTAssertEqual(comments["TITLE"], "Tango de prueba")
        XCTAssertEqual(comments["ARTIST"], "Orquesta Ejemplo")
        XCTAssertEqual(comments["ALBUM"], "En vivo")
        XCTAssertEqual(comments["TRACKNUMBER"], "7")
    }

    func testReadsStreamInfoAndDurationWhenSampleCountIsKnown() async throws {
        let url = try makeFLAC(comments: nil, streamInfo: streamInfo(sampleRate: 44_100, channels: 2, bitsPerSample: 16, totalSamples: 88_200))

        let metadata = try await FLACReader.read(url: url)
        let info = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])

        XCTAssertEqual(info["sampleRate"] as? Int, 44_100)
        XCTAssertEqual(info["channels"] as? Int, 2)
        XCTAssertEqual(info["bitsPerSample"] as? Int, 16)
        XCTAssertEqual(try XCTUnwrap(metadata["durationSeconds"] as? Double), 2.0, accuracy: 0.0001)
    }

    func testMissingCommentsAndUnknownDurationAreOmitted() async throws {
        let url = try makeFLAC(comments: nil, streamInfo: Data(repeating: 0, count: 34))

        let metadata = try await FLACReader.read(url: url)

        XCTAssertNil(metadata["vorbisComments"])
        XCTAssertNil(metadata["durationSeconds"])
        XCTAssertEqual(metadata["format"] as? String, "FLAC")
    }

    func testDetectsArtworkBlock() async throws {
        let url = try makeFLAC(comments: nil, extraBlocks: [
            FLACBlock(type: FLACBlocks.picture, data: Data([0, 0, 0, 0]))
        ])

        let metadata = try await FLACReader.read(url: url)

        XCTAssertEqual(metadata["hasArtwork"] as? Bool, true)
        XCTAssertNotNil(metadata["artworkInfo"])
    }

    func testMalformedFLACThrows() async throws {
        let url = temporaryDirectory.appendingPathComponent("broken.flac")
        try Data("fLaC\\x00".utf8).write(to: url)

        do {
            _ = try await FLACReader.read(url: url)
            XCTFail("Expected malformed FLAC data to throw.")
        } catch {
            // Expected: parser rejects truncated metadata.
        }
    }

    private func makeFLAC(
        comments: [String: String]?,
        streamInfo: Data? = nil,
        extraBlocks: [FLACBlock] = []
    ) throws -> URL {
        var blocks = [FLACBlock(type: FLACBlocks.streamInfo, data: streamInfo ?? Data(repeating: 0, count: 34))]
        if let comments {
            blocks.append(FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(comments)))
        }
        blocks.append(contentsOf: extraBlocks)
        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).flac")
        try FLACBlocks.serialize(blocks: blocks, audioData: Data([0xFF, 0xF8, 0x00, 0x01])).write(to: url)
        return url
    }

    private func streamInfo(sampleRate: Int, channels: Int, bitsPerSample: Int, totalSamples: Int) -> Data {
        var data = Data(repeating: 0, count: 34)
        data[10] = UInt8((sampleRate >> 12) & 0xFF)
        data[11] = UInt8((sampleRate >> 4) & 0xFF)
        data[12] = UInt8(((sampleRate & 0x0F) << 4) | (((channels - 1) & 0x07) << 1) | (((bitsPerSample - 1) >> 4) & 0x01))
        data[13] = UInt8((((bitsPerSample - 1) & 0x0F) << 4) | ((totalSamples >> 32) & 0x0F))
        data[14] = UInt8((totalSamples >> 24) & 0xFF)
        data[15] = UInt8((totalSamples >> 16) & 0xFF)
        data[16] = UInt8((totalSamples >> 8) & 0xFF)
        data[17] = UInt8(totalSamples & 0xFF)
        return data
    }
}
