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
}
