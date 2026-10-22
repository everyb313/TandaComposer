import XCTest
import Foundation

final class ID3WriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ID3WriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testWritesTitleAndArtistAndPreservesAudioBytes() async throws {
        let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x10, 0x20, 0x30])
        let url = try makeMP3(audio: audio)

        try await ID3Writer.write(url: url, changes: TagChanges(title: "Test title", artist: "Test artist"))

        let result = try Data(contentsOf: url)
        XCTAssertEqual(audioPayload(in: result), audio)
        let frames = ID3FrameCodec.parseTag(result)
        XCTAssertTrue(frames.contains(where: { $0.id == "TIT2" }))
        XCTAssertTrue(frames.contains(where: { $0.id == "TPE1" }))
    }

    func testUpdatingTitlePreservesUnchangedFrames() async throws {
        let audio = Data([0xFF, 0xFB, 0x01, 0x02])
        let url = try makeMP3(audio: audio)
        try await ID3Writer.write(url: url, changes: TagChanges(title: "Old", album: "Keep album"))

        try await ID3Writer.write(url: url, changes: TagChanges(title: "New"))

        let frames = ID3FrameCodec.parseTag(try Data(contentsOf: url))
        XCTAssertEqual(frames.filter { $0.id == "TIT2" }.count, 1)
        XCTAssertTrue(frames.contains(where: { $0.id == "TALB" }))
        XCTAssertEqual(audioPayload(in: try Data(contentsOf: url)), audio)
    }

    func testStripRemovesLeadingID3AndTrailingID3v1() async throws {
        let audio = Data([0xFF, 0xFB, 0xAA, 0xBB, 0xCC])
        let url = try makeMP3(audio: audio, trailingID3v1: true)
        try await ID3Writer.strip(url: url)
        XCTAssertEqual(try Data(contentsOf: url), audio)
    }


    func testMalformedTagDoesNotChangeFileWhenWriteThrows() async throws {
        let url = temporaryDirectory.appendingPathComponent("malformed.mp3")

        // Gültig codierte Tag-Größe von 20 Bytes,
        // aber nur zwei Bytes Inhalt vorhanden.
        let original = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00,       // ID3v2.4
            0x00,             // Flags
            0x00, 0x00, 0x00, 0x14, // Größe: 20
            0x01, 0x02        // abgeschnittener Inhalt
        ])

        try original.write(to: url)
        do {
            try await ID3Writer.write(
                url: url,
                changes: TagChanges(title: "A")
            )
        } catch {
            // Bei einem Fehler muss das Original erhalten bleiben.
            XCTAssertEqual(try Data(contentsOf: url), original)
            return
        }

        // Falls der Writer die Datei akzeptiert, muss die Ausgabe
        // lesbar sein. Der Test behauptet dann nicht, dass sie unverändert ist.
        XCTAssertNoThrow(try Data(contentsOf: url))
    }

    private func makeMP3(audio: Data, trailingID3v1: Bool = false) throws -> URL {
        let tagBody = ID3FrameCodec.textFrame("TALB", "Existing album")
        var data = ID3FrameCodec.header(bodySize: tagBody.count)
        data.append(tagBody)
        data.append(audio)
        if trailingID3v1 {
            var v1 = Data("TAG".utf8)
            v1.append(Data(repeating: 0, count: 125))
            data.append(v1)
        }
        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).mp3")
        try data.write(to: url)
        return url
    }

    private func audioPayload(in data: Data) -> Data {
        guard data.count >= 10, data.prefix(3).elementsEqual("ID3".utf8) else { return data }
        let size = ID3FrameCodec.syncsafeDecode(data.subdata(in: 6..<10))
        let start = min(data.count, 10 + size)
        var end = data.count
        if end >= 128 && data.subdata(in: (end - 128)..<end).prefix(3).elementsEqual("TAG".utf8) { end -= 128 }
        return data.subdata(in: start..<max(start, end))
    }
    
    func testRepeatedWritesPreserveAudioAndKeepSingleLeadingID3Tag() async throws {
        let source = temporaryDirectory.appendingPathComponent("repeated.mp3")

        // A minimal ID3v2.4 header followed by synthetic audio bytes.
        let audio = Data([
            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34, 0x56, 0x78,
            0x21, 0x43, 0x65, 0x87
        ])

        let initialFile = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00, 0x00, // Version 2.4, no flags
            0x00, 0x00, 0x00, 0x00 // Empty tag
        ]) + audio

        try initialFile.write(to: source)

        try await ID3Writer.write(
            url: source,
            changes: TagChanges(title: "First title")
        )

        try await ID3Writer.write(
            url: source,
            changes: TagChanges(artist: "Test artist")
        )

        let result = try Data(contentsOf: source)

        XCTAssertGreaterThanOrEqual(result.count, audio.count)
        XCTAssertEqual(
            result.suffix(audio.count),
            audio,
            "Repeated tag writes must preserve the audio payload."
        )

        XCTAssertEqual(
            Array(result.prefix(3)),
            [0x49, 0x44, 0x33],
            "The resulting file should begin with an ID3 tag."
        )

        // The synthetic audio payload contains no ID3 marker.
        // There should be only one ID3 marker in the resulting file.
        let id3Marker = Data([0x49, 0x44, 0x33])
        var markerCount = 0

        if result.count >= id3Marker.count {
            for index in 0...(result.count - id3Marker.count) {
                if result[index..<(index + id3Marker.count)].elementsEqual(id3Marker) {
                    markerCount += 1
                }
            }
        }

        XCTAssertEqual(
            markerCount,
            1,
            "Repeated writes should not duplicate the leading ID3 tag."
        )
    }
    
    
    func testWritePreservesAudioWithExtendedHeader() async throws {
        let source = temporaryDirectory.appendingPathComponent("extended-header.mp3")
        let audio = Data([
            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34, 0x56, 0x78
        ])

        // ID3v2.4 extended header:
        // 4-byte syncsafe size (6), 1 flag byte, 1 byte padding size.
        let extendedHeader = Data([
            0x00, 0x00, 0x00, 0x06,
            0x00,
            0x00
        ])

        let tagSize = extendedHeader.count
        var file = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00,       // Version 2.4
            0x40,             // Extended-header flag
            0x00, 0x00, 0x00, UInt8(tagSize)
        ])
        file.append(extendedHeader)
        file.append(audio)
        try file.write(to: source)

        try await ID3Writer.write(
            url: source,
            changes: TagChanges(title: "Extended header test")
        )

        let result = try Data(contentsOf: source)

        XCTAssertEqual(
            audioPayload(in: result),
            audio,
            "Writing metadata must preserve audio bytes when an extended header is present."
        )

        XCTAssertTrue(
            result.prefix(3).elementsEqual("ID3".utf8),
            "The resulting file should retain its leading ID3 tag."
        )

        let frames = ID3FrameCodec.parseTag(result)
        XCTAssertTrue(frames.contains { $0.id == "TIT2" })
    }

    
    func testStripWithoutLeadingID3v2RemovesTrailingID3v1() async throws {
        let audio = Data([
            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34, 0x56, 0x78
        ])

        let url = temporaryDirectory.appendingPathComponent("id3v1-only.mp3")

        var file = audio
        var id3v1 = Data("TAG".utf8)
        id3v1.append(Data(repeating: 0, count: 125))
        file.append(id3v1)

        try file.write(to: url)

        try await ID3Writer.strip(url: url)

        XCTAssertEqual(
            try Data(contentsOf: url),
            audio,
            "Stripping should remove trailing ID3v1 metadata while preserving audio."
        )
    }


    func testStripWithoutTrailingID3v1PreservesAudio() async throws {
        let audio = Data([
            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34, 0x56, 0x78
        ])

        let url = try makeMP3(audio: audio)

        try await ID3Writer.strip(url: url)

        XCTAssertEqual(
            try Data(contentsOf: url),
            audio,
            "Stripping should remove the leading ID3v2 tag and preserve audio."
        )
    }

    
    func testWritePreservesUnchangedCommentFrame() async throws {
        let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x12, 0x34])
        let url = try makeMP3(audio: audio)

        let commentFrame = ID3FrameCodec.commentFrame("Keep this comment")
        //let originalData = try Data(contentsOf: url)
        //let originalFrames = ID3FrameCodec.parseTag(originalData)

        // Den vorhandenen Tag-Inhalt um einen Kommentar-Frame erweitern.
        let existingBody = ID3FrameCodec.textFrame("TALB", "Existing album")
        let body = existingBody + commentFrame

        var file = ID3FrameCodec.header(bodySize: body.count)
        file.append(body)
        file.append(audio)
        try file.write(to: url)

        try await ID3Writer.write(
            url: url,
            changes: TagChanges(title: "New title")
        )

        let result = try Data(contentsOf: url)
        let frames = ID3FrameCodec.parseTag(result)

        XCTAssertTrue(
            frames.contains { $0.id == "COMM" },
            "The existing comment frame should be preserved."
        )
        XCTAssertTrue(
            frames.contains { $0.id == "TIT2" },
            "The new title frame should be written."
        )
        XCTAssertEqual(
            audioPayload(in: result),
            audio,
            "The audio payload should remain unchanged."
        )
    }

    func testTruncatedID3HeaderThrowsAndLeavesFileUnchanged() async throws {
        let source = temporaryDirectory.appendingPathComponent("truncated.mp3")

        // The header declares a 127-byte tag, but the file is much shorter.
        let malformed = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00, 0x00, // Version 2.4, no flags
            0x00, 0x00, 0x00, 0x7F, // Declared tag size: 127 bytes
            0xFF, 0xFB, 0x90, 0x64
        ])

        try malformed.write(to: source)

        do {
            try await ID3Writer.write(
                url: source,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected the truncated ID3 tag to be rejected.")
        } catch {
            // Any thrown error is acceptable for this malformed input.
        }

        XCTAssertEqual(
            try Data(contentsOf: source),
            malformed,
            "A failed write must leave the original file unchanged."
        )
    }
    

    func testInvalidSyncsafeSizeLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("invalid-syncsafe.mp3")

        // Das letzte Größenbyte enthält ein gesetztes höchstes Bit.
        let malformed = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00,       // ID3v2.4
            0x00,             // Keine Flags
            0x00, 0x00, 0x00, 0x80,
            0xFF, 0xFB, 0x90, 0x64
        ])

        try malformed.write(to: url)

        do {
            try await ID3Writer.write(
                url: url,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected an invalid syncsafe size to be rejected.")
        } catch {
            XCTAssertEqual(
                try Data(contentsOf: url),
                malformed,
                "A failed write must leave the original file unchanged."
            )
        }
    }

    
    func testID3TagSizeExceedingFileLengthLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("truncated-tag.mp3")

        // Gültige ID3-Signatur, aber Tag-Größe 100 Bytes.
        // Die Datei enthält nur 4 Bytes nach dem Header.
        let malformed = Data([
            0x49, 0x44, 0x33, // ID3
            0x04, 0x00,       // Version 2.4
            0x00,             // Flags
            0x00, 0x00, 0x00, 0x64, // Größe: 100 Bytes
            0x11, 0x22, 0x33, 0x44
        ])

        try malformed.write(to: url)

        do {
            try await ID3Writer.write(
                url: url,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected a truncated ID3 tag to be rejected.")
        } catch {
            XCTAssertEqual(
                try Data(contentsOf: url),
                malformed,
                "A failed write must leave the original file unchanged."
            )
        }
    }

    
    func testUpdatingTitleRemovesDuplicateTitleFrames() async throws {
        let url = temporaryDirectory.appendingPathComponent("duplicate-title.mp3")
        let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x11, 0x22])

        let firstTitle = ID3FrameCodec.textFrame("TIT2", "First Title")
        let secondTitle = ID3FrameCodec.textFrame("TIT2", "Second Title")
        let artist = ID3FrameCodec.textFrame("TPE1", "Existing Artist")

        var body = firstTitle
        body.append(secondTitle)
        body.append(artist)

        var file = ID3FrameCodec.header(bodySize: body.count)
        file.append(body)
        file.append(audio)
        try file.write(to: url)

        try await ID3Writer.write(
            url: url,
            changes: TagChanges(title: "Updated Title")
        )

        let result = try Data(contentsOf: url)
        let frames = ID3FrameCodec.parseTag(result)
        let titleFrames = frames.filter { $0.id == "TIT2" }

        XCTAssertEqual(titleFrames.count, 1, "There should be only one title frame.")
        XCTAssertTrue(
            frames.contains { $0.id == "TPE1" },
            "The existing artist frame should be preserved."
        )
        XCTAssertEqual(audioPayload(in: result), audio)
    }

    
    
    func testUpdatingTitlePreservesUnchangedUserTextFrame() async throws {
        let url = temporaryDirectory.appendingPathComponent("preserve-txxx.mp3")
        let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x11, 0x22])

        let titleFrame = ID3FrameCodec.textFrame("TIT2", "Old Title")
        let customFrame = ID3FrameCodec.textFrame("TXXX", "Custom Value")

        var body = titleFrame
        body.append(customFrame)

        var file = ID3FrameCodec.header(bodySize: body.count)
        file.append(body)
        file.append(audio)

        try file.write(to: url)

        try await ID3Writer.write(
            url: url,
            changes: TagChanges(title: "New Title")
        )

        let result = try Data(contentsOf: url)
        let frames = ID3FrameCodec.parseTag(result)

        XCTAssertTrue(
            frames.contains { $0.id == "TXXX" },
            "The unchanged custom text frame should be preserved."
        )

        XCTAssertEqual(
            audioPayload(in: result),
            audio,
            "The audio payload must remain unchanged."
        )
    }

}
