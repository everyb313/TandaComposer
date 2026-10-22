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

    
    func testChangingYearDoesNotPreserveLegacyDateFrames() async throws {
        let url = try makeAIFF(sound: Data([0x11, 0x22, 0x33, 0x44]))

        // Zuerst einen normalen Tag schreiben.
        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Date test")
        )

        // Danach das Jahr ändern.
        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(year: "2026")
        )

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        let id3Chunk = try XCTUnwrap(
            parsed.chunks.first(where: { $0.id == "ID3 " })
        )
        let frames = ID3FrameCodec.parseTag(id3Chunk.data)

        XCTAssertTrue(
            frames.contains(where: { $0.id == "TDRC" }),
            "The updated year should be stored in TDRC"
        )
        XCTAssertFalse(
            frames.contains(where: { ["TYER", "TDAT", "TIME"].contains($0.id) }),
            "Legacy date frames must not remain after updating the year"
        )
    }

    
    func testWritePreservesAIFCFormTypeAndSoundData() async throws {
        let sound = Data([0x21, 0x32, 0x43, 0x54])

        let url = temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).aifc")

        let chunks = [
            AIFFChunk(
                id: "COMM",
                data: Data([
                    0, 1, 0, 0, 0, 0, 16, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                ])
            ),
            AIFFChunk(id: "SSND", data: sound)
        ]

        try AIFFChunks.serialize(formType: "AIFC", chunks: chunks)
            .write(to: url)

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "AIFC title")
        )

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))

        XCTAssertEqual(parsed.formType, "AIFC")
        XCTAssertEqual(
            parsed.chunks.first(where: { $0.id == "SSND" })?.data,
            sound
        )
        XCTAssertEqual(
            parsed.chunks.filter { $0.id == "ID3 " }.count,
            1
        )
    }
    
    
    func testWritePreservesUnchangedCustomID3Frames() async throws {
        let url = try makeAIFF(sound: Data([0x11, 0x22, 0x33, 0x44]))

        let customFrame = ID3FrameCodec.textFrame("TXXX", "Custom metadata")
        let originalTag = ID3FrameCodec.header(bodySize: customFrame.count) + customFrame

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        let chunksWithID3 = parsed.chunks + [
            AIFFChunk(id: "ID3 ", data: originalTag)
        ]
        try AIFFChunks.serialize(
            formType: parsed.formType,
            chunks: chunksWithID3
        ).write(to: url)

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Updated AIFF title")
        )

        let result = try AIFFChunks.parse(Data(contentsOf: url))
        let id3Chunk = try XCTUnwrap(result.chunks.first { $0.id == "ID3 " })
        let frames = ID3FrameCodec.parseTag(id3Chunk.data)

        XCTAssertTrue(frames.contains { $0.id == "TXXX" })
        XCTAssertTrue(frames.contains { $0.id == "TIT2" })
        XCTAssertEqual(result.chunks.filter { $0.id == "ID3 " }.count, 1)
    }
    
    
    func testUpdatingTitlePreservesUnchangedID3Frames() async throws {
        let url = try makeAIFF(sound: Data([0x21, 0x43, 0x65, 0x87]))

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Old title", artist: "Keep artist")
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "New title")
        )

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        let id3Chunk = try XCTUnwrap(
            parsed.chunks.first { $0.id == "ID3 " }
        )
        let frames = ID3FrameCodec.parseTag(id3Chunk.data)

        XCTAssertEqual(
            frames.filter { $0.id == "TIT2" }.count,
            1,
            "Updating a title should not create duplicate title frames."
        )

        XCTAssertEqual(
            frames.filter { $0.id == "TPE1" }.count,
            1,
            "The unchanged artist frame should remain exactly once."
        )


        let finalParsed = try AIFFChunks.parse(Data(contentsOf: url))

        XCTAssertEqual(
            finalParsed.chunks.first { $0.id == "SSND" }?.data,
            Data([0x21, 0x43, 0x65, 0x87]),
            "The sound data must remain unchanged."
        )
    }
    
    
    func testRepeatedStripPreservesSoundAndTechnicalChunks() async throws {
        let sound = Data([0x12, 0x34, 0x56, 0x78])
        let technicalData = Data([0x01, 0x02, 0x03])

        let url = try makeAIFF(
            sound: sound,
            extraChunks: [
                AIFFChunk(id: "XTRA", data: technicalData),
                AIFFChunk(id: "NAME", data: Data("Private title".utf8))
            ]
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Remove this")
        )

        try await AIFFWriter.strip(url: url)
        try await AIFFWriter.strip(url: url)

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))

        XCTAssertFalse(
            parsed.chunks.contains { $0.id == "ID3 " },
            "ID3 metadata should remain removed."
        )
        XCTAssertFalse(
            parsed.chunks.contains { $0.id == "NAME" },
            "The NAME metadata chunk should remain removed."
        )
        XCTAssertEqual(
            parsed.chunks.first { $0.id == "XTRA" }?.data,
            technicalData,
            "Unrelated chunks should be preserved."
        )
        XCTAssertEqual(
            parsed.chunks.first { $0.id == "SSND" }?.data,
            sound,
            "Sound data should remain unchanged."
        )
    }

    /*
    func testRepeatedTitleUpdatesPreserveOriginalSoundData() async throws {
        let sound = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let url = try makeAIFF(sound: sound)

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "First")
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Second")
        )

        let fileData = try Data(contentsOf: url)
        let parsed = try AIFFChunks.parse(fileData)

        let soundChunk = try XCTUnwrap(
            parsed.chunks.first { $0.id == "SSND" },
            "The AIFF file must contain an SSND chunk after repeated metadata updates."
        )

        XCTAssertGreaterThanOrEqual(
            soundChunk.data.count,
            8,
            "The SSND chunk must contain the 8-byte offset/block-size header."
        )

        let actualSound = Data(soundChunk.data.dropFirst(8))

        XCTAssertEqual(
            actualSound,
            sound,
            "Repeated metadata updates must preserve the original sound payload."
        )
    }
     */
    
    func testUpdatingTitlePreservesArtistAndAlbumFrames() async throws {
        let url = try makeAIFF(sound: Data([1, 2, 3, 4, 5]))

        defer { try? FileManager.default.removeItem(at: url) }

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(
                title: "Original Title",
                artist: "Existing Artist",
                album: "Existing Album"
            )
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(title: "Updated Title")
        )

        let parsed = try AIFFChunks.parse(Data(contentsOf: url))
        let id3Chunk = try XCTUnwrap(
            parsed.chunks.first { $0.id == "ID3 " }
        )
        let frames = ID3FrameCodec.parseTag(id3Chunk.data)

        XCTAssertEqual(frames.filter { $0.id == "TIT2" }.count, 1)
        XCTAssertEqual(frames.filter { $0.id == "TPE1" }.count, 1)
        XCTAssertEqual(frames.filter { $0.id == "TALB" }.count, 1)

        XCTAssertEqual(
            try XCTUnwrap(frames.first { $0.id == "TIT2" }).content,
            ID3FrameCodec.textFrame("TIT2", "Updated Title").dropFirst(10)
        )
    }

   /*
    func testMultipleMetadataUpdatesPreserveCustomChunk() async throws {
        let url = try makeAIFF(sound: Data([1, 2, 3, 4, 5, 6]))

        defer { try? FileManager.default.removeItem(at: url) }

        let original = try Data(contentsOf: url)
        let originalParsed = try AIFFChunks.parse(original)
        let customChunk = try XCTUnwrap(
            originalParsed.chunks.first { $0.id == "JUNK" }
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(
                title: "Test Title",
                artist: "Test Artist"
            )
        )

        try await AIFFWriter.write(
            url: url,
            changes: TagChanges(
                album: "Test Album",
                year: "2024"
            )
        )

        let updated = try Data(contentsOf: url)
        let updatedParsed = try AIFFChunks.parse(updated)
        let preservedChunk = try XCTUnwrap(
            updatedParsed.chunks.first { $0.id == "JUNK" }
        )

        XCTAssertEqual(
            preservedChunk.data,
            customChunk.data,
            "Unrecognized custom chunks must survive metadata updates."
        )
    }

    */
    
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
