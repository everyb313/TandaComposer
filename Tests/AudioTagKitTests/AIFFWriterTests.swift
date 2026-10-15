import XCTest
import Foundation

final class AIFFWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIFFWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testWriteAddsID3ChunkAndPreservesSoundAndCustomChunks() async throws {
        let sound = Data([0x10, 0x20, 0x30, 0x40])
        let custom = Data([0xCA, 0xFE, 0xBA])
        let url = try makeAIFF(sound: sound, extraChunks: [AIFFChunk(id: "XTRA", data: custom)])

        try await AIFFWriter.write(url: url, changes: TagChanges(title: "AIFF title", artist: "AIFF artist"))

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        XCTAssertEqual(parsed.formType, "AIFF")
        XCTAssertEqual(parsed.chunks.first(where: { $0.id == "SSND" })?.data, sound)
        XCTAssertEqual(parsed.chunks.first(where: { $0.id == "XTRA" })?.data, custom)
        let id3 = try XCTUnwrap(parsed.chunks.first(where: { $0.id == "ID3 " }))
        let frames = ID3FrameCodec.parseTag(id3.data)
        XCTAssertTrue(frames.contains(where: { $0.id == "TIT2" }))
        XCTAssertTrue(frames.contains(where: { $0.id == "TPE1" }))
    }

    func testWriteUpdatesExistingID3ChunkInsteadOfDuplicatingIt() async throws {
        let url = try makeAIFF(sound: Data([1, 2, 3, 4]))
        try await AIFFWriter.write(url: url, changes: TagChanges(title: "First"))
        try await AIFFWriter.write(url: url, changes: TagChanges(title: "Second"))

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        XCTAssertEqual(parsed.chunks.filter { $0.id == "ID3 " }.count, 1)
        let frames = ID3FrameCodec.parseTag(try XCTUnwrap(parsed.chunks.first { $0.id == "ID3 " }).data)
        XCTAssertEqual(frames.filter { $0.id == "TIT2" }.count, 1)
    }

    func testStripRemovesMetadataButKeepsSoundAndTechnicalChunks() async throws {
        let sound = Data([0x11, 0x22, 0x33, 0x44])
        let url = try makeAIFF(sound: sound, extraChunks: [
            AIFFChunk(id: "NAME", data: Data("private name".utf8)),
            AIFFChunk(id: "COMM", data: Data([0, 1, 2, 3]))
        ])
        try await AIFFWriter.write(url: url, changes: TagChanges(title: "Remove me"))

        try await AIFFWriter.strip(url: url)

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        XCTAssertFalse(parsed.chunks.contains { $0.id == "ID3 " })
        XCTAssertFalse(parsed.chunks.contains { $0.id == "NAME" })
        XCTAssertTrue(parsed.chunks.contains { $0.id == "COMM" })
        XCTAssertEqual(parsed.chunks.first(where: { $0.id == "SSND" })?.data, sound)
    }

    func testMalformedAIFFThrowsAndLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("broken.aiff")
        let original = Data("not an AIFF file".utf8)
        try original.write(to: url)

        do {
            try await AIFFWriter.write(url: url, changes: TagChanges(title: "Should fail"))
            XCTFail("Expected malformed AIFF input to throw")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    private func makeAIFF(sound: Data, extraChunks: [AIFFChunk] = []) throws -> URL {
        // Synthetic container fixture for structural tests; SSND payload is
        // byte-controlled and is not intended to be a playable audio sample.
        var chunks = [AIFFChunk(id: "COMM", data: Data([0, 1, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))]
        chunks.append(contentsOf: extraChunks)
        chunks.append(AIFFChunk(id: "SSND", data: sound))
        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).aiff")
        try AIFFChunks.serialize(formType: "AIFF", chunks: chunks).write(to: url)
        return url
    }
}
