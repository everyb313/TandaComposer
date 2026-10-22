import XCTest
import Foundation

final class FLACWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testWritesTitleAndArtistAndPreservesAudioPayload() async throws {
        let url = try makeFLACFile(audioPayload: Data([0xFF, 0xF8, 0xAA, 0xBB, 0x10, 0x20]))
        let originalAudio = try audioPayload(in: Data(contentsOf: url))

        try await FLACWriter.write(url: url, changes: TagChanges(title: "Test Title", artist: "Test Artist"))

        let writtenData = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(writtenData)
        let commentBlock = try XCTUnwrap(parsed.blocks.first(where: { $0.type == FLACBlocks.vorbisComment }))
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "Test Title")
        XCTAssertEqual(comments["ARTIST"], "Test Artist")
        XCTAssertEqual(try audioPayload(in: writtenData), originalAudio)
    }

    func testUpdatesExistingCommentsAndPreservesUnchangedFields() async throws {
        let url = try makeFLACFile(audioPayload: Data([0x11, 0x22, 0x33]), comments: ["TITLE": "Old title", "ALBUM": "Keep this"])

        try await FLACWriter.write(url: url, changes: TagChanges(title: "New title"))

        let parsed = try FLACBlocks.parse(Data(contentsOf: url))
        let block = try XCTUnwrap(parsed.blocks.first(where: { $0.type == FLACBlocks.vorbisComment }))
        let comments = VorbisCommentCodec.decode(block.data)
        XCTAssertEqual(comments["TITLE"], "New title")
        XCTAssertEqual(comments["ALBUM"], "Keep this")
    }

    func testStripRemovesVorbisCommentsAndPicturesButPreservesAudio() async throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let url = try makeFLACFile(audioPayload: payload, comments: ["TITLE": "Private title"], includePicture: true)

        try await FLACWriter.strip(url: url)

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        XCTAssertFalse(parsed.blocks.contains(where: { $0.type == FLACBlocks.vorbisComment }))
        XCTAssertFalse(parsed.blocks.contains(where: { $0.type == FLACBlocks.picture }))
        XCTAssertEqual(try audioPayload(in: result), payload)
    }

    
    func testRepeatedWritesUpdateTitleAndPreserveArtistAndAudio() async throws {
        let originalAudio = Data([0xFF, 0xF8, 0xAA, 0xBB, 0x10, 0x20])
        let url = try makeFLACFile(audioPayload: originalAudio)

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "First title", artist: "Test Artist")
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "Updated title")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        let commentBlock = try XCTUnwrap(
            parsed.blocks.first(where: { $0.type == FLACBlocks.vorbisComment })
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "Updated title")
        XCTAssertEqual(comments["ARTIST"], "Test Artist")
        XCTAssertEqual(try audioPayload(in: result), originalAudio)
    }

    func testWriteMergesExistingVorbisCommentBlocks() async throws {
        let audio = Data([0x21, 0x43, 0x65])

        let blocks: [FLACBlock] = [
            FLACBlock(
                type: FLACBlocks.streamInfo,
                data: Data(repeating: 0, count: 34)
            ),
            FLACBlock(
                type: FLACBlocks.vorbisComment,
                data: VorbisCommentCodec.encode(["TITLE": "Old title"])
            ),
            FLACBlock(
                type: FLACBlocks.vorbisComment,
                data: VorbisCommentCodec.encode(["ALBUM": "Keep album"])
            )
        ]

        let fileData = FLACBlocks.serialize(blocks: blocks, audioData: audio)
        let url = temporaryDirectory.appendingPathComponent(
            "duplicate-comments-\(UUID().uuidString).flac"
        )
        try fileData.write(to: url)

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "New title")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)

        XCTAssertEqual(
            parsed.blocks.filter { $0.type == FLACBlocks.vorbisComment }.count,
            1,
            "Writing should leave only one Vorbis Comment block."
        )

        let commentBlock = try XCTUnwrap(
            parsed.blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "New title")
        XCTAssertEqual(comments["ALBUM"], "Keep album")
        XCTAssertEqual(try audioPayload(in: result), audio)
    }

    
    func testMalformedFLACThrowsAndLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("broken.flac")
        let original = Data("fLaC\u{00} \u{00}".utf8)
        try original.write(to: url)

        do {
            try await FLACWriter.write(url: url, changes: TagChanges(title: "Should fail"))
            XCTFail("Expected malformed FLAC input to throw")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    
    func testRepeatedWritesKeepSingleVorbisCommentBlock() async throws {
        let url = try makeFLACFile(
            audioPayload: Data([0x12, 0x34, 0x56]),
            comments: ["TITLE": "Original title", "ALBUM": "Keep album"]
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "First update")
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "Second update")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)

        XCTAssertEqual(
            parsed.blocks.filter { $0.type == FLACBlocks.vorbisComment }.count,
            1,
            "Repeated writes should leave exactly one Vorbis Comment block."
        )

        let commentBlock = try XCTUnwrap(
            parsed.blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "Second update")
        XCTAssertEqual(comments["ALBUM"], "Keep album")
        XCTAssertEqual(
            try audioPayload(in: result),
            Data([0x12, 0x34, 0x56])
        )
    }
    
    
    func testStripWithoutMetadataPreservesStreamInfoAndAudio() async throws {
        let audio = Data([0x31, 0x42, 0x53, 0x64])
        let url = try makeFLACFile(audioPayload: audio)

        try await FLACWriter.strip(url: url)

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)

        XCTAssertTrue(
            parsed.blocks.contains { $0.type == FLACBlocks.streamInfo },
            "STREAMINFO must be preserved."
        )

        XCTAssertFalse(
            parsed.blocks.contains { $0.type == FLACBlocks.vorbisComment },
            "No Vorbis Comment block should be present."
        )

        XCTAssertFalse(
            parsed.blocks.contains { $0.type == FLACBlocks.picture },
            "No picture block should be present."
        )

        XCTAssertEqual(
            try audioPayload(in: result),
            audio,
            "Audio data must remain unchanged."
        )
    }

    
    func testRepeatedStripPreservesAudioAndStreamInfo() async throws {
        let audio = Data([0x41, 0x52, 0x63, 0x74])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: ["TITLE": "Private title"],
            includePicture: true
        )

        try await FLACWriter.strip(url: url)

        let afterFirstStrip = try Data(contentsOf: url)

        try await FLACWriter.strip(url: url)

        let afterSecondStrip = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(afterSecondStrip)

        XCTAssertEqual(
            afterSecondStrip,
            afterFirstStrip,
            "Repeated stripping should not change an already stripped FLAC file."
        )

        XCTAssertTrue(
            parsed.blocks.contains { $0.type == FLACBlocks.streamInfo },
            "STREAMINFO must be preserved."
        )

        XCTAssertFalse(
            parsed.blocks.contains { $0.type == FLACBlocks.vorbisComment }
        )

        XCTAssertFalse(
            parsed.blocks.contains { $0.type == FLACBlocks.picture }
        )

        XCTAssertEqual(
            try audioPayload(in: afterSecondStrip),
            audio
        )
    }

    
    func testUpdatingMultipleFieldsPreservesOtherComments() async throws {
        let audio = Data([0x12, 0x34, 0x56, 0x78])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: [
                "TITLE": "Old title",
                "ARTIST": "Old artist",
                "ALBUM": "Keep album",
                "GENRE": "Jazz"
            ]
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(
                title: "New title",
                artist: "New artist"
            )
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        let commentBlock = try XCTUnwrap(
            parsed.blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "New title")
        XCTAssertEqual(comments["ARTIST"], "New artist")
        XCTAssertEqual(comments["ALBUM"], "Keep album")
        XCTAssertEqual(comments["GENRE"], "Jazz")
        XCTAssertEqual(try audioPayload(in: result), audio)

        XCTAssertEqual(
            parsed.blocks.filter { $0.type == FLACBlocks.vorbisComment }.count,
            1,
            "The file should contain exactly one Vorbis Comment block."
        )
    }

    
    func testWritingEmptyTitlePreservesOtherComments() async throws {
        let audio = Data([0x21, 0x43, 0x65, 0x87])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: [
                "TITLE": "Old title",
                "ARTIST": "Keep artist",
                "ALBUM": "Keep album"
            ]
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        let commentBlock = try XCTUnwrap(
            parsed.blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "")
        XCTAssertEqual(comments["ARTIST"], "Keep artist")
        XCTAssertEqual(comments["ALBUM"], "Keep album")
        XCTAssertEqual(try audioPayload(in: result), audio)
    }

    
    func testUpdatingAlbumArtistPreservesExistingAliases() async throws {
        let audio = Data([0x12, 0x34, 0x56, 0x78])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: [
                "ALBUMARTIST": "Old canonical",
                "ALBUM ARTIST": "Old spaced",
                "ALBUM_ARTIST": "Old underscored",
                "TITLE": "Keep title"
            ]
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(albumArtist: "New album artist")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        let commentBlock = try XCTUnwrap(
            parsed.blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["ALBUMARTIST"], "New album artist")
        XCTAssertEqual(comments["ALBUM ARTIST"], "New album artist")
        XCTAssertEqual(comments["ALBUM_ARTIST"], "New album artist")
        XCTAssertEqual(comments["TITLE"], "Keep title")
        XCTAssertEqual(try audioPayload(in: result), audio)
    }

   
 
    func testUpdatingYearSynchronizesExistingDateAliases() async throws {
        let audio = Data([0x11, 0x22, 0x33, 0x44])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: [
                "DATE": "1998",
                "YEAR": "1998",
                "TITLE": "Keep title"
            ]
        )

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(year: "2026")
        )

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        let commentBlock = try XCTUnwrap(
            parsed.blocks.first {
                $0.type == FLACBlocks.vorbisComment
            }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["DATE"], "2026")
        XCTAssertEqual(comments["YEAR"], "2026")
        XCTAssertEqual(comments["TITLE"], "Keep title")
        XCTAssertEqual(try audioPayload(in: result), audio)
    }

    
    
    func testTruncatedFLACMetadataLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("truncated-metadata.flac")

        // FLAC-Signatur, gefolgt von einem Metadaten-Header,
        // der einen unvollständigen STREAMINFO-Block ankündigt.
        let malformed = Data([
            0x66, 0x4C, 0x61, 0x43,
            0x00,             // STREAMINFO, nicht letzter Block
            0x00, 0x00, 0x22, // angekündigte Länge: 34 Bytes
            0x00, 0x01, 0x02, 0x03
        ])

        try malformed.write(to: url)

        do {
            try await FLACWriter.write(
                url: url,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected truncated FLAC metadata to throw.")
        } catch {
            XCTAssertEqual(
                try Data(contentsOf: url),
                malformed,
                "A failed write must leave the original file unchanged."
            )
        }
    }

    
    func testWriteAddsCommentsWhenNoneExistAndPreservesAudio() async throws {
        let audio = Data([0x11, 0x22, 0x33, 0x44, 0x55])
        let url = try makeFLACFile(
            audioPayload: audio,
            comments: nil,
            includePicture: false
        )

        defer { try? FileManager.default.removeItem(at: url) }

        let originalAudio = try audioPayload(in: Data(contentsOf: url))
        XCTAssertEqual(originalAudio, audio)

        try await FLACWriter.write(
            url: url,
            changes: TagChanges(title: "New FLAC Title")
        )

        let result = try Data(contentsOf: url)
        let preservedAudio = try audioPayload(in: result)

        XCTAssertEqual(
            preservedAudio,
            audio,
            "Adding metadata must not change the FLAC audio payload."
        )

        let (blocks, _) = try FLACBlocks.parse(result)

        XCTAssertEqual(
            blocks.filter { $0.type == FLACBlocks.vorbisComment }.count,
            1,
            "Exactly one Vorbis Comment block should exist after writing."
        )

        let commentBlock = try XCTUnwrap(
            blocks.first { $0.type == FLACBlocks.vorbisComment }
        )
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "New FLAC Title")
    }

    
    func testStripRemovesPictureWithoutCommentsAndPreservesAudio() async throws {
        let audio = Data([0x11, 0x22, 0x33, 0x44, 0x55])

        let url = try makeFLACFile(
            audioPayload: audio,
            comments: nil,
            includePicture: true
        )

        defer { try? FileManager.default.removeItem(at: url) }

        try await FLACWriter.strip(url: url)

        let result = try Data(contentsOf: url)
        let preservedAudio = try audioPayload(in: result)
        let (blocks, _) = try FLACBlocks.parse(result)

        XCTAssertEqual(
            preservedAudio,
            audio,
            "Stripping metadata must preserve the audio payload."
        )

        XCTAssertFalse(
            blocks.contains { $0.type == FLACBlocks.picture },
            "The Picture block should be removed."
        )

        XCTAssertFalse(
            blocks.contains { $0.type == FLACBlocks.vorbisComment },
            "No Vorbis Comment block should remain."
        )

        XCTAssertTrue(
            blocks.contains { $0.type == FLACBlocks.streamInfo },
            "The required STREAMINFO block must remain."
        )
    }

    
    // MARK: - Fixture helpers

    private func makeFLACFile(
        audioPayload: Data,
        comments: [String: String]? = nil,
        includePicture: Bool = false
    ) throws -> URL {
        var blocks: [FLACBlock] = [FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34))]
        if let comments {
            blocks.append(FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(comments)))
        }
        if includePicture {
            blocks.append(FLACBlock(type: FLACBlocks.picture, data: Data([0, 0, 0, 0])))
        }
        let data = FLACBlocks.serialize(blocks: blocks, audioData: audioPayload)
        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).flac")
        try data.write(to: url)
        return url
    }

    private func audioPayload(in data: Data) throws -> Data {
        let parsed = try FLACBlocks.parse(data)
        return data.subdata(in: parsed.audioOffset..<data.endIndex)
    }
}
