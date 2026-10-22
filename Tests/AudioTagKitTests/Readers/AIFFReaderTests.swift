import XCTest
import Foundation

final class AIFFReaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIFFReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testReadsCanonicalID3FieldsAndFormatSpecificFrames() async throws {
        let url = try makeAIFF(frames: [
            ID3FrameCodec.textFrame("TIT2", "Milonga de prueba"),
            ID3FrameCodec.textFrame("TPE1", "Cuarteto Ejemplo"),
            ID3FrameCodec.textFrame("TALB", "Sesión en vivo"),
            ID3FrameCodec.textFrame("TDRC", "2025")
        ])

        let metadata = try await AIFFReader.read(url: url)
        let common = try XCTUnwrap(metadata["common"] as? [String: Any])
        let formatSpecific = try XCTUnwrap(metadata["formatSpecific"] as? [String: Any])
        let id3 = try XCTUnwrap(formatSpecific["ID3"] as? [String: Any])

        XCTAssertEqual(metadata["format"] as? String, "AIFF")
        XCTAssertEqual(common["title"] as? String, "Milonga de prueba")
        XCTAssertEqual(common["artist"] as? String, "Cuarteto Ejemplo")
        XCTAssertEqual(common["albumName"] as? String, "Sesión en vivo")
        XCTAssertEqual(id3["TIT2"] as? String, "Milonga de prueba")
        XCTAssertEqual(id3["TPE1"] as? String, "Cuarteto Ejemplo")
        XCTAssertEqual(id3["TYER"] as? String, "2025")
    }

    func testReadsAIFCFormType() async throws {
        let url = try makeAIFF(formType: "AIFC", frames: [])

        let metadata = try await AIFFReader.read(url: url)

        XCTAssertEqual(metadata["format"] as? String, "AIFC")
    }

    func testReportsArtworkWhenAPICFrameExists() async throws {
        // Reader only needs the frame ID to report artwork presence.
        let apic = ID3FrameCodec.frame(id: "APIC", content: Data())
        let url = try makeAIFF(frames: [apic])

        let metadata = try await AIFFReader.read(url: url)

        XCTAssertEqual(metadata["hasArtwork"] as? Bool, true)
    }

    func testMissingID3ChunkReturnsStreamInfoWithoutCanonicalTags() async throws {
        let url = try makeAIFF(frames: nil)

        let metadata = try await AIFFReader.read(url: url)

        XCTAssertEqual(metadata["format"] as? String, "AIFF")
        XCTAssertNil(metadata["common"])
        XCTAssertNotNil(metadata["streamInfo"])
    }

    func testMalformedAIFFThrows() async throws {
        let url = temporaryDirectory.appendingPathComponent("broken.aiff")
        try Data("not an AIFF file".utf8).write(to: url)

        do {
            _ = try await AIFFReader.read(url: url)
            XCTFail("Expected malformed AIFF data to throw.")
        } catch {
            // Expected: parser rejects the invalid FORM marker.
        }
    }

    private func makeAIFF(formType: String = "AIFF", frames: [Data]?) throws -> URL {
        let sound = AIFFChunk(id: "SSND", data: Data([0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0x22]))
        let comm = AIFFChunk(id: "COMM", data: Data([
            0, 2,             // channels
            0, 0, 0, 10,      // sample frames
            0, 16,            // sample size
            0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0 // 80-bit extended sample rate
        ]))
        var chunks = [comm]
        if let frames {
            let frameData = frames.reduce(into: Data()) { $0.append($1) }
            chunks.append(AIFFChunk(id: "ID3 ", data: ID3FrameCodec.header(bodySize: frameData.count) + frameData))
        }
        chunks.append(sound)

        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).\(formType == "AIFC" ? "aifc" : "aiff")")
        try AIFFChunks.serialize(formType: formType, chunks: chunks).write(to: url)
        return url
    }
}
