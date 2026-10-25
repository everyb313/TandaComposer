import XCTest
import Foundation

/// What `AIFFReader` surfaces from the COMM chunk, from the embedded ID3 tag
/// (by frame kind) and from AIFF's own NAME/AUTH/ANNO chunks.
final class AIFFReaderFramesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIFFReaderFramesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func be32(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ]
    }

    private func comm(frames: Int, rate: [UInt8]) -> AIFFChunk {
        var data = Data([0x00, 0x02])
        data.append(contentsOf: be32(frames))
        data.append(contentsOf: [0x00, 0x10])
        data.append(contentsOf: rate)
        return AIFFChunk(id: "COMM", data: data)
    }

    private let rate44100: [UInt8] = [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]

    private func id3(_ frames: [Data]) -> AIFFChunk {
        let body = frames.reduce(Data(), +)
        var tag = ID3FrameCodec.header(bodySize: body.count)
        tag.append(body)
        return AIFFChunk(id: "ID3 ", data: tag)
    }

    private func read(_ chunks: [AIFFChunk]) async throws -> [String: Any] {
        let url = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
        try AIFFChunks.serialize(formType: "AIFF", chunks: chunks).write(to: url)

        return try await AIFFReader.read(url: url)
    }

    private func id3Fields(_ metadata: [String: Any]) throws -> [String: Any] {
        let formatSpecific = try XCTUnwrap(metadata["formatSpecific"] as? [String: Any])
        return try XCTUnwrap(formatSpecific["ID3"] as? [String: Any])
    }

    private func commonFields(_ metadata: [String: Any]) -> [String: Any]? {
        metadata["common"] as? [String: Any]
    }

    private func userText(_ description: String, _ value: String) -> Data {
        ID3FrameCodec.frame(
            id: "TXXX",
            content: Data([0x00]) + Data(description.utf8) + Data([0x00]) + Data(value.utf8)
        )
    }

    private func describedComment(_ description: String, _ value: String) -> Data {
        ID3FrameCodec.frame(
            id: "COMM",
            content: Data([0x00]) + Data("eng".utf8) + Data(description.utf8) + Data([0x00]) + Data(value.utf8)
        )
    }

    // MARK: - COMM chunk

    func testSampleRatesAreDecodedFromTheExtendedFloat() async throws {
        let cases: [(rate: [UInt8], hertz: Int)] = [
            ([0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0], 44_100),
            ([0x40, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0], 48_000),
            ([0x40, 0x0F, 0xBB, 0x80, 0, 0, 0, 0, 0, 0], 96_000),
            ([0x40, 0x0D, 0xAC, 0x44, 0, 0, 0, 0, 0, 0], 22_050)
        ]

        for entry in cases {
            let metadata = try await read([comm(frames: entry.hertz, rate: entry.rate)])
            let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])

            XCTAssertEqual(streamInfo["sampleRate"] as? Int, entry.hertz)
            XCTAssertEqual(streamInfo["channels"] as? Int, 2)
            XCTAssertEqual(streamInfo["bitsPerSample"] as? Int, 16)
            XCTAssertEqual(metadata["durationSeconds"] as? Double, 1.0, "\(entry.hertz) Hz")
        }
    }

    func testNoSampleFramesMeansNoDuration() async throws {
        let metadata = try await read([comm(frames: 0, rate: rate44100)])

        let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])
        XCTAssertEqual(streamInfo["sampleRate"] as? Int, 44_100)
        XCTAssertNil(streamInfo["durationSeconds"])
        XCTAssertNil(metadata["durationSeconds"])
    }

    func testAZeroSampleRateMeansNoDuration() async throws {
        let metadata = try await read([comm(frames: 1000, rate: [UInt8](repeating: 0, count: 10))])

        let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])
        XCTAssertEqual(streamInfo["sampleRate"] as? Int, 0)
        XCTAssertNil(metadata["durationSeconds"])
    }

    func testACommChunkThatIsTooShortGivesNoStreamDetails() async throws {
        let metadata = try await read([AIFFChunk(id: "COMM", data: Data(repeating: 0, count: 10))])

        let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])
        XCTAssertTrue(streamInfo.isEmpty)
        XCTAssertNil(metadata["durationSeconds"])
    }

    func testWithoutACommChunkThereIsNoStreamInfo() async throws {
        let metadata = try await read([id3([ID3FrameCodec.textFrame("TIT2", "Title")])])

        XCTAssertNil(metadata["streamInfo"])
    }

    // MARK: - ID3 frames

    func testUserTextFramesAreKeyedByTheirDescription() async throws {
        let metadata = try await read([
            id3([userText("REPLAYGAIN_TRACK_GAIN", "-6.2 dB"), userText("MOOD", "calm")])
        ])

        let fields = try id3Fields(metadata)
        XCTAssertEqual(fields["TXXX:REPLAYGAIN_TRACK_GAIN"] as? String, "-6.2 dB")
        XCTAssertEqual(fields["TXXX:MOOD"] as? String, "calm")
    }

    func testAUserTextFrameWithoutADescriptionIsKeyedTXXX() async throws {
        let metadata = try await read([id3([userText("", "bare")])])

        XCTAssertEqual(try id3Fields(metadata)["TXXX"] as? String, "bare")
    }

    func testOnlyAPlainCommentIsTheCanonicalComment() async throws {
        let metadata = try await read([
            id3([ID3FrameCodec.commentFrame("Plain note"), describedComment("iTunNORM", "000 111")])
        ])

        let fields = try id3Fields(metadata)
        XCTAssertEqual(fields["COMM"] as? String, "Plain note")
        XCTAssertEqual(fields["COMM:iTunNORM"] as? String, "000 111")
        XCTAssertEqual(commonFields(metadata)?["description"] as? String, "Plain note")
    }

    func testADescribedCommentAloneIsNotTheCanonicalComment() async throws {
        let metadata = try await read([id3([describedComment("iTunNORM", "000 111")])])

        XCTAssertEqual(try id3Fields(metadata)["COMM:iTunNORM"] as? String, "000 111")
        XCTAssertNil(commonFields(metadata)?["description"])
    }

    func testTDRCWinsOverTYERInEitherOrder() async throws {
        let tdrcFirst = try await read([
            id3([ID3FrameCodec.textFrame("TDRC", "2025"), ID3FrameCodec.textFrame("TYER", "1999")])
        ])
        let tyerFirst = try await read([
            id3([ID3FrameCodec.textFrame("TYER", "1999"), ID3FrameCodec.textFrame("TDRC", "2025")])
        ])

        XCTAssertEqual(try id3Fields(tdrcFirst)["TYER"] as? String, "2025")
        XCTAssertEqual(try id3Fields(tyerFirst)["TYER"] as? String, "2025")
    }

    func testALegacyTYERAloneIsReported() async throws {
        let metadata = try await read([id3([ID3FrameCodec.textFrame("TYER", "1999")])])

        XCTAssertEqual(try id3Fields(metadata)["TYER"] as? String, "1999")
    }

    func testOtherTextFramesAreSurfaced() async throws {
        let metadata = try await read([
            id3([ID3FrameCodec.textFrame("TCON", "Tango"), ID3FrameCodec.textFrame("TRCK", "3/12")])
        ])

        let fields = try id3Fields(metadata)
        XCTAssertEqual(fields["TCON"] as? String, "Tango")
        XCTAssertEqual(fields["TRCK"] as? String, "3/12")
    }

    func testFramesThatAreNeitherTextNorPictureAreSummarizedBySize() async throws {
        let metadata = try await read([
            id3([ID3FrameCodec.frame(id: "PRIV", content: Data([1, 2, 3, 4, 5]))])
        ])

        XCTAssertEqual(try id3Fields(metadata)["PRIV"] as? String, "<binary, 5 bytes>")
    }

    // MARK: - Native AIFF chunks

    func testNativeChunksAreUsedWhenThereIsNoID3Tag() async throws {
        let metadata = try await read([
            AIFFChunk(id: "NAME", data: Data("Native title".utf8)),
            AIFFChunk(id: "AUTH", data: Data("Native artist".utf8)),
            AIFFChunk(id: "ANNO", data: Data("Native note".utf8))
        ])

        let common = try XCTUnwrap(commonFields(metadata))
        XCTAssertEqual(common["title"] as? String, "Native title")
        XCTAssertEqual(common["artist"] as? String, "Native artist")
        XCTAssertEqual(common["description"] as? String, "Native note")
        XCTAssertNil(metadata["formatSpecific"])
    }

    func testAnID3TagTakesPriorityOverNativeChunks() async throws {
        let metadata = try await read([
            AIFFChunk(id: "NAME", data: Data("Native title".utf8)),
            AIFFChunk(id: "AUTH", data: Data("Native artist".utf8)),
            id3([ID3FrameCodec.textFrame("TIT2", "ID3 title")])
        ])

        let common = try XCTUnwrap(commonFields(metadata))
        XCTAssertEqual(common["title"] as? String, "ID3 title")
        XCTAssertNil(common["artist"], "the native AUTH chunk is ignored once an ID3 tag exists")
    }

    func testAFileWithoutAnyMetadataHasNoCommonFields() async throws {
        let metadata = try await read([AIFFChunk(id: "SSND", data: Data(repeating: 0, count: 8))])

        XCTAssertNil(metadata["common"])
        XCTAssertNil(metadata["formatSpecific"])
        XCTAssertEqual(metadata["format"] as? String, "AIFF")
    }
}
